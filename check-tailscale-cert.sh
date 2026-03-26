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

: "${CERT_FILE:=/etc/ssl/cert.crt}"
: "${KEY_FILE:=/etc/ssl/cert.key}"
: "${CHECK_SERVER_PORT:=443}"
: "${CHECK_TIMEOUT_SECONDS:=5}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required but was not found in PATH" >&2
  exit 1
fi

if [ ! -f "${CERT_FILE}" ]; then
  echo "Certificate file not found: ${CERT_FILE}" >&2
  exit 1
fi

print_cert_summary() {
  local cert_path="$1"

  echo "Installed certificate: ${cert_path}"
  openssl x509 -in "${cert_path}" -noout \
    -subject \
    -issuer \
    -startdate \
    -enddate \
    -serial \
    -fingerprint -sha256
}

check_local_certificate() {
  local cert_path="$1"
  local host_name="${2:-}"

  if ! openssl x509 -in "${cert_path}" -noout >/dev/null 2>&1; then
    echo "Certificate file is not a valid X.509 PEM: ${cert_path}" >&2
    return 1
  fi

  print_cert_summary "${cert_path}"

  if openssl x509 -in "${cert_path}" -noout -checkend 0 >/dev/null 2>&1; then
    echo "Status: certificate is currently valid."
  else
    echo "Status: certificate is expired or not yet valid." >&2
    return 1
  fi

  if [ -n "${host_name}" ]; then
    if openssl verify -verify_hostname "${host_name}" -CAfile "${cert_path}" "${cert_path}" >/dev/null 2>&1; then
      echo "Hostname: certificate matches ${host_name}."
    else
      echo "Hostname: certificate does not match ${host_name}." >&2
      return 1
    fi
  fi
}

remote_cert_pem() {
  local host="$1"
  local port="$2"
  local sni="$3"

  timeout "${CHECK_TIMEOUT_SECONDS}" \
    openssl s_client \
      -connect "${host}:${port}" \
      -servername "${sni}" \
      -showcerts </dev/null 2>/dev/null |
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' |
    awk '
      BEGIN {capture=0}
      /-----BEGIN CERTIFICATE-----/ {
        if (capture == 0) {
          capture=1
        }
      }
      capture == 1 {print}
      /-----END CERTIFICATE-----/ {
        if (capture == 1) {
          exit
        }
      }
    '
}

compare_with_served_certificate() {
  local local_cert="$1"
  local host="$2"
  local port="$3"
  local sni="$4"
  local served_cert
  local local_fp
  local served_fp

  served_cert="$(remote_cert_pem "${host}" "${port}" "${sni}")"
  if [ -z "${served_cert}" ]; then
    echo "Served certificate: unable to read a certificate from ${host}:${port}" >&2
    return 1
  fi

  if ! served_fp="$(printf '%s\n' "${served_cert}" | openssl x509 -noout -fingerprint -sha256 2>/dev/null)"; then
    echo "Served certificate: failed to parse certificate from ${host}:${port}" >&2
    return 1
  fi

  local_fp="$(openssl x509 -in "${local_cert}" -noout -fingerprint -sha256)"

  echo
  echo "Served certificate: ${host}:${port}"
  printf '%s\n' "${served_cert}" | openssl x509 -noout \
    -subject \
    -issuer \
    -startdate \
    -enddate \
    -serial \
    -fingerprint -sha256

  if [ "${local_fp}" = "${served_fp}" ]; then
    echo "Match: the served certificate matches the installed certificate."
  else
    echo "Match: the served certificate does not match the installed certificate." >&2
    echo "The UI or proxy may still be using the previous certificate and may need a reload or restart." >&2
    return 1
  fi
}

main() {
  local rc=0

  check_local_certificate "${CERT_FILE}" "${TS_CERT_NAME:-}" || rc=1

  if [ -n "${CHECK_SERVER_HOST:-}" ]; then
    compare_with_served_certificate \
      "${CERT_FILE}" \
      "${CHECK_SERVER_HOST}" \
      "${CHECK_SERVER_PORT}" \
      "${CHECK_SERVER_SNI:-${TS_CERT_NAME:-${CHECK_SERVER_HOST}}}" || rc=1
  fi

  exit "${rc}"
}

main "$@"
