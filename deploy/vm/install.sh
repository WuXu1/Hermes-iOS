#!/usr/bin/env bash
# Install the Hermes Mobile relay, connector, always-on dashboard API and Caddy on a VM
# that already runs Hermes as the `hermes` user (HERMES_HOME=/data/.hermes).
# The phone reaches the relay over Tailscale: `tailscale serve` (HTTPS :443, tailnet only)
# forwards to Caddy on 127.0.0.1:8080, which forwards to the relay on 127.0.0.1:8000.
# Idempotent: safe to rerun after pulling a new version of the repo.
set -euo pipefail

REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" ]] || { echo "usage: install.sh --repo <checkout>" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
id hermes >/dev/null || { echo "the hermes user is missing" >&2; exit 1; }
for tool in rsync python3 curl; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool (apt-get install $tool)" >&2; exit 1; }
done
command -v tailscale >/dev/null || { echo "tailscale is not installed; install it and join the tailnet first" >&2; exit 1; }
TS_JSON=$(tailscale status --json 2>/dev/null || true)
DOMAIN=$(printf '%s' "$TS_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("BackendState") != "Running" or not d.get("CertDomains"):
    sys.exit(1)
print((d.get("Self") or {}).get("DNSName", "").rstrip("."))
' 2>/dev/null || true)
[[ -n "$DOMAIN" ]] || { echo "tailscale is not Running, or HTTPS certificates are not enabled: enable MagicDNS + HTTPS certificates in the Tailscale admin console (DNS) and check 'tailscale status'" >&2; exit 1; }
[[ $DOMAIN =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || { echo "the Tailscale name '$DOMAIN' contains unexpected characters" >&2; exit 1; }
# Refuse to start if another program already listens on one of our loopback ports
# (9119 is left alone: Hermes Desktop's backend uses it). A rerun is fine: then our own unit owns the port.
for pair in 8000:hermes-mobile-relay 8080:caddy 9120:hermes-dashboard; do
  port=${pair%%:*} unit=${pair#*:}
  if ss -Hltn "sport = :$port" | grep -q . && ! systemctl is-active --quiet "$unit"; then
    echo "port $port is already in use by another program; free it before installing" >&2; exit 1
  fi
done
[[ $DOMAIN == *.ts.net ]] || { echo "the Tailscale name '$DOMAIN' does not end in .ts.net; enable MagicDNS for the tailnet (admin console, DNS)" >&2; exit 1; }
[[ -d "$REPO/relay" && -d "$REPO/connector" && -d "$REPO/deploy/vm" ]] || { echo "--repo is not a Hermes-iOS checkout" >&2; exit 1; }

HERMES_UID=$(id -u hermes)
UV=/data/.hermes/bin/uv
[[ -x "$UV" ]] || UV=$(command -v uv || true)
[[ -n "$UV" && -x "$UV" ]] || { echo "uv not found (expected /data/.hermes/bin/uv or on PATH)" >&2; exit 1; }

echo "== packages"
install -d -o root -g root -m 0755 /etc/hermes-mobile
if ! command -v caddy >/dev/null; then
  touch /etc/hermes-mobile/.installed-caddy
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
chown -R hermes-relay:hermes-relay /var/lib/hermes-mobile-relay
install -d -o root -g root -m 0755 /opt/hermes-mobile /etc/hermes-mobile
install -d -o hermes -g hermes -m 0700 /data/.hermes-mobile

echo "== code"
rsync -a --delete --exclude .venv --exclude tests "$REPO/relay/" /opt/hermes-mobile/relay/
rsync -a --delete --exclude .venv --exclude tests "$REPO/connector/" /opt/hermes-mobile/connector/
UV_PYTHON_INSTALL_DIR=/opt/hermes-mobile/python "$UV" venv --python 3.12 /opt/hermes-mobile/relay-venv --allow-existing
"$UV" pip install --reinstall-package hermes-mobile-relay --python /opt/hermes-mobile/relay-venv/bin/python /opt/hermes-mobile/relay
UV_PYTHON_INSTALL_DIR=/opt/hermes-mobile/python "$UV" venv --python 3.12 /opt/hermes-mobile/connector-venv --allow-existing
# Connector dependencies come from its lockfile; the relay is installed unlocked.
(cd /opt/hermes-mobile/connector && "$UV" export --frozen --no-dev --no-emit-project --format requirements-txt) \
  | "$UV" pip install --python /opt/hermes-mobile/connector-venv/bin/python -r -
"$UV" pip install --reinstall-package hermes-mobile-connector --no-deps --python /opt/hermes-mobile/connector-venv/bin/python /opt/hermes-mobile/connector
chmod -R a+rX /opt/hermes-mobile

echo "== secrets (generated once, never printed)"
secret() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
if [[ ! -f /etc/hermes-mobile/dashboard.env && ! -f /etc/hermes-mobile/relay.env && ! -f /etc/hermes-mobile/connector.env ]]; then
  (
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
  )
fi
for f in dashboard relay connector; do
  [[ -f /etc/hermes-mobile/$f.env ]] || { echo "/etc/hermes-mobile/$f.env is missing but the others exist; remove all three to regenerate" >&2; exit 1; }
done
chown root:root /etc/hermes-mobile/*.env
chmod 0600 /etc/hermes-mobile/*.env
sed -i "s#^PUBLIC_BASE_URL=.*#PUBLIC_BASE_URL=https://$DOMAIN/v1#" /etc/hermes-mobile/relay.env

echo "== services"
install -m 0644 "$REPO/deploy/vm/hermes-dashboard.service" /etc/systemd/system/
install -m 0644 "$REPO/deploy/vm/hermes-mobile-relay.service" /etc/systemd/system/
sed "s#/run/user/1001#/run/user/$HERMES_UID#g" "$REPO/deploy/vm/hermes-mobile-connector.service" > /etc/systemd/system/hermes-mobile-connector.service
chmod 0644 /etc/systemd/system/hermes-mobile-connector.service
# Keep a pre-existing Caddyfile once, so uninstall.sh can restore it.
if [[ -f /etc/caddy/Caddyfile && ! -f /etc/caddy/Caddyfile.bak-before-hermes-mobile && ! -f /etc/hermes-mobile/.caddyfile-generated ]]; then
  cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-before-hermes-mobile
fi
CADDY_TMP=$(mktemp /etc/hermes-mobile/Caddyfile.XXXXXX)
trap 'rm -f "$CADDY_TMP"' EXIT
cp "$REPO/deploy/vm/Caddyfile.template" "$CADDY_TMP"
caddy validate --config "$CADDY_TMP" --adapter caddyfile >/dev/null || { echo "generated Caddyfile is invalid; /etc/caddy/Caddyfile left untouched" >&2; exit 1; }
chmod 0644 "$CADDY_TMP"
mv -f "$CADDY_TMP" /etc/caddy/Caddyfile
touch /etc/hermes-mobile/.caddyfile-generated
# `sudo -u hermes hermes-mobile ...` must see the same environment as the connector service
# (values mirror deploy/vm/hermes-mobile-connector.service).
rm -f /usr/local/bin/hermes-mobile  # an older install left a symlink here
cat > /usr/local/bin/hermes-mobile <<'WRAPEOF'
#!/bin/sh
export HERMES_HOME=/data/.hermes
export HERMES_MOBILE_CONNECTOR_HOME=/data/.hermes-mobile
export HERMES_MOBILE_RELAY_INTERNAL_URL=http://127.0.0.1:8000/v1
export HERMES_COMMAND=/home/hermes/.local/bin/hermes
export HERMES_WORKDIR=/data/workspace
export HERMES_DASHBOARD_URL=http://127.0.0.1:9120
export HERMES_MOBILE_MCP_PROFILES=default,assistant,coach
exec /opt/hermes-mobile/connector-venv/bin/hermes-mobile "$@"
WRAPEOF
chmod 0755 /usr/local/bin/hermes-mobile
systemctl daemon-reload
systemctl enable --now hermes-dashboard hermes-mobile-relay
systemctl reload-or-restart caddy

echo "== connector registration (first run only)"
if [[ ! -f /data/.hermes-mobile/state.json ]]; then
  echo "waiting for the relay"
  for _ in $(seq 30); do
    curl -fs http://127.0.0.1:8000/v1/health >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fs http://127.0.0.1:8000/v1/health >/dev/null 2>&1 || { echo "the relay did not answer on 127.0.0.1:8000 within 30s; see journalctl -u hermes-mobile-relay" >&2; exit 1; }
  systemd-run --wait --pipe --collect -p User=hermes -p EnvironmentFile=/etc/hermes-mobile/connector.env \
    -E HERMES_HOME=/data/.hermes -E HERMES_MOBILE_CONNECTOR_HOME=/data/.hermes-mobile \
    -E HERMES_COMMAND=/home/hermes/.local/bin/hermes \
    /opt/hermes-mobile/connector-venv/bin/hermes-mobile setup --relay-url http://127.0.0.1:8000/v1 --skip-mcp
fi
systemctl enable --now hermes-mobile-connector

echo "== tailscale serve (tailnet-only HTTPS -> Caddy on 127.0.0.1:8080)"
# Our config is exactly: HTTPS :443 on this machine's name, proxying to Caddy, no Funnel.
SERVE_CHECK='
import json, sys
dom, want = sys.argv[1], "http://127.0.0.1:8080"
cfg = json.load(sys.stdin) or {}
if not cfg:
    print("empty"); sys.exit(0)
web = cfg.get("Web") or {}
ok = (set(cfg) <= {"TCP", "Web"}
      and not cfg.get("AllowFunnel")
      and set(cfg.get("TCP", {})) == {"443"}
      and cfg["TCP"]["443"].get("HTTPS") is True
      and set(web) == {dom + ":443"}
      and set(web[dom + ":443"].get("Handlers", {})) == {"/"}
      and web[dom + ":443"]["Handlers"]["/"].get("Proxy") == want)
print("ours" if ok else "foreign")
'
SERVE_STATE=$(tailscale serve status --json 2>/dev/null | python3 -c "$SERVE_CHECK" "$DOMAIN" 2>/dev/null || echo unreadable)
case "$SERVE_STATE" in
  empty|ours) ;;
  *) echo "tailscale serve/funnel already has a configuration that is not Hermes Mobile's ($SERVE_STATE); not overwriting it." >&2
     echo "Review it with 'tailscale serve status', then remove it or add the route by hand: tailscale serve --bg --https=443 http://127.0.0.1:8080" >&2
     exit 1 ;;
esac
if [[ $SERVE_STATE == empty ]]; then
  tailscale serve --bg --https=443 http://127.0.0.1:8080
fi
touch /etc/hermes-mobile/.tailscale-serve-configured

echo "== done."
echo "Tailnet requirements: MagicDNS and HTTPS certificates must be enabled (Tailscale admin console, DNS)."
echo "The first HTTPS request to https://$DOMAIN may take a few seconds while the certificate is issued."
echo "Next: register phone context (needs a gateway restart) and pair a phone; see deploy/vm/README.md"
