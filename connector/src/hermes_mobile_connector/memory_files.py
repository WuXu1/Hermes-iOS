"""Read and write Hermes's built-in memory files for the default profile."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

MEMORY_FILES = {"memory": "MEMORY.md", "user": "USER.md"}
MAX_MEMORY_BYTES = 64 * 1024


def _document(path: Path) -> dict:
    if not path.exists():
        return {"content": "", "updatedAt": None}
    return {"content": path.read_text(encoding="utf-8"), "updatedAt": path.stat().st_mtime}


def read_memory(hermes_home: Path) -> dict:
    memories = hermes_home / "memories"
    return {kind: _document(memories / name) for kind, name in MEMORY_FILES.items()}


def write_memory(hermes_home: Path, kind: str, content: str) -> dict:
    name = MEMORY_FILES.get(kind)
    if name is None:
        raise ValueError(f"invalid: unknown memory kind {kind!r}")
    data = content.encode("utf-8")
    if len(data) > MAX_MEMORY_BYTES:
        raise ValueError(f"too_large: memory is limited to {MAX_MEMORY_BYTES} bytes")

    memories = hermes_home / "memories"
    memories.mkdir(parents=True, exist_ok=True)
    target = memories / name
    fd, temp_name = tempfile.mkstemp(dir=memories, prefix=f".{name}.")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.replace(temp_name, target)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise
    return _document(target)
