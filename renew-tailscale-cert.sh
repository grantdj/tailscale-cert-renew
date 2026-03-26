#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Linux" ]; then
  echo "This script only supports Linux." >&2
  exit 1
fi

ENV_FILE="/etc/default/renew-tailscale-cert"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1091
  . "${ENV_FILE}"
fi

: "${TS_CERT_NAME:?Set TS_CERT_NAME in /etc/default/renew-tailscale-cert}"
: "${CERT_FILE:=/etc/ssl/cert.crt}"
: "${KEY_FILE:=/etc/ssl/cert.key}"
: "${OWNER_USER:=root}"
: "${OWNER_GROUP:=${OWNER_USER}}"

if ! command -v /usr/bin/tailscale >/dev/null 2>&1; then
  echo "tailscale binary not found at /usr/bin/tailscale" >&2
  exit 1
fi

mkdir -p "$(dirname "${CERT_FILE}")" "$(dirname "${KEY_FILE}")"

/usr/bin/tailscale cert \
  --cert-file "${CERT_FILE}" \
  --key-file "${KEY_FILE}" \
  --min-validity 720h \
  "${TS_CERT_NAME}"

chmod 0600 "${KEY_FILE}"
chmod 0644 "${CERT_FILE}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${KEY_FILE}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${CERT_FILE}"
