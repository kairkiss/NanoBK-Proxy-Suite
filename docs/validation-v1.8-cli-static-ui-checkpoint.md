# NanoBK v1.8 CLI Static UI Acceptance Checkpoint

## 1. Purpose

This is the **v1.8 CLI static UI phase acceptance closure document**. It is NOT a real deployment acceptance test.

This checkpoint proves:

- CLI display mode boundaries are correct.
- dry-run Summary is honest.
- Secret safety is intact.
- Default / Compact / Plain / UI=0 four-mode semantics are clear.
- v1.7.27 stable installation logic was not intentionally changed.

This checkpoint does NOT prove:

- Real VPS clean install.
- Real Cloudflare deploy.
- Worker verify.
- Rotate sync.
- Bot/Web real control plane availability.
- Real subscription node availability.

## 2. Baseline

- **v1.7.27** is the Full Wizard Productization Final (tag: `v1.7.27`).
- **v1.8.0–v1.8.18** built CLI UI polish on top of v1.7.27.
- `installer/install.sh` is a high-risk core file — v1.8 must not break stage logic, strict menus, Summary honesty, recovery, or resume.
- All v1.8 changes to install.sh are display-only (version bumps, mode-aware helpers, section headers).

## 3. What v1.8.0–v1.8.18 Completed

| Version | Key Achievement |
|---------|----------------|
| v1.8.0 | UI display layer (`ui.sh`), operation-log redaction skeleton |
| v1.8.1 | Plain mode ANSI/emoji fallback hardening |
| v1.8.2 | Test pipefail stability fix |
| v1.8.3 | CLI visual snapshot tests, Full Wizard dry-run smoke |
| v1.8.4 | Token safety wording polish, recovery block wording |
| v1.8.5 | Dry-run layout snapshot tests |
| v1.8.6 | Manual visual acceptance guide |
| v1.8.7 | Mock/dry-run existing-state wording polish |
| v1.8.8 | Dry-run Summary skip honesty fix |
| v1.8.9 | Validation checkpoint, decision matrix |
| v1.8.10 | Brand banner / CLI identity |
| v1.8.11 | Brand banner width fix |
| v1.8.12 | CLI stage page cards |
| v1.8.13 | Compact mode (`NANOBK_COMPACT=1`) |
| v1.8.14 | Visual comparison guide (four-mode manual review) |
| v1.8.15 | Plain/UI=0/Compact visible Unicode boundary fix |
| v1.8.16 | Plain/UI=0/CI ANSI boundary fix |
| v1.8.17 | Interactive Plain/UI=0 ANSI cleanup |
| v1.8.18 | UI=0 Summary Unicode dash fix |

### Capabilities delivered

- `installer/lib/ui.sh` — display layer with 20+ functions
- `installer/lib/operation-log.sh` — redaction skeleton
- `NANOBK_PLAIN=1` — no ANSI, no emoji, no Unicode
- `NANOBK_UI=0` — legacy minimal output
- `NANOBK_COMPACT=1` — shorter output (≤85% of default)
- `NANOBK_NO_EMOJI=1` — emoji disabled
- `CI=1` — ANSI auto-disabled
- `installer_has_color()` — central color mode check
- Brand banner, stage cards, token reminder, recovery block, dry-run notice
- 11 automated test suites with 700+ individual assertions

## 4. Phase 14 Manual Visual Comparison

**Date**: v1.8.14 baseline (commit `4bab18c`)

**Overall**: BLOCKED

**Reasons**:

- Plain mode not plain — full installer output still contained `╔║╚═✓■□──` characters.
- UI=0 still showed large box banner.
- Compact was not compact enough (line count > 85% of default).

**What passed**:

- Security grep: PASS
- dry-run honesty: PASS
- fake success guard: PASS
- Default mode: PASS with polish

## 5. Follow-up Fixes

### v1.8.15 — Visible Unicode Boundary Fix

- Plain full output: banner, preflight, tools status, section headers converted to plain ASCII.
- UI=0 main banner: plain text, no box drawing.
- Compact main banner: single-line format.
- `section_line()` helper: mode-aware (PLAIN/UI=0/COMPACT use plain text).
- `preflight_pass/fail/warn`: PLAIN/UI=0 use `OK`/`FAIL`/`WARN`.
- Tools status: PLAIN/UI=0 use `OK`/`FAIL`.
- Compact output reduced to ≤85% of default.

### v1.8.16 — ANSI Boundary Fix

