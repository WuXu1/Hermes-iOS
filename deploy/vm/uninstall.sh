#!/usr/bin/env bash
# Undo install.sh: stop and remove the services, Caddy config and relay user.
# Phone-context entries are removed from the agents' configs; restart hermes-gateway afterwards.
# --keep-data keeps /var/lib/hermes-mobile-relay and /data/.hermes-mobile.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
KEEP_DATA=0
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=1

if [[ -x /opt/hermes-mobile/connector-venv/bin/hermes-mobile ]]; then
  sudo -u hermes env HERMES_HOME=/data/.hermes /opt/hermes-mobile/connector-venv/bin/hermes-mobile \
    configure-mcp --unregister --profiles default,assistant,coach || true
fi

for unit in hermes-mobile-connector hermes-mobile-relay hermes-dashboard; do
  systemctl disable --now "$unit" 2>/dev/null || true
  rm -f "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload

systemctl disable --now caddy 2>/dev/null || true
apt-get remove -y -q caddy || true
rm -f /etc/apt/sources.list.d/caddy-stable.list /usr/share/keyrings/caddy-stable-archive-keyring.gpg

rm -f /usr/local/bin/hermes-mobile
rm -rf /opt/hermes-mobile /etc/hermes-mobile
if [[ $KEEP_DATA -eq 0 ]]; then
  rm -rf /var/lib/hermes-mobile-relay /data/.hermes-mobile
fi
if id hermes-relay >/dev/null 2>&1; then userdel hermes-relay || true; fi

echo "Removed. Now restart the gateway (sudo systemctl restart hermes-gateway), then remove the"
echo "Azure firewall rules for 80/443 and the DNS label (see deploy/vm/README.md)."
