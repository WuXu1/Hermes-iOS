# Hermes iOS revamp: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iPhone app native Team, Automations, Library and chat-history
screens, backed by an allowlisted proxy to the Hermes dashboard API, and
restyle the whole app on iOS 26 Liquid Glass.

**Architecture:**
- The connector gains a `hermes.api` RPC, which proxies allowlisted routes to
  the loopback Hermes dashboard, plus `memory.read` and `memory.write` RPCs.
- The relay exposes these under `/v1/hermes/...` and adds endpoints for
  multiple conversations.
- The app adds one `WorkspaceTransport` (live: relay; mock: recorded fixtures),
  a typed `HermesWorkspaceAPI` on top of it, four observable stores, and a
  four-tab shell.

**Tech stack:** Python 3.11+ (connector: httpx and pytest; relay: FastAPI and
pytest), Swift 6.2 with strict concurrency, SwiftUI on iOS 26, and XCTest.

**Spec:** `docs/superpowers/specs/2026-09-28-hermes-ios-revamp-design.md`

## Global constraints

- iOS deployment target 26.0; `SWIFT_STRICT_CONCURRENCY: complete`. All new
  stores and services are `@MainActor`.
- Don't regenerate the Xcode project with XcodeGen: `project.yml` is stale and
  would drop the widget extension's settings. Add files to the existing
  `HermesMobile.xcodeproj` with `scripts/xcode_add_files.py` (Task 6).
- Existing endpoints (`/v1/conversations/current`, `/v1/messages`,
  `/v1/conversations/current/clear`) must behave exactly as before.
- The relay reports an offline host as HTTP 409 with detail `Hermes host is
  offline.` (the existing convention). New endpoints reuse it.
- The connector never proxies a route that isn't in the allowlist.
- Colors come only from `Design` tokens. There are no hex literals in view
  code.
- Commit after each task, on branch `ui-revamp`.

## Commands

- Connector tests: `cd connector && ../.venv-connector/bin/pytest -q` (create
  the venv once with `python3 -m venv .venv-connector && .venv-connector/bin/pip install -e 'connector[dev]'`).
- Relay tests: `cd relay && ../.venv-relay/bin/pytest -q` (create it once with
  `python3 -m venv .venv-relay && .venv-relay/bin/pip install -e 'relay[dev]'`).
- App build: `xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath build/DerivedData build`
- App tests: the same command with `test -only-testing:HermesMobileTests`.
- Known pre-existing failures to ignore: 3 tests in
  `connector/tests/test_sensor_store.py`, which are date-dependent.

---

### Task 1: Connector `hermes.api` proxy

**Files:**
- Create: `connector/src/hermes_mobile_connector/hermes_api_proxy.py`
- Modify: `connector/src/hermes_mobile_connector/client.py` (`_handle_rpc_request`)
- Test: `connector/tests/test_hermes_api_proxy.py`

**Interfaces:**
- Produces: `check_route(method: str, path: str) -> None` (raises `HermesApiError`),
  `HermesApiConfig.from_env(env: Mapping[str, str] | None = None) -> HermesApiConfig`,
  `async call_hermes_api(params: dict, *, config: HermesApiConfig, transport: httpx.AsyncBaseTransport | None = None) -> dict`.
  The result is `{"status": int, "json": Any}` or `{"status": int, "contentType": str, "base64": str}`.
  Errors are `HermesApiError`, whose message starts with `forbidden:`, `unavailable:` or `too_large:`.
- The RPC method name is `hermes.api`, with params `{method, path, query?, body?}`.

- [ ] **Step 1: Write the failing tests**

```python
# connector/tests/test_hermes_api_proxy.py
from __future__ import annotations

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


def _transport(handler):
    return httpx.MockTransport(handler)


async def test_proxy_forwards_token_query_and_body():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["token"] = request.headers.get("X-Hermes-Session-Token")
        seen["url"] = str(request.url)
        seen["body"] = json.loads(request.content) if request.content else None
        return httpx.Response(201, json={"task": {"id": "t_1"}})

    result = await call_hermes_api(
        {"method": "POST", "path": "/api/plugins/kanban/tasks", "query": {"board": "main"}, "body": {"title": "x"}},
        config=CONFIG,
        transport=_transport(handler),
    )

    assert result == {"status": 201, "json": {"task": {"id": "t_1"}}}
    assert seen["token"] == "secret-token"
    assert seen["url"] == "http://127.0.0.1:9119/api/plugins/kanban/tasks?board=main"
    assert seen["body"] == {"title": "x"}


async def test_proxy_passes_through_error_status():
    def handler(request):
        return httpx.Response(404, json={"detail": "task t_9 not found"})

    result = await call_hermes_api(
        {"method": "GET", "path": "/api/plugins/kanban/tasks/t_9"}, config=CONFIG, transport=_transport(handler)
    )
    assert result == {"status": 404, "json": {"detail": "task t_9 not found"}}


async def test_proxy_base64_encodes_binary():
    def handler(request):
        return httpx.Response(200, content=b"# report", headers={"content-type": "text/markdown"})

    result = await call_hermes_api(
        {"method": "GET", "path": "/api/plugins/kanban/attachments/3"}, config=CONFIG, transport=_transport(handler)
    )
    assert result == {"status": 200, "contentType": "text/markdown", "base64": base64.b64encode(b"# report").decode()}


async def test_proxy_rejects_oversize_binary():
    def handler(request):
        return httpx.Response(200, content=b"x" * (2 * 1024 * 1024 + 1), headers={"content-type": "image/png"})

    with pytest.raises(HermesApiError, match="^too_large:"):
        await call_hermes_api(
            {"method": "GET", "path": "/api/plugins/kanban/attachments/3"}, config=CONFIG, transport=_transport(handler)
        )


async def test_proxy_without_token_is_unavailable():
    with pytest.raises(HermesApiError, match="^unavailable:"):
        await call_hermes_api(
            {"method": "GET", "path": "/api/status"}, config=HermesApiConfig(base_url=CONFIG.base_url, token=None)
        )


def test_config_from_env_defaults():
    config = HermesApiConfig.from_env({"HERMES_DASHBOARD_SESSION_TOKEN": "t"})
    assert config == HermesApiConfig(base_url="http://127.0.0.1:9119", token="t")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd connector && ../.venv-connector/bin/pytest -q tests/test_hermes_api_proxy.py`
