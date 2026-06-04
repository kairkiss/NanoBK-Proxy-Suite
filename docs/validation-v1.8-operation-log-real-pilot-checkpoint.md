# NanoBK v1.8 Operation Log Real Command Pilot Checkpoint

## Purpose

This checkpoint closes the v1.8.27–v1.8.28 one-command real pilot phase.

It proves operation-log can wrap one harmless real command:

`bin/nanobk --version`

**It does NOT prove real deployment output hiding.**
**It does NOT approve full run_cmd or run_critical_step rollout.**
**It does NOT modify real deployment behavior.**

## Baseline

- v1.7.27 is Full Wizard Productization Final.
- v1.8.0–v1.8.19 closed CLI static UI.
- v1.8.20–v1.8.26 closed operation-log test-mode pilot.
- v1.8.27–v1.8.28 tested exactly one harmless real command.
- `installer/install.sh` remains high-risk.
- `run_cmd` / `run_critical_step` remain unwrapped.

## What v1.8.27 proved

- `NANOBK_OPLOG_REAL_PILOT=1` + `--mode test --defaults` can trigger real command pilot.
- Default test mode does not trigger.
- Non-default test mode does not trigger.
- Full dry-run does not trigger.
- Wrapped command is only `bash bin/nanobk --version`.
- Default screen output hides raw command output.
- Verbose mode shows redacted command output.
- Log file is generated.
- Log chmod 600.
- Log contains version output.
- Fake failure command returns non-zero.
- Fake failure secret is redacted from screen and log.
- No VPS deploy / Cloudflare deploy / rotate / Bot/Web command wrapped.

## What v1.8.28 fixed

- Audit found v1.8.27 only had PLAIN no-ANSI real pilot test.
- v1.8.28 added UI=0 real pilot no-ANSI test.
- v1.8.28 added CI real pilot no-ANSI test.
- install.sh behavior did not change.
- Real pilot implementation remained stable.

## Current acceptance result

Operation-log real command pilot status:

**PASS FOR ONE HARMLESS REAL COMMAND**

**Not approved for deployment command wrapping.**
**Not approved for full run_cmd/run_critical_step rollout.**

| Acceptance point | Result |
|------------------|--------|
| Trigger boundary | PASS |
| Hidden output | PASS |
| Verbose redacted output | PASS |
| Failure propagation | PASS |
| PLAIN/UI=0/CI mode boundary | PASS |
| Full dry-run unaffected | PASS |
| Real deployment wrapping | NOT STARTED |

## What the real pilot did NOT prove

- Real VPS deploy output hiding.
- Real Cloudflare deploy output hiding.
- Real healthcheck output hiding.
- Real cf verify output hiding.
- Rotate sync output hiding.
- Sudo/systemd failure logging.
- Network failure logging.
- Wrangler OAuth failure logging.
- Large-output command handling.
- Interactive command handling.
- Command timeout handling.
- Full `run_cmd` rollout.
- Full `run_critical_step` rollout.
- Bot/Web logging.

## Risk assessment before second real command

The next command must still be low-risk.

Risk increases if the command:

- Reads installed profile.
- Reads env files.
- Reads Cloudflare admin env.
- Calls network.
- Calls systemctl.
- Calls sudo.
- Invokes wrangler.
- May output URLs.
- May output subscription paths.
- May output token fingerprints.
- May block waiting for user input.

## Candidate second real command

### Option A

`bash bin/nanobk status --json`

Pros:

- Closer to real user value.
- Exercises nanobk CLI status output.
- Useful for future Bot/Web control plane.

Risks:

- May read local installed state.
- May include environment-derived fields.
- May include Cloudflare status / URL-like values.
- Needs strong redaction assertions.
- Should be tested only in mock or sanitized environment first.

### Option B

`bash bin/nanobk --help`

Pros:

- Harmless.
- No network.
- No secrets.
- More complex than `--version` but still safe.

Risks:

- Lower user value than status.
- Mostly just text output.

### Option C

`bash bin/nanobk status --json` with forced test/mock env

Pros:

- Closer to real status without real env.
- Safer than reading dirty VPS state.

Risks:

- Requires understanding status mock hooks.
- Must not accidentally read `/etc/nanobk` or real env.

### Recommendation

Next recommended version:

**v1.8.30 — Operation Log Second Real Command Planning**

Do not implement the second command directly unless explicit approval is given.

If implementation is approved later, start with either:

1. `bin/nanobk --help`, or
2. `bin/nanobk status --json` only under a mock/sanitized test environment.

Do NOT wrap real installed status on a dirty VPS yet.

## Gates before wrapping status

If the future choice is `status --json`, it must satisfy:

- Explicit opt-in env var.
- Default path unchanged.
- No full `run_cmd` rollout.
- No `run_critical_step` rollout.
- Mock/sanitized status source.
- No real env file reads in tests.
- No raw VPS IP.
- No raw workers.dev.
- No raw subscription URL.
- No `TOKEN=` / `SECRET=`.
- JSON remains valid if captured in log.
- Failure propagation non-zero.
- PLAIN/UI=0/CI no ANSI.
- Verbose redacted output.
- Full dry-run unaffected.
- All existing tests pass.

## Safety rules

- Do not paste real tokens.
- Do not cat env files.
- Do not share real VPS IP.
- Do not share real workers.dev subdomain.
- Do not share subscription URL.
- Bot/Web are control plane only.
- Dry-run is not real deployment.
- operation-log can hide output, but must never hide failure.
- One harmless command pilot does not approve deployment wrapping.
