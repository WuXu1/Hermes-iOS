from __future__ import annotations

import pytest

from hermes_mobile_connector.memory_files import MAX_MEMORY_BYTES, read_memory, write_memory


def test_read_memory_when_files_missing(tmp_path):
    assert read_memory(tmp_path) == {
        "memory": {"content": "", "updatedAt": None},
        "user": {"content": "", "updatedAt": None},
    }


def test_write_then_read_round_trip(tmp_path):
    saved = write_memory(tmp_path, "user", "Name: Max\nLikes: tennis\n")

    assert saved["content"] == "Name: Max\nLikes: tennis\n"
    assert (tmp_path / "memories" / "USER.md").read_text() == "Name: Max\nLikes: tennis\n"
    loaded = read_memory(tmp_path)["user"]
    assert loaded["content"] == "Name: Max\nLikes: tennis\n"
    assert loaded["updatedAt"] is not None


def test_write_leaves_no_temp_files(tmp_path):
    write_memory(tmp_path, "memory", "note")
    assert sorted(path.name for path in (tmp_path / "memories").iterdir()) == ["MEMORY.md"]


def test_write_rejects_unknown_kind(tmp_path):
    with pytest.raises(ValueError, match="^invalid:"):
        write_memory(tmp_path, "soul", "x")


def test_write_rejects_oversize_content(tmp_path):
    with pytest.raises(ValueError, match="^too_large:"):
        write_memory(tmp_path, "memory", "x" * (MAX_MEMORY_BYTES + 1))
