# NanoBK v1.8 Status Mock Oplog Prototype Checkpoint

## 1. Purpose

This checkpoint records the accepted v1.8.34–v1.8.42 status JSON mock/oplog proof chain.

It does not approve dirty VPS status.
It does not approve production status wrapper.
It does not add NANOBK_OPLOG_STATUS_PILOT.
It does not change deployment behavior.

## 2. Accepted proof chain

### v1.8.34 — Status JSON Mock/Sanitized Planning

- Correct command is `bin/nanobk --json status`.
- Not `bin/nanobk status --json`.
- Status can output domain, VPS IP, route URL, subscription path, token fingerprint.
- Dirty VPS status is high-risk and must not be wrapped directly.

### v1.8.35 — Status JSON Sanitized Fixture Prototype

- Sanitized static status JSON fixture created.
- operation-log can capture fixture output.
- Default mode hides JSON from screen.
- Verbose mode shows sanitized JSON.
- PLAIN/UI=0/CI no ANSI boundaries verified.
- Failure propagation with redaction verified.

### v1.8.36 — Status JSON Fixture Test Polish

- Fixed-string grep (`grep -Fq`) prevents regex interpretation of `[REDACTED_...]`.
- Here-string checks replace `echo | grep` patterns.
- `register_cleanup` replaces multiple `trap` overrides.
- Source guard avoids self-referencing false positives.

### v1.8.37 — Status JSON Mock Filesystem Root Design

- `--config-dir` alone is insufficient because `resolve_repo_dir()` runs before `cmd_status()` parses `--config-dir`.
- Mock config/repo/root layout designed.
- Path isolation requirements documented.
- systemctl/service status strategy documented.

### v1.8.38 — Status JSON Mock Filesystem Feasibility Gate

- `NANOBK_REPO_DIR` + `--config-dir` + PATH systemctl shim evaluated.
- Verdict: FEASIBLE ONLY AS PLAN, NOT RUNTIME.
- Blocker: direct `/root/.nanok-cf-admin.env` existence check in `cmd_status()`.

### v1.8.39 — Status JSON Mock Isolation Hook Planning

- Compared broad `NANOBK_STATUS_MOCK_ROOT` vs narrow `NANOBK_STATUS_ADMIN_ENV_PATH`.
- Recommended `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` as minimal test-only hook.
- Hook name is explicitly test-scoped.

### v1.8.40 — Status JSON Admin Env Path Test Hook

- `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` implemented in `cmd_status()`.
- Only affects admin env existence check (`cf_admin_env_exists`).
- Default `/root/.nanok-cf-admin.env` behavior unchanged.
- Mock false/true case tests pass.
- systemctl PATH shim test passes.
- No status wrapper added.

### v1.8.41 — Status JSON Mock Filesystem Operation-Log Prototype

- Real `bin/nanobk --json status --config-dir <tmp/config>` runs against mock filesystem.
- Output captured via `oplog_run_hidden`.
- Default mode hides JSON (screen shows only Log: path).
- Verbose mode shows sanitized JSON.
- Log JSON validity verified.
- PLAIN/UI=0/CI no ANSI verified.
- systemctl shim proof (is-active logged).
- Failure propagation with redaction verified.
- Issue found: full log header recorded real repo absolute path.

### v1.8.42 — Status Mock Oplog Command Path Polish

- Runner uses `cd "$REPO_DIR"` then `bash bin/nanobk` (relative path).
- Operation-log command header no longer records real repo absolute path.
- Full log checks now include real HOME and real repo path absence.
- JSON block remains clean and valid.
- Source guard verifies relative path usage.

## 3. Current accepted status

PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE

Current status:

- Mock filesystem status code path can be captured by operation-log.
- default output can hide JSON.
- verbose output can show sanitized JSON.
- log JSON can remain valid.
- PLAIN/UI=0/CI can remain ANSI-free.
- systemctl can be shimmed via PATH.
- failure propagation works with redaction.
- Full log can avoid real HOME/repo path after v1.8.42.
- dirty VPS status remains unapproved.

## 4. What is still NOT approved

- Dirty VPS status wrapping.
- Production status wrapper.
- NANOBK_OPLOG_STATUS_PILOT.
- run_cmd rollout.
- run_critical_step rollout.
- Real healthcheck wrapping.
- Real cf verify wrapping.
- Rotate sync wrapping.
- Bot/Web operation wrapping.
- Raw status JSON sharing in chat.
- Reading real /etc/nanobk.
- Reading real /root/.nanok-cf-admin.env.
- Reading real repo env files.

## 5. Security proof summary

Current mock proof verifies:

- no TOKEN=
- no SECRET=
- no ADMIN_TOKEN
- no SUB_TOKEN
- no NANOB_TOKEN
- no REALITY_PRIVATE_KEY
- no raw IPv4
- no workers.dev
- no pages.dev
- no http://
- no https://
- no /etc/nanobk
- no /root/
- no real HOME
- no real repo absolute path
- no env content printed
- log chmod 600
- failure secret redacted

## 6. Testing strategy status

- Focused tests are preferred for v1.8 operation-log work.
- full operation-log pilot suite is not required every cycle.
- Full suite should be run only before a major rollout, before tagging, or when operation-log library changes.
- This checkpoint does not require real VPS/Cloudflare tests.

## 7. Recommended next options

### Option A — Status Pilot Gate Planning

Plan what would be required before adding NANOBK_OPLOG_STATUS_PILOT.

Pros:

- Continues status logging path.

Risks:

- Closer to production wrapper.
- Must avoid dirty VPS leakage.

### Option B — Manual mock-status local revalidation

Run only mock-root status oplog tests manually on a clean/dev VPS or local environment.

Pros:

- More confidence.
- No production change.

Risks:

- Still not dirty VPS proof.

### Option C — Pause status path and return to broader v1.8 checkpoint

Create v1.8 CLI/operation-log summary checkpoint and decide whether v1.9 should start Bot/Web polish.

Pros:

- Avoids over-engineering status.
- Lets project return to product roadmap.

Risks:

- Status path remains incomplete in v1.8.

Recommended next step: Option C.

Status mock oplog has already proven enough. Continuing toward production status wrapper increases risk with limited benefit. v1.8's main goal is CLI UI + operation-log groundwork, and a formal status wrapper does not need to be completed in v1.8.

## 8. Possible v1.8.44 scope

If Option C:

v1.8.44 — v1.8 CLI and Operation Log Checkpoint

Scope:

- Summarize v1.8 UI accomplishments.
- Summarize operation-log accomplishments.
- Summarize status mock/oplog proof chain.
- Document what remains for v1.9.
- No code behavior changes.
- No new wrapper.

If Option A:

v1.8.44 — Status Pilot Gate Planning

Scope:

- Plan NANOBK_OPLOG_STATUS_PILOT.
- No implementation.
- No dirty VPS.
- No wrapper yet.

## 9. Still forbidden

Do NOT add NANOBK_OPLOG_STATUS_PILOT yet.
Do NOT wrap dirty VPS status.
Do NOT read /etc/nanobk.
Do NOT read /root/.nanok-cf-admin.env.
Do NOT read real repo env.
Do NOT expose raw status JSON in chat.
Do NOT full-rollout run_cmd.
Do NOT full-rollout run_critical_step.
Do NOT wrap deploy/healthcheck/cf verify/rotate/Bot/Web yet.

## 10. v1.8.44 Broader Checkpoint

v1.8.44 broadens checkpoint from status mock/oplog to whole v1.8 CLI/operation-log groundwork.

- no status pilot.
- no dirty VPS.
- no production wrapper.
- recommended next step is closeout decision (v1.8.45).
