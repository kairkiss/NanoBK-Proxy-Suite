# NanoBK v1.8 Status JSON Mock Filesystem Root Design

## 1. Purpose

This document designs a future mock filesystem root strategy for testing `bin/nanobk --json status` with operation-log without reading or leaking real installed VPS/Cloudflare state.

It does not implement the mock runner.

It does not run real status.

It does not approve dirty VPS status wrapping.

## 2. Current accepted baseline

- v1.8.34 planned status JSON mock/sanitized strategy.
- v1.8.35 added static sanitized status JSON fixture.
- v1.8.36 polished fixture tests.
- current fixture prototype uses `cat` fixture.
- real `bin/nanobk --json status` remains unwrapped.
- dirty VPS status remains out of scope.
- run_cmd / run_critical_step remain unwrapped.

## 3. Correct status command and current risk

Correct command:

```bash
bin/nanobk --json status
```

Not:

```bash
bin/nanobk status --json
```

Current risk:

- status may read real `/etc/nanobk/config.env`.
- status may read real `/etc/nanobk/profile.current.json`.
- status may check `secrets.private.env` existence/mode.
- status may inspect systemd service state.
- status may read repo/root Cloudflare env candidate paths.
- status may output domain/IP/route/sub path/token fingerprints.
- status must not be run on dirty VPS and pasted raw.

## 4. Current code path inspection

Inspection source: `bin/nanobk` at current v1.8.36 baseline.

- `cmd_status` location: `cmd_status()` starts in `bin/nanobk` at the status section.
- `--json` global parsing: `parse_global_args()` handles `--json` before command dispatch and sets `JSON_OUT=1`.
- `--config-dir` handling: `cmd_status()` accepts `status --config-dir PATH` and assigns a local `config_dir`.
- `CONFIG_DIR` default: global `CONFIG_DIR="/etc/nanobk"`.
- `resolve_repo_dir()` behavior: `main()` calls `resolve_repo_dir` before dispatching `cmd_status`. If `REPO_DIR` is empty, it checks `NANOBK_REPO_DIR`, then `${CONFIG_DIR}/config.env` for `NANOBK_REPO_DIR`, then `/opt/NanoBK-Proxy-Suite`, then `${HOME}/NanoBK-Proxy-Suite`, then the script-relative repository.
- Current `--config-dir` timing: because `status --config-dir PATH` is parsed inside `cmd_status()`, it does not affect `resolve_repo_dir()` before dispatch. Therefore `--config-dir` alone is not a complete mock root isolation control.
- When `config.env` is sourced: inside `cmd_status()`, if `${config_dir}/config.env` exists, it is sourced and then `NANOBK_DOMAIN`, `NANOBK_VPS_IP`, `NANOBK_GEO_LABEL`, and `REALITY_SERVERNAME` are read from the shell environment.
- How `REPO_DIR` may be derived from config: `resolve_repo_dir()` reads `NANOBK_REPO_DIR=` from `${CONFIG_DIR}/config.env`, where `CONFIG_DIR` is still the global default unless `CONFIG_DIR` was changed before dispatch. It does not read the later status-local `--config-dir` path.
- Where profile path is derived: `cmd_status()` sets `profile_file="${config_dir}/profile.current.json"`.
- Where secrets path is derived: `cmd_status()` sets `secrets_file="${config_dir}/secrets.private.env"` and checks existence and file mode.
- Where Cloudflare env candidates are checked: nanok env candidates are checked in order: `${REPO_DIR}/.cloudflare.local.env`, `${config_dir}/cloudflare.local.env`, `/root/.nanok-cf-admin.env`. Separately, `adminEnvExists` checks `/root/.nanok-cf-admin.env` directly.
- Where nanob env candidates are checked: nanob env candidates are checked in order: `${REPO_DIR}/.nanob.local.env`, `${config_dir}/nanob.local.env`.
- Where systemctl/service checks happen: if `systemctl` exists, `cmd_status()` calls `systemctl is-active` for `hysteria-server.service`, `tuic-v5-9443.service`, `xray-reality-8443.service`, and `xray-trojan-2443.service`.
- Whether current code has a test-only mock root hook: no status-specific test-only mock root hook was found in `cmd_status()`.
- Whether current `--config-dir` is sufficient alone: no. It covers local `config.env`, `profile.current.json`, `secrets.private.env`, and config-dir fallback env names, but it does not control pre-dispatch `resolve_repo_dir()` and does not prevent direct `/root/.nanok-cf-admin.env` checks.
- What remains unsafe or uncertain: direct `/root/.nanok-cf-admin.env` checks remain unsafe for mock isolation; real repository env files remain possible if `REPO_DIR` resolves to a real repo; real `systemctl is-active` remains possible; sourcing `config.env` is safe only when the test controls the file content. Unknown / needs follow-up inspection: whether a production-compatible status mock hook is justified, or whether a PATH/systemctl shim plus explicit `--repo-dir` is enough for v1.8.38.

