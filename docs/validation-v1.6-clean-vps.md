# NanoBK v1.6 Clean VPS Full Wizard Validation

## 1. Scope

This document defines the acceptance test plan for the NanoBK unified beginner installer on a clean VPS. It covers the full wizard flow from bootstrap to final status.

## 2. What This Validates

- Bootstrap from GitHub main branch
- Full Recommended wizard (VPS + Cloudflare + Bot + Web)
- VPS four-protocol deployment (HY2, TUIC, Reality, Trojan)
- Cloudflare nanok and nanob deployment
- Subscription YAML generation and verification
- Bot and Web Panel env generation
- Key rotation with Cloudflare sync
- Summary honesty (planned/configured/installed/verified states)

## 3. What This Does Not Validate

- Let's Encrypt automatic certificate
- edgetunnel deployment
- Cloudflare Tunnel
- Telegram Bot actual connection
- Web Panel actual HTTP serving
- Multi-user scenarios
- Traffic monitoring

## 4. Test Environment Requirements

- Clean Ubuntu 24.04 VPS with root access
- Domain name pointed to VPS public IP
- Cloudflare account with Workers enabled; paid plan may be required depending on usage and Cloudflare limits
- Telegram Bot Token from @BotFather
- Your Telegram numeric User ID

## 5. Required Accounts/Tools

- GitHub access (to clone repository)
- Cloudflare account (for Workers)
- Telegram account (for Bot)
- SSH access to VPS

## 6. Security Notes

- Do NOT paste real tokens into chat or logs
- Do NOT paste subscription URLs into public places
- Do NOT commit .env files to Git
- If tokens were exposed, regenerate immediately:
  - SUB_TOKEN / ADMIN_TOKEN on Cloudflare Worker secrets
  - NANOB_TOKEN on nanob Worker secrets
  - TELEGRAM_BOT_TOKEN via @BotFather

## 7. Phase 0: Clean VPS Baseline

```bash
# Verify clean state
uname -a
cat /etc/os-release
df -h /
free -m
```

Expected: Ubuntu 24.04, sufficient disk (>1GB) and memory (>512MB).

## 8. Phase 1: Bootstrap

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
```

Verify:
- Repository cloned successfully
- install.sh launched automatically
- No errors during clone

## 9. Phase 2: Full Recommended Wizard

```bash
bash installer/install.sh --mode full --lang zh
```

Steps to verify:
1. Preflight checks pass (OS, tools, ports all free)
2. Domain input accepted
3. Certificate mode selected
4. VPS deploy completes
5. Cloudflare preflight passes (Node>=22, wrangler login)
6. Profile validation passes
7. nanok KV created and Worker deployed
8. nanok profile uploaded and verified
9. nanob deployed with Service Binding
10. nanob verified
11. Bot .env generated (chmod 600)
12. Web Panel .env generated (chmod 600)
13. Summary shows honest status

## 10. Phase 3: VPS Verification

```bash
sudo bash /opt/nanobk/bin/healthcheck.sh
```

Verify all pass:
- HY2 :443 (udp): active
- TUIC :9443 (udp): active
- Reality :8443 (tcp): active
- Trojan :2443 (tcp): active
- Profile JSON: valid
- Secrets mode: 600

## 11. Phase 4: Cloudflare Verification

```bash
bash bin/nanobk cf verify
```

Or individually:
```bash
bash installer/install-cloudflare.sh --verify-nanok-only
bash installer/install-cloudflare.sh --verify-nanob-only
```

Verify:
- nanok verifyStatus: verified
- nanob verifyStatus: verified

## 12. Phase 5: nanok Subscription Verification

```bash
# Replace with your actual URL and token
curl -fsS "https://YOUR_NANOK_URL/jb?token=YOUR_SUB_TOKEN"
```

Verify output:
- Valid Clash/Mihomo YAML
- Contains: proxies, proxy-groups, rules
- Contains: type: hysteria2, type: tuic, type: vless, type: trojan
- No invalid control characters

## 13. Phase 6: nanob Subscription Verification

```bash
# Replace with your actual URL and token
curl -fsS "https://YOUR_NANOB_URL/jb?token=YOUR_NANOB_TOKEN"
```

Verify output:
- Valid YAML
- Contains all four protocol types
- If edgetunnel configured: backup nodes present

## 14. Phase 7: Bot Env Verification

```bash
# Check file permissions (should be 600)
stat -c "%a %n" bot/.env

