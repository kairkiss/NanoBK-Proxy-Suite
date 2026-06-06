# Changelog

## v1.9.57 — Web Chinese Copy Polish / i18n Coverage Fix

### Fixed

- Fixed T17-P2-003: Web Chinese mode "Next step" copy residue.
- Root cause: `_next_step_hint()` in `web/app.py` returned hardcoded English strings for status card next-step hints, bypassing the i18n system entirely.
- Added 6 new i18n keys in `web/i18n.py`: `next_step_check_ssh_recovery`, `next_step_check_ssh_services`, `next_step_finish_cf`, `next_step_verify_subscription`, `next_step_no_action`, `next_step_run_doctor`.
- Modified `_next_step_hint()` to accept `lang` parameter and use `wt()` for translated output.
- Modified `_build_safe_cards()` and `format_status()` to propagate `lang` parameter.
- Dashboard and status routes now pass `config.lang` to `format_status()`.
- zh mode now returns Chinese text for all next-step hints.
- en mode returns English text (unchanged behavior).
- Machine values (healthy/failed/unknown/active/etc.) remain English by design.
- Raw JSON keys not translated. `/api/status` unchanged.
- No Bot, installer, CLI, redaction, gating, advanced mode, rotate, or deployment changes.

### Safety

- Web i18n/copy only.
- No Bot runtime behavior changed.
- No `installer/install.sh` behavior changed.
- No CLI behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.56 — Installer Language Propagation Test Debt Fix

### Fixed

- Fixed T17-TEST-002: `tests/installer-language-propagation-v1.9.49.sh` false-positive env-cat checks.
- Root cause: test grep matched safety warning text (`echo "不要执行 cat bot/.env"`, heredoc `⚠ Do NOT cat bot/.env`) instead of executable env reads.
- macOS was unaffected because `grep -P` (PCRE) is unavailable, causing the check to silently skip.
- Fix: added filters for comment lines, echo/printf statements, and heredoc/documentation content (lines not starting with a valid shell command character).
- Switched from `grep -P` (PCRE, non-portable) to `grep -vE` (ERE, POSIX-compatible) for all filtering.
- All 22 installer language propagation tests now pass.
- Real executable env reads (`cat bot/.env`, `$(cat bot/.env)`, `cat bot/.env | head`) are still correctly detected.
- No assertions weakened. No installer runtime behavior changed.
- No Bot, Web, CLI, redaction, gating, advanced mode, rotate, or deployment changes.

### Safety

- Test fix only.
- No `installer/install.sh` behavior changed.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.55 — Real Chinese/English Control Plane Smoke Validation

### Added

- Added T17 real Chinese/English control-plane smoke test validation document.
- Documented user-run real smoke test result: PASS WITH POLISH.
- Documented environment: Ubuntu 24.04.1 LTS, root, Python 3.12, dirty test VPS, existing four-protocol deployment.
- Documented Stage 0 baseline update (9 commits behind, fast-forwarded to `daa9740`).
- Documented Stage 1 preflight: installer language propagation test false-positive debt (T17-TEST-002), all other focused tests PASS.
- Documented Stage 2 Bot/Web restart and health: /healthz ok, four services active, no errors.
- Documented Stage 3 Web Chinese/English: default Chinese, English switch, switch back, logout session reset, safety regression — all PASS.
- Documented Stage 4 Bot Chinese: /start, /help, /language, /status, /doctor, /advanced, /status_json, button callbacks — all PASS.
- Documented Stage 5 final health: HEAD verified, processes running, services active.
- Documented leak check: no P0/P1 leaks, Advanced-only visible information acceptable.
- Documented issue matrix: 12 items, 0 P0, 0 P1, 1 test debt, 9 P2/known.
- Documented stable tag gate conditions.
- No Bot, Web, CLI, installer, redaction, gating, advanced mode, rotate, or deployment changes.

### Safety

- Documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `installer/install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tests added.
- No tag/release.

## v1.9.54 — Web Language Switch Test Debt Fix

### Fixed

- Fixed 5 pre-existing source-level check failures in `tests/web-language-switch-v1.9.51.py`.
- Root cause: `web_source.split("def language(")` matched 2 occurrences (actual route function + self-test string reference), producing 3 parts. `parts[1]` pointed to self-test code, not the route body.
- Fix: replaced brittle `split` with `re.search(r'^[ ]*def language\\(', web_source, re.MULTILINE)` to anchor to line-start function definition.
- All 5 previously failing checks now pass: `/language is POST only`, `/language requires login`, `/language validates CSRF`, `/language accepts lang form field`, `/language stores valid lang`.
- No assertions weakened. No Web runtime behavior changed.
- No Bot, installer, CLI, redaction, gating, advanced mode, rotate, or deployment changes.
- Added validation document `docs/validation-v1.9.54-web-language-switch-test-debt-fix.md`.

### Safety

- Test fix only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `installer/install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.53 — Chinese/English Control Plane Smoke Test Plan

### Added

- Added Chinese/English control-plane smoke test planning document.
- Defined safe user-run real smoke test scope: Bot startup, /start, /help, /language, /status, /doctor, /advanced, /status_json gate, Web startup, login, Dashboard, Status, Doctor, language switch zh/en, Raw JSON gate, /api/status, service health.
- Excluded from scope: deployment, Cloudflare mutation, real rotate, repair/restart, systemd, production runner, tag/release.
- Documented known preflight test debt: `tests/web-language-switch-v1.9.51.py` has 5 pre-existing source-level check failures (not caused by v1.9.52).
- Defined preflight decision: rerun test, record exact failures, classify as false positive or real issue before stable closeout.
- Defined Bot Chinese smoke checklist (10 steps) with leak checks.
- Defined Bot English strategy: defer full real test until persistent CLI language command exists.
- Defined Web Chinese/English smoke checklist (14 steps) with leak checks.
- Defined P0/P1/P2 leak classification and checklist.
- Defined copy-paste-safe user report template.
- Defined failure handling: stop on raw secret, stop on CSRF bypass, stop on gate breakage.
- Defined stable tag prerequisites: Chinese default verified, Web switch verified, Bot guidance verified, test debt resolved, no P0/P1, CLI version addressed.
- Defined verdict criteria: PASS, PASS WITH POLISH, BLOCKED.
- Readiness decision: READY FOR USER-RUN CHINESE/ENGLISH CONTROL PLANE SMOKE TEST AFTER CHATGPT REVIEW.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No installer behavior changed.
- No env files read or written.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.52 — Bot Language Command / Guidance Minimal Implementation

### Changed

- Added Bot `/language` command: owner-only, shows current runtime language and guidance.
- Added `build_language_guidance()` function with zh/en support.
- Added 10 i18n keys: `language_title`, `language_current_zh`, `language_current_en`, `language_source_explanation`, `language_default_zh`, `language_en_available`, `language_persistent_planned`, `language_no_env_write`, `language_usage`, `help_language`.
- Updated `/help` to include `/language` in Basic section.
- Registered `CommandHandler("language", cmd_language)`.
- Command does NOT call run_nanobk, does NOT write/read env, does NOT expose tokens.
- Guidance explains: current language from NANOBK_LANG, Chinese default, English available via NANOBK_LANG=en, persistent switching planned for future CLI/installer-safe command.
- Bot self-test expanded from 180 to 228 checks.
- Added focused Bot language command test (90 checks).
- Added validation document `docs/validation-v1.9.52-bot-language-command-guidance.md`.

### Safety

- Bot language guidance command only.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `installer/install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.51 — Web Session Language Switch Minimal Implementation

### Changed

- Added `get_current_lang()` helper: session["lang"] > config.lang > default zh.
- Updated `inject_i18n()` context processor to use `get_current_lang()`.
- Added `POST /language` route: login required, CSRF protected, accepts zh/en.
- Added language switch button in layout.html navigation bar.
- Added i18n keys: `lang_switch_to_en`, `lang_switch_to_zh`, `lang_changed`, `lang_invalid`.
- Session language override clears on logout/session expiry.
- No env writes. No Bot changes. No CLI changes. No installer changes.
- Added focused Web language switch test.
- Added validation document `docs/validation-v1.9.51-web-session-language-switch.md`.

### Safety

- Web session language switch only.
- No Bot runtime behavior changed.
- No CLI behavior changed.
- No `installer/install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No env files read or written.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.50 — Language Switch UX Planning

### Added

- Added Language Switch UX planning document.
- Compared Web language switch options: session-only (recommended), persistent env write (rejected), CLI call (future), static instructions (poor UX).
- Compared Bot language switch options: guidance-only (recommended first), in-memory switch, CLI call (future), direct env write (rejected).
- Defined persistent language strategy: CLI/installer-safe path for long-term persistent switching.
- Defined Web first implementation contract: `POST /language`, session storage, login + CSRF, layout buttons.
- Defined Bot first implementation contract: `/language` command, owner-only, current language display, safe guidance.
- Defined testing strategy for Web session switch and Bot language guidance.
- Defined stable tag language gate prerequisites.
- Defined AI maintenance interface interaction for language switching.
- Proposed implementation route: v1.9.51 Web session switch, v1.9.52 Bot guidance, v1.9.53-54 smoke tests, v1.9.55+ stable tag prep.
- Readiness decision: READY FOR WEB SESSION LANGUAGE SWITCH MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No installer behavior changed.
- No env files read or written.
- No deployment core, protocol template, Worker, rotate sync changed.
- No tag/release.

## v1.9.49 — Installer Bot/Web Language Propagation Minimal Implementation

### Changed

- Installer Bot env generation now writes `NANOBK_LANG=${LANG_CODE:-zh}` to bot/.env.
- Installer Web env generation now writes `NANOBK_LANG=${LANG_CODE:-zh}` to web/.env.
- `--lang zh` propagates `NANOBK_LANG=zh` to Bot/Web env.
- `--lang en` propagates `NANOBK_LANG=en` to Bot/Web env.
- Missing/invalid language falls back to `zh`.
- Full Wizard language selection automatically propagates via existing `LANG_CODE` global.
- chmod 600 preserved for both Bot and Web env files.
- No env contents printed. No tokens printed.
- VPS deployment, Cloudflare, rotate logic unchanged.
- Added focused installer language propagation test (22 checks).
- Added validation document `docs/validation-v1.9.49-installer-language-propagation.md`.
- Recommended v1.9.50 Language Switch UX Planning as next step.

### Safety

- Installer Bot/Web env propagation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.48 — Bot/Web Chinese Default Minimal Implementation

### Changed

- Changed Bot `DEFAULT_LANG` from `"en"` to `"zh"`. Missing/empty/invalid `NANOBK_LANG` now falls back to Chinese.
- Changed Bot `BotConfig.lang` default from `"en"` to `"zh"`.
- Changed Web `DEFAULT_LANG` from `"en"` to `"zh"`. Missing/empty/invalid `NANOBK_LANG` now falls back to Chinese.
- Changed Web `WebConfig.lang` default from `"en"` to `"zh"`.
- Explicit `NANOBK_LANG=en` still forces English for both Bot and Web.
- Slash command names unchanged. Status machine values unchanged.
- Redaction, Raw JSON gating, advanced mode, rotate behavior unchanged.
- Updated Bot i18n test (116 checks), Web i18n test (123 checks), i18n checkpoint test (167 checks).
- Updated Bot and Web embedded self-tests to expect Chinese default.
- Added focused Chinese default test (75 checks).
- Added validation document `docs/validation-v1.9.48-bot-web-chinese-default.md`.
- Total: 1,524 checks passed across all test suites.
- Recommended v1.9.49 Installer Bot/Web Language Propagation as next step.

### Safety

- Bot/Web default language change only.
- No installer behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.47 — Bot/Web Language Propagation and Chinese Default Planning

### Added

- Added Bot/Web language propagation and Chinese default planning document.
- Audited current i18n architecture: Bot `BOT_TEXT`/`bt()`, Web `WEB_TEXT`/`wt()`, both read `NANOBK_LANG`, default `en`.
- Identified gap: installer `select_language()` defaults Chinese but does not write `NANOBK_LANG` to bot/.env/web/.env.
- Identified gap: no user-facing language switch UX exists.
- Defined default language decision: Option C — follow installer language, fallback Chinese when missing.
- Defined installer propagation plan: `--lang zh|en` should write `NANOBK_LANG` to bot/.env/web/.env.
- Defined language switch strategy: staged hybrid — Web session switch, CLI persistent, Bot guidance.
- Defined implementation route: v1.9.48 default Chinese, v1.9.49 installer propagation, v1.9.50+ switch UX.
- Defined stable tag gate: Chinese default must be implemented before v1.9 stable tag.
- Defined AI maintenance interface plan for future no-memory AI targeted fixes.
- Readiness decision: READY FOR BOT/WEB CHINESE DEFAULT MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real status executed by Claude Code.
- No real doctor executed by Claude Code.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.46 — Real Doctor Field Compatibility Retest Validation

### Added

- Recorded T16 real Doctor field compatibility retest result: PASS WITH POLISH.
- T15-P2-001 confirmed fixed in real status data layer, real Bot UI, and real Web UI.
- Bot /doctor Advanced OFF now shows Profile present, Config present.
- Web /doctor Advanced OFF now shows Profile present, Config present.
- Advanced ON still shows warning + redacted full diagnostics.
- /status_json gate still works. Web Raw JSON gate still works.
- Dashboard/Status safe cards still work. Four protocol services remained active.
- No P0/P1 leak observed.
- Bot/Web derived summaries match on all key fields.
- Forbidden-fragment check PASS.
- Issue matrix: P0/P1 passed, P2 items for CLI version, systemd, Flask dev server, English default, advanced diagnostics engineering-oriented, fingerprint policy, duplicated builder logic.
- Recommended v1.9.47 Bot/Web Language Propagation and Chinese Default Planning as next step.

### Safety

- Documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real status executed by Claude Code.
- No real doctor executed by Claude Code.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.45 — Limited Real Doctor Field Compatibility Retest Plan

### Added

- Added limited real Doctor field compatibility retest planning document.
- Defined safe control-plane-only retest scope: Bot /doctor and Web /doctor Profile/Config field verification only.
- Defined Bot Doctor retest checklist (18 steps): Profile/Config present verification, Advanced OFF summary-only, Advanced ON summary + redacted full diagnostics, existing gates sanity.
- Defined Web Doctor retest checklist (19 steps): Profile/Config present verification, Advanced OFF summary cards, Advanced ON collapsed full diagnostics, Raw JSON gate sanity.
- Defined leak checklist with P0/P1 severity levels for forbidden observations.
- Defined copy-paste-safe user report template with no raw values.
- Defined failure handling: stop on raw secret, redacted reporting only.
- Readiness decision: READY FOR USER-RUN LIMITED REAL DOCTOR FIELD COMPATIBILITY RETEST AFTER CHATGPT REVIEW.
- Recommended user run the retest and report redacted PASS/FAIL.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real status executed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.44 — Doctor Summary Field Compatibility Checkpoint

### Added

- Added Doctor Summary field compatibility checkpoint validation document.
- Added field compatibility checkpoint test (242 checks).
- Verified Bot and Web `build_doctor_summary()` correctly consume v1.9.42 fixtures.
- Verified `profile.exists == true` maps to profile present in both Bot and Web.
- Verified `profile.exists == false` maps to profile missing.
- Verified `configDir` non-empty supports config present without path display.
- Verified `security.secretsExists` inference works correctly.
- Verified backward compatibility with v1.9.35 original fixtures.
- Verified no raw configDir path/IP/domain/URL/token in formatted output.
- Verified Bot/Web source markers: `--json status` in doctor handlers, `safe_output` for full diagnostics, no `shell=True`, no production status wrapper markers.
- Readiness decision: READY FOR LIMITED REAL DOCTOR FIELD COMPATIBILITY RETEST PLANNING.
- Recommended v1.9.45 Limited Real Doctor Field Compatibility Retest Plan as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No real status executed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.43 — Bot/Web Doctor Summary Field Compatibility Minimal Fix

