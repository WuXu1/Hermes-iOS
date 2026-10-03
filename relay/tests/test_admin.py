from __future__ import annotations

from sqlalchemy import select

from app.admin import run_revoke_devices
from app.models import AuthSession

from test_pairing import build_client, create_invite, pairing_payload


def pair(client, installation_id: str) -> None:
    _, token = create_invite(client)
    response = client.post(
        "/v1/pairing/redeem", json=pairing_payload(token, installation_id)
    )
    assert response.status_code == 200


def active_sessions(client) -> int:
    with client.app.state.database.session() as db:
        return len(list(db.scalars(select(AuthSession).where(AuthSession.revoked_at.is_(None)))))


def test_revoke_devices_lists_then_revokes_one_then_all(tmp_path, capsys):
    with build_client(tmp_path) as client:
        pair(client, "11111111-1111-1111-1111-111111111111")
        pair(client, "22222222-2222-2222-2222-222222222222")
        database = client.app.state.database
        assert active_sessions(client) == 2

        assert run_revoke_devices(device_id=None, revoke_all=False, database=database) == 0
        listing = capsys.readouterr().out
        assert "Taylor's iPhone" in listing
        assert active_sessions(client) == 2

        with database.session() as db:
            first = db.scalars(select(AuthSession)).first().device_id
        assert run_revoke_devices(device_id=first, revoke_all=False, database=database) == 0
        assert active_sessions(client) == 1

        assert run_revoke_devices(device_id=None, revoke_all=True, database=database) == 0
        assert active_sessions(client) == 0


def test_revoke_devices_rejects_unknown_device(tmp_path, capsys):
    with build_client(tmp_path) as client:
        pair(client, "11111111-1111-1111-1111-111111111111")
        assert run_revoke_devices(device_id="nope", revoke_all=False, database=client.app.state.database) == 1
        assert active_sessions(client) == 1