# Check required fields exist (without printing values)
grep -q '^TELEGRAM_BOT_TOKEN=' bot/.env && echo "TELEGRAM_BOT_TOKEN: present"
grep -q '^OWNER_TELEGRAM_ID=' bot/.env && echo "OWNER_TELEGRAM_ID: present"
grep -q '^NANOBK_CLI=' bot/.env && echo "NANOBK_CLI: present"

# Run self-test
python3 bot/nanobk_bot.py --self-test
```

Verify:
- File mode 600
- TELEGRAM_BOT_TOKEN: present
- OWNER_TELEGRAM_ID: present
- NANOBK_CLI: present
- Self-test passes

⚠ Do NOT execute `cat bot/.env` — this prints tokens to terminal/logs.
⚠ Do NOT paste `.env` contents into chat, logs, or issues.

## 15. Phase 8: Web Panel Env Verification

```bash
# Check file permissions (should be 600)
stat -c "%a %n" web/.env

# Check required fields exist (without printing values)
grep -q '^NANOBK_WEB_TOKEN=' web/.env && echo "NANOBK_WEB_TOKEN: present"
grep -q '^NANOBK_WEB_SECRET_KEY=' web/.env && echo "NANOBK_WEB_SECRET_KEY: present"
grep -q '^NANOBK_WEB_HOST=127.0.0.1' web/.env && echo "NANOBK_WEB_HOST: 127.0.0.1"

# Run self-test
python3 web/app.py --self-test
```

Verify:
- File mode 600
- NANOBK_WEB_TOKEN: present
- NANOBK_WEB_SECRET_KEY: present
- NANOBK_WEB_HOST: 127.0.0.1
- Self-test passes

⚠ Do NOT execute `cat web/.env` — this prints secrets to terminal/logs.
⚠ Do NOT paste `.env` contents into chat, logs, or issues.

## 16. Phase 9: Rotate TUIC + Cloudflare Sync

```bash
sudo bash /opt/nanobk/bin/rotate-keys.sh --yes --protocol tuic
```

Verify:
- New credentials generated (fingerprints shown)
- Backup created in /opt/nanobk/backups/
- TUIC service restarted
- Healthcheck passes
- Cloudflare profile updated
- Cloudflare verification passes

## 17. Phase 10: Final Status

```bash
bash bin/nanobk status
bash bin/nanobk --json status | python3 -m json.tool
```

Verify JSON output:
- ok: true
- All four services: active
- cloudflare.nanok.verifyStatus: verified
- cloudflare.nanob.verifyStatus: verified
- No warnings about missing config

## 18. Pass Criteria

All of the following must be true:
- All 10 phases complete without errors
- All four proxy protocols active on VPS
- Cloudflare nanok subscription verified
- Cloudflare nanob subscription verified
- Key rotation with Cloudflare sync works
- Summary shows honest status throughout

## 19. Fail Criteria

Any of the following means failure:
- Any phase exits non-zero
- Any service not active after deployment
- Cloudflare verification fails
- Rotate fails or Cloudflare sync fails
- Summary shows misleading status (e.g., "verified" when not)

## 20. Data to Report Back

When reporting results, include:
- Which phases passed / failed
- Error messages from any failures
- `nanobk --json status` output (redact tokens)
- `healthcheck.sh` output
- Do NOT paste real tokens or subscription URLs

## Notes

- Claude Code / local tests cannot perform this validation
- User must run the commands on a real VPS
- Dry-run output does not prove real deployment works
- This document is a guide, not automated test
