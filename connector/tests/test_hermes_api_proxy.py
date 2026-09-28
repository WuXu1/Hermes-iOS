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
)

CONFIG = HermesApiConfig(base_url="http://127.0.0.1:9119", token="secret-token")


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/api/status"),
        ("GET", "/api/sessions"),
        ("GET", "/api/sessions/20260928_154726_fc313e/messages"),
        ("GET", "/api/profiles"),
        ("PUT", "/api/profiles/researcher/soul"),
        ("PUT", "/api/profiles/researcher/description"),
        ("GET", "/api/plugins/kanban/board"),
        ("POST", "/api/plugins/kanban/tasks"),
        ("PATCH", "/api/plugins/kanban/tasks/t_54d94a7a"),
        ("DELETE", "/api/plugins/kanban/tasks/t_54d94a7a"),
        ("POST", "/api/plugins/kanban/tasks/t_54d94a7a/comments"),
        ("GET", "/api/plugins/kanban/tasks/t_54d94a7a/log"),
        ("GET", "/api/plugins/kanban/attachments/12"),
        ("GET", "/api/cron/jobs"),
        ("POST", "/api/cron/jobs"),
        ("POST", "/api/cron/jobs/abc123/trigger"),
        ("GET", "/api/cron/jobs/abc123/runs"),
        ("POST", "/api/cron/blueprints/instantiate"),
        ("GET", "/api/skills/content"),
        ("PUT", "/api/skills/toggle"),
    ],
)
def test_allowlisted_routes_pass(method, path):
    check_route(method, path)


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/api/env"),
        ("GET", "/api/env/reveal"),
        ("POST", "/api/status"),
        ("DELETE", "/api/sessions/abc"),
        ("GET", "/api/plugins/kanban/../../env"),
        ("GET", "/api/sessions/%2e%2e/messages"),
        ("GET", "/api/profiles/../config"),
        ("GET", "api/status"),
        ("GET", "/api/sessions/a/b/messages"),
        ("PUT", "/api/profiles/.hidden/soul"),
    ],
)
def test_other_routes_are_forbidden(method, path):
    with pytest.raises(HermesApiError, match="^forbidden:"):
        check_route(method, path)


def _call(params, config=CONFIG, handler=None):
    transport = httpx.MockTransport(handler) if handler else None
    return asyncio.run(call_hermes_api(params, config=config, transport=transport))


def test_proxy_forwards_token_query_and_body():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["token"] = request.headers.get("X-Hermes-Session-Token")
        seen["url"] = str(request.url)
        seen["body"] = json.loads(request.content) if request.content else None
        return httpx.Response(201, json={"task": {"id": "t_1"}})

    result = _call(
        {"method": "POST", "path": "/api/plugins/kanban/tasks", "query": {"board": "main"}, "body": {"title": "x"}},
        handler=handler,
    )

    assert result == {"status": 201, "json": {"task": {"id": "t_1"}}}
    assert seen["token"] == "secret-token"
    assert seen["url"] == "http://127.0.0.1:9119/api/plugins/kanban/tasks?board=main"
    assert seen["body"] == {"title": "x"}


def test_proxy_passes_through_error_status():
    result = _call(
        {"method": "GET", "path": "/api/plugins/kanban/tasks/t_9"},
        handler=lambda request: httpx.Response(404, json={"detail": "task t_9 not found"}),
    )
    assert result == {"status": 404, "json": {"detail": "task t_9 not found"}}


def test_proxy_base64_encodes_binary():
    result = _call(
        {"method": "GET", "path": "/api/plugins/kanban/attachments/3"},
        handler=lambda request: httpx.Response(200, content=b"# report", headers={"content-type": "text/markdown"}),
    )
    assert result == {"status": 200, "contentType": "text/markdown", "base64": base64.b64encode(b"# report").decode()}


def test_proxy_rejects_oversize_binary():
    with pytest.raises(HermesApiError, match="^too_large:"):
        _call(
            {"method": "GET", "path": "/api/plugins/kanban/attachments/3"},
            handler=lambda request: httpx.Response(
                200, content=b"x" * (2 * 1024 * 1024 + 1), headers={"content-type": "image/png"}
            ),
        )


def test_proxy_without_token_is_unavailable():
    with pytest.raises(HermesApiError, match="^unavailable:"):
        _call({"method": "GET", "path": "/api/status"}, config=HermesApiConfig(base_url=CONFIG.base_url, token=None))


def test_proxy_rejects_forbidden_route_before_any_request():
    def handler(request):
        raise AssertionError("no request should be made")

    with pytest.raises(HermesApiError, match="^forbidden:"):
        _call({"method": "GET", "path": "/api/env/reveal"}, handler=handler)


def test_config_from_env_defaults():
    config = HermesApiConfig.from_env({"HERMES_DASHBOARD_SESSION_TOKEN": "t"})
    assert config == HermesApiConfig(base_url="http://127.0.0.1:9119", token="t")
