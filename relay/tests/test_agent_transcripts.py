from __future__ import annotations

import base64
import time

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def build_client(tmp_path, **overrides):
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'relay.db'}",
        internal_api_key="test-internal-key",
        **overrides,
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


def test_opened_session_shows_earlier_hermes_messages(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        before = time.time() - 60

        def handler(method, params):
            assert method == "session.transcript"
            assert params == {"profile": "tutor", "sessionId": "s1"}
            return {"sessionId": "s1", "messages": [
                {"id": "1", "role": "user", "text": "quiz me", "timestamp": before},
                {"id": "2", "role": "assistant", "text": "Question 1", "timestamp": before + 1},
                {"id": "3", "role": "assistant", "text": "too new", "timestamp": time.time() + 3600},
            ]}

        install_fake_rpc(client, handler)
        client.post("/v1/conversations/open", json={"profile": "tutor", "sessionId": "s1"}, headers=auth(token))
        conversation = client.get("/v1/conversations/current?profile=tutor", headers=auth(token)).json()["data"]["conversation"]

        assert [(m["role"], m["text"]) for m in conversation["messages"]] == [("user", "quiz me"), ("hermes", "Question 1")]
        assert all(m["deliveryStatus"] in {"sent", "delivered"} for m in conversation["messages"])


def test_transcript_failure_falls_back_to_relay_messages(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)

        def handler(method, params):
            raise RuntimeError("unavailable: dashboard down")

        install_fake_rpc(client, handler)
        client.post("/v1/conversations/open", json={"profile": "tutor", "sessionId": "s1"}, headers=auth(token))
        response = client.get("/v1/conversations/current?profile=tutor", headers=auth(token))
        assert response.status_code == 200
        assert response.json()["data"]["conversation"]["messages"] == []


def test_memory_routes_pass_the_profile(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        calls = install_fake_rpc(client, lambda method, params: {"memory": {"content": ""}, "user": {"content": ""}})
        client.get("/v1/hermes/memory?profile=coach", headers=auth(token))
        assert calls[-1] == ("memory.read", {"profile": "coach"})


def test_audio_transcribe_forwards_to_the_connector(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        calls = install_fake_rpc(client, lambda method, params: {"transcript": "hi tutor"})
        data = base64.b64encode(b"audio").decode()
        response = client.post(
            "/v1/audio/transcribe", json={"profile": "tutor", "mimeType": "audio/m4a", "data": data}, headers=auth(token)
        )
        assert response.json()["data"] == {"transcript": "hi tutor"}
        assert calls[-1] == ("audio.transcribe", {"profile": "tutor", "mimeType": "audio/m4a", "data": data})
