from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services import conversation_title_from_text


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


def current_id(client: TestClient, token: str) -> str:
    return client.get("/v1/conversations/current", headers=auth(token)).json()["data"]["conversation"]["id"]


def listed(client: TestClient, token: str) -> list[dict]:
    return client.get("/v1/conversations", headers=auth(token)).json()["data"]["conversations"]


def test_new_conversation_becomes_current_and_is_listed_first(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        first = current_id(client, token)

        created = client.post("/v1/conversations", headers=auth(token)).json()["data"]["conversation"]

        assert current_id(client, token) == created["id"]
        conversations = listed(client, token)
        assert [c["id"] for c in conversations] == [created["id"], first]
        assert [c["isCurrent"] for c in conversations] == [True, False]
        assert created["title"] == "New chat"


def test_activate_switches_current(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        first = current_id(client, token)
        client.post("/v1/conversations", headers=auth(token))

        response = client.post(f"/v1/conversations/{first}/activate", headers=auth(token))

        assert response.status_code == 200
        assert response.json()["data"]["conversation"]["isCurrent"] is True
        assert current_id(client, token) == first


def test_rename_and_archive(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        created = client.post("/v1/conversations", headers=auth(token)).json()["data"]["conversation"]

        renamed = client.patch(f"/v1/conversations/{created['id']}", json={"title": "  Trip plans "}, headers=auth(token))
        assert renamed.json()["data"]["conversation"]["title"] == "Trip plans"

        assert client.delete(f"/v1/conversations/{created['id']}", headers=auth(token)).status_code == 200
        assert created["id"] not in [c["id"] for c in listed(client, token)]
        assert current_id(client, token) != created["id"]


def test_rename_rejects_blank_title(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        conversation = current_id(client, token)
        response = client.patch(f"/v1/conversations/{conversation}", json={"title": "   "}, headers=auth(token))
        assert response.status_code == 400


def test_unknown_conversation_is_404(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        assert client.post("/v1/conversations/nope/activate", headers=auth(token)).status_code == 404
        assert client.patch("/v1/conversations/nope", json={"title": "x"}, headers=auth(token)).status_code == 404
        assert client.delete("/v1/conversations/nope", headers=auth(token)).status_code == 404


def test_first_user_message_titles_the_conversation(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)

        client.post(
            "/v1/messages",
            json={"text": "Plan   a weekend\nin Lisbon please"},
            headers=auth(token),
        )

        conversations = listed(client, token)
        assert conversations[0]["title"] == "Plan a weekend in Lisbon please"
        assert conversations[0]["preview"]


def test_title_is_trimmed_to_sixty_characters():
    title = conversation_title_from_text("word " * 30)
    assert len(title) <= 60
    assert title.endswith("…")
    assert conversation_title_from_text("   ") is None


def test_clear_starts_an_empty_conversation_even_with_older_chats(tmp_path):
    with build_client(tmp_path) as client:
        token = access_token(client)
        client.post("/v1/messages", json={"text": "Older chat"}, headers=auth(token))
        client.post("/v1/conversations", headers=auth(token))
        client.post("/v1/messages", json={"text": "Newer chat"}, headers=auth(token))

        cleared = client.post("/v1/conversations/current/clear", headers=auth(token)).json()["data"]["conversation"]

        assert cleared["messages"] == []
        assert current_id(client, token) == cleared["id"]
        titles = [c["title"] for c in listed(client, token)]
        assert "Older chat" in titles
        assert "Newer chat" not in titles
