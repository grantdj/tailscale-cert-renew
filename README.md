# tailscale-cert-renew

Small systemd-based helper to keep a Tailscale TLS certificate refreshed on a Linux host.

It installs:

- `renew-tailscale-cert.sh` into `/usr/local/sbin/`
- `check-tailscale-cert.sh` into `/usr/local/sbin/`
- `renew-tailscale-cert.service` into `/etc/systemd/system/`
- `renew-tailscale-cert.timer` into `/etc/systemd/system/`
- `/etc/default/renew-tailscale-cert` as the runtime config file

The timer runs every two months and the script asks `tailscale cert` to renew only when the current certificate has less than 30 days remaining.

## Requirements

- Linux system using `systemd`
- `tailscaled` installed and running
- `tailscale cert` available at `/usr/bin/tailscale`
- A MagicDNS / Tailscale HTTPS name that is eligible for `tailscale cert`

## Config

After install, edit `/etc/default/renew-tailscale-cert`:

```sh
TS_CERT_NAME=host.example.ts.net
CERT_FILE=/etc/ssl/cert.crt
KEY_FILE=/etc/ssl/cert.key
OWNER_USER=root
OWNER_GROUP=root
CHECK_SERVER_HOST=
CHECK_SERVER_PORT=443
CHECK_SERVER_SNI=
CHECK_TIMEOUT_SECONDS=5
```

Notes:

- `TS_CERT_NAME` must be the exact Tailscale DNS name you want the certificate for.
- `CERT_FILE` and `KEY_FILE` are where the certificate and private key will be written.
- The script sets the key to `0600` and the certificate to `0644`.
- `CHECK_SERVER_HOST`, if set, makes the check script connect to the running UI or proxy and compare the served certificate to the installed file.
- `CHECK_SERVER_PORT` defaults to `443`.
- `CHECK_SERVER_SNI` defaults to `TS_CERT_NAME`, then `CHECK_SERVER_HOST`.

## Install

```sh
./install.sh
sudoedit /etc/default/renew-tailscale-cert
sudo systemctl start renew-tailscale-cert.service
```

The installer enables and starts `renew-tailscale-cert.timer`.

Re-run the installer after updating this repo if you want the new check script copied into `/usr/local/sbin/`.

## Verify

Check the one-shot service:

```sh
systemctl status renew-tailscale-cert.service --no-pager
journalctl -u renew-tailscale-cert.service --no-pager
```

Check the timer:

```sh
systemctl status renew-tailscale-cert.timer --no-pager
systemctl list-timers renew-tailscale-cert.timer --no-pager
```

Check the installed certificate on disk:

```sh
sudo /usr/local/sbin/check-tailscale-cert.sh
```

If you set `CHECK_SERVER_HOST`, the same command also compares the installed certificate to the certificate currently served by the UI. A mismatch usually means the UI, reverse proxy, or terminating service has not reloaded the new certificate yet.

## Files

- `renew-tailscale-cert.sh`: runs `tailscale cert` and fixes file ownership and permissions
- `check-tailscale-cert.sh`: validates the installed certificate and can compare it with the live HTTPS endpoint
- `renew-tailscale-cert.service`: one-shot systemd unit
- `renew-tailscale-cert.timer`: recurring schedule
- `install.sh`: installs the script, units, and default config
