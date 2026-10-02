"""Hermes profiles (one per agent): names, homes and locked skills."""

from __future__ import annotations

import re
from pathlib import Path

from ruamel.yaml import YAML

DEFAULT_PROFILE = "default"
_NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")


def normalize_profile(name: str | None) -> str:
    value = (name or "").strip()
    if not value:
        return DEFAULT_PROFILE
    if not _NAME.match(value):
        raise ValueError(f"invalid: {value!r} is not a profile name")
    return value


def profile_home(hermes_home: Path, profile: str | None) -> Path:
    name = normalize_profile(profile)
    if name == DEFAULT_PROFILE:
        return hermes_home
    home = hermes_home / "profiles" / name
    if not home.is_dir():
        raise ValueError(f"not_found: profile {name!r} does not exist")
    return home


def locked_skills(home: Path) -> frozenset[str]:
    config_path = home / "config.yaml"
    if not config_path.exists():
        return frozenset()
    loaded = YAML(typ="safe").load(config_path.read_text(encoding="utf-8")) or {}
    auto_load = (loaded.get("skills") or {}).get("auto_load") or []
    return frozenset(str(item) for item in auto_load if item)
