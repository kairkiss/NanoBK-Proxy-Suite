# Test Matrix

All test scripts in `tests/` are designed to be safe for local development. None modify real Cloudflare resources or VPS configurations unless explicitly configured.

## Test Scripts

| Test | Purpose | Network | System changes | Cloudflare real | macOS | CI |
|------|---------|:-------:|:--------------:|:---------------:|:-----:|:--:|
| `bootstrap-dry-run.sh` | Bootstrap command preview | No | No | No | ✅ | ✅ |
| `render-install-vps.sh` | Render VPS configs offline | No | No | No | ✅ | ✅ |
| `rotate-render-only.sh` | Key rotation offline (all + single-protocol) | No | No | No | ✅ | ✅ |
| `wrangler-nanok-dry-run.sh` | nanok Worker bundle test | Maybe¹ | No | No | ✅ | ✅ |
| `wrangler-nanob-dry-run.sh` | nanob Worker bundle test | Maybe¹ | No | No | ✅ | ✅ |
| `nanobk-cli-dry-run.sh` | CLI command dry-run tests | No | No | No | ✅ | ✅ |
| `nanobk-status-cloudflare.sh` | Status JSON + security test | No | No | No | ✅ | ✅ |
| `production-hotfix-static.sh` | TUIC template + x25519 parser + download patterns | No | No | No | ✅ | ✅ |
| `installed-layout-rotate.sh` | Installed layout rotate (tuic/reality/all) | No | No | No | ✅ | ✅ |
| `bot-cli-mock.sh` | Bot self-test (no Telegram connection) + ANSI stripping + venv guidance | No | No | No | ✅ | ✅ |
| `web-panel-mock.sh` | Web panel self-test (no Flask server) + safety checks | No | No | No | ✅ | ✅ |
| `cloudflare-installer-dry-run.sh` | Cloudflare installer dry-run (no real Cloudflare) | No | No | No | ✅ | ✅ |
| `cloudflare-profile-validation.sh` | Profile JSON validation (private key rejection) | No | No | No | ✅ | ✅ |
| `nanob-fallback-static.sh` | nanob fallback to primary when edgetunnel disabled | No | No | No | ✅ | ✅ |
| `cloudflare-kv-parser.sh` | KV namespace ID parser (Wrangler 4 JSON, TOML, text) | No | No | No | ✅ | ✅ |
| `unified-installer-dry-run.sh` | Unified installer dry-run (modes, safety, language) | No | No | No | ✅ | ✅ |
| `unified-installer-config.sh` | Installer config save/resume (no sensitive tokens) | No | No | No | ✅ | ✅ |
| `cloudflare-sync-retry-static.sh` | rotate Cloudflare verify retry/rollback logic | No | No | No | ✅ | ✅ |
| `unified-installer-resume.sh` | --resume + explicit --mode precedence | No | No | No | ✅ | ✅ |
| `nanob-status-env.sh` | nanob verify status field consistency | No | No | No | ✅ | ✅ |
| `rotate-cloudflare-stale-read-mock.sh` | Cloudflare stale read retry logic | No | No | No | ✅ | ✅ |

¹ Wrangler may download npm packages on first run.

## Running All Tests

```bash
# Core tests (no wrangler needed)
bash tests/bootstrap-dry-run.sh
bash tests/render-install-vps.sh
bash tests/rotate-render-only.sh
bash tests/nanobk-cli-dry-run.sh
bash tests/nanobk-status-cloudflare.sh

# Bundle tests (requires wrangler)
bash tests/wrangler-nanok-dry-run.sh
bash tests/wrangler-nanob-dry-run.sh

# Or use nanobk CLI
bash bin/nanobk test        # core tests
bash bin/nanobk test --all  # includes wrangler bundle tests
```

## What Each Test Verifies

### bootstrap-dry-run.sh
- Bootstrap syntax check
- `--help` output
- `--dry-run` shows clone/install commands without executing
- Passthrough args to install.sh
- No `eval` in bootstrap

### render-install-vps.sh
- VPS config rendering to temp directory
- All 14 expected files generated
- Secrets permissions (mode 600)
- JSON configs valid
- Profile has all four protocols
- Reality private key NOT in profile
- No unreplaced placeholders
- Offline healthcheck passes

### rotate-render-only.sh
- **Test A**: Full rotation — all credentials change, profile valid
- **Test B**: Rollback on failure — restores per-protocol backup files
- **Test C**: Single-protocol matrix — hy2/tuic/reality/trojan individually
  - Only target protocol's secrets change
  - Only target protocol's profile fields change
  - Other protocols unchanged
  - Reality private key NOT in profile

### wrangler-nanok-dry-run.sh
- nanok Worker can be bundled by Wrangler
- Bundle output contains index.js
- Existing wrangler.toml is backed up and restored

### wrangler-nanob-dry-run.sh
- nanob Worker can be bundled by Wrangler
- Bundle output contains index.js
- Existing wrangler.toml is backed up and restored

### nanobk-cli-dry-run.sh
- Command-level `--dry-run` works for test/doctor
- Global `--dry-run` works for test/doctor
- `--json status` produces valid JSON
- Missing config → `ok: false` in JSON
- JSON escape handles special characters
- Single-protocol rotate passes `--protocol` flag
- No `eval` in nanobk

### nanobk-status-cloudflare.sh
- JSON output is valid
- Cloudflare nanok/nanob env fields present
- Token fingerprints present (not full tokens)
- **Malicious env NOT executed**: command substitution `$(touch ...)` and bare `touch ...` in env files are NOT run
- Text output has Cloudflare and Aggregator sections
- No secret leakage in text or JSON output
- `install-cli --dry-run` works without root
