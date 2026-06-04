# NanoBK v1.8 Status JSON Mock Isolation Hook Planning

## 1. Purpose

This document plans the minimal test-only isolation hook needed before a status JSON mock filesystem runtime prototype can safely run the real `bin/nanobk --json status` code path.

It does not implement the hook.

It does not run real status.

It does not add a status pilot.

It does not approve dirty VPS status wrapping.

## 2. Current accepted baseline

- v1.8.34 status JSON planning.
- v1.8.35 sanitized fixture prototype.
- v1.8.36 fixture test polish.
- v1.8.37 mock filesystem root design.
- v1.8.38 feasibility gate.
- v1.8.38 verdict: FEASIBLE ONLY AS PLAN, NOT RUNTIME.
- blocker: direct `/root/.nanok-cf-admin.env` existence check.
- run_cmd / run_critical_step remain unwrapped.
- real status remains unwrapped.

## 3. Current blocker

Current `cmd_status()` directly checks `/root/.nanok-cf-admin.env`.

This is not token content reading, but it can still touch real root filesystem state and leak whether a dirty host has NanoBK admin env installed.

Therefore runtime proof cannot claim "no real `/root/` path touched" until this path is isolated.

The current source also lists `/root/.nanok-cf-admin.env` as the final nanok env candidate after mock repo/config candidates. The immediate blocker for the v1.8.38 Route A proof is the separate `adminEnvExists` check, because it always tests the real root path.

## 4. Candidate hooks

### Option A - NANOBK_STATUS_MOCK_ROOT

Description:

A broad test-only root override used to derive root/admin paths.

Pros:

- unified.
- future expandable.
- can model root paths under `tmp_root/root`.

Cons:

- larger code change.
- touches more path logic.
- harder to audit.
- may encourage broad mock behavior in production code path.

### Option B - NANOBK_STATUS_ADMIN_ENV_PATH

Description:

A narrow test-only override for the admin env existence check path only.

Default remains:

```text
/root/.nanok-cf-admin.env
```

When env is set:

```bash
NANOBK_STATUS_ADMIN_ENV_PATH=<tmp_root/root/.nanok-cf-admin.env>
```

`cmd_status()` checks that path instead.

Pros:

- minimal.
- localized.
- preserves production default.
- easy to test.
- solves current blocker.
- lower risk than Option A.

Cons:

- narrow.
- may need future hook if more hardcoded root paths appear.

## 5. Recommended hook

Recommended final variable:

```bash
NANOBK_STATUS_TEST_ADMIN_ENV_PATH
```

This is preferred over `NANOBK_STATUS_ADMIN_ENV_PATH` because the name is explicitly test-scoped. It includes `STATUS`, `TEST`, and `ADMIN_ENV_PATH`, making the intended surface narrow and avoiding the appearance of a normal user configuration option.

Recommendation rationale:

- name is clearly status-scoped.
- name is clearly test-scoped.
- name does not look like a production user setting.
- it should not appear in normal user docs.
- it should only be set by tests.
- it addresses the current hardcoded root admin env blocker without changing `resolve_repo_dir()`, `--config-dir`, or status JSON schema.

## 6. Proposed implementation sketch

This is a sketch only. Do not implement in this planning checkpoint.

Current conceptual behavior:

```bash
cf_admin_env_exists="false"
if [[ -f "/root/.nanok-cf-admin.env" ]]; then
  cf_admin_env_exists="true"
fi
```

Future test-only sketch:

```bash
status_admin_env_path="${NANOBK_STATUS_TEST_ADMIN_ENV_PATH:-/root/.nanok-cf-admin.env}"
cf_admin_env_exists="false"
if [[ -f "$status_admin_env_path" ]]; then
  cf_admin_env_exists="true"
fi
```

Rules:

- Default behavior unchanged.
- Only path existence check changes.
- Do not source admin env content.
- Do not print path.
- Do not add token reading.
- Do not change JSON field name.
- Do not change normal status output.
- Only tests set the env var.
- Production docs should not advertise it.

## 7. Required future tests for hook implementation

Future hook implementation tests must cover:

- default behavior source guard.
- with env override, `cmd_status()` checks mock path.
- no `/root/.nanok-cf-admin.env` appears in stdout/log.
- no `/etc/nanobk`.
- JSON valid.
- `adminEnvExists` reflects mock file presence.
- when mock admin env absent, `adminEnvExists=false`.
- when mock admin env present, `adminEnvExists=true`.
- no env content printed.
- no `TOKEN=` / `SECRET=`.
- no raw path output.
- no dirty VPS.
- no status pilot.
- no run_cmd rollout.
- no run_critical_step rollout.

## 8. Relationship to future mock filesystem prototype

Once this hook is implemented and tested, future mock filesystem prototype can use:

- `NANOBK_REPO_DIR=<tmp_root/repo>`.
- `bin/nanobk --json status --config-dir <tmp_root/config>`.
- `NANOBK_STATUS_TEST_ADMIN_ENV_PATH=<tmp_root/root/.nanok-cf-admin.env>`.
- PATH systemctl shim.

Then future prototype can verify:

- no real `/root/`.
- no real `/etc/nanobk`.
- mock-only sentinel values.
- JSON valid.
- operation-log hidden/verbose behavior.
- no dirty VPS.

