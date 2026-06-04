# NanoBK v1.8 Operation Log Second Real Command Planning

## 1. Purpose

This document plans the second real command candidate after the v1.8.27-v1.8.28 one-command pilot.

It does not implement a second command wrapper.

It does not approve full deployment wrapping.

It does not approve run_cmd or run_critical_step rollout.

## 2. Current accepted baseline

- v1.8.29 accepted the one-command real pilot.
- Currently only `bin/nanobk --version` is wrapped.
- Real deployment output hiding is still not proven.
- run_cmd / run_critical_step remain unwrapped.

## 3. Candidate A: bin/nanobk --help

### Pros

- Harmless.
- No network.
- No sudo.
- No secrets expected.
- No profile/env read expected.
- Output larger than --version.
- Useful for output/log handling test.

### Risks

- Lower user value than status.
- May still be too trivial.
- Must verify it does not read env/profile.
- Must verify no hidden side effects.

### Decision

Likely safest second real command if code inspection confirms no env/profile/system reads.

## 4. Candidate B: bin/nanobk status --json

This candidate name refers to JSON status behavior. Current CLI syntax in this repository is `bin/nanobk --json status`; literal `bin/nanobk status --json` is not the implemented path.

### Pros

- Closer to real user value.
- Useful for future Bot/Web control plane.
- Exercises JSON output.
- Closer to future product needs.

### Risks

- May read /etc/nanobk.
- May read profile.current.json.
- May read Cloudflare env/admin env.
- May include URL-like values.
- May include workers.dev.
- May include token fingerprints.
- May include local VPS/domain/IP-like fields.
- May call systemctl or inspect services.
- May produce environment-dependent output.
- May not be safe on dirty VPS.
- May leak real deployment metadata if not sanitized.
- The literal `status --json` spelling currently fails as an unknown status option after global parsing, so rollout design must choose one spelling explicitly.

### Decision

Do not wrap real installed status --json on dirty VPS yet.

Only consider status under mock/sanitized environment after separate design.

## 5. Code inspection findings

- `--help` is implemented in `bin/nanobk` as `cmd_help()`, a static heredoc around lines 185-228.
- `parse_global_args()` handles `--help|-h` by calling `cmd_help` and exiting before `resolve_repo_dir` runs.
- Based on code inspection, `bin/nanobk --help` does not read env files, profile files, `/etc/nanobk`, Cloudflare env files, systemctl, sudo, or network.
- `cmd_help()` interpolates only `NANOBK_VERSION`.
- JSON status is implemented by the global `--json` flag plus the `status` command: `bin/nanobk --json status`.
- `cmd_status()` is implemented in `bin/nanobk` around lines 312-632.
- `cmd_status()` defaults `config_dir` to `/etc/nanobk`, then defines `config.env`, `profile.current.json`, and `secrets.private.env`.
- If `config.env` exists, `cmd_status()` sources it and reads `NANOBK_DOMAIN`, `NANOBK_VPS_IP`, `NANOBK_GEO_LABEL`, and `REALITY_SERVERNAME`.
- If `profile.current.json` exists, `cmd_status()` reads it with jq or python3 to inspect `updatedAt` and protocol sections.
- If systemctl exists, `cmd_status()` calls `systemctl is-active` for hysteria, tuic, reality, and trojan services.
- `cmd_status()` checks `secrets.private.env` existence and permissions but does not print the file contents.
- `cmd_status()` searches for Cloudflare nanok env at `${REPO_DIR}/.cloudflare.local.env`, `${config_dir}/cloudflare.local.env`, and `/root/.nanok-cf-admin.env`.
- If a nanok env file exists, `cmd_status()` reads route URL, sub path, deploy status, profile upload status, verify status, KV namespace presence, SUB_TOKEN, and ADMIN_TOKEN.
- Token values are not printed directly by `cmd_status()`, but token fingerprints are emitted as `subTokenFingerprint` and `adminTokenFingerprint` in JSON.
- `cmd_status()` separately checks whether `/root/.nanok-cf-admin.env` exists and emits `adminEnvExists`.
- `cmd_status()` searches for nanob env at `${REPO_DIR}/.nanob.local.env` and `${config_dir}/nanob.local.env`.
- If a nanob env file exists, `cmd_status()` reads worker name, route URL, path, deploy status, verify status, geo KV presence, edge host, and NANOB_TOKEN.
- Token values are not printed directly by `cmd_status()`, but `tokenFingerprint` is emitted in JSON for nanob.
- JSON status can output real domain, VPS IP, Cloudflare route URLs, workers.dev-like URLs, status fields, subscription path fields, and token fingerprints.
- `resolve_repo_dir()` can read `/etc/nanobk/config.env` before command dispatch unless `--repo-dir` or `NANOBK_REPO_DIR` is supplied.
- Existing tests use `--config-dir` and fake repo roots to exercise status safely, for example `tests/nanobk-cli-dry-run.sh`, `tests/nanob-status-env.sh`, and `tests/nanobk-status-cloudflare.sh`.
- Existing status tests create fake `.cloudflare.local.env` and `.nanob.local.env` files, but there is no general mock/sanitized status source in `bin/nanobk`.
- Status output redaction is not guaranteed by status itself. It avoids raw token output but can emit real metadata and fingerprints. Operation-log redaction would also have to preserve valid JSON if used with verbose/log output.
- Unknown / needs follow-up inspection: whether future Bot/Web status consumers depend on token fingerprints as stable identifiers.

