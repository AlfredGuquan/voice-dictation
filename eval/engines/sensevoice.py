"""SenseVoice-Small via FunASR (local, Apple Silicon)."""
from __future__ import annotations
import re
import sys
from pathlib import Path

from .base import TranscriptResult, wav_duration_seconds, wav_id, timed, print_result

MODEL = "iic/SenseVoiceSmall"
ENGINE = "sensevoice"

_model = None

_TAG_RE = re.compile(r"<\|[^|]*\|>")


def _get_model():
    global _model
    if _model is None:
        from funasr import AutoModel
        _model = AutoModel(
            model=MODEL,
            trust_remote_code=True,
            disable_update=True,
            device="cpu",
        )
    return _model


def _clean_text(raw: str) -> str:
    return _TAG_RE.sub("", raw or "").strip()


def transcribe(wav_path: str | Path, language: str = "auto") -> TranscriptResult:
    model = _get_model()
    audio_sec = wav_duration_seconds(wav_path)

    def _call():
        return model.generate(
            input=str(wav_path),
            cache={},
            language=language,
            use_itn=True,
            batch_size_s=60,
        )

    res, latency_ms = timed(_call)
    raw_text = res[0]["text"] if res else ""
    return TranscriptResult(
        engine=ENGINE,
        model=MODEL,
        wav_id=wav_id(wav_path),
        text=_clean_text(raw_text),
        latency_ms=latency_ms,
        audio_sec=audio_sec,
        rtf=latency_ms / 1000 / audio_sec if audio_sec > 0 else 0,
        raw={"language_input": language, "funasr_raw": raw_text},
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python -m engines.sensevoice <wav>", file=sys.stderr)
        sys.exit(1)
    print_result(transcribe(sys.argv[1]))
