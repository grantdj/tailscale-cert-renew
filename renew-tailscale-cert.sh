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
# Command to reload the TLS-terminating server after the cert changes. Servers
# read the cert once at startup and keep serving the old one from memory, so
# without this a successful renewal is invisible to clients. Empty disables it.
: "${RELOAD_COMMAND:=}"

if ! command -v /usr/bin/tailscale >/dev/null 2>&1; then
  echo "tailscale binary not found at /usr/bin/tailscale" >&2
  exit 1
fi

if [ -n "${RELOAD_COMMAND}" ] && ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to detect cert changes for RELOAD_COMMAND" >&2
  exit 1
fi

# SHA-256 fingerprint of the installed cert, or empty if it is missing.
cert_fingerprint() {
  [ -f "$1" ] || return 0
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null || true
}

mkdir -p "$(dirname "${CERT_FILE}")" "$(dirname "${KEY_FILE}")"

fingerprint_before="$(cert_fingerprint "${CERT_FILE}")"

/usr/bin/tailscale cert \
  --cert-file "${CERT_FILE}" \
  --key-file "${KEY_FILE}" \
  --min-validity 720h \
  "${TS_CERT_NAME}"

chmod 0600 "${KEY_FILE}"
chmod 0644 "${CERT_FILE}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${KEY_FILE}"
chown "${OWNER_USER}:${OWNER_GROUP}" "${CERT_FILE}"

fingerprint_after="$(cert_fingerprint "${CERT_FILE}")"

# Most runs are a no-op (the cert is still outside the renewal window), so only
# reload when the cert on disk actually changed.
if [ "${fingerprint_before}" = "${fingerprint_after}" ]; then
  echo "Certificate unchanged; not reloading."
elif [ -z "${RELOAD_COMMAND}" ]; then
  echo "Certificate changed; RELOAD_COMMAND is unset so the server was not reloaded." >&2
  echo "The server may keep serving the previous certificate until it is reloaded." >&2
else
  echo "Certificate changed; running: ${RELOAD_COMMAND}"
  # shellcheck disable=SC2086
  ${RELOAD_COMMAND}
fi
