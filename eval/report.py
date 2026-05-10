"""Generate eval report from outputs/all.jsonl.

Outputs:
  reports/report.md    human-readable markdown
  reports/by_row.csv   per (engine, wav) row for spreadsheets
  reports/by_engine.csv  aggregate metrics per engine
"""
from __future__ import annotations
import csv
import json
import re
import statistics
from pathlib import Path

from jiwer import cer, wer

ROOT = Path(__file__).parent.resolve()
OUT = ROOT / "outputs"
REP = ROOT / "reports"
REP.mkdir(exist_ok=True)

# Normalization:
#  - Strip all non-alphanumeric punctuation (both ASCII and CJK)
#  - Lowercase Latin
#  - Keep CJK / Latin / digits
_NOISE = re.compile(
    r"[\s，。！？、；：""''「」『』（）《》【】,.!?;:'\"()\[\]<>\-_/\\|~`@#\$%\^&\*\+=]"
)


def normalize(s: str) -> str:
    if not s:
        return ""
    return _NOISE.sub("", s).lower()


def load_rows() -> list[dict]:
    p = OUT / "all.jsonl"
    if not p.exists():
        raise SystemExit(f"{p} not found. run run_eval.py first.")
    rows = []
    with p.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def compute_pair_metrics(gt: str, hyp: str) -> dict:
    gt_n = normalize(gt)
    hyp_n = normalize(hyp)
    if not gt_n:
        return {"cer": None, "wer": None}
    try:
        c = cer(gt_n, hyp_n)
    except Exception:
        c = None
    # WER is character-level on CJK unless we split by space; gt is mixed.
    # For mixed/zh we report CER as primary; WER only meaningful for pure English.
    try:
        w = wer(gt, hyp) if gt and hyp else None
    except Exception:
        w = None
    return {"cer": c, "wer": w}


def per_row(rows: list[dict]) -> list[dict]:
    out = []
    for r in rows:
        if r.get("error"):
            out.append({**r, "cer": None, "wer": None})
            continue
        m = compute_pair_metrics(r.get("ground_truth", ""), r.get("text", ""))
        out.append({**r, **m})
    return out