### Changed

- Fixed T15-P2-001: Bot/Web Doctor Summary now correctly infers profile present from `profile.exists == true`.
- Fixed config inference: non-empty `configDir` and `security.secretsExists == true` now support config present.
- Fixed explicit missing: `profile.exists == false` now maps to profile missing.
- Bot `build_doctor_summary()` updated with profile.exists, configDir, secretsExists checks.
- Web `build_doctor_summary()` updated with identical semantics.
- Added test `tests/doctor-field-compatibility-runtime-v1.9.43.py` (282 tests).
- All v1.9.42 fixtures now consumed correctly by both Bot and Web builders.
- Backward compatible with v1.9.35 original fixtures.
- Added validation document `docs/validation-v1.9.43-doctor-field-compatibility-fix.md`.
- Recommended v1.9.44 Doctor Summary Field Compatibility Checkpoint as next step.

### Safety

- Bot/Web doctor summary builder fix only.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No raw configDir path displayed.
- No raw IP/domain/URL/token/private key in summary.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.42 — Doctor Summary Field Compatibility Fixture Tests

### Added

- Added 6 fake realistic status input fixtures under `tests/fixtures/doctor-field-compatibility-v1.9.42/`.
- Added 6 expected summary fixtures for field compatibility scenarios.
- Added fixture contract test `tests/doctor-field-compatibility-fixtures-v1.9.42.py` (294 checks).
- Defined mapping contract: `profile.exists == true` → present, `configDir`/`security.secretsExists` → config present, `profile.exists == false` → missing.
- Validated all expected summaries conform to v1.9.35 schema with display_policy flags true.
- Validated forbidden patterns absent from all expected summaries.
- Validated honesty rules: missing stays missing, unknown stays unknown, services missing → not healthy.
- Verified v1.9.35 contract fixtures still exist (regression).
- Readiness decision: READY FOR BOT/WEB FIELD COMPATIBILITY MINIMAL FIX AFTER CHATGPT REVIEW.
- Recommended v1.9.43 Bot/Web Doctor Summary Field Compatibility Minimal Fix as next step.

### Safety

- Fixture/test/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real status executed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.41 — Doctor Summary Real Status Field Compatibility Fix Planning

### Added

- Added Doctor Summary field compatibility fix planning document.
- Audited Bot and Web Doctor Summary builder profile/config inference logic.
- Identified root cause: real `nanobk --json status` uses `profile.exists` (boolean) and `security.secretsExists` (boolean), but builders only check `profile.currentPath`/`profile.domain`.
- Defined safe compatibility mapping: `profile.exists == true` → present, `configDir` non-empty or `security.secretsExists == true` → config present.
- Defined honesty rules: unknown stays unknown without evidence, missing beats inferred present, no raw paths displayed.
- Defined fixture/test plan for v1.9.42: 6 new realistic status fixtures, 7 test cases.
- Recommended v1.9.42 Doctor Summary Field Compatibility Fixture Tests as next step.
- Readiness decision: READY FOR FIELD COMPATIBILITY FIXTURE TESTS.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real status executed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.40 — Real Doctor Smoke Retest Validation

### Added

- Recorded T15 real Bot/Web Doctor smoke retest result: PASS WITH POLISH.
- Bot /doctor Advanced OFF showed safe summary only. Advanced ON showed warning + redacted full diagnostics.
- Web /doctor Advanced OFF showed summary cards only. Advanced ON showed warning + redacted full diagnostics.
- No P0/P1 security leakage observed.
- Four protocol services remained active. No deployment/protocol service breakage.
- Issue matrix: P2 Doctor Summary Profile/Config field compatibility, P2 advanced diagnostics engineering-oriented, P2 fingerprint redaction policy pending, P2 Web Doctor collapse state confirmation, P2 i18n mainly English, P1 systemd not productized, P2 Web uses Flask dev server.
- Readiness decision: PASS WITH POLISH.
- Recommended v1.9.41 Doctor Summary Real Status Field Compatibility Fix Planning as next step.

### Safety

- Documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real doctor executed by Claude Code.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.39 — Limited Real Bot/Web Doctor Smoke Retest Plan

### Added

- Added limited real Bot/Web Doctor smoke retest planning document.
- Defined safe control-plane-only retest scope: Bot /doctor and Web /doctor summary behavior only.
- Defined Bot Doctor retest checklist (18 steps): summary-only advanced OFF, summary + redacted full diagnostics advanced ON, existing gates sanity.
- Defined Web Doctor retest checklist (19 steps): summary cards advanced OFF, collapsed full diagnostics advanced ON, /api/status redaction sanity.
- Defined leak checklist with P0/P1/P2 severity levels for forbidden observations.
- Defined copy-paste-safe user report template with no raw values.
- Defined failure handling: stop on raw secret, redacted reporting only.
- Readiness decision: READY FOR USER-RUN LIMITED REAL BOT/WEB DOCTOR SMOKE RETEST AFTER CHATGPT REVIEW.
- Recommended user run the retest and report redacted PASS/FAIL.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.38 — Doctor Output Checkpoint

### Added

- Added Doctor Output checkpoint validation document.
- Added Bot/Web Doctor Output consistency test (208 checks).
- Verified Bot and Web Doctor Summary implementations are consistent in contract schema, summary values, display policy flags, advanced mode gating, and safety boundaries.
- Verified neither implementation weakens redaction, Raw JSON gating, advanced mode, rotate safety, or /api/status compatibility.
- Verified v1.9.36 Bot and v1.9.37 Web both use `--json status` for summary and gate full diagnostics behind advanced mode.
- Readiness decision: READY FOR LIMITED REAL BOT/WEB DOCTOR SMOKE RETEST PLANNING.
- Recommended v1.9.39 Limited Real Bot/Web Doctor Smoke Retest Plan as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.37 — Web Doctor Summary Minimal Implementation

### Changed

- Web `/doctor` now shows safe beginner summary cards by default instead of raw technical output.
- Added `build_doctor_summary()` to Web app, matching Bot v1.9.36 semantics.
- Added helper functions: `_infer_doctor_overall()`, `_infer_doctor_cloudflare()`, `_infer_doctor_subscription()`, `_infer_doctor_security()`, `_doctor_next_step()`.
- Advanced OFF: `/doctor` POST calls `--json status`, builds summary, renders cards. Does not call `nanobk doctor`.
- Advanced ON: `/doctor` POST shows summary cards first, then appends full redacted diagnostics in collapsed `<details>` with warning.
- Updated `doctor.html` template with summary cards, advanced mode gate, and collapsed full diagnostics.
- Added 25 new Web i18n keys for doctor summary labels (zh/en).
- Added `WEB_TEXT` import to web/app.py.
- Web self-test expanded from 75 to 106 tests with doctor summary verification.
- Added test `tests/web-doctor-summary-v1.9.37.py` (164 tests).
- Added validation document `docs/validation-v1.9.37-web-doctor-summary.md`.
- Recommended v1.9.38 Doctor Output Checkpoint as next step.

### Safety

- Web-only doctor summary change.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No raw IP/domain/URL/token/private key in summary.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.36 — Bot Doctor Summary Minimal Implementation

### Changed

- Bot `/doctor` now shows safe beginner summary by default instead of raw technical output.
- Added `build_doctor_summary()` to build summary dict from `nanobk --json status` conforming to v1.9.35 contract schema.
- Added `format_doctor_summary()` to format summary into human-readable text with i18n labels.
- Added helper functions: `_infer_doctor_overall()`, `_infer_doctor_cloudflare()`, `_infer_doctor_subscription()`, `_infer_doctor_security()`, `_doctor_next_step()`.
- Advanced OFF: `/doctor` calls `--json status`, builds summary, formats and sends. Does not call `nanobk doctor`.
- Advanced ON: `/doctor` shows summary first, then appends full redacted diagnostics with warning.
- Added 23 new Bot i18n keys for doctor summary labels (zh/en).
- Bot self-test expanded from 148 to 180 tests with doctor summary verification.
- Added test `tests/bot-doctor-summary-v1.9.36.py` (163 tests).
- Added validation document `docs/validation-v1.9.36-bot-doctor-summary.md`.
- Recommended v1.9.37 Web Doctor Summary Minimal Implementation as next step.

### Safety

- Bot-only doctor summary change.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No redaction changes.
- No /status_json gate changes.
- No advanced mode changes.
- No rotate confirmation changes.
- No raw IP/domain/URL/token/private key in summary.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.35 — Doctor Summary Contract / Fixture Tests

### Added

- Added Doctor Summary contract document with schema, safety rules, and scenario expectations.
- Added 14 fixture files under `tests/fixtures/doctor-summary-v1.9.35/`: 7 input fixtures (healthy, partial, missing config, CF missing, failure, secret-containing, unknown) and 7 expected summary fixtures.
- Added contract test `tests/doctor-summary-contract-v1.9.35.py` (352 checks).
- Defined stable Doctor Summary JSON schema with allowed value sets.
- Validated all expected summaries for schema compliance, forbidden pattern absence, and honesty rules.
- Verified input fixtures contain fake secrets for redaction testing, while expected summaries contain none.
- Readiness decision: READY FOR BOT DOCTOR SUMMARY MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW.
- Recommended v1.9.36 Bot Doctor Summary Minimal Implementation as next step.

### Safety

- Contract/fixture/test only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.34 — Doctor Output Current-State Audit

### Added

- Added Doctor Output Current-State audit document.
- Audited Bot doctor path: `cmd_doctor()` → `run_nanobk(config, ["doctor"])` → `safe_output()` → reply text. Owner-only, redacted, no shell=True.
- Audited Web doctor path: `/doctor` route → `run_nanobk(config, ["doctor"])` → `safe_output()` → render template. Login+CSRF, redacted.
- Audited CLI doctor path: `bin/nanobk doctor` → `installer/doctor.sh`. Text output, `--json` is placeholder. Checks OS/kernel/arch, tool paths, config existence/permissions, admin env existence, systemd services, port listening, config files.
- Classified output risk: beginner-safe (service status, port listening, config existence), advanced-only (OS/kernel, tool paths, config paths, port numbers, systemd names), never allowed (raw tokens/keys/env/IP/URL).
- Evaluated data source options; recommended fixture contract tests first, avoid brittle text parsing, prefer future safe JSON summary.
- Defined recommended summary contract direction for v1.9.35.
- Readiness decision: READY FOR DOCTOR SUMMARY CONTRACT / FIXTURE TESTS.
- Recommended v1.9.35 Doctor Summary Contract / Fixture Tests as next step.

### Safety

- Audit/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No `installer/doctor.sh` behavior changed.
- No real doctor executed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.33 — Doctor Output Productization Planning

### Added

- Added Doctor Output Productization planning document.
- Defined two-layer Doctor UX model: beginner summary (default) and full diagnostics (advanced mode).
- Compared Bot doctor design options; recommended option C (advanced mode gates output depth) with option A as fallback.
- Compared Web doctor design options; recommended option C (summary + advanced details tabs).
- Defined data source strategy: prefer future safe JSON summary, avoid brittle text parsing.
- Defined redaction/information-class policy for beginner summary vs advanced-only content.
- Defined staged implementation route: v1.9.34 audit, v1.9.35 fixture tests, v1.9.36 Bot, v1.9.37 Web, v1.9.38 checkpoint.
- Readiness decision: READY FOR DOCTOR OUTPUT CURRENT-STATE AUDIT.
- Recommended v1.9.34 Doctor Output Current-State Audit as next step.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No CLI behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.32 — Bot/Web i18n Checkpoint

### Added

