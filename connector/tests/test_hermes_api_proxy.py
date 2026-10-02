from __future__ import annotations

import asyncio
import base64
import json

import httpx
import pytest

from hermes_mobile_connector.hermes_api_proxy import (
    HermesApiConfig,
    HermesApiError,
    call_hermes_api,
    check_route,
    filter_query,
    prepare_request,
)

CONFIG = HermesApiConfig(base_url="http://127.0.0.1:9119", token="secret-token")


ALLOWED = [
    ("GET", "/api/status"),
    ("GET", "/api/model/info"),
    ("GET", "/api/analytics/usage"),
    ("GET", "/api/profiles"),
    ("GET", "/api/profiles/coach/soul"),
    ("GET", "/api/sessions"),
    ("GET", "/api/sessions/search"),
    ("GET", "/api/sessions/20260928_154726_fc313e"),
    ("GET", "/api/sessions/20260928_154726_fc313e/messages"),
    ("PATCH", "/api/sessions/20260928_154726_fc313e"),
    ("GET", "/api/plugins/kanban/board"),
    ("GET", "/api/plugins/kanban/assignees"),
    ("POST", "/api/plugins/kanban/tasks"),
    ("GET", "/api/plugins/kanban/tasks/t_54d94a7a"),
    ("PATCH", "/api/plugins/kanban/tasks/t_54d94a7a"),
    ("POST", "/api/plugins/kanban/tasks/t_54d94a7a/comments"),
    ("POST", "/api/plugins/kanban/tasks/t_54d94a7a/reassign"),
    ("GET", "/api/plugins/kanban/tasks/t_54d94a7a/log"),
    ("GET", "/api/plugins/kanban/attachments/12"),
    ("POST", "/api/plugins/kanban/links"),
    ("GET", "/api/cron/jobs"),
    ("POST", "/api/cron/jobs"),
    ("GET", "/api/cron/jobs/abc123"),
    ("PUT", "/api/cron/jobs/abc123"),
    ("POST", "/api/cron/jobs/abc123/trigger"),
    ("POST", "/api/cron/jobs/abc123/pause"),
    ("GET", "/api/cron/jobs/abc123/runs"),
    ("GET", "/api/cron/blueprints"),
    ("POST", "/api/cron/blueprints/instantiate"),
    ("GET", "/api/skills"),
    ("GET", "/api/skills/content"),
    ("PUT", "/api/skills/toggle"),
]

REFUSED = [
    ("PUT", "/api/profiles/coach/soul"),
    ("PUT", "/api/profiles/coach/description"),
    ("DELETE", "/api/sessions/abc"),
    ("DELETE", "/api/plugins/kanban/tasks/t_1"),
    ("DELETE", "/api/cron/jobs/abc123"),
    ("POST", "/api/model/set"),
    ("GET", "/api/config/raw"),
    ("POST", "/api/actions/restart-gateway"),
    ("POST", "/api/audio/transcribe"),
    ("GET", "/api/env"),
    ("POST", "/api/status"),
    ("GET", "/api/plugins/kanban/../../env"),
    ("GET", "/api/sessions/%2e%2e/messages"),
    ("GET", "/api/profiles/../config"),
    ("GET", "api/status"),
    ("GET", "/api/sessions/a/b/messages"),
]


@pytest.mark.parametrize(("method", "path"), ALLOWED)
def test_allowlisted_routes_pass(method, path):
    check_route(method, path)


@pytest.mark.parametrize(("method", "path"), REFUSED)
def test_other_routes_are_refused(method, path):
    with pytest.raises(HermesApiError, match="forbidden"):
        check_route(method, path)


def test_filter_query_drops_unknown_keys():
    assert filter_query("/api/sessions", {"profile": "coach", "limit": "50", "full": "1", "evil": "x"}) == {
        "profile": "coach",
        "limit": "50",
    }


def test_prepare_request_validates_profile(tmp_path):
    with pytest.raises(HermesApiError, match="invalid"):
        prepare_request({"method": "GET", "path": "/api/sessions", "query": {"profile": "../x"}}, hermes_home=tmp_path)


def test_prepare_request_pins_profile_into_patch_body(tmp_path):
    (tmp_path / "profiles" / "coach").mkdir(parents=True)
    request = prepare_request(
        {"method": "PATCH", "path": "/api/sessions/s1", "query": {"profile": "coach"}, "body": {"title": "x", "profile": "tutor"}},
        hermes_home=tmp_path,
    )
    assert request["body"] == {"title": "x", "profile": "coach"}


def test_prepare_request_strips_session_flags_other_than_title_and_archived(tmp_path):
    request = prepare_request(
        {"method": "PATCH", "path": "/api/sessions/s1", "body": {"title": "x", "archived": True, "hidden": True}},
        hermes_home=tmp_path,
    )
    assert request["body"] == {"title": "x", "archived": True, "profile": "default"}


def test_locked_skill_cannot_be_disabled(tmp_path):
    (tmp_path / "profiles" / "coach").mkdir(parents=True)
    (tmp_path / "profiles" / "coach" / "config.yaml").write_text("skills:\n  auto_load: [coach]\n", encoding="utf-8")
    with pytest.raises(HermesApiError, match="locked"):
        prepare_request(
            {"method": "PUT", "path": "/api/skills/toggle", "query": {"profile": "coach"}, "body": {"name": "coach", "enabled": False}},
            hermes_home=tmp_path,
        )


