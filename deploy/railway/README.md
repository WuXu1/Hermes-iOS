# Railway deployment

Runs the whole stack on Railway so no home machine is needed:

| Service | Source | Volume | Notes |
|---|---|---|---|
| `relay` | `relay/Dockerfile` (root directory `relay`) | `/data` (SQLite) | Public domain; the iPhone app points here |
| `hermes-host` | `deploy/railway/hermes-host.Dockerfile` (repo root) | `/opt/data` (`HERMES_HOME` + connector state) | Hermes Agent + connector + team profiles; no public domain |

## Variables

`relay`:

```
RELAY_ENVIRONMENT=production
HERMES_ADAPTER=connector
PORT=8000
DATABASE_URL=sqlite:////data/relay.db
PUBLIC_BASE_URL=https://<relay-domain>/v1
INTERNAL_API_KEY=<random>
CONNECTOR_SETUP_SECRET=<random>
CONNECTOR_SYNC_WAIT_SECONDS=25
```

`hermes-host`:

```
RAILWAY_DOCKERFILE_PATH=deploy/railway/hermes-host.Dockerfile
HERMES_MOBILE_RELAY_URL=https://<relay-domain>/v1
CONNECTOR_SETUP_SECRET=${{relay.CONNECTOR_SETUP_SECRET}}
DEEPSEEK_API_KEY=<your key>
```

The model defaults to DeepSeek `deepseek-flash`. Override with `HERMES_PROVIDER`,
`HERMES_MODEL` and `HERMES_BASE_URL`.

## What the start script does on every boot

1. Syncs the bundled `hermes-ios` skill into `HERMES_HOME`.
2. Creates a Hermes profile for each directory in `roles/` (except `default`)
   and writes its `SOUL.md` persona. Personas that still carry the
   `managed by hermes-host` marker line are refreshed on each deploy; delete
   that line to keep your own edits.
3. Pins the model, provider and base URL in every profile's `config.yaml`, and
   copies `DEEPSEEK_API_KEY` into every profile's `.env` (workers spawned by
   the gateway don't inherit the container environment).
4. Registers with the relay on first boot, then runs the connector.

The gateway (kanban dispatcher and cron) starts automatically via
`HERMES_GATEWAY_BOOTSTRAP_STATE=running`.

## Team roles

The default profile, which the iPhone app talks to, acts as chief of staff and
assigns kanban tasks to `researcher`, `operator`, `coder` and `reviewer`. To add
a role, create `roles/<name>/SOUL.md` and `roles/<name>/description`, then
redeploy.

## Pairing a phone

```bash
railway ssh -s hermes-host -- hermes-mobile pair-phone
```
