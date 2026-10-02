from __future__ import annotations

import asyncio
import base64

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.state import ConnectorStateStore


def _rpc(tmp_path, monkeypatch, method, params):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path / "hermes"))
    connector = HermesMobileConnector(state_store=ConnectorStateStore(state_dir=tmp_path / "state"))
    return asyncio.run(
        connector._handle_rpc_request({"requestId": "r1", "method": method, "params": params})  # noqa: SLF001
    )


def test_memory_read_and_write_use_the_profile_home(tmp_path, monkeypatch):
    memories = tmp_path / "hermes" / "profiles" / "coach" / "memories"
    memories.mkdir(parents=True)
    (memories / "MEMORY.md").write_text("coach notes", encoding="utf-8")

    read = _rpc(tmp_path, monkeypatch, "memory.read", {"profile": "coach"})
    assert read["success"] is True
    assert read["result"]["memory"]["content"] == "coach notes"

    write = _rpc(tmp_path, monkeypatch, "memory.write", {"profile": "coach", "kind": "user", "content": "about me"})
    assert write["success"] is True
    assert (memories / "USER.md").read_text(encoding="utf-8") == "about me"


def test_audio_transcribe_with_invalid_base64_fails_cleanly(tmp_path, monkeypatch):
    response = _rpc(tmp_path, monkeypatch, "audio.transcribe", {"profile": "default", "mimeType": "audio/m4a", "data": "!!not base64!!"})
    assert response["success"] is False
    assert response["error"]


def test_audio_transcribe_passes_profile_and_home(tmp_path, monkeypatch):
    calls = []

    async def fake(data, mime_type, *, profile, config, hermes_home):
        calls.append((data, mime_type, profile, hermes_home))
        return "hi"

    monkeypatch.setattr("hermes_mobile_connector.client.transcribe_audio_via_hermes", fake)
    response = _rpc(
        tmp_path, monkeypatch, "audio.transcribe",
        {"profile": "coach", "mimeType": "audio/m4a", "data": base64.b64encode(b"abc").decode()},
    )
    assert response["result"] == {"transcript": "hi"}
    assert calls == [(b"abc", "audio/m4a", "coach", tmp_path / "hermes")]


def test_session_transcript_passes_profile_through(tmp_path, monkeypatch):
    calls = []

    async def fake(session_id, *, profile, config, hermes_home):
        calls.append((session_id, profile, hermes_home))
        return {"sessionId": session_id, "messages": []}

    monkeypatch.setattr("hermes_mobile_connector.client.session_transcript", fake)
    response = _rpc(tmp_path, monkeypatch, "session.transcript", {"profile": "tutor", "sessionId": "s1"})
    assert response["success"] is True
    assert response["result"] == {"sessionId": "s1", "messages": []}
    assert calls == [("s1", "tutor", tmp_path / "hermes")]
