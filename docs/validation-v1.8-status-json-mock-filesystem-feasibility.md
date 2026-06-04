# NanoBK v1.8 Status JSON Mock Filesystem Feasibility Gate

## 1. Purpose

This document decides whether a future status JSON mock filesystem prototype can safely run the real `bin/nanobk --json status` code path without reading real installed VPS/Cloudflare state.

It does not implement the prototype.

It does not add a status pilot.

It does not approve dirty VPS status wrapping.

## 2. Current accepted baseline

- v1.8.34 status JSON planning.
- v1.8.35 sanitized fixture prototype.
- v1.8.36 fixture test polish.
- v1.8.37 mock filesystem root design.
- real `bin/nanobk --json status` remains unwrapped.
- dirty VPS status remains not approved.
- run_cmd / run_critical_step remain unwrapped.

## 3. Feasibility question

Can we safely run:

```bash
NANOBK_REPO_DIR=<tmp_root/repo> bin/nanobk --json status --config-dir <tmp_root/config>
```

with a PATH systemctl shim and sanitized mock files, without modifying production code?

## 4. Code path gating analysis

Inspection source: `bin/nanobk` at v1.8.37 baseline before this version bump; the inspected status path is unchanged in this v1.8.38 feasibility gate.

- `parse_global_args()` handles `--json` globally and sets `JSON_OUT=1` before dispatch.
- `main()` calls `resolve_repo_dir()` before command dispatch.
- `resolve_repo_dir()` first returns if `REPO_DIR` is already set.
- `resolve_repo_dir()` next respects `NANOBK_REPO_DIR` and assigns `REPO_DIR="$NANOBK_REPO_DIR"`.
- If `NANOBK_REPO_DIR` is set to a mock repo, it should avoid `/etc/nanobk/config.env` repo resolution because the function returns before checking `${CONFIG_DIR}/config.env`.
- `cmd_status()` parses `--config-dir` later, after repo resolution.
- `cmd_status()` reads `<tmp/config>/config.env` when invoked as `status --config-dir <tmp/config>`.
- `cmd_status()` reads `<tmp/config>/profile.current.json` through `profile_file="${config_dir}/profile.current.json"`.
- `cmd_status()` checks `<tmp/config>/secrets.private.env` through `secrets_file="${config_dir}/secrets.private.env"`.
- Cloudflare nanok candidates include mock repo and mock config, then `/root/.nanok-cf-admin.env`: `${REPO_DIR}/.cloudflare.local.env`, `${config_dir}/cloudflare.local.env`, `/root/.nanok-cf-admin.env`.
- nanob candidates include mock repo and mock config: `${REPO_DIR}/.nanob.local.env`, `${config_dir}/nanob.local.env`.
- `systemctl is-active` is resolved via PATH because `cmd_status()` uses `command -v systemctl` and then calls `systemctl is-active ...`.
- A test-only PATH systemctl shim can intercept service checks if its directory is prepended to PATH.
- Current code still has a direct `/root/.nanok-cf-admin.env` existence check for `adminEnvExists`.
- Therefore Route A is only feasible if tests accept root admin env as absent or run in an environment where `/root/.nanok-cf-admin.env` does not exist, or if source-level/output guards prove no sensitive data is exposed.
- Because the current code still performs a direct root path existence check, Route A cannot strictly prove "no real `/root/.nanok-cf-admin.env` touch" without extra isolation or a code hook.

## 5. Route A feasibility verdict

Verdict: FEASIBLE ONLY AS PLAN, NOT RUNTIME

Route A can be reasoned about from source inspection, and most path controls are promising:

- `NANOBK_REPO_DIR=<tmp_root/repo>` should short-circuit `resolve_repo_dir()` before `/etc/nanobk/config.env`.
- `--config-dir <tmp_root/config>` should direct status-local config/profile/secrets reads to mock files.
- mock repo/config Cloudflare env candidates precede the root candidate.
- PATH systemctl shim should intercept service-state checks.

However, it is not yet safe to run as a runtime prototype in this cycle because `cmd_status()` still directly checks `/root/.nanok-cf-admin.env` for `adminEnvExists`. That check does not read token content, but it can still touch a real root path and can leak a boolean installed-state signal if a dirty host has the file.

Answer to the core questions:

