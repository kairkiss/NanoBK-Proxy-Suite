# NanoBK Proxy Suite Maintenance Map

> **Purpose:** This document helps future no-memory AI agents perform targeted fixes safely.
> It maps subsystems, ownership, protected areas, contracts, and test requirements.
> Read this before making any change.

---

## 1. Purpose

Future AI agents may have no memory of prior sessions. This map provides:

* what can be changed
* what must not be changed
* which files own which behavior
* which tests to run for each subsystem
* how to report changes
* how to avoid secret leaks
* how to do targeted fixes without broad refactors

**If a change is not covered here, ask the user before proceeding.**

---

## 2. Product goal

NanoBK Proxy Suite is a beginner-friendly VPS proxy automation suite:

* one-command installer (`bash <(curl ...)` or `bash installer/install.sh`)
* four-protocol VPS deployment (HY2, TUIC, Reality, Trojan)
* Cloudflare nanok/nanob subscription service
* Telegram Bot control plane
* Web Panel control plane
* safe status / doctor / recovery
* Chinese-first UI with English switch
* hidden secrets and auditable diagnostics
* automatic key rotation

**Architecture rule:** The CLI (`bin/nanobk`) is the single gateway to all secrets, configs, and operations. Bot and Web are control surfaces only — they call CLI via subprocess, never touch secrets or configs directly.

---

## 3. Protected core

These files/areas must not be changed casually. Changes require explicit task approval and careful review.

### 3.1 Deployment core (v1.7.27 baseline)

| File/area | Why protected |
|-----------|---------------|
| `installer/install.sh` deployment logic | Full Wizard stage logic, strict numbered menus, Summary status, resume, admin env install |
| `installer/doctor.sh` | Doctor logic unless doctor task specifically approved |
| `vps/scripts/` | VPS protocol templates (HY2, TUIC, Reality, Trojan) |
| `cloudflare/` | Cloudflare Worker core |
| `vps/scripts/rotate-keys.sh` | Rotate sync logic |
| `installer/install-cloudflare.sh` | Cloudflare deployment flow |

### 3.2 Control-plane boundaries

| File/area | Why protected |
|-----------|---------------|
| `bin/nanobk` command dispatch | CLI routing, run_cmd semantics, run_critical_step semantics |
| `lib/nanobk_redaction.py` | Shared redaction — never bypass |
| `bot/nanobk_bot.py` Bot/Web control-plane semantics | Owner-only, safe summary, advanced gating |
| Env files and secrets | Never read, write, or output real values |
| Systemd/config/secrets paths | `/etc/nanobk/`, `/root/.nanok-cf-admin.env` |

### 3.3 What "protected" means

* Do not refactor protected files for style or convenience.
* Do not change behavior without explicit task approval.
* Do not add features to protected files unless the task specifically approves it.
* Version constant updates (e.g., `VERSION="1.9.58"`) are acceptable if the task approves.

---

## 4. Subsystem ownership map

