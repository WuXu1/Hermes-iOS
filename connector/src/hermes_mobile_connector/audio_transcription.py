"""Transcribe audio attachments with Gemini so the main model only sees text.

The main model (DeepSeek) reads text and images but not audio, so this is the one
job handed to Gemini: the connector sends the audio, puts the transcript into the
user's message, and the main model does the rest.
"""

from __future__ import annotations

import asyncio
import base64
import os
import subprocess
import tempfile
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path

import httpx

DEFAULT_MODEL = "gemini-3.6-flash"
GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
REQUEST_TIMEOUT_SECONDS = 120.0
CONVERT_TIMEOUT_SECONDS = 120
PROMPT = (
    "Transcribe this audio verbatim in its original language. "
    "Output only the transcript, with no commentary."
)

# Formats Gemini accepts as-is; anything else (m4a, caf, webm...) is converted to mp3.
GEMINI_AUDIO_TYPES = {
    "audio/wav": "audio/wav",
    "audio/x-wav": "audio/wav",
    "audio/wave": "audio/wav",
    "audio/mp3": "audio/mp3",
    "audio/mpeg": "audio/mp3",
    "audio/aiff": "audio/aiff",
    "audio/x-aiff": "audio/aiff",
    "audio/aac": "audio/aac",
    "audio/ogg": "audio/ogg",
    "audio/flac": "audio/flac",
    "audio/x-flac": "audio/flac",
}


class TranscriptionError(RuntimeError):
    """Raised when audio can't be transcribed; the message is shown to the agent."""


@dataclass(frozen=True)
class TranscriptionConfig:
    api_key: str | None
    model: str = DEFAULT_MODEL

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "TranscriptionConfig":
        env = os.environ if env is None else env
        return cls(
            api_key=env.get("GEMINI_API_KEY") or None,
            model=env.get("HERMES_TRANSCRIBE_MODEL") or DEFAULT_MODEL,
        )


def convert_to_mp3(data: bytes, mime_type: str) -> bytes:
    """Convert audio to mono mp3 with ffmpeg (temp files: mp4/m4a can't be read from a pipe)."""
    with tempfile.TemporaryDirectory() as tmp:
        source, target = Path(tmp) / "input", Path(tmp) / "output.mp3"
        source.write_bytes(data)
        try:
            subprocess.run(
                ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(source),
                 "-vn", "-ac", "1", "-ar", "16000", "-b:a", "48k", str(target)],
                check=True, capture_output=True, timeout=CONVERT_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise TranscriptionError(f"could not convert {mime_type} audio ({type(exc).__name__})") from exc
        return target.read_bytes()


async def transcribe_audio(
    data: bytes,
    mime_type: str,
    *,
    config: TranscriptionConfig,
    transport: httpx.AsyncBaseTransport | None = None,
    convert: Callable[[bytes, str], bytes] = convert_to_mp3,
) -> str:
    if not config.api_key:
        raise TranscriptionError("no Gemini key is set on the host (GEMINI_API_KEY)")

    gemini_type = GEMINI_AUDIO_TYPES.get(mime_type.lower())
    if gemini_type is None:
        data = await asyncio.to_thread(convert, data, mime_type)
        gemini_type = "audio/mp3"

    body = {
        "contents": [{
            "parts": [
                {"text": PROMPT},
                {"inline_data": {"mime_type": gemini_type, "data": base64.b64encode(data).decode()}},
            ],
        }],
    }
    async with httpx.AsyncClient(transport=transport, timeout=REQUEST_TIMEOUT_SECONDS) as client:
        try:
            response = await client.post(
                f"{GEMINI_BASE_URL}/models/{config.model}:generateContent",
                headers={"x-goog-api-key": config.api_key},
                json=body,
            )
        except httpx.HTTPError as exc:
            raise TranscriptionError(f"could not reach Gemini ({type(exc).__name__})") from exc

    if response.status_code == 429:
        raise TranscriptionError("the free Gemini limit is used up for now; try again later")
    if response.status_code != 200:
        raise TranscriptionError(f"Gemini returned {response.status_code}")

    try:
        parts = response.json()["candidates"][0]["content"]["parts"]
        transcript = "".join(part.get("text", "") for part in parts).strip()
    except (ValueError, KeyError, IndexError, TypeError):
        transcript = ""
    if not transcript:
        raise TranscriptionError("no speech was found in the audio")
    return transcript
