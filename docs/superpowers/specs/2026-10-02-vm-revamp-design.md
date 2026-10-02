# Hermes iOS on a self-hosted VM with five agents: design

Date: 2026-10-02
Status: approved in chat by the owner, awaiting review of this written spec
Branch: `vm-revamp`

## Goal

Make the app work with the owner's current Hermes setup, which has replaced the
Railway deployment this repo was built for:

- Hermes Agent v0.21.5 (2026.9.24, the stable release) runs on a single Linux VM
  as the unprivileged user `hermes`, with `HERMES_HOME=/data/.hermes`, a
  `hermes-gateway` systemd service, and the source in `/opt/hermes/hermes-agent`
  (its own venv; `hermes update` is deliberately disabled).
- Five agents, each a Hermes profile with its own Telegram bot, served by one
  multiplexed gateway: `default` (shown as **Commander**, the chief), and the
  specialists `developer`, `tutor`, `assistant` and `coach`. Commander hands
  work to the specialists on the kanban board.
- All five share one Holographic fact store. Each has its own `MEMORY.md`,
  `USER.md`, skills, cron jobs, `.env` and `state.db`.
- Speech-to-text is local faster-whisper, configured in every profile.

The app should let the owner talk to any of the five agents, see each one's
history (including Telegram), run the board and automations, and manage memory
and skills, from anywhere, without opening anything on the VM except HTTPS.

## Non-goals

