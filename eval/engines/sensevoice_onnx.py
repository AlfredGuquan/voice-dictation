"""SenseVoice-Small via sherpa-onnx (ONNX + optimized C++ runtime, Apple Silicon)."""
from __future__ import annotations
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

from .base import TranscriptResult, wav_duration_seconds, wav_id, timed, print_result

MODEL_DIR = Path(__file__).resolve().parent.parent / "models" / "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
MODEL_FILE = MODEL_DIR / "model.int8.onnx"
TOKENS_FILE = MODEL_DIR / "tokens.txt"

MODEL = "sherpa-onnx/sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
ENGINE = "sensevoice_onnx"

_recognizer = None


def _get_recognizer():
    global _recognizer
    if _recognizer is None:
        import sherpa_onnx
        _recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=str(MODEL_FILE),
            tokens=str(TOKENS_FILE),
            num_threads=4,
            use_itn=True,
            provider="cpu",
        )
    return _recognizer


def _load_mono_16k(wav_path: str) -> np.ndarray:
    audio, sr = sf.read(wav_path, dtype="float32", always_2d=False)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        # simple linear resample; good enough for ASR preprocessing comparison
        ratio = 16000 / sr
        n_out = int(len(audio) * ratio)
        x = np.linspace(0, len(audio) - 1, n_out).astype(np.float32)
        i = x.astype(np.int64)
        f = x - i
        i_next = np.minimum(i + 1, len(audio) - 1)
        audio = (1 - f) * audio[i] + f * audio[i_next]
        audio = audio.astype(np.float32)
    return audio


def transcribe(wav_path: str | Path, language: str = "auto") -> TranscriptResult:
    rec = _get_recognizer()
    audio_sec = wav_duration_seconds(wav_path)
    audio = _load_mono_16k(str(wav_path))

    def _call():
        stream = rec.create_stream()
        stream.accept_waveform(16000, audio)
        rec.decode_stream(stream)
        return stream.result.text

    text, latency_ms = timed(_call)
    return TranscriptResult(
        engine=ENGINE,
        model=MODEL,
        wav_id=wav_id(wav_path),
        text=(text or "").strip(),
        latency_ms=latency_ms,
        audio_sec=audio_sec,
        rtf=latency_ms / 1000 / audio_sec if audio_sec > 0 else 0,
        raw={"provider": "cpu", "num_threads": 4},
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python -m engines.sensevoice_onnx <wav>", file=sys.stderr)
        sys.exit(1)
    print_result(transcribe(sys.argv[1]))
