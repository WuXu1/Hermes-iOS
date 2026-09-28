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
                json=body,
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
