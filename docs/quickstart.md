# Quick Start

> ⚠️ **v0.1 scaffold**: The one-click installers are not yet fully automated. This guide shows the planned flow and current manual steps.

## Prerequisites

- A Linux VPS (Ubuntu 20.04+ or Debian 11+ recommended)
- A domain name on Cloudflare
- Cloudflare Workers plan (free tier works)

## Step 1: Check VPS Environment

```bash
bash installer/doctor.sh
```

This checks:
- OS compatibility
- Required tools (curl, jq, python3, openssl, systemctl)
- Existing services and ports

## Step 2: Deploy VPS Proxy Services

### Option A: Automated (planned for v0.2)

```bash
sudo bash installer/install-vps.sh
```

### Option B: Manual

1. Install dependencies:
   ```bash
   apt-get update
   apt-get install -y curl jq python3 openssl uuid-runtime
   ```

2. Install proxy binaries:
   - [Hysteria2](https://github.com/apernet/hysteria)
   - [Xray-core](https://github.com/XTLS/Xray-core)
   - [tuic-server](https://github.com/EAimTY/tuic)

3. Generate initial credentials:
   ```bash
   HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
   TUIC_UUID=$(uuidgen)
   TUIC_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')
   TROJAN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
   REALITY_UUID=$(uuidgen)
   REALITY_SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
   KEYPAIR=$(xray x25519)
   REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Private key/ {print $2}')
   REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Public key/ {print $2}')
   ```

4. Copy and edit config templates from `vps/templates/` to their target paths.

5. Copy systemd service templates from `vps/systemd/` to `/etc/systemd/system/`.

6. Start services:
   ```bash
   systemctl daemon-reload
   systemctl enable --now hysteria-server.service
   systemctl enable --now tuic-v5-9443.service
   systemctl enable --now xray-reality-8443.service
   systemctl enable --now xray-trojan-2443.service
   ```

7. Verify:
   ```bash
   bash vps/scripts/healthcheck.sh
   ```

## Step 3: Deploy Cloudflare Workers

### Option A: Automated (planned for v0.3)

```bash
bash installer/install-cloudflare.sh
```

### Option B: Manual

1. Install Wrangler CLI:
   ```bash
   npm install -g wrangler
   wrangler login
   ```

2. Create KV namespaces:
   ```bash
   wrangler kv:namespace create SUB_STORE
   wrangler kv:namespace create NANOB_GEO_CACHE
   ```

3. Deploy nanok:
   ```bash
   cd workers/nanok
   # Edit wrangler.toml with your KV namespace ID
   cp wrangler.toml.example wrangler.toml
   # Edit wrangler.toml
   wrangler secret put SUB_TOKEN
   wrangler secret put ADMIN_TOKEN
   wrangler deploy
   ```

4. Initialize the KV profile:
   ```bash
   # Edit examples/profile.example.json with your actual credentials
   curl -X POST https://YOUR_NANOK_HOST/admin/update \
     -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     --data-binary @examples/profile.example.json
   ```

5. Deploy nanob (optional):
   ```bash
   cd workers/nanob
   cp wrangler.toml.example wrangler.toml
   # Edit wrangler.toml
   wrangler secret put NANOB_TOKEN
   wrangler secret put NANOK_SUB_TOKEN
   wrangler deploy
   ```

6. Attach custom domains in Cloudflare dashboard.

## Step 4: Configure VPS Admin Token

On your VPS, create the admin environment file:

```bash
cat > /root/.nanok-cf-admin.env <<'EOF'
ADMIN_TOKEN="YOUR_ADMIN_TOKEN"
ADMIN_CURRENT_URL="https://YOUR_NANOK_HOST/admin/current"
ADMIN_UPDATE_URL="https://YOUR_NANOK_HOST/admin/update"
EOF
chmod 600 /root/.nanok-cf-admin.env
```

## Step 5: Import Subscription

Use this URL in your Clash/Mihomo client:

```
https://YOUR_NANOB_HOST/jb?token=YOUR_NANOB_TOKEN
```

Or if using nanok directly:

```
https://YOUR_NANOK_HOST/jb?token=YOUR_SUB_TOKEN
```

See [client-import.md](../examples/client-import.md) for detailed client instructions.

## Step 6: Key Rotation

When you want to rotate all credentials:

```bash
sudo bash vps/scripts/rotate-keys.sh
```

This will:
1. Back up all configs
2. Generate new credentials
3. Update VPS services
4. Sync to Cloudflare KV
5. Verify everything works
6. Roll back on failure

The subscription URL never changes. Clients refresh to get new keys.
