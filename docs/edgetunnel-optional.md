# Edgetunnel — Optional Enhancement

**edgetunnel is NOT required.** The entire NanoBK Proxy Suite works without it.

## What Is edgetunnel?

[cmliu/edgetunnel](https://github.com/cmliu/edgetunnel) is a Cloudflare Worker that provides proxy nodes using Cloudflare's network. It serves as a backup/companion to your VPS nodes.

## Behavior Without edgetunnel

| Scenario | nanob behavior |
|---|---|
| `EDGE_HOST` is empty or `EDGETUNNEL_EXPORT_TOKEN` not set | Returns nanok primary YAML only |
| edgetunnel fetch fails (timeout, 5xx, network error) | Returns nanok primary YAML only |
| edgetunnel returns non-200 | Returns nanok primary YAML only |
| edgetunnel YAML merge fails | Returns nanok primary YAML only |

**In every failure case, the primary subscription is returned unmodified.**

## Behavior With edgetunnel

When properly configured:

1. nanob fetches primary YAML from nanok.
2. nanob fetches backup YAML from edgetunnel (with internal auth header).
3. Backup nodes are appended after primary nodes with `# edgetunnel backup nodes` comment.
4. Backup node names are prefixed with `[EDT backup]` and optional geo labels.

```
proxies:
  # Primary nodes (from nanok / VPS)
  - name: "JP-TYO-01 | HY2 | 443 | Primary"
    ...
  - name: "JP-TYO-02 | TUIC V5 | 9443 | Speed"
    ...

  # edgetunnel backup nodes
  - name: "[US / California] [EDT backup] CF Preferred 1"
    ...
  - name: "[JP / Tokyo] [EDT backup] CF Preferred 2"
    ...
```

## Setup

### With install-cloudflare.sh (v0.4+)

```bash
bash installer/install-cloudflare.sh --yes \
  --deploy-nanob --nanob-route-url https://nanob.yourdomain.com \
  --edge-host edge-subscription.example.com \
  --edgetunnel-export-token YOUR_EDGE_TOKEN \
  ...other flags...
```

### Manual setup

1. Deploy edgetunnel from [cmliu/edgetunnel](https://github.com/cmliu/edgetunnel).
2. Add internal authorization check (see `docs/edgetunnel-internal-auth.md`).
3. Set `EDGETUNNEL_EXPORT_TOKEN` secret on nanob.
4. Set `EDGE_HOST` in nanob wrangler.toml `[vars]`.
5. Bind `NANOB_TOKEN` secret on edgetunnel.

**No source code editing is needed.** All configuration comes from env vars.

## Enabling edgetunnel

Set both `EDGE_HOST` and `EDGETUNNEL_EXPORT_TOKEN`. If either is empty/missing, edgetunnel is disabled.

```toml
# wrangler.toml
[vars]
EDGE_HOST = "edge-subscription.example.com"
EDGE_SUB_PATH = "/sub?target=clash"
```

```bash
wrangler secret put EDGETUNNEL_EXPORT_TOKEN
```

## Disabling edgetunnel

To disable edgetunnel without removing the secret:

1. Set `EDGE_HOST = ""` in wrangler.toml `[vars]`, OR
2. Unset the `EDGETUNNEL_EXPORT_TOKEN` secret.

nanob will immediately return primary-only subscriptions. No redeployment needed if only changing the env var (Wrangler auto-picks up `[vars]` on next deploy).

## Internal Authorization

The aggregator authenticates to edgetunnel via a shared secret header:

```http
x-nanob-token: <EDGETUNNEL_EXPORT_TOKEN>
```

edgetunnel compares it against its own `NANOB_TOKEN` binding. This avoids using edgetunnel's public subscription token.

See [edgetunnel-internal-auth.md](edgetunnel-internal-auth.md) for the minimal patch.
