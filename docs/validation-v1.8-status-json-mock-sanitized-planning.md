# NanoBK v1.8 Status JSON Mock/Sanitized Planning

## 1. Purpose

This document plans how `bin/nanobk --json status` could eventually be tested with operation-log without reading or leaking real installed VPS/Cloudflare state.

It does not implement status wrapping.

It does not add a status pilot.

It does not approve wrapping dirty VPS installed status.

## 2. Current accepted baseline

- v1.8.29 accepted one harmless real command: `bin/nanobk --version`.
- v1.8.31 accepted second harmless real command: `bin/nanobk --help`.
- v1.8.32/v1.8.33 added focused fast tests.
- run_cmd / run_critical_step remain unwrapped.
- real deployment output hiding remains unproven.
- status remains unwrapped.

## 3. Correct status JSON command

The correct command is:

```bash
bin/nanobk --json status
```

Not:

```bash
bin/nanobk status --json
```

Reason: `parse_global_args()` consumes global options only before the command name. `--json` sets `JSON_OUT=1` before `status` is dispatched. After `status` is selected, remaining arguments are parsed by `cmd_status()`, which accepts `--config-dir` and `--dry-run` but not `--json`; therefore literal `bin/nanobk status --json` is an unknown status option in the current CLI.

## 4. Code inspection findings

- `cmd_status` is implemented in `bin/nanobk`, starting at the `cmd_status()` function.
- `--json` is parsed by `parse_global_args()` in `bin/nanobk`; it sets the global `JSON_OUT=1`.
- Before command dispatch, `resolve_repo_dir()` may inspect `/etc/nanobk/config.env` for `NANOBK_REPO_DIR` unless `--repo-dir` or `NANOBK_REPO_DIR` is supplied.
- `cmd_status()` defaults `config_dir` to `/etc/nanobk` and accepts `--config-dir PATH`.
- It defines and may read `${config_dir}/config.env`, `${config_dir}/profile.current.json`, and `${config_dir}/secrets.private.env`.
- It does read `/etc/nanobk/config.env` by default when `${config_dir}` is unchanged. The current implementation sources this file, then reads `NANOBK_DOMAIN`, `NANOBK_VPS_IP`, `NANOBK_GEO_LABEL`, and `REALITY_SERVERNAME`.
- It does read `/etc/nanobk/profile.current.json` by default when present. It extracts `updatedAt` and checks `hy2`, `tuic`, `reality`, and `trojan` profile sections using `jq` or `python3`.
- It does check `/etc/nanobk/secrets.private.env` by default for existence and file mode. It does not print or parse raw secrets from that file in `cmd_status()`.
- It may read `.cloudflare.local.env` from `${REPO_DIR}/.cloudflare.local.env`, `${config_dir}/cloudflare.local.env`, or `/root/.nanok-cf-admin.env`, using `read_env_value`.
- It does check `/root/.nanok-cf-admin.env` separately for `adminEnvExists`.
- It may read `.nanob.local.env` from `${REPO_DIR}/.nanob.local.env` or `${config_dir}/nanob.local.env`, using `read_env_value`.
- It calls `systemctl is-active` for `hysteria-server.service`, `tuic-v5-9443.service`, `xray-reality-8443.service`, and `xray-trojan-2443.service` when `systemctl` exists.
- It may inspect service status and emit service active/inactive/unknown values.
- It may output domain, VPS IP, Cloudflare route URL, workers.dev-like URL, subscription path, token fingerprint, deploy status, verify status, profile updatedAt, config/profile/env presence, and service state.
- It does not currently output raw `SUB_TOKEN`, `ADMIN_TOKEN`, `NANOB_TOKEN`, or Reality private key values from status.
- It does not currently output `ADMIN_CURRENT_URL` or `ADMIN_UPDATE_URL` from status JSON, but these values are share-sensitive if future status sources include them.
- It does not currently output profile sha16 in status JSON.
- It does not call network directly in `cmd_status()` based on this inspection; it reports local files and local service state.
- It may behave differently on dirty VPS versus clean env because dirty VPS can have `/etc/nanobk`, real profile, real Cloudflare env, `/root/.nanok-cf-admin.env`, real systemd services, and repository-local env files.

## 5. Sensitive and semi-sensitive output map