- Added `installer_has_color()` helper checking `NANOBK_PLAIN`, `NANOBK_UI`, `CI`.
- Updated `log()`, `ok()`, `warn()`, `err()`, `print_cmd()`, `preflight_pass/fail/warn`, `section_line`, `mock_log`, `prompt`, `confirm`, `prompt_menu_choice`, Summary disclaimers, config confirmation headers.
- Plain/UI=0/CI full installer output: 0 ANSI escapes.

### v1.8.17 — Interactive ANSI Cleanup

- VPS domain warnings: `say_yellow()` replacement.
- Cloudflare URL/KV warnings: `say_yellow()` replacement.
- Port conflict, Preflight summary, select_language, show_menu, test menu: `installer_has_color()` gating.
- Commands-only and root-run warnings: `say_yellow()` replacement.
- Interactive Plain/UI=0 regression tests added.

### v1.8.18 — UI=0 Summary Unicode Dash Fix

- `ui_section()` UI=0 branch: `echo "── $title ──"` → `echo "$title"`.
- Single Unicode dash (`─`) check added to UI=0 and Plain boundary tests.
- Summary title boundary tests added for all four modes.

## 6. Final Four-Mode Status

### Default

- **PASS**
- Product-like UI with brand banner, stage cards, progress bars.
- Summary title with Unicode elements preserved.
- Long output but acceptable for first-time users.

### Compact

- **PASS with minor polish**
- Shorter than default (≤85% line count).
- No large banner, single-line section headers.
- Suitable for small SSH screens.
- Minor: one long Summary line remains.

### Plain

- **PASS**
- No ANSI escapes (verified: 0 in full output).
- No emoji, no box drawing, no Unicode dash/progress/checkmark.
- Suitable for logs/CI.

### UI=0

- **PASS**
- No ANSI escapes (verified: 0 in full output).
- No box drawing, no Unicode dash.
- Legacy minimal output.
- Section headers are plain text by design.

### Safety

- **PASS**
- No `TOKEN=`, `SECRET=`, `ADMIN_TOKEN=`, `SUB_TOKEN=`, `NANOB_TOKEN=`, `NANOBK_CF_API_TOKEN` in any mode output.
- No `status: success` in any mode output.

### dry-run honesty

- **PASS**
- `planned / dry-run` present.
- "没有执行真实部署" / "No real deployment was performed" present.
- No `installed`/`healthy`/`verified` fake success.

## 7. Remaining Limitations

- Default output still somewhat long (acceptable for first-time users).
- Preflight still has some operational feel.
- Telegram Bot dry-run defaults confirmation may appear twice (pre-existing).
- `[MOCK]` output still has some test flavor.
- Complex real command logs are not yet hidden by operation-log.
- Dynamic progress / mascot not implemented.
- Telegram Bot menu UI not yet productized.
- Web Panel Apple-style polish not yet started.

## 8. Next Decision

### A. Operation Log Low-risk Pilot

**Goal**: Begin hiding complex command output by default. Write detailed logs to redacted operation log. Show simple progress/status to user. Failure shows log path and recovery command.

**Risk**: Touches `run_cmd` / `run_critical_step`. High review required. Should start with one low-risk command path only.

**Recommendation**: Good next step if goal is "hide complex logs."

### B. Dynamic Progress / Mascot Pilot

**Goal**: Add lightweight progress / small expression. Improve emotional/product feel. No real command wrapping at first.

**Risk**: Can pollute non-TTY/CI if not carefully gated. Must respect PLAIN / UI=0 / CI.

**Recommendation**: Good next step if goal is "more alive CLI."

### C. Telegram Bot Menu Polish

**Goal**: `/start` menu, inline buttons, grouped status/rotate/Cloudflare/diagnosis/recovery. Still only calls `nanobk` CLI.

**Risk**: New subsystem scope. Should be v1.9.

**Recommendation**: Start after CLI static UI is accepted.

### D. Web Panel Apple-style Polish

**Goal**: Card UI, dark/light, mobile, Apple-like design.

**Risk**: Larger project. Should be separate later phase.

**Recommendation**: Not next immediate step.

## 9. Recommended Next Step

**Recommended next version**: v1.8.20 — Operation Log Low-risk Pilot

**Reason**: The CLI now has acceptable static UI boundaries. The largest remaining gap against the product goal is not visual text anymore; it is that complex command output is still not hidden by default. Operation-log should be introduced carefully as a low-risk pilot before dynamic progress / mascot.

**Alternative**: v1.8.20 — Dynamic Progress / Mascot Pilot, if the project owner prefers emotional UI before log hiding.

## 10. Safety Reminder

- Do NOT paste real tokens.
- Do NOT `cat` env files.
- Do NOT share real VPS IP / workers.dev / subscription URL.
- Bot/Web are control plane only.
- dry-run is not a real deployment.
