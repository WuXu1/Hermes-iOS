# Self-hosted VM deployment

Runs the Hermes Mobile relay, connector, an always-on Hermes dashboard API and Caddy on a VM that already runs Hermes. The phone reaches it over Tailscale; nothing is exposed on the public internet.

```
iPhone (Tailscale on) --HTTPS--> tailscale serve (:443, tailnet only) --> Caddy (127.0.0.1:8080) --> relay (127.0.0.1:8000) <--WebSocket-- connector --> Hermes (+ dashboard API on 127.0.0.1:9120)
```

## What gets installed

| Piece | Where |
|---|---|
| Relay (user `hermes-relay`, SQLite) | `/opt/hermes-mobile/relay`, venv `/opt/hermes-mobile/relay-venv`, data `/var/lib/hermes-mobile-relay` |
| Connector (user `hermes`) | `/opt/hermes-mobile/connector`, venv `/opt/hermes-mobile/connector-venv` (built from `connector/uv.lock`), state `/data/.hermes-mobile`; `/usr/local/bin/hermes-mobile` is a wrapper that sets the connector's environment |
| Dashboard API | service `hermes-dashboard`, loopback port 9120 (not 9119, which a Hermes Desktop backend may already use) |
| Caddy | apt package; `/etc/caddy/Caddyfile` generated from `Caddyfile.template`; listens on 127.0.0.1:8080 only, automatic HTTPS off |
| Tailscale serve | HTTPS :443 on the VM's `<machine>.<tailnet>.ts.net` name forwarding to Caddy; marker `/etc/hermes-mobile/.tailscale-serve-configured`. Funnel is never enabled |
| Secrets | `/etc/hermes-mobile/{dashboard,relay,connector}.env` (root, mode 0600, generated once, never printed) |
| Services | `hermes-dashboard`, `hermes-mobile-relay`, `hermes-mobile-connector` |

Assumes Hermes runs as user `hermes` with `HERMES_HOME=/data/.hermes` and the CLI at `/home/hermes/.local/bin/hermes`. The install never runs `hermes update` and never touches Hermes's own venv.

Caddy only exposes `/v1/*` and returns 404 for connector, host, push, talk, docs and `/internal/*` paths, plus `/v1/device/register` (the relay also refuses it with 403 in production). The relay's own dependencies are installed unlocked (it has no committed lockfile); only the connector is pinned.

## Prerequisites

- The VM is on your tailnet (`tailscale status` works on it). No inbound firewall rules are needed.
- In the Tailscale admin console (DNS), MagicDNS and HTTPS certificates are enabled for the tailnet.
- Tailscale issues a certificate for the `ts.net` name, which puts the machine and tailnet name into public Certificate Transparency logs (Tailscale documents this).
- The Tailscale app is installed on the iPhone, signed into the same tailnet and switched on whenever you use Hermes Mobile.

## Install

On the VM, with a checkout of this repo:

```bash
sudo deploy/vm/install.sh --repo <path-to-checkout>
```

The VM's name (`<machine>.<tailnet>.ts.net`) is read from `tailscale status`. The script requires Tailscale to be running with HTTPS certificates enabled, then configures `tailscale serve --bg --https=443 http://127.0.0.1:8080`. If `tailscale serve` or Funnel already has a different configuration it stops without changing it. The first HTTPS request may take a few seconds while the certificate is issued.

Safe to rerun; existing secrets are kept.

## Register phone context

Phone context (location, health, motion) is added to exactly the `default`, `assistant` and `coach` agents. Hermes only reads agent config on gateway start, so check nothing is running first:

```bash
sudo -u hermes hermes kanban list          # make sure no task is running
sudo -u hermes hermes-mobile configure-mcp --profiles default,assistant,coach
sudo systemctl restart hermes-gateway
```

## Pair a phone

```bash
sudo -u hermes hermes-mobile pair-phone
```

In the app choose *Enter Code Manually*, make sure Tailscale is on, set the relay URL to `https://<machine>.<tailnet>.ts.net/v1` and enter the code.

## Revoking a device

The relay admin CLI can list paired devices and revoke their sessions. Run it as the relay user with the relay's own environment:

```bash
sudo systemd-run --wait --pipe -p User=hermes-relay -p EnvironmentFile=/etc/hermes-mobile/relay.env \
  /opt/hermes-mobile/relay-venv/bin/hermes-mobile-relay-admin revoke-devices
```

With no options it lists devices (id, name, last seen). Add `--device <id>` to revoke one device, or `--all` to revoke every device.

The phone must then pair again.

## Verify

From a device on the tailnet (Tailscale on), check the blocked routes are closed and health answers:

```bash
base=https://<machine>.<tailnet>.ts.net
curl -s -w "\nhealth %{http_code}\n" $base/v1/health                       # 200 with a JSON body, not an empty reply
for p in v1/hosts/ws v1/device/register v1/hosts/current/revoke v1/connector/setup v1/talk/readiness internal/inbox/create; do
  curl -s -o /dev/null -w "$p %{http_code}\n" -X POST $base/$p            # each 404
done
```

On the VM, check nothing listens publicly:

```bash
sudo ss -tlnp | grep -E ':(8080|8000|9120)\b'     # all on 127.0.0.1 only
sudo ss -tlnp | grep caddy                         # only 127.0.0.1:8080 (and Caddy's admin port on 127.0.0.1:2019); not :80 or :443
tailscale serve status                             # one tailnet-only HTTPS :443 entry, no Funnel
```

## Logs

```bash
journalctl -u hermes-mobile-relay -u hermes-mobile-connector -u hermes-dashboard -f
```

## Dashboard tunnel

The dashboard API listens on loopback only. To open it in a browser:

```bash
ssh -L 9120:127.0.0.1:9120 <admin>@<vm>
```

then open http://localhost:9120. The login uses the session token in `/etc/hermes-mobile/dashboard.env` (`HERMES_DASHBOARD_SESSION_TOKEN`).

## Updating

```bash
cd <path-to-checkout> && git pull
sudo deploy/vm/install.sh --repo <path-to-checkout>
sudo systemctl restart hermes-mobile-relay hermes-mobile-connector
```

## Rollback

```bash
sudo deploy/vm/uninstall.sh              # add --keep-data to keep the relay database and connector state; also runs `tailscale serve --https=443 off`, which turns off the whole Tailscale HTTPS :443 listener on the VM
sudo systemctl restart hermes-gateway    # picks up the removed phone-context entries
tailscale serve status                   # confirm nothing is left
```

## Memory budget

On a small VM watch memory: the relay and connector are light (roughly 100 MB each) and the dashboard API adds a Python process on top of the gateway. Check with `systemctl status` and `free -h` after installing, and stop `hermes-dashboard` first if the VM is tight (the app's Team, Automations and Library tabs need it).