Expected: an `ImportError` for `hermes_mobile_connector.hermes_api_proxy`.
Also add `asyncio_mode = "auto"` under `[tool.pytest.ini_options]` in
`connector/pyproject.toml` and `pytest-asyncio>=0.24,<1.0` to the dev extras,
unless the existing async tests already use another runner. Check
`connector/tests/test_streaming.py` first and match its convention.

- [ ] **Step 3: Implement**

```python
# connector/src/hermes_mobile_connector/hermes_api_proxy.py
"""Allowlisted proxy from relay RPCs to the loopback Hermes dashboard API."""

from __future__ import annotations

import base64
import os
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

import httpx

DEFAULT_DASHBOARD_URL = "http://127.0.0.1:9119"
MAX_BINARY_BYTES = 2 * 1024 * 1024
REQUEST_TIMEOUT_SECONDS = 25.0

# One path segment: an id, name or slug. It never starts with a dot, so "." and
# ".." can't match, and there are no "%" escapes.
_SEG = r"[A-Za-z0-9_-][A-Za-z0-9._-]*"

_ROUTES: tuple[tuple[frozenset[str], re.Pattern[str]], ...] = tuple(
    (frozenset(methods), re.compile(f"^{pattern}$"))
    for methods, pattern in (
        ({"GET"}, r"/api/status"),
        ({"GET"}, r"/api/model/info"),
        ({"GET"}, r"/api/analytics/usage"),
        ({"GET"}, r"/api/sessions"),
        ({"GET"}, r"/api/sessions/search"),
        ({"GET"}, rf"/api/sessions/{_SEG}"),
        ({"GET"}, rf"/api/sessions/{_SEG}/messages"),
        ({"GET"}, r"/api/profiles"),
        ({"GET", "PUT"}, rf"/api/profiles/{_SEG}/soul"),
        ({"PUT"}, rf"/api/profiles/{_SEG}/description"),
        ({"GET"}, r"/api/plugins/kanban/(board|assignees|stats)"),
        ({"POST"}, r"/api/plugins/kanban/tasks"),
        ({"GET", "PATCH", "DELETE"}, rf"/api/plugins/kanban/tasks/{_SEG}"),
        ({"POST"}, rf"/api/plugins/kanban/tasks/{_SEG}/(comments|reassign)"),
        ({"GET"}, rf"/api/plugins/kanban/tasks/{_SEG}/(log|attachments)"),
        ({"GET"}, rf"/api/plugins/kanban/attachments/{_SEG}"),
        ({"POST"}, r"/api/plugins/kanban/links"),
        ({"GET", "POST"}, r"/api/cron/jobs"),
        ({"GET", "PUT", "DELETE"}, rf"/api/cron/jobs/{_SEG}"),
        ({"POST"}, rf"/api/cron/jobs/{_SEG}/(pause|resume|trigger)"),
        ({"GET"}, rf"/api/cron/jobs/{_SEG}/runs"),
        ({"GET"}, r"/api/cron/blueprints"),
        ({"POST"}, r"/api/cron/blueprints/instantiate"),
        ({"GET"}, r"/api/skills"),
        ({"GET"}, r"/api/skills/content"),
        ({"PUT"}, r"/api/skills/toggle"),
    )
)


class HermesApiError(RuntimeError):
    """Raised for requests the proxy refuses or can't complete."""


@dataclass(frozen=True)
class HermesApiConfig:
    base_url: str
    token: str | None

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "HermesApiConfig":
        source = os.environ if env is None else env
        return cls(
            base_url=(source.get("HERMES_DASHBOARD_URL") or DEFAULT_DASHBOARD_URL).rstrip("/"),
            token=source.get("HERMES_DASHBOARD_SESSION_TOKEN") or None,
        )


def check_route(method: str, path: str) -> None:
    method = (method or "").upper()
    for methods, pattern in _ROUTES:
        if method in methods and pattern.match(path or ""):
            return
    raise HermesApiError(f"forbidden: {method} {path} is not available to the app")


async def call_hermes_api(
    params: dict,
    *,
    config: HermesApiConfig,
    transport: httpx.AsyncBaseTransport | None = None,
) -> dict:
    method = str(params.get("method") or "GET").upper()
    path = str(params.get("path") or "")
    check_route(method, path)
    if not config.token:
        raise HermesApiError("unavailable: the Hermes dashboard API is not configured on this host")

    query = {key: str(value) for key, value in (params.get("query") or {}).items() if value is not None}
    body: Any = params.get("body")
    async with httpx.AsyncClient(
        base_url=config.base_url, transport=transport, timeout=REQUEST_TIMEOUT_SECONDS
    ) as client:
        try:
            response = await client.request(
                method,
                path,
                params=query or None,
                json=body if body is not None else None,
                headers={"X-Hermes-Session-Token": config.token},
            )
        except httpx.HTTPError as error:
            raise HermesApiError(f"unavailable: {error}") from error

    content_type = response.headers.get("content-type", "").split(";")[0].strip()
    if content_type == "application/json" or not response.content:
        return {"status": response.status_code, "json": response.json() if response.content else None}
    if len(response.content) > MAX_BINARY_BYTES:
        raise HermesApiError(f"too_large: response is {len(response.content)} bytes")
    return {
        "status": response.status_code,
        "contentType": content_type or "application/octet-stream",
        "base64": base64.b64encode(response.content).decode("ascii"),
    }
```