| Subsystem | Main files | Owns | Safe change examples | Dangerous changes | Required tests |
|-----------|-----------|------|---------------------|-------------------|----------------|
| **Installer / Full Wizard** | `installer/install.sh`, `installer/bootstrap.sh`, `installer/doctor.sh` | VPS deployment, Bot/Web env generation, language propagation, summary status | Fix i18n copy in env generation, fix test debt | Changing deployment stages, changing run_cmd, changing summary logic | `bash tests/installer-language-propagation-v1.9.49.sh` |
| **CLI / bin/nanobk** | `bin/nanobk` | Command dispatch, status JSON, doctor, rotate, version display | Update version constant, fix help text | Changing command routing, changing status JSON schema | `bash tests/cli-version-display-v1.9.58.sh`, `bash tests/unified-cli-ui-v1.8.sh` |
| **Redaction** | `lib/nanobk_redaction.py` | All text/JSON redaction, ANSI stripping | Add new redaction pattern, fix false positive | Removing redaction, bypassing redaction | Bot/Web self-tests (import redaction) |
| **Telegram Bot** | `bot/nanobk_bot.py`, `bot/run.sh` | Bot commands, i18n (BOT_TEXT), buttons, safe summary, advanced gating | Fix i18n copy, add button label | Adding direct file/env access, bypassing owner check | `bash tests/bot-cli-mock.sh`, `python3 bot/nanobk_bot.py --self-test` |
| **Web Panel** | `web/app.py`, `web/run.sh`, `web/templates/` | Web routes, i18n (WEB_TEXT), CSRF, login, status cards, advanced gating | Fix i18n copy, fix template text | Adding direct file/env access, bypassing CSRF | `bash tests/web-panel-mock.sh`, `python3 web/app.py --self-test` |
| **Web i18n** | `web/i18n.py` | WEB_TEXT dictionary, normalize_lang | Add/fix translation keys | Changing DEFAULT_LANG logic, removing keys | `python3 tests/web-i18n-minimal-v1.9.31.py`, `python3 tests/chinese-default-v1.9.48.py` |
| **Bot i18n** | `bot/nanobk_bot.py` (BOT_TEXT dict) | BOT_TEXT dictionary, normalize_lang | Add/fix translation keys | Changing DEFAULT_LANG logic, removing keys | `python3 tests/bot-language-command-v1.9.52.py`, `python3 tests/i18n-checkpoint-v1.9.32.py` |
| **Doctor summary** | `bot/nanobk_bot.py`, `web/app.py` (build_doctor_summary) | Doctor summary builder, display policy | Fix summary labels | Changing inference logic, removing display policy | `python3 tests/web-doctor-summary-v1.9.37.py`, `python3 tests/doctor-output-checkpoint-v1.9.38.py` |
| **Raw JSON / advanced** | `web/app.py`, `bot/nanobk_bot.py` | Advanced mode TTL, Raw JSON gating, locked panel | Fix gating copy | Removing gate, changing TTL, exposing raw JSON | `python3 tests/web-raw-json-soft-gate-v1.9.21.py` |
| **Rotate** | `vps/scripts/rotate-keys.sh`, `bin/nanobk` (cmd_rotate) | Key rotation, confirmation flow | Fix rotate output copy | Changing rotate logic, skipping confirmation | Rotate render tests |
| **Cloudflare** | `installer/install-cloudflare.sh`, `cloudflare/` | CF deployment, KV, subscription | Fix CF deploy output | Changing Worker code, changing KV schema | CF dry-run tests |
| **Tests** | `tests/` | Test harnesses, mock tests, self-tests | Add focused test, fix test debt | Weakening assertions, removing safety checks | Tests test themselves |
| **Docs / roadmap** | `docs/`, `README.md`, `CHANGELOG.md` | Documentation, version history, validation records | Add doc, update roadmap | Claiming features as implemented when not | N/A |

---

## 5. Bot maintenance contract

The Telegram Bot is a **control plane only**. It must:

* Call `nanobk` CLI for all operations (status, doctor, rotate) via subprocess.
* Never directly read/write configs, systemd files, secrets, or `.env` files.
* Enforce owner-only authorization for all commands.
* Provide safe summary by default (no raw IP/domain/token/URL).
* Gate `/status_json` behind advanced mode (15-minute expiry).
* Provide `/doctor` summary by default; full diagnostics only in advanced mode.
* Provide `/language` as guidance only (no env writes).
* Use shared redaction (`lib/nanobk_redaction.py`) for all output.
* Translate UI text via `BOT_TEXT` dictionary (en/zh, default zh).

**Rotate buttons** are guidance unless an explicit confirmed command flow is approved for the task.

---

## 6. Web maintenance contract

The Web Panel is a **control plane only**. It must:

* Call `nanobk` CLI for all operations via subprocess.
* Never directly read/write configs, systemd files, secrets, or `.env` files.
* Require login (token-based) and CSRF protection for all state-changing routes.
* Keep `/api/status` redacted and intentionally not gated by advanced mode.
* Gate Raw JSON UI behind advanced mode (15-minute expiry).
* Provide doctor summary by default; full diagnostics only in advanced mode.
* Language switch is session-only (does not persist to env).
* Use shared redaction (`lib/nanobk_redaction.py`) for all output.
* Translate UI text via `WEB_TEXT` dictionary in `web/i18n.py` (en/zh, default zh).
* Default bind to `127.0.0.1` (not exposed to internet).

---

## 7. Redaction contract

* Never leak real IP, domain, workers.dev URL, subscription URL, token, or private key.
* Use shared helper `lib/nanobk_redaction.py` (`redact_text`, `redact_json_obj`, `redact_json_text`).
* Do not bypass redaction in Bot or Web output.
* Raw JSON advanced mode does NOT mean unredacted — it is still redacted.
* Fingerprint/hash display policy remains a future task unless specifically approved.

