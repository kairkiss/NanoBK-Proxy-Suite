# Cloudflare Bindings

This document lists the sanitized bindings used by the aggregator architecture.

## `nanob` Worker

| Binding | Type | Purpose |
| --- | --- | --- |
| `NANOB_TOKEN` | secret text | Public import-link token for the aggregator. |
| `NANOK_SUB_TOKEN` | secret text | Upstream token used to fetch the primary Worker. |
| `EDGETUNNEL_EXPORT_TOKEN` | secret text | Shared internal token used to fetch edgetunnel. |
| `NANOB_GEO_CACHE` | KV namespace | Caches IP geo metadata and learned IPv4 network labels. |

## `edgetunnel` Worker

Keep existing edgetunnel bindings and add one internal secret:

| Binding | Type | Purpose |
| --- | --- | --- |
| existing edgetunnel secrets | secret text | Existing admin/key/UUID/config values. |
| existing edgetunnel KV | KV namespace | Existing edgetunnel state/config storage. |
| `NANOB_TOKEN` | secret text | Shared internal token accepted from `nanob`. |

## Custom Domains

| Host | Worker |
| --- | --- |
| `<AGGREGATOR_HOST>` | `nanob` |
| `<PRIMARY_HOST>` | `nanok` or equivalent primary Worker |
| `<EDGETUNNEL_HOST>` | `edgetunnel` |

## Token Rotation

If the primary subscription token changes:

1. Update only `NANOK_SUB_TOKEN` on `nanob`.
2. Keep `NANOB_TOKEN` unchanged.
3. The public import URL remains unchanged.

If the public import token should change:

1. Update `NANOB_TOKEN`.
2. Update the client import URL.

