from __future__ import annotations

import argparse
from dataclasses import dataclass
import sys
from urllib.parse import urlparse

import qrcode

from .config import Settings
from .database import Database
from .pairing import SetupCodePayload, build_setup_code
from sqlalchemy import select

from .models import AuthSession, Device
from .services import create_pairing_invite, revoke_auth_session


LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


@dataclass(frozen=True)
class PublicBaseURLSummary:
    display_host: str
    is_local: bool


def summarize_public_base_url(public_base_url: str, *, environment: str) -> PublicBaseURLSummary:
    parsed = urlparse(public_base_url)

    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise SystemExit("PUBLIC_BASE_URL must be an absolute http(s) URL.")

    if not parsed.path.endswith("/v1"):
        raise SystemExit("PUBLIC_BASE_URL must point to the relay API base and end with '/v1'.")

    host = parsed.hostname or public_base_url
    is_local = host in LOCAL_HOSTS

    if environment != "development":
        if parsed.scheme != "https":
            raise SystemExit("PUBLIC_BASE_URL must use HTTPS outside development.")
        if is_local:
            raise SystemExit("PUBLIC_BASE_URL must not be localhost outside development.")

    return PublicBaseURLSummary(display_host=host, is_local=is_local)


def print_setup_code_qr(setup_code: str) -> None:
    qr = qrcode.QRCode(border=1)
    qr.add_data(setup_code)
    qr.make(fit=True)
    qr.print_ascii(tty=False)


def run_create_setup_code() -> int:
    settings = Settings.from_env()
    summary = summarize_public_base_url(settings.public_base_url, environment=settings.environment)
    database = Database(settings.database_url)
    database.create_all()

    with database.session() as db:
        invite, invite_token = create_pairing_invite(db, settings=settings)

    setup_code = build_setup_code(
        SetupCodePayload(
            relay_url=settings.public_base_url,
            invite_token=invite_token,
            expires_at=invite.expires_at,
        )
    )

    if summary.is_local:
        print(
            "Warning: PUBLIC_BASE_URL resolves to localhost. This setup code only works from the same machine "
            "or an iOS simulator running on it.",
            file=sys.stderr,
        )

    print(f"Relay host: {summary.display_host}")
    print(f"Expires at: {invite.expires_at.isoformat()}")
    print()
    print("Setup code:")
    print(setup_code)
    print()
    print("QR code:")
    print_setup_code_qr(setup_code)
    return 0


def run_revoke_devices(*, device_id: str | None, revoke_all: bool, database: Database | None = None) -> int:
    """List paired devices; with a device id or --all, revoke their active auth sessions."""
    if database is None:
        settings = Settings.from_env()
        database = Database(settings.database_url)
        database.create_all()

    with database.session() as db:
        devices = list(db.scalars(select(Device).order_by(Device.created_at)))
        if device_id is not None and all(device.id != device_id for device in devices):
            print(f"No device with id {device_id}.", file=sys.stderr)
            return 1

        if device_id is None and not revoke_all:
            if not devices:
                print("No paired devices.")
            for device in devices:
                last_seen = device.last_seen_at.isoformat() if device.last_seen_at else "never"
                print(f"{device.id}  {device.device_name or '(unnamed)'}  last seen {last_seen}")
            print("Revoke one with --device <id>, or everything with --all.")
            return 0

        targets = [device for device in devices if revoke_all or device.id == device_id]
        revoked = 0
        for device in targets:
            sessions = db.scalars(
                select(AuthSession).where(AuthSession.device_id == device.id, AuthSession.revoked_at.is_(None))
            )
            for auth_session in list(sessions):
                revoke_auth_session(db, auth_session=auth_session)
                revoked += 1
        print(f"Revoked {revoked} session(s) on {len(targets)} device(s). Those phones must pair again.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="hermes-mobile-relay-admin")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("create-setup-code", help="Create a single-use Hermes Mobile pairing setup code.")
    revoke = subparsers.add_parser(
        "revoke-devices", help="List paired devices, or revoke their sessions with --device <id> or --all."
    )
    revoke.add_argument("--device", help="Device id to revoke (see the listing).")
    revoke.add_argument("--all", action="store_true", dest="revoke_all", help="Revoke every device.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "create-setup-code":
        return run_create_setup_code()

    if args.command == "revoke-devices":
        if args.device and args.revoke_all:
            raise SystemExit("Use either --device or --all, not both.")
        return run_revoke_devices(device_id=args.device, revoke_all=args.revoke_all)

    raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
