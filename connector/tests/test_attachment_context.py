from __future__ import annotations

import asyncio
import base64

from hermes_mobile_connector.audio_transcription import TranscriptionError
from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.state import ConnectorStateStore


def _attachment(filename: str, mime_type: str, data: bytes = b"bytes") -> dict:
    return {"filename": filename, "mimeType": mime_type, "data": base64.b64encode(data).decode()}


def _context(tmp_path, attachments, transcribe=None) -> str:
    connector = HermesMobileConnector(state_store=ConnectorStateStore(state_dir=tmp_path))
    if transcribe is not None:
        connector.transcribe_audio = transcribe
    return asyncio.run(
        connector._build_cli_attachment_context(job_id="job1", attachments=attachments)  # noqa: SLF001
    )


def test_audio_is_transcribed_into_the_message(tmp_path):
    calls = []

    async def transcribe(data, mime_type):
        calls.append((data, mime_type))
        return "Buy oat milk on Friday."

    context = _context(tmp_path, [_attachment("memo.m4a", "audio/x-m4a", b"audio")], transcribe)

    assert calls == [(b"audio", "audio/x-m4a")]
    assert "memo.m4a" in context
    assert "Buy oat milk on Friday." in context


def test_failed_transcription_is_reported(tmp_path):
    async def transcribe(data, mime_type):
        raise TranscriptionError("the free Gemini limit is used up for now; try again later")

    context = _context(tmp_path, [_attachment("memo.m4a", "audio/x-m4a")], transcribe)

    assert "could not be transcribed" in context
    assert "free Gemini limit" in context


def test_documents_point_to_read_file(tmp_path):
    context = _context(tmp_path, [_attachment("report.pdf", "application/pdf")])

    assert "report.pdf" in context
    assert "read_file" in context
    assert (tmp_path / "attachment_staging" / "job1" / "report.pdf").read_bytes() == b"bytes"


def test_images_are_left_to_the_main_model(tmp_path):
    async def transcribe(data, mime_type):
        raise AssertionError("images must never be sent for transcription")

    context = _context(tmp_path, [_attachment("photo.jpg", "image/jpeg")], transcribe)

    assert "vision_analyze" in context
