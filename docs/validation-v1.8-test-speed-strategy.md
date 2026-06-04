# NanoBK v1.8 Test Speed Strategy

## 1. Purpose

v1.8 operation-log tests became too slow because full installer test mode was repeatedly invoked.

This document defines focused fast tests, related regression tests, and full regression rules.

## 2. Why v1.8.31 was slow

- Operation-log pilot suite reached 190 assertions.
- Many tests invoked `installer/install.sh --mode test --defaults`.
- `--defaults` selects "All safe tests" (option 5).
- Each invocation runs the full offline test battery.
- Repeated "All safe tests" caused multi-hour runs.
- This is acceptable for checkpoint/full regression, but not for every small feature.

## 3. Fast test strategy

- Operation-log pilot hooks (`run_operation_log_pilot_check`, `run_operation_log_real_command_pilot`, `run_operation_log_help_command_pilot`) run before `NANOBK_TEST_OVERRIDE_SCRIPT` in `run_test_mode()`.
- Focused tests can use `NANOBK_TEST_OVERRIDE_SCRIPT` with a trivial exit-0 script to avoid "All safe tests".
- The pilot hooks execute normally; only the subsequent test battery is skipped.
- Use this for `--version` and `--help` pilots.
- Do not use it to prove test-wrapper behavior (which runs inside the test battery).
- Full regression still exists and must be run at checkpoints.

### v1.8.33 no-trigger speed polish

- v1.8.32 introduced fast tests but default no-trigger checks still invoked `--mode test --defaults` without override, which could enter All safe tests.
- v1.8.33 updates no-trigger checks to use `NANOBK_TEST_OVERRIDE_SCRIPT` as well.
- Version/help focused fast tests now avoid All safe tests in both no-trigger and trigger paths.
- Full regression remains available but full regression is not run by default.

## 4. Test tiers

### Tier 0 — Static review

- `git status`
- `git diff --stat`
- Version check (`bin/nanobk --version`)
- `install.sh` diff review
- No installer invocation needed.

### Tier 1 — Focused tests

- New/changed focused test only.
- Version fast test: `tests/unified-cli-operation-log-real-version-fast-v1.8.sh`
- Help fast test: `tests/unified-cli-operation-log-help-fast-v1.8.sh`
- Docs coverage tests: `tests/unified-cli-test-speed-strategy-v1.8.sh`
- Focused tests should run much faster than the full operation-log pilot suite.
- Exact runtime depends on host performance.

### Tier 2 — Related regression

- Operation-log pilot suite: `tests/unified-cli-operation-log-pilot-v1.8.sh`
- Checkpoint tests: `tests/unified-cli-operation-log-checkpoint-v1.8.sh`, `tests/unified-cli-operation-log-real-pilot-checkpoint-v1.8.sh`
- Mode boundary tests: `tests/unified-cli-mode-boundaries-v1.8.sh`
- May take 10-30 minutes.

### Tier 3 — Full regression

- All v1.8 tests.
- Full Wizard mock/state/resume.
- Summary honesty.
- `output-control-chars`.
- `nanobk-cli-dry-run`.
- May take 30-60+ minutes.

## 5. When to run full regression

Run full regression only when:

- Modifying `install.sh` behavior (not just version bump).
- Modifying `run_cmd`.
- Modifying `run_critical_step`.
- Modifying Summary status logic.
- Modifying resume/deploy logic.
- Modifying Cloudflare/rotate logic.
- Preparing checkpoint.
- Preparing tag.
- Before real VPS/Cloudflare validation.

## 6. When real VPS/CF tests are needed

### Not needed for

- Docs.
- Version bump.
- UI wording.
- `--version` pilot.
- `--help` pilot.
- Plain/UI=0/CI mode boundary.
- Operation-log library-only tests.

### Dirty VPS may be useful for

- Status reading.
- Existing deployment resume.
- Healthcheck display.
- Operation-log status pilot (future).

### Clean VPS needed for

- Fresh install.
- VPS deploy.
- Systemd service setup.
- Four protocol validation.

### Cloudflare real test needed for

- nanok/nanob deploy.
- KV.
- Service Binding.
- cf verify.
- rotate sync.

## 7. Policy for future agents

- Do not run full regression by default.
- first run focused tests
- Report "FAST PASS" with test count and time.
- Only run full regression if requested or if Tier 1 fails.
- if full regression is skipped, say so honestly
- operation-log can hide output, but must never hide failure.
