# Changelog

## v1.6.5 — Noninteractive Test Timeout Guard Hotfix

### Fixed

- Added timeout guards to `unified-noninteractive-mode.sh`
- Added timeout guards to installer-level override tests in `unified-test-failure-propagation.sh`
- Prevented noninteractive test scripts from hanging indefinitely if installer regressions reappear

### Safety

- Timeout fallback remains compatible with systems that do not provide the `timeout` command
- This release only hardens offline tests and does not change deployment behavior

## v1.6.4 — Test Failure Propagation Verification Hotfix

### Fixed

- Reset test failure state at the start of each test mode run
- Added a test-only override hook (`NANOBK_TEST_OVERRIDE_SCRIPT`) for verifying child test failure propagation
- Extracted `finalize_test_mode()` as reusable function
- Strengthened `unified-test-failure-propagation.sh` with real installer-level failure and success cases

### Safety

- `--mode test --defaults` can now be tested to ensure child failures produce non-zero exit codes
- The test override hook only affects test mode and does not change deployment behavior

### Tests

- Rewrote `tests/unified-test-failure-propagation.sh` with real installer-level dynamic tests

## v1.6.3 — Unified Installer Dependency and Test Failure Hotfix

### Fixed

- Cloudflare-only mode now stops early when `/etc/nanobk/profile.current.json` is missing
- Cloudflare-only mode now shows beginner-friendly recovery commands instead of low-level profile validation errors
- Test mode now propagates child test failures and exits non-zero when any safe test fails
- Test mode now prints failed test names

### Safety

- Cloudflare deployment is no longer previewed as executable when the VPS profile dependency is missing
- `--mode test --defaults` can no longer report success while child tests failed

### Tests

- Added `tests/unified-cloudflare-dependency.sh`: profile dependency guard coverage
- Added `tests/unified-test-failure-propagation.sh`: test failure propagation checks

## v1.6.2 — Unified Installer Recovery and Noninteractive Hotfix

### Fixed

- Fixed `--mode commands --dry-run` hanging on language selection
- Fixed `--mode test --defaults` hanging in noninteractive test flow
- Added cert-mode input validation and recovery for common typos such as `self-`
- Prevented Cloudflare stage from running when VPS profile is missing
- Made full wizard stage dependencies stricter
- Improved summary states for failed, skipped, dependency missing, and control-plane-only cases
- Added stronger token safety warnings before Bot/Web credential handling

### Safety

- Full wizard no longer continues Cloudflare deployment after VPS failure by default
- Bot/Web configuration after VPS failure is clearly marked as control-plane-only
- Recovery commands are shown after failed stages

### Tests

- Added `tests/unified-noninteractive-mode.sh`: commands/test noninteractive coverage
- Added `tests/unified-failure-recovery.sh`: failure recovery and stage dependency checks

## v1.6.1 — Validation Plan Safety Polish

### Fixed

- Added `unified-validation-plan.sh` to installer All safe tests
- Removed unsafe `cat bot/.env` and `cat web/.env` validation instructions
- Replaced raw env output with presence-only checks for tokens and secrets
- Clarified Cloudflare Workers requirement wording

### Safety

- Validation docs now avoid printing Bot/Web tokens or secrets
- Human testers are reminded not to paste `.env` contents into chat, logs, or issues

## v1.6.0 — Unified Installer Clean VPS Full Wizard Validation Prep

### Added

- Added clean VPS full wizard validation plan output (`--mode validate-plan`)
- Added `docs/validation-v1.6-clean-vps.md` with complete acceptance test plan
- Added validation-plan offline test
- Added clearer dry-run and commands-only summary boundaries

### Safety

- Dry-run summaries no longer imply real deployment
- Commands-only mode explicitly states that it does not validate the system
- Real VPS and Cloudflare validation must be performed by a human tester

### Tests

- Added `tests/unified-validation-plan.sh`: validate-plan mode coverage
- Updated `tests/unified-beginner-flow.sh`: dry-run/commands boundary assertions

## v1.5.2 — Dry-run Preflight Safety Hotfix

### Fixed

- Dry-run preflight no longer fails because real VPS ports are occupied
- Dry-run port checks now report `assumed free (dry-run)`
- Core port conflict re-check no longer recurses when `ss` is unavailable
- Fixed a non-recursive fallback when `ss` is unavailable during port re-check
- VPS summary now says `installed / not healthchecked` unless service health was actually verified

### Safety

- `--mode full --dry-run --defaults` remains safe even on systems with occupied ports
- Combo dry-run modes remain safe and do not write Bot/Web env files

### Tests

- Added `tests/unified-dry-run-preflight.sh`: dry-run not blocked by port occupation
- Updated `tests/unified-beginner-flow.sh`: assumed free and honest summary checks
- Updated `tests/unified-preflight-static.sh`: assumed free and ss unavailability assertions

## v1.5.1 — Unified Installer Safety and Fidelity Hotfix

### Fixed

