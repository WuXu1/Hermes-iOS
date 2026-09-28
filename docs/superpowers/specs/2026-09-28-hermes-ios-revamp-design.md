# Hermes iOS revamp: design

Date: 2026-09-28
Status: approved direction (the owner delegated design decisions)

## Goal

Turn the app from a single chat screen into a native home for everything
Hermes does: chat (with history), the kanban team of profiles, scheduled
automations, and Hermes's memory and skills. At the same time, give the whole
app a cleaner, more modern look built on iOS 26 Liquid Glass.

## Non-goals

- Home Screen widgets, Live Activities and CarPlay keep their current look.
- No push notifications (sideloaded builds can't receive APNs). Screens refresh
  while they're visible.
- No new relay database tables. The existing `conversations` table already
  supports several conversations per user; it gains one nullable column,
  `activated_at`, added by the relay's existing migration step.
- No light mode. The app stays dark-first, but every color becomes a semantic
  token so light mode can be added later.

## Architecture

```
iOS app ──HTTPS──▶ Relay ──WebSocket RPC──▶ Connector ──HTTP (loopback)──▶ Hermes dashboard API
                                              └──files──▶ $HERMES_HOME/memories/*.md
```

### Hermes side (already running on the server)

The Hermes dashboard API runs inside the hermes-host container, bound to
`127.0.0.1:9119` (`HERMES_DASHBOARD=1`, `HERMES_DASHBOARD_HOST=127.0.0.1`), and
authenticates loopback requests with `X-Hermes-Session-Token:
$HERMES_DASHBOARD_SESSION_TOKEN`. It is never exposed publicly.

### Connector: two new RPC methods

1. `hermes.api`, a request proxy to the dashboard API.
   - Params: `{method, path, query?, body?}`.
   - Only these method + path combinations are allowed; everything else returns
     a `forbidden` error. Paths are matched after normalization, so `..` and
     encoded tricks are rejected.

     | Area | Allowed |
     |---|---|
     | Status | `GET /api/status`, `GET /api/model/info`, `GET /api/analytics/usage` |
     | Sessions | `GET /api/sessions`, `GET /api/sessions/search`, `GET /api/sessions/{id}`, `GET /api/sessions/{id}/messages` |
     | Profiles | `GET /api/profiles`, `GET/PUT /api/profiles/{name}/soul`, `PUT /api/profiles/{name}/description` |
     | Kanban | `GET /api/plugins/kanban/board`, `GET /api/plugins/kanban/assignees`, `GET /api/plugins/kanban/stats`, `GET/PATCH/DELETE /api/plugins/kanban/tasks/{id}`, `POST /api/plugins/kanban/tasks`, `POST /api/plugins/kanban/tasks/{id}/comments`, `POST /api/plugins/kanban/tasks/{id}/reassign`, `GET /api/plugins/kanban/tasks/{id}/log`, `GET /api/plugins/kanban/tasks/{id}/attachments`, `GET /api/plugins/kanban/attachments/{id}`, `POST /api/plugins/kanban/links` |
     | Cron | `GET/POST /api/cron/jobs`, `GET/PUT/DELETE /api/cron/jobs/{id}`, `POST /api/cron/jobs/{id}/{pause,resume,trigger}`, `GET /api/cron/jobs/{id}/runs`, `GET /api/cron/blueprints`, `POST /api/cron/blueprints/instantiate` |
     | Skills | `GET /api/skills`, `GET /api/skills/content`, `PUT /api/skills/toggle` |

   - Returns `{status, json}` for JSON responses. Non-JSON responses up to
     2 MB (such as attachments) return `{status, contentType, base64}`; larger
     ones return `too_large`.
   - Configuration comes from `HERMES_DASHBOARD_URL` (default
     `http://127.0.0.1:9119`) and `HERMES_DASHBOARD_SESSION_TOKEN`. If the token
     isn't set, the method returns `unavailable`.
2. `memory.read` and `memory.write` read and write `MEMORY.md` ("Hermes's
   notes") and `USER.md` ("About you") in `$HERMES_HOME/memories/`, for the
   default profile. Writes are capped at 64 KB and are atomic (temporary file,
   then rename).

### Relay: new endpoints (all need a paired-phone access token)

| Endpoint | Purpose |
|---|---|
| `GET/POST/PUT/PATCH/DELETE /v1/hermes/api/{path:path}` | Forwards to `hermes.api`, with a 30 s timeout. Returns 503 `host_offline` when no connector is connected. |
| `GET /v1/hermes/memory`, `PUT /v1/hermes/memory/{kind}` | Forwards to `memory.read` / `memory.write` |
| `GET /v1/conversations` | Lists non-archived conversations: `id, title, preview, lastMessageAt, isCurrent` |
| `POST /v1/conversations` | Starts a new conversation and makes it current |
| `POST /v1/conversations/{id}/activate` | Makes a past conversation current |
| `PATCH /v1/conversations/{id}` | Renames a conversation |
| `DELETE /v1/conversations/{id}` | Archives a conversation |

"Current" becomes the non-archived conversation the user activated most
recently (`activated_at`, falling back to `created_at`), so a reply arriving in
an older chat never switches you back to it. Existing endpoints
(`/v1/conversations/current`, `/v1/messages`, clear) keep working unchanged,
so old app builds don't break. Clear still gives you an empty conversation,
even when older ones exist. A conversation's title is set from its first user
message (whitespace collapsed, at most 60 characters) unless it has been
renamed.

### App: data layer

This follows the existing pattern of a protocol, a Live implementation, a Mock
implementation and an `@Observable` store:

- A single `WorkspaceTransport` protocol with `LiveWorkspaceTransport` (the
  relay, through `RelayAPIClient`, with token refresh) and
  `MockWorkspaceTransport` (serves fixtures recorded from the live server; used
  when `UITEST_PAIRING_MODE=mock`). A typed `HermesWorkspaceAPI` sits on top.
- Stores: `TeamStore` (board, assignees, task detail, actions),
  `AutomationsStore` (jobs, runs, blueprints), `LibraryStore` (memory, skills,
  personas), `ConversationsStore` (history, new chat, switching).
- Models are small `Decodable` structs that ignore unknown keys, so a Hermes
  upgrade that adds fields doesn't break decoding.
- Stores refresh when their tab appears and every 10 s while a tab showing live
  work (Team) is visible. When the host is offline, a store keeps its last data
  and shows an offline banner.

## Navigation

The app uses a native iOS 26 `TabView` with the Liquid Glass tab bar:

1. **Chat**: the conversation.
2. **Team**: the kanban team.
3. **Automations**: scheduled jobs.
4. **Library**: memory and skills.

Settings opens as a sheet from the avatar button at the top left of Chat.
Voice mode stays a full-screen cover, opened from the composer.

## Screens

### Chat

- **Top bar:** the avatar (opens Settings) on the left; a title button in the
  middle showing the conversation title, which opens **History**; a
  new-chat button on the right. The model and context ring move to a compact
  chip under the title.
- **Messages:** assistant replies are full width with no bubble. User messages
  are right-aligned tinted pills. Tool activity is a compact collapsible row
  of chips. Code blocks, diffs and images keep their current renderers,
  restyled.
- **Empty state:** a greeting, a live team strip ("2 working · 1 needs you",
  tapping it opens Team), and four starter cards that fill the composer:
  Research, Do it on the web, Automate, Remember.
- **Composer:** a Liquid Glass bar with attach, text, and a voice/send button,
  with the existing slash-command menu. An "Assign" chip opens a role picker;
  sending with a role selected creates a kanban task for that role instead of
  a chat message, and shows a confirmation toast that links to the task.
- **History sheet:** conversations grouped by Today / This week / Earlier, with
  search and swipe actions to rename or delete. Tapping a conversation switches
  to it.

### Team

- **Header:** a horizontal strip of role avatars (chief of staff, researcher,
  operator, coder, reviewer, plus any new profile) with a live dot for working
  and a count badge. Tapping an avatar filters the list. A long press opens the
  role sheet.
- **Sections:** Needs you (blocked, plus review items waiting on a human),
  Working (running), Up next (triage, todo, ready, scheduled), and Done (the
  last 20, with archive).
- **Task card:** title, role avatar, status pill, relative age, and the first
  line of the latest summary. Running cards show a subtle animated progress
  shimmer.
- **Task detail:** status header; result or summary (rendered markdown);
  brief (the body); activity (events, runs, comments) as a timeline; and
  attachments (text and markdown shown inline, images previewed). Actions:
  Reply and unblock (comment, then set status to ready), Reassign, Mark done,
  Delete. The live log is available from a "Worker log" row.
- **New task sheet:** title, details, a role picker showing each role's
  description, and a "Have the reviewer check it" toggle, which also creates a
  linked reviewer task that waits on the first.
- **Role sheet:** the role's description, model, and task counts, with editing
  for the description and persona (SOUL.md).

### Automations

- **List:** each job shows its name, a human-readable schedule, next run, last
  run status, and a pause toggle. Empty state: blueprint cards.
- **New automation:** choose a blueprint (a form generated from the
  blueprint's fields) or Custom: what should Hermes do, when (presets for every
  morning, every hour, weekdays at, weekly, plus a custom cron expression), and
  which role runs it. Delivery defaults to `local`, since results are read in
  the app.
- **Job detail:** the prompt, the schedule, a runs list whose items open the
  output (markdown), and Run now, Pause/Resume and Delete.

### Library

A segmented control with two views:

- **Memory:** two cards, "About you" (`USER.md`) and "Hermes's notes"
  (`MEMORY.md`). Each has a view mode and an edit mode (a monospaced editor
  with save).
- **Skills:** a searchable list grouped by category, with an enable toggle and
  usage count. Tapping a skill shows its content.

### Settings (sheet)

Settings is reorganized into sections:

- **Hermes:** host status, version, model and context, and usage/cost for the
  last 7 days.
- **Connection:** relay and re-pair.
- **Permissions & sensors.**
- **Voice.**
- **About.**

This keeps the existing settings and moves them into the new layout.

## Visual system

- **Background:** layered near-black (`#0B0B0D`, with raised surfaces at
  `#16161A`) and a soft amber glow at the top of each tab. This replaces the
  flat `#2D2D2B` charcoal.
- **Brand:** Hermes amber `#FFBF00`, used sparingly for primary actions, live
  states and focus.
- **Glass:** iOS 26 `glassEffect` on the tab bar, composer, floating buttons
  and toasts. Content cards use solid raised surfaces with hairline borders at
  6% white, so text stays readable.
- **Role identity:** a color and SF Symbol per role, shared by avatars, task
  cards and pills. Unknown roles get a stable color derived from their name.

  | Role | Color | Symbol |
  |---|---|---|
  | chief of staff (default) | amber | `sparkles` |
  | researcher | sky `#5AC8FA` | `magnifyingglass` |
  | operator | green `#34C759` | `safari` |
  | coder | violet `#AF7BFF` | `chevron.left.forwardslash.chevron.right` |
  | reviewer | coral `#FF7A6B` | `checkmark.seal` |

- **Type:** SF Pro. Large titles and numbers use the rounded design; body text
  uses dynamic type throughout.
- **Motion:** spring transitions from the existing `Design.Motion` tokens, a
  breathing live dot for working states, and matched-geometry transitions from
  card to detail where cheap.
- **Tokens:** `Design.swift` gains semantic color tokens (`canvas`, `surface`,
  `surfaceRaised`, `hairline`, `textPrimary`, `textSecondary`, `textTertiary`,
  `success`, `warning`, `danger`) and `RoleStyle`. Existing token names remain
  as aliases, so untouched screens keep compiling.

## Error handling

- Relay 503 `host_offline`: an inline banner reading "Hermes is offline",
  cached data kept, and retry on pull-to-refresh.
- `forbidden` or 4xx from `hermes.api`: a toast showing the server's message.
  Nothing is retried automatically.
- Destructive actions (delete a task, a job, or a conversation) ask for
  confirmation.
- Decoding failures are logged, and the item is skipped rather than failing
  the whole list.

## Testing

- **Connector (pytest):** the allowlist accepts every documented route and
  rejects traversal, unlisted methods and unlisted paths; the proxy passes the
  token header, and handles JSON versus binary responses, oversize responses
  and a missing token; memory read/write round-trips, including the size cap.
- **Relay (pytest):** conversation list, create, activate, rename and archive,
  while current-conversation behavior stays intact; the proxy endpoints
  forward and map offline hosts to 503.
- **App (XCTest):** model decoding against fixtures captured from the live
  server; store logic (grouping the board into sections, bucketing history,
  building schedules from presets) against the mock service.
- **Simulator:** build and run in mock mode, and screenshot every tab and main
  sheet to check layout.
- **Live:** deploy the connector and relay, then call each proxied endpoint
  through the relay with a real phone token.

## Delivery

The work ships in this order, each step building and passing its tests before
the next starts:

1. The backend: connector RPCs, relay endpoints and tests.
2. Design tokens and the tab shell.
3. Team.
4. Chat restyle and history.
5. Automations.
6. Library.
7. Settings.
8. A new unsigned IPA.
