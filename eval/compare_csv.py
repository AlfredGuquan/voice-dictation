"""Generate Whisper vs SenseVoice side-by-side comparison CSV.

Reads outputs/all.jsonl and produces:
  reports/whisper_vs_sensevoice.csv  (40 rows, 12 columns)
"""
from __future__ import annotations
import csv
import json
from pathlib import Path
import re
from jiwer import cer

ROOT = Path(__file__).parent.resolve()
ALL = ROOT / "outputs" / "all.jsonl"
OUT = ROOT / "reports" / "whisper_vs_sensevoice.csv"

_NOISE = re.compile(r"[\s，。！？、；：\"'()<>\-_/\\|~`@#$%^&*+=,.!?;:\[\]]")


def normalize(s: str) -> str:
    return _NOISE.sub("", s or "").lower() if s else ""


def compute_cer(gt: str, hyp: str) -> float | None:
    gt_n = normalize(gt)
    hyp_n = normalize(hyp)
    if not gt_n:
        return None
    try:
        return cer(gt_n, hyp_n)
    except Exception:
        return None


def main():
    rows = [json.loads(l) for l in ALL.read_text(encoding="utf-8").splitlines() if l.strip()]
    by_id: dict[str, dict] = {}
    for r in rows:
        rid = r["wav_id"]
        by_id.setdefault(rid, {"id": rid, "lang": r.get("lang", ""), "bucket": r.get("bucket", ""), "scene": r.get("scene", ""), "ground_truth": r.get("ground_truth", "")})
        if r["engine"] == "openai_whisper_api":
            by_id[rid]["whisper_text"] = r.get("text", "")
            by_id[rid]["whisper_latency_ms"] = r.get("latency_ms")
        elif r["engine"] == "sensevoice":
            by_id[rid]["sensevoice_text"] = r.get("text", "")
            by_id[rid]["sensevoice_latency_ms"] = r.get("latency_ms")

    out_rows = []
    for rid in sorted(by_id.keys()):
        r = by_id[rid]
        gt = r.get("ground_truth", "")
        w_text = r.get("whisper_text", "")
        s_text = r.get("sensevoice_text", "")
        w_cer = compute_cer(gt, w_text)
        s_cer = compute_cer(gt, s_text)
        delta = (w_cer - s_cer) if (w_cer is not None and s_cer is not None) else None
        winner = "tie"
        if delta is not None:
            if delta > 0.01:
                winner = "sensevoice"
            elif delta < -0.01:
                winner = "whisper"
        out_rows.append({
            "id": rid,
            "bucket": r.get("bucket", ""),
            "lang": r.get("lang", ""),
            "scene": r.get("scene", ""),
            "ground_truth": gt,
            "whisper_text": w_text,
            "sensevoice_text": s_text,
            "whisper_cer_pct": f"{w_cer*100:.2f}" if w_cer is not None else "",
            "sensevoice_cer_pct": f"{s_cer*100:.2f}" if s_cer is not None else "",
            "cer_delta_pp": f"{delta*100:+.2f}" if delta is not None else "",
            "whisper_latency_ms": f"{r.get('whisper_latency_ms'):.0f}" if r.get("whisper_latency_ms") is not None else "",
            "sensevoice_latency_ms": f"{r.get('sensevoice_latency_ms'):.0f}" if r.get("sensevoice_latency_ms") is not None else "",
            "cer_winner": winner,
        })

    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        for r in out_rows:
            w.writerow(r)

    # summary
    wins_w = sum(1 for r in out_rows if r["cer_winner"] == "whisper")
    wins_s = sum(1 for r in out_rows if r["cer_winner"] == "sensevoice")
    ties = sum(1 for r in out_rows if r["cer_winner"] == "tie")
    print(f"wrote {OUT}  ({len(out_rows)} rows)")
    print(f"CER winner: sensevoice={wins_s}  whisper={wins_w}  tie={ties}")


if __name__ == "__main__":
    main()
