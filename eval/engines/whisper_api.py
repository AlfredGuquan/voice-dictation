"""OpenAI Whisper-1 baseline. Mirrors voice-dictation's WhisperService.swift config."""
from __future__ import annotations
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI

from .base import TranscriptResult, wav_duration_seconds, wav_id, timed, print_result

MODEL = "whisper-1"
ENGINE = "openai_whisper_api"


def _load_key() -> str:
    for p in (
        Path("/Users/alfred.gu/Desktop/2-projects/voice-dictation/.env"),
        Path.home() / ".voice-dictation/.env",
    ):
        if p.exists():
            load_dotenv(p)
            break
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY not found in env or .env")
    return key


_client: OpenAI | None = None


def _get_client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(api_key=_load_key())
    return _client


def transcribe(wav_path: str | Path, language: str = "zh") -> TranscriptResult:
    client = _get_client()
    audio_sec = wav_duration_seconds(wav_path)

    def _call():
        with open(wav_path, "rb") as f:
            return client.audio.transcriptions.create(
                model=MODEL,
                file=f,
                language=language,
                response_format="json",
            )

    resp, latency_ms = timed(_call)
    text = getattr(resp, "text", "") or ""
    return TranscriptResult(
        engine=ENGINE,
        model=MODEL,
        wav_id=wav_id(wav_path),
        text=text.strip(),
        latency_ms=latency_ms,
        audio_sec=audio_sec,
        rtf=latency_ms / 1000 / audio_sec if audio_sec > 0 else 0,
        raw={"language": language},
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python -m engines.whisper_api <wav>", file=sys.stderr)
        sys.exit(1)
    print_result(transcribe(sys.argv[1]))
