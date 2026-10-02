# Self-hosted VM deployment

Runs the Hermes Mobile relay, connector, an always-on Hermes dashboard API and Caddy (HTTPS) on a VM that already runs Hermes.

```
iPhone --HTTPS--> Caddy (443) --> relay (127.0.0.1:8000) <--WebSocket-- connector --> Hermes (+ dashboard API on 127.0.0.1:9119)
```

## What gets installed

| Piece | Where |
|---|---|
| Relay (user `hermes-relay`, SQLite) | `/opt/hermes-mobile/relay`, venv `/opt/hermes-mobile/relay-venv`, data `/var/lib/hermes-mobile-relay` |
| Connector (user `hermes`) | `/opt/hermes-mobile/connector`, venv `/opt/hermes-mobile/connector-venv`, state `/data/.hermes-mobile` |
| Dashboard API | service `hermes-dashboard`, loopback port 9119 |
| Caddy | apt package; `/etc/caddy/Caddyfile` generated from `Caddyfile.template` |
| Secrets | `/etc/hermes-mobile/{dashboard,relay,connector}.env` (root, mode 0600, generated once, never printed) |
| Services | `hermes-dashboard`, `hermes-mobile-relay`, `hermes-mobile-connector` |

Assumes Hermes runs as user `hermes` with `HERMES_HOME=/data/.hermes` and the CLI at `/home/hermes/.local/bin/hermes`. The install never runs `hermes update` and never touches Hermes's own venv.

Caddy only exposes `/v1/*` and returns 404 for connector, host, push, talk, docs and `/internal/*` paths.

## Azure prerequisites

Give the VM's public IP a DNS name and open ports 80 (certificate issuance) and 443:

```bash
az network public-ip update -g <rg> -n <ip-name> --dns-name <label>
az network nsg rule create -g <rg> --nsg-name <nsg> -n https-in --priority 310 --access Allow --protocol Tcp --direction Inbound --destination-port-ranges 443
az network nsg rule create -g <rg> --nsg-name <nsg> -n http-in --priority 311 --access Allow --protocol Tcp --direction Inbound --destination-port-ranges 80
```

The DNS name is `<label>.<region>.cloudapp.azure.com`.

## Install

On the VM, with a checkout of this repo:

```bash
sudo deploy/vm/install.sh --domain <dns-name> --email <acme-email> --repo <path-to-checkout>
```

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

In the app choose *Enter Code Manually*, set the relay URL to `https://<dns-name>/v1` and enter the code.

## Revoking a device

`hermes-mobile-relay-admin --help` (run it as `/opt/hermes-mobile/relay-venv/bin/hermes-mobile-relay-admin`, with the variables from `/etc/hermes-mobile/relay.env` exported) offers only `create-setup-code`, which makes a single-use pairing code for the relay's own pairing flow. There is no revoke command. To revoke a phone, revoke its sessions in the relay database:

```bash
sudo sqlite3 /var/lib/hermes-mobile-relay/relay.db \
  "SELECT d.id, d.device_name, d.last_seen_at FROM devices d;"
sudo sqlite3 /var/lib/hermes-mobile-relay/relay.db \
  "UPDATE auth_sessions SET revoked_at = datetime('now') WHERE device_id = '<device-id>';"
```

The phone must then pair again.

## Logs

```bash
journalctl -u hermes-mobile-relay -u hermes-mobile-connector -u hermes-dashboard -f
```

## Dashboard tunnel

The dashboard API listens on loopback only. To open it in a browser:

```bash
ssh -L 9119:127.0.0.1:9119 <admin>@<vm>
```

then open http://localhost:9119. The login uses the session token in `/etc/hermes-mobile/dashboard.env` (`HERMES_DASHBOARD_SESSION_TOKEN`).

## Updating

```bash
cd <path-to-checkout> && git pull
sudo deploy/vm/install.sh --domain <dns-name> --email <acme-email> --repo <path-to-checkout>
sudo systemctl restart hermes-mobile-relay hermes-mobile-connector
```

## Rollback

```bash
sudo deploy/vm/uninstall.sh              # add --keep-data to keep the relay database and connector state
sudo systemctl restart hermes-gateway    # picks up the removed phone-context entries
az network nsg rule delete -g <rg> --nsg-name <nsg> -n https-in
az network nsg rule delete -g <rg> --nsg-name <nsg> -n http-in
az network public-ip update -g <rg> -n <ip-name> --dns-name ""
```

## Memory budget

On a small VM watch memory: the relay and connector are light (roughly 100 MB each) and the dashboard API adds a Python process on top of the gateway. Check with `systemctl status` and `free -h` after installing, and stop `hermes-dashboard` first if the VM is tight (the app's Team, Automations and Library tabs need it).
