# Changelog

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