## 6. Recommendation for v1.8.31

### Option 1, likely recommended

v1.8.31 -- Operation Log Second Real Command Pilot: `bin/nanobk --help`

Only if code inspection confirms it is harmless.

Why:

- No network.
- No sudo.
- No real status.
- No secrets.
- Still larger output than --version.

### Option 2

v1.8.31 -- Status JSON Mock/Sanitized Planning

If status --json is considered more valuable but risky.

Why:

- Needs mock/sanitized source before wrapping.
- Should not read real /etc/nanobk on dirty VPS.
- Must keep JSON valid after redaction.

## 7. Gates before wrapping --help

- Explicit opt-in env var.
- Only --mode test --defaults.
- Default path unchanged.
- Full dry-run unaffected.
- No run_cmd rollout.
- No run_critical_step rollout.
- Command failure non-zero.
- Log chmod 600.
- Hidden output default.
- Verbose redacted output.
- PLAIN/UI=0/CI no ANSI.
- No TOKEN= / SECRET=.
- No env/profile reads confirmed.
- All existing tests pass.

## 8. Gates before wrapping status --json

- Explicit opt-in env var.
- Only --mode test --defaults.
- Mock/sanitized status source.
- No real /etc/nanobk reads in tests.
- No real env file reads.
- No raw VPS IP.
- No raw domain if real.
- No raw workers.dev.
- No raw subscription URL.
- No raw token fingerprint unless explicitly redacted.
- JSON remains valid.
- Failure propagation non-zero.
- Log chmod 600.
- Hidden output default.
- Verbose redacted output.
- PLAIN/UI=0/CI no ANSI.
- Full dry-run unaffected.
- All existing tests pass.

## 9. Forbidden next steps

Do NOT wrap VPS deploy.
Do NOT wrap Cloudflare deploy.
Do NOT wrap rotate sync.
Do NOT wrap real healthcheck.
Do NOT wrap real cf verify.
Do NOT wrap Bot/Web operations.
Do NOT full-rollout run_cmd.
Do NOT full-rollout run_critical_step.
Do NOT wrap real installed status on dirty VPS.

## 10. Safety rules

- Do not paste real tokens.
- Do not cat env files.
- Do not share real VPS IP.
- Do not share real workers.dev subdomain.
- Do not share subscription URL.
- Bot/Web are control plane only.
- Dry-run is not real deployment.
- operation-log can hide output, but must never hide failure.
- planning does not approve implementation.

## 11. Implementation status

v1.8.31 implements the recommended `bin/nanobk --help` second real command pilot, while keeping `status --json` out of scope.
