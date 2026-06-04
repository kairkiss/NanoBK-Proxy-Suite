# NanoBK v1.8 Operation Log Pilot Acceptance Checkpoint

## Purpose

This checkpoint closes the v1.8.20–v1.8.25 operation-log pilot phase.

**This is NOT a full deployment log rollout.**
**This does NOT prove real VPS deployment output is hidden.**
**This does NOT prove real Cloudflare deployment output is hidden.**
**This does NOT modify real deployment behavior.**

It records whether operation-log is ready for the next low-risk real command pilot.

## Baseline

- v1.7.27 is Full Wizard Productization Final.
- v1.8.0–v1.8.19 closed CLI static UI.
- v1.8.20–v1.8.25 tested operation-log only through safe library/test-mode paths.
- `installer/install.sh` remains high-risk.
- `run_cmd` / `run_critical_step` are not yet wrapped.

## What the pilot proved

- `oplog_redact` strips tokens, secrets, workers.dev, pages.dev, Bearer, password, private keys.
- `oplog_write` writes redacted log content.
- Log files use permission 600.
- `oplog_run_hidden` hides command output by default (hidden output).
- `NANOBK_VERBOSE=1` shows redacted command output.
- `oplog_hint_on_failure` shows log path.
- PLAIN/UI=0/CI no ANSI for operation-log output.
- install.sh can trigger a harmless pilot only with `NANOBK_OPLOG_PILOT=1` + `--mode test --defaults`.
- Pilot does not trigger in full dry-run; full dry-run unaffected.
- `NANOBK_OPLOG_TEST_WRAP=1` can wrap exactly one safe test path.
- Wrapped test failure propagation to non-zero test-mode result.
- no raw secrets in screen output or log files.
- Missing wrapped script fails safely.
- Full/vps/cloudflare/bot/web modes remain unchanged.
- Hidden output by default; verbose shows redacted output.

## What the pilot did NOT prove

- Real VPS deploy output hiding.
- Real Cloudflare deploy output hiding.
- Real healthcheck output hiding.
- Real cf verify output hiding.
- Rotate sync output hiding.
- Full `run_cmd` rollout.
- Full `run_critical_step` rollout.
- Log behavior under real network failure.
- Log behavior under sudo/systemd failure.
- Log behavior with real large command output.
- Log behavior with real Cloudflare Wrangler OAuth failure.
- Bot/Web UI logging.

## v1.8.20–v1.8.25 timeline

### v1.8.20

- Operation-log library pilot.
- Redaction.
- Hidden output.
- Verbose redacted output.
- Failure hint.
- Log chmod 600.

### v1.8.21

- Fixed UI=0 color boundary.
- Added UI=0 no-ANSI pilot test.

### v1.8.22

- Added install.sh harmless pilot hook.
- Opt-in only.
- Test mode only.

### v1.8.23

- Fixed defaults boundary.
- Pilot now requires `NANOBK_OPLOG_PILOT=1` + `DEFAULTS=1`.

### v1.8.24

- Added single test path wrapper.
- Wrapped `output-control-chars.sh` only.
- Still blocked because failure proof was insufficient.

### v1.8.25

- Added `NANOBK_OPLOG_TEST_WRAP_SCRIPT`.
- Proved verbose/plain/UI=0/CI wrapper paths really trigger.
- Proved controlled failing wrapped script returns non-zero test mode.
- Proved redaction in failure output and log.

## Current acceptance result

Operation-log pilot status:

**PASS FOR TEST-MODE PILOT**

**Not approved for full deployment rollout yet.**

Six specific acceptance points:

| Criterion | Result |
|-----------|--------|
| Redaction | PASS |
| Hidden output | PASS |
| Verbose redacted output | PASS |
| Failure propagation | PASS |
| Mode boundary | PASS |
| Real deployment wrapping | NOT STARTED |

## Risk assessment before real command pilot

Risk level increases sharply once operation-log touches `run_cmd` / `run_critical_step`.

Main risks:

- False success.
- Hidden failure.
- Lost recovery command.
- Broken `LAST_RUN_CMD_STATUS`.
- Broken dry-run / commands-only semantics.
- Secret leakage into log.
- User cannot debug real deployment.
- Real Cloudflare OAuth / Wrangler output behaves differently.
- Sudo/systemd output may be large or interactive.

## Next recommended step

**v1.8.27 — Operation Log One Low-risk Real Command Pilot**

Do not wrap VPS deploy.
Do not wrap Cloudflare deploy.
Do not wrap rotate sync.
Do not wrap Bot/Web operations.

### Candidate low-risk commands

**Option A, recommended:**

`bin/nanobk --version`

Reason:

- Harmless.
- No network.
- No sudo.
- No secrets.
- Predictable output.
- Easiest to verify failure/verbose/log behavior.

**Option B:**

`bin/nanobk status --json` in mock/test environment only.

Risk:

- May read local installed state.
- May include environment-derived fields.
- More complex.

**Option C:**

`installer/doctor.sh` in dry-run/mock mode only.

Risk:

- May read system state.
- Output may be larger.

**Recommendation:** Start with Option A only.

## Acceptance criteria for v1.8.27

If the next round does a real command pilot, it must satisfy:

- Explicit opt-in env var.
- Default user path unchanged.
- No full `run_cmd` rollout.
- No `run_critical_step` rollout.
- Wraps only one harmless command.
- Command failure returns non-zero.
- Log exists.
- Log chmod 600.
- No raw secrets.
- Verbose shows redacted output.
- PLAIN/UI=0/CI no ANSI.
- Full dry-run unaffected.
- All existing tests pass.

## Safety rules

- Do not paste real tokens.
- Do not `cat` env files.
- Do not share real VPS IP.
- Do not share real workers.dev subdomain.
- Do not share subscription URL.
- Bot/Web are control plane only.
- Dry-run is not real deployment.
- operation-log can hide output, but must never hide failure.

## v1.8.27 update

v1.8.27 implements the first one-command real pilot using `bin/nanobk --version`.

- Wraps only `bin/nanobk --version`.
- Opt-in only via `NANOBK_OPLOG_REAL_PILOT=1`.
- Only in `--mode test --defaults`.
- No deploy path wrapped.
- No `run_cmd`/`run_critical_step` rollout.
- Full dry-run unaffected.
- Real deployment output hiding still not proven.
- Next rollout requires explicit review.

## v1.8.28 update

v1.8.28 adds missing UI=0 and CI no-ANSI regression tests for the real command pilot. No installer behavior changed.

## v1.8.29 update

v1.8.29 adds the real command pilot acceptance checkpoint document and coverage test. No installer behavior changed.
