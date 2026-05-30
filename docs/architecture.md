# Architecture

NanoBK Proxy Suite combines VPS-side proxy deployment with Cloudflare Workers subscription management.

## Full Chain

```
┌─────────────────────────────────────────────────────────┐
│  VPS                                                    │
│                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │  HY2     │ │ TUIC v5  │ │ VLESS    │ │ Trojan   │  │
│  │  :443    │ │ :9443    │ │ Reality  │ │ TLS      │  │
│  │  (UDP)   │ │ (UDP)    │ │ :8443    │ │ :2443    │  │
│  └──────────┘ └──────────┘ │ (TCP)    │ │ (TCP)    │  │
│                             └──────────┘ └──────────┘  │
│         │                                               │
│         │ rotate-keys.sh                                │
│         │ (generate → patch → restart → POST)           │
│         ▼                                               │
└─────────────────────────────────────────────────────────┘
          │
          │ POST /admin/update (Bearer ADMIN_TOKEN)
          ▼
┌─────────────────────────────────────────────────────────┐
│  Cloudflare Workers                                     │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  nanok (Primary Worker)                         │   │
│  │                                                 │   │
│  │  KV: SUB_STORE → profile:main                   │   │
│  │  GET /jb?token=SUB_TOKEN → Clash/Mihomo YAML    │   │
│  │  POST /admin/update → write profile to KV       │   │
│  └─────────────────────────────────────────────────┘   │
│          │                                              │
│          │ fetch (NANOK_SUB_TOKEN)                      │
│          ▼                                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │  nanob (Aggregator Worker) — OPTIONAL           │   │
│  │                                                 │   │
│  │  GET /jb?token=NANOB_TOKEN → merged YAML        │   │
│  │  - primary nodes from nanok                     │   │
│  │  - backup nodes from edgetunnel (if configured) │   │
│  │  - geo labels from ipwho.is cache               │   │
│  └─────────────────────────────────────────────────┘   │
│          │                                              │
│          │ (optional) fetch with x-nanob-token          │
│          ▼                                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │  edgetunnel (cmliu/edgetunnel) — OPTIONAL       │   │
│  │                                                 │   │
│  │  Returns backup Clash subscription              │   │
│  │  Internal auth via x-nanob-token header         │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  KV: NANOB_GEO_CACHE → geo:IP, net4:X.Y               │
└─────────────────────────────────────────────────────────┘
          │
          │ Subscription URL (unchanged after key rotation)
          ▼
┌─────────────────────────────────────────────────────────┐
│  Clients                                                │
│  Clash / Mihomo / Shadowrocket / ...                    │
│                                                         │
│  Import: https://<AGGREGATOR_HOST>/jb?token=NANOB_TOKEN │
└─────────────────────────────────────────────────────────┘
```

## Component Summary

| Component | Role | Required? |
|---|---|---|
| **nanok** | Primary subscription Worker. Reads KV profile, outputs Clash/Mihomo YAML. | Yes |
| **nanob** | Aggregator. Merges nanok + optional edgetunnel. Single public URL. | Optional (recommended) |
| **edgetunnel** | Backup node source from `cmliu/edgetunnel`. | Optional |
| **VPS services** | HY2, TUIC v5, VLESS Reality, Trojan TLS. | Yes |
| **rotate-keys.sh** | Generates new credentials, patches configs, updates KV. | Yes |

## Token Model

| Token | Owner | Purpose |
|---|---|---|
| `SUB_TOKEN` | nanok | Public subscription access |
| `ADMIN_TOKEN` | nanok + VPS script | Private admin API |
| `NANOB_TOKEN` | nanob | Public aggregator access |
| `NANOK_SUB_TOKEN` | nanob | Fetch from nanok internally |
| `EDGETUNNEL_EXPORT_TOKEN` | nanob + edgetunnel | Shared internal auth (optional) |

## Key Rotation Flow

```
VPS: bash /root/rotate-proxy-keys.sh
  │
  ├── 1. Backup local configs + fetch current CF profile
  ├── 2. Generate new credentials (openssl, uuidgen, xray x25519)
  ├── 3. Patch local configs (structured Python parsers)
  ├── 4. Restart services one by one
  ├── 5. Verify ports listening
  ├── 6. POST new profile to nanok /admin/update
  ├── 7. Verify CF profile updated
  └── 8. Write private record (chmod 600)
        On failure: rollback local configs + restore CF profile
```

Client subscription URL never changes. Clients refresh to get new credentials.
