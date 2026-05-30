# NanoK KV Profile and Automatic Key Rotation

This document records a sanitized version of a Cloudflare Worker + VPS automation pattern for keeping a private Clash/Mihomo subscription in sync with rotated server-side proxy credentials.

No production hostnames, IP addresses, tokens, passwords, UUIDs, X25519 private keys, KV namespace IDs, Cloudflare account IDs, or service credentials are included here.

## Goal

Create a workflow where one VPS-side command can rotate the credentials for four existing proxy services and then update a Cloudflare Worker subscription profile without manually editing Worker code.

The intended one-command operation is:

```bash
bash /root/rotate-proxy-keys.sh
```

The script should:

1. Generate new sanitized-equivalent values for the four existing services.
2. Update the corresponding VPS service configuration files.
3. Restart and verify the four services.
4. POST a sanitized profile update to a private Cloudflare Worker admin endpoint.
5. Let clients keep using the same public subscription URL.

The public subscription URL shape is:

```text
https://<PRIMARY_WORKER_HOST>/<SUB_PATH>?token=<SUB_TOKEN>
```

Example placeholder:

```text
https://primary-subscription.example.com/jb?token=<PUBLIC_SUBSCRIPTION_TOKEN>
```

## Architecture

```text
Client
  |
  | GET /<SUB_PATH>?token=<SUB_TOKEN>
  v
Cloudflare Worker
  |
  | reads KV key: profile:main
  v
Cloudflare KV profile
  |
  | generated YAML
  v
Clash / Mihomo / compatible client
```

For key rotation:

```text
VPS rotation script
  |
  | updates local service configs
  | restarts and verifies services
  | POST /admin/update with Authorization: Bearer <ADMIN_TOKEN>
  v
Cloudflare Worker private admin endpoint
  |
  | validates profile
  | writes KV key: profile:main
  v
Clients refresh the unchanged public subscription URL
```

## Component Roles

| Component | Role |
| --- | --- |
| `nanok` or primary Worker | Builds the private subscription YAML from a KV profile. |
| `SUB_STORE` KV binding | Stores `profile:main`, the current sanitized-equivalent node profile. |
| VPS rotation script | Generates new keys, edits VPS configs, restarts services, and updates KV. |
| `nanob` aggregator | Optional upper-level aggregator that can fetch `nanok` and append backup nodes. |

## KV Profile Shape

The KV key is:

```text
profile:main
```

The profile is JSON with this sanitized shape:

```json
{
  "updatedAt": "2026-01-01T00:00:00.000Z",
  "hy2": {
    "name": "JP-TYO-01 | HY2 | 443 | Primary",
    "server": "hy2.example.com",
    "port": 443,
    "password": "<HY2_PASSWORD>",
    "sni": "hy2.example.com"
  },
  "tuic": {
    "name": "JP-TYO-02 | TUIC V5 | 9443 | Speed",
    "server": "tuic.example.com",
    "port": 9443,
    "uuid": "<TUIC_UUID>",
    "password": "<TUIC_PASSWORD>",
    "sni": "tuic.example.com"
  },
  "reality": {
    "name": "JP-TYO-03 | Reality | 8443 | Stealth",
    "server": "<VPS_IP>",
    "port": 8443,
    "uuid": "<REALITY_UUID>",
    "servername": "www.example-front.com",
    "publicKey": "<REALITY_PUBLIC_KEY>",
    "shortId": "<REALITY_SHORT_ID>"
  },
  "trojan": {
    "name": "JP-TYO-04 | Trojan | 2443 | Fallback",
    "server": "trojan.example.com",
    "port": 2443,
    "password": "<TROJAN_PASSWORD>",
    "sni": "trojan.example.com"
  },
  "extraNodes": {
    "poetryNodeName": "Status placeholder",
    "recommendNodeName": "Project placeholder"
  }
}
```

Do not store an X25519 Reality private key in KV. The private key belongs only on the VPS service configuration. The Worker subscription only needs the public key and short ID.

## Worker Bindings

| Binding | Type | Purpose |
| --- | --- | --- |
| `SUB_STORE` | KV namespace | Stores the current `profile:main`. |
| `SUB_TOKEN` | secret text | Public subscription token used by clients. |
| `ADMIN_TOKEN` | secret text | Private admin token used only by the VPS rotation script. |
| `SUB_PATH` | plain variable | Public subscription path, for example `/jb`. |
| `EDGE_PATH` | plain variable | Optional upstream proxy path, for example `/edge`. |
| `ADMIN_PATH` | plain variable | Admin update path, default `/admin/update`. |
| `ADMIN_CURRENT_PATH` | plain variable | Admin read path, default `/admin/current`. |
| `POETRY_NODE_NAME` | plain variable | Optional display-only node name. |
| `RECOMMEND_NODE_NAME` | plain variable | Optional display-only node name. |

## Admin Endpoint Contract

### Read current profile

```http
GET /admin/current
Authorization: Bearer <ADMIN_TOKEN>
```

