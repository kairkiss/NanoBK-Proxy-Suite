# Cloudflare Setup Guide

Deploy nanok (primary subscription) and optionally nanob (aggregator) Workers.

## Prerequisites

- Cloudflare account with Workers enabled
- Node.js and npm installed locally
- Wrangler CLI (auto-detected: `npx wrangler` or global `wrangler`)
- Cloudflare authentication (`wrangler login`)
- A `profile.current.json` from the VPS installer (or `examples/profile.example.json`)

## Quick Deploy: nanok only

```bash
wrangler login

bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com
```

## Quick Deploy: nanok + nanob (no edgetunnel)

```bash
bash installer/install-cloudflare.sh --yes \
  --create-kv --create-nanob-geo-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com \
  --deploy-nanob --nanob-route-url https://nanob.yourdomain.com
```

## Quick Deploy: nanok + nanob + edgetunnel

```bash
bash installer/install-cloudflare.sh --yes \
  --create-kv --create-nanob-geo-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com \
  --deploy-nanob --nanob-route-url https://nanob.yourdomain.com \
  --edge-host edge-subscription.example.com \
  --edgetunnel-export-token YOUR_EDGE_TOKEN
```

## Architecture

```
Client → nanob (aggregator) → nanok (primary YAML)
                            → edgetunnel (optional backup YAML)
```

- **nanok**: Primary subscription Worker. Reads KV profile, outputs Clash/Mihomo YAML.
- **nanob**: Aggregator. Merges nanok + optional edgetunnel. Single public URL.
- **edgetunnel**: Optional backup node source. If it fails, nanob returns primary only.

## Which URL to Import

| Scenario | Import URL |
|----------|-----------|
| Only nanok deployed | `https://nanok.../jb?token=SUB_TOKEN` |
| nanok + nanob deployed | `https://nanob.../jb?token=NANOB_TOKEN` (recommended) |
| nanob without edgetunnel | Same as above — returns nanok primary nodes |
| nanob with edgetunnel | Same URL — primary + backup nodes |

## edgetunnel is Optional

edgetunnel is **not required** for nanob to work. Without it, nanob returns the nanok primary subscription. With it, nanob appends backup nodes. If edgetunnel fails, nanob falls back to primary.

See [edgetunnel-optional.md](edgetunnel-optional.md) for details.

## Bundle Test

Test that Workers can be bundled without deploying:

```bash
bash tests/wrangler-nanok-dry-run.sh
bash tests/wrangler-nanob-dry-run.sh
```

These tests temporarily generate `wrangler.toml` in the worker directories. If a `wrangler.toml` already exists, it is backed up and restored after the test. No Cloudflare resources are modified.

## All Options

### General

| Option | Default | Description |
|--------|---------|-------------|
| `--dry-run` | off | Print actions without modifying Cloudflare |
| `--yes` | off | Non-interactive mode |
| `--force` | off | Overwrite existing non-NanoBK wrangler.toml |

### nanok (primary)

| Option | Default | Description |
|--------|---------|-------------|
| `--worker-name` | `nanok` | Worker name |
| `--worker-dir` | `workers/nanok` | Worker source dir |
| `--profile` | `/etc/nanobk/profile.current.json` | Profile JSON path |
| `--sub-token` | auto-generated | Subscription token |
| `--admin-token` | auto-generated | Admin token |
| `--sub-path` | `/jb` | Subscription path |
| `--admin-path` | `/admin/update` | Admin update path |
| `--admin-current-path` | `/admin/current` | Admin read path |
| `--kv-namespace-id` | (none) | Use existing KV |
| `--create-kv` | off | Auto-create KV |
| `--kv-binding` | `SUB_STORE` | KV binding name |
| `--route-url` | (none) | nanok Worker URL |
| `--skip-profile-upload` | off | Skip profile upload |
| `--skip-verify` | off | Skip nanok verification |

### nanob (aggregator, optional)

| Option | Default | Description |
|--------|---------|-------------|
| `--deploy-nanob` | off | Deploy nanob aggregator |
| `--nanob-worker-name` | `nanob` | nanob Worker name |
| `--nanob-worker-dir` | `workers/nanob` | nanob source dir |
| `--nanob-route-url` | (none) | nanob Worker URL (required with --deploy-nanob) |
| `--nanob-token` | auto-generated | nanob subscription token |
| `--nanob-path` | `/jb` | nanob subscription path |
| `--nanob-geo-kv-namespace-id` | (none) | Use existing Geo KV |
| `--create-nanob-geo-kv` | off | Auto-create Geo KV |
| `--nanob-geo-kv-binding` | `NANOB_GEO_CACHE` | Geo KV binding |
| `--edge-host` | (none) | Edgetunnel host (enables edgetunnel) |
| `--edge-sub-path` | `/sub?target=clash` | Edgetunnel path |
| `--edgetunnel-export-token` | (none) | Edgetunnel auth token (optional) |
| `--skip-nanob-verify` | off | Skip nanob verification |

## After Deployment

1. Import subscription URL into Clash/Mihomo.
2. On VPS, create admin env for key rotation (see [key-rotation.md](key-rotation.md)).
