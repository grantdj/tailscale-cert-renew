#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Linux" ]; then
  echo "This installer only supports Linux." >&2
  exit 1
fi

SCRIPT_SRC="./renew-tailscale-cert.sh"
SERVICE_SRC="./renew-tailscale-cert.service"
TIMER_SRC="./renew-tailscale-cert.timer"
ENV_SRC="./renew-tailscale-cert.env.example"

SCRIPT_DST="/usr/local/sbin/renew-tailscale-cert.sh"
SERVICE_DST="/etc/systemd/system/renew-tailscale-cert.service"
TIMER_DST="/etc/systemd/system/renew-tailscale-cert.timer"
ENV_DST="/etc/default/renew-tailscale-cert"

for f in "$SCRIPT_SRC" "$SERVICE_SRC" "$TIMER_SRC" "$ENV_SRC"; do
  if [ ! -f "$f" ]; then
    echo "Missing required file: $f" >&2
    exit 1
  fi
done

sudo install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"
sudo install -m 0644 "$SERVICE_SRC" "$SERVICE_DST"
sudo install -m 0644 "$TIMER_SRC" "$TIMER_DST"

if ! sudo test -f "$ENV_DST"; then
  sudo install -m 0644 "$ENV_SRC" "$ENV_DST"
fi

sudo systemctl daemon-reload
sudo systemctl enable --now renew-tailscale-cert.timer

echo
echo "Installed successfully."
echo
echo "Timer status:"
systemctl status renew-tailscale-cert.timer --no-pager
echo
echo "Next runs:"
systemctl list-timers renew-tailscale-cert.timer --no-pager