## 9. Risk assessment

Risk level:

Low to Medium, because it changes `cmd_status()` path selection but only under a test-scoped env var.

Risk controls:

- env var name includes `STATUS` and `TEST`.
- default path unchanged.
- no content read.
- no output path.
- tests prove default behavior still references original conceptual path only in source, not output.
- tests prove override path works.
- code review required.

Option B is preferred over Option A because it fixes the current blocker with a minimal, localized test-only override. Option A should remain deferred unless future status work finds multiple hardcoded root/system paths that cannot be isolated individually.

## 10. v1.8.40 recommendation

Recommended next version:

v1.8.40 - Status JSON Admin Env Path Test Hook

Scope:

- implement only `NANOBK_STATUS_TEST_ADMIN_ENV_PATH`.
- no operation-log status wrapper.
- no dirty VPS status.
- no deploy.
- no run_cmd rollout.
- no run_critical_step rollout.
- focused tests only.
- update docs.

Do not proceed directly to full mock filesystem runtime in v1.8.40. The admin env path hook should be implemented and reviewed first.

## 11. Still forbidden

- Do NOT add NANOBK_OPLOG_STATUS_PILOT yet.
- Do NOT wrap real installed status on dirty VPS.
- Do NOT read `/etc/nanobk`.
- Do NOT read `/root/.nanok-cf-admin.env` in tests.
- Do NOT read real repo env.
- Do NOT modify resolve_repo_dir.
- Do NOT change status JSON schema.
- Do NOT wrap VPS deploy.
- Do NOT wrap Cloudflare deploy.
- Do NOT wrap rotate sync.
- Do NOT wrap real healthcheck.
- Do NOT wrap real cf verify.
- Do NOT wrap Bot/Web operations.
- Do NOT full-rollout run_cmd.
- Do NOT full-rollout run_critical_step.
- Do NOT expose raw status JSON in chat.

## 12. v1.8.40 Admin Env Path Test Hook

v1.8.40 implements NANOBK_STATUS_TEST_ADMIN_ENV_PATH.

### What changed

- `cmd_status()` admin env existence check now reads path from `status_admin_env_path`.
- `status_admin_env_path` defaults to `/root/.nanok-cf-admin.env` when `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` is unset.
- When `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` is set, `cmd_status()` checks that path instead.
- only affects admin env existence check (`cf_admin_env_exists`).
- Does not source admin env content (no content sourced).
- Does not print the path (no path printed).
- Does not change JSON field name.
- Does not change `adminEnvExists` semantics.
- Does not change token fingerprint logic.
- Does not change `resolve_repo_dir()`.
- Does not change `--config-dir` parsing.
- No status wrapper added (no status wrapper).

### Tests

- Source guard verifies `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` and `/root/.nanok-cf-admin.env` in `bin/nanobk`.
- Mock false case: hook set, no file at mock path → `adminEnvExists=false`.
- Mock true case: hook set, file at mock path → `adminEnvExists=true`.
- No real paths, no secrets, no ANSI in output.
- systemctl PATH shim verified.
- JSON validity verified.
- Full dry-run unaffected.

### What was NOT done

- No `NANOBK_OPLOG_STATUS_PILOT`.
- No status operation-log wrapper.
- No dirty VPS status.
- No `resolve_repo_dir` changes.
- No status JSON schema changes.
- No `run_cmd`/`run_critical_step` rollout.

### Next step

Next step can be mock filesystem status prototype with operation-log capture only after this hook passes review.

## 13. v1.8.41 Mock Filesystem Operation-Log Prototype

v1.8.41 uses NANOBK_STATUS_TEST_ADMIN_ENV_PATH from v1.8.40.

### What was done

- Runs real status code path only against mock config/repo/admin env path.
- Captures output with operation-log (`oplog_run_hidden`).
- Default mode hides JSON (screen shows only Log: path).
- Verbose mode shows sanitized JSON (no secrets, no real paths).
- PLAIN/UI=0/CI modes verified no ANSI.
- systemctl PATH shim verified (log proves `is-active` called).
- failure propagation verified (non-zero rc, raw secret redacted, exit code logged).
- JSON validity verified in log extraction.
- No dirty VPS status.
- No NANOBK_OPLOG_STATUS_PILOT.
- No production status wrapper added.
- No run_cmd/run_critical_step rollout.

### What was NOT done

- No `NANOBK_OPLOG_STATUS_PILOT` added.
- No production status wrapper.
- No dirty VPS status.
- No `cmd_status` schema changes.
- No `resolve_repo_dir` changes.

### Next step

Next step can be status mock prototype checkpoint or carefully planned status pilot gate.

## 14. v1.8.42 Command Path Polish

v1.8.42 keeps v1.8.41 mock status operation-log prototype.

### What changed

- Runner now `cd`s into repo and calls `bash bin/nanobk` (relative path).
- Operation-log command header no longer records real repo absolute path.
- Full log checks now include real HOME and real repo path absence.
- JSON block remains clean.
- Source guard verifies relative path usage in runners.
- No dirty VPS status.
- No NANOBK_OPLOG_STATUS_PILOT.
- No status wrapper.
- No cmd_status/schema/resolve_repo_dir change.
