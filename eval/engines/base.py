"""Common Engine interface. Each engine module implements transcribe(wav_path)."""
from __future__ import annotations
import json
import time
import wave
import contextlib
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any


@dataclass
class TranscriptResult:
    engine: str
    model: str
    wav_id: str
    text: str
    latency_ms: float
    audio_sec: float
    rtf: float
    raw: Any = None

    def to_dict(self) -> dict:
        d = asdict(self)
        return d


def wav_duration_seconds(wav_path: str | Path) -> float:
    with contextlib.closing(wave.open(str(wav_path))) as w:
        return w.getnframes() / w.getframerate()


def wav_id(wav_path: str | Path) -> str:
    return Path(wav_path).stem


def timed(fn, *args, **kwargs):
    t0 = time.perf_counter()
    out = fn(*args, **kwargs)
    elapsed_ms = (time.perf_counter() - t0) * 1000
    return out, elapsed_ms


def print_result(r: TranscriptResult) -> None:
    print(json.dumps(r.to_dict(), ensure_ascii=False, indent=2))
