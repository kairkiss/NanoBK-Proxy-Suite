# NanoBK v1.8 Operation Log Pilot

## Purpose

This document records the v1.8.20 operation-log low-risk pilot.

**This is NOT a full deployment log rollout.**
**This does NOT prove real VPS/Cloudflare deploy output is hidden.**
**This only proves redacted operation-log pilot behavior.**

## Scope

### What is tested

- `oplog_redact` strips bot tokens, API tokens, passwords, secrets, workers.dev/pages.dev URLs.
- `oplog_write` writes redacted content to log file.
- `oplog_run_hidden` captures command output to log, hides from screen by default.
- `oplog_run` captures and shows redacted output on screen.
- `oplog_hint_on_failure` shows log path on failure.
- Log file permissions are 600.
- PLAIN/UI=0/CI modes produce no ANSI in pilot output.
- Verbose mode shows redacted output on screen.

### What is NOT tested

- Real VPS deployment output hiding.
- Real Cloudflare deploy output hiding.
- Real Worker verify output hiding.
- Real rotate sync output hiding.
- Full `run_cmd` / `run_critical_step` rollout.
- Real healthcheck / cf verify output hiding.

## Safety Rules

- Do NOT paste real tokens.
- Do NOT `cat` env files.
- Do NOT share real VPS IP / workers.dev / subscription URL.
- Log files use redacted content only.
- Test secrets are obvious fakes (e.g., `TOKEN=fake-token-for-redaction-test`).

## Redaction Patterns

The `oplog_redact` function strips:

| Pattern | Replacement |
|---------|-------------|
| `SUB_TOKEN=...` | `SUB_TOKEN=[REDACTED]` |
| `ADMIN_TOKEN=...` | `ADMIN_TOKEN=[REDACTED]` |
| `NANOB_TOKEN=...` | `NANOB_TOKEN=[REDACTED]` |
| `CF_API_TOKEN=...` | `CF_API_TOKEN=[REDACTED]` |
| `REALITY_PRIVATE_KEY=...` | `REALITY_PRIVATE_KEY=[REDACTED]` |
| `PRIVATE_KEY=...` | `PRIVATE_KEY=[REDACTED]` |
| `SECRET=...` (4+ chars) | `SECRET=[REDACTED]` |
| `TOKEN=...` (4+ chars) | `TOKEN=[REDACTED]` |
| `password=...` | `password=[REDACTED]` |
| `Authorization: Bearer ...` | `Authorization: Bearer [REDACTED]` |
| `*.workers.dev/...` | `[REDACTED_WORKERS_URL]` |
| `*.pages.dev/...` | `[REDACTED_PAGES_URL]` |
| `?token=...` / `&token=...` | `[REDACTED]` |
| Bot token pattern `123456789:ABC...` | `[REDACTED_BOT_TOKEN]` |

## Pilot Limitations

- Only tested with harmless echo/exit commands.
- Not integrated into real `run_cmd` or `run_critical_step`.
- Default user paths do not change behavior.
- `NANOBK_OPLOG_PILOT=1` is for test use only.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `NANOBK_VERBOSE=1` | Show redacted command output on screen |
| `NANOBK_OPLOG_DIR=...` | Override log directory for testing |
| `NANOBK_OPLOG_PILOT=1` | Reserved for future pilot integration |

## v1.8.21 UI=0 Boundary Fix

- v1.8.20 added operation-log pilot but missed explicit UI=0 no-color handling in `_oplog_has_color()` and tests.
- v1.8.21 adds `NANOBK_UI != "0"` to `_oplog_has_color()` color gating.
- Added UI=0 no-ANSI test to pilot test suite with log hint and secret safety assertions.
- PLAIN/CI no-ANSI behavior preserved.

## v1.8.22 Install.sh Pilot Hook

- `NANOBK_OPLOG_PILOT=1` can trigger a harmless operation-log pilot under `--mode test --defaults`.
- It does NOT run in full/vps/cloudflare/bot/web/doctor modes.
- It does NOT integrate with real `run_cmd` / `run_critical_step`.
- It does NOT prove real deployment output hiding.
- It proves install.sh can initialize operation-log and run a redacted harmless hidden-output command.
- Full rollout still requires explicit review approval.

## v1.8.23 Defaults Boundary Fix

- v1.8.22 introduced install.sh pilot hook triggered by `NANOBK_OPLOG_PILOT=1`.
- Audit found it also triggered for `--mode test` without `--defaults` when `NANOBK_OPLOG_PILOT=1`.
- v1.8.23 restricts pilot to `NANOBK_OPLOG_PILOT=1` + `DEFAULTS=1` (i.e., `--defaults` required).
- Added regression test: `NANOBK_OPLOG_PILOT=1 --mode test` without `--defaults` does NOT trigger pilot.

## v1.8.24 Single Test Path Wrapper Pilot

- `NANOBK_OPLOG_TEST_WRAP=1` wraps exactly one safe test script (`output-control-chars.sh`) under `--mode test --defaults`.
- Default test mode unchanged.
- Full/vps/cloudflare/bot/web modes unchanged.
- No real deploy command wrapped.
- No `run_cmd`/`run_critical_step` rollout.
- Full rollout still requires explicit review.

## v1.8.25 Test Wrapper Failure Proof

- v1.8.24 added single test path wrapper but audit found verbose/PLAIN tests used `NANOBK_TEST_OVERRIDE_SCRIPT`, which bypassed wrapper.
- v1.8.25 adds `NANOBK_OPLOG_TEST_WRAP_SCRIPT` test-only override for wrapped script.
- v1.8.25 verifies verbose/PLAIN/UI=0/CI wrapper paths really trigger.
- v1.8.25 verifies controlled failing wrapped script causes non-zero installer test result.
- v1.8.25 verifies failure output/log redaction (no raw secret on screen or in log).

## v1.8.27 One Low-risk Real Command Pilot

- Wraps only `bin/nanobk --version`.
- Opt-in only via `NANOBK_OPLOG_REAL_PILOT=1`.
- Only in `--mode test --defaults`.
- No deploy path wrapped.
- No `run_cmd`/`run_critical_step` rollout.
- Full dry-run unaffected.
- Real deployment output hiding still not proven.
- Next rollout requires explicit review.

## v1.8.28 Real Pilot UI=0/CI Test Fix

- v1.8.27 added the one-command real pilot.
- Audit found only PLAIN no-ANSI was tested in the real pilot section.
- v1.8.28 adds explicit UI=0 and CI no-ANSI coverage.

## v1.8.31 Help Command Pilot

- Wraps only `bin/nanobk --help`.
- Opt-in only via `NANOBK_OPLOG_HELP_PILOT=1`.
- Only in `--mode test --defaults`.
- Default test mode does not trigger.
- Full dry-run does not trigger.
- Non-default test mode does not trigger.
- No deployment path wrapped.
- No `run_cmd`/`run_critical_step` rollout.
- Hidden output by default.
- Verbose shows redacted help output.
- PLAIN/UI=0/CI no-ANSI.
- Failure propagation tested with `NANOBK_OPLOG_HELP_PILOT_CMD`.
- Real pilot + help pilot independence verified.
- `status --json` is still not wrapped.

## Next Step Before Full Rollout

Before integrating `oplog_run_hidden` into `run_cmd`:

1. Prove redaction covers all real command outputs.
2. Prove failure hints work with real VPS/CF commands.
3. Prove verbose mode is useful for debugging.
4. Get explicit review approval for `run_cmd` changes.
5. Start with one low-risk command path only.
