# Quick Start

## Prerequisites

- A Linux VPS (Debian 11+, Ubuntu 20.04+, or RHEL-family)
- A domain name (on Cloudflare recommended)
- A TLS certificate (Let's Encrypt or Cloudflare Origin Certificate)

## Step 1: Deploy VPS Proxy Services

```bash
sudo bash installer/install-vps.sh --yes \
  --domain proxy.example.com \
  --cert-mode existing \
  --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem
```

This installs and configures:
- **Hysteria2** (UDP 443)
- **TUIC v5** (UDP 9443)
- **VLESS Reality** (TCP 8443)
- **Trojan TLS** (TCP 2443)

And generates a Cloudflare-compatible profile at `/etc/nanobk/profile.current.json`.

To preview without changing anything:

```bash
sudo bash installer/install-vps.sh --dry-run \
  --domain proxy.example.com --cert-mode self-signed
```

## Step 2: Deploy nanok Worker

See [cloudflare-setup.md](cloudflare-setup.md) for detailed instructions.

Quick version:

1. Install Wrangler: `npm install -g wrangler && wrangler login`
2. Create KV: `wrangler kv:namespace create SUB_STORE`
3. Deploy: `cd workers/nanok && cp wrangler.toml.example wrangler.toml && wrangler deploy`
4. Set secrets: `wrangler secret put SUB_TOKEN` and `wrangler secret put ADMIN_TOKEN`
5. Upload profile via admin API:
   ```bash
   curl -X POST https://YOUR_WORKER/admin/update \
     -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     --data-binary @/etc/nanobk/profile.current.json
   ```

## Step 3: Import Subscription

Use this URL in Clash/Mihomo:

```
https://YOUR_WORKER_HOST/jb?token=YOUR_SUB_TOKEN
```

See [client-import.md](../examples/client-import.md) for client-specific instructions.

## Step 4: Optional Enhancements

- **nanob aggregator**: merges nanok + edgetunnel backup nodes (see [edgetunnel-optional.md](edgetunnel-optional.md))
- **Key rotation**: `bash /opt/nanobk/bin/rotate-keys.sh`
- **Health check**: `bash /opt/nanobk/bin/healthcheck.sh`

## Troubleshooting

See [troubleshooting.md](troubleshooting.md).
