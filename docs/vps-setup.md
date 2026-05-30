# VPS Setup Guide

Deploy four proxy services on a Linux VPS using the one-click installer.

## Supported Systems

| Distro | Status |
|--------|--------|
| Debian 11+ | ✅ Primary support |
| Ubuntu 20.04+ | ✅ Primary support |
| Rocky / Alma Linux 9+ | ✅ Best effort |
| CentOS / RHEL 8+ | ✅ Best effort |
| Fedora | ✅ Best effort |
| macOS | ❌ Not supported |

Architecture: x86_64 (amd64) and aarch64 (arm64).

## Quick Install

```bash
sudo bash installer/install-vps.sh --yes \
  --domain proxy.example.com \
  --cert-mode existing \
  --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem
```

Or from GitHub (planned for v0.3):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/install-vps.sh) \
  --domain proxy.example.com --cert-mode existing \
  --cert-file /etc/ssl/fullchain.pem --key-file /etc/ssl/privkey.pem
```

## Dry-Run Preview

Preview all actions without modifying the system:

```bash
sudo bash installer/install-vps.sh --dry-run \
  --domain proxy.example.com \
  --cert-mode self-signed
```

## Certificate Modes

### `existing` (recommended for production)

Provide your own TLS certificate and key:

```bash
--cert-mode existing \
--cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
--key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem
```

Recommended certificate sources:
- **Let's Encrypt** (free, automated renewal)
- **Cloudflare Origin Certificate** (15-year validity)

### `self-signed` (testing only)

Generates a self-signed certificate. Clients will need `skip-cert-verify: true`.

```bash
--cert-mode self-signed --domain proxy.example.com
```

### `none`

No TLS certificates. Only VLESS Reality will work. HY2, TUIC, and Trojan require TLS.

```bash
--cert-mode none
```

⚠️ **Not recommended** — three of four protocols will be non-functional.

## Installer Options

| Option | Default | Description |
|--------|---------|-------------|
| `--dry-run` | off | Print actions without modifying system |
| `--yes` | off | Non-interactive mode |
| `--domain` | (required) | Domain for HY2/TUIC/Trojan |
| `--reality-servername` | `www.microsoft.com` | Reality camouflage SNI |
| `--vps-ip` | auto-detect | VPS public IP |
| `--email` | (none) | Email for cert requests |
| `--cert-mode` | `existing` | Certificate mode |
| `--cert-file` | (none) | Path to TLS cert |
| `--key-file` | (none) | Path to TLS key |
| `--install-dir` | `/opt/nanobk` | Installation directory |
| `--config-dir` | `/etc/nanobk` | Configuration directory |
| `--open-firewall` | off | Open firewall ports |
| `--force` | off | Overwrite existing config |

## Installed File Layout

```
/etc/nanobk/
  config.env                  # VPS config variables
  secrets.private.env         # All generated credentials (mode 600)
  profile.current.json        # Cloudflare KV profile
  profile.initial.json        # Initial profile backup
  hysteria/config.yaml
  tuic-v5-9443/config.json
  xray-reality-8443/config.json
  xray-trojan-2443/config.json
  tls/                        # Self-signed certs (if used)

/opt/nanobk/
  bin/rotate-keys.sh
  bin/healthcheck.sh
  backups/
  logs/

/etc/systemd/system/
  hysteria-server.service
  tuic-v5-9443.service
  xray-reality-8443.service
  xray-trojan-2443.service
```

## After Installation

1. **Deploy nanok Worker** on Cloudflare (see [cloudflare-setup.md](cloudflare-setup.md)).
2. **Upload profile**: copy `/etc/nanobk/profile.current.json` into KV key `profile:main`.
3. **Set secrets**: `SUB_TOKEN` and `ADMIN_TOKEN` on the Worker.
4. **Import subscription** URL into Clash/Mihomo client.

## Manual Setup

If you prefer manual setup, see the config templates in `vps/templates/` and systemd units in `vps/systemd/`. The installer uses `__PLACEHOLDER__` syntax in these templates.

## Key Rotation

After initial setup:

```bash
# Configure Cloudflare admin token first
cat > /root/.nanok-cf-admin.env <<'EOF'
ADMIN_TOKEN="YOUR_ADMIN_TOKEN"
ADMIN_CURRENT_URL="https://YOUR_WORKER_HOST/admin/current"
ADMIN_UPDATE_URL="https://YOUR_WORKER_HOST/admin/update"
EOF
chmod 600 /root/.nanok-cf-admin.env

# Rotate all credentials
bash /opt/nanobk/bin/rotate-keys.sh
```

## Health Check

```bash
bash /opt/nanobk/bin/healthcheck.sh
```

Checks services, ports, config files, profile JSON, and secrets file permissions.