- Can real status code path read mock config/profile/env without `cmd_status` changes? Source inspection says yes for status-local files when `--config-dir <tmp_root/config>` is passed.
- Is `NANOBK_REPO_DIR` enough to stop `resolve_repo_dir()` from reading real repo config? Source inspection says yes, because it returns before `${CONFIG_DIR}/config.env`.
- Is `--config-dir <tmp/config>` enough for `cmd_status()` config/profile/secrets? Source inspection says yes for those three path families.
- Do Cloudflare env candidates prioritize mock repo/config? Source inspection says yes for nanok and nanob candidates, but direct root admin existence check remains.
- Does direct `/root/.nanok-cf-admin.env` checking create unacceptable risk? Yes for a strict "no real root path touch" runtime proof without extra isolation.
- Is PATH systemctl shim enough to stop real systemd status reads? Source inspection says yes if the shim is first in PATH and handles `is-active`.
- Can a future prototype test safely run locally/CI? Only after it either proves the root-admin check cannot touch real state in that environment or introduces an approved minimal test isolation hook.
- Should v1.8.39 implement runtime prototype? Not yet. v1.8.39 should continue with mock isolation hook planning unless explicit approval changes the boundary.

## 6. Required mock files for future prototype

Future v1.8.39 or later prototype would need these files if runtime isolation is approved.

`tmp_root/config/config.env`:

- sanitized `NANOBK_DOMAIN`.
- sanitized `NANOBK_VPS_IP`.
- `NANOBK_GEO_LABEL`.
- sanitized `REALITY_SERVERNAME`.
- `NANOBK_REPO_DIR=<tmp_root/repo>` or rely on env `NANOBK_REPO_DIR`.
- no raw token.
- no raw URL.

`tmp_root/config/profile.current.json`:

- `updatedAt` placeholder.
- `hy2` / `tuic` / `reality` / `trojan` sections.
- no Reality private key.
- no raw URL/IP/token.

`tmp_root/config/secrets.private.env`:

- exists.
- chmod 600.
- placeholder only.
- never printed.

`tmp_root/repo/.cloudflare.local.env`:

- sanitized worker.
- sanitized route fields or placeholder.
- no raw token.
- no workers.dev.
- no http/https raw URL unless placeholder policy is explicit.

`tmp_root/repo/.nanob.local.env`:

- sanitized worker/path.
- no raw token.
- no raw URL.

`tmp_root/bin/systemctl` shim:

- handles `is-active`.
- returns fixed sanitized status.
- logs only safe marker if needed.
- never calls real systemctl.

## 7. Required runtime guards for future prototype

Future v1.8.39 prototype must verify:

- stdout valid JSON.
- operation-log hidden output by default.
- verbose output sanitized.
- log JSON valid or extracted JSON valid.
- no ANSI in PLAIN/UI=0/CI.
- no `TOKEN=`.
- no `SECRET=`.
- no raw IPv4.
- no workers.dev.
- no pages.dev.
- no http://.
- no https://.
- no `/etc/nanobk`.
- no `/root/`.
- no real repo path.
- no real user home path.
- no raw token fingerprint.
- no Reality private key.
- systemctl shim used.
- real systemctl not called.
- full dry-run unaffected.
- failure rc non-zero.
- no fake success.

## 8. How to prove no real path read

Recommended proof levels:

Level 1 - source inspection:

- confirm `NANOBK_REPO_DIR` short-circuits `resolve_repo_dir`.
- confirm `--config-dir` controls status-local config/profile/secrets.
- confirm mock repo/config candidates precede root candidate.
- confirm PATH shim catches systemctl.

Level 2 - output/log gates:

- forbidden patterns.
- sentinel values.
- mock-only values present.
- real path patterns absent.

Level 3 - optional later:

- strace/lsof/container only if needed.
- not required for v1.8.39 first prototype unless risk remains.

Current gate result: Level 1 still finds a direct `/root/.nanok-cf-admin.env` existence check, so runtime proof should not proceed in this cycle.

## 9. v1.8.39 recommendation

Recommended next version:

v1.8.39 - Status JSON Mock Isolation Hook Planning

Scope:

- design minimal test-only hook.
- no runtime prototype yet.
- no dirty VPS.
- decide how to handle direct `/root/.nanok-cf-admin.env` existence checks without changing production behavior.
- keep operation-log status wrapper out of scope.
- keep `run_cmd` rollout out of scope.
- keep `run_critical_step` rollout out of scope.

## 10. Still forbidden

- Do NOT add NANOBK_OPLOG_STATUS_PILOT yet.
- Do NOT wrap real installed status on dirty VPS.
- Do NOT read `/etc/nanobk`.
- Do NOT read `/root/.nanok-cf-admin.env`.
- Do NOT read real repo env.
- Do NOT modify cmd_status without explicit approval.
- Do NOT modify resolve_repo_dir without explicit approval.
- Do NOT wrap VPS deploy.
- Do NOT wrap Cloudflare deploy.
- Do NOT wrap rotate sync.
- Do NOT wrap real healthcheck.
- Do NOT wrap real cf verify.
- Do NOT wrap Bot/Web operations.
- Do NOT full-rollout run_cmd.
- Do NOT full-rollout run_critical_step.
- Do NOT expose raw status JSON in chat.
- do not expose raw status JSON in chat.
