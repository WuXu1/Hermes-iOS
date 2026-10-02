from __future__ import annotations

import asyncio
import base64
import json

import httpx
import pytest

from hermes_mobile_connector.hermes_api_proxy import (
    HermesApiConfig,
    HermesApiError,
    session_transcript,
    transcribe_audio_via_hermes,
)
from hermes_mobile_connector.memory_files import read_memory, write_memory
from hermes_mobile_connector.profiles import profile_home

CONFIG = HermesApiConfig(base_url="http://127.0.0.1:9119", token="secret-token")


def test_transcription_posts_a_data_url_for_the_profile():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/audio/transcribe"
        assert request.url.params["profile"] == "coach"
        body = json.loads(request.content)
        assert body["mime_type"] == "audio/m4a"
        assert body["data_url"] == "data:audio/m4a;base64," + base64.b64encode(b"abc").decode()
        return httpx.Response(200, json={"ok": True, "transcript": "hello there"})

    text = asyncio.run(
        transcribe_audio_via_hermes(b"abc", "audio/m4a", profile="coach", config=CONFIG, transport=httpx.MockTransport(handler))
    )
    assert text == "hello there"


def test_transcription_rejects_oversized_audio():
    with pytest.raises(HermesApiError, match="too_large"):
        asyncio.run(transcribe_audio_via_hermes(b"x" * (5 * 1024 * 1024 + 1), "audio/m4a", profile="default", config=CONFIG))


def test_transcript_keeps_visible_user_and_assistant_messages(tmp_path):
    (tmp_path / "profiles" / "tutor").mkdir(parents=True)

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/sessions/s1/messages"
        assert request.url.params["profile"] == "tutor"
        return httpx.Response(200, json={
            "session_id": "s1",
            "messages": [
                {"id": 1, "role": "session_meta", "content": "x", "timestamp": 1.0},
                {"id": 2, "role": "user", "content": "quiz me", "timestamp": 2.0},
                {"id": 3, "role": "assistant", "content": "", "tool_calls": [{}], "timestamp": 3.0},
                {"id": 4, "role": "tool", "content": "{...}", "timestamp": 4.0},
                {"id": 5, "role": "assistant", "content": "raw", "display_content": "Question 1", "timestamp": 5.0},
                {"id": 6, "role": "assistant", "content": "summary", "display_kind": "hidden", "timestamp": 6.0},
            ],
        })

    result = asyncio.run(
        session_transcript("s1", profile="tutor", config=CONFIG, hermes_home=tmp_path, transport=httpx.MockTransport(handler))
    )
    assert result == {
        "sessionId": "s1",
        "messages": [
            {"id": "2", "role": "user", "text": "quiz me", "timestamp": 2.0},
            {"id": "5", "role": "assistant", "text": "Question 1", "timestamp": 5.0},
        ],
    }


def test_memory_is_read_from_the_profile_home(tmp_path):
    coach = tmp_path / "profiles" / "coach"
    (coach / "memories").mkdir(parents=True)
    (coach / "memories" / "MEMORY.md").write_text("coach notes", encoding="utf-8")
    assert read_memory(profile_home(tmp_path, "coach"))["memory"]["content"] == "coach notes"
    write_memory(profile_home(tmp_path, "coach"), "user", "about me")
    assert (coach / "memories" / "USER.md").read_text(encoding="utf-8") == "about me"