In `client.py`:
- Import `from .hermes_api_proxy import HermesApiConfig, call_hermes_api`.
- Add a branch to `_handle_rpc_request` before the final `else`:
  ```python
  elif method == "hermes.api":
      result = await call_hermes_api(params, config=HermesApiConfig.from_env())
  ```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd connector && ../.venv-connector/bin/pytest -q tests/test_hermes_api_proxy.py`
Expected: all tests pass.

- [ ] **Step 5: Commit**: `git commit -m "connector: add allowlisted hermes.api proxy RPC"`

### Task 2: Connector memory RPCs

**Files:**
- Create: `connector/src/hermes_mobile_connector/memory_files.py`
- Modify: `connector/src/hermes_mobile_connector/client.py`
- Test: `connector/tests/test_memory_files.py`

**Interfaces:**
- Produces: `read_memory(hermes_home: Path) -> dict`, which returns
  `{"memory": {"content": str, "updatedAt": float | None}, "user": {...}}`, and
  `write_memory(hermes_home: Path, kind: str, content: str) -> dict`, which
  returns the same shape for one kind. RPC methods are `memory.read` (no
  params) and `memory.write` (`{kind, content}`). Errors are `ValueError`,
  whose messages start with `invalid:` or `too_large:`.

- [ ] **Step 1: Write the failing tests**

```python
# connector/tests/test_memory_files.py
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
    assert read_memory(tmp_path)["user"]["content"] == "Name: Max\nLikes: tennis\n"
    assert read_memory(tmp_path)["user"]["updatedAt"] is not None


def test_write_rejects_unknown_kind(tmp_path):
    with pytest.raises(ValueError, match="^invalid:"):
        write_memory(tmp_path, "soul", "x")


def test_write_rejects_oversize_content(tmp_path):
    with pytest.raises(ValueError, match="^too_large:"):
        write_memory(tmp_path, "memory", "x" * (MAX_MEMORY_BYTES + 1))
```

- [ ] **Step 2: Run to verify they fail**, with an `ImportError`.

- [ ] **Step 3: Implement**

```python
# connector/src/hermes_mobile_connector/memory_files.py
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
```

In `client.py`, import `read_memory` and `write_memory`, plus
`resolve_hermes_home` from `.mcp_registration`, and add these branches:

```python
elif method == "memory.read":
    result = read_memory(resolve_hermes_home())
elif method == "memory.write":
    result = write_memory(resolve_hermes_home(), str(params.get("kind") or ""), str(params.get("content") or ""))
```

- [ ] **Step 4: Run the tests to verify they pass.**
- [ ] **Step 5: Commit**: `git commit -m "connector: add memory.read/memory.write RPCs"`

### Task 3: Relay Hermes proxy and memory endpoints

**Files:**
- Modify: `relay/app/main.py`, to store `app.state.connector_rpc = send_connector_rpc` after it is defined, and add the endpoints.
- Test: `relay/tests/test_hermes_proxy.py`

**Interfaces:**
- Consumes: the RPCs `hermes.api`, `memory.read` and `memory.write` from Tasks 1 and 2.
- Produces:
  - `GET|POST|PUT|PATCH|DELETE /v1/hermes/api/{path:path}`. A 2xx response is
    `success(<Hermes JSON>)` for JSON, or `success({"contentType", "base64"})`
    for binary. A Hermes 4xx or 5xx becomes the same status with
    `{"detail": <Hermes detail or "Hermes returned <status>.">}`.
  - `GET /v1/hermes/memory` returns
    `success({"memory": {...}, "user": {...}})`.
  - `PUT /v1/hermes/memory/{kind}` takes the body `{"content": str}` and
    returns `success({"content", "updatedAt"})`.
  - Error mapping: an RPC `forbidden:` error becomes 403, `unavailable:`
    becomes 503, `too_large:` becomes 413, `invalid:` becomes 400, and any
    other `RuntimeError` becomes 502. An offline host stays 409 (from
    `send_connector_rpc`).

- [ ] **Step 1: Write the failing tests.** Build the client the way
  `relay/tests/test_api.py::build_client` does, and register a device with
  `register_device` to get an access token (copy both helpers). Replace
  `client.app.state.connector_rpc` with an async fake:

```python
# relay/tests/test_hermes_proxy.py
from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def build_client(tmp_path):
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'relay.db'}",
        internal_api_key="test-internal-key",
    )
    return TestClient(create_app(settings))


def access_token(client: TestClient) -> str:
    response = client.post(
        "/v1/device/register",
        json={
            "device": {
                "platform": "ios", "deviceName": "Test iPhone", "appVersion": "1.0.0", "buildNumber": "1",
                "bundleId": "io.hermesmobile.HermesMobile", "installationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "deviceModel": "iPhone17,2", "systemVersion": "26.4",
            },
            "client": {"environment": "development"},
        },
    )
    return response.json()["data"]["session"]["accessToken"]


def install_fake_rpc(client, handler):
    calls = []

    async def fake(user_id, *, method, params=None, timeout_seconds=None):
        calls.append((method, params))
        return handler(method, params)

    client.app.state.connector_rpc = fake
    return calls