| Field / output pattern | Risk | Required handling |
|---|---|---|
| VPS IP | Identifies the server and should not appear in public logs or chat. | Redact before display/log sharing; assert no raw IP in operation-log output. |
| node domain | Identifies the deployment and may identify the user. | Redact real domain in public logs/chat; allow only example domains in fixtures. |
| profile route URL | May expose the installed access or control-plane route. | Redact as share-sensitive URL unless sanitized fixture value. |
| workers.dev URL | Share-sensitive Cloudflare deployment metadata. | Redact raw workers.dev in logs/chat. |
| subscription path | Can help reconstruct subscription endpoints. | Redact or replace with JSON-safe placeholder. |
| admin current/update URL | High risk if ever included because it can identify admin endpoints. | Do not emit raw values; redact as admin URL. Current status JSON does not emit these fields. |
| token fingerprint | Not raw token but still deployment metadata. | Treat as semi-sensitive; redact unless policy explicitly allows redacted fingerprint. |
| Cloudflare verified status | Reveals deployment state. | OK in local private logs; sanitize in public summaries. |
| nanob verified status | Reveals deployment state. | OK in local private logs; sanitize in public summaries. |
| service active/inactive status | Reveals runtime topology and installed services. | OK for local diagnostics; avoid public dirty VPS status dumps. |
| config/profile presence | Reveals installed state. | OK for sanitized summaries; do not pair with real paths and host metadata in public logs. |
| env presence | Reveals whether private env files exist. | OK as boolean in sanitized output; do not expose env contents. |
| profile updatedAt | Reveals deployment/update timing. | Treat as semi-sensitive; sanitize for public logs. |
| profile sha16 | Can correlate a deployment/profile across logs. | Current status JSON does not emit it; redact or use fixture-only placeholder if added. |

JSON redaction must not break valid JSON. If a field is redacted, replace the value with a JSON-safe string such as `"[REDACTED]"`, not raw text outside JSON syntax.

workers.dev URL and subscription URL must be treated as share-sensitive.

VPS IP/domain should not appear in public logs or chat.

## 6. Existing mock/sanitized support

Repository inspection found partial support, but not a status-specific sanitized source:

- `NANOBK_TEST_MOCK` exists in `installer/install.sh` for installer mock paths.
- `NANOBK_TEST_TMPDIR` exists in `installer/install.sh` and is used for wizard/mock temp state and fake profile paths.
- fake profile fixtures are created by installer mock paths and several tests create temporary profile/config trees.
- status test fixtures exist in tests such as `tests/nanobk-status-cloudflare.sh` and `tests/nanob-status-env.sh`, which create fake env files and invoke status with `--repo-dir` / `--config-dir`.
- mock env files are created by installer mock functions and status tests.
- `NANOBK_ASSUME_PORTS_FREE` exists for mock/dry-run port preflight assumptions.
- No current status-specific mock hook was found in `bin/nanobk`.
- No `NANOBK_TEST_MOCK` branch was found inside `cmd_status()`.
- No dedicated sanitized status fixture command was found.
- No operation-log status JSON pilot source was found.

Conclusion: Existing support is partially sufficient for tests that pass explicit `--repo-dir` and `--config-dir`, but insufficient for a safe operation-log status pilot. Missing pieces are a dedicated sanitized status source, a hard guarantee that status tests do not read real `/etc/nanobk`, and JSON-valid redaction gates.

## 7. Proposed sanitized status strategy

### Option A - fixture-based status JSON

- Create a static sanitized JSON fixture.
- operation-log wraps `cat` fixture or a helper command.
- Proves JSON capture/redaction/log handling.
- Does not test real `bin/nanobk --json status` path.
- Safest but low realism.

### Option B - mock filesystem root

- Run `bin/nanobk --json status` with `NANOBK_TEST_TMPDIR` or similar.
- Inject sanitized config/profile/env files.
- Ensure status reads only test root.
- Block `/etc/nanobk` reads.
- More realistic but requires code support if not present.

### Option C - dirty VPS read-only status

- Run real `bin/nanobk --json status` on dirty VPS.
- High realism.
- High leakage risk.
- Only after redaction and local review.
- Never paste raw output into chat.

Recommendation: v1.8.35 should use `v1.8.35 - Status JSON Sanitized Fixture Prototype` as the next step. Do not implement dirty VPS status pilot yet.

## 8. JSON validity gates

Before wrapping status JSON, tests must verify:

- raw captured output is valid JSON.
- redacted log output remains valid JSON or is clearly marked as log text.
- if redaction replaces values, it must use JSON-safe strings.
- no trailing ANSI.
- no control chars.
- PLAIN/UI=0/CI no ANSI.
- no TOKEN=.
- no SECRET=.
- no raw IP.
- no raw workers.dev.
- no raw subscription URL.
- no raw admin URL.
- no raw token fingerprint unless policy explicitly allows redacted fingerprint.
- failure returns non-zero.
- full dry-run unaffected.

## 9. Dirty VPS validation policy

