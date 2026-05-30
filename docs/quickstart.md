# Quick Start

## One-Line Bootstrap (Recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
```

This downloads the repository and launches the interactive installer. You can also pass arguments:

```bash
# Show command templates
bash <(curl -fsSL ...) -- --mode commands

# Run diagnostics
bash <(curl -fsSL ...) -- --mode doctor

# Preview VPS deployment
bash <(curl -fsSL ...) -- --mode vps --dry-run
```

The bootstrap script only clones/updates the repository and starts `install.sh`. It does not directly deploy services or modify Cloudflare.

## Manual Setup

```bash
git clone https://github.com/kairkiss/NanoBK-Proxy-Suite.git
cd NanoBK-Proxy-Suite
bash installer/install.sh
```

The interactive menu guides you through VPS setup, Cloudflare deployment, key rotation, and testing.

Direct mode shortcuts:

```bash
bash installer/install.sh --mode doctor       # Environment check
bash installer/install.sh --mode vps           # VPS deployment
bash installer/install.sh --mode cloudflare    # Cloudflare deployment
bash installer/install.sh --mode commands      # Show command templates
bash installer/install.sh --mode test          # Run local tests
```

## Manual Setup

### Prerequisites

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

```bash
wrangler login

bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com
```

See [cloudflare-setup.md](cloudflare-setup.md) for all options and manual steps.

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