- Added Bot/Web i18n checkpoint validation document.
- Added Bot/Web i18n consistency test (167 checks).
- Verified Bot and Web i18n implementations are consistent in language normalization, fallback behavior, translation coverage, and safety boundaries.
- Verified neither implementation weakens redaction, Raw JSON gating, advanced mode, rotate safety, or /api/status compatibility.
- Verified v1.9.31 did not weaken Bot i18n test safety assertions.
- Explicitly inspected `web/app.py` (omitted from v1.9.31 report's Files changed list).
- Readiness decision: READY FOR DOCTOR OUTPUT PRODUCTIZATION PLANNING.
- Recommended v1.9.33 Doctor Output Productization Planning as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.31 — Web i18n Minimal Implementation

### Changed

- Added `NANOBK_LANG=zh|en` support in WebConfig (defaults to `en`).
- Added `web/i18n.py` translation dictionary module with `normalize_lang()`, `wt()`, and `WEB_TEXT` (80+ zh/en entries).
- Added Flask context processor injecting `t()` and `lang` into all templates.
- Translated all Web UI text: login, dashboard, status cards, Raw JSON locked/warning, advanced mode controls, doctor page, rotate page, navigation, error messages.
- Status category values (healthy/failed/unknown etc.) remain untranslated.
- Web self-test expanded from 62 to 75 tests with i18n verification.
- Added test `tests/web-i18n-minimal-v1.9.31.py` (123 tests).
- Updated existing Web tests to match translated template keys.
- Added validation document `docs/validation-v1.9.31-web-i18n-minimal.md`.
- Recommended v1.9.32 i18n Checkpoint as next step.

### Safety

- Web-only i18n implementation.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No redaction changes.
- No /api/status schema changes.
- No Raw JSON gating behavior changes.
- No advanced mode behavior changes.
- No rotate behavior changes.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.30 — Bot i18n Minimal Implementation

### Changed

- Added `NANOBK_LANG=zh|en` support in BotConfig (defaults to `en`).
- Added `normalize_lang()` helper for language code normalization.
- Added `BOT_TEXT` translation dictionary with zh/en entries for all Bot control-plane text.
- Added `bt(lang, key, **kwargs)` translation helper with safe English fallback.
- Added builder functions: `build_control_center_text()`, `build_help_text()`, `build_guidance_recovery()`, `build_guidance_diagnostics()`, `build_guidance_rotate()`, `build_guidance_web()`.
- Updated `format_status()` to accept `lang` parameter for localized labels.
- Updated all Bot command handlers to use localized text via `bt()` and builders.
- Status category values (healthy/failed/unknown etc.) remain untranslated.
- Slash command names remain unchanged.
- Bot self-test now covers 117 tests with zh/en verification.
- Added test `tests/bot-i18n-minimal-v1.9.30.py` (116 tests).
- Updated existing tests to match new builder function references.
- Added validation document `docs/validation-v1.9.30-bot-i18n-minimal.md`.
- Recommended v1.9.31 Web i18n Minimal Implementation as next step.

### Safety

- Bot-only i18n implementation.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No redaction changes.
- No /status_json gate changes.
- No advanced mode changes.
- No rotate confirmation changes.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.29 — Bot/Web i18n Planning

### Added

- Added Bot/Web zh/en i18n planning document.
- Defined language source strategy: explicit NANOBK_LANG=zh|en env variable.
- Defined Bot i18n design: central translation dictionary, safe fallback to English, command names unchanged.
- Defined Web i18n design: template translation helper, zh/en Dashboard/Status/Raw JSON warning/advanced controls.
- Recommended shared lib/nanobk_i18n.py if import path is simple; otherwise separate dictionaries.
- Defined safety requirements: i18n must not change redaction, no raw secrets in translations.
- Provided Bot and Web text inventory tables for future implementation.
- Defined staged implementation route: v1.9.30 Bot i18n, v1.9.31 Web i18n, v1.9.32 i18n checkpoint.
- Defined testing strategy for future implementation.
- Applied typo fix in v1.9.28 validation doc: v1.9.18 → v1.9.28.
- Readiness decision: READY FOR BOT I18N MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW.

### Safety

- Planning/documentation only + typo fix.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.28 — Real Bot/Web Smoke Test Validation

### Added

- Added real Bot/Web smoke test validation document.
- Recorded user-run v1.9.27 limited real Bot/Web smoke test result: PASS WITH POLISH.
- Web control plane passed: login, Dashboard, Status, API, Doctor, Rotate dry-run, safe cards, Raw JSON gating, advanced mode.
- Bot control plane passed: /start, /help, /status, /status_json OFF/ON, /advanced on/off, /doctor, all buttons.
- Security result: no observed leakage of raw IPv4/IPv6/domain/workers.dev/subscription URL/token/private key/env content.
- Documented issue matrix: CLI version display, Bot/Web systemd, i18n, /doctor output, fingerprint redaction policy.
- Documented token exposure follow-up: exposed token must be revoked/regenerated.
- Recommended v1.9.29 Bot/Web i18n Planning as next step.

### Safety

- Documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.27 — Limited Real Bot/Web Smoke Test Plan

### Added

- Added limited real Bot/Web smoke test planning document.
- Defined safe smoke test scope: control-plane only, no redeploy, no Cloudflare mutation, no rotate execution.
- Provided user-facing absolute safety rules (no secret sharing, no raw IP/domain/token/URL pasting).
- Provided 20-step Bot smoke test checklist with expected safe results.
- Provided 16-step Web smoke test checklist with expected safe results.
- Defined redaction observation rules for safe reporting.
- Defined failure handling: stop on secret exposure, report redacted PASS/FAIL only.
- Provided copyable redacted test report template.
- Readiness decision: READY FOR USER-RUN LIMITED REAL BOT/WEB SMOKE TEST AFTER CHATGPT REVIEW.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.26 — Bot Control Center Checkpoint

### Added

- Added Bot Control Center checkpoint validation document.
- Added Bot Control Center consistency test (66 checks).
- Verified /start control center menu is safe, owner-only, productized.
- Verified all 7 callbacks use nanobk: prefix and scoped CallbackQueryHandler.
- Verified shared get_safe_status_text() used by both /status and Status Summary callback.
- Verified rotate callback is guidance-only (no run_nanobk, no confirmations.set).
- Verified Web callback exposes no raw URL, no workers.dev, no subscription path.
- Verified /status_json soft gate preserved.
- Verified advanced mode helpers preserved.
- Verified all slash commands remain registered.
- Readiness decision: READY FOR LIMITED REAL BOT/WEB SMOKE TEST PLANNING.
- Recommended v1.9.27 Limited Real Bot/Web Smoke Test Plan as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.25 — Bot Control Center Callback Polish

### Changed

- Extracted shared `get_safe_status_text(config)` helper to eliminate logic drift between `/status` and Status Summary callback.
- Both `/status` and Status Summary callback now use the same safe status path.
- Extracted callback guidance constants: `GUIDANCE_RECOVERY`, `GUIDANCE_DIAGNOSTICS`, `GUIDANCE_ROTATE`, `GUIDANCE_WEB`, `HELP_TEXT`.
- Callbacks now reference constants instead of inline strings, improving testability.
- Strengthened Bot self-test: removed weak `or True` checks, added 15 new guidance constant validations.
- Bot self-test expanded from 81 to 93 tests.
- Added test `tests/bot-control-center-callback-polish-v1.9.25.py` (50 tests).
- Added validation document `docs/validation-v1.9.25-bot-control-center-callback-polish.md`.
- Recommended v1.9.26 Bot Control Center Checkpoint as next step.

### Safety

- Bot-only callback polish.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Callbacks remain owner-only.
- Rotate callback remains guidance-only.
- Web Panel callback does not expose raw URL.
- `/status_json` soft gate unchanged.
- Advanced mode unchanged.
- Redaction unchanged.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.24 — Bot Control Center Static Menu Minimal Implementation

### Changed

- Updated `/start` to show productized NanoBK Control Center message with InlineKeyboardButton menu.
- Added static main menu: Status Summary, Recovery Help, Diagnostics, Advanced Mode, Rotate Secrets, Web Panel, Help.
- Added callback data constants with `nanobk:` prefix for safe scoping.
- Added `handle_menu_callback()` with owner-only authorization and scoped `CallbackQueryHandler`.
- Status Summary callback calls existing safe `/status` logic.
- Recovery Help callback shows static safe recovery text.
- Diagnostics callback shows guidance for /doctor, /advanced on, /status_json.
- Advanced Mode callback shows current status + command guidance.
- Rotate Secrets callback shows static guidance only (does NOT execute rotate).
- Web Panel callback shows safe guidance (does NOT expose raw URL).
- Help callback shows help text.
- All slash commands remain available as canonical shortcuts.
- Bot self-test expanded from 66 to 81 tests with control center verification.
- Added test `tests/bot-control-center-menu-v1.9.24.py` (46 tests).
- Added validation document `docs/validation-v1.9.24-bot-control-center-static-menu.md`.
- Recommended v1.9.25 Bot Control Center Callback Polish as next step.

### Safety

- Bot-only static menu implementation.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Callbacks do not bypass owner checks, advanced mode gate, or rotate confirmation.
- Rotate callback does not execute rotate.
- Web Panel callback does not expose raw URL.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.23 — Bot Control Center Menu Planning

### Added

- Added Bot Control Center Menu planning document.
- Defined Telegram Bot as phone-side NanoBK control center.
- Defined user layer model: L1 Beginner, L2 Advanced diagnostics, L3 Owner/maintainer.
- Designed future `/start` behavior with main menu buttons.
- Mapped main menu buttons: Status Summary, Recovery Help, Diagnostics, Advanced Mode, Rotate Secrets, Web Panel, Help.
- Classified risk levels: read-only safe, medium-risk diagnostics, high-risk confirmed, blocked.
- Compared callback vs slash command strategies; recommended static menu + callback calling existing handlers.
- Provided Chinese/English message copy for main menu, diagnostics, advanced mode, rotate, recovery.
- Defined staged implementation route: v1.9.24 static menu, v1.9.25 callback polish, v1.9.26 checkpoint.
- Defined testing strategy for future implementation.
- Readiness decision: READY FOR BOT CONTROL CENTER STATIC MENU MINIMAL IMPLEMENTATION (narrow scope).

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.22 — Raw JSON Gating Checkpoint

### Added

- Added Raw JSON Gating checkpoint validation document.
- Added Bot/Web Raw JSON soft gating consistency test (58 checks).
- Verified Bot /status_json soft gate: OFF = guidance only, ON = warning + redacted JSON.
- Verified Web Raw JSON soft gate: OFF = locked panel, ON = warning + redacted details.
- Verified both use 15-minute TTL, preserve redaction, protect beginner UI.
- Verified /api/status remains available and not gated.
- Readiness decision: READY FOR CONTROL-PLANE UX POLISH PLANNING.
- Recommended v1.9.23 Bot Control Center Menu Planning as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.21 — Web Raw JSON Soft Gate Minimal Implementation

### Changed

- Web Status page Raw JSON section now requires advanced diagnostics mode.
- When advanced mode is OFF: shows locked panel (no status.raw_json rendered).
- When advanced mode is ON: shows warning + redacted Raw JSON details (collapsed by default).
- Expired advanced mode behaves as OFF.
- Added `.locked-panel` CSS class for locked state styling.
- `/api/status` remains unchanged and not gated.
- Added test `tests/web-raw-json-soft-gate-v1.9.21.py` (48 tests).
- Added validation document `docs/validation-v1.9.21-web-raw-json-soft-gate.md`.
- Recommended v1.9.22 Raw JSON Gating Checkpoint as next step.

### Safety

- Web-only Raw JSON gating change.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Advanced mode does not bypass redaction.
- Off-state does not render status.raw_json.
- /api/status unchanged and not gated.
- Secrets, raw addresses, subscription URLs remain hidden.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.20 — Bot /status_json Soft Gate Minimal Implementation

### Changed

- Bot `/status_json` now requires advanced diagnostics mode to display JSON output.
- When advanced mode is OFF: shows guidance message (no JSON output, no nanobk call).
- When advanced mode is ON: shows warning header + redacted JSON (existing behavior).
- Expired advanced mode behaves as OFF.
- Updated `/help` to clarify `/status_json` requires advanced mode.
- Bot self-test expanded with soft gate copy verification.
- Added test `tests/bot-status-json-soft-gate-v1.9.20.py` (50 tests).
- Added validation document `docs/validation-v1.9.20-bot-status-json-soft-gate.md`.
- Recommended v1.9.21 Web Raw JSON Soft Gate as next step.

### Safety

- Bot-only /status_json gating change.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Advanced mode does not bypass redaction.
- Off-state does not call run_nanobk.
- Secrets, raw addresses, subscription URLs remain hidden.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.19 — Raw JSON Gating Policy Planning

### Added

- Added Raw JSON Gating Policy planning document.
- Defined why Raw JSON gating is desirable (not beginner UI, reduces accidental exposure).
- Defined gating principles: gate visibility not redaction, advanced mode never disables redaction.
- Compared Bot `/status_json` gating options; recommended soft gate.
- Compared Web Raw JSON details gating options; recommended soft gate in Status page.
- Defined future Bot behavior: off = instructions only, on = redacted JSON with warning.
- Defined future Web behavior: off = locked panel + enable form, on = redacted Raw JSON details.
- Defined `/api/status` policy: do NOT gate in v1.9.x, already returns redacted JSON.
- Provided Chinese/English warning and fallback copy for Bot and Web.
- Defined testing strategy for future implementation.
- Recommended staged route: v1.9.20 Bot soft gate, v1.9.21 Web soft gate, v1.9.22 checkpoint.
- Readiness decision: READY FOR BOT RAW JSON SOFT GATE MINIMAL IMPLEMENTATION (narrow scope).

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.18 — Advanced Diagnostics Mode Checkpoint

### Added

- Added Advanced Diagnostics Mode checkpoint validation document.
- Added Bot/Web advanced diagnostics mode consistency test (80 checks).
- Verified Bot and Web advanced mode implementations are consistent in safety, temporality, non-persistence, and warning protection.
- Verified neither implementation bypasses redaction or alters high-risk operations.
- Confirmed TTL, enable/disable/status semantics, auth requirements, and session/memory storage match.
- Readiness decision: READY FOR RAW JSON GATING PLANNING (narrow scope).
- Recommended v1.9.19 Raw JSON Gating Policy Planning as next step.

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.17 — Web Advanced Mode Minimal Implementation

### Changed

- Added Web advanced diagnostics mode helper functions: `enable_advanced_mode()`, `disable_advanced_mode()`, `is_advanced_mode_enabled()`, `advanced_mode_remaining_seconds()`.
- Advanced mode state stored in Flask session only. Not persisted to disk/env/config.
- Auto-expires after 15 minutes (`ADVANCED_MODE_TTL_SECONDS = 900`).
- Logout/session expiry resets advanced mode.
- Added `POST /advanced/on` route (login + CSRF required): enables mode, redirects to Status.
- Added `POST /advanced/off` route (login + CSRF required): disables mode, redirects to Status.
- Added `GET /advanced/status` route (login required): returns JSON status.
- Updated Status page template with Advanced Diagnostics control card (enable/disable buttons, warning copy).
- Added `.badge-ok` and `.button-warn` CSS classes.
- Web self-test expanded with advanced mode helper verification.
- Added test `tests/web-advanced-mode-v1.9.17.py`.
- Added validation document `docs/validation-v1.9.17-web-advanced-mode.md`.
- Recommended v1.9.18 Advanced Diagnostics Mode Checkpoint as next step.

### Safety

- Web-only advanced mode state change.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Advanced mode does not change redaction rules.
- Advanced mode does not gate Raw JSON details.
- Advanced mode does not change /api/status.
- No URL query parameter bypass.
- No persistent storage.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.16 — Bot Advanced Mode Minimal Implementation

### Changed

- Added Bot advanced diagnostics mode helper functions: `enable_advanced_mode()`, `disable_advanced_mode()`, `is_advanced_mode_enabled()`, `advanced_mode_remaining_seconds()`, `advanced_mode_expires_at()`.
- Advanced mode state stored in-memory only (`_ADVANCED_MODE_EXPIRES_AT` dict). Not persisted to disk/env/config.
- Auto-expires after 15 minutes (`ADVANCED_MODE_TTL_SECONDS = 900`).
- Bot restart resets advanced mode.
- Added `/advanced on` command (owner-only): enables mode, shows warning copy.
- Added `/advanced off` command (owner-only): disables mode.
- Added `/advanced status` command (owner-only): shows mode status and remaining time.
- Added `/advanced` without arguments: shows usage text.
- Updated `/help` to include `/advanced on|off|status` under Advanced diagnostics section.
- Bot self-test expanded from 47 to 61 tests with advanced mode verification.
- Added test `tests/bot-advanced-mode-v1.9.16.py`.
- Added validation document `docs/validation-v1.9.16-bot-advanced-mode.md`.
- Recommended v1.9.17 Web Advanced Mode Planning as next step.

### Safety

- Bot-only advanced mode state change.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Advanced mode does not change redaction rules.
- Advanced mode does not gate `/status_json`.
- Advanced mode does not change rotate behavior.
- No file/env/config persistence.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.15 — Advanced Diagnostics Mode Planning

### Added

- Added Advanced Diagnostics Mode planning document.
- Defined what advanced diagnostics mode is (temporary redacted debugging) and is not (secret viewer/deployment mode).
- Defined user/permission model: L1 Beginner, L2 Advanced diagnostics, L3 Owner.
- Compared Bot advanced mode options; recommended `/advanced on/off` with in-memory state and auto-expiration.
- Compared Web advanced mode options; recommended session-level toggle with warning confirmation.
- Defined expiration/persistence policy: Bot in-memory 10-15 min, Web session-only.
- Provided Chinese/English warning copy for Bot and Web advanced mode enablement.
- Defined advanced mode visibility rules (what it may and may not reveal).
- Defined interaction with existing commands/pages.
- Defined testing strategy for future implementation.
- Recommended v1.9.16 Bot Advanced Mode Minimal Implementation as next step.
- Readiness decision: READY FOR BOT ADVANCED MODE MINIMAL IMPLEMENTATION (narrow scope).

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.14 — Web Raw JSON Warning Copy Minimal Implementation

### Changed

- Added safety warning copy before Raw JSON `<details>` block on Web Status page.
- Warning text: "Advanced diagnostics — Raw JSON is redacted and intended for troubleshooting only. It is not the normal status view and should not be shared as subscription information. Use the status cards above for the normal safe summary."
- Added `.warning-box` CSS class for warning styling.
- Raw JSON details remain visible (not hidden), collapsed by default.
- Raw JSON values remain redacted through existing shared redaction helper.
- `/api/status` unchanged.
- Added test `tests/web-raw-json-warning-v1.9.14.py` (33 tests).
- Added validation document `docs/validation-v1.9.14-web-raw-json-warning.md`.
- Recommended v1.9.15 Advanced Diagnostics Mode Planning as next step.

### Safety

- Web-only warning copy change.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Raw JSON details still visible (not hidden).
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.13 — Bot /status_json Warning and Help Classification

### Changed

- Updated Bot `/help` text to classify commands into Basic, Safe operations, and Advanced diagnostics sections.
- Moved `/status_json` from main command list to "Advanced diagnostics" section.
- Added safety warning before `/status_json` output: "Advanced diagnostics ... Do not forward ... Use /status for normal safe summary."
- `/status_json` command remains available, not hidden or removed.
- Output remains redacted through existing shared redaction helper.
- Updated Bot self-test from 38 to 47 tests with help classification and warning verification.
- Added test `tests/bot-status-json-warning-v1.9.13.py` (44 tests).
- Added validation document `docs/validation-v1.9.13-bot-status-json-warning.md`.
- Recommended v1.9.14 Web Raw JSON Warning Copy as next step.

### Safety

- Bot-only help/warning change.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.12 — Raw JSON / Advanced Diagnostics Policy Planning

### Added

- Added Raw JSON / Advanced Diagnostics policy planning document.
- Defined user layer strategy: L1 Beginner, L2 Advanced, L3 Owner.
- Defined Bot `/status_json` policy: keep available, hide from main `/help`, add warning.
- Defined Web Raw JSON details policy: keep visible, add warning, plan future advanced toggle.
- Defined advanced mode design options for Bot (`/advanced on/off`) and Web (session flag/toggle).
- Provided safe Chinese/English warning copy for diagnostic outputs.
- Defined Raw JSON content rules and copy/paste support policy.
- Defined testing strategy for future implementation.
- Recommended v1.9.13 Bot `/status_json` Warning and Help Classification as next step.

### Safety

- Planning/documentation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.11 — Web Safe Status Cards Minimal Implementation

### Changed

- Rewrote Web `format_status()` from address-heavy dict to safe card-oriented structure.
- Web Dashboard/Status normal views no longer show Domain/VPS IP/geo labels or raw values.
- Web cards now show: Overall, VPS, Protocols, Cloudflare, Subscription, Secrets, Profile, Next step.
- Honest status categories preserved: healthy/verified/active/failed/unknown/partial/incomplete/missing.
- Missing fields produce "unknown" rather than success.
- Next-step hints generated based on status (SSH recovery, Cloudflare verification, no action needed).
- Raw JSON details still visible in Status page `<details>` block (values redacted via shared helper).
- `/api/status` unchanged — returns redacted JSON.
- Updated `index.html` and `status.html` templates for safe card display.
- Added `.muted` CSS class for footer hints.
- Web self-test updated from 42 to 48 tests.
- Added test `tests/web-safe-status-cards-v1.9.11.py` (82 tests).
- Added validation document `docs/validation-v1.9.11-web-safe-status-cards.md`.
- Recommended v1.9.12 Raw JSON / Advanced Diagnostics Policy Planning as next step.

### Safety

- Web-only status card formatting change.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- Raw JSON details still visible (not hidden).
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.10 — Bot Safe Status Summary Minimal Implementation

### Changed

- Rewrote Bot `format_status()` from address-heavy dump to safe beginner-friendly summary.
- Bot `/status` no longer shows Domain/VPS IP/geo labels or raw values.
- Bot `/status` now shows: Overall, VPS, Protocols, Cloudflare, Subscription, Secrets, Profile, Next step.
- Honest status categories preserved: healthy/verified/active/failed/unknown/manual_pending/dry-run/planned/skipped.
- Missing fields produce "unknown" rather than success.
- Next-step hints generated based on status (SSH recovery, Cloudflare verification, no action needed).
- Defensive implementation tolerates missing keys, unexpected types, non-dict input.
- Bot self-test updated from 28 to 38 tests with new format expectations.
- Added test `tests/bot-safe-status-summary-v1.9.10.py` (67 tests).
- Added validation document `docs/validation-v1.9.10-bot-safe-status-summary.md`.
- Recommended v1.9.11 Web Safe Status Cards as next step.

### Safety

- Bot-only /status formatting change.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- `/status_json` unchanged.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.9 — Redaction Integration Checkpoint / Bot-Web Safety Gate

### Added

- Added redaction integration checkpoint validation document.
- Added Bot/Web redaction consistency test with 94 checks.
- Verified Bot and Web redaction paths delegate to shared helper consistently.
- Verified no old local redaction patterns remain in Bot/Web source.
- Verified address-class values (IPv4/IPv6/domain/URL/workers.dev/subscription path) are redacted by both Bot and Web.
- Verified status words (active/failed/unknown/JP/600/configured) are preserved.
- Verified idempotency: Bot and Web produce identical redacted output on same input.
- Readiness decision: READY FOR SMALL UX IMPLEMENTATION PLANNING (narrow scope).
- Recommended v1.9.10 Bot Safe Status Summary as next step (after ChatGPT review).

### Safety

- Checkpoint/validation only.
- No Bot runtime behavior changed.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.8 — Web Redaction Helper Integration

### Changed

- Integrated shared redaction helper `lib/nanobk_redaction.py` into Web output path.
- Web `strip_ansi()` now delegates to shared helper.
- Web `redact_text()` now delegates to shared helper with address-class redaction.
- Web `redact_json()` now delegates to shared `redact_json_obj()` with address-class redaction.
- Web Dashboard/Status/API/Doctor/Rotate/failure outputs now redact IPv4, IPv6, domain, URL, workers.dev, subscription path.
- Web `format_status()` domain/IP values are now redacted through `redact_json()`.
- Web self-test expanded from 18 to 42 tests with address-class redaction verification.
- Added integration test `tests/web-redaction-helper-integration-v1.9.8.py` (84 tests).
- Added validation document `docs/validation-v1.9.8-web-redaction-helper-integration.md`.
- Recommended v1.9.9 Redaction Integration Checkpoint as next step.

### Safety

- Web-only redaction integration.
- No Bot runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.7 — Bot Redaction Helper Integration

### Changed

- Integrated shared redaction helper `lib/nanobk_redaction.py` into Bot output path.
- Bot `strip_ansi()` now delegates to shared helper.
- Bot `redact_text()` now delegates to shared helper with address-class redaction.
- Bot `/status`, `/status_json`, `/doctor`, failure output now redact IPv4, IPv6, domain, URL, workers.dev, subscription path.
- Bot self-test expanded from 20 to 28 tests with address-class redaction verification.
- Added integration test `tests/bot-redaction-helper-integration-v1.9.7.py` (57 tests).
- Added validation document `docs/validation-v1.9.7-bot-redaction-helper-integration.md`.
- Recommended v1.9.8 Web Redaction Helper Integration as next step.

### Safety

- Bot-only redaction integration.
- No Web runtime behavior changed.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.6 — Shared Redaction Helper Design / Prototype Review

### Added

- Added shared redaction helper module `lib/nanobk_redaction.py`.
- Helper exposes `redact_text()`, `redact_json_obj()`, `redact_json_text()`, `strip_ansi()`.
- Covers address-class redaction: IPv4, IPv6, domain, URL, workers.dev, subscription path.
- Covers token/secret/password/private-key redaction with key-value patterns.
- Covers Telegram bot token format and long base64/hex strings.
- JSON redaction preserves booleans, numbers, status fields, and JSON validity.
- Domain redaction excludes file extensions (.json, .py, etc.) to avoid false positives on paths.
- Added 82-test suite `tests/redaction-helper-v1.9.6.py` covering fixtures, idempotency, edge cases.
- Added design document `docs/design-v1.9.6-shared-redaction-helper.md`.
- Recommended v1.9.7 Bot Redaction Helper Integration as next step.

### Safety

- Helper module added but NOT wired into Bot/Web runtime.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web runtime behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.5 — Redaction Layer Audit and Address-Class Redaction Tests

### Added

- Added Redaction Layer audit and address-class redaction specification document.
- Audited current Bot/Web redaction functions: `redact_text()`, `redact_json()`, `safe_output()`.
- Defined address-class sensitive data: IPv4, IPv6, domain, URL, workers.dev, subscription path, route URL.
- Defined standardized replacement tokens: `[REDACTED_IPV4]`, `[REDACTED_IPV6]`, `[REDACTED_DOMAIN]`, `[REDACTED_URL]`, `[REDACTED_WORKERS_DEV]`, `[REDACTED_SUBSCRIPTION_PATH]`.
- Added safe fixture files under `tests/fixtures/redaction-v1.9.5/` with RFC 5737/3849/2606 safe values.
- Added contract test `tests/redaction-address-class-v1.9.5.sh` with 30+ checks.
- Confirmed current redaction does NOT cover address-class values (IPv4/IPv6/domain/URL/workers.dev/subscription path).
- Recommended v1.9.6 Shared Redaction Helper Design as next step.

### Safety

- Documentation + fixtures + contract test only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web runtime behavior changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.4 — Bot/Web Command Allowlist Spec and Static Tests

### Added

- Added Bot/Web Command Allowlist specification document.
- Defined command risk levels: L0 safe read-only, L1 medium-risk diagnostic, L2 high-risk mutating, L3 blocked.
- Documented current Bot command inventory with risk levels and allowlist status.
- Documented current Web command inventory with risk levels and allowlist status.
- Proposed allowlist table for all nanobk CLI commands.
- Defined hard-denied categories: shell=True, os.system, systemctl, direct file writes, direct env reads, direct CF writes.
- Added static guard test `tests/bot-web-command-allowlist-v1.9.4.sh` with 11 checks.
- Clarified v1.9.3 implementation ordering: v1.9.4 (allowlist) and v1.9.5 (redaction) are parallel safety gates.
- Recommended v1.9.5 Redaction Layer Audit and Address-Class Redaction Tests as next step.

### Safety

- Documentation + static test only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web code changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.3 — Web Dashboard UX Spec

### Added

- Added Web Dashboard UX specification document.
- Defined Web Panel design principles: browser dashboard, beginner-first, honest status, redaction-first, CLI-backed, consistent with Bot.
- Defined three-tier user model matching Bot: Beginner (L1), Advanced (L2), Owner (L3).
- Designed Dashboard layout with Overall Status, VPS, CF, Subscription, Bot/Web, Recent Operations, and Recovery cards.
- Defined status color/badge semantics matching Bot spec.
- Specified each card's allowed/forbidden fields for beginner view.
- Specified Raw JSON/details policy: hidden by default, advanced-only, must pass address-class redaction.
- Specified Doctor page UX as medium-risk with beginner/advanced view split.
- Specified Rotate page UX with two-step CSRF-protected confirmation.
- Defined Recovery page for SSH-based recovery guidance.
- Defined Recent Operations card as safe summary only (no full operation-log rollout).
- Defined Auth/Session/CSRF UX rules with safe error messages.
- Defined Web copywriting rules and UI text templates.
- Mapped Web UX to Bot UX for consistency verification.
- Defined future test requirements for Web UX implementation.
- Recommended v1.9.4 Bot/Web Command Allowlist Spec and Static Tests as next step.

### Safety

- Documentation/spec only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web code changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.2 — Telegram Bot UX/Menu Spec

### Added

- Added Telegram Bot UX/Menu specification document.
- Defined Bot design principles: phone control center, beginner-first, honest status, redaction-first.
- Defined three-tier user model: Beginner (L1), Advanced (L2), Owner (L3).
- Designed `/start` homepage with InlineKeyboardButton groups.
- Designed full menu tree with status, operations, and help sections.
- Mapped current commands to future menu items with risk levels.
- Specified status overview card format with honest status categories.
- Specified VPS, Cloudflare, and subscription status card formats.
- Specified Doctor UX as medium-risk with beginner/advanced view split.
- Specified Rotate UX with two-step button confirmation.
- Defined `/status_json` policy: hidden by default, advanced-only.
- Defined future redaction requirements (IPv4/IPv6/domain/URL/workers.dev/subscription path).
- Defined action risk classification: read-only / medium / high.
- Defined Bot copywriting rules and message templates.
- Defined future test requirements for Bot UX implementation.
- Recommended v1.9.3 Web Dashboard UX Spec as next step.

### Safety

- Documentation/spec only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web code changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.1 — Bot/Web Current-State Safety Audit

### Added

- Added Bot/Web current-state safety audit document.
- Audited Bot command structure, CLI calls, confirmation flows, and redaction coverage.
- Audited Web route structure, API endpoints, CSRF/auth, and redaction coverage.
- Confirmed Bot/Web have no direct-write paths to configs/systemd/secrets/env.
- Confirmed all CLI calls use list-form subprocess with `shell=False`.
- Identified address-class redaction gap (IP/domain/URL/workers.dev/subscription path).
- Identified `/status_json` and Raw JSON exposure as medium risk.
- Confirmed rotate confirmation flow is complete (two-step + expiry + CSRF).
- Confirmed `bot-cli-mock.sh` and `web-panel-mock.sh` both pass.
- Recommended v1.9.2 Bot UX/Menu Spec can proceed.

### Safety

- Documentation/audit only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web code changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release.

## v1.9.0-planning — Bot/Web Control Plane Productization Scope Proposal

### Added

- Added v1.9.0 Bot/Web control-plane productization scope proposal.
- Defined Bot/Web as safe productized control planes that call `nanobk` CLI only.
- Documented Bot and Web current-state audit findings from repo inspection.
- Proposed safe status categories, confirmation levels, command allowlist principles, redaction policy, and tiered testing strategy.
- Proposed a small-step v1.9 roadmap before any implementation.

### Safety

- Planning/documentation only.
- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed.
- No Bot/Web code changed.
- No deployment core, protocol template, Worker, rotate sync, status wrapper, or operation-log rollout changed.
- No tag/release recommendation.

## v1.8.45 — v1.8 Closeout Decision

### Added

- Added v1.8 closeout decision.
- Recommended stopping v1.8 feature development after v1.8.45.
- Confirmed v1.8 status as CLI UI + operation-log groundwork.
- Documented optional final manual review before any tag/release.
- Documented v1.9 Bot/Web control-plane productization recommendation.
- Documented that this is not a release tag recommendation.

### Safety

- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed except version.
- No status wrapper.
- No `NANOBK_OPLOG_STATUS_PILOT`.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.44 — v1.8 CLI and Operation Log Checkpoint

### Added

- Added v1.8 CLI and operation-log checkpoint.
- Summarized v1.8 CLI UI productization.
- Summarized operation-log low-risk groundwork.
- Summarized focused test speed strategy.
- Summarized status mock/oplog proof chain.
- Recorded overall status: PASS FOR CLI UI + OPERATION-LOG GROUNDWORK.
- Documented that production status wrapper remains unapproved.
- Documented that dirty VPS status remains unapproved.
- Documented that `run_cmd`/`run_critical_step` rollout remains unapproved.
- Recommended v1.8.45 closeout decision.

### Safety

- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed except version.
- No status wrapper.
- No `NANOBK_OPLOG_STATUS_PILOT`.
- No real deployment path changed.

## v1.8.43 — Status Mock Oplog Prototype Checkpoint

### Added

- Added status mock operation-log prototype checkpoint.
- Recorded v1.8.34–v1.8.42 status JSON proof chain.
- Accepted mock filesystem status operation-log prototype.
- Documented that dirty VPS status remains unapproved.
- Documented that production status wrapper remains unapproved.
- Documented that `NANOBK_OPLOG_STATUS_PILOT` is still not added.
- Documented security proof summary.
- Recommended next step toward broader v1.8 CLI/operation-log checkpoint.

### Safety

- No `install.sh` behavior changed.
- No `bin/nanobk` behavior changed except version.
- No status wrapper.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.42 — Status Mock Oplog Command Path Polish

### Fixed

- Polished status mock operation-log command path.
- Runner now uses relative `bash bin/nanobk` after `cd "$REPO_DIR"`.
- Full log now checks absence of real HOME and real repo absolute path.
- Preserved mock-root status operation-log prototype.
- Preserved JSON block validity and forbidden pattern checks.

### Safety

- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- Did not run dirty VPS status.
- Did not add production status wrapper.
- No `install.sh` behavior changed.
- No `cmd_status` schema changes.
- No `resolve_repo_dir` changes.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.41 — Status JSON Mock Filesystem Operation-Log Prototype

### Added

- Added status JSON mock filesystem operation-log prototype.
- Used `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` with mock admin env path.
- Captured mock-root `bin/nanobk --json status --config-dir <tmp/config>` via operation-log.
- Verified default hidden output.
- Verified verbose sanitized output.
- Verified log JSON validity.
- Verified PLAIN/UI=0/CI no-ANSI boundaries.
- Verified systemctl PATH shim usage.
- Verified failure propagation with redaction.

### Safety

- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- Did not run dirty VPS status.
- Did not add production status wrapper.
- No `install.sh` behavior changed.
- No `cmd_status` schema changes.
- No `resolve_repo_dir` changes.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.40 — Status JSON Admin Env Path Test Hook

### Added

- Added `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` test-only status hook.
- Limited hook to admin env existence check in `cmd_status()`.
- Preserved default `/root/.nanok-cf-admin.env` behavior.
- Added focused tests for `adminEnvExists` false/true with mock path.
- Added systemctl PATH shim test.
- Verified JSON validity and no real root/etc path leakage.

### Safety

- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- Did not add status operation-log wrapper.
- Did not change status JSON schema.
- No `install.sh` behavior changed.
- No `resolve_repo_dir` changes.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.39 — Status JSON Mock Isolation Hook Planning

### Added

- Added status JSON mock isolation hook planning.
- Compared broad `NANOBK_STATUS_MOCK_ROOT` vs narrow admin env path override.
- Recommended `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` as the minimal test-only hook.
- Documented implementation sketch.
- Documented future hook tests.
- Documented risk controls.
- Recommended v1.8.40 admin env path test hook.

### Safety

- Did not implement hook.
- Did not run real `bin/nanobk --json status`.
- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- No `install.sh` behavior changed.
- No `cmd_status` changes.
- No `resolve_repo_dir` changes.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.38 — Status JSON Mock Filesystem Prototype Feasibility Gate

### Added

- Added status JSON mock filesystem feasibility gate.
- Evaluated `NANOBK_REPO_DIR` + `--config-dir` + PATH systemctl shim route.
- Documented Route A feasibility verdict.
- Documented required mock files.
- Documented runtime guards.
- Documented proof levels for no real path read.
- Recommended v1.8.39 next step.

### Safety

- Did not implement mock runner.
- Did not run real `bin/nanobk --json status`.
- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- No `install.sh` behavior changed.
- No `cmd_status` changes.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.37 — Status JSON Mock Filesystem Root Design

### Added

- Added status JSON mock filesystem root design.
- Documented current `cmd_status` path reads.
- Documented proposed mock config/repo/root layout.
- Documented path isolation requirements.
- Documented systemctl/service status strategy.
- Documented JSON validity and redaction gates.
- Recommended v1.8.38 mock filesystem prototype.

### Safety

- Did not run real `bin/nanobk --json status`.
- Did not add status wrapper.
- Did not add `NANOBK_OPLOG_STATUS_PILOT`.
- No `install.sh` behavior changed.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.36 — Status JSON Fixture Test Polish

### Fixed

- Polished status JSON sanitized fixture test.
- Replaced placeholder `grep` checks with fixed-string matching (`grep -Fq`) to prevent regex interpretation of `[REDACTED_...]`.
- Replaced `echo | grep` patterns with here-string (`<<<`) checks where practical.
- Improved temporary directory cleanup using `register_cleanup` instead of multiple `trap` overrides.
- Removed unused variables from fixture test.
- Used `has_ansi` helper for ANSI detection in mode boundary tests.
- Improved source guard to avoid self-referencing false positives.

### Safety

- Preserved fixture JSON validity, hidden output, verbose output, PLAIN/UI=0/CI, and failure propagation checks.
- Did not run real `bin/nanobk --json status`.
- Did not add status wrapper.
- Did not add third real command pilot.
- No `install.sh` behavior changed.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.35 — Status JSON Sanitized Fixture Prototype

### Added

- Added sanitized status JSON fixture (`tests/fixtures/status-json-sanitized-v1.8.json`).
- Added operation-log fixture capture test (`tests/unified-cli-status-json-sanitized-fixture-v1.8.sh`).
- Verified raw fixture JSON validity.
- Verified log JSON validity after operation-log capture.
- Verified default hidden output (JSON not shown on screen).
- Verified verbose sanitized output (JSON shown on screen, no secrets).
- Verified PLAIN/UI=0/CI no-ANSI boundaries.
- Verified failure propagation with redaction (non-zero exit, raw secret redacted).
- Added v1.8.35 section to status JSON planning document.
- Updated planning coverage test with v1.8.35 assertions.

### Safety

- Did not run real `bin/nanobk --json status`.
- Did not add status wrapper.
- Did not add third real command pilot.
- No `install.sh` behavior changed.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.34 — Status JSON Mock/Sanitized Planning

### Added

- Added status JSON mock/sanitized planning.
- Documented correct status JSON command: `bin/nanobk --json status`.
- Documented risks of real installed status on dirty VPS.
- Documented sensitive and semi-sensitive status output map.
- Documented JSON validity gates.
- Documented dirty VPS validation policy.
- Added focused documentation coverage test for the planning checkpoint.

### Safety

- No status wrapper implemented.
- No third command pilot added.
- No install.sh behavior changed.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.33 — Focused Test No-Trigger Speed Polish

### Fixed

- Polished focused fast tests so default no-trigger checks also use `NANOBK_TEST_OVERRIDE_SCRIPT`.
- Avoided All safe tests in version/help fast test no-trigger paths.
- Updated test speed strategy documentation with v1.8.33 no-trigger polish note.

### Safety

- No install.sh behavior changed.
- No third command wrapper added.
- No `status --json` wrapping.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.32 — Operation Log Focused Test Speed Split

### Added

- Added operation-log focused fast tests for `bin/nanobk --version` pilot.
- Added operation-log focused fast tests for `bin/nanobk --help` pilot.
- Added v1.8 test speed strategy document.
- Documented Tier 0 / Tier 1 / Tier 2 / Tier 3 test policy.
- Documented when real VPS/Cloudflare tests are needed.
- Added shared test assertion helper (`tests/lib/assertions.sh`).
- Added test speed strategy coverage test.

### Safety

- No install.sh behavior changed.
- No third command wrapper added.
- No `status --json` wrapping.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.31 — Operation Log Second Real Command Pilot: bin/nanobk --help

### Added

- Added opt-in operation-log help command pilot for `bin/nanobk --help`.
- Hidden output by default; verbose shows redacted help output.
- Added PLAIN/UI=0/CI no-ANSI tests for help command pilot.
- Added failure propagation test with test-only command override (`NANOBK_OPLOG_HELP_PILOT_CMD`).
- Added real pilot + help pilot independence test.
- Full dry-run unaffected; non-default test mode unaffected.

### Safety

- Only wraps `bin/nanobk --help` under explicit opt-in (`NANOBK_OPLOG_HELP_PILOT=1`).
- No `status --json` wrapping.
- No real deployment path changed.
- No `run_cmd`/`run_critical_step` rollout.
- No protocol templates changed.
- No Worker core changed.
- No rotate sync changed.
- No Bot/Web business logic changed.

## v1.8.30 — Operation Log Second Real Command Planning

### Added

- Added operation-log second real command planning.
- Compared `bin/nanobk --help` and `bin/nanobk status --json`.
- Documented status --json risks.
- Documented gates before wrapping --help.
- Documented gates before wrapping status --json.
- Recommended next step based on code inspection.
- Added second-command planning coverage test.

### Safety

- No install.sh behavior changed.
- No second command wrapper implemented.
- No real deployment path changed.
- No `run_cmd`/`run_critical_step` rollout.
- No protocol templates changed.
- No Worker core changed.
- No rotate sync changed.
- No Bot/Web business logic changed.

## v1.8.29 — Operation Log Real Command Pilot Checkpoint

### Added

- Added operation-log real command pilot checkpoint document.
- Documented v1.8.27 one-command real pilot proof.
- Documented v1.8.28 UI=0/CI coverage fix.
- Documented what real pilot proved and did not prove.
- Documented second real command risk assessment.
- Added real pilot checkpoint coverage test.

### Safety

- No install.sh behavior changed.
- No real deployment path changed.
- No `run_cmd`/`run_critical_step` rollout.
- No protocol templates changed.
- No Worker core changed.
- No rotate sync changed.
- No Bot/Web business logic changed.

## v1.8.28 — Operation Log Real Pilot UI=0/CI Test Fix

### Fixed

- Added missing UI=0 and CI no-ANSI regression tests for real command pilot.
- Corrected v1.8.27 test coverage gap (PLAIN was tested, UI=0/CI were not).

### Safety

- No installer behavior changed.
- No `run_cmd`/`run_critical_step` rollout.
- No real deployment path changed.

## v1.8.27 — Operation Log One Low-risk Real Command Pilot

### Added

- Added opt-in operation-log real command pilot for `bin/nanobk --version`.
- Hidden output by default; verbose shows redacted output.
- Added PLAIN/UI=0/CI no-ANSI tests for real command pilot.
- Added failure propagation test with test-only command override.
- Full dry-run unaffected; non-default test mode unaffected.

### Safety

- No real deployment path changed.
- No `run_cmd`/`run_critical_step` rollout.
- No protocol templates changed.
- No Worker core changed.
- No rotate sync changed.
- No Bot/Web business logic changed.

## v1.8.26 — Operation Log Pilot Acceptance Checkpoint

### Added

- Added operation-log pilot acceptance checkpoint document.
- Documented v1.8.20–v1.8.25 proof chain.
- Documented what pilot proved and did not prove.
- Documented real command pilot risk assessment.
- Recommended v1.8.27 one low-risk real command pilot.
- Added checkpoint coverage test.

### Safety

- No real deployment path changed.
- No `run_cmd`/`run_critical_step` rollout.
- No protocol templates changed.
- No Worker core changed.
- No rotate sync changed.
- No Bot/Web business logic changed.

## v1.8.25 — Operation Log Test Wrapper Failure Proof

### Fixed

- Fixed v1.8.24 proof gap: verbose/PLAIN/UI=0/CI wrapper tests used `NANOBK_TEST_OVERRIDE_SCRIPT` which bypassed the wrapper. Now use `NANOBK_OPLOG_TEST_WRAP_SCRIPT` to run a controlled test script through the wrapper.
- Added `NANOBK_OPLOG_TEST_WRAP_SCRIPT` support to `run_safe_test_logged_pilot()` — test-only override for wrapped script.
- Added real wrapper trigger tests: verbose, PLAIN, UI=0, CI — all verified to actually invoke wrapper.
- Added controlled failing script propagation test: verifies non-zero exit, failure label, log redaction, no raw secret on screen/log.
- Added missing override script test.

### Safety

- Only test-mode paths changed. No real deployment paths, no `run_cmd`/`run_critical_step` integration.

## v1.8.24 — Operation Log Single Test Path Pilot

### Added

- Added `run_safe_test_logged_pilot()` to `installer/install.sh` — wraps one safe test script (`output-control-chars.sh`) with operation-log hidden output under `NANOBK_OPLOG_TEST_WRAP=1` + `DEFAULTS=1`.
- Wrapped test output hidden by default, log file written with redaction, verbose shows redacted output.
- Failure propagation preserved: `TEST_FAILURES` and `TEST_FAILED_NAMES` updated on failure.
- Added single test path wrapper pilot tests: default no-trigger, trigger, non-defaults no-trigger, full dry-run no-trigger, verbose, PLAIN no-ANSI.

### Safety

- Only wraps `output-control-chars.sh` under explicit opt-in. No real deployment paths changed. No `run_cmd`/`run_critical_step` integration.

## v1.8.23 — Operation Log Pilot Defaults Boundary Fix

### Fixed

- Fixed `run_operation_log_pilot_check()` to require both `NANOBK_OPLOG_PILOT=1` AND `DEFAULTS=1`. Previously only checked `NANOBK_OPLOG_PILOT=1`, so `--mode test` without `--defaults` could trigger pilot.
- Added non-defaults no-trigger regression test.

### Safety

- No deployment logic, protocol templates, Worker core, rotate sync, Bot/Web logic, or run_cmd/run_critical_step changes.

## v1.8.22 — Operation Log Install.sh Pilot Hook

### Added

- Added `run_operation_log_pilot_check()` to `installer/install.sh` — opt-in harmless operation-log pilot under `NANOBK_OPLOG_PILOT=1` + `--mode test --defaults`.
- Pilot runs a harmless echo command with fake token, verifies redaction, shows log path.
- Default test mode does NOT trigger pilot (requires explicit `NANOBK_OPLOG_PILOT=1`).
- Full dry-run mode does NOT trigger pilot.
- Added install.sh pilot path tests: default no-trigger, pilot trigger, verbose redacted output, PLAIN no-ANSI, full dry-run unaffected.

### Safety

- Pilot only runs under `NANOBK_OPLOG_PILOT=1` + `--mode test --defaults`. No real deployment paths changed. No `run_cmd`/`run_critical_step` integration.

## v1.8.21 — Operation Log UI=0 Boundary Fix

### Fixed

- Fixed `_oplog_has_color()` in `installer/lib/operation-log.sh`: added `NANOBK_UI != "0"` check so UI=0 mode disables color in operation-log output.
- Added UI=0 no-ANSI test to operation-log pilot test suite.
- Added UI=0 log hint and secret safety assertions.

### Safety

- No run_cmd / run_critical_step integration. No deployment logic changed. No protocol templates, Worker core, rotate sync, or Bot/Web logic changed.

## v1.8.20 — Operation Log Low-risk Pilot

### Added

- Enhanced `installer/lib/operation-log.sh` with `oplog_run_hidden()` — captures command output to log, hides from screen by default. Verbose mode shows redacted output.
- Enhanced `oplog_redact()`: broadened `TOKEN=` pattern to catch 4+ char values (was 8+).
- Enhanced `oplog_init()`: log file permissions set to 600.
- Added `NANOBK_OPLOG_DIR` env var support as alias for `NANOBK_LOG_DIR` (test convenience).
- New `tests/unified-cli-operation-log-pilot-v1.8.sh` — operation log pilot tests covering redaction, hidden output, failure hints, verbose mode, PLAIN/UI=0/CI safety, log permissions.
- New `docs/validation-v1.8-operation-log-pilot.md` — pilot documentation with scope, safety rules, redaction patterns, limitations, and next-step guidance.

### Safety

- This is a low-risk pilot only. No `run_cmd` or `run_critical_step` changes. No real deployment output hiding. Default user paths unchanged.

## v1.8.19 — CLI Static UI Acceptance Checkpoint

### Added

- New `docs/validation-v1.8-cli-static-ui-checkpoint.md` — CLI static UI acceptance closure document.
  - Records v1.8.14 manual visual BLOCKED result and reasons.
  - Documents v1.8.15–v1.8.18 mode-boundary fix chain.
  - Records final four-mode status (Default/Compact/Plain/UI=0 all PASS).
  - Documents remaining limitations.
  - Provides next-stage decision matrix (operation-log pilot, dynamic progress, Bot polish, Web polish).
  - Recommends v1.8.20 Operation Log Low-risk Pilot.
- New `tests/unified-cli-static-ui-checkpoint-v1.8.sh` — verifies checkpoint document contains required records.

### Safety

- No deployment logic, protocol templates, Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.18 — UI=0 Summary Boundary Final Fix

### Fixed

- Fixed UI=0 Summary title Unicode dash leakage: `ui_section()` UI=0 branch now outputs plain text title instead of `── title ──`.
- Added single Unicode dash (`─`) check to UI=0 and Plain mode boundary tests.
- Added UI=0 Summary title boundary test: verifies title present, no Unicode dash, no ANSI.
- Added Plain Summary title boundary test: verifies title present, no Unicode dash, no ANSI.
- Added Default mode preservation test: verifies Summary title still present with product UI.
- Added Compact Summary title test.

### Safety

- All changes are display-only. No deployment logic, Summary status logic, or execution commands changed.

## v1.8.17 — Interactive Plain ANSI Cleanup

### Fixed

- Cleaned remaining interactive Plain/UI=0 ANSI leakage in `collect_vps_args()`, `collect_cloudflare_args()`, `collect_bot_args()`, `collect_web_args()`.
- Updated VPS domain warnings (protocol prefix, path, example domain, Let's Encrypt, self-signed typo recovery) to use `say_yellow()`.
- Updated Cloudflare URL warnings (Worker URL, placeholder, https detection) to use `say_yellow()`.
- Updated Cloudflare KV warnings (SUB_STORE, NANOB_GEO_CACHE) to use `say_yellow()`.
- Updated port conflict warning, Preflight summary, select_language prompt, show_menu header, test menu prompt to use `installer_has_color()`.
- Updated commands-only and root-run warnings to use `say_yellow()`.
- Added interactive Plain ANSI regression tests (VPS invalid input, UI=0 invalid input).
- Added static source guard test for remaining unguarded YELLOW echo lines.

### Safety

- All changes are display-only. No input validation, menu options, defaults, status variables, or execution commands changed.

## v1.8.16 — Plain ANSI Boundary Fix

### Fixed

- Fixed Plain mode (`NANOBK_PLAIN=1`) ANSI escape leakage: added `installer_has_color()` helper that checks `NANOBK_PLAIN`, `NANOBK_UI`, and `CI` env vars.
- Updated `log()`, `ok()`, `warn()`, `err()`, `print_cmd()` to use `installer_has_color()`.
- Updated `preflight_pass()`, `preflight_fail()`, `preflight_warn()` to use `installer_has_color()`.
- Updated `section_line()` to use `installer_has_color()` (also covers CI mode).
- Updated `run_cmd()`, `run_critical_step()`, `run_one_test()` dry-run/commands-only messages.
- Updated `mock_log()` to use `installer_has_color()`.
- Updated `prompt()`, `confirm()`, `prompt_menu_choice()` prompt display.
- Updated Summary disclaimers (dry-run, commands-only) to use `installer_has_color()`.
- Updated configuration confirmation headers (VPS, Cloudflare, Bot, Web) to use `installer_has_color()`.
- Updated Bot/Web safety warnings to use `installer_has_color()`.
- Updated main banner to use `installer_has_color()`.
- Added `say_yellow()`, `say_cyan()` helpers for mode-aware colored output.
- Added full-output ANSI boundary tests for PLAIN/UI=0/CI modes.
- Added Compact+Plain combined mode test.

### Safety

- All changes are display-only. No deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.15 — Plain and UI=0 Mode Boundary Fix

### Fixed

- Fixed Plain mode (`NANOBK_PLAIN=1`) full installer output: banner, preflight, tools status, section headers all converted to plain ASCII. No `╔║╚═✓■□──` characters remain.
- Fixed UI=0 mode: main banner uses plain text, no box drawing.
- Fixed Compact mode: main banner uses single-line format, section headers use plain text, preflight tools/ports condensed.
- Fixed `section_line` helper: COMPACT mode now uses plain text (no `──`).
- Fixed `preflight_pass`/`preflight_fail`/`preflight_warn`: PLAIN/UI=0 now use `OK`/`FAIL`/`WARN` instead of `✓`/`✗`/`⚠`.
- Fixed tools status display: PLAIN/UI=0 now use `OK`/`FAIL` instead of `✓`/`✗`.
- Fixed compact stage cards, token reminder, recovery block, dry-run notice: removed trailing blank lines to reduce visual density.
- Compact output is now ≤85% of default output line count (228 vs 269 lines).
- Added `tests/unified-cli-mode-boundaries-v1.8.sh` — 69 full-output mode boundary tests.

### Safety

- No deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed. All changes are display-only.

### Fixed

- Fixed Plain mode (`NANOBK_PLAIN=1`) full installer output: banner now uses plain text instead of box drawing (`╔║╚═`).
- Fixed Plain mode preflight: `preflight_pass` now outputs `OK` instead of `✓`, `preflight_fail` outputs `FAIL` instead of `✗`, `preflight_warn` outputs `WARN` instead of `⚠`.
- Fixed Plain mode tools status: tool check marks now use `OK`/`FAIL` instead of `✓`/`✗`.
- Fixed Plain mode section headers: `section_line` helper outputs plain text title instead of `── title ──` in PLAIN/UI=0 mode.
- Fixed UI=0 mode: main banner uses plain text instead of box drawing.
- Fixed Compact mode: main banner uses single-line format instead of box drawing.
- Added `section_line` helper function for mode-aware section headers.
- All Unicode box drawing (`╔║╚═`), checkmarks (`✓✗⚠`), progress bars (`■□`), and section borders (`──`) in `installer/install.sh` are now gated by PLAIN/UI=0 mode checks.
- Added `tests/unified-cli-mode-boundaries-v1.8.sh` — full-output mode boundary tests covering Plain, UI=0, Compact, and secret safety.

### Safety

- No deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed. All changes are display-only.

## v1.8.14 — CLI Manual Visual Comparison Guide

### Added

- New `docs/validation-v1.8-cli-visual-comparison.md` — manual visual comparison guide for default, compact, plain, and UI=0 modes.
  - Purpose: human visual comparison acceptance, not real deployment.
  - Safety rules: do NOT input real tokens, do NOT cat env files.
  - Commands for all four modes with `tee` output capture.
  - Quick safety grep for token/secret/fake-success detection.
  - Human review checklist per mode.
  - PASS / NEEDS POLISH / BLOCKED criteria.
  - Feedback template with per-mode sections.
  - Decision matrix for next version direction.
- New `tests/unified-cli-visual-comparison-guide-v1.8.sh` — verifies comparison guide contains required commands, safety rules, acceptance criteria, and decision matrix.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.13 — CLI Compact Mode and Visual Density Polish

### Added

- New `NANOBK_COMPACT=1` environment variable for compact display mode.
- Compact banner: single-line format (`NanoBK v1.8.13 · Full Recommended`), no box drawing.
- Compact stage cards: single-line per stage with key items joined by `·`.
- Compact token reminder: single-line safety summary preserving all required security semantics.
- Compact recovery block: shorter intro, still shows all recovery commands.
- Compact dry-run notice: shorter format, still contains both Chinese and English disclaimers.
- New `tests/unified-cli-compact-mode-v1.8.sh` — compact mode snapshot tests covering banner, stage cards, token reminder, recovery block, dry-run notice, Full Wizard dry-run, and line count comparison.

### Safety

- Compact mode preserves all security semantics: no secrets, no fake success, control-plane warnings, honest status words.
- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.12 — CLI Stage Page Cards Polish

### Added

- New `ui_stage_card` generic function in `installer/lib/ui.sh` — displays stage description and bullet items with PLAIN/NO_EMOJI/UI=0/CI fallback.
- New stage-specific card helpers: `ui_stage_card_vps`, `ui_stage_card_cloudflare`, `ui_stage_card_bot`, `ui_stage_card_web`, `ui_stage_card_summary`.
- Stage cards inserted in `installer/install.sh` after each `ui_section` call (VPS, Cloudflare, Bot, Web Panel, Summary).
  - VPS card: HY2/TUIC/Reality/Trojan, systemd, healthcheck, dry-run note.
  - Cloudflare card: nanok/nanob, KV/Service Binding, verify, dry-run note.
  - Bot card: control plane, nanobk CLI, token safety.
  - Web Panel card: control plane, no direct secrets, SSH tunnel, not node-ready.
  - Summary card: honest status words, dry-run not real deployment.
- New `tests/unified-cli-stage-cards-v1.8.sh` — stage card snapshot tests covering default, PLAIN, NO_EMOJI, UI=0, dry-run output, secret safety, fake success guard.

### Safety

- All install.sh changes are display-only: added `ui_stage_card_*` calls after existing `ui_section` calls. No if/case/return moved, no variables changed, no status words changed, no commands changed.

## v1.8.11 — Brand Banner Width and Snapshot Fix

### Fixed

- Fixed `_ui_banner_box` long subtitle overflow: subtitle exceeding inner width is now truncated with `...` instead of breaking the right border.
- Expanded box inner width range: min 46, max 76 (total line ≤ 80 columns with prefix and borders).
- Added direct `_ui_banner_box` snapshot test: verifies box drawing characters (`╭╮╰╯│`), product name, version, subtitle, and width ≤ 90 columns.
- Added long subtitle width guard test: verifies extra-long subtitle is truncated or fits without breaking the box.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.10 — NanoBK Brand Banner and CLI Identity

### Added

- Enhanced `ui_banner` in `installer/lib/ui.sh` with branded box-style banner for interactive terminals.
  - Default mode: Unicode box-drawing frame with product name, tagline ("一条命令，完成 VPS 代理部署"), and subtitle.
  - PLAIN mode: clean text fallback, no box drawing, no ANSI, no emoji.
  - NO_EMOJI mode: box drawing preserved (if terminal supports), no emoji.
  - UI=0 mode: minimal traditional output, no box, no emoji.
  - Non-TTY / CI: automatically falls back to plain text, no ANSI, no emoji.
  - Width guard: longest line ≤ 52 columns inside box, ≤ 90 columns total.
- New `tests/unified-cli-brand-identity-v1.8.sh` — brand identity snapshot tests covering default, PLAIN, NO_EMOJI, UI=0, CI=1 modes, width guard, and secret safety.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.9 — CLI Visual Polish Checkpoint and Validation Notes

### Added

- Updated `docs/validation-v1.8-cli-visual.md` with Phase 13 acceptance result, v1.8.7/v1.8.8 follow-up fixes documentation, and next-phase decision point.
- New `tests/unified-cli-validation-notes-v1.8.sh` — verifies validation guide contains Phase 13 result, follow-up fixes, decision point, and no real secrets.

### Changed

- Tightened user-skip VPS dry-run Summary test: now fails if VPS block is not found in Summary output (was passing silently).

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.8 — CLI Dry-run Skip Summary Honesty Fix

### Fixed

- Fixed dry-run VPS Summary honesty edge case: when user explicitly skips VPS in dry-run mode, Summary now correctly shows `skipped (dry-run)` instead of `planned / dry-run`.
- Added `VPS_STAGE_STATUS == "skipped"` check before global `DRY_RUN` check in `print_summary()` VPS block (display-only, no logic change).
- Narrowed dry-run layout test `skipped (dry-run)` check to VPS Summary block only (was global, could误伤).
- Added user-skip VPS dry-run Summary test: verifies VPS block shows `skipped` when user explicitly skips.
- Added mock/dry-run existing-state output test: creates temporary wizard state file and verifies explanation text appears in output.

### Safety

- No run_cmd / run_critical_step, deploy status tracking, resume routing, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web business logic, or admin env logic changed.

## v1.8.7 — CLI Dry-run Mock State Wording Polish

### Changed

- VPS Summary in dry-run mode now shows `planned / dry-run` instead of `skipped (dry-run)` (display-only, no logic change).
- Added mock/dry-run explanation in `wizard_state_print`: "（mock / dry-run 模式，不会读取真实部署状态）" when `NANOBK_TEST_MOCK=1` or `DRY_RUN=1`.
- Polished mock output wording from English to Chinese product copy:
  - `VPS deploy success (simulated)` → `VPS 部署步骤已模拟完成 (dry-run)`
  - `Cloudflare deploy success (simulated)` → `Cloudflare 部署步骤已模拟完成 (dry-run)`
  - `Cloudflare preflight passed (simulated)` → `Cloudflare 预检已模拟通过 (dry-run)`
  - `Profile validation passed (simulated)` → `配置文件验证已模拟通过 (dry-run)`
  - `Healthcheck passed (simulated)` → `健康检查已模拟通过 (dry-run)`
  - `Cloudflare verify passed (simulated)` → `Cloudflare 验证已模拟通过 (dry-run)`
- Strengthened dry-run layout tests: VPS Summary wording, mock output product wording, mock/dry-run explanation in source.

### Known Limitations

- Telegram Bot configuration confirmation may appear twice in dry-run defaults mode. This is a pre-existing interaction flow behavior and is not addressed in this release to avoid modifying real Bot configuration logic.

### Safety

- No run_cmd / run_critical_step, deploy status tracking, resume routing, Summary status judgment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web business logic, or admin env logic changed.
- All mock output changes are display-only strings; no variable meanings, status words, or execution paths changed.

## v1.8.6 — CLI Manual Dry-run Visual Acceptance Guide

### Added

- New `docs/validation-v1.8-cli-visual.md` — manual CLI visual acceptance guide.
  - Purpose: CLI page visual and beginner experience acceptance (not real deployment).
  - Safety rules: do NOT input real tokens, do NOT cat env files, do NOT share real IPs/URLs.
  - Safe dry-run commands: `NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 --dry-run --defaults`.
  - PLAIN mode and NO_EMOJI mode commands.
  - Human review checklist: entry page, stages, dry-run honesty, security, summary, overall feel.
  - PASS / NEEDS POLISH / BLOCKED criteria.
  - Feedback template.
- New `tests/unified-cli-visual-guide-v1.8.sh` — verifies guide contains required safety rules, commands, and acceptance criteria.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.5 — CLI Dry-run Page Layout Polish

### Added

- New `ui_dry_run_notice` function in `installer/lib/ui.sh` — displays clear dry-run disclaimer in both Chinese and English.
- New `tests/unified-cli-dry-run-layout-v1.8.sh` — dry-run page layout snapshot tests.
  - Entry page: verifies NanoBK, Full Recommended, VPS+Cloudflare+Bot+Web Panel.
  - Stage structure: verifies VPS, Cloudflare, Telegram Bot, Web Panel presence.
  - Stage ordering: verifies VPS → Cloudflare → Bot → Web Panel order.
  - Dry-run honesty: verifies "planned / dry-run", no fake success, Summary present.
  - Control-plane wording: verifies "控制端配置" and "不代表 VPS 节点或 Cloudflare 订阅已经可用" preserved in install.sh.
  - Secret safety: verifies no SECRET_TEST_BOT_TOKEN, TOKEN=, SECRET=, ADMIN_TOKEN=, NANOBK_CF_API_TOKEN, env file paths.
  - Visual noise: verifies no bash trace (`+ echo`, `+ set`), limits raw command lines.
  - Test helper stability: verifies no `printf | grep -q` pipe, uses here-string.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.4 — CLI Wording and Page Copy Polish

### Changed

- Polished `ui_token_reminder` wording: "输入 token 时请不要截图，也不要把它发到聊天、issue 或日志里。NanoBK 会尽量隐藏敏感信息，但你仍然应该把 token 当作密码保管。如果 token 暴露，请立即在对应平台 revoke / regenerate。"
- Polished `ui_recovery_block` wording: added intro "可以稍后继续" and "下面这些命令可以帮助你恢复或重新执行当前阶段：" before listing commands.
- Strengthened visual snapshot checks: added "当作密码保管", "隐藏敏感信息", "聊天、issue 或日志", "可以稍后继续", "恢复或重新执行", control-plane wording assertions.

### Safety

- No install.sh business logic, deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.
- Control-plane semantic "Bot/Web 是控制端配置，不代表 VPS 节点或 Cloudflare 订阅已经可用" preserved in install.sh.

## v1.8.3 — CLI Visual Snapshot and Install Output Polish

### Added

- New `tests/unified-cli-visual-snapshot-v1.8.sh` — visual snapshot tests for CLI output shape.
  - Banner snapshot: verifies product name, version, subtitle, no ANSI/emoji in PLAIN mode.
  - Section snapshot: verifies `Step N/M` format, no Unicode bars/dashes in PLAIN mode.
  - Recovery block snapshot: verifies commands shown, no secret leakage, no ANSI in PLAIN.
  - Token reminder snapshot: verifies honest wording (revoke/regenerate/脱敏), no absolute promise.
  - Progress snapshot: verifies `Step N/M - label` in PLAIN, no Unicode bars.
  - Divider snapshot: verifies ASCII dash in PLAIN, no Unicode dash.
  - Summary card snapshot: verifies honest status words preserved, no fake success.
  - Full Wizard dry-run smoke: verifies key content present, no secret leakage, no dangerous control chars.
  - Test helper self-check: verifies no `printf | grep -q` pipe, uses here-string.

### Changed

- Polished `ui_banner` legacy bypass (UI=0) to indent subtitle consistently.
- Polished `ui_recovery_block` legacy bypass (UI=0) label from "恢复命令" to "恢复方法" for consistency with non-legacy output.
- Updated UI display layer version comment to v1.8.3.

### Safety

- No deployment logic, install.sh business logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or Summary status logic changed.

## v1.8.2 — CLI UI Test Stability and Log Raw Guard

### Fixed

- Fixed test helper stability check in `tests/unified-cli-ui-v1.8.sh` Test 14: replaced `grep -v | grep -qF` pipe with variable + here-string to eliminate `set -Eeuo pipefail` flakiness.
- `oplog_init` now redacts the `label` parameter before writing to log file and using it in the log filename.
- `oplog_close` now redacts the `status` parameter before writing to log file.

### Safety

- No deployment logic, VPS protocol templates, Cloudflare Worker core, rotate sync, Bot/Web logic, or install.sh main flow changed.

## v1.8.1 — CLI UI Plain Mode and Log Safety Fix

### Fixed

- Fixed test helper `assert_contains`/`assert_not_contains` to use here-string (`<<<`) instead of `printf | grep -q` pipe, preventing `set -Eeuo pipefail` flakiness.
- Fixed `NANOBK_PLAIN=1` mode: `ui_section` now outputs `Step N/M - title` instead of Unicode `■□──` bars.
- Fixed `NANOBK_PLAIN=1` mode: `ui_progress` now outputs `Step N/M - label` instead of Unicode bars.
- Fixed `NANOBK_PLAIN=1` mode: `ui_divider` now uses plain ASCII `-` instead of Unicode `─`.
- Fixed `NANOBK_PLAIN=1` mode: `ui_spinner_start` explicitly skips animation in PLAIN mode.
- Fixed `ui_spinner_stop`: no longer emits `\033[K` ANSI clear-line escape in non-TTY/PLAIN mode.
- Fixed `ui_banner`: no `echo -e` in non-color mode.
- Fixed `oplog_hint_on_failure`: no longer emits `\033[0;36m` ANSI escape in non-TTY/PLAIN/CI mode.
- Corrected `ui_token_reminder` wording: removed over-promise "不会出现在屏幕或日志中", now says "不要截图或把 token 发到聊天、issue、日志" and "尽量脱敏".

### Hardened

- `oplog_write` now always calls `oplog_redact` before writing to log file (was raw write).
- `oplog_run` now redacts command line arguments before logging.
- `oplog_redact` expanded coverage: `SUB_TOKEN`, `ADMIN_TOKEN`, `NANOB_TOKEN`, `CF_API_TOKEN`, `REALITY_PRIVATE_KEY`, `PRIVATE_KEY`, `SECRET`, `KEY`, `TOKEN` (with single/double quote variants), `Authorization: Bearer`, `password` (with quote variants), `?token=`, `&token=`, `?admin_token=`, `?sub_token=` query parameters.
- `ui_detect_capabilities` now checks `CI` env var to disable color in CI environments.
- Added internal `_oplog_write_raw` for header-only writes that bypass redaction.
- Added `_oplog_has_color` helper for lightweight capability check independent of ui.sh.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No deployment logic, menu logic, resume routing, or healthcheck/cf verify semantics changed.
- Summary honest status words preserved unchanged.

## v1.8.0 — CLI Product UI and Operation Log Polish

### Added

- New `installer/lib/ui.sh` — unified UI display layer for the installer and Full Wizard.
  - `ui_banner`, `ui_section`, `ui_step`, `ui_info`, `ui_success`, `ui_warn`, `ui_error` functions.
  - `ui_progress` with `[■■■□□□]` visual bar and plain fallback.
  - `ui_summary_card`, `ui_recovery_block`, `ui_token_reminder`, `ui_describe`.
  - Supports `NANOBK_PLAIN=1` (all decoration off), `NANOBK_NO_EMOJI=1` (emoji off only), `NANOBK_UI=0` (legacy bypass).
  - Non-TTY and CI-safe: no color, no emoji, no spinner outside interactive terminals.
- New `installer/lib/operation-log.sh` — operation logging skeleton.
  - Timestamped log files under `/var/log/nanobk/` or `$TMPDIR` fallback.
  - `oplog_redact` helper strips bot tokens, API tokens, passwords, workers.dev URLs before logging.
  - `oplog_run` captures command output to log, shows inline only in `NANOBK_VERBOSE=1`.
  - `oplog_hint_on_failure` shows log path after failures.
- Full Wizard now uses `ui_banner` for startup display.
- Full Wizard phase headers use `ui_section` with progress indicator (`[■■■□□□] 1/5`).
- Full Wizard failure recovery blocks use `ui_recovery_block` for consistent formatting.
- Full Wizard token safety reminder uses `ui_token_reminder`.
- Full Wizard control-plane-only warnings use `ui_warn`.

### Changed

- Version bumped to 1.8.0 in `bin/nanobk`, `installer/install.sh`, `installer/bootstrap.sh`.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No deployment logic, menu logic, resume routing, or healthcheck/cf verify semantics changed.
- Summary honest status words (planned, dry-run, failed, manual_pending, skipped, etc.) are preserved unchanged.
- No secret tokens, env file contents, real IPs, or subscription URLs are printed.

## v1.7.27 — Existing Runtime Refresh Reliability Fix

### Fixed

- Removed unsupported `--quiet` argument from Full Wizard existing runtime healthcheck refresh.
- Preserved refreshed `installed` / `verified` / `admin env installed` states when choosing Cloudflare or Bot/Web resume paths.
- Fixed the new existing deployment resume test harness to avoid `echo "$text" | grep -q` under `set -Eeuo pipefail`.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Real fresh deployment mode still checks core port conflicts.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.26 — Existing Deployment Resume Preflight Summary Fix

### Fixed

- Refreshed existing deployment runtime state before showing the Full Wizard resume menu.
- Avoided stale `manual_pending` / `deployed` resume labels when healthcheck and Cloudflare verify state already prove installed/verified status.
- Skipped VPS core port conflict preflight when resuming from Cloudflare/Bot/Web on an existing deployment.
- Preserved fresh deployment port conflict checks for real new installs.
- Improved existing deployment Summary so verified nanok/nanob and admin env installed status are shown truthfully.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Real fresh deployment mode still checks core port conflicts.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.25 — Interactive Mock Input and Verified Summary Alignment Fix

### Fixed

- Updated dynamic Full Wizard mock input flows so mock tests no longer fall into example Worker URL placeholder rejection loops on VPS with real system state.
- Fixed mock wizard state detection so resume menu doesn't appear in non-resume mock tests, preventing input stream misalignment.
- Aligned Cloudflare mock state so Summary proves `nanok: verified`, `nanob: verified`, `verify: passed`, and `admin env: installed`.
- Prevented Cloudflare verified Summary mock tests from being polluted by unrelated mock VPS failed state.

### Safety

- Real deployment still rejects example/placeholder Worker URLs.
- Strict Cloudflare Summary checks remain enforced; `deployed or verified` is not accepted.
- Dynamic mock timeout and subprocess cleanup diagnostics remain in place.
- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.

## v1.7.24 — Interactive Mock Timeout Diagnostics Fix

### Fixed

- Added hard timeouts to dynamic Full Wizard interactive mock tests so Phase A cannot hang indefinitely.
- Added subprocess cleanup (process group kill) for timed-out mock installer runs.
- Added timeout diagnostics with test name, recent output, and input summary.
- Added timeout protection for state-summary dynamic mock checks.
- Preserved v1.7.22/v1.7.23 strict Cloudflare Summary checks for nanok/nanob verified, verify passed, and admin env installed.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Real deployment mode remains unchanged.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.23 — Test Harness Mock Preflight Isolation Fix

### Fixed

- Made `NANOBK_TEST_MOCK=1` preflight port checks assume core ports are free so interactive mock tests are not affected by already-running NanoBK services.
- Added/used `NANOBK_ASSUME_PORTS_FREE=1` for hermetic test-mode preflight isolation.
- Kept real non-mock Full Wizard port conflict detection unchanged.
- Preserved v1.7.22 strict Cloudflare Summary checks for verified nanok/nanob, verify passed, and admin env installed.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Real deployment mode still checks core port conflicts.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.22 — Full Wizard Verified Summary Mock Fix

### Fixed

- Disabled the legacy hand-written admin env auto-write path during Full Wizard so the wizard uses `bin/nanobk cf install-admin-env` as the authoritative admin env installer.
- Updated Cloudflare mock deploy to write mock verified env state so Summary can prove nanok/nanob verified status.
- Tightened dynamic stdin mock checks to require `nanok: verified`, `nanob: verified`, `verify: passed`, and `admin env: installed`.
- Removed loose `deployed or verified` acceptance from Cloudflare Summary mock validation.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Admin tokens remain hidden and are not printed in Summary or logs.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.21 — Full Wizard Cloudflare State Callback Fix

### Fixed

- Fixed Cloudflare deploy status callback mismatch where the deploy collector returned `deployed` but the Full Wizard caller expected `executed`.
- Added a real `install_cf_admin_env_from_wizard` helper that reuses `bin/nanobk cf install-admin-env` instead of duplicating admin env file writing logic.
- Refreshed Cloudflare verify states before Summary so nanok/nanob can show verified when env status proves verification passed.
- Added dynamic mock coverage for Cloudflare verified Summary and admin env status.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Admin tokens remain hidden and are not printed in Summary or logs.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.20 — Full Wizard State and Summary Truth Fix

### Fixed

- Separated VPS deploy status from optional healthcheck/status-check results so skipped checks no longer overwrite successful installs.
- Refreshed Cloudflare deploy/verify stage states so Full Wizard Summary reports deployed/verified instead of configured/pending after success.
- Full Wizard now installs Cloudflare admin env via `bin/nanobk cf install-admin-env` after Cloudflare deploy success.
- Replaced remaining loose Full Wizard `[y/N]` prompts for healthcheck/status/verify steps with strict numbered menus.

### Safety

- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- No new real VPS or Cloudflare validation is claimed by this commit.
- Admin tokens remain hidden and are not printed in Summary or logs.
- Real Full Wizard validation remains a manual user-run step.

## v1.7.19 — Test Harness Grep Stability Completion

### Fixed

- Completed grep/pipefail stabilization across remaining Full Wizard test harness scripts.
- Replaced remaining fragile `echo "$output" | grep -q` checks with here-string based grep checks.
- Fixed flaky dry-run Summary assertions such as `planned / dry-run` checks in unified-full-wizard-behavior.sh.
- Applied here-string fix to all test files: unified-full-wizard-behavior.sh, unified-beginner-flow.sh, unified-full-wizard-review-resume.sh, unified-summary-honesty.sh, unified-test-failure-propagation.sh, unified-noninteractive-mode.sh, unified-installer-safety.sh, unified-installer-resume.sh, unified-installer-config.sh, unified-installer-dry-run.sh, unified-preflight-static.sh, unified-dry-run-preflight.sh, nanob-status-env.sh, nanob-fallback-static.sh, nanobk-status-cloudflare.sh, nanobk-cli-dry-run.sh, bootstrap-dry-run.sh, cloudflare-installer-dry-run.sh, production-hotfix-static.sh.
- Preserved Full Wizard, Cloudflare installer, VPS protocol templates, Worker core logic, Bot/Web business logic, and rotate sync behavior unchanged.

### Safety

- No real VPS or Cloudflare validation is claimed.
- No production validation is claimed.
- This release only fixes local test harness stability.
- Real clean VPS validation remains a manual user-run step.

## v1.7.18 — Validation Test Harness Grep Stability Fix

### Fixed

- Stabilized validation-plan test helpers under `set -Eeuo pipefail`.
- Replaced fragile `echo "$output" | grep -q` checks with here-string based grep checks.
- Fixed a flaky `contains nanob` failure where validate-plan output contained `nanob` but the test harness misreported failure.
- Applied the same fix to `unified-cloudflare-dependency.sh`, `unified-real-vps-ux-hardening.sh`, and `unified-dry-run-preflight.sh`.
- Preserved Full Wizard and Cloudflare installer behavior unchanged.

### Safety

- No real VPS or Cloudflare validation is claimed.
- No VPS protocol templates, Worker core logic, Bot/Web business logic, or rotate sync logic changed.
- This release only fixes local validation test harness stability.

## v1.7.17 — Cloudflare Mock/Dry-run Unbound Variable Fix

### Fixed

- Initialized Cloudflare route/profile variables to prevent `route_url: unbound variable` in dry-run/default flows.
- Initialized Cloudflare admin env variables to prevent `adm_token: unbound variable` in mock/dry-run paths.
- Preserved mock/dry-run/commands-only behavior without requiring real Cloudflare admin tokens.
- Revalidated Full Wizard dynamic stdin mock and all safe tests after cleaning test residues.

### Safety

- No real VPS or Cloudflare validation is claimed.
- No VPS protocol templates, Worker core logic, or rotate sync logic changed.
- Mock and dry-run paths must not require or print raw admin tokens.
- Real clean VPS validation remains a manual user-run step.

## v1.7.16 — Version and Documentation Sync

### Fixed

- Synchronized displayed version numbers across installer, CLI, bootstrap, README, quickstart, roadmap, and validation docs.
- Documented that v1.7.15 hardened the Full Wizard test gates.
- Kept Full Wizard dynamic stdin mock as the local prerequisite before any further real VPS validation.

### Safety

- No real VPS or Cloudflare validation is claimed.
- No installer behavior, protocol templates, Worker core logic, or rotate sync logic changed in this release.
- Real clean VPS validation remains a manual user-run step.

## v1.7.15 — Full Wizard Test Gate Hardening

### Fixed

- Restored `installer/install.sh --mode test --defaults` to run all safe tests by default.
- Dynamic stdin mock now requires installer exit code 0 for each main flow.
- Dynamic stdin mock no longer deletes real repository `bot/.env` or `web/.env` by default.
- Removed artificial marker output that could cause external grep checks to pass without installer output.

### Safety

- Mock tests remain offline and do not connect to a real VPS or Cloudflare.
- Mock tests do not write to `/etc`, `/root`, or real repository env files by default.
- v1.7.15 does not claim real VPS or Cloudflare validation.

## Previous Full Wizard Dynamic Mock Failure Fix

### Fixed

- Fixed the failing Full Wizard dynamic stdin mock tests from v1.7.13.
- Ensured find_existing_kv_id works in mock, dry-run, commands-only, and real modes.
- Cloudflare stdin mock now dynamically verifies Worker URL recommendation, SUB_STORE reuse, NANOB_GEO_CACHE reuse, profile validation, and mock deploy.
- Resume stdin mock now verifies Cloudflare and Bot/Web routing.
- tests/full-wizard-interactive-mock.sh now passes with 0 failed checks.

### Safety

- Mock tests do not connect to a real VPS or Cloudflare.
- Mock tests do not write to /etc or /root.
- Mock output does not print raw tokens or secrets.
- This release does not claim real VPS or Cloudflare validation.

## v1.7.13 — Cloudflare Stdin Mock and KV Helper Completion

### Fixed

- Added or repaired find_existing_kv_id so Cloudflare existing KV recovery can return namespace IDs
- Mock KV recovery now returns mock-sub-store-id and mock-geo-cache-id through the real Cloudflare flow
- Dynamic stdin mock now covers the Cloudflare branch, Worker URL recommendation, SUB_STORE reuse, NANOB_GEO_CACHE reuse, and mock Cloudflare deploy
- Dynamic stdin mock now covers resume-from-Cloudflare and resume-to-Bot/Web routing

### Safety

- Mock tests do not connect to a real VPS or Cloudflare
- Mock tests do not write to /etc or /root
- Mock output does not print raw tokens or secrets
- v1.7.13 does not claim real VPS or Cloudflare validation

## v1.7.12 — Full Wizard Real Stdin Mock Validation

### Fixed

- Full Wizard interactive mock now uses a real stdin input stream instead of --defaults
- Dynamic mock now verifies invalid menu input, review editing, Bot/Web redaction, and Summary output from real installer output
- Test matrix now documents the dynamic interactive mock test
- v1.7 validation docs now clarify that stdin mock passing is required before any further real VPS test

### Safety

- Mock tests do not connect to a real VPS or Cloudflare
- Mock tests do not write to /etc or /root
- Mock output does not print raw tokens or secrets
- v1.7.12 does not claim real VPS or Cloudflare validation

## v1.7.11 — Full Wizard Dynamic Mock and Cloudflare UX Completion

### Fixed

- Full Wizard interactive mock now runs `installer/install.sh --mode full` with a real input stream
- Mock test now verifies review edits, invalid input rejection, Worker URL recommendation, KV reuse, token redaction, and Summary output dynamically
- Cloudflare setup now recommends nanok/nanob Worker URLs from a workers.dev subdomain
- NANOB_GEO_CACHE existing KV recovery is now wired into the Cloudflare flow
- Cloudflare review table now reflects recommended Worker URLs and reused KV states

### Safety

- Mock tests do not connect to a real VPS or Cloudflare
- Mock tests do not write to /etc or /root
- Review tables and mock output do not print raw tokens or secrets
- v1.7.11 does not claim real VPS or Cloudflare validation

## v1.7.10 — Full Wizard Flow Wiring Cleanup

### Fixed

- Wired VPS, Cloudflare, Bot, and Web review loops into the actual Full Wizard flow
- Removed old one-shot review tables from collect_vps_args, collect_cloudflare_args, collect_bot_args, and collect_web_args
- Editing a review field now returns to the same review table before execution
- Existing Cloudflare KV detection is now used before automatic KV creation
- Worker URL recommendation is now used before asking for full Worker URLs
- Mock deploy/preflight/validate paths now run through the real Full Wizard flow
- Interactive mock tests now run the Full Wizard input stream instead of only grepping source code
- Bot/Web internal dry-run, self-test, launch, and 0.0.0.0 confirmations no longer use loose confirm

### Safety

- Mock tests do not connect to VPS or Cloudflare
- Mock tests do not write to /etc or /root
- Review tables and mock output do not print raw tokens or secrets
- v1.7.10 does not claim real VPS or Cloudflare validation

## v1.7.9 — Full Wizard Real Interaction Mock Hardening

### Fixed

- Full Wizard critical choices no longer use loose y/n confirmation
- Review tables now loop until the user confirms, returns, or exits
- Editing a stage field returns to the stage review table
- Resume routing no longer marks Cloudflare as deployed without evidence
- Existing KV recovery is now wired into the Cloudflare flow
- Worker URL recommendations are now wired into the Cloudflare flow
- Interactive mock tests now execute real input streams instead of static grep checks

### Improved

- Added real local mock interaction tests for invalid input, review edits, resume routing, KV reuse, Worker URL recommendation, and token redaction
- Bot/Web configuration now uses strict review loops before writing env files
- Full Wizard state transitions are easier to verify without repeated real VPS tests

### Safety

- Mock tests do not connect to VPS or Cloudflare
- Review tables and mock output do not print raw tokens or secrets
- v1.7.9 does not claim real VPS or Cloudflare validation

## v1.7.8 — Full Wizard Interaction Harness and Real Review Flow

### Added

- Local interactive Full Wizard mock tests to reduce repeated real VPS validation
- Real VPS, Cloudflare, Bot, and Web review tables with edit loops
- Strict numbered Full Wizard menus for critical choices
- Resume stage routing that can actually continue from Cloudflare or Bot/Web
- Existing KV recovery flow wired into Cloudflare setup
- Worker URL recommendation flow based on a workers.dev subdomain
- Test-only mock mode for Full Wizard interaction paths

### Fixed

- Full Wizard no longer relies on loose y/n confirmation for critical user choices
- Invalid inputs such as t no longer continue as yes in Full Wizard paths
- Review tables are now part of the actual flow instead of static text
- Resume menu choices now skip completed stages instead of only changing labels
- Existing SUB_STORE / NANOB_GEO_CACHE can be reused instead of causing dead-end failures
- Domain input first offers protocol/path correction, then validates the corrected domain
- Bot/Web setup now has review/modify confirmation before writing env files

### Safety

- Mock tests do not connect to VPS or Cloudflare
- Resume state and review tables do not store or print raw secrets
- Local/offline tests still do not claim real VPS or Cloudflare validation

## v1.7.7 — Full Wizard Review, Resume, and Existing Resource Recovery

### Added

- Full Wizard resume state file for interrupted sessions
- Stage review tables for VPS, Cloudflare, Bot, and Web configuration
- Strict numbered menus for critical choices
- Existing Cloudflare KV recovery and reuse prompts
- Worker URL recommendation from detected Cloudflare Workers subdomain
- Output control-character checks for installer/status/cloudflare output
- Stronger domain validation for real deployment mode

### Fixed

- Invalid menu inputs such as random letters no longer continue as yes
- Users can review and modify stage inputs before execution
- Interrupted Full Wizard runs can resume from the next logical stage
- Existing SUB_STORE and NANOB_GEO_CACHE no longer cause dead-end failures
- Worker URLs no longer require beginners to type the full URL manually
- Full Wizard no longer accepts invalid domains such as pure numbers or no-dot strings
- Bot/Web are included in final Full Wizard validation state

### Safety

- Resume state avoids storing raw secrets
- Tokens and subscription URLs remain hidden by default
- Local/offline tests still do not claim real VPS or Cloudflare validation
- Real clean VPS validation remains a user-executed step

## v1.7.6 — Full Wizard Critical State and Admin Env Hardening

### Fixed

- Re-validates corrected domain input so placeholder domains cannot bypass real-mode checks
- Cloudflare preflight/profile validation skipped by the user now stops the Cloudflare stage as manual-pending
- Critical-step menu no longer offers misleading "return to edit parameters" option
- Summary no longer falls back to configured/not verified when Cloudflare was requested but never actually prepared/deployed
- Admin env installation now avoids putting tokens in sudo command-line arguments
- Direct Cloudflare installer runs now provide a safe admin env installation path for rotate sync

### Improved

- Added safer admin env installation flow using a temporary file and sudo install -m 600
- Added `nanobk cf install-admin-env` to install /root/.nanok-cf-admin.env from .cloudflare.local.env without printing tokens
- Cloudflare installer next steps now mention install-admin-env command

### Safety

- Tokens are not printed or embedded in process command arguments
- Skipped critical Cloudflare steps are manual-pending, not configured or deployed
- Local/offline tests still do not claim real VPS or Cloudflare validation

## v1.7.5 — Real VPS Full Wizard UX Hardening

### Fixed

- Full Wizard now rejects placeholder Worker URLs in real deployment mode
- Critical deploy steps no longer use ambiguous [y/N] prompts that can silently skip deployment
- Cloudflare skipped/manual-pending states no longer appear as configured/not verified
- Bot/Web now remain control-plane-only whenever Cloudflare is not deployed or verified
- Cloudflare deploy now writes the admin env needed by rotate sync
- Cloudflare installer no longer prints raw subscription URLs or admin token URLs by default

### Improved

- Added headless Wrangler OAuth guidance for clean VPS environments
- Added explicit critical-step menus for VPS and Cloudflare deployment
- Added safer redacted output for subscription/admin URLs
- Added validation checks for placeholder domains and Worker URLs
- Updated real VPS validation documentation based on the tenth clean VPS run

### Safety

- Tokens and subscription URLs are hidden by default
- Local/offline tests still do not claim real VPS or Cloudflare validation
- Real clean VPS validation remains a user-executed manual step

## v1.7.4 — Full Wizard Control Plane State Propagation

### Fixed

- Bot/Web now show control-plane-only when VPS is manual-pending, commands-only, dry-run, skipped, failed, or unknown
- Bot/Web now show control-plane-only when Cloudflare is manual-pending, commands-only, dry-run, skipped, dependency-missing, failed, or unknown
- Full Wizard no longer reports Bot/Web as ordinary configured when lower layers were not actually deployed or verified

### Improved

- Added a shared `control_plane_only_required()` helper for consistent Bot/Web status decisions
- Summary warnings now cover manual-pending and commands-only dependency states
- Full Wizard behavior tests cover Bot/Web control-only propagation from pending lower-layer states

### Safety

- Control-plane configuration is never presented as proof that VPS nodes or Cloudflare subscriptions are usable
- Local tests still do not claim real VPS or Cloudflare validation

## v1.7.3 — Full Wizard Command Execution State Hardening

### Fixed

- Critical deploy commands no longer report success when the user chooses not to execute them
- Full Wizard no longer marks VPS as installed when the VPS deploy command was only printed or skipped
- Full Wizard no longer marks Cloudflare as deployed when the Cloudflare deploy command was only printed or skipped
- Behavior tests now check command exit status correctly instead of masking failures with `|| true`

### Improved

- Added explicit command execution outcomes for executed, skipped, dry-run, commands-only, and failed states
- Summary now distinguishes installed/deployed from manual command not executed
- Full Wizard behavior tests cover skipped command execution paths

### Safety

- Non-executed commands are reported as manual/pending, not as verified deployment
- Local tests still do not claim real VPS or Cloudflare validation

## v1.7.2 — Full Wizard Retry Flow Hardening

### Fixed

- Fixed cert-mode retry flow so "重新选择 / 返回重新选择" no longer returns success before VPS deployment
- `collect_vps_args` now returns success only after the VPS deploy command has actually completed successfully
- Full Wizard no longer marks VPS as installed when the user merely chooses to reselect cert mode
- Corrected v1.7.1 changelog/test documentation drift

### Improved

- Cert-mode selection now uses an internal retry loop instead of returning early to the caller
- Full Wizard behavior tests now include real command-output checks instead of only static grep
- Added v1.7 Full Wizard validation document for manual clean VPS verification

### Safety

- Retry/cancel paths now preserve honest Summary states
- Local tests still do not claim real VPS or Cloudflare validation

## v1.7.1 — Full Wizard Behavior Hardening

### Fixed

- Fixed Worker URL validation so valid HTTPS Worker root URLs are not corrupted
- Domain input no longer silently truncates protocol/path mistakes without user confirmation
- Cloudflare is skipped with dependency-missing status whenever the VPS profile is unavailable
- Bot/Web setup failures are now reported as failed instead of configured/control-plane-only
- Full Wizard test mode now includes v1.7 productization and behavior hardening tests

### Improved

- Cert-mode menu now includes the letsencrypt placeholder as not recommended / future work
- Recovery commands are shown for Bot/Web failures
- Dynamic Full Wizard behavior tests cover URL cleaning, dependency skipping, and failed control-plane setup

### Safety

- Subscription URLs containing tokens are rejected without printing raw tokens
- Summary continues to avoid raw token and secret output
- Real VPS / Cloudflare validation remains a user-executed manual step

### Tests

- Added `tests/unified-full-wizard-behavior.sh`: behavior test for URL validation and dependency handling
- Updated `tests/unified-full-wizard-productization.sh`: cert-mode letsencrypt and Bot/Web failed state assertions
- Added v1.7 tests to installer All safe tests

## v1.7.0 — Clean Full Wizard Productization

### Added

- More productized Full Wizard stage flow with honest stage states
- Beginner-friendly recovery commands for failed VPS, Cloudflare, Bot, and Web stages
- Stronger input guidance for cert mode, domain, Worker URLs, and tokens
- Summary output that distinguishes verified, failed, skipped, dry-run, and control-plane-only states
- Cert-mode numbered menu for beginners (self-signed recommended)
- Domain validation (strips protocol, rejects empty/spaces)
- Cloudflare URL validation (strips query params, rejects token URLs)

### Fixed

- Full Wizard no longer misleads users after dependency failures
- Cloudflare stage is skipped when VPS profile dependency is missing
- Bot/Web setup clearly states when it is only a control-plane configuration
- rotate-render-only tests now use isolated temp directories to avoid concurrent test pollution

### Safety

- Token entry warnings are shown before collecting secrets
- Summary output avoids printing raw tokens
- Offline tests avoid shared fixed temp directories

### Tests

- Added `tests/unified-full-wizard-productization.sh`: input validation and stage dependency coverage
- Added `tests/unified-summary-honesty.sh`: summary honesty verification
- Added `tests/rotate-render-only-tempdir.sh`: temp dir isolation verification

## v1.6.5 — Noninteractive Test Timeout Guard Hotfix

### Fixed

- Added timeout guards to `unified-noninteractive-mode.sh`
- Added timeout guards to installer-level override tests in `unified-test-failure-propagation.sh`
- Prevented noninteractive test scripts from hanging indefinitely if installer regressions reappear
- Fixed render-only Xray Reality/Trojan config completeness in `rotate-render-only.sh` test
- Fixed per-protocol rotate-render-only fixtures so hy2/tuic/trojan rotations keep valid Reality/Trojan Xray configs
- Added pre-rotate and post-rotate fixture validation for every per-protocol rotation test
- Added JSON field validation for Reality/Trojan configs after rotation

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