Dirty VPS may be useful later for read-only status validation, but only with strict rules:

- run locally on VPS.
- do not paste raw output.
- first grep/redact locally.
- only share sanitized summary.
- do not cat env files.
- do not share real IP/domain/workers.dev/subscription URL.
- do not run Cloudflare deploy.
- do not rotate keys.
- do not run fresh install.

## 10. Forbidden next steps

Do NOT wrap real installed status on dirty VPS yet.

Do NOT wrap VPS deploy.

Do NOT wrap Cloudflare deploy.

Do NOT wrap rotate sync.

Do NOT wrap real healthcheck.

Do NOT wrap real cf verify.

Do NOT wrap Bot/Web operations.

Do NOT full-rollout run_cmd.

Do NOT full-rollout run_critical_step.

Do NOT expose raw status JSON in chat.

## 11. Recommendation for v1.8.35

Recommended next version:

`v1.8.35 - Status JSON Sanitized Fixture Prototype`

Requirements:

- still no dirty VPS real status wrapping.
- no run_cmd rollout.
- no run_critical_step rollout.
- start with sanitized fixture or mock filesystem.
- prove JSON validity and redaction policy.
- keep focused fast tests.

## 12. v1.8.35 Sanitized Fixture Prototype

v1.8.35 adds a static sanitized status JSON fixture:

- `tests/fixtures/status-json-sanitized-v1.8.json`
- fixture mirrors current status JSON schema structure.
- fixture contains only JSON-safe placeholders (`[REDACTED_IP]`, `[REDACTED_DOMAIN]`, `[REDACTED_URL]`, `[REDACTED_FINGERPRINT]`, etc.).
- fixture does not contain real IP, domain, workers.dev URL, subscription URL, admin URL, or raw token fingerprints.
- fixture does not contain `TOKEN=`, `SECRET=`, `sha256:`, `/etc/nanobk`, `/root/`, or any RFC test IP.

Operation-log capture verified:

- `oplog_run_hidden` captures fixture output to log file.
- default mode hides JSON content from screen.
- verbose mode (`NANOBK_VERBOSE=1`) shows sanitized JSON on screen.
- PLAIN/UI=0/CI modes produce no ANSI escape sequences.
- log file has chmod 600 permissions.
- log file contains valid JSON after extraction.
- log file does not contain forbidden patterns.
- failure propagation tested: non-zero exit code propagates, raw secrets are redacted from both screen and log.

What this does NOT do:

- this still does not run real `bin/nanobk --json status`.
- this still does not approve dirty VPS status wrapping.
- this does not add a third real command pilot.
- this does not modify `cmd_status` or status JSON schema.
- this does not change `install.sh` behavior.

Next step should be mock filesystem root design (Option B from section 7), not real dirty VPS status.

## 13. v1.8.36 Fixture Test Polish

v1.8.36 does not change the fixture schema.

v1.8.36 does not run real `bin/nanobk --json status`.

Test polish applied:

- fixed placeholder checks to use fixed-string matching (`grep -Fq`) instead of regex matching, preventing `[REDACTED_IP]` from being interpreted as a character class.
- replaced `echo "$x" | grep -q` patterns with here-string (`grep -qF "pattern" <<< "$x"`) where practical.
- replaced multiple `trap "rm -rf ..." EXIT` overrides with `register_cleanup` from `tests/lib/assertions.sh`.
- removed unused variables (`json_in_log`, `log_json_errors`, `log_json_rc`).
- used `has_ansi` helper from assertions library for ANSI detection in PLAIN/UI=0/CI tests.
- improved source guard to read only the test body (before the guard section) to avoid self-referencing false positives.
- preserved all operation-log hidden/verbose/PLAIN/UI=0/CI/failure propagation checks.

What this does NOT do:

- this still does not run real `bin/nanobk --json status`.
- this still does not approve dirty VPS status wrapping.
- next step remains mock filesystem root design, not dirty VPS status wrapping.

## 14. v1.8.37 Mock Filesystem Root Design

v1.8.37 adds mock filesystem root design.

- it does not implement mock runner.
- it does not run real status.
- it does not approve dirty VPS status wrapping.
- it documents path isolation requirements before any real status code-path prototype.
- next step is v1.8.38 mock filesystem prototype only if path isolation is clear.
- v1.8.38 adds a feasibility gate before any mock filesystem runtime prototype.
- v1.8.39 keeps dirty VPS status out of scope and plans a minimal test-only admin env path hook.
- v1.8.40 implements the minimal `NANOBK_STATUS_TEST_ADMIN_ENV_PATH` hook for admin env existence check isolation.
