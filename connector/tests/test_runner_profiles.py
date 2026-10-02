from __future__ import annotations

import subprocess

import pytest

from hermes_mobile_connector.client import effective_relay_url, effective_websocket_url
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.state import ConnectorState


def settings(**overrides) -> ConnectorHermesSettings:
    base = dict(
        hermes_command="hermes",
        hermes_workdir=None,
        hermes_provider="deepseek",
        hermes_model="deepseek-flash",
        hermes_toolsets=None,
        hermes_source="tool",
        hermes_history_limit=20,
        hermes_chat_timeout_seconds=900,
    )
    base.update(overrides)
    return ConnectorHermesSettings(**base)


def test_default_profile_has_no_profile_flag_and_no_model_override():
    command = HermesCLIExecutor(settings())._build_command(query="hi", session_id="s1", profile="default")
    assert command == ["hermes", "chat", "-Q", "-q", "hi", "--resume", "s1", "--source", "tool"]


def test_named_profile_is_passed_before_the_subcommand():
    command = HermesCLIExecutor(settings())._build_command(query="hi", profile="coach")
    assert command[:4] == ["hermes", "-p", "coach", "chat"]
    assert "--model" not in command and "--provider" not in command


def test_bad_profile_never_reaches_the_command_line():
    with pytest.raises(ValueError, match="^invalid:"):
        HermesCLIExecutor(settings())._build_command(query="hi", profile="--help")


def test_send_message_passes_profile_and_parses_session(monkeypatch):
    seen = {}

    def fake_run(command, **kwargs):
        seen["command"] = command
        seen["timeout"] = kwargs.get("timeout")
        return subprocess.CompletedProcess(command, 0, stdout="Hello\n\nsession_id: 20261002_x\n", stderr="")

    monkeypatch.setattr("hermes_mobile_connector.hermes_runner.shutil.which", lambda _: "/usr/bin/hermes")
    monkeypatch.setattr("hermes_mobile_connector.hermes_runner.subprocess.run", fake_run)
    result = HermesCLIExecutor(settings()).send_message(latest_user_message="hi", history=[], profile="tutor")

    assert seen["command"][:3] == ["hermes", "-p", "tutor"]
    assert seen["timeout"] == 900
    assert result.text == "Hello"
    assert result.session_id == "20261002_x"


def test_timeout_becomes_a_clear_non_retryable_error(monkeypatch):
    def fake_run(command, **kwargs):
        raise subprocess.TimeoutExpired(command, kwargs["timeout"])

    monkeypatch.setattr("hermes_mobile_connector.hermes_runner.shutil.which", lambda _: "/usr/bin/hermes")
    monkeypatch.setattr("hermes_mobile_connector.hermes_runner.subprocess.run", fake_run)
    with pytest.raises(RuntimeError, match="did not finish within 15 minutes"):
        HermesCLIExecutor(settings()).send_message(latest_user_message="hi", history=[], session_id="s1")


def test_internal_relay_url_overrides_public_urls(monkeypatch):
    state = ConnectorState(
        relay_url="https://example.invalid/v1",
        web_socket_url="wss://example.invalid/v1/hosts/ws",
        user_id="u",
        host_id="h",
        connector_credential="c",
        enrolled_at="2026-10-02T00:00:00Z",
    )
    monkeypatch.delenv("HERMES_MOBILE_RELAY_INTERNAL_URL", raising=False)
    assert effective_relay_url(state) == "https://example.invalid/v1"
    assert effective_websocket_url(state) == "wss://example.invalid/v1/hosts/ws"

    monkeypatch.setenv("HERMES_MOBILE_RELAY_INTERNAL_URL", "http://127.0.0.1:8000/v1/")
    assert effective_relay_url(state) == "http://127.0.0.1:8000/v1"
    assert effective_websocket_url(state) == "ws://127.0.0.1:8000/v1/hosts/ws"
