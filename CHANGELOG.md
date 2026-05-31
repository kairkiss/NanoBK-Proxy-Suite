# Changelog

## v1.1.2 — Bot Output Polish

### Fixed

- `bot/run.sh` now detects missing Python venv support and prints Ubuntu/Debian install instructions
- Bot output now strips ANSI color escape codes before sending messages to Telegram
- `/doctor` output no longer shows raw `[0;34m` codes in Telegram

### Tests

- Added self-test coverage for `strip_ansi()` and `safe_output()` ANSI stripping
- Added bot mock checks for `strip_ansi` function and venv guidance in `run.sh`

## v1.1.1 — Telegram Bot Safety Polish

### Fixed

- Confirmation mismatch no longer clears pending rotate action
- Owner receives "Unknown command" for unsupported commands instead of "Unauthorized."
- Bot startup logs no longer print the numeric owner Telegram ID

### Tests

- Expanded Bot self-test for confirmation mismatch preserves pending
- Expanded Bot self-test for matched pop clears pending

## v1.1.0 — Telegram Bot Foundation

### Added

- Telegram Bot skeleton under `bot/`
- Owner-only command authorization (`OWNER_TELEGRAM_ID`)
- `/status`, `/status_json`, `/doctor` commands
- `/rotate_all`, `/rotate_hy2`, `/rotate_tuic`, `/rotate_reality`, `/rotate_trojan` with confirmation flow
- Safe nanobk CLI subprocess wrapper (no `shell=True`)
- Output redaction (tokens, passwords, keys)
- Message length limiting for Telegram
- `NANOBK_BOT_DRY_RUN` mode for testing rotate without execution
- `bot/run.sh` — one-command bot startup with auto venv
- `bot/systemd/nanobk-telegram-bot.service.example` — systemd unit
- `tests/bot-cli-mock.sh` — bot self-test without Telegram connection

### Security

- Bot never directly reads or writes NanoBK secrets/profile/config
- Bot token and owner ID loaded from untracked `.env`
- Rotate actions require explicit `/confirm_rotate_*` (120s expiry)
- All output passes through `redact_text()` and `limit_text()`
- Unauthorized users get "Unauthorized." — no owner ID leaked

## v1.0.3 — Installed Rotate and Reality Rotation Hotfix

### Fixed

- Installed `/opt/nanobk/bin/rotate-keys.sh` can now locate helper libraries
- Installer copies required helper libs into `/opt/nanobk/lib/`
- `rotate all` and `rotate reality` use unified hardened Xray x25519 parser
- Shared parser supports new Xray output format: `Password (PublicKey):`
- Single `parse_xray_x25519_output()` used by both install and rotate

### Verified

- Ubuntu 24.04 clean install works
- Installed healthcheck works
- Source-tree and installed-layout rotate tests cover tuic, reality, and all
- Production hotfix static tests cover 7 x25519 format variations

## v1.0.2 — Production Installer Hotfix

### Fixed

- Support bare binary Hysteria release assets (not just tar.gz)
- Support bare binary TUIC release assets (not just zip)
- Harden Xray Reality x25519 keypair parsing (case-insensitive, space-tolerant)
- Make TUIC config compatible with tuic-server 1.0.0
- Remove unsupported `udp_relay_mode` from TUIC template
- Remove incompatible integer `gc_interval` / `gc_lifetime` from TUIC template
- Add `log_level` to TUIC template

### Verified

- Ubuntu 24.04 production VPS install hotfixed successfully
- HY2 UDP 443 active
- TUIC UDP 9443 active
- Reality TCP 8443 active
- Trojan TCP 2443 active

## v1.0.0 — CLI Core Release

### Added

