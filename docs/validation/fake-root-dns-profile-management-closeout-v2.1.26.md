# Fake-root DNS Profile Management Closeout — v2.1.26

## 1. Baseline and Verdict

- **Baseline commit:** `9987bdf`
- **Baseline message:** v2.1.25 polish legacy backup policy
- **Verdict:** v2.1 fake-root DNS/profile management line is ready to close as a non-production safety milestone
- **Release/tag:** No release or tag unless owner explicitly approves

---

## 2. Completed Scope

The v2.1 line delivered the following capabilities, all under fake-root test mode:

### Read-only DNS preparation (v2.1.4–v2.1.12)

- Cloudflare zone listing (`cf zones list`)
- DNS readiness report (`cf dns readiness`)
- DNS target preview (`cf dns target preview`)
- Subdomain availability check and summary (`cf dns availability`)
- Combined DNS preparation report (`cf dns report`)
- DNS plan dry-run (`cf dns plan`)
- DNS profile validation (`cf dns validate-profile`)

### Profile preview and generation (v2.1.14–v2.1.17)

- DNS profile preview (`cf dns profile preview`)
- Temp-output DNS profile writer (`cf dns profile generate`)
- Fake-root production profile writer (`cf dns profile generate --allow-production-output`)

### Profile backup and replace preview (v2.1.19–v2.1.20)

- Backup-only fake-root command (`cf dns profile backup`)
- Replace preview (`cf dns profile replace preview`)

### Rollback preview and execute (v2.1.21–v2.1.24)

- Rollback preview (`cf dns profile rollback preview`)
- Fake-root rollback execute (`cf dns profile rollback execute`)
- Pre-rollback backup with random8 suffix
- Current identity guard (stat + sha256)
- Final pre-replace identity comparison
- Marker-scoped `os.replace()`
- Post-replace validation with `manual_recovery_required`
- 6 test hooks for failure simulation

### Policy documentation (v2.1.25)

- Real `/etc` rollback enablement policy
- Root/no-sudo model
- Exact path policy
- Lock model
- Metadata/provenance requirement
- Legacy backup rejection

---

## 3. Safety Guarantees

The v2.1 profile management line maintains the following safety guarantees:

- **No Cloudflare mutation** from profile management flow
- **No DNS apply/check auto-run** from any profile command
- **No real `/etc` rollback** implemented
- **No Full Wizard / Web / Bot / console integration**
- **Fake-root-only** write / replace / rollback paths
- **Mandatory confirmations** for all destructive fake-root operations:
  - `--yes`
  - `--allow-production-output`
  - `--confirm-hostname EXACT`
  - `--confirm-rollback-profile "rollback profile"`
- **Mandatory pre-rollback backup** before fake-root rollback execute
- **Current identity guard** before replace (stat + sha256, including final pre-replace comparison)
- **Marker-scoped `os.replace()`** — exactly one, inside rollback-execute block
- **No `os.rename()`** anywhere
- **Raw values not printed** by default: profile content, backup content, IPs, hostnames, paths, full sha256, confirmation phrases

---

## 4. Test Coverage

### Focused profile tests

| Test | Coverage |
|------|----------|
| `cf-dns-profile-preview.sh` | Preview-only validation, dry-run, safety |
| `cf-dns-profile-generate.sh` | Temp-output writer, overwrite rejection, source checks |
| `cf-dns-profile-production.sh` | Fake-root production writer, confirmations, source checks |
| `cf-dns-profile-backup.sh` | Backup-only, mode verification, source checks |
| `cf-dns-profile-replace-preview.sh` | Replace preview, diff, source checks |
| `cf-dns-profile-rollback-preview.sh` | Rollback preview, backup validation, source checks |
| `cf-dns-profile-rollback-execute.sh` | Rollback execute, hooks, identity guard, 140+ assertions |

### Regression tests

- `cf-dns-prep-contract.sh`
- `cf-dns-report.sh`
- `cf-dns-availability.sh`
- `cf-dns-target-preview.sh`
- `cf-dns-readiness.sh`
- `cf-zones-list.sh`
- `cf-dns-plan.sh`
- `cf-dns-apply.sh`
- CLI UI / TUI / product entry / bootstrap / version tests

### `nanobk test --all`

All 7 newer profile tests are included in `nanobk test --all`.

---

## 5. Explicitly Not Implemented

The following are **not** implemented in v2.1:

- Real `/etc` rollback
- Real production profile replacement
- Real `/etc` metadata / provenance implementation
- Real lock implementation (`fcntl.flock()`)
- Auto-restore on post-replace failure
- DNS apply/check integration from profile management
- Cloudflare API mutation
- Full Wizard / Web / Bot / console integration
- Release / tag

---

## 6. Real /etc Policy Status

The v2.1.25 policy document (`docs/architecture/real-etc-dns-profile-rollback-policy-v2.1.25.md`) defines the production safety requirements:

- Real `/etc` requires **v2.2 planning**
- **Root / no-sudo** model
- **Exact path** policy (`/etc/nanobk/cloudflare-dns-profile.json` only)
- **`--enable-real-etc`** flag required
- **Typed confirmation:** `real production rollback`
- **Lock file:** `/etc/nanobk/.nanobk-profile-lock` with `fcntl.flock()`
- **Metadata / provenance** sidecar required for all backups
- **Legacy backups rejected** (no `--accept-legacy-backup`)
- **Fake-root tests first** — real implementation blocked until fake-root coverage exists

---

## 7. v1.9.60 Compatibility Note

- v2.1 profile management did **not** intentionally replace or modify v1.9.60 rotate/key rotation features.
- v1.9.60 rotate/key rotation remains **separate**.
- No Full Wizard / installer / rotate integration was added in the v2.1 profile line.
- Any production integration should be **planned separately**.

---

## 8. Future Roadmap

**Recommendation:** Stop v2.1 feature work after closeout.

| Phase | Scope |
|-------|-------|
| **v2.2.0-planning** | Production profile management scope decision |
| **v2.2.1** | Metadata / provenance design |
| **v2.2.2** | Fake-root metadata implementation |
| **v2.2.3** | Real `/etc` rollback design gate |
| **Real implementation** | Only after explicit approval |

---

## 9. Non-goals

This closeout does **not**:

- Implement new runtime behavior
- Create a release or tag
- Modify `bin/nanobk`, `lib/`, or installer files
- Touch real `/etc`
- Call Cloudflare or DNS apply/check