- Push notifications (sideloaded builds can't receive APNs). Screens refresh
  while visible.
- Live voice mode (OpenAI Realtime) and CarPlay: removed.
- Gemini audio transcription, hermes-webui, the Bot Screen desktop image and the
  Railway/Docker deployment: removed.
- Editing agent personas (`SOUL.md`) from the phone.
- Viewing or editing the shared Holographic fact store.
- Moving this setup back to Railway (a separate job later).
- Any change to Hermes itself. Everything goes through Hermes's own API and CLI.

## Architecture

```
iPhone app ──HTTPS :443──▶ Caddy ──▶ relay (127.0.0.1:8000, user hermes-relay)
                                        │ WebSocket RPC (loopback)
                                        ▼
                         connector (user hermes) ──HTTP──▶ Hermes dashboard API (127.0.0.1:9119)
                                        └──subprocess──▶ hermes -p <profile> chat …
```

Everything except Caddy listens on loopback only. The relay and connector keep
their existing protocol (pairing, device tokens, WebSocket RPC between relay and
connector), so the app's networking layer is unchanged.

### Public address and TLS

- An Azure DNS label on the VM's existing static public IP gives a stable name
  of the form `<label>.<region>.cloudapp.azure.com`. Free, no third-party DNS.
- Caddy terminates TLS with an automatic Let's Encrypt certificate.
- The network security group gains two rules: TCP 443 from anywhere, and TCP 80
  from anywhere. Port 80 only serves ACME challenges and redirects to HTTPS.
  The SSH rule (owner's IP only) is unchanged.

### Caddy routing

Caddy forwards only the routes the app uses and returns 404 for everything
else. Blocked from outside, so reachable only on loopback:

- `/internal/*`
- relay admin routes (`relay/app/admin.py`)
- `/v1/connector/setup`, `/v1/connector/phone-pairing-codes`,
  `/v1/hosts/enrollment-codes`, `/v1/hosts/ws` (the connector reaches the relay
  on loopback through `HERMES_MOBILE_RELAY_INTERNAL_URL`, because the relay
  hands out its public URL)
- `/v1/push/*` (unused without APNs)
- `/v1/talk/*` (live voice is removed)

The exact allowlist is written in the Caddyfile in `deploy/vm/` and tested with
`curl` from outside after install.

### Services

Three new systemd units, alongside the existing `hermes-gateway`:

| Unit | User | Listens | What it runs |
|---|---|---|---|
| `hermes-dashboard` | `hermes` | 127.0.0.1:9119 | `hermes dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build`, always on, with `HERMES_DASHBOARD_SESSION_TOKEN` |
| `hermes-mobile-relay` | `hermes-relay` | 127.0.0.1:8000 | the relay (`relay/`), SQLite in `/var/lib/hermes-mobile-relay` |
| `hermes-mobile-connector` | `hermes` | none (dials the relay) | the connector (`connector/`), state in `/data/.hermes-mobile` |

- `hermes-relay` is a new system user with no access to `/data/.hermes`.
- The relay and connector each get their own venv under `/opt/hermes-mobile/`,
  built with uv from the lock files, and are never mixed into Hermes's venv.
- Secrets (`INTERNAL_API_KEY`, `CONNECTOR_SETUP_SECRET`, the dashboard session
  token) are generated on the VM into root-owned `EnvironmentFile`s
  (`/etc/hermes-mobile/*.env`, mode 0600) and never committed.
- Because the dashboard is now always on, the owner's dashboard tunnel becomes
  `ssh -L 9119:127.0.0.1:9119 <vm>` with nothing started on demand.
- Expected extra memory: about 0.5 GB (dashboard ~0.35 GB, relay and connector
  ~0.1 GB, Caddy ~0.03 GB). Each app message also starts a short-lived
  `hermes chat` process, as Telegram turns do.

### Repo layout

- New: `deploy/vm/` with `install.sh` (idempotent; takes the DNS name as an
  argument), the three unit files, the `Caddyfile` template and a README
  runbook (install, pair a phone, revoke a device, logs, rollback).
- Removed: `deploy/railway/` (Dockerfile, start script, role personas),
  Gemini transcription in `connector/.../audio_transcription.py`, the
  hermes-webui and Bot Screen notes, and the Fly/Docker files in `relay/`
  that only served the old hosting.
- The repo stays public-safe: no IP addresses, hostnames, tokens, user IDs or
  personal details. VM-specific values live only on the VM and in the owner's
  private notes.

## Connector changes

### Chat per agent

- Every chat RPC carries a `profile` (one of the names from `/api/profiles`;
  default `default`). The runner calls
  `hermes -p <profile> chat -Q -q <text> [--resume <session_id>] --source tool`.
- The `--provider`/`--model` overrides are dropped, so each profile uses its own
  configured model.
- The profile name is validated against the live profile list before use and is
  passed as a separate argv item, never through a shell.

### History from Hermes, not the relay

- Conversation list: the app reads `GET /api/sessions?profile=<p>&order=recent`
  through the proxy (excluding `cron` and `subagent` sessions), showing each
  session's title, source (`telegram`, `desktop`, `tool`…) and last activity.
- Rename and archive use the dashboard's own `PATCH /api/sessions/<id>`
  (`title`, `archived`) with the profile in the body. Hard delete is not offered.
- Each relay conversation gains a `profile` and stays bound to one Hermes
  session (`hermes_session_id`). The relay keeps the turns sent from the app,
  which is what live streaming and retries rely on, and "current conversation"
  becomes per agent.
- Opening a Hermes session from history (`POST /v1/conversations/open`) archives
  any older relay binding for that session and creates a fresh one. When the
  app loads it, the relay asks the connector for the session transcript
  (`session.transcript` RPC → `GET /api/sessions/<id>/messages?profile=<p>`),
  keeps user and assistant messages from before the binding was created, and
  puts them ahead of the relay's own messages. Messages added in Telegram after
  that point appear the next time the session is opened from history.

### Voice notes

- The app uploads the recording. The connector sends it to Hermes's own
  transcription endpoint (`POST /api/audio/transcribe?profile=<p>`), which uses
  the profile's configured `stt` (local faster-whisper). The transcript is
  returned to the app, shown in the chat, then sent as the message text.
- Size limit stays 5 MB.

### Attachments

- Images are passed to the agent as they are (the model reads them).
- PDF and Office files are converted to text on the VM with Hermes's document
  reader, as before.

### Phone context (MCP)

- The connector's `hermes_mobile` MCP server (location, Health, motion tools)
  is registered in exactly three profiles: `default`, `assistant` and `coach`.
  Registration backs up each `config.yaml` first and only adds the
  `mcp_servers.hermes_mobile` entry.
- Data is only sent by the phone for the types the owner has allowed in the
  app's permission screen.

### Tightened API allowlist

`hermes_api_proxy._ROUTES` becomes:

| Allowed | Notes |
|---|---|
| `GET /api/status`, `GET /api/model/info`, `GET /api/analytics/usage` | `profile` query allowed |
| `GET /api/profiles`, `GET /api/profiles/<p>/soul` | personas read-only (no `PUT`) |
| `GET /api/sessions`, `/api/sessions/search`, `/api/sessions/<id>`, `/api/sessions/<id>/messages` | `profile` query allowed |
| session rename / archive | the dashboard's exact routes, confirmed during implementation |
| kanban: `GET` board/assignees/stats/task/log/attachments; `POST` tasks, comments, reassign, links; `PATCH` task | no `DELETE` |
| cron: `GET`/`POST` jobs, `GET`/`PUT` job, pause/resume/trigger, runs, blueprints | no `DELETE`; `profile` query allowed |
| `GET /api/skills`, `GET /api/skills/content`, `PUT /api/skills/toggle` | toggle refused for pinned skills (checked in the connector) |
| `POST /api/audio/transcribe` | voice notes |

Everything else, including config, gateway restart, update, plugin, MCP, OAuth
and file routes, is refused. Query parameters are allowlisted per route
(`profile`, `days`, `q`, `limit`, `offset`, `name`).

### Memory files

The connector reads and writes `MEMORY.md` and `USER.md` under the chosen
profile's home (`$HERMES_HOME` for `default`, `$HERMES_HOME/profiles/<p>` for
the others), with the existing size limits.

## App changes

### Agents

- `RoleStyle` gets styles for the five agents: `default` displayed as
  "Commander", plus Developer, Tutor, Assistant and Coach. The old roles are
  removed. Unknown profiles still get a palette color, so new agents appear
  without an app update.
- A shared `AgentStore` loads `/api/profiles` once per foreground and is the
  single source for agent pickers across tabs.

### Chat tab

- An agent picker in the navigation bar; the choice is remembered.
- The history sheet lists the selected agent's sessions with a source badge
  ("Telegram", "App"). Any session can be opened. Continuing a Telegram session
  from the app keeps the conversation context, but replies appear only in the
  app; a one-line note in that chat says so.
- Attachments: photo, PDF, Office, and voice note (record, show transcript,
  send).
- Slash commands: only those that make sense outside Telegram are kept.

### Team tab

- Commander's board with the four specialists as assignees; reply to blocked
  cards, approve or send back, create a task for an agent, turn a chat message
  into a task.
- The role sheet shows the persona read-only.

### Automations tab

- Jobs from all five profiles, merged, each with an agent badge. Run now,
  pause/resume, run history and output, and new jobs for a chosen agent from a
  blueprint or a custom prompt and schedule. No delete.

### Library tab

- Agent picker, then memory (`MEMORY.md`, `USER.md`, editable) and skills
  (toggle; pinned role skills shown locked).

### Settings

- Server status: gateway running, connected bots.
- Model per agent.
- Usage and cost over the last 7 days, in total and per agent.
- Paired devices note and how to revoke.

### Widgets

- Board widget (running and waiting-on-you counts) and next-automation widget,
  fed by the existing App Group store.

### Removed from the app

Live voice (`Features/Talk`, `TalkStore`, the voice services), CarPlay, the
Railway "connect host" screens, and the old Inbox and Capture screens if they
are confirmed unreachable. Each removal is checked with a build and the test
suite.

### Pairing

Unchanged: a single-use code made on the VM
(`sudo -u hermes hermes-mobile pair-phone`), valid for 10 minutes, entered or
scanned in the app; the device token is stored in the Keychain.

## Error handling

- When the relay is reachable but the connector is not, the app shows the
  existing offline banner ("Hermes is offline") and keeps cached data visible.
- Chat sends that fail are kept as failed messages with a retry button.
- When the dashboard API is down, the connector returns a clear `unavailable`
  error for workspace calls, while chat (which uses the CLI) keeps working.
- A refused allowlist call returns `forbidden` and is logged by the connector
  without request bodies.
- `hermes chat` has a timeout matching the gateway's (the model stall timeout
  is already 60 s, with one retry), so a hung DeepSeek call ends with an error
  message rather than a spinner forever.

