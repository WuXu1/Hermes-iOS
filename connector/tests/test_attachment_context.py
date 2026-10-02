from __future__ import annotations

import asyncio
import base64

from hermes_mobile_connector.hermes_api_proxy import HermesApiError
from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.state import ConnectorStateStore


def _attachment(filename: str, mime_type: str, data: bytes = b"bytes") -> dict:
    return {"filename": filename, "mimeType": mime_type, "data": base64.b64encode(data).decode()}


def _context(tmp_path, attachments, transcribe=None, monkeypatch=None, profile="default") -> str:
    connector = HermesMobileConnector(state_store=ConnectorStateStore(state_dir=tmp_path))
    if transcribe is not None:
        monkeypatch.setattr("hermes_mobile_connector.client.transcribe_audio_via_hermes", transcribe)
    return asyncio.run(
        connector._build_cli_attachment_context(job_id="job1", attachments=attachments, profile=profile)  # noqa: SLF001
    )


def test_audio_is_transcribed_into_the_message(tmp_path, monkeypatch):
    calls = []

    async def transcribe(data, mime_type, *, profile, config):
        calls.append((data, mime_type, profile))
        return "Buy oat milk on Friday."

    context = _context(tmp_path, [_attachment("memo.m4a", "audio/x-m4a", b"audio")], transcribe, monkeypatch, "coach")

    assert calls == [(b"audio", "audio/x-m4a", "coach")]
    assert "memo.m4a" in context
    assert "Buy oat milk on Friday." in context


def test_failed_transcription_is_reported(tmp_path, monkeypatch):
    async def transcribe(data, mime_type, *, profile, config):
        raise HermesApiError("unavailable: transcription backend is down")

    context = _context(tmp_path, [_attachment("memo.m4a", "audio/x-m4a")], transcribe, monkeypatch)

    assert "could not be transcribed" in context
    assert "transcription backend is down" in context


def test_documents_point_to_read_file(tmp_path):
    context = _context(tmp_path, [_attachment("report.pdf", "application/pdf")])

    assert "report.pdf" in context
    assert "read_file" in context
    assert (tmp_path / "attachment_staging" / "job1" / "report.pdf").read_bytes() == b"bytes"


def test_images_are_left_to_the_main_model(tmp_path, monkeypatch):
    async def transcribe(data, mime_type, *, profile, config):
        raise AssertionError("images must never be sent for transcription")

    context = _context(tmp_path, [_attachment("photo.jpg", "image/jpeg")], transcribe, monkeypatch)

    assert "vision_analyze" in context
