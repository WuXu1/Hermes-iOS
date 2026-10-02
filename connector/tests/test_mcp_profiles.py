from __future__ import annotations

from pathlib import Path

from ruamel.yaml import YAML

from hermes_mobile_connector import mcp_registration
from hermes_mobile_connector.mcp_registration import register_native_mcp_server, unregister_native_mcp_server


def setup_home(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    monkeypatch.setattr(mcp_registration, "resolve_mcp_command_path", lambda: Path("/opt/x/hermes-mobile-mcp"))
    (tmp_path / "config.yaml").write_text("model:\n  default: deepseek-flash\n", encoding="utf-8")
    for name in ("assistant", "coach", "tutor"):
        home = tmp_path / "profiles" / name
        home.mkdir(parents=True)
        (home / "config.yaml").write_text("mcp_servers:\n  moodle: {enabled: true}\n", encoding="utf-8")


def servers(path: Path) -> dict:
    return YAML(typ="safe").load(path.read_text(encoding="utf-8")).get("mcp_servers") or {}


def test_registers_only_the_named_profiles_and_backs_up(tmp_path, monkeypatch):
    setup_home(tmp_path, monkeypatch)
    register_native_mcp_server(state_dir=tmp_path / "state", profiles=("default", "assistant", "coach"))

    assert "hermes_mobile" in servers(tmp_path / "config.yaml")
    assert "hermes_mobile" in servers(tmp_path / "profiles" / "coach" / "config.yaml")
    assert "moodle" in servers(tmp_path / "profiles" / "coach" / "config.yaml")
    assert "hermes_mobile" not in servers(tmp_path / "profiles" / "tutor" / "config.yaml")
    assert (tmp_path / "profiles" / "coach" / "config.yaml.bak-before-hermes-mobile").exists()


def test_unregister_removes_only_our_entry(tmp_path, monkeypatch):
    setup_home(tmp_path, monkeypatch)
    register_native_mcp_server(state_dir=tmp_path / "state", profiles=("coach",))
    unregister_native_mcp_server(profiles=("coach",))
    assert servers(tmp_path / "profiles" / "coach" / "config.yaml") == {"moodle": {"enabled": True}}
