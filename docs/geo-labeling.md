# Geo Labeling

Automatic country/region detection for proxy nodes using free GeoIP lookup.

## How It Works

1. When nanob fetches edgetunnel backup nodes, it extracts IP addresses from proxy definitions.
2. For each IP, it checks the `NANOB_GEO_CACHE` KV namespace.
3. If not cached, it queries `https://ipwho.is/{ip}` (free, no API key).
4. Results are cached in KV with a 30-day write TTL and 1-hour read cache.
5. IPv4 /24 network prefixes are learned for cache efficiency (e.g., `net4:203.0`).

## Output Format

Node names are prefixed with geo labels:

```
[US / California] [EDT backup] CF Preferred 1
[JP / Tokyo] [EDT backup] CF Preferred 2
[EDT backup] CF Preferred 3          ← geo lookup failed, still works
```

## Caching Strategy

| Layer | TTL | Purpose |
|---|---|---|
| KV write (`geo:{ip}`) | 30 days | Long-term storage |
| KV write (`net4:X.Y`) | 30 days | IPv4 /24 network learning |
| KV read cache | 1 hour | Worker-side cache for repeated reads |
| Background warming | N/A | `ctx.waitUntil` fills missing entries |

## Failure Behavior

- **ipwho.is timeout**: Returns `null`, node gets `[EDT backup]` prefix without geo label.
- **ipwho.is error**: Same as timeout.
- **KV read error**: Returns `null`, falls through to network prefix or fresh lookup.
- **All lookups fail**: Subscription output is unaffected. Only geo labels are missing.

**Geo lookup failure NEVER blocks subscription output.**

## Current Scope

Currently applied only to edgetunnel backup nodes in nanob.

## Future Plans

- Apply geo labels to nanok primary VPS nodes (auto-detect by VPS IP).
- Reuse the same `shared/geo.js` module from both nanok and nanob.
- Cache primary node geo data alongside edgetunnel data.

## Cloudflare Anycast IPs

For Cloudflare Anycast IPs (edgetunnel), ipwho.is returns a geo result that represents the Cloudflare edge selection hint, not a guaranteed runtime egress location. Treat it as informational.

## API Notes

- `ipwho.is` is free with no API key for basic usage.
- Rate limit: the module adds a 1.1-second delay between lookups.
- Max 24 background lookups per request to stay within limits.
