from __future__ import annotations

from hermes_mobile_connector import cli
from hermes_mobile_connector.audio_transcription import TranscriptionError


def test_transcribe_writes_output_file(tmp_path, monkeypatch):
    audio = tmp_path / "memo.m4a"
    audio.write_bytes(b"audio")
    output = tmp_path / "transcript.txt"
    calls = []

    async def fake(data, mime_type, *, config):
        calls.append((data, mime_type))
        return "Buy oat milk."

    monkeypatch.setattr(cli, "transcribe_audio", fake)

    assert cli.main(["transcribe", str(audio), "--output", str(output)]) == 0
    assert output.read_text() == "Buy oat milk.\n"
    assert calls == [(b"audio", "audio/mp4")]


def test_transcribe_prints_without_output(tmp_path, monkeypatch, capsys):
    audio = tmp_path / "memo.wav"
    audio.write_bytes(b"audio")

    async def fake(data, mime_type, *, config):
        return "Hello."

    monkeypatch.setattr(cli, "transcribe_audio", fake)

    assert cli.main(["transcribe", str(audio)]) == 0
    assert capsys.readouterr().out == "Hello.\n"


def test_transcribe_reports_errors(tmp_path, monkeypatch, capsys):
    audio = tmp_path / "memo.wav"
    audio.write_bytes(b"audio")

    async def fake(data, mime_type, *, config):
        raise TranscriptionError("the free Gemini limit is used up for now; try again later")

    monkeypatch.setattr(cli, "transcribe_audio", fake)

    assert cli.main(["transcribe", str(audio)]) == 1
    assert "free Gemini limit" in capsys.readouterr().err
