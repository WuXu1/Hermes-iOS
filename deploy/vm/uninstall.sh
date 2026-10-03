#!/usr/bin/env bash
# Undo install.sh: stop and remove the services, generated Caddy config and relay user.
# Phone-context entries are removed from the agents' configs; restart hermes-gateway afterwards.
# Caddy itself is removed only if install.sh installed it.
# --keep-data keeps /var/lib/hermes-mobile-relay, /data/.hermes-mobile and the hermes-relay user.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
KEEP_DATA=0
case "${1:-}" in
  "") ;;
  --keep-data) KEEP_DATA=1 ;;
  *) echo "usage: uninstall.sh [--keep-data]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "usage: uninstall.sh [--keep-data]" >&2; exit 2; }

# Read what install.sh recorded before /etc/hermes-mobile is deleted.
CADDY_INSTALLED_BY_US=0
[[ -f /etc/hermes-mobile/.installed-caddy ]] && CADDY_INSTALLED_BY_US=1

if [[ -x /opt/hermes-mobile/connector-venv/bin/hermes-mobile ]]; then
  if ! sudo -u hermes env HERMES_HOME=/data/.hermes /opt/hermes-mobile/connector-venv/bin/hermes-mobile \
    configure-mcp --unregister --profiles default,assistant,coach; then
    echo "WARNING: could not remove the phone-context entries automatically." >&2
    echo "Remove the hermes_mobile entries from the default, assistant and coach agents' configs by hand." >&2
  fi
else
  echo "WARNING: connector not found; remove any hermes_mobile entries from the agents' configs by hand." >&2
fi

for unit in hermes-mobile-connector hermes-mobile-relay hermes-dashboard; do
  systemctl disable --now "$unit" 2>/dev/null || true
  rm -f "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload

if [[ $CADDY_INSTALLED_BY_US -eq 1 ]]; then
  systemctl disable --now caddy 2>/dev/null || true
  apt-get remove -y -q caddy || true
  rm -f /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg
fi
if [[ -f /etc/caddy/Caddyfile.bak-before-hermes-mobile ]]; then
  mv -f /etc/caddy/Caddyfile.bak-before-hermes-mobile /etc/caddy/Caddyfile
else
  rm -f /etc/caddy/Caddyfile
fi
if [[ $CADDY_INSTALLED_BY_US -eq 0 ]] && systemctl is-active --quiet caddy 2>/dev/null; then
  systemctl reload caddy || echo "WARNING: Caddy did not reload; check /etc/caddy/Caddyfile" >&2
fi

rm -f /usr/local/bin/hermes-mobile
rm -rf /opt/hermes-mobile /etc/hermes-mobile
if [[ $KEEP_DATA -eq 0 ]]; then
  rm -rf /var/lib/hermes-mobile-relay /data/.hermes-mobile
  if id hermes-relay >/dev/null 2>&1; then userdel hermes-relay || true; fi
fi

echo "Removed. Now restart the gateway (sudo systemctl restart hermes-gateway), then remove the"
echo "Azure firewall rules for 80/443 and the DNS label (see deploy/vm/README.md)."
