# NanoBK Proxy Suite — v2.1.12 Read-only DNS Preparation Phase Closeout

## Baseline

- Repository: https://github.com/kairkiss/NanoBK-Proxy-Suite
- Branch: main
- Baseline commit: cfd196395b76c2f42948ba7c779aa117df61e2bf
- Baseline commit message: v2.1.11 polish dns prep json contract
- Closeout type: docs-only
- Release/tag: none

## Verdict

**PASS — v2.1 read-only DNS preparation foundation is ready to close.**

This closeout does not approve profile writing, DNS apply, Cloudflare mutation, Full Wizard integration, Tunnel, Access, DNS-01, release, or tag.

## Completed Scope

| Command | Purpose |
|---------|---------|
| `nanobk cf zones list --api-env PATH [--json]` | Read-only Cloudflare zone discovery |
| `nanobk cf dns readiness [--api-env PATH] [--profile PATH] [--json]` | Read-only DNS preparation readiness |
| `nanobk vps ip detect [--json]` | Fixture-first VPS IP candidate detection |
| `nanobk cf dns target preview --zone DOMAIN [--node NODE] --ip-fixture PATH [--json]` | Redacted target preview for proxy A/AAAA candidates |
| `nanobk cf dns availability check --zone DOMAIN --node NODE --api-env PATH [--json]` | GET-only one-host DNS availability check |
| `nanobk cf dns availability summary --zone DOMAIN --api-env PATH [--nodes proxy,web] [--json]` | GET-only multi-host availability summary |
| `nanobk cf dns report --zone DOMAIN --api-env PATH --ip-fixture PATH [--nodes proxy,web] [--json]` | Combined DNS preparation report |
| `tests/cf-dns-prep-contract.sh` | Shared JSON/dry-run contract smoke test |

## Safety Guarantees

- No read-only prep helper writes DNS profiles.
- No read-only prep helper writes `/etc/nanobk/cloudflare-dns-profile.json`.
- No read-only prep helper calls `cf dns apply`.
- No read-only prep helper calls `cf dns apply --check`.
- No read-only prep helper performs DNS create/update/delete.
- No read-only prep helper performs Cloudflare mutation.
- Availability and zone discovery are GET-only.
- Tests use fake transports/fixtures where real Cloudflare would otherwise be involved.
- Existing DNS apply helper remains isolated and unchanged by this closeout phase.
- Full Wizard behavior is not changed by this phase.
- Bot/Web behavior is not changed by this phase.
- Installer behavior is not changed by this phase.

## Privacy and Redaction Guarantees

- Token values are not printed.
- Authorization headers are not printed.
- Raw env contents are not printed.
- DNS record IDs are not printed in prep outputs.
- DNS record comments are not printed in prep outputs.
- DNS record content is redacted/summarized.
- Full IPs are not printed by default in new prep helpers.
- Raw hostnames/domains are redacted in JSON outputs.
- Protocol links are not printed.
- Subscription URLs are not printed.
- `workers.dev` URLs are not printed.
- Reality private keys are not printed.

**Accepted limitation:** Text output may show masked examples such as redacted hostnames and redacted IPs. Older explicit advanced `cf dns plan` behavior is not the same as the stricter v2.1 prep redaction contract and should not be overclaimed.

## JSON Contract

- `ok` means command/report construction result, not "DNS applied".
- `mutation=false` is included across expected prep JSON outputs/errors.
- `profile_write=false` is included for DNS-profile-related prep helpers.
- `ready`, `target_ready`, `dns_target_ready`, and `ready_for_profile_generation` are conservative readiness indicators.
- `manual_pending`/`manual_review` states mean user action is still required.
- JSON errors should be sanitized and should not print tracebacks.

## Dry-run Contract

Global and command-level dry-run now skip helper execution for:

- `cf zones list`
- `cf dns readiness`
- `vps ip detect`
- `cf dns target preview`
- `cf dns availability check`
- `cf dns availability summary`
- `cf dns report`

Dry-run should not read env/profile/fixture files and should not call Cloudflare.

**Accepted difference:** Older `cf dns plan` / `validate-profile` remain local no-mutation validation paths and may still validate local input under dry-run.

## Test and Contract Coverage

- `tests/cf-dns-prep-contract.sh`
- `tests/cf-zones-list.sh`
- `tests/cf-dns-readiness.sh`
- `tests/vps-ip-detect.sh`
- `tests/cf-dns-target-preview.sh`
- `tests/cf-dns-availability.sh`
- `tests/cf-dns-report.sh`
- `tests/cf-dns-plan.sh`
- `tests/cf-dns-apply.sh`
- `tests/v2.1.2-cli-tui-skeleton.sh`
- `tests/v2.1.3-cli-ui-polish.sh`
- `tests/bootstrap-dry-run.sh`
- `tests/cli-version-display-v1.9.58.sh`

This closeout is based on source inspection and reported focused test results from v2.1.4–v2.1.11. No real Cloudflare mutation is part of this closeout.

## Explicitly Not Implemented

- DNS profile generator.
- Writing `/etc/nanobk/cloudflare-dns-profile.json`.
- Automatic DNS apply.
- `cf dns apply --check` integration into readiness/report.
- Cloudflare DNS record create/update/delete.
- Cloudflare mutation.
- Full Wizard integration of new prep report flow.
- Web/Bot integration of new prep report flow.
- Live VPS IP detection.
- Real Cloudflare GET-only validation.
- Real Cloudflare write validation.
- Cloudflare Tunnel.
- Cloudflare Access.
- DNS-01 certificate automation.
- Worker custom domain automation.
- Release/tag.

## Accepted Limitations

- v2.1 prep report is not a deployment.
- `ready_for_profile_generation` does not mean DNS has been created.
- Availability checks can perform real GET-only Cloudflare lookups when used with real api-env, but tests use fake transport.
- Profile generation is intentionally deferred.
- Full Wizard integration is intentionally deferred.
- Web public exposure/Tunnel/Access are intentionally deferred.
- DNS-01 certificate automation is intentionally deferred.

## Future Work

Recommended next phase:

**v2.1.13-planning — Controlled DNS Profile Generator Scope**

Future work should plan:

- Explicit confirmation before writing profile.
- `chmod 600`.
- No DNS apply.
- No Cloudflare mutation.
- No Full Wizard auto-run.
- No overwrite without backup/review.
- Rollback/recovery story.
- Honest Summary states.
- No raw secret output.
- Disposable test resources before any real mutation.

## Release/Tag Policy

- No release tag is created for v2.1.12.
- No release should be created without Owner explicit approval.
- v2.1.12 is a docs-only closeout record on main.

## Owner Next Decision

Owner should decide whether to proceed to:

- **v2.1.13-planning — Controlled DNS Profile Generator Scope**

or pause v2.1 after read-only closeout.
