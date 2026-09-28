#!/bin/sh
# Boot script for the hermes-host container: seed Hermes config, register
# with the relay on first boot, then run the connector in the foreground.
set -eu

: "${HERMES_HOME:=/opt/data}"
: "${HERMES_MOBILE_RELAY_URL:?Set HERMES_MOBILE_RELAY_URL to the public relay /v1 URL}"
STATE_DIR="${HERMES_MOBILE_CONNECTOR_HOME:-$HERMES_HOME/.hermes-mobile}"

if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ "${HERMES_PROVIDER:-}" = "deepseek" ]; then
    echo "[hermes-host] WARNING: DEEPSEEK_API_KEY is not set; chats will fail until it is." >&2
fi

mkdir -p "$HERMES_HOME/skills" "${HERMES_WORKDIR:-$HERMES_HOME/workspace}" "$STATE_DIR"

# Keep the bundled hermes-ios skill in sync with the image.
rm -rf "$HERMES_HOME/skills/hermes-ios"
cp -R /opt/hermes-mobile/skills/hermes-ios "$HERMES_HOME/skills/"

# --- Team roles --------------------------------------------------------------
# The default profile (the one the iPhone app talks to) is the chief of staff;
# every other directory in roles/ becomes a named profile that picks up kanban
# tasks. SOUL.md files carrying the marker line are regenerated on each boot;
# delete the marker line in a profile's SOUL.md to keep your own edits.
ROLES_DIR=/opt/hermes-mobile/roles
UPSTREAM_SOUL=/opt/hermes/docker/SOUL.md
SOUL_MARKER="<!-- managed by hermes-host; delete this line to keep your own edits across redeploys -->"

seed_soul() {
    target=$1
    role_soul=$2
    if [ ! -f "$target" ] || [ "$(head -n 1 "$target")" = "$SOUL_MARKER" ] || cmp -s "$target" "$UPSTREAM_SOUL"; then
        { echo "$SOUL_MARKER"; cat "$UPSTREAM_SOUL"; printf '\n\n'; cat "$role_soul"; } > "$target"
    fi
}

seed_soul "$HERMES_HOME/SOUL.md" "$ROLES_DIR/default/SOUL.md"
hermes tools enable kanban >/dev/null 2>&1 || echo "[hermes-host] WARNING: could not enable kanban tools" >&2

for role_dir in "$ROLES_DIR"/*/; do
    role=$(basename "$role_dir")
    [ "$role" = "default" ] && continue
    if [ ! -d "$HERMES_HOME/profiles/$role" ]; then
        hermes profile create "$role" --clone --no-alias --description "$(cat "$role_dir/description")" \
            || { echo "[hermes-host] WARNING: could not create profile $role" >&2; continue; }
    fi
    seed_soul "$HERMES_HOME/profiles/$role/SOUL.md" "$role_dir/SOUL.md"
done

# Pin the model in every profile's config.yaml so `hermes` and the app agree.
python - <<'EOF'
import os
from pathlib import Path
from ruamel.yaml import YAML

home = Path(os.environ["HERMES_HOME"])
yaml = YAML()
for path in [home / "config.yaml", *sorted(home.glob("profiles/*/config.yaml"))]:
    config = (yaml.load(path.read_text(encoding="utf-8")) if path.exists() else None) or {}
    model = config.get("model")
    if not isinstance(model, dict):
        model = {}
        config["model"] = model
    model["provider"] = os.environ.get("HERMES_PROVIDER") or "deepseek"
    model["default"] = os.environ.get("HERMES_MODEL") or "deepseek-flash"
    # The upstream image seeds an OpenRouter base_url; it must match the provider.
    base_url = os.environ.get("HERMES_BASE_URL") or (
        "https://api.deepseek.com" if model["provider"] == "deepseek" else ""
    )
    if base_url:
        model["base_url"] = base_url
    else:
        model.pop("base_url", None)
    # Schedules and "today" follow the owner's zone, not the server's UTC.
    if os.environ.get("HERMES_TIMEZONE"):
        config["timezone"] = os.environ["HERMES_TIMEZONE"]
    # DeepSeek flash reads images itself; drop the Gemini vision pin an earlier
    # version of this script wrote. Gemini is only used to transcribe audio.
    auxiliary = config.get("auxiliary")
    if isinstance(auxiliary, dict) and isinstance(auxiliary.get("vision"), dict) \
            and auxiliary["vision"].get("provider") == "gemini":
        del auxiliary["vision"]
    # Audio transcription for every client (web UI, messaging apps, this app's
    # connector): Hermes runs `hermes-mobile transcribe`, which calls Gemini.
    stt = config.get("stt")
    if not isinstance(stt, dict):
        stt = {}
        config["stt"] = stt
    providers = stt.get("providers")
    if not isinstance(providers, dict):
        providers = {}
        stt["providers"] = providers
    if os.environ.get("GEMINI_API_KEY"):
        stt["provider"] = "gemini-flash"
        providers["gemini-flash"] = {
            "type": "command",
            "command": "/opt/hermes-mobile/.venv/bin/hermes-mobile transcribe {input_path} --output {output_path}",
            "env_passthrough": ["GEMINI_API_KEY", "HERMES_TRANSCRIBE_MODEL"],
            "timeout": 180,
        }
    elif stt.get("provider") == "gemini-flash":
        del stt["provider"]
    with path.open("w", encoding="utf-8") as handle:
        yaml.dump(config, handle)