Expected behavior:

- Returns current `profile:main` JSON.
- Returns `404` for missing or wrong admin token.
- Does not expose token errors through `401` or `403`.

### Update profile

```http
POST /admin/update
Authorization: Bearer <ADMIN_TOKEN>
Content-Type: application/json
```

Expected behavior:

- Validates required profile fields.
- Rejects YAML-invalid control characters.
- Writes `profile:main` only after validation.
- Returns fingerprints only, not full secrets.

Example response:

```json
{
  "ok": true,
  "updatedAt": "2026-01-01T00:00:00.000Z",
  "fingerprints": {
    "hy2Password": "abc123...def456",
    "tuicUuid": "abc123...def456",
    "tuicPassword": "abc123...def456",
    "realityUuid": "abc123...def456",
    "realityPublicKey": "abc123...def456",
    "realityShortId": "abc123...def456",
    "trojanPassword": "abc123...def456"
  }
}
```

## YAML Safety Fix

After moving node values from hardcoded Worker strings into KV, Clash/Mihomo can fail with:

```text
yaml: control characters are not allowed
```

This means the YAML text itself is invalid before protocol support is even checked. The fix is to sanitize and quote all string fields before building YAML.

### Disallowed characters

The Worker rejects:

- U+0000 through U+0008
- U+000B
- U+000C
- U+000E through U+001F
- U+007F
- U+0080 through U+009F

TAB, LF, and CR are handled intentionally; profile string fields should still be trimmed and emitted as JSON-quoted YAML scalars.

### Required output rule

Every YAML string field should be generated through a safe quoting function. This includes:

- `name`
- `server`
- `password`
- `uuid`
- `sni`
- `servername`
- `public-key`
- `short-id`

Numeric ports and booleans do not need quoting.

## VPS Rotation Transaction

The VPS-side script should be transaction-like:

1. Read current Cloudflare profile and save it as `cf-profile-old.json`.
2. Find and back up all four local service config files.
3. Generate new credentials.
4. Edit local configs using structured parsers, not broad `sed` replacements.
5. Validate configs where possible.
6. Restart services one by one.
7. Verify services are active and ports are listening.
8. Only then POST the new profile to `/admin/update`.
9. Verify `/admin/current` reflects the new profile.
10. Save full new values only to a local `chmod 600` private record.
11. On failure, restore old local configs and restore the old KV profile when necessary.

## Service Scope

The one-command rotation scope is only the four primary nodes:

| Service | Rotated fields |
| --- | --- |
| HY2 / Hysteria2 | password only |
| TUIC v5 | UUID and password |
| VLESS + Reality | client UUID, private key, public key, short ID |
| Trojan TLS | password only |

Do not rotate:

- domains
- ports
- certificate paths
- SSH settings
- firewall base policy
- Cloudflare DNS
- Cloudflare Tunnel
- Cloudflare Access

## Rotation Output Policy

The script should not print full secrets. It may print fingerprints:

```text
HY2 password: abc123...def456
TUIC UUID: abc123...def456
Reality publicKey: abc123...def456
Trojan password: abc123...def456
```

Full values may be written only to:

```text
/root/proxy-key-rotation-latest.private.md
```

with:

```bash
chmod 600 /root/proxy-key-rotation-latest.private.md
```

## Test Matrix

After Worker deployment:

```bash
curl -i https://<PRIMARY_WORKER_HOST>/
curl -i https://<PRIMARY_WORKER_HOST>/<OLD_SUB_PATH>
curl -i https://<PRIMARY_WORKER_HOST>/<SUB_PATH>
curl -i "https://<PRIMARY_WORKER_HOST>/<SUB_PATH>?token=wrong"
curl -i "https://<PRIMARY_WORKER_HOST>/<SUB_PATH>?token=<SUB_TOKEN>"
curl -i https://<PRIMARY_WORKER_HOST>/<ADMIN_CURRENT_PATH>
curl -i -H "Authorization: Bearer <ADMIN_TOKEN>" \
  https://<PRIMARY_WORKER_HOST>/<ADMIN_CURRENT_PATH>
```

Expected:

| Request | Expected result |
| --- | --- |
| `/` | HTML status page, no real token. |
| old public path | `404` if replaced. |
| public path without token | `404`. |
| public path with wrong token | `404`. |
| public path with correct token | Clash/Mihomo YAML. |
| admin path without token | `404`. |
| admin path with admin token | JSON profile. |

After VPS rotation:

```bash
systemctl is-active hysteria-server.service
systemctl is-active tuic-v5-9443.service
systemctl is-active xray-reality-8443.service
systemctl is-active xray-trojan-2443.service
```

All should return:

```text
active
```

## Security Notes

- Public subscription tokens and admin tokens are different secrets.
- The public subscription token is for clients.
- The admin token is only for the VPS rotation script.
- If a token is exposed, rotate that token.
- If a node credential is exposed, run the VPS rotation script.
- Do not commit production secrets or generated private records to Git.
