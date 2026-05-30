# Key Rotation Guide

One-command credential rotation for all four proxy services.

## Quick Start

```bash
sudo bash vps/scripts/rotate-keys.sh
```

## What It Does

1. **Backs up** all local configs and current Cloudflare profile
2. **Generates** new credentials for all four services
3. **Patches** local service configs using structured parsers
4. **Restarts** services one by one
5. **Verifies** all ports are listening
6. **Syncs** new profile to Cloudflare KV via admin API
7. **Verifies** Cloudflare profile is updated
8. **Writes** private record with full credentials (chmod 600)
9. **On failure**: rolls back local configs and attempts CF restore

## Credentials Rotated

| Service | Rotated Fields |
|---------|---------------|
| HY2 / Hysteria2 | password |
| TUIC v5 | UUID, password |
| VLESS Reality | client UUID, private key, public key, short ID |
| Trojan TLS | password |

## Credentials NOT Rotated

- Domains
- Ports
- Certificate paths
- SSH settings
- Firewall rules
- Cloudflare DNS / Tunnel / Access

## Prerequisites

- `/root/.nanok-cf-admin.env` with `ADMIN_TOKEN`, `ADMIN_CURRENT_URL`, `ADMIN_UPDATE_URL`
- Four proxy services running
- Tools: curl, jq, python3, openssl, uuidgen, xray, systemctl, ss

## After Rotation

- **Subscription URL**: Does NOT change. Clients refresh to get new keys.
- **Private record**: Full credentials saved to `/root/proxy-key-rotation-latest.private.md` (chmod 600).
- **Backup**: Old configs saved in `/root/proxy-key-rotation-backup-YYYYMMDD-HHMMSS/`.

## Rollback

If something goes wrong:

```bash
# Find the backup directory
ls -lt /root/proxy-key-rotation-backup-*/ | head

# Run the auto-generated rollback script
bash /root/proxy-key-rotation-backup-YYYYMMDD-HHMMSS/rollback.sh

# Restore Cloudflare profile if needed
curl -X POST https://YOUR_WORKER/admin/update \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @/root/proxy-key-rotation-backup-YYYYMMDD-HHMMSS/cf-profile-old.json
```

## Security Notes

- Full credentials are only written to `chmod 600` local files
- The script prints only fingerprints (e.g., `abc123...def456`), not full values
- Never commit `/root/proxy-key-rotation-latest.private.md` to Git
- Admin token and subscription token are separate secrets
