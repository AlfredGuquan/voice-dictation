"""Run all engines across all recordings, cache per-file JSON, aggregate to all.jsonl.

Usage:
  uv run python run_eval.py                    # all engines, all wavs
  uv run python run_eval.py --engines whisper_api
  uv run python run_eval.py --force            # ignore cache
"""
from __future__ import annotations
import argparse
import json
import sys
import traceback
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
REC_DIR = ROOT / "recorder" / "recordings"
OUT_DIR = ROOT / "outputs"
OUT_DIR.mkdir(exist_ok=True)

ENGINES = {
    "whisper_api": "engines.whisper_api",
    "sensevoice": "engines.sensevoice",
    "qwen3_asr": "engines.qwen3_asr",
    "sensevoice_onnx": "engines.sensevoice_onnx",
}


def load_scripts() -> list[dict]:
    return json.loads((ROOT / "recorder" / "scripts.json").read_text())


def wav_paths() -> list[Path]:
    return sorted(REC_DIR.glob("*.wav"))


def run_engine(engine_key: str, wavs: list[Path], force: bool) -> int:
    module_name = ENGINES[engine_key]
    engine_out = OUT_DIR / engine_key
    engine_out.mkdir(exist_ok=True)

    pending = []
    for w in wavs:
        dst = engine_out / f"{w.stem}.json"
        if not force and dst.exists():
            continue
        pending.append((w, dst))

    if not pending:
        print(f"[{engine_key}] all cached, skipping")
        return 0

    print(f"[{engine_key}] importing module...")
    import importlib
    mod = importlib.import_module(module_name)
    total = len(pending)
    done = 0
    errors = 0
    for i, (w, dst) in enumerate(pending, 1):
        try:
            r = mod.transcribe(str(w))
            dst.write_text(json.dumps(r.to_dict(), ensure_ascii=False, indent=2))
            done += 1
            print(f"  [{engine_key}] {i}/{total}  {w.stem}  {r.latency_ms:.0f}ms  {r.text[:40]}")
        except Exception as e:
            errors += 1
            print(f"  [{engine_key}] {i}/{total}  {w.stem}  ERROR  {e}", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            dst.write_text(json.dumps({"error": str(e), "wav_id": w.stem}, ensure_ascii=False))
    print(f"[{engine_key}] done {done}/{total}  errors={errors}")
    return errors


def aggregate() -> None:
    scripts_by_id = {s["id"]: s for s in load_scripts()}
    out = OUT_DIR / "all.jsonl"
    rows = []
    for engine_key in ENGINES:
        engine_dir = OUT_DIR / engine_key
        if not engine_dir.is_dir():
            continue
        for f in sorted(engine_dir.glob("*.json")):
            try:
                data = json.loads(f.read_text())
            except Exception:
                continue
            wav_id = data.get("wav_id", f.stem)
            script = scripts_by_id.get(wav_id, {})
            rows.append({
                "wav_id": wav_id,
                "engine": data.get("engine", engine_key),
                "model": data.get("model", ""),
                "text": data.get("text", ""),
                "ground_truth": script.get("text", ""),
                "lang": script.get("lang", ""),
                "bucket": script.get("bucket", ""),
                "scene": script.get("scene", ""),
                "latency_ms": data.get("latency_ms"),
                "audio_sec": data.get("audio_sec"),
                "rtf": data.get("rtf"),
                "error": data.get("error"),
            })
    with out.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"aggregated {len(rows)} rows -> {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engines", nargs="*", choices=list(ENGINES), default=None)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    wavs = wav_paths()
    if not wavs:
        print(f"no wavs in {REC_DIR}", file=sys.stderr)
        sys.exit(1)
    engines = args.engines or list(ENGINES)
    print(f"engines={engines}  wavs={len(wavs)}  force={args.force}")

    total_errors = 0
    for e in engines:
        total_errors += run_engine(e, wavs, args.force)
    aggregate()
    print(f"all done. total_errors={total_errors}")


if __name__ == "__main__":
    main()