- **One-line bootstrap installer** (`installer/bootstrap.sh`)
  - Remote curl bootstrap: `bash <(curl -fsSL .../bootstrap.sh)`
  - Auto clone/pull repository
  - Safe directory handling (won't overwrite non-NanoBK repos)
  - `--dry-run`, `--install-dir`, `--branch` support
- **Interactive main installer** (`installer/install.sh`)
  - 9-option Chinese menu: VPS, Cloudflare, nanob, full wizard, rotate, doctor, test, commands
  - `--mode` for non-interactive use
  - `--dry-run` and `--yes` support
  - `--repo-dir` for custom repository paths
- **VPS four-protocol deployment** (`installer/install-vps.sh`)
  - HY2 (UDP 443), TUIC v5 (UDP 9443), VLESS Reality (TCP 8443), Trojan TLS (TCP 2443)
  - `--render-only` mode for safe local testing
  - `--dry-run`, `--cert-mode existing/self-signed/none`
  - Auto IP detection and Geo labeling via ipwho.is
  - Profile JSON generation for Cloudflare KV
- **Cloudflare nanok deployment** (`installer/install-cloudflare.sh`)
  - KV namespace creation
  - Worker deployment from local source
  - Profile upload via admin API
  - Subscription and admin endpoint verification
  - `--dry-run`, `--force`, `--skip-profile-upload`, `--skip-verify`
- **Optional nanob aggregator deployment**
  - `--deploy-nanob` flag
  - Geo KV namespace for ipwho.is caching
  - `--edge-host` / `--edgetunnel-export-token` for optional edgetunnel
  - edgetunnel failure never blocks primary subscription
- **Unified `nanobk` CLI** (`bin/nanobk`)
  - `nanobk status` — VPS config, profile, services, Cloudflare state
  - `nanobk --json status` — JSON output for Bot/Panel integration
  - `nanobk doctor` — environment diagnostics
  - `nanobk install` — launch interactive installer
  - `nanobk install-cli` — symlink to `/usr/local/bin/nanobk`
  - `nanobk cf deploy` — Cloudflare Worker deployment
  - `nanobk rotate all|hy2|tuic|reality|trojan` — key rotation
  - `nanobk test [--all]` — local safety tests
  - `nanobk version` — version output
  - Global `--dry-run`, `--json`, `--repo-dir`
- **Full key rotation** (`vps/scripts/rotate-keys.sh`)
  - Staged credentials (generate first, commit only after success)
  - Backup with unique per-protocol filenames
  - Automatic rollback on any failure
  - Cloudflare sync with per-protocol verification
  - `--protocol all|hy2|tuic|reality|trojan` for single-protocol rotation
  - `--skip-cloudflare`, `--skip-services`, `--allow-placeholder-reality`
- **Safe env parsing**
  - `read_env_value()` awk-based parser (no shell execution)
  - Cloudflare local env files read without `source`
  - Malicious env lines (command substitution, bare commands) are NOT executed
- **Token fingerprinting**
  - `fingerprint_secret()` using sha256 (first 8 hex chars)
  - Status output never prints full tokens
- **Test suite**
  - `tests/bootstrap-dry-run.sh` — bootstrap command preview
  - `tests/render-install-vps.sh` — VPS config rendering offline
  - `tests/rotate-render-only.sh` — key rotation offline (all + single-protocol)
  - `tests/wrangler-nanok-dry-run.sh` — nanok bundle test
  - `tests/wrangler-nanob-dry-run.sh` — nanob bundle test
  - `tests/nanobk-cli-dry-run.sh` — CLI command tests
  - `tests/nanobk-status-cloudflare.sh` — Cloudflare status + security test

### Security

- `secrets.private.env` mode 600
- Reality private key excluded from profile JSON
- YAML control character sanitization (prevents `yaml: control characters are not allowed`)
- Cloudflare/admin tokens never printed in full (fingerprint only)
- Local env files parsed without `source`/`exec` (awk-based `read_env_value`)
- `--yes` blocked for destructive modes without `--dry-run`
- Wrangler bundle tests back up and restore existing `wrangler.toml`

### Known Limitations

- Let's Encrypt automation not included in v1.0
- Telegram Bot not included in v1.0
- Web Panel not included in v1.0
- edgetunnel deployment automation not included in v1.0
- Full production E2E test still requires a real VPS and Cloudflare account
