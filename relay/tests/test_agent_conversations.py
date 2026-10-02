from __future__ import annotations

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


def current(client, token, profile=None):
    url = "/v1/conversations/current" + (f"?profile={profile}" if profile else "")
    return client.get(url, headers=auth(token)).json()["data"]["conversation"]


def test_each_agent_has_its_own_current_conversation(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        commander = current(client, token)
        coach = current(client, token, "coach")
        assert commander["profile"] == "default"
        assert coach["profile"] == "coach"
        assert commander["id"] != coach["id"]
        assert current(client, token, "coach")["id"] == coach["id"]


def test_bad_profile_is_rejected(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        response = client.get("/v1/conversations/current?profile=../x", headers=auth(token))
        assert response.status_code == 422


def test_open_binds_a_hermes_session_and_makes_it_current(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        opened = client.post(
            "/v1/conversations/open", json={"profile": "tutor", "sessionId": "20261001_abc"}, headers=auth(token)
        ).json()["data"]["conversation"]
        now = current(client, token, "tutor")
        assert now["id"] == opened["id"]
        assert now["hermesSessionId"] == "20261001_abc"


def test_reopening_the_same_session_replaces_the_binding(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        body = {"profile": "tutor", "sessionId": "20261001_abc"}
        first = client.post("/v1/conversations/open", json=body, headers=auth(token)).json()["data"]["conversation"]
        second = client.post("/v1/conversations/open", json=body, headers=auth(token)).json()["data"]["conversation"]
        assert first["id"] != second["id"]
        assert current(client, token, "tutor")["id"] == second["id"]


def test_message_job_carries_the_agent(tmp_path):
    with build_client(tmp_path, hermes_adapter="connector") as client:
        token = access_token(client)
        client.post("/v1/messages", json={"text": "hi", "profile": "coach"}, headers=auth(token))
        from app.models import MessageJob

        with client.app.state.database.session() as db:
            job = db.query(MessageJob).one()
            payload = client.app.state.build_job_execute_payload(db, job_id=job.id)
        assert payload["job"]["profile"] == "coach"