---

## 8. Language/i18n contract

* Default language is `zh` (Chinese).
* `NANOBK_LANG=zh|en` controls installed/runtime default (written by installer to Bot/Web `.env`).
* Web session language switch is temporary (session-only, cleared on logout).
* Bot `/language` is guidance only (no env writes).
* Raw JSON keys and `/api/status` schema are NOT translated.
* Machine values (`healthy`, `failed`, `unknown`, `active`, `configured`, `present`, `missing`, `ok`) remain stable English by design.
* Bot i18n: `BOT_TEXT` dict in `bot/nanobk_bot.py`, `bt()` helper.
* Web i18n: `WEB_TEXT` dict in `web/i18n.py`, `wt()` helper, `t()` template function.

---

## 9. Doctor contract

* Beginner doctor output is a safe summary (no raw IP/domain/token/URL).
* Full diagnostics are advanced-mode only (15-minute expiry).
* Full diagnostics may show technical structure but must be redacted.
* Doctor does NOT directly read env files.
* Doctor does NOT use a production status wrapper.
* Doctor does NOT wrap dirty VPS status as clean.
* Doctor summary builder: `build_doctor_summary()` in Bot and Web (independently implemented, cross-checked).

---

## 10. Version/tag contract

* Version display is `1.9.58` (set in `bin/nanobk`, `installer/install.sh`, `installer/bootstrap.sh`).
* Version display does NOT imply a release tag.
* No tag/release without explicit user approval.
* Stable tag requires closeout checkpoint (v1.9.60) and all gate items resolved.

---

## 11. Standard test matrix by change type

| Change type | Required tests |
|-------------|----------------|
| **Bot-only** | `bash tests/bot-cli-mock.sh`, `python3 bot/nanobk_bot.py --self-test` |
| **Web-only** | `bash tests/web-panel-mock.sh`, `python3 web/app.py --self-test` |
| **Web i18n** | `python3 tests/web-i18n-minimal-v1.9.31.py`, `python3 tests/chinese-default-v1.9.48.py`, `python3 tests/web-language-switch-v1.9.51.py`, `python3 tests/web-chinese-copy-polish-v1.9.57.py` |
| **Bot i18n** | `python3 tests/bot-language-command-v1.9.52.py`, `python3 tests/i18n-checkpoint-v1.9.32.py` |
| **Redaction** | Bot self-test, Web self-test, `python3 tests/web-raw-json-soft-gate-v1.9.21.py` |
| **Doctor** | `python3 tests/web-doctor-summary-v1.9.37.py`, `python3 tests/doctor-output-checkpoint-v1.9.38.py` |
| **Installer** | `bash tests/installer-language-propagation-v1.9.49.sh`, installer mock tests |
| **CLI** | `bash tests/cli-version-display-v1.9.58.sh`, `bash tests/unified-cli-ui-v1.8.sh` |
| **Docs-only** | `git diff --check`, security grep |
| **Version-only** | `bash tests/cli-version-display-v1.9.58.sh` |
| **Test-only** | Run the modified test + relevant subsystem tests |
| **Release/tag** | ALL tests, user explicit approval, closeout checkpoint |

---

## 12. Change report checklist

Every change must include:

1. **Branch** — current branch name
2. **Commit** — commit hash and message
3. **Files changed** — list of modified/added files
4. **install.sh changes** — must be none unless task specifically approves
5. **Core code changes** — what changed and why
6. **Tests run** — which tests passed
7. **Security checks** — grep for secrets in changed files
8. **Known limitations** — what was NOT done
9. **git log -1** — verification output
10. **Push status** — pushed to origin/main
11. **Recommendation** — suggested next step

---

## 13. Never do list

* `cat bot/.env`, `cat web/.env`, or any real env file
* Paste or output real tokens, keys, IPs, domains, URLs
* Run real deploy unless the task specifically approves
* Run real rotate unless the task specifically approves
* Mutate Cloudflare unless the task specifically approves
* Tag/release unless the task specifically approves
* Let Bot/Web write system configs, systemd files, or secrets directly
* Expose raw subscription URL or token in any output
* Bypass redaction in Bot/Web output
* Weaken test assertions
* Refactor protected files for style or convenience
