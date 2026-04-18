"""Qwen3-ASR-0.6B via MLX (local, Apple Silicon ANE/GPU)."""
from __future__ import annotations
import sys
from pathlib import Path

from .base import TranscriptResult, wav_duration_seconds, wav_id, timed, print_result

MODEL = "Qwen/Qwen3-ASR-0.6B"
ENGINE = "qwen3_asr_mlx"

_model = None
_config = None


def _get_model():
    global _model, _config
    if _model is None:
        import mlx_qwen3_asr
        _model, _config = mlx_qwen3_asr.load_model(MODEL)
    return _model


def transcribe(wav_path: str | Path, language: str | None = None) -> TranscriptResult:
    import mlx_qwen3_asr
    model = _get_model()
    audio_sec = wav_duration_seconds(wav_path)
    audio = mlx_qwen3_asr.load_audio(str(wav_path))

    def _call():
        return mlx_qwen3_asr.transcribe(audio, model=model, language=language)

    res, latency_ms = timed(_call)
    text = getattr(res, "text", "") or ""
    return TranscriptResult(
        engine=ENGINE,
        model=MODEL,
        wav_id=wav_id(wav_path),
        text=text.strip(),
        latency_ms=latency_ms,
        audio_sec=audio_sec,
        rtf=latency_ms / 1000 / audio_sec if audio_sec > 0 else 0,
        raw={"language_input": language},
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python -m engines.qwen3_asr <wav>", file=sys.stderr)
        sys.exit(1)
    print_result(transcribe(sys.argv[1]))
