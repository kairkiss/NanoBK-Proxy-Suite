# Quick Start

**NanoBK Proxy Suite v1.6.2 — Unified Beginner Installer**

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

In `--dry-run` mode, the install.sh launch command shown is a preview — the repository has not been cloned yet. The actual flow is: clone → then launch install.sh.

## Unified CLI (nanobk)

After cloning, you can use the unified CLI:

```bash
bash bin/nanobk status          # Show config and service status
bash bin/nanobk --json status   # JSON output for Bot/Panel integration
bash bin/nanobk doctor          # Run environment diagnostics
bash bin/nanobk install         # Launch interactive installer
bash bin/nanobk cf deploy       # Deploy Cloudflare Workers
bash bin/nanobk rotate all      # Rotate all keys
bash bin/nanobk rotate hy2      # Rotate only HY2
bash bin/nanobk test            # Run local tests

# --dry-run can be global or command-level:
bash bin/nanobk --dry-run test
bash bin/nanobk test --dry-run
```

Optional: install to PATH for shorter commands:

```bash
sudo bash bin/nanobk install-cli
# or manually: sudo ln -sf "$(pwd)/bin/nanobk" /usr/local/bin/nanobk
nanobk status
```

`nanobk status` shows VPS config, Cloudflare deployment status, and aggregator state. Use `nanobk --json status` for Bot/Panel integration (no secrets leaked, only fingerprints).

## Manual Setup

```bash
git clone https://github.com/kairkiss/NanoBK-Proxy-Suite.git
cd NanoBK-Proxy-Suite
bash installer/install.sh
```

The interactive menu guides you through VPS setup, Cloudflare deployment, key rotation, and testing.

## Step-by-Step

### Step 1: Deploy VPS Proxy Services

```bash
sudo bash installer/install-vps.sh --yes \
  --domain proxy.example.com \
  --cert-mode existing \
  --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem
```

### Step 2: Deploy Cloudflare Workers

```bash
wrangler login

bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com
```

See [cloudflare-setup.md](cloudflare-setup.md) for all options.

### Step 3: Import Subscription

```
https://nanok.yourdomain.com/jb?token=YOUR_SUB_TOKEN
```

### Step 4: Key Rotation

```bash
nanobk rotate all
# or
nanobk rotate hy2 --skip-cloudflare
```

## What's Not in v1.0

- Telegram Bot (planned v1.1)
- Web Panel (planned v1.2)
- Let's Encrypt automation
- edgetunnel deployment automation

These will call `nanobk` CLI commands — they won't duplicate core logic.
