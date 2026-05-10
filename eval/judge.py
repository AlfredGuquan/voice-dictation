"""LLM-as-judge over 3 ASR engines' outputs.

Invokes `claude -p` with model claude-opus-4-7. Sends:
  - ground truth per row
  - each engine's transcript per row
  - instructions to evaluate per-row + overall
Does NOT pass CER/WER or latency (deterministic metrics handled separately).

Output: reports/judge.md + reports/judge_input.md (the prompt sent).
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
OUT = ROOT / "outputs"
REP = ROOT / "reports"
REP.mkdir(exist_ok=True)

MODEL = "claude-opus-4-7"


def load_rows() -> list[dict]:
    p = OUT / "all.jsonl"
    if not p.exists():
        raise SystemExit(f"{p} not found. run run_eval.py first.")
    return [json.loads(line) for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]


def build_prompt(rows: list[dict]) -> str:
    by_id: dict[str, dict] = {}
    engines: list[str] = []
    for r in rows:
        e = r["engine"]
        if e not in engines:
            engines.append(e)
        by_id.setdefault(r["wav_id"], {"_meta": r})[e] = r

    ordered_ids = sorted(by_id.keys())

    parts = []
    parts.append("# ASR 引擎对比评判任务\n")
    parts.append("你是一位严谨的 ASR（语音识别）评估员。以下 40 条对照数据中，每条包含：\n")
    parts.append("- **Ground Truth**：用户照稿念读的原文\n")
    parts.append(f"- 三个模型的转写结果：{', '.join(engines)}\n")
    parts.append('\n> 注意：`qwen3_asr_mlx` 因推理延迟过高（单条 RTF 20-100，每条 60-230 秒）只跑了 11/40 就被终止；标记 `(MISSING)` 的行表示该 engine 未产出结果。请基于现有数据做判断，对 Qwen3 的结论请说明是"基于 11 条样本"。\n')
    parts.append("\n## 评判规则\n")
    parts.append("1. **只看文本内容**，不考虑延迟或 CER/WER 等机器指标——那些由别的通道处理\n")
    parts.append("2. 对每一条，指出 **哪个模型转写得最好**，并给出**具体证据**（哪里错了、漏了、幻觉了、标点处理如何）\n")
    parts.append("3. 关注维度：语义保真、专有名词/英文术语准确性、中英混合处理、数字/版本号、标点、幻觉（虚构内容）\n")
    parts.append('4. 区分"小瑕疵"（标点、语气词）和"硬伤"（关键术语错、语义变了、丢字漏段）\n')
    parts.append("5. 最后给出**总体排名**和**推荐**，必须附证据——哪些条/哪类场景决定了你的判断\n")
    parts.append("\n## 输出格式（严格遵守）\n")
    parts.append("```markdown\n")
    parts.append("## Per-row\n")
    parts.append("| ID | Winner | 关键证据（一句话） |\n")
    parts.append('| 001 | sensevoice | Whisper 丢了全部标点；Qwen3 把"，"换成"？" |\n')
    parts.append("... (40 行)\n\n")
    parts.append("## 按场景聚合\n")
    parts.append("（比如：中英混合类、长句类、含犹豫词类哪个赢）\n\n")
    parts.append("## 总体排名\n")
    parts.append("1. [engine] — 理由\n2. ...\n3. ...\n\n")
    parts.append("## 推荐\n")
    parts.append("根据用户的使用场景（voice-dictation 给 coding agent 当输入），推荐哪个、为什么、有什么 trade-off\n")
    parts.append("```\n")
    parts.append("\n## 数据\n\n")

    for wav_id in ordered_ids:
        meta = by_id[wav_id]["_meta"]
        parts.append(f"### {wav_id}  `[{meta.get('bucket','?')} / {meta.get('lang','?')} / {meta.get('scene','?')}]`\n")
        parts.append(f"**Ground Truth**: {meta.get('ground_truth','')}\n")
        for e in engines:
            r = by_id[wav_id].get(e)
            if r is None:
                parts.append(f"- `{e}`: (MISSING)\n")
            elif r.get("error"):
                parts.append(f"- `{e}`: ERROR — {r['error']}\n")
            else:
                parts.append(f"- `{e}`: {r.get('text','')}\n")
        parts.append("\n")

    return "".join(parts)


def main():
    if not shutil.which("claude"):
        sys.exit("claude CLI not found. Install Claude Code CLI or adapt to use another entry point.")
    rows = load_rows()
    prompt = build_prompt(rows)
    input_path = REP / "judge_input.md"
    input_path.write_text(prompt, encoding="utf-8")
    print(f"wrote prompt to {input_path}  ({len(prompt)} chars)")

    out_path = REP / "judge.md"
    print(f"invoking claude -p (model={MODEL})...")
    res = subprocess.run(
        ["claude", "-p", "--model", MODEL],
        input=prompt,
        capture_output=True,
        text=True,
        timeout=600,
    )
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        sys.exit(f"claude -p failed: exit {res.returncode}")
    out_path.write_text(res.stdout, encoding="utf-8")
    print(f"wrote judge output to {out_path}  ({len(res.stdout)} chars)")


if __name__ == "__main__":
    main()