- Blocked `--defaults` from running real deployments in combo modes (cli-only, cli-bot, cli-web, cli-bot-web)
- Removed misleading "skip protocol" behavior from core port conflict handling
- Added unified preflight to CLI combo modes (cli-only, cli-bot, cli-web, cli-bot-web)
- Made setup summary more honest about planned/configured/verified states
- Updated installer test mode to run current safe test suites (20 tests)
- Fixed stale installer header version (v1.4.0 → v1.5.1)
- Fixed `nanobk-status-cloudflare.sh` regression (symlink conflict case)

### Safety

- Combo modes now require interactive confirmation for real deployment
- Dry-run remains safe and does not write Bot/Web env files
- Summary does not print full tokens or private keys
- Core port conflict handler shows "re-check" instead of fake "skip protocol"

### Tests

- Added `tests/unified-installer-safety.sh`: --defaults safety block coverage
- Updated `tests/unified-beginner-flow.sh`: combo preflight and honest summary checks
- Updated `tests/unified-preflight-static.sh`: no fake skip protocol assertions

## v1.5.0 — Unified Beginner Installer Practical Flow

### Added

- Expanded unified beginner installer with 10 installation modes
- New combo modes: `cli-only`, `cli-bot`, `cli-web`, `cli-bot-web`
- Added unified preflight checks for OS, architecture, dependencies, ports, disk, and memory
- Added port conflict detection for HY2 (443), TUIC (9443), Reality (8443), Trojan (2443), Web Panel (8080)
- Added guided Cloudflare preparation with Node.js >=22 detection and Wrangler login guidance
- Added guided Bot configuration with python3-venv check and owner ID validation
- Added guided Web Panel configuration with 0.0.0.0 warning and SSH tunnel hint
- Added comprehensive final summary with next-step commands
- Added fuller `--dry-run` and `--mode commands` outputs covering all stages

### Improved

- Full Recommended mode now runs preflight before deployment
- Bot configuration validates owner ID is numeric
- Web Panel warns when listening on 0.0.0.0 and offers to switch to 127.0.0.1
- Commands mode now outputs Bot/Web env templates with all required fields
- Summary shows Bot/Web listen address, dry-run status, and start commands

### Safety

- Dry-run does not write Bot/Web env files
- Saved installer config remains non-sensitive (no tokens/passwords)
- Tokens and private keys are not printed in summaries
- Bot `.env` and Web `.env` are always chmod 600

### Tests

- Added `tests/unified-beginner-flow.sh`: full dry-run flow coverage
- Added `tests/unified-preflight-static.sh`: preflight content validation

## v1.4.3 — Status and Environment Polish

### Fixed

- Fixed stale `nanob verify: pending` status after successful nanob verification
- Unified nanob local env verify status fields between installer and `nanobk status`
- Added `nanobk cf verify [nanok|nanob]` for re-verify / status refresh
- Added `--verify-nanok-only` and `--verify-nanob-only` to install-cloudflare.sh
- Added Python fallback for Cloudflare JSON field verification when `jq` is unavailable
- Improved Cloudflare rollback log wording
- Added safe env reader for install-cloudflare.sh verify-only mode

### Tests

- Added `tests/nanob-status-env.sh`: nanob verify status field test
- Added `tests/rotate-cloudflare-stale-read-mock.sh`: stale read retry coverage

## v1.4.2 — Cloudflare Sync Consistency Hotfix

### Fixed

- Added retry/backoff for Cloudflare profile verification after rotate sync
- Prevented stale `/admin/current` reads from causing immediate rotate rollback
- Added best-effort Cloudflare rollback when local rollback occurs after successful upload
- Added local/cloud `updatedAt` and SHA16 summary output for sync verification
- Added retry/backoff for nanok profile upload after Worker deploy
- Added retry/backoff for nanob subscription verification
- Updated nanob local env verify status after successful verification
- Fixed unified installer literal ANSI escape output (`echo` → `echo -e`)
- Fixed `--resume` with explicit `--mode` precedence (explicit --mode wins)

### Safety

- Reduces risk of local/cloud profile split-brain
- Cloudflare sync failures now include manual resync guidance
- Existing secret/token redaction behavior preserved

## v1.4.1 — Unified Installer Safety and Orchestration Hotfix

### Fixed

- Removed unsafe `source` loading for installer resume config
- Replaced installer config loading with a whitelist parser (`read_config_value`)
- Removed `eval` from installer prompt handling (`printf -v` instead)
- Added Cloudflare preflight and profile validation before deployment in unified flow
- Added VPS healthcheck and `nanobk status` after VPS deployment
- Improved full wizard error handling between stages
- Marked English UI as partial/reserved instead of complete

### Safety

- Malicious installer config files are not executed (no `source`, no `eval`)
- Invalid mode from config is warned and ignored
- Bot/Web env inputs validated for newlines and port format
- Web host `0.0.0.0` triggers a warning
- Dry-run still does not write `bot/.env`, `web/.env`, or installer config

## v1.4.0 — Unified Beginner Installer Foundation

### Added

