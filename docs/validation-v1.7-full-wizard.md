# NanoBK v1.7 Full Wizard Clean VPS Validation

## Important

- Real clean VPS Full Wizard validation must be executed by a human tester
- Local automated tests cannot claim real VPS / Cloudflare validation passed
- dry-run does not prove real deployment works
- The pre-gate-hardening release fixed the Full Wizard dynamic stdin mock failure
- v1.7.15 fixes the Full Wizard test gates
- v1.7.16 synchronizes displayed versions and documentation
- v1.7.17 fixes `route_url: unbound variable` and `adm_token: unbound variable` that blocked local gate tests on clean VPS
- v1.7.17 fixes the local gate blocker exposed by the 12th real VPS Phase 1 validation
- v1.7.18 fixes flaky `echo "$output" | grep -q` patterns in test harnesses under `set -Eeuo pipefail`
- v1.7.18 is a test harness stability fix, not a Full Wizard main flow change
- v1.7.19 completes grep/pipefail stabilization across all remaining test harness scripts
- v1.7.19 is a test harness stability fix, not a Full Wizard main flow change
- v1.7.19 Phase A/B/D/F proved real underlying VPS and Cloudflare deploy/verify/sync works
- v1.7.19 could not tag because Full Wizard Summary had state truth bugs
- v1.7.20 fixes Full Wizard state machine and Summary truthfulness
- v1.7.20 does not claim automatic real VPS validation; user must re-run real Full Wizard
- v1.7.20 had a Cloudflare deploy status callback mismatch (deployed vs executed)
- v1.7.21 fixes Cloudflare deploy/verify/admin env status callback
- v1.7.21 does not claim automatic real VPS validation; user must re-run real Full Wizard
- v1.7.22 disables legacy admin env in Full Wizard, writes mock verified env, tightens dynamic Summary checks
- v1.7.22 does not claim automatic real VPS validation; user must re-run real Full Wizard
- v1.7.22 Phase A failed on deployed VPS because interactive mock preflight detected real occupied ports
- v1.7.23 fixes mock preflight port isolation so NANOBK_TEST_MOCK=1 skips real port detection
- v1.7.23 does not claim automatic real VPS validation; user must re-run real Full Wizard
- Phase A local gate must be re-run after v1.7.23
- Phase A must be all green before entering Phase B manual dry-run interactive validation
- dynamic stdin mock covers Cloudflare + resume before real VPS
- dynamic mock passing still does not mean production passed
- Real clean VPS / Cloudflare validation must be run by the user
- Do not enter v1.8 before v1.7 Full Wizard is completed
- Do not paste tokens into chat, logs, or issues
- Do not `cat bot/.env` or `cat web/.env`
- Do not paste `bot/.env` or `web/.env`
- Subscription URLs need to be redacted before sharing
- Bot/Web are control plane only — they do not mean VPS/Cloudflare is working

## Clean VPS Steps

```bash
# clean Ubuntu 24.04 VPS
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
cd /opt/NanoBK-Proxy-Suite
bash bin/nanobk --version

# dry-run preview
bash installer/install.sh --mode full --dry-run --defaults --lang zh

# real full wizard
bash installer/install.sh --mode full --lang zh

# verify
sudo bash /opt/nanobk/bin/healthcheck.sh
bash bin/nanobk status
bash bin/nanobk cf verify

# rotate check
sudo bash /opt/nanobk/bin/rotate-keys.sh --yes --protocol tuic
bash bin/nanobk status
```

## Pass Criteria

- VPS four protocols active (hy2, tuic, reality, trojan)
- Four ports listening (UDP 443, UDP 9443, TCP 8443, TCP 2443)
- profile.current.json exists and does not contain Reality private key
- nanok verified
- nanob verified
- Subscription YAML valid
- Bot .env mode 600
- Web .env mode 600
- rotate tuic + Cloudflare sync works
- Summary does not misreport status

## Fail Criteria

- Any stage exits non-zero
- Summary shows installed/verified but actually not verified
- Token leakage
- profile contains private key
- Cloudflare profile missing but shows configured
- Bot/Web failed but shows configured
- Deploy command was printed but user skipped execution, yet Summary shows installed/deployed
- dry-run or commands-only mode shows installed/deployed/verified states
- Bot/Web shows ordinary configured when VPS is manual-pending, commands-only, dry-run, skipped, failed, or unknown
- Bot/Web shows ordinary configured when Cloudflare is manual-pending, commands-only, dry-run, skipped, dependency-missing, failed, or unknown

## Control Plane States

Bot/Web are control-plane-only unless VPS is `installed` AND Cloudflare is `deployed` or `verified`.

States that trigger control-plane-only:
- VPS: failed, manual_pending, commands_only, dry_run, skipped, unknown
- Cloudflare: failed, manual_pending, commands_only, dry_run, skipped, skipped_dependency, unknown

`configured / control plane only` is not a clean VPS pass. Clean VPS pass requires healthcheck / status / cf verify results.

## Important: Command Execution States

If the installer only prints a deploy command but the user chooses not to execute it, this is **not** a successful deployment. The Summary will show:
- `manual command not executed` — not an error, but not a pass
- `manual / pending` — user needs to run the command manually

dry-run and commands-only modes will show:
- `planned / dry-run` — no real deployment
- `commands only / not executed` — commands printed but not run

These states are **not** valid for clean VPS pass criteria.

## Data to Report Back

- Which phases passed / failed
- Error messages from failures
- `nanobk --json status` output (redact tokens)
- healthcheck output
- Do NOT paste real tokens or subscription URLs
