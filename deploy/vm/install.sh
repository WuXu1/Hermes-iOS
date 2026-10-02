#!/usr/bin/env bash
# Install the Hermes Mobile relay, connector, always-on dashboard API and Caddy on a VM
# that already runs Hermes as the `hermes` user (HERMES_HOME=/data/.hermes).
# Idempotent: safe to rerun after pulling a new version of the repo.
set -euo pipefail

DOMAIN="" EMAIL="" REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DOMAIN" && -n "$EMAIL" && -n "$REPO" ]] || { echo "usage: install.sh --domain <name> --email <email> --repo <checkout>" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
id hermes >/dev/null || { echo "the hermes user is missing" >&2; exit 1; }

HERMES_UID=$(id -u hermes)
UV=/data/.hermes/bin/uv
[[ -x "$UV" ]] || UV=$(command -v uv)

echo "== packages"
if ! command -v caddy >/dev/null; then
  apt-get update -q
  apt-get install -y -q debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q
  apt-get install -y -q caddy
fi

echo "== users and folders"
id hermes-relay >/dev/null 2>&1 || useradd --system --home /var/lib/hermes-mobile-relay --shell /usr/sbin/nologin hermes-relay
install -d -o hermes-relay -g hermes-relay -m 0750 /var/lib/hermes-mobile-relay
install -d -o root -g root -m 0755 /opt/hermes-mobile /etc/hermes-mobile
install -d -o hermes -g hermes -m 0700 /data/.hermes-mobile

echo "== code"
rsync -a --delete --exclude .venv --exclude tests "$REPO/relay/" /opt/hermes-mobile/relay/
rsync -a --delete --exclude .venv --exclude tests "$REPO/connector/" /opt/hermes-mobile/connector/
UV_PYTHON_INSTALL_DIR=/opt/hermes-mobile/python "$UV" venv --python 3.12 /opt/hermes-mobile/relay-venv --allow-existing
"$UV" pip install --python /opt/hermes-mobile/relay-venv/bin/python /opt/hermes-mobile/relay
UV_PYTHON_INSTALL_DIR=/opt/hermes-mobile/python "$UV" venv --python 3.12 /opt/hermes-mobile/connector-venv --allow-existing
"$UV" pip install --python /opt/hermes-mobile/connector-venv/bin/python /opt/hermes-mobile/connector
chmod -R a+rX /opt/hermes-mobile

echo "== secrets (generated once, never printed)"
secret() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
if [[ ! -f /etc/hermes-mobile/dashboard.env ]]; then
  umask 077
  DASH=$(secret); SETUP=$(secret); INTERNAL=$(secret)
  printf 'HERMES_DASHBOARD_SESSION_TOKEN=%s\n' "$DASH" > /etc/hermes-mobile/dashboard.env
  cat > /etc/hermes-mobile/relay.env <<ENVEOF
RELAY_ENVIRONMENT=production
HERMES_ADAPTER=connector
PUBLIC_BASE_URL=https://$DOMAIN/v1
DATABASE_URL=sqlite:////var/lib/hermes-mobile-relay/relay.db
INTERNAL_API_KEY=$INTERNAL
CONNECTOR_SETUP_SECRET=$SETUP
CONNECTOR_SYNC_WAIT_SECONDS=25
CONNECTOR_JOB_LEASE_SECONDS=960
ENVEOF
  cat > /etc/hermes-mobile/connector.env <<ENVEOF
HERMES_DASHBOARD_SESSION_TOKEN=$DASH
CONNECTOR_SETUP_SECRET=$SETUP
HERMES_CHAT_TIMEOUT_SECONDS=900
ENVEOF
fi
chown root:root /etc/hermes-mobile/*.env
chmod 0600 /etc/hermes-mobile/*.env
sed -i "s#^PUBLIC_BASE_URL=.*#PUBLIC_BASE_URL=https://$DOMAIN/v1#" /etc/hermes-mobile/relay.env

echo "== services"
install -m 0644 "$REPO/deploy/vm/hermes-dashboard.service" /etc/systemd/system/
install -m 0644 "$REPO/deploy/vm/hermes-mobile-relay.service" /etc/systemd/system/
sed "s#/run/user/1001#/run/user/$HERMES_UID#g" "$REPO/deploy/vm/hermes-mobile-connector.service" > /etc/systemd/system/hermes-mobile-connector.service
sed -e "s#__DOMAIN__#$DOMAIN#g" -e "s#__EMAIL__#$EMAIL#g" "$REPO/deploy/vm/Caddyfile.template" > /etc/caddy/Caddyfile
ln -sf /opt/hermes-mobile/connector-venv/bin/hermes-mobile /usr/local/bin/hermes-mobile
systemctl daemon-reload
systemctl enable --now hermes-dashboard hermes-mobile-relay
systemctl reload-or-restart caddy

echo "== connector registration (first run only)"
if [[ ! -f /data/.hermes-mobile/state.json ]]; then
  # The env file holds only KEY=value lines with URL-safe values, so word splitting is safe here.
  # shellcheck disable=SC2046
  sudo -u hermes env $(grep -v '^#' /etc/hermes-mobile/connector.env | xargs) \
    HERMES_HOME=/data/.hermes HERMES_MOBILE_CONNECTOR_HOME=/data/.hermes-mobile \
    HERMES_COMMAND=/home/hermes/.local/bin/hermes \
    /opt/hermes-mobile/connector-venv/bin/hermes-mobile setup --relay-url http://127.0.0.1:8000/v1 --skip-mcp
fi
systemctl enable --now hermes-mobile-connector

echo "== done. Next: register phone context (needs a gateway restart) and pair a phone; see deploy/vm/README.md"
