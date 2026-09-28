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
                "platform": "ios",
                "deviceName": "Test iPhone",
                "appVersion": "1.0.0",
                "buildNumber": "1",
                "bundleId": "io.hermesmobile.HermesMobile",
                "installationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "deviceModel": "iPhone17,2",
                "systemVersion": "26.4",
            },
            "client": {"environment": "development"},
        },
    )
    assert response.status_code == 200
    return response.json()["data"]["auth"]["accessToken"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def install_fake_rpc(client: TestClient, handler):
    calls = []

    async def fake(user_id, *, method, params=None, timeout_seconds=None):
        calls.append((method, params))
        return handler(method, params)

    client.app.state.connector_rpc = fake
    return calls


def test_proxy_get_passes_path_and_query(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        calls = install_fake_rpc(client, lambda method, params: {"status": 200, "json": {"columns": []}})

        response = client.get("/v1/hermes/api/plugins/kanban/board?board=main", headers=auth(token))

        assert response.status_code == 200
        assert response.json()["data"] == {"columns": []}
        assert calls == [
            (
                "hermes.api",
                {"method": "GET", "path": "/api/plugins/kanban/board", "query": {"board": "main"}, "body": None},
            )
        ]


def test_proxy_passes_list_payloads(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        install_fake_rpc(client, lambda method, params: {"status": 200, "json": [{"id": "job1"}]})

        response = client.get("/v1/hermes/api/cron/jobs", headers=auth(token))

        assert response.json()["data"] == [{"id": "job1"}]


def test_proxy_post_forwards_json_body(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        calls = install_fake_rpc(client, lambda method, params: {"status": 200, "json": {"task": {"id": "t_1"}}})

        response = client.post("/v1/hermes/api/plugins/kanban/tasks", json={"title": "Research"}, headers=auth(token))

        assert response.status_code == 200
        assert calls[0][1]["method"] == "POST"
        assert calls[0][1]["body"] == {"title": "Research"}


def test_proxy_returns_binary_payloads(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        install_fake_rpc(
            client,
            lambda method, params: {"status": 200, "contentType": "text/markdown", "base64": "IyByZXBvcnQ="},
        )

        response = client.get("/v1/hermes/api/plugins/kanban/attachments/3", headers=auth(token))

        assert response.json()["data"] == {"contentType": "text/markdown", "base64": "IyByZXBvcnQ="}


def test_proxy_maps_hermes_errors(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        install_fake_rpc(client, lambda method, params: {"status": 404, "json": {"detail": "task t_9 not found"}})

        response = client.get("/v1/hermes/api/plugins/kanban/tasks/t_9", headers=auth(token))

        assert response.status_code == 404
        assert response.json()["detail"] == "task t_9 not found"


def test_proxy_maps_rpc_error_codes(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        for message, expected in [
            ("forbidden: GET /api/env is not available to the app", 403),
            ("unavailable: the Hermes dashboard API is not configured on this host", 503),
            ("too_large: response is 9999999 bytes", 413),
            ("something unexpected", 502),
        ]:
            def handler(method, params, message=message):
                raise RuntimeError(message)

            install_fake_rpc(client, handler)
            response = client.get("/v1/hermes/api/env", headers=auth(token))
            assert response.status_code == expected, message
            assert response.json()["detail"] == message


def test_proxy_reports_offline_host_as_409(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)

        response = client.get("/v1/hermes/api/status", headers=auth(token))

        assert response.status_code == 409
        assert response.json()["detail"] == "Hermes host is offline."


def test_proxy_requires_auth(tmp_path):
    with build_client(tmp_path) as client:
        assert client.get("/v1/hermes/api/status").status_code == 401


def test_memory_read_and_write(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)

        def handler(method, params):
            if method == "memory.write":
                return {"content": params["content"], "updatedAt": 1.0}
            return {"memory": {"content": "", "updatedAt": None}, "user": {"content": "Max", "updatedAt": 1.0}}

        calls = install_fake_rpc(client, handler)

        read = client.get("/v1/hermes/memory", headers=auth(token))
        assert read.json()["data"]["user"]["content"] == "Max"

        write = client.put("/v1/hermes/memory/user", json={"content": "Max\n"}, headers=auth(token))
        assert write.json()["data"] == {"content": "Max\n", "updatedAt": 1.0}
        assert calls[-1] == ("memory.write", {"kind": "user", "content": "Max\n"})
