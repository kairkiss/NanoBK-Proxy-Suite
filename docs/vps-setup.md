# VPS Setup Guide

Detailed guide for setting up the four proxy services on a Linux VPS.

## Supported Systems

- Ubuntu 20.04+ / Debian 11+
- CentOS 8+ / Rocky Linux 8+
- Any systemd-based Linux

## Architecture

Each proxy service runs as an independent systemd service:

| Service | Binary | Config Path | Port | Protocol |
|---------|--------|-------------|------|----------|
| hysteria-server.service | /usr/local/bin/hysteria | /etc/hysteria/config.yaml | 443 | UDP |
| tuic-v5-9443.service | /usr/local/bin/tuic-server | /etc/proxy-stack/tuic-v5-9443/config.json | 9443 | UDP |
| xray-reality-8443.service | /usr/local/bin/xray | /etc/proxy-stack/xray-reality-8443/config.json | 8443 | TCP |
| xray-trojan-2443.service | /usr/local/bin/xray | /etc/proxy-stack/xray-trojan-2443/config.json | 2443 | TCP |

## Install Dependencies

```bash
apt-get update
apt-get install -y curl jq python3 openssl uuid-runtime
```

## Install Proxy Binaries

### Hysteria2

```bash
# Download from https://github.com/apernet/hysteria/releases
# Place at /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria
```

### Xray-core

```bash
# Download from https://github.com/XTLS/Xray-core/releases
# Place at /usr/local/bin/xray
chmod +x /usr/local/bin/xray
```

### tuic-server

```bash
# Download from https://github.com/EAimTY/tuic/releases
# Place at /usr/local/bin/tuic-server
chmod +x /usr/local/bin/tuic-server
```

## Generate Initial Credentials

```bash
# HY2
HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')

# TUIC
TUIC_UUID=$(uuidgen)
TUIC_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')

# Reality
REALITY_UUID=$(uuidgen)
REALITY_SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
KEYPAIR=$(xray x25519)
REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Private key/ {print $2}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Public key/ {print $2}')

# Trojan
TROJAN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
```

## Configuration Templates

Copy and edit the templates from `vps/templates/`:

```bash
# Create directories
mkdir -p /etc/hysteria
mkdir -p /etc/proxy-stack/tuic-v5-9443
mkdir -p /etc/proxy-stack/xray-reality-8443
mkdir -p /etc/proxy-stack/xray-trojan-2443

# Copy and edit templates
cp vps/templates/hysteria2.config.yaml.tpl /etc/hysteria/config.yaml
cp vps/templates/tuic-v5.config.json.tpl /etc/proxy-stack/tuic-v5-9443/config.json
cp vps/templates/xray-reality.config.json.tpl /etc/proxy-stack/xray-reality-8443/config.json
cp vps/templates/xray-trojan.config.json.tpl /etc/proxy-stack/xray-trojan-2443/config.json

# Replace all REPLACE_WITH_* placeholders with actual values
```

## TLS Certificates

You need TLS certificates for HY2, TUIC, and Trojan. Options:

1. **Let's Encrypt** (recommended for domains):
   ```bash
   apt-get install -y certbot
   certbot certonly --standalone -d your-domain.com
   ```

2. **Cloudflare Origin Certificate** (for Cloudflare-proxied domains):
   - Go to Cloudflare Dashboard → SSL/TLS → Origin Server
   - Create certificate
   - Save cert and key to the appropriate paths

## Systemd Services

Copy service templates from `vps/systemd/` to `/etc/systemd/system/`:

```bash
cp vps/systemd/hysteria-server.service.tpl /etc/systemd/system/hysteria-server.service
cp vps/systemd/tuic-v5-9443.service.tpl /etc/systemd/system/tuic-v5-9443.service
cp vps/systemd/xray-reality-8443.service.tpl /etc/systemd/system/xray-reality-8443.service
cp vps/systemd/xray-trojan-2443.service.tpl /etc/systemd/system/xray-trojan-2443.service

systemctl daemon-reload
systemctl enable --now hysteria-server.service
systemctl enable --now tuic-v5-9443.service
systemctl enable --now xray-reality-8443.service
systemctl enable --now xray-trojan-2443.service
```

## Verify

```bash
# Check services
systemctl is-active hysteria-server.service
systemctl is-active tuic-v5-9443.service
systemctl is-active xray-reality-8443.service
systemctl is-active xray-trojan-2443.service

# Check ports
ss -ulnp | grep ':443'
ss -ulnp | grep ':9443'
ss -tlnp | grep ':8443'
ss -tlnp | grep ':2443'

# Or use the health check script
bash vps/scripts/healthcheck.sh
```

## Firewall

Ensure your firewall allows the proxy ports:

```bash
# UFW example
ufw allow 443/udp    # HY2
ufw allow 9443/udp   # TUIC
ufw allow 8443/tcp   # Reality
ufw allow 2443/tcp   # Trojan
```

## Key Rotation

After initial setup, configure the admin token and use the rotation script:

```bash
# Create admin env file
cat > /root/.nanok-cf-admin.env <<'EOF'
ADMIN_TOKEN="YOUR_ADMIN_TOKEN"
ADMIN_CURRENT_URL="https://YOUR_NANOK_HOST/admin/current"
ADMIN_UPDATE_URL="https://YOUR_NANOK_HOST/admin/update"
EOF
chmod 600 /root/.nanok-cf-admin.env

# Rotate keys
sudo bash vps/scripts/rotate-keys.sh
```