Answers to the current design questions:

1. Existing `bin/nanobk --json status` does not already support a complete safe mock root.
2. Current `--config-dir` covers status-local `config.env`, `profile.current.json`, `secrets.private.env`, `cloudflare.local.env`, and `nanob.local.env`, but not pre-dispatch repo resolution or direct root admin env checks.
3. Current `REPO_DIR` / `resolve_repo_dir()` does not read repo path from the status-local mock config path; it reads the global default config path before `cmd_status()`.
4. Cloudflare env candidate paths may still fall back to real repo/root if `REPO_DIR` is real or `/root/.nanok-cf-admin.env` exists.
5. `systemctl is-active` must be isolated, shimmed, or allowed to remain unknown; it should not inspect real services in a mock proof.
6. Future mock filesystem root needs sanitized config, profile, secrets, repo Cloudflare env, repo nanob env, and possibly a root admin env placeholder.
7. Reads from real `/etc/nanobk`, `/root`, real repo env files, and user home env files must be explicitly forbidden.
8. No `/etc/nanobk` read should be verified through source-level path inspection first, then output/log forbidden-pattern gates; strace/lsof is optional later and not required now.
9. JSON validity should be verified with `python3 -m json.tool` or equivalent on stdout/extracted operation-log JSON.
10. v1.8.38 should implement only a mock filesystem prototype if path isolation is clear; otherwise it should remain plan-only.

## 5. Proposed mock filesystem layout

Future design target:

```text
tmp_root/
  config/
    config.env
    profile.current.json
    secrets.private.env
    cloudflare.local.env
    nanob.local.env
  repo/
    .cloudflare.local.env
    .nanob.local.env
  root/
    .nanok-cf-admin.env
```

Current code cannot redirect `/root/.nanok-cf-admin.env` to `tmp_root/root/.nanok-cf-admin.env` without either a code hook, a container/chroot-style test environment, or accepting that admin root env remains absent. For v1.8.38, prefer avoiding direct root admin env reads rather than modifying production behavior.

`config.env` sanitized fields:

- `NANOBK_DOMAIN=[REDACTED_DOMAIN]` or safe placeholder.
- `NANOBK_VPS_IP=[REDACTED_IP]`.
- `NANOBK_GEO_LABEL=test-region`.
- `REALITY_SERVERNAME=[REDACTED_SNI]`.
- `REPO_DIR=`.
- optionally `NANOBK_REPO_DIR=<tmp_root/repo>` only if future inspection confirms it is needed and safe.

`profile.current.json` sanitized fields:

- `updatedAt` placeholder.
- `hy2` / `tuic` / `reality` / `trojan` sections.
- no Reality private key.
- no real URL.
- no real token.
- no real IP.

`secrets.private.env` sanitized fields:

- exists only, mode 600.
- placeholder content only.
- never printed.
- test should check mode but not cat content in final output.

`.cloudflare.local.env` sanitized fields:

- sanitized worker name.
- sanitized route URL placeholder or no raw URL.
- token-present flags if needed.
- no raw token.

