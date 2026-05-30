# Deployment Checklist

## Before Deploy

- Confirm the primary Worker already returns a valid Clash/Mihomo YAML subscription.
- Confirm edgetunnel returns a Clash-compatible subscription when authorized.
- Generate random secret values for public and internal tokens.
- Create a KV namespace for geo cache.

## Deploy `nanob`

1. Replace the example host constants in `workers/nanob.worker.example.js`:
   - `NANOK_ORIGIN`
   - `EDGE_HOST`
   - `EDGE_SUB_PATH`
2. Bind secrets:
   - `NANOB_TOKEN`
   - `NANOK_SUB_TOKEN`
   - `EDGETUNNEL_EXPORT_TOKEN`
3. Bind KV:
   - `NANOB_GEO_CACHE`
4. Attach a custom domain to the `nanob` Worker.

## Verify

Valid token should return `200`:

```text
https://<AGGREGATOR_HOST>/jb?token=<NANOB_TOKEN>
```

Invalid token should return `404`:

```text
https://<AGGREGATOR_HOST>/jb?token=wrong
```

The returned YAML should contain:

- Primary nodes first.
- Comment marker: `edgetunnel backup nodes`.
- Backup node names containing `[EDT backup]`.
- Geo labels when cached, for example `[US / California]`.

## Operational Notes

- The primary Worker is not modified by this architecture.
- Geo lookup failures must not fail the subscription response.
- `ipwho.is` is used as a best-effort GeoIP data source.
- Cloudflare Anycast IP geo labels are hints, not guaranteed runtime edge locations.

