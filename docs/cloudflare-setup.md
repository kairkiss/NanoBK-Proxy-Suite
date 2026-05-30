# Cloudflare Setup Guide

Detailed guide for deploying nanok and nanob Workers on Cloudflare.

## Prerequisites

- Cloudflare account
- Domain added to Cloudflare
- Node.js installed locally
- Wrangler CLI (`npm install -g wrangler`)

## Step 1: Authenticate Wrangler

```bash
wrangler login
```

## Step 2: Create KV Namespaces

```bash
# For nanok (profile storage)
wrangler kv:namespace create SUB_STORE
# Note the output: { binding = "SUB_STORE", id = "xxxxxxxx" }

# For nanob (geo cache)
wrangler kv:namespace create NANOB_GEO_CACHE
# Note the output: { binding = "NANOB_GEO_CACHE", id = "xxxxxxxx" }
```

## Step 3: Deploy nanok

```bash
cd workers/nanok

# Create wrangler.toml from example
cp wrangler.toml.example wrangler.toml

# Edit wrangler.toml:
# - Set KV namespace ID for SUB_STORE
# - Uncomment and set any custom vars

# Set secrets
wrangler secret put SUB_TOKEN
# Enter your subscription token

wrangler secret put ADMIN_TOKEN
# Enter your admin token (different from SUB_TOKEN!)

# Deploy
wrangler deploy
```

### Verify nanok

```bash
# Root page should show HTML status
curl https://YOUR_NANOK_HOST/

# Without token should return 404
curl -i https://YOUR_NANOK_HOST/jb

# With wrong token should return 404
curl -i https://YOUR_NANOK_HOST/jb?token=wrong

# With correct token should return YAML (after profile init)
curl -i https://YOUR_NANOK_HOST/jb?token=YOUR_SUB_TOKEN
```

## Step 4: Initialize KV Profile

```bash
# Edit the example profile with your actual VPS credentials
cp examples/profile.example.json /tmp/profile.json
# Edit /tmp/profile.json with real values

# Upload to KV via admin API
curl -X POST https://YOUR_NANOK_HOST/admin/update \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/profile.json

# Verify
curl -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  https://YOUR_NANOK_HOST/admin/current
```

## Step 5: Deploy nanob (Optional)

nanob is optional. If you only need the primary subscription, skip this step.

```bash
cd workers/nanob

# Create wrangler.toml from example
cp wrangler.toml.example wrangler.toml

# Edit wrangler.toml:
# - Set KV namespace ID for NANOB_GEO_CACHE

# Set secrets
wrangler secret put NANOB_TOKEN
# Enter your public aggregator token

wrangler secret put NANOK_SUB_TOKEN
# Enter the same value as SUB_TOKEN on nanok

# Optional: edgetunnel integration
wrangler secret put EDGETUNNEL_EXPORT_TOKEN
# Enter shared secret for edgetunnel (or skip if not using edgetunnel)

# Deploy
wrangler deploy
```

### Verify nanob

```bash
# With correct token should return merged YAML
curl -i https://YOUR_NANOB_HOST/jb?token=YOUR_NANOB_TOKEN
```

## Step 6: Attach Custom Domains

In the Cloudflare Dashboard:

1. Go to **Workers & Pages**.
2. Select your Worker.
3. Go to **Settings** → **Triggers** → **Custom Domains**.
4. Add your custom domain.

Or via CLI:

```bash
# nanok
wrangler domains add YOUR_NANOK_HOST

# nanob
wrangler domains add YOUR_NANOB_HOST
```

## Step 7: Configure VPS Admin Token

On your VPS, create the admin environment file:

```bash
cat > /root/.nanok-cf-admin.env <<'EOF'
ADMIN_TOKEN="YOUR_ADMIN_TOKEN"
ADMIN_CURRENT_URL="https://YOUR_NANOK_HOST/admin/current"
ADMIN_UPDATE_URL="https://YOUR_NANOK_HOST/admin/update"
EOF
chmod 600 /root/.nanok-cf-admin.env
```

## Token Summary

| Token | Set on | Purpose |
|-------|--------|---------|
| SUB_TOKEN | nanok | Public subscription access |
| ADMIN_TOKEN | nanok + VPS env | Private admin API |
| NANOB_TOKEN | nanob | Public aggregator access |
| NANOK_SUB_TOKEN | nanob | Fetch from nanok internally |
| EDGETUNNEL_EXPORT_TOKEN | nanob + edgetunnel | Shared internal auth (optional) |

## Worker Bindings Summary

### nanok

| Binding | Type | Value |
|---------|------|-------|
| SUB_STORE | KV namespace | Profile storage |
| SUB_TOKEN | Secret | Public subscription token |
| ADMIN_TOKEN | Secret | Admin API token |

### nanob

| Binding | Type | Value |
|---------|------|-------|
| NANOB_GEO_CACHE | KV namespace | Geo cache |
| NANOB_TOKEN | Secret | Public aggregator token |
| NANOK_SUB_TOKEN | Secret | Token to fetch nanok |
| EDGETUNNEL_EXPORT_TOKEN | Secret | Shared edgetunnel token (optional) |
