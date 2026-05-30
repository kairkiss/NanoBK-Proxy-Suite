# Cloudflare Subscription Aggregator

This repository documents a sanitized Cloudflare Workers setup for aggregating a primary subscription Worker with an edgetunnel backup Worker.

No production tokens, UUIDs, account IDs, KV namespace IDs, or private node credentials are included.

## What This Builds

The final public import URL is a single subscription endpoint:

```text
https://<AGGREGATOR_HOST>/jb?token=<NANOB_TOKEN>
```

The aggregator Worker:

1. Validates the public aggregator token.
2. Fetches the primary subscription from a separate Worker.
3. Fetches backup nodes from an edgetunnel Worker through an internal authorization header.
4. Appends edgetunnel nodes after the primary nodes.
5. Adds geo labels to edgetunnel node names using cached `ipwho.is` metadata.

The primary Worker remains the source of truth for the main subscription logic.

## Components

| Worker | Role |
| --- | --- |
| `nanok` | Primary subscription Worker. Keeps existing VPS/profile/key logic. |
| `edgetunnel` | Backup node source based on `cmliu/edgetunnel`. |
| `nanob` | Aggregator Worker. Public single-link entrypoint. |

## Token Model

`nanob` separates the public import token from the upstream primary Worker token:

| Secret | Used by | Purpose |
| --- | --- | --- |
| `NANOB_TOKEN` | `nanob` | Public import-link token. |
| `NANOK_SUB_TOKEN` | `nanob` | Token used internally to fetch `nanok`. |
| `EDGETUNNEL_EXPORT_TOKEN` | `nanob` | Shared token sent to edgetunnel. |
| `NANOB_TOKEN` or equivalent internal token | `edgetunnel` | Accepts authorized aggregator requests. |

When the primary Worker token changes, only update `NANOK_SUB_TOKEN` on `nanob`. The public import link does not need to change.

## Geo Labeling

`nanob` enriches only edgetunnel backup nodes. Primary nodes are left unchanged.

Example output:

```text
[US / California] [EDT backup] CF Preferred 1
```

Geo lookup behavior:

- Reads from `NANOB_GEO_CACHE` first.
- Falls back to learned IPv4 network-prefix labels.
- Warms missing geo data in the background.
- If lookup fails, subscription output still works and uses `[EDT backup]`.

`ipwho.is` data is a GeoIP database result. For Cloudflare Anycast IPs, treat it as a selection hint, not a guaranteed runtime egress or edge location.

## Files

| Path | Purpose |
| --- | --- |
| `workers/nanob.worker.example.js` | Sanitized aggregator Worker. |
| `docs/edgetunnel-internal-auth.md` | Minimal edgetunnel patch concept. |
| `docs/cloudflare-bindings.md` | Required Worker bindings and custom domains. |
| `docs/deploy-checklist.md` | Deployment and verification checklist. |

## Deployment Summary

1. Deploy or keep the primary subscription Worker.
2. Deploy edgetunnel and add the internal authorization check described in `docs/edgetunnel-internal-auth.md`.
3. Deploy `nanob` from `workers/nanob.worker.example.js`.
4. Bind secrets and KV as described in `docs/cloudflare-bindings.md`.
5. Attach a custom domain to `nanob`.
6. Import only the `nanob` URL into clients.

