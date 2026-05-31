# NanoBK Cloudflare Real Validation Guide

Step-by-step guide for validating NanoBK's Cloudflare automation with a real Cloudflare account.

## Prerequisites

- Completed VPS install (`/etc/nanobk/profile.current.json` exists)
- Node.js installed
- Wrangler CLI installed (`npm install -g wrangler` or use `npx wrangler`)
- Cloudflare account with Workers enabled
- Either a `workers.dev` subdomain or a custom domain on Cloudflare

## Step 1: Login to Cloudflare

```bash
wrangler login
wrangler whoami
```

On a remote VPS, copy the login URL to your local browser, finish authorization, then continue.

**Never enter your Cloudflare password into a script.**

## Step 2: Run Preflight

```bash
bash installer/install-cloudflare.sh --preflight
```

This checks: wrangler, login status, profile, Worker sources, and local env files.

## Step 3: Deploy nanok

```bash
bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://YOUR-NANOK.workers.dev \
  --force
```

This will:
1. Create a KV namespace
2. Generate SUB_TOKEN and ADMIN_TOKEN
3. Write `workers/nanok/wrangler.toml`
4. Set Worker secrets
5. Deploy the nanok Worker
6. Upload the profile to KV
7. Verify the deployment

## Step 4: Verify nanok

```bash
# Check local env
cat .cloudflare.local.env

# Verify admin endpoint
curl -sS "https://YOUR-NANOK.workers.dev/admin/current" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" | python3 -m json.tool

# Verify subscription
curl -sS "https://YOUR-NANOK.workers.dev/jb?token=YOUR_SUB_TOKEN"
```

The subscription should return valid Clash/Mihomo YAML with all four protocols.

## Step 5: Deploy nanob (without edgetunnel)

```bash
bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://YOUR-NANOK.workers.dev \
  --deploy-nanob \
  --nanob-route-url https://YOUR-NANOB.workers.dev \
  --create-nanob-geo-kv \
  --force
```

**Without edgetunnel, nanob returns the nanok primary subscription.** This is expected and correct behavior.

## Step 6: Verify nanob

```bash
# Check nanob local env
cat .nanob.local.env

# Verify nanob subscription
curl -sS "https://YOUR-NANOB.workers.dev/jb?token=YOUR_NANOB_TOKEN"
```

The YAML should contain all four protocols from the VPS nodes. If edgetunnel is not configured, you will only see VPS nodes — this is normal.

## Step 7: Connect Existing edgetunnel (Optional)

If you have an existing edgetunnel Worker:

```bash
bash installer/install-cloudflare.sh --yes \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://YOUR-NANOK.workers.dev \
  --deploy-nanob \
  --nanob-route-url https://YOUR-NANOB.workers.dev \
  --edge-host https://YOUR-EDGETUNNEL.workers.dev \
  --edge-sub-path "/sub?target=clash" \
  --edgetunnel-export-token "YOUR_EDGE_TOKEN" \
  --force
```

**edgetunnel is optional.** Without it, NanoBK is fully functional. With it, nanob appends backup nodes.

## Step 8: Import into Clash/Mihomo

Use the subscription URL:

```
https://YOUR-NANOB.workers.dev/jb?token=YOUR_NANOB_TOKEN
```

Or if using nanok directly:

```
https://YOUR-NANOK.workers.dev/jb?token=YOUR_SUB_TOKEN
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| wrangler not found | CLI not installed | `npm install -g wrangler` |
| wrangler not logged in | Not authenticated | `wrangler login` |
| KV namespace creation failed | API error or permission | Check Cloudflare account permissions |
| secret put failed | Wrong Worker name or config | Check `workers/nanok/wrangler.toml` |
| profile upload failed | Wrong admin token or URL | Check `.cloudflare.local.env` |
| admin current 401 | Wrong ADMIN_TOKEN | Re-deploy or check secret |
| subscription 401 | Wrong SUB_TOKEN | Re-deploy or check secret |
| YAML invalid | Profile has bad characters | Re-run VPS installer |
| nanob only returns VPS nodes | edgetunnel not configured | This is expected! nanob falls back to nanok primary |
| edgetunnel fetch failed | edgetunnel Worker down | nanob falls back to primary — subscription still works |

## Security Notes

- `.cloudflare.local.env` contains real tokens — never commit
- `.nanob.local.env` contains real tokens — never commit
- Use SSH tunnel for remote VPS Cloudflare operations
- edgetunnel export token is never written to `wrangler.toml`
- Profile validation rejects private key leakage before upload