## Testing

- Connector `pytest`: the profile argument in the runner (including rejection
  of unknown names), the history mapping, the new allowlist (allowed and
  refused cases, query filtering), the pinned-skill guard, voice transcription
  through the dashboard, and MCP registration into exactly three profiles.
- Relay `pytest`: routing of sends by `(profile, session_id)`, and pairing.
- App: unit tests for the stores and models, plus the mock-mode screenshot tour
  updated for five agents.
- End to end in the iOS Simulator against the real VM, before anything is
  installed on the phone: a message to each agent, opening a Telegram session,
  the board, automations, library, settings, a voice note and phone context.
- After install: `curl` from outside confirms that only the allowed routes
  answer, and the certificate is valid.

## Rollout

1. Implement on `vm-revamp`: connector and relay first (with tests), then
   `deploy/vm/`, then the app.
2. Before touching the VM: confirm no kanban card is running and no chat is in
   progress; back up configs and `.env` files to
   `/data/backups/pre-mobile-<date>`.
3. On the VM: DNS label and firewall rules, Caddy, the three services, phone
   context registration in three profiles, one gateway restart.
4. Simulator end-to-end test, build the unsigned IPA, the owner sideloads and
   pairs.
5. Update the owner's private runbook, merge `vm-revamp` into `master`, push.

## Rollback

Stop and disable `caddy`, `hermes-mobile-relay`, `hermes-mobile-connector` and
`hermes-dashboard`; delete the 80/443 firewall rules; restore the three
profiles' `config.yaml` from the backup and restart the gateway once. No
Hermes data (sessions, memory, board, cron) is changed by the app except
through Hermes's own API, so nothing else needs undoing.
