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

# One path segment: an id, name or slug. It never starts with a dot (so "." and
# ".." can't match) and allows no "%" escapes.
_SEG = r"[A-Za-z0-9_-][A-Za-z0-9._-]*"

from pathlib import Path

from .profiles import locked_skills, normalize_profile, profile_home

_COMMON = frozenset({"profile"})

# (methods, path pattern, allowed query keys)
_ROUTES: tuple[tuple[frozenset[str], re.Pattern[str], frozenset[str]], ...] = tuple(
    (frozenset(methods), re.compile(f"^{pattern}$"), frozenset(keys) | _COMMON)
    for methods, pattern, keys in (
        ({"GET"}, r"/api/status", ()),
        ({"GET"}, r"/api/model/info", ()),
        ({"GET"}, r"/api/analytics/usage", ("days",)),
        ({"GET"}, r"/api/profiles", ()),
        ({"GET"}, rf"/api/profiles/{_SEG}/soul", ()),
        ({"GET"}, r"/api/sessions", ("limit", "offset", "order", "archived", "exclude_sources", "sources", "min_messages")),
        ({"GET"}, r"/api/sessions/search", ("q", "limit")),
        ({"GET", "PATCH"}, rf"/api/sessions/{_SEG}", ()),
        ({"GET"}, rf"/api/sessions/{_SEG}/messages", ("limit", "offset", "order")),
        ({"GET"}, r"/api/plugins/kanban/(board|assignees|stats)", ("board",)),
        ({"POST"}, r"/api/plugins/kanban/tasks", ()),
        ({"GET", "PATCH"}, rf"/api/plugins/kanban/tasks/{_SEG}", ()),
        ({"POST"}, rf"/api/plugins/kanban/tasks/{_SEG}/(comments|reassign)", ()),
        ({"GET"}, rf"/api/plugins/kanban/tasks/{_SEG}/(log|attachments)", ()),
        ({"GET"}, rf"/api/plugins/kanban/attachments/{_SEG}", ()),
        ({"POST"}, r"/api/plugins/kanban/links", ()),
        ({"GET", "POST"}, r"/api/cron/jobs", ()),
        ({"GET", "PUT"}, rf"/api/cron/jobs/{_SEG}", ()),
        ({"POST"}, rf"/api/cron/jobs/{_SEG}/(pause|resume|trigger)", ()),
        ({"GET"}, rf"/api/cron/jobs/{_SEG}/runs", ("limit",)),
        ({"GET"}, r"/api/cron/blueprints", ()),
        ({"POST"}, r"/api/cron/blueprints/instantiate", ()),
        ({"GET"}, r"/api/skills", ()),
        ({"GET"}, r"/api/skills/content", ("name",)),
        ({"PUT"}, r"/api/skills/toggle", ()),
    )
)

# Routes whose JSON body also names the profile; the query value wins.
_BODY_PROFILE_ROUTES = (re.compile(rf"^/api/sessions/{_SEG}$"), re.compile(r"^/api/skills/toggle$"))
_SESSION_PATCH_KEYS = frozenset({"title", "archived"})
_SESSION_ROUTE = re.compile(rf"^/api/sessions/{_SEG}$")


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


def _match(method: str, path: str) -> frozenset[str]:
    method = (method or "").upper()
    for methods, pattern, keys in _ROUTES:
        if method in methods and pattern.match(path or ""):
            return keys
    raise HermesApiError(f"forbidden: {method} {path} is not available to the app")


def check_route(method: str, path: str) -> None:
    _match(method, path)


def filter_query(path: str, query: Mapping[str, Any] | None, *, method: str = "GET") -> dict[str, str]:
    keys = _match(method, path)
    return {key: str(value) for key, value in (query or {}).items() if key in keys and value is not None}


def prepare_request(params: Mapping[str, Any], *, hermes_home: Path) -> dict:
    method = str(params.get("method") or "GET").upper()
    path = str(params.get("path") or "")
    query = filter_query(path, params.get("query"), method=method)
    try:
        profile = normalize_profile(query.get("profile"))
        home = profile_home(hermes_home, profile)
    except ValueError as error:
        raise HermesApiError(str(error)) from error
    # /api/cron/jobs without a profile lists every agent's jobs ("all"); keep that.
    if "profile" in query or not (method == "GET" and path == "/api/cron/jobs"):
        query["profile"] = profile

    body = params.get("body")
    if method == "PATCH" and _SESSION_ROUTE.match(path):
        body = {key: value for key, value in dict(body or {}).items() if key in _SESSION_PATCH_KEYS}
    if any(pattern.match(path) for pattern in _BODY_PROFILE_ROUTES) and method in {"PATCH", "PUT"}:
        body = {**dict(body or {}), "profile": profile}
    if method == "PUT" and path == "/api/skills/toggle":
        name = str((body or {}).get("name") or "")
        if not (body or {}).get("enabled", True) and name in locked_skills(home):
            raise HermesApiError(f"locked: {name} is this agent's role skill and stays on")
    return {"method": method, "path": path, "query": query, "body": body, "home": home}


async def call_hermes_api(
    params: dict,
    *,
    config: HermesApiConfig,
    hermes_home: Path,
    transport: httpx.AsyncBaseTransport | None = None,
) -> dict:
    request = prepare_request(params, hermes_home=hermes_home)
    if not config.token:
        raise HermesApiError("unavailable: the Hermes dashboard API is not configured on this host")

    async with httpx.AsyncClient(
        base_url=config.base_url, transport=transport, timeout=REQUEST_TIMEOUT_SECONDS
    ) as client:
        try:
            response = await client.request(
                request["method"],
                request["path"],
                params=request["query"] or None,
                json=request["body"],
                headers={"X-Hermes-Session-Token": config.token},
            )
        except httpx.HTTPError as error:
            raise HermesApiError(f"unavailable: {error}") from error

    content_type = response.headers.get("content-type", "").split(";")[0].strip()
    if content_type == "application/json" or not response.content:
        payload = response.json() if response.content else None
        if request["method"] == "GET" and request["path"] == "/api/skills" and isinstance(payload, list):
            locked = locked_skills(request["home"])
            payload = [{**skill, "locked": skill.get("name") in locked} for skill in payload]
        return {"status": response.status_code, "json": payload}
    if len(response.content) > MAX_BINARY_BYTES:
        raise HermesApiError(f"too_large: response is {len(response.content)} bytes")
    return {
        "status": response.status_code,
        "contentType": content_type or "application/octet-stream",
        "base64": base64.b64encode(response.content).decode("ascii"),
    }