def test_proxy_get_passes_path_and_query(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    calls = install_fake_rpc(client, lambda m, p: {"status": 200, "json": {"columns": []}})

    response = client.get("/v1/hermes/api/plugins/kanban/board?board=main", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    assert response.json()["data"] == {"columns": []}
    assert calls == [("hermes.api", {"method": "GET", "path": "/api/plugins/kanban/board", "query": {"board": "main"}, "body": None})]


def test_proxy_post_forwards_json_body(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    calls = install_fake_rpc(client, lambda m, p: {"status": 200, "json": {"task": {"id": "t_1"}}})

    response = client.post(
        "/v1/hermes/api/plugins/kanban/tasks", json={"title": "Research"}, headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 200
    assert calls[0][1]["body"] == {"title": "Research"}


def test_proxy_maps_hermes_errors(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    install_fake_rpc(client, lambda m, p: {"status": 404, "json": {"detail": "task t_9 not found"}})

    response = client.get("/v1/hermes/api/plugins/kanban/tasks/t_9", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 404
    assert response.json()["detail"] == "task t_9 not found"


def test_proxy_maps_forbidden_rpc_error(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)

    def handler(method, params):
        raise RuntimeError("forbidden: GET /api/env is not available to the app")

    install_fake_rpc(client, handler)
    response = client.get("/v1/hermes/api/env", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_proxy_requires_auth(tmp_path):
    client = build_client(tmp_path)
    assert client.get("/v1/hermes/api/status").status_code == 401


def test_memory_read_and_write(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    calls = install_fake_rpc(
        client,
        lambda m, p: {"content": p["content"], "updatedAt": 1.0} if m == "memory.write"
        else {"memory": {"content": "", "updatedAt": None}, "user": {"content": "Max", "updatedAt": 1.0}},
    )

    read = client.get("/v1/hermes/memory", headers={"Authorization": f"Bearer {token}"})
    assert read.json()["data"]["user"]["content"] == "Max"

    write = client.put("/v1/hermes/memory/user", json={"content": "Max\n"}, headers={"Authorization": f"Bearer {token}"})
    assert write.json()["data"] == {"content": "Max\n", "updatedAt": 1.0}
    assert calls[-1] == ("memory.write", {"kind": "user", "content": "Max\n"})
```

Check the access-token path in the register response against
`test_api.py::test_device_register_session_and_refresh`, and adjust
`access_token()` if the key differs. Also confirm that unauthenticated
requests return 401; `get_auth_context` decides this.

- [ ] **Step 2: Run to verify they fail**, with 404s.
- [ ] **Step 3: Implement.** In `create_app`, after `send_connector_rpc` is
  defined, add `app.state.connector_rpc = send_connector_rpc`. Then add:

```python
    RPC_ERROR_STATUS = {"forbidden": 403, "unavailable": 503, "too_large": 413, "invalid": 400}

    async def call_connector(user_id: str, method: str, params: dict, timeout_seconds: float = 30.0) -> dict:
        try:
            return await app.state.connector_rpc(
                user_id, method=method, params=params, timeout_seconds=timeout_seconds
            )
        except HTTPException:
            raise
        except RuntimeError as error:
            message = str(error)
            code = message.split(":", 1)[0]
            raise HTTPException(status_code=RPC_ERROR_STATUS.get(code, 502), detail=message) from error

    @app.api_route("/v1/hermes/api/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    async def hermes_api_proxy(
        path: str,
        request: Request,
        auth: AuthContext = Depends(get_auth_context),
    ) -> JSONResponse:
        raw_body = await request.body()
        result = await call_connector(
            auth.user.id,
            "hermes.api",
            {
                "method": request.method,
                "path": f"/api/{path}",
                "query": dict(request.query_params),
                "body": json.loads(raw_body) if raw_body else None,
            },
        )
        status_code = int(result.get("status") or 502)
        if "base64" in result:
            payload = {"contentType": result.get("contentType"), "base64": result["base64"]}
        else:
            payload = result.get("json")
        if 200 <= status_code < 300:
            return JSONResponse(status_code=status_code, content=jsonable_encoder(success(payload)))
        detail = payload.get("detail") if isinstance(payload, dict) else None
        return JSONResponse(status_code=status_code, content={"detail": detail or f"Hermes returned {status_code}."})

    @app.get("/v1/hermes/memory")
    async def hermes_memory(auth: AuthContext = Depends(get_auth_context)) -> dict:
        return success(await call_connector(auth.user.id, "memory.read", {}))

    class MemoryWriteBody(BaseModel):
        content: str

    @app.put("/v1/hermes/memory/{kind}")
    async def hermes_memory_write(
        kind: str, body: MemoryWriteBody, auth: AuthContext = Depends(get_auth_context)
    ) -> dict:
        return success(await call_connector(auth.user.id, "memory.write", {"kind": kind, "content": body.content}))
```

`success()` is typed `dict` but receives lists (for cron jobs and skills), so
widen its annotation to `Any`. Import `json`, `Request` and `BaseModel` if
they aren't already imported, and define `MemoryWriteBody` at module level if
FastAPI can't resolve a nested class.

- [ ] **Step 4: Run the tests**: `cd relay && ../.venv-relay/bin/pytest -q`.
  The whole relay suite must pass.
- [ ] **Step 5: Commit**: `git commit -m "relay: proxy allowlisted Hermes API and memory to the app"`

### Task 4: Relay multi-conversation endpoints

**Files:**
- Modify: `relay/app/services.py`, `relay/app/main.py`
- Test: `relay/tests/test_conversations.py`

**Interfaces:**
- Produces:
  - `GET /v1/conversations` returns
    `success({"conversations": [{"id","title","preview","lastMessageAt","isCurrent"}]})`,
    newest activity first, non-archived only.
  - `POST /v1/conversations` returns `success({"conversation": <summary>})`
    and makes the new conversation current.
  - `POST /v1/conversations/{id}/activate` returns the same shape.
  - `PATCH /v1/conversations/{id}` takes `{"title": str}` and returns the same
    shape.
  - `DELETE /v1/conversations/{id}` returns `success({"archived": True})`.
  - A foreign or missing id returns 404.
- "Current" is the non-archived conversation with the most recent
  `updated_at`. Activating one bumps its `updated_at`. Creating a conversation
  doesn't archive the previous one (unlike `/clear`, which is unchanged).
- Titles: the relay sets the title from the first user message (60
  characters, whitespace collapsed) while it is still `"Hermes"`, at the point
  where user messages are appended in `services.py`.

- [ ] **Step 1: Read how `get_or_create_current_conversation` picks the
  current conversation in `services.py`.** If it already orders by
  `updated_at`, reuse it; otherwise change it to
  `order_by(Conversation.updated_at.desc())` over non-archived rows. Write
  tests:

```python
# relay/tests/test_conversations.py
# (reuse build_client/access_token from test_hermes_proxy.py by copying them)

def auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_new_conversation_becomes_current_and_lists(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    first = client.get("/v1/conversations/current", headers=auth(token)).json()["data"]["conversation"]["id"]

    created = client.post("/v1/conversations", headers=auth(token)).json()["data"]["conversation"]
    listed = client.get("/v1/conversations", headers=auth(token)).json()["data"]["conversations"]
    current = client.get("/v1/conversations/current", headers=auth(token)).json()["data"]["conversation"]["id"]

    assert current == created["id"]
    assert [c["id"] for c in listed][:2] == [created["id"], first]
    assert [c["isCurrent"] for c in listed][:2] == [True, False]


def test_activate_switches_current(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    first = client.get("/v1/conversations/current", headers=auth(token)).json()["data"]["conversation"]["id"]
    client.post("/v1/conversations", headers=auth(token))

    client.post(f"/v1/conversations/{first}/activate", headers=auth(token))

    assert client.get("/v1/conversations/current", headers=auth(token)).json()["data"]["conversation"]["id"] == first


def test_rename_and_archive(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    created = client.post("/v1/conversations", headers=auth(token)).json()["data"]["conversation"]

    renamed = client.patch(f"/v1/conversations/{created['id']}", json={"title": "Trip plans"}, headers=auth(token))
    assert renamed.json()["data"]["conversation"]["title"] == "Trip plans"

    assert client.delete(f"/v1/conversations/{created['id']}", headers=auth(token)).status_code == 200
    ids = [c["id"] for c in client.get("/v1/conversations", headers=auth(token)).json()["data"]["conversations"]]
    assert created["id"] not in ids


def test_unknown_conversation_is_404(tmp_path):
    client = build_client(tmp_path)
    token = access_token(client)
    assert client.post("/v1/conversations/nope/activate", headers=auth(token)).status_code == 404
```

Also add a title test based on
`test_api.py::test_chat_roundtrip_uses_relay_conversation`. After sending
"Plan a weekend in Lisbon please", the listed title must be `"Plan a weekend
in Lisbon please"`.

- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** the service functions `list_conversations(db,
  user_id)`, `create_conversation(db, user_id)`, `get_user_conversation(db,
  user_id, conversation_id)` (returns `None` for a foreign or missing id),
  `activate_conversation`, `rename_conversation` and `archive_conversation`,
  plus `summarize_conversation(conversation, last_message) -> dict` with a
  `preview` of the last message text (100 characters). Add the endpoints in
  `main.py` next to `/v1/conversations/current`, and set the title where user
  messages are persisted.
- [ ] **Step 4: Run the full relay suite**; it must pass.
- [ ] **Step 5: Commit**: `git commit -m "relay: list, create, switch, rename and archive conversations"`

### Task 5: Deploy the backend and verify it live

- [ ] Push the `ui-revamp` branch. Deploy both services from this checkout (the
  services follow `master`, so use the CLI):
  - `railway up relay --path-as-root --service relay --ci`
  - `railway up --service hermes-host --ci`

  The `hermes-host` dashboard variables are already set.
- [ ] Get a phone-scoped token by registering a throwaway device against the
  relay. Use `POST /v1/device/register` with a new `installationId`, as in the
  tests. A registered, unpaired device has no host, so proxied calls should
  return 409. That confirms routing and auth.
- [ ] Verify the paired flow from the server side. Run `railway ssh -s hermes-host --
  hermes-mobile status` to confirm the connector reconnected, then check that
  the relay logs show `/v1/hermes/api/...` requests succeeding once the app
  calls them (Task 12). Record the results in the task log.
- [ ] Capture fixtures for the app (Task 7) from the live dashboard over
  `railway ssh`: board, profiles, a task detail, the task log, sessions, cron
  jobs (create one paused job named "Fixture job", capture it, then delete it),
  blueprints, skills, a skill's content, memory, model info and usage. Save them
  under `HermesMobileTests/Fixtures/*.json` and
  `HermesMobile/Resources/MockFixtures/*.json`, the same files for both, used by
  the mock transport. Trim long bodies.

### Task 6: Design tokens, role styles, components and the project-file helper

**Files:**
- Create: `scripts/xcode_add_files.py`, which uses the `pbxproj` pip package
  (`pip install pbxproj` in a scratch venv) to add files to a target and
  group: `python scripts/xcode_add_files.py --target HermesMobile path/to/File.swift ...`.
- Modify: `HermesMobile/Core/Design.swift`, adding the semantic `Design.Colors`
  tokens `canvas` `#0B0B0D`, `surface` `#16161A`, `surfaceRaised` `#1E1E23`,
  `hairline` (white at 6%), `textPrimary` `#F5F5F2`, `textSecondary` (70%),
  `textTertiary` (45%), `success` `#34C759`, `warning` `#FFB020` and `danger`
  `#FF5A52`. Existing names become aliases: `background` = `canvas`,
  `foreground` = `textPrimary`, `secondaryForeground` = `textSecondary`,
  `surface` stays, and `divider` = `hairline`.
- Create: `HermesMobile/Core/RoleStyle.swift`
  - `struct RoleStyle { let name: String; let displayName: String; let color: Color; let symbol: String }`
    with `static func forProfile(_ name: String) -> RoleStyle`, using the known
    roles from the spec table. The default profile displays as "Chief of staff".
    Unknown names get a color from an 8-color palette, indexed by a stable
    FNV-1a hash of the name (not `hashValue`, which is randomized per launch).
- Create: `HermesMobile/Components/Revamp/`
  - `CanvasBackground.swift`: the canvas color plus a top radial amber glow at
    12% opacity; `.canvasBackground()` modifier.
  - `RoleAvatar.swift`: a circle in the role color at 18% fill with the
    symbol, sizes `.small` (24), `.medium` (36) and `.large` (56), and an
    optional live dot.
  - `StatusPill.swift`: a capsule label for `KanbanStatus` and cron states.
  - `SectionHeader.swift`: a title, count and optional trailing button.
  - `OfflineBanner.swift`: "Hermes is offline — showing saved data".
  - `ToastCenter.swift`: an `@Observable final class ToastCenter` with
    `show(_ message: String, systemImage: String, action: ToastAction?)`, plus
    `.toastOverlay(center)`, a glass capsule at the bottom that dismisses after
    3 s.
  - `EmptyStateView.swift`: a symbol, title, message and optional button.
- Test: `HermesMobileTests/RoleStyleTests.swift`
  - `test_knownRolesHaveFixedSymbols`: the researcher's symbol is
    `magnifyingglass`, and `default` displays as "Chief of staff".
  - `test_unknownRoleColorIsStableAcrossCalls`.

Steps: write the tests, run them and see them fail, implement, add the files
with the script, build, run the tests until they pass, then commit
`app: add revamp design tokens, role styles and shared components`.

### Task 7: Workspace transport, API and models

**Files:**
- Create: `HermesMobile/Services/Workspace/WorkspaceTransport.swift`

  ```swift
  @MainActor
  protocol WorkspaceTransport {
      func send<Response: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String], body: (any Encodable)?) async throws -> Response
      func sendIgnoringResponse(_ method: HTTPMethod, _ path: String, query: [String: String], body: (any Encodable)?) async throws
  }
  enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }
  enum WorkspaceError: LocalizedError, Equatable { case hostOffline, forbidden(String), server(String) }
  ```
- Create: `LiveWorkspaceTransport.swift`. It wraps `RelayAPIClient` through a
  new generic `request(path:method:query:body:accessToken:)` method that
  supports every HTTP method and query items. It uses the same
  `accessTokenProvider`/`accessTokenRefresher` closures as `LiveHermesClient`
  (retry once on `.unauthorized`). It maps a 409 whose message contains
  "offline" to `.hostOffline` and a 403 to `.forbidden`.
- Create: `MockWorkspaceTransport.swift`. It serves
  `Resources/MockFixtures/<name>.json` keyed by method and path. Mutations
  return `{}` and update an in-memory copy of the board and jobs, so UI tests
  see their effects.
- Modify: `RelayAPIClient.swift`. Add the generic `request`, keep the existing
  `get`/`post` wrappers, and expose the HTTP status in
  `ClientError.requestFailed` through a new case
  `.httpStatus(Int, String)`, used only by `request`.
- Create: `HermesMobile/Services/Workspace/HermesWorkspaceAPI.swift`, a
  `@MainActor struct` with typed methods whose names match the stores:
  `board()`, `profiles()`, `task(id:)`, `taskLog(id:)`,
  `createTask(_: KanbanTaskDraft)` (sends `{title, body, assignee, parents}`),
  `updateTask(id:status:assignee:summary:)`, `comment(taskID:body:)`,
  `reassign(taskID:to:)`, `deleteTask(id:)`, `attachment(id:)`,
  `soul(profile:)`, `updateSoul(profile:content:)`,
  `updateDescription(profile:_:)`, `jobs()`, `blueprints()`,
  `createJob(_: CronJobDraft, profile:)`, `instantiate(blueprint:values:)`,
  `pause(jobID:)`, `resume(jobID:)`, `trigger(jobID:)`, `deleteJob(id:)`,
  `runs(jobID:)`, `memory()`, `saveMemory(_: HermesMemoryKind, content:)`,
  `skills()`, `skillContent(name:)`, `setSkill(name:enabled:)`,
  `modelInfo()`, `usage(days:)`, `conversations()`, `newConversation()`,
  `activateConversation(id:)`, `renameConversation(id:title:)` and
  `archiveConversation(id:)`. Relay paths are `hermes/api/...`,
  `hermes/memory`, `hermes/memory/{kind}` and `conversations...`.
- Create: `HermesMobile/Models/Workspace/` containing `TeamModels.swift`
  (`KanbanTask`, `KanbanStatus`, `KanbanBoard`, `KanbanTaskDetail`, `KanbanEvent`,
  `KanbanComment`, `KanbanAttachment`, `HermesProfile`, `KanbanTaskDraft`),
  `AutomationModels.swift` (`CronJob`, `CronRun`, `CronBlueprint`,
  `CronBlueprintField`, `CronJobDraft`, `CronSchedulePreset`),
  `LibraryModels.swift` (`HermesMemory`, `HermesMemoryDocument`,
  `HermesMemoryKind`, `HermesSkill`), `ConversationModels.swift`
  (`ConversationSummary`), and `StatusModels.swift` (`HermesModelInfo`,
  `HermesUsageSummary`). Every model uses explicit `CodingKeys` for snake_case,
  treats unix timestamps as `Double` with computed `Date` accessors, and
  decodes unknown enum values to `.unknown`. The field lists come from the
  Task 5 fixtures, so decode only the fields the UI uses.
- Test: `HermesMobileTests/WorkspaceDecodingTests.swift`, which decodes every
  fixture, checks one or two key fields each, and checks that
  `KanbanStatus(rawValue:)` falls back to `.unknown` for an unrecognized string
  such as `"parked"`.
- Test: `HermesMobileTests/CronSchedulePresetTests.swift`. For example,
  `.everyMorning(hour: 8, minute: 0)` gives `"0 8 * * *"`, `.hourly` gives
  `"0 * * * *"`, `.weekdays(hour: 9, minute: 30)` gives `"30 9 * * 1-5"`, and
  `.weekly(weekday: 1, hour: 18, minute: 0)` gives `"0 18 * * 1"`.

Steps: write the tests, see them fail, implement, add the files, build and
test, then commit `app: add workspace transport, typed Hermes API and models`.

### Task 8: Stores

**Files:**
- Create: `HermesMobile/Stores/TeamStore.swift`
  - State: `board`, `profiles`, `selectedRole: String?`, `loadState`
    (`.idle`, `.loading`, `.loaded`, `.offline` or `.failed(String)`), and
    `isOffline`.
  - Computed `sections: [TeamSection]`, in this order:
    - `needsYou`: blocked, plus review items where `assignee == nil ||
      assignee == "default"`
    - `working`: running
    - `upNext`: triage, todo, ready or scheduled, sorted by priority
      descending then `createdAt` ascending
    - `review`: the remaining review items
    - `done`: the 20 most recently completed

    All sections are filtered by `selectedRole`, and empty sections are
    dropped.
  - `roleActivity(for profile) -> (isWorking: Bool, activeCount: Int)`.
  - Methods: `refresh()`, `startLivePolling()` (every 10 s while the Team tab
    is visible; cancelled by `stopLivePolling()`), `create(_ draft,
    reviewAfter: Bool)`, which creates a second reviewer task with `parents:
    [first.id]` when `reviewAfter` is set, `reply(to:with:)`, which posts a
    comment and then sets the status to `ready` if the task was `blocked`,
    `reassign`, `markDone`, and `delete`.
- Create: `AutomationsStore.swift`: `jobs`, `blueprints`, `refresh()`,
  `create(draft:profile:)`, `instantiate`, `togglePause(job)`, `runNow`,
  `delete`, and `runs(for:)`.
- Create: `LibraryStore.swift`: `memory`, `skills`, a `skillQuery` with
  computed `skillsByCategory`, `refresh()`, `save(kind:content:)`, and
  `setSkill(_:enabled:)` with an optimistic update that reverts on failure.
- Create: `ConversationsStore.swift`: `conversations`, computed `grouped`
  (Today, This week, Earlier), `refresh()`, `startNew()`, `activate(_:)`,
  `rename`, `archive`. After a switch, it calls
  `chatStore.reloadConversation()`.
- Modify: `ChatStore.swift`, adding a public `reloadConversation()` that
  resets the cached conversation and loads the current one. Reuse
  `loadConversationIfNeeded` with a force flag if it has one.
- Modify: `AppContainer.swift`. Create one live or mock `WorkspaceTransport`
  (mock when `UITEST_PAIRING_MODE == "mock"`), the API, and the four stores
  plus `ToastCenter`, and inject them into the environment in `AppEntry.swift`.
- Test: `HermesMobileTests/TeamStoreTests.swift` against
  `MockWorkspaceTransport`. It covers section grouping and ordering, the role
  filter, `create(reviewAfter: true)` producing a linked reviewer task, and
  `reply` unblocking a blocked task. Also add `ConversationsStoreTests` for
  grouping by date with a fixed `now`.

Steps: TDD per store, then commit `app: add team, automations, library and conversation stores`.

### Task 9: Tab shell

**Files:**
- Modify: `HermesMobile/Core/Router.swift`. `AppTab` becomes `chat`, `team`,
  `automations` and `library`, with titles and SF Symbols (`bubble.left.and.text.bubble.right`,
  `person.3`, `clock.arrow.2.circlepath`, `books.vertical`). Add
  `navigationPath` per tab, and `SheetDestination` cases `.settings`,
  `.history`, `.newTask(prefill: KanbanTaskDraft?)` and `.newAutomation`.
- Modify: `HermesMobile/ContentView.swift` (`MainTabView`). A native `TabView`
  with `Tab(...)` items, each in its own `NavigationStack`. Keep the existing
  voice cover and voice-transcript injection, add `.toastOverlay`, and show
  the Team badge (the `needsYou` count).
- Create: placeholder `TeamScreen`, `AutomationsScreen` and `LibraryScreen` that
  show `EmptyStateView`. Tasks 10 to 13 replace them.
- Verify: build, run in the simulator in mock mode
  (`SIMCTL_CHILD_UITEST_PAIRING_MODE=mock`), switch between tabs, and take a
  screenshot of each.
- Commit `app: four-tab Liquid Glass shell`.

### Task 10: Team screens

**Files:** `HermesMobile/Features/Team/`
- `TeamScreen.swift`: a large title "Team", the role strip
  (`RoleStripView.swift`, a horizontal scroll of `RoleAvatar(.large)` with
  names, a live dot and a count badge; tapping toggles the filter and a long
  press opens `RoleSheet`), sections from `TeamStore.sections` as
  `SectionHeader` plus `TaskCardView` rows, pull to refresh, the offline
  banner, a toolbar "+" that opens `NewTaskSheet`, and an empty state that
  explains the team with a "Give the team a task" button.
- `TaskCardView.swift`: a raised surface with a hairline border; row 1 is the
  avatar, title (2 lines) and status pill; row 2 is the role display name,
  relative age and the first line of `latestSummary` or
  `lastFailureError`. Running cards get a shimmer.
- `TaskDetailScreen.swift`: a header with the title, role and status; a
  "Result" card rendering `latestSummary` or `result` with the existing
  `MarkdownContentView`; a "Brief" card with the body, collapsed after 6
  lines; an "Activity" timeline of events and comments; an "Attachments" list
  (text and markdown are decoded from base64 into a sheet using
  `MarkdownContentView`, images are previewed); and a "Worker log" row that
  pushes a monospaced log view. The bottom action bar changes with status:
  blocked shows Reply and unblock; review shows Approve (PATCH `status: done`) and
  Request changes (a comment with the reviewer's notes, then PATCH `status: ready`, which re-queues it for
  the assignee); every
  status offers a menu with Reassign, Mark done and Delete (confirmed).
- `NewTaskSheet.swift`: a title field, details editor, role picker (a grid of
  avatars with descriptions from `profiles`) and a "Have the reviewer check it"
  toggle, then Create. Afterwards it shows the toast "Assigned to Researcher"
  with a View action.
- `RoleSheet.swift`: the avatar, description (editable), model, counts, and a
  "Persona" row that pushes `PersonaEditorScreen` (a monospaced `TextEditor`
  with Save that calls `updateSoul`).
- Verify in the simulator (mock mode): screenshot the Team list, a task detail
  and the new-task sheet, and fix any layout issues.
- Commit `app: team board, task detail and role management`.

### Task 11: Chat restyle and history

**Files:**
- Modify: `ChatScreen.swift`. Use `.canvasBackground()`. The toolbar has the
  avatar button (opens Settings) on the leading side, a title button (the
  conversation title with a chevron, which opens `HistorySheet`) in the
  principal slot with the model chip below it, and a new-chat button on the
  trailing side (calls `ConversationsStore.startNew()`). Keep all current
  behavior: streaming, scrolling, attachments, slash commands, clear.
- Modify: `MessageBubble.swift`. Assistant messages render full width with no
  bubble; user messages are right-aligned `surfaceRaised` pills. Keep all
  content renderers.
- Modify: `ToolActivityRail.swift`, which becomes compact chips that expand on
  tap.
- Modify: `ChatInputBar.swift`. Use a glass container and add an assign chip
  (`person.badge.plus`) that opens a role menu. When a role is selected, the
  send button tint becomes the role color, and send calls
  `TeamStore.create(KanbanTaskDraft(title: firstLine, body: text, assignee: role))`
  instead of `chatStore.send`, then clears the composer and shows the toast.
- Create: `Features/Chat/ChatEmptyState.swift`, with a greeting based on time
  of day, a team strip ("N working · M need you"; tapping it switches to the
  Team tab), and four starter cards that prefill the composer:
  - Research: "Research … and give me a sourced summary"
  - Do it on the web: "Go to … and …"
  - Automate: "Every morning at 8, …"
  - Remember: "Remember that …"
- Create: `Features/Chat/HistorySheet.swift`, which lists
  `ConversationsStore.grouped` with search (a local title and preview filter),
  swipe to rename (an alert with a text field) and swipe to delete (with
  confirmation). Tapping a conversation activates it and dismisses the sheet.
- Verify the empty state, a conversation with a code block and tool chips (the
  mock client supplies them), the history sheet, and assign mode, with a
  screenshot of each.
- Commit `app: restyled chat with history, starters and assign-to-role`.

### Task 12: Automations screens

**Files:** `HermesMobile/Features/Automations/`
- `AutomationsScreen.swift`: a list of `JobRow`s (name, human-readable
  schedule, next run as relative time, last status pill, and a pause
  `Toggle`), a toolbar "+", and an empty state showing a grid of blueprint
  cards.
- `NewAutomationSheet.swift`: a segmented control for Blueprints and Custom.
  - **Blueprints:** choose a card, then a form built from `CronBlueprintField`.
    `time` fields use a `DatePicker(.hourAndMinute)` formatted `HH:mm`, `enum`
    fields use a `Picker`, and `text` fields use a `TextField`. `deliver`
    defaults to `local` and is hidden when `local` is available.
  - **Custom:** a "What should Hermes do?" editor, `CronSchedulePreset`
    pickers (Every morning, Hourly, Weekdays, Weekly, Custom cron), and a role
    picker (sent as the `profile` query parameter).
  - Create shows the toast "Automation created".
- `JobDetailScreen.swift`: the prompt card, schedule, actions (Run now,
  Pause/Resume, Delete), and a runs list; each run pushes its output rendered
  as markdown.
- Verify with screenshots in mock mode, then create and delete one job against
  the live host by pairing the simulator. If pairing the simulator isn't
  possible, verify against the live API over `railway ssh` using the same
  request bodies.
- Commit `app: automations with blueprints, custom schedules and run history`.

### Task 13: Library screens

**Files:** `HermesMobile/Features/Library/`
- `LibraryScreen.swift`: a segmented control for Memory and Skills.
- `MemoryCardView.swift` and `MemoryEditorScreen.swift`: a title, an "Updated
  …" line, content rendered as markdown (empty state: "Hermes hasn't saved
  anything here yet"), and Edit, which pushes a monospaced editor with Save
  and a byte counter (64 KB limit).
- `SkillsListView.swift`: `.searchable` and grouped by category, where each row
  shows the name, description, a usage count badge and an enable `Toggle`;
  tapping pushes `SkillDetailScreen` (the content as markdown).
- Verify with screenshots; commit `app: library for memory and skills`.

### Task 14: Settings restyle

- Modify `SettingsScreen.swift` and `SettingsSectionView.swift` to reorganize
  into Hermes (host status, version from `/api/status` via the proxy, model
  and context window from `modelInfo()`, and usage over 7 days showing
  sessions, tokens and estimated cost from `usage(days: 7)`), Connection,
  Permissions & sensors, Voice, and About. Restyle with the new tokens. Keep
  every existing control and binding.
- Restyle the onboarding screens (`ConnectHermesScreen`,
  `PermissionsOnboardingScreen`) with the new tokens only; their layout
  doesn't change.
- Verify with screenshots, run the whole unit test suite, and commit
  `app: reorganized settings and restyled onboarding`.

### Task 15: Ship

- [ ] Run the full connector, relay and app test suites.
- [ ] Build the unsigned IPA the way the existing one was built: a
  `generic/platform=iOS` Release build with `CODE_SIGNING_ALLOWED=NO`, then
  `Payload/HermesMobile.app` zipped as `HermesMobile-unsigned.ipa`. Check with
  `file`/`otool` that it's arm64 with minos 26.0.
- [ ] Merge `ui-revamp` into `master` with a merge commit and push. Railway
  redeploys both services from `master`. Confirm both deploys succeed and that
  `/v1/health` responds.
- [ ] Update `deploy/railway/README.md` with the new `HERMES_DASHBOARD_*`
  variables.