def _toggle(tmp_path, name, enabled):
    (tmp_path / "config.yaml").write_text("skills:\n  auto_load: [coach]\n", encoding="utf-8")
    return prepare_request(
        {"method": "PUT", "path": "/api/skills/toggle", "body": {"name": name, "enabled": enabled}},
        hermes_home=tmp_path,
    )


@pytest.mark.parametrize("enabled", ["false", 0, "off", False, None])
def test_locked_skill_refuses_non_true_enabled(tmp_path, enabled):
    with pytest.raises(HermesApiError, match="locked|invalid"):
        _toggle(tmp_path, "coach", enabled)


def test_locked_skill_name_match_is_normalised(tmp_path):
    with pytest.raises(HermesApiError, match="locked"):
        _toggle(tmp_path, "Coach ", False)


def test_enabling_locked_skill_and_disabling_unlocked_pass(tmp_path):
    assert _toggle(tmp_path, "coach", True)["body"] == {"name": "coach", "enabled": True, "profile": "default"}
    assert _toggle(tmp_path, "arxiv", False)["body"]["enabled"] is False


def test_route_with_trailing_newline_is_refused():
    with pytest.raises(HermesApiError, match="forbidden"):
        check_route("GET", "/api/status\n")


def test_non_object_body_is_invalid(tmp_path):
    with pytest.raises(HermesApiError, match="invalid"):
        prepare_request({"method": "PATCH", "path": "/api/sessions/s1", "body": "x"}, hermes_home=tmp_path)


def test_skills_response_marks_locked_skills(tmp_path):
    (tmp_path / "config.yaml").write_text("skills:\n  auto_load: [assistant-roles]\n", encoding="utf-8")

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params.get("profile") == "default"
        return httpx.Response(200, json=[{"name": "assistant-roles", "enabled": True}, {"name": "arxiv", "enabled": True}])

    result = asyncio.run(
        call_hermes_api(
            {"method": "GET", "path": "/api/skills"},
            config=CONFIG,
            hermes_home=tmp_path,
            transport=httpx.MockTransport(handler),
        )
    )
    assert [skill["locked"] for skill in result["json"]] == [True, False]


def _call(params, *, tmp_path, config=CONFIG, handler=None):
    transport = httpx.MockTransport(handler) if handler else None
    return asyncio.run(call_hermes_api(params, config=config, hermes_home=tmp_path, transport=transport))


def test_proxy_forwards_token_query_and_body(tmp_path):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["token"] = request.headers.get("X-Hermes-Session-Token")
        seen["url"] = str(request.url)
        seen["body"] = json.loads(request.content) if request.content else None
        return httpx.Response(201, json={"task": {"id": "t_1"}})

    result = _call(
        {"method": "POST", "path": "/api/plugins/kanban/tasks", "query": {"board": "main"}, "body": {"title": "x"}},
        handler=handler,
        tmp_path=tmp_path,
    )

    assert result == {"status": 201, "json": {"task": {"id": "t_1"}}}
    assert seen["token"] == "secret-token"
    assert seen["url"] == "http://127.0.0.1:9119/api/plugins/kanban/tasks?profile=default"
    assert seen["body"] == {"title": "x"}


def test_proxy_passes_through_error_status(tmp_path):
    result = _call(
        {"method": "GET", "path": "/api/plugins/kanban/tasks/t_9"},
        handler=lambda request: httpx.Response(404, json={"detail": "task t_9 not found"}),
        tmp_path=tmp_path,
    )
    assert result == {"status": 404, "json": {"detail": "task t_9 not found"}}


def test_proxy_base64_encodes_binary(tmp_path):
    result = _call(
        {"method": "GET", "path": "/api/plugins/kanban/attachments/3"},
        handler=lambda request: httpx.Response(200, content=b"# report", headers={"content-type": "text/markdown"}),
        tmp_path=tmp_path,
    )
    assert result == {"status": 200, "contentType": "text/markdown", "base64": base64.b64encode(b"# report").decode()}


def test_proxy_rejects_oversize_binary(tmp_path):
    with pytest.raises(HermesApiError, match="^too_large:"):
        _call(
            {"method": "GET", "path": "/api/plugins/kanban/attachments/3"},
            handler=lambda request: httpx.Response(
                200, content=b"x" * (2 * 1024 * 1024 + 1), headers={"content-type": "image/png"}
            ),
            tmp_path=tmp_path,
        )


def test_proxy_without_token_is_unavailable(tmp_path):
    with pytest.raises(HermesApiError, match="^unavailable:"):
        _call({"method": "GET", "path": "/api/status"}, config=HermesApiConfig(base_url=CONFIG.base_url, token=None), tmp_path=tmp_path)


def test_proxy_rejects_forbidden_route_before_any_request(tmp_path):
    def handler(request):
        raise AssertionError("no request should be made")

    with pytest.raises(HermesApiError, match="^forbidden:"):
        _call({"method": "GET", "path": "/api/env/reveal"}, handler=handler, tmp_path=tmp_path)


def test_config_from_env_defaults():
    config = HermesApiConfig.from_env({"HERMES_DASHBOARD_SESSION_TOKEN": "t"})
    assert config == HermesApiConfig(base_url="http://127.0.0.1:9119", token="t")