`.nanob.local.env` sanitized fields:

- sanitized path / host placeholder.
- no raw token.

`.nanok-cf-admin.env` sanitized fields:

- sanitized admin URLs or placeholders.
- no raw token.

## 6. Path isolation requirements

Future mock runner must ensure:

- no `/etc/nanobk` read.
- no `/root/.nanok-cf-admin.env` read.
- no real repo `.cloudflare.local.env` read.
- no real repo `.nanob.local.env` read.
- no user home env read.
- no real VPS IP/domain in output.
- no workers.dev/pages.dev/raw URL.
- no token fingerprint unless placeholder.
- temp files chmod 600 where secrets-like.
- cleanup after run.

Verification method:

- use unique sentinel values in mock files.
- grep output/log for sentinel only.
- grep output/log to ensure no `/etc/nanobk`.
- grep output/log to ensure no `/root/`.
- optionally strace/lsof is NOT required at this stage.
- source-level path inspection required before implementation.

## 7. systemctl/service status strategy

Current status may call `systemctl is-active`.

Options:

A. Allow service status to be unknown in mock mode.

B. Add test-only systemctl shim in PATH.

C. Add future `NANOBK_STATUS_MOCK_SYSTEMCTL=1` hook.

D. Avoid service state in first mock prototype.

Recommendation: v1.8.38 should avoid real systemctl by using a PATH shim only inside the test process, or accept unknown if existing code naturally falls back. Do not modify production status behavior in planning stage.

## 8. JSON validity and redaction gates

Future mock status test must verify:

- stdout valid JSON.
- operation-log hidden output by default.
- verbose output sanitized.
- log output valid JSON or explicitly extracted JSON valid.
- no ANSI in PLAIN/UI=0/CI.
- no `TOKEN=`.
- no `SECRET=`.
- no raw IPv4.
- no raw workers.dev/pages.dev.
- no raw http/https URL.
- no `/etc/nanobk`.
- no `/root/`.
- no raw token fingerprint.
- no Reality private key.
- no fake success.
- failure rc non-zero.
- full dry-run unaffected.

## 9. Recommended v1.8.38 scope

v1.8.38 - Status JSON Mock Filesystem Prototype

Recommended allowed work:

- create mock config dir in tmp.
- create mock repo dir in tmp.
- create sanitized config/profile/env files.
- run `bin/nanobk --json status --config-dir <tmp/config>` only if inspection confirms it does not escape mock root.
- use PATH shim or unknown service status strategy.
- capture via operation-log.
- validate JSON.
- no real `/etc/nanobk`.
- no dirty VPS.
- no Cloudflare network.
- no deploy.
- no run_cmd rollout.

Alternative if risk remains:

v1.8.38 - Status JSON Mock Filesystem Prototype Plan Only

## 10. Dirty VPS policy

Dirty VPS status validation is still not approved.

Dirty VPS may be used later only after mock root prototype passes and only with strict local redaction:

- do not paste raw output.
- do not cat env.
- do not share IP/domain/workers.dev/subscription URL.
- do not run deploy.
- do not rotate.
- share sanitized summary only.

## 11. Forbidden next steps

Do NOT wrap real installed status on dirty VPS yet.

Do NOT add NANOBK_OPLOG_STATUS_PILOT yet.

Do NOT modify cmd_status yet.

Do NOT wrap VPS deploy.

Do NOT wrap Cloudflare deploy.

Do NOT wrap rotate sync.

Do NOT wrap real healthcheck.

Do NOT wrap real cf verify.

Do NOT wrap Bot/Web operations.

Do NOT full-rollout run_cmd.

Do NOT full-rollout run_critical_step.

Do NOT expose raw status JSON in chat.

## 12. v1.8.38 Feasibility Gate

v1.8.38 evaluates Route A feasibility.

- no mock runner implemented.
- no real status runtime proof yet.
- no status pilot.
- next step depends on feasibility verdict.
- v1.8.39 plans admin env path isolation before runtime prototype.