- Unified beginner-friendly installer flow in `installer/install.sh`
- Language selection framework (Chinese default, English reserved)
- Mode selection: full, vps, cloudflare, bot, web, rotate, doctor, test, commands
- Cloudflare preflight/profile validation integration in unified flow
- Bot `.env` generation flow with auto-generated secrets
- Web Panel `.env` generation flow with auto-generated tokens
- Commands-only and dry-run planning modes
- Optional local installer config with `--save-config` and `--resume`
- `--defaults` flag for non-interactive mode with safe defaults
- `tests/unified-installer-dry-run.sh`: dry-run integration test
- `tests/unified-installer-config.sh`: config save/resume test

### Safety

- Dry-run does not modify system files, bot/.env, web/.env, or installer config
- Saved installer config excludes sensitive tokens
- Bot/Web secrets written only to dedicated `.env` files with mode 600
- `--yes` blocked for destructive modes without `--dry-run`

## v1.3.3 — Wrangler KV Parser Hotfix

### Fixed

- Improved KV namespace id parser for Wrangler 4.95 JSON output (`kv_namespaces[].id`)
- Added binding-aware parsing: picks correct namespace when multiple exist
- Parser covers JSON, TOML-style, compact, text, and mixed outputs
- Added `--test-parse-kv-id` for offline parser testing
- Fixed Cloudflare installer help version display (now uses `CLOUDFLARE_INSTALLER_VERSION` variable)

### Verified

- v1.3.2 real Cloudflare chain passed with manual KV id workaround
- v1.3.3 removes the manual KV id workaround requirement

## v1.3.2 — Cloudflare Wrangler 4 and nanob Service Binding Hotfix

### Fixed

- Updated KV namespace creation for Wrangler 4: `wrangler kv namespace create` (was `kv:namespace`)
- Added Node.js >=22 preflight detection for current Wrangler versions
- nanob now uses Cloudflare Service Binding (`NANOK_SERVICE`) to fetch nanok
- nanob wrangler.toml generation now includes a service binding to nanok
- Improved nanob verification diagnostics for primary subscription fetch failures

### Verified

- nanok deploy works with real Cloudflare
- nanok subscription YAML validates
- rotate + Cloudflare sync works
- nanob Service Binding hotfix verified in real Cloudflare

## v1.3.1 — Cloudflare Preflight Hotfix

### Fixed

- `--preflight` no longer requires KV deployment options
- Preflight no longer calls undefined `fail` / `info` helpers
- Dry-run validates existing profile files instead of skipping validation
- Added `--validate-profile-only` for offline profile safety tests
- Profile validation tests now assert installer exit codes

## v1.3.0 — Cloudflare Full Automation Validation

### Added

- `install-cloudflare.sh --preflight`: pre-deployment checks (wrangler, login, profile, sources)
- Cloudflare real validation guide (`docs/cloudflare-real-validation.md`)
- Profile validation rejects private key leakage before upload
- Dry-run tests for nanok/nanob deployment planning
- Profile validation tests for Cloudflare upload safety
- Static nanob fallback tests
- Clearer edgetunnel optional integration documentation

### Improved

- Better wrangler login diagnostics (remote VPS guidance)
- Safer profile validation before upload (private key check)
- More explicit nanob fallback behavior when edgetunnel is disabled

### Security

- Profile validation rejects `privateKey`, `REALITY_PRIVATE_KEY`, `private_key` in profile JSON
- Worker tokens are fingerprinted in output
- edgetunnel export token is never written to `wrangler.toml`

## v1.2.1 — Web Panel Security Polish

### Fixed

- Web Panel now rejects default or empty `NANOBK_WEB_SECRET_KEY`
- Removed Flask fallback static session secret
- `/api/status` now returns redacted JSON on success
- Status raw JSON is redacted before display
- Added lightweight CSRF protection for authenticated POST actions
- Logout now uses POST instead of GET

### Tests

- Added Web Panel self-test coverage for secret validation, JSON redaction, and CSRF
- Expanded mock test checks for CSRF fields, redact_json, safe logout, and /api/status redaction

## v1.2.0 — Web Panel Foundation

### Added

- Local-only Flask Web Panel under `web/`
- Token-based login (single shared token, no user system)
- Dashboard with quick status overview
- `/status` page with formatted display and raw JSON
- `/api/status` JSON API endpoint
- `/doctor` page with run button
- `/rotate` page with protocol selection and confirmation flow
- `/healthz` endpoint (no auth, for monitoring)
- Dry-run mode for rotate testing
- Safe nanobk CLI subprocess wrapper (no `shell=True`)
- ANSI stripping, output redaction, and length limiting
- `web/run.sh` with Python venv guidance
- `web/systemd/nanobk-web-panel.service.example`
- Web panel self-test and mock test script

### Security

- Web Panel binds to `127.0.0.1:8080` by default (not exposed to internet)
- Web Panel never directly reads or writes NanoBK secrets/profile/config
- Rotate actions require explicit confirmation (120s expiry)
- Login token must be changed from default
- `.env` is gitignored

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