def by_engine(rows: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = {}
    for r in rows:
        groups.setdefault(r["engine"], []).append(r)
    result = []
    for engine, rs in groups.items():
        cers = [r["cer"] for r in rs if r.get("cer") is not None]
        # exclude first call per engine (warmup effect for local models)
        sorted_by_id = sorted([r for r in rs if r.get("latency_ms") is not None], key=lambda r: r["wav_id"])
        lats_warm = [r["latency_ms"] for r in sorted_by_id[1:]]
        rtfs_warm = [r["rtf"] for r in sorted_by_id[1:] if r.get("rtf") is not None]
        errs = sum(1 for r in rs if r.get("error"))

        result.append({
            "engine": engine,
            "model": rs[0].get("model", ""),
            "n": len(rs),
            "errors": errs,
            "cer_mean": statistics.mean(cers) if cers else None,
            "cer_median": statistics.median(cers) if cers else None,
            "cer_p95": sorted(cers)[int(len(cers) * 0.95)] if len(cers) >= 2 else (cers[0] if cers else None),
            "latency_median_ms": statistics.median(lats_warm) if lats_warm else None,
            "latency_p95_ms": sorted(lats_warm)[int(len(lats_warm) * 0.95)] if len(lats_warm) >= 2 else (lats_warm[0] if lats_warm else None),
            "latency_mean_ms": statistics.mean(lats_warm) if lats_warm else None,
            "rtf_median": statistics.median(rtfs_warm) if rtfs_warm else None,
            "first_call_ms": sorted_by_id[0]["latency_ms"] if sorted_by_id else None,
        })
    return result


def by_bucket(rows: list[dict]) -> list[dict]:
    """CER split by bucket × lang × engine."""
    groups: dict[tuple, list[float]] = {}
    for r in rows:
        if r.get("cer") is None:
            continue
        key = (r["engine"], r.get("bucket", ""), r.get("lang", ""))
        groups.setdefault(key, []).append(r["cer"])
    out = []
    for (engine, bucket, lang), cs in sorted(groups.items()):
        out.append({
            "engine": engine,
            "bucket": bucket,
            "lang": lang,
            "n": len(cs),
            "cer_mean": statistics.mean(cs),
            "cer_median": statistics.median(cs),
        })
    return out


def fmt_pct(x: float | None) -> str:
    return "—" if x is None else f"{x*100:.2f}%"


def fmt_ms(x: float | None) -> str:
    return "—" if x is None else f"{x:.0f}"


def write_md(rows: list[dict], agg: list[dict], bucket_rows: list[dict]) -> Path:
    p = REP / "report.md"
    lines = []
    lines.append("# Voice Dictation ASR Eval Report\n")
    lines.append(f"Dataset: **{len(rows) // max(1, len(agg))} wavs × {len(agg)} engines = {len(rows)} runs**\n")
    lines.append("## Overall (warm-up excluded: first latency per engine dropped)\n")
    lines.append("| Engine | Model | N | Errors | CER mean | CER median | CER p95 | Lat median (ms) | Lat p95 (ms) | RTF median | First-call (ms) |")
    lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for a in sorted(agg, key=lambda x: (x["cer_mean"] is None, x["cer_mean"] or 0)):
        rtf = f"{a['rtf_median']:.2f}" if a["rtf_median"] is not None else "—"
        lines.append(
            f"| {a['engine']} | `{a['model']}` | {a['n']} | {a['errors']} | "
            f"{fmt_pct(a['cer_mean'])} | {fmt_pct(a['cer_median'])} | {fmt_pct(a['cer_p95'])} | "
            f"{fmt_ms(a['latency_median_ms'])} | {fmt_ms(a['latency_p95_ms'])} | "
            f"{rtf} | {fmt_ms(a['first_call_ms'])} |"
        )

    lines.append("\n## By bucket × language\n")
    lines.append("| Engine | Bucket | Lang | N | CER mean | CER median |")
    lines.append("|---|---|---|---:|---:|---:|")
    for b in bucket_rows:
        lines.append(
            f"| {b['engine']} | {b['bucket']} | {b['lang']} | {b['n']} | "
            f"{fmt_pct(b['cer_mean'])} | {fmt_pct(b['cer_median'])} |"
        )

    lines.append("\n## Per-row results\n")
    lines.append("CER is character-level, normalized (punctuation + whitespace stripped, lowercased).\n")
    lines.append("| ID | Bucket | Lang | Ground Truth | Engine | Transcript | CER | Lat (ms) |")
    lines.append("|---|---|---|---|---|---|---:|---:|")
    for r in sorted(rows, key=lambda x: (x["wav_id"], x["engine"])):
        gt = (r.get("ground_truth") or "").replace("|", "\\|")
        tx = (r.get("text") or "").replace("|", "\\|") if not r.get("error") else f"`ERROR: {r['error']}`"
        lines.append(
            f"| {r['wav_id']} | {r.get('bucket','')} | {r.get('lang','')} | {gt} | "
            f"{r['engine']} | {tx} | {fmt_pct(r.get('cer'))} | {fmt_ms(r.get('latency_ms'))} |"
        )

    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def write_csvs(rows: list[dict], agg: list[dict]) -> None:
    with (REP / "by_row.csv").open("w", newline="", encoding="utf-8") as f:
        if rows:
            keys = ["wav_id", "engine", "model", "bucket", "lang", "scene",
                    "ground_truth", "text", "cer", "wer", "latency_ms", "audio_sec", "rtf", "error"]
            wtr = csv.DictWriter(f, fieldnames=keys)
            wtr.writeheader()
            for r in rows:
                wtr.writerow({k: r.get(k) for k in keys})
    with (REP / "by_engine.csv").open("w", newline="", encoding="utf-8") as f:
        if agg:
            keys = list(agg[0].keys())
            wtr = csv.DictWriter(f, fieldnames=keys)
            wtr.writeheader()
            for r in agg:
                wtr.writerow(r)


def main():
    raw = load_rows()
    rows = per_row(raw)
    agg = by_engine(rows)
    bucket_rows = by_bucket(rows)
    md = write_md(rows, agg, bucket_rows)
    write_csvs(rows, agg)
    print(f"wrote {md}")
    print(f"wrote {REP/'by_row.csv'}")
    print(f"wrote {REP/'by_engine.csv'}")
    print("\nEngine summary:")
    for a in sorted(agg, key=lambda x: (x["cer_mean"] is None, x["cer_mean"] or 0)):
        rtf = f"{a['rtf_median']:.2f}" if a["rtf_median"] is not None else "—"
        print(f"  {a['engine']:20s}  CER mean {fmt_pct(a['cer_mean']):8s}  lat median {fmt_ms(a['latency_median_ms']):>6s}ms  rtf {rtf}")


if __name__ == "__main__":
    main()
