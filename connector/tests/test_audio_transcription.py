from __future__ import annotations

import asyncio
import base64
import json

import httpx
import pytest

from hermes_mobile_connector.audio_transcription import (
    TranscriptionConfig,
    TranscriptionError,
    transcribe_audio,
)

CONFIG = TranscriptionConfig(api_key="gemini-key", model="gemini-test")


def _reply(text: str) -> dict:
    return {"candidates": [{"content": {"parts": [{"text": text}]}}]}


def _call(data=b"RIFFaudio", mime_type="audio/wav", config=CONFIG, handler=None, convert=None):
    transport = httpx.MockTransport(handler) if handler else None
    kwargs = {"config": config, "transport": transport}
    if convert is not None:
        kwargs["convert"] = convert
    return asyncio.run(transcribe_audio(data, mime_type, **kwargs))


def test_sends_audio_inline_and_returns_transcript():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["key"] = request.headers.get("x-goog-api-key")
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_reply("  Buy oat milk on Friday.  "))

    assert _call(handler=handler) == "Buy oat milk on Friday."
    assert seen["url"] == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent"
    assert seen["key"] == "gemini-key"
    inline = seen["body"]["contents"][0]["parts"][1]["inline_data"]
    assert inline == {"mime_type": "audio/wav", "data": base64.b64encode(b"RIFFaudio").decode()}


def test_converts_formats_gemini_cannot_read():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["inline"] = json.loads(request.content)["contents"][0]["parts"][1]["inline_data"]
        return httpx.Response(200, json=_reply("hello"))

    def convert(data: bytes, mime_type: str) -> bytes:
        assert (data, mime_type) == (b"m4a-bytes", "audio/x-m4a")
        return b"mp3-bytes"

    assert _call(b"m4a-bytes", "audio/x-m4a", handler=handler, convert=convert) == "hello"
    assert seen["inline"] == {"mime_type": "audio/mp3", "data": base64.b64encode(b"mp3-bytes").decode()}


def test_native_formats_skip_conversion():
    def convert(data, mime_type):
        raise AssertionError("mp3 should be sent as-is")

    _call(b"mp3", "audio/mpeg", handler=lambda request: httpx.Response(200, json=_reply("ok")), convert=convert)


def test_missing_key_fails_before_any_request():
    def handler(request):
        raise AssertionError("no request should be made")

    with pytest.raises(TranscriptionError, match="GEMINI_API_KEY"):
        _call(config=TranscriptionConfig(api_key=None), handler=handler)


def test_rate_limit_is_explained():
    with pytest.raises(TranscriptionError, match="free Gemini limit"):
        _call(handler=lambda request: httpx.Response(429, json={"error": {"message": "quota"}}))


def test_other_errors_include_status():
    with pytest.raises(TranscriptionError, match="400"):
        _call(handler=lambda request: httpx.Response(400, json={"error": {"message": "bad audio"}}))


def test_empty_transcript_is_an_error():
    with pytest.raises(TranscriptionError, match="no speech"):
        _call(handler=lambda request: httpx.Response(200, json=_reply("   ")))


def test_config_from_env():
    assert TranscriptionConfig.from_env({"GEMINI_API_KEY": "k"}) == TranscriptionConfig(
        api_key="k", model="gemini-3.6-flash"
    )
    assert TranscriptionConfig.from_env({"GEMINI_API_KEY": "k", "HERMES_TRANSCRIBE_MODEL": "m"}).model == "m"
    assert TranscriptionConfig.from_env({}).api_key is None
