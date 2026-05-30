# Nanok KV Primary Worker

This document records the sanitized primary subscription Worker design that was deployed and verified.

No production token, node password, UUID, Reality public key, Reality short ID, Cloudflare account ID, or KV namespace ID is included.

## Scope

The primary Worker was changed from a code-only subscription profile to a KV-driven profile with a private management API.

The production deployment kept the existing proxy parameters intact. Only Worker code, Worker bindings, and KV profile storage were changed.

## Runtime Components

| Component | Purpose |
| --- | --- |
| Worker | Primary Clash/Mihomo subscription output. |
| KV binding `SUB_STORE` | Stores the four managed Japan nodes under `profile:main`. |
| Worker secret `SUB_TOKEN` | Protects the subscription and edge proxy paths. |
| Worker secret `ADMIN_TOKEN` | Protects private management endpoints. |
| Fixed in-code node | Keeps one non-KV Reality node outside the managed KV profile. |

## Paths

| Path | Source | Purpose |
| --- | --- | --- |
| `/` | fixed route | HTML status page; shows only `token=*****`. |
| `SUB_PATH`, default `/sub-kai` | environment variable | Clash/Mihomo YAML subscription. |
| `EDGE_PATH`, default `/edge` | environment variable | Protected upstream edge subscription proxy. |
| `ADMIN_CURRENT_PATH`, default `/admin/current` | environment variable | Reads current KV profile after admin auth. |
| `ADMIN_PATH`, default `/admin/update` | environment variable | Writes current KV profile after admin auth and validation. |

Authentication failures intentionally return `404`, not `401` or `403`.

## KV Profile

The KV key is:

```text
profile:main
```

The sanitized shape is shown in [`examples/nanok-profile.example.json`](../examples/nanok-profile.example.json).

The KV profile manages only:

- HY2
- TUIC v5
- VLESS Reality
- Trojan
- Display-only node names

The fixed Reality node is intentionally not stored in KV in this example.

## YAML Safety

The deployed Worker includes explicit YAML safety handling because some Clash/Mihomo importers reject subscriptions with:

```text
yaml: control characters are not allowed
```

Implemented safeguards:

- `hasYamlControlChars(str)` rejects YAML-invalid control characters.
- `cleanString(value, fieldName)` converts to string, normalizes to NFC, trims, and rejects invalid control characters.
- `yamlQuote(value, fieldName)` uses `JSON.stringify(cleanString(...))` for YAML-safe double quoted scalars.
- `validateProfile(profile)` returns a cleaned profile before KV writes or YAML generation.
- `buildSubYaml(profile, cfg)` quotes every YAML string field, including server, SNI, UUID, password, public key, and short ID.
- `assertValidYamlText(yaml)` scans the final generated YAML before responding.

The Worker does not include production secrets in error messages.

## Admin API Behavior

### `GET /admin/current`

Requires:

```http
Authorization: Bearer <ADMIN_TOKEN>
```

Returns the raw current profile only to authorized callers.

### `POST /admin/update`

Requires the same authorization header and a full profile JSON body.

Before writing KV, the Worker validates and cleans:

- all required string fields
- all ports
- display-only node names

Invalid profile input returns:

```text
400 invalid profile
```

The response returns only masked fingerprints.

## Response Headers

Subscription, edge, admin JSON, and error responses use no-store/noindex headers:

```http
Cache-Control: no-store, no-cache, must-revalidate, max-age=0
X-Robots-Tag: noindex, nofollow
```

Plain `404` responses use:

```http
Cache-Control: no-store
X-Robots-Tag: noindex, nofollow
```

## Verification Summary

Deployment was verified with:

- root path returns HTML and masks token as `*****`
- missing subscription token returns `404`
- wrong subscription token returns `404`
- valid subscription token returns Clash/Mihomo YAML
- generated YAML contains no invalid YAML control characters
- admin endpoint requires `ADMIN_TOKEN`
- KV profile scan found no invalid control characters

Operationally verified clients:

- Shadowrocket import and use succeeded
- Clash/Mihomo import and use succeeded after YAML safety hardening

## Non-Goals

This change did not:

- modify VPS services
- modify proxy server configuration
- rotate production node credentials
- change Cloudflare DNS
- change Cloudflare Tunnel
- change Cloudflare Access
- delete any existing node