# Workers spawned by the supervised gateway (kanban, cron) don't inherit the
# container environment, so mirror provider keys into every profile's .env.
# The Gemini key only goes to the default profile, whose gateway transcribes
# voice messages; Hermes never picks Gemini for anything else, since the main
# provider is set explicitly.
keys = {name: os.environ[name] for name in ("DEEPSEEK_API_KEY",) if os.environ.get(name)}
gemini = {"GEMINI_API_KEY": os.environ["GEMINI_API_KEY"]} if os.environ.get("GEMINI_API_KEY") else {}
for env_path in [home / ".env", *sorted(home.glob("profiles/*/.env"))]:
    wanted = {**keys, **gemini} if env_path == home / ".env" else keys
    lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
    lines = [line for line in lines if line.split("=", 1)[0].strip() not in {*keys, "GEMINI_API_KEY"}]
    lines += [f"{name}={value}" for name, value in wanted.items()]
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    env_path.chmod(0o600)
EOF

if [ ! -f "$STATE_DIR/state.json" ]; then
    attempt=1
    until hermes-mobile setup --relay-url "$HERMES_MOBILE_RELAY_URL"; do
        if [ "$attempt" -ge 10 ]; then
            echo "[hermes-host] setup failed after $attempt attempts" >&2
            exit 1
        fi
        echo "[hermes-host] setup failed (attempt $attempt); retrying in 15s" >&2
        attempt=$((attempt + 1))
        sleep 15
    done
fi

# --- Web UI ------------------------------------------------------------------
# hermes-webui gives browser (and Hermex) access to this same Hermes. It's
# public through a Railway domain, so it only starts with a password set.
if [ -n "${HERMES_WEBUI_PASSWORD:-}" ]; then
    mkdir -p "$HERMES_HOME/webui"
    (
        cd /opt/hermes-webui || exit 1
        while true; do
            HERMES_HOME="$HERMES_HOME" \
            HERMES_WEBUI_AGENT_DIR=/opt/hermes \
            HERMES_WEBUI_PYTHON=/opt/hermes/.venv/bin/python \
            HERMES_WEBUI_HOST=0.0.0.0 \
            HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}" \
            HERMES_WEBUI_STATE_DIR="$HERMES_HOME/webui" \
                /opt/hermes/.venv/bin/python server.py || true
            echo "[hermes-host] web UI exited; restarting in 5s" >&2
            sleep 5
        done
    ) &
else
    echo "[hermes-host] HERMES_WEBUI_PASSWORD is not set; web UI disabled" >&2
fi

echo "[hermes-host] connector starting; pair with: railway ssh -s hermes-host -- hermes-mobile pair-phone"
exec hermes-mobile run
