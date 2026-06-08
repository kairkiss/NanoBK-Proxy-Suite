# Real /etc DNS Profile Rollback Enablement Policy — v2.1.25

## 1. Purpose

Real `/etc` rollback would restore a selected NanoBK DNS profile backup over
the production file:

```
/etc/nanobk/cloudflare-dns-profile.json
```

This is a **local production profile replacement** operation. It does not
create, update, or delete DNS records. It does not call Cloudflare. It does
not apply DNS. The subsequent step of applying the restored profile to
Cloudflare DNS is a separate explicit user action (`cf dns apply --yes`).

This document defines the production safety policy that must be satisfied
before real `/etc` rollback is implemented.

---

## 2. Current Fake-root Status (v2.1.23 / v2.1.24)

As of v2.1.24, fake-root rollback execute exists with the following properties:

- Command: `nanobk cf dns profile rollback execute`
- Real `/etc` is **blocked**; only fake-root test paths are writable
- Requires `--yes`
- Requires `--allow-production-output`
- Requires matching `--confirm-hostname EXACT`
- Requires exact `--confirm-rollback-profile "rollback profile"` (case-sensitive)
- Selected backup id is filename-only (regex-validated, no paths/traversal)
- Mandatory pre-rollback backup before replace
- Pre-rollback backup filename: `cloudflare-dns-profile.json.pre-rollback.YYYYMMDD-HHMMSS.<hex8>.bak`
- Current identity guard before replace (stat + sha256), including final
  pre-replace comparison immediately before `os.replace()`
- Exactly one `os.replace()` inside rollback-execute marker block
- No `os.rename()` anywhere
- No DNS apply/check
- No Cloudflare API calls
- No Full Wizard / Web / Bot / Console integration
- Post-replace validation failure sets `manual_recovery_required: true`
- No auto-restore on failure
- 6 test hooks for failure simulation
- 140+ test assertions

---

## 3. Decision

**v2.1.25 is docs-only.**

No real `/etc` rollback implementation is included in v2.1.25.

Real `/etc` rollback should **not** be enabled until additional production
safeguards are designed, implemented in fake-root, and reviewed.

Prefer one of:
- Closing v2.1 as fake-root-only profile management
- Moving real `/etc` enablement to v2.2 planning

---

## 4. Production Risk Model

Real `/etc` rollback carries the following risks:

| Risk | Description |
|------|-------------|
| **Root ownership** | `/etc/nanobk/` is typically root-owned; writes require root |
| **Accidental overwrite** | Wrong backup selected could overwrite valid production profile |
| **Concurrent writers** | Multiple processes could write the profile simultaneously |
| **Race conditions** | Profile could change between validation and replace |
| **Backup provenance** | Unknown origin backups could contain invalid or malicious content |
| **Legacy backup ambiguity** | Backups created before metadata model may lack provenance |
| **Operator confusion** | Operator could confuse rollback preview with execute |
| **Post-replace failure** | Replace could succeed but final validation could fail |
| **Manual recovery** | Recovery from failed replace may require manual intervention |
| **Raw secret leakage** | Error output could expose raw profile content, paths, or IPs |
| **Full Wizard/Web/Bot misuse** | Automated flows could invoke rollback without human review |
| **DNS apply confusion** | Operator could assume rollback also applies DNS |

---

## 5. Root / sudo Policy

Real `/etc` rollback must require root.

- Command must **refuse** if not running as root (`os.geteuid() != 0`)
- Command must **not** call `sudo` internally
- No privilege escalation inside NanoBK
- User must intentionally run as root (`sudo nanobk cf dns profile rollback execute ...`)
- Error message must state root is required without printing raw paths

---

## 6. Exact Path Policy

Real `/etc` rollback operates on exactly one path:

```
/etc/nanobk/cloudflare-dns-profile.json
```

- No alternative output/profile path
- No symlink path (must reject symlinks)
- No relative path
- No `/etc/nanobk/*.bak` as target
- No subdirectory path
- Parent `/etc/nanobk` must be:
  - A directory
  - Root-owned
  - Mode `0700`
  - Not a symlink

---

## 7. Additional Production Flags

Real `/etc` rollback requires all existing confirmations **plus** one new flag:

**New required flag:**
- `--enable-real-etc`

**New required typed phrase:**
- `--confirm-real-rollback "real production rollback"`
- Phrase must exactly match `real production rollback` (case-sensitive)

**Existing required flags (still required):**
- `--yes`
- `--allow-production-output`
- `--confirm-hostname EXACT`
- `--confirm-rollback-profile "rollback profile"`

Do not print expected or provided raw phrases or hostname.

---

## 8. Locking Model

Production rollback must use file locking to prevent concurrent writes.

**Lock file:** `/etc/nanobk/.nanobk-profile-lock`

Properties:
- Root-owned
- Mode `0600` or `0640` (as justified)
- Created automatically if missing (root only)
- Reject symlink

**Lock primitive:** `fcntl.flock()` (advisory, Linux/macOS compatible)

**Lock scope:**
1. Lock acquired **before** reading current profile or backup
2. Lock held through:
   - Current profile validation
   - Backup profile validation
   - Pre-rollback backup creation
   - Temp file write
   - `os.replace()`
   - Final validation
   - Directory fsync
3. Lock released after final validation

**Failure mode:**
- If lock cannot be acquired, fail safely with sanitized error
- No blocking wait; immediate fail
- No real implementation before lock model is tested in fake-root

---

## 9. Backup Metadata / Provenance Model

Real rollback should accept only backups created by NanoBK backup tooling
with metadata.

**Legacy backups** (without metadata sidecar) should be **rejected by default**.

**Metadata sidecar file:** `<backup-filename>.meta.json`

Required fields:

| Field | Description |
|-------|-------------|
| `creator_command` | Command that created this backup (e.g. `backup`, `pre-rollback`) |
| `nanobk_version` | NanoBK version at creation time |
| `created_at` | ISO 8601 timestamp |
| `logical_source_path` | `/etc/nanobk/cloudflare-dns-profile.json` |
| `profile_schema_version` | Schema version marker |
| `source_file_mode` | Octal mode of source file at creation |
| `source_owner_uid` | Expected UID of source owner |
| `backup_sha256` | SHA-256 of backup file content |
| `hostname_redacted` | Masked hostname for display |
| `backup_purpose` | `normal` or `pre-rollback` |

**Rules:**
- Full sha256 stored but **not printed** by default
- Metadata must be validated before real rollback
- Metadata tampering (hash mismatch) must fail closed
- Metadata missing must fail closed (unless explicit `--accept-legacy-backup`)

---

## 10. Pre-rollback Backup Model

Real rollback must still create a **mandatory pre-rollback backup**.

Rules:
- Byte-for-byte copy of current profile
- Backup dir: `/etc/nanobk/backups`
- Backup dir mode: `0700`
- Backup file mode: `0600`
- Metadata sidecar created alongside backup
- Pre-backup verified by:
  - Size match
  - SHA-256 match
  - JSON parse
  - Profile schema validation
- If pre-backup fails: **no replace**
- Output only redacted pre-backup id

---

## 11. Post-replace Failure / Recovery Model

Current fake-root behavior:
- Reports `manual_recovery_required: true`
- Does **not** auto-restore

Real `/etc` should **not** be implemented until recovery policy is explicitly
decided.

**Options:**

| Option | Description |
|--------|-------------|
| **A. Manual recovery only** | User manually restores from pre-rollback backup |
| **B. Auto-restore from pre-rollback** | Automatically restores pre-rollback backup on failure |
| **C. Selective auto-restore** | Auto-restore only for specific validation failure classes |

**Recommendation:** Do not implement auto-restore until separately designed
and reviewed. Auto-restore could mask underlying issues.

**If manual recovery policy is used:**
- Output must include redacted pre-backup id
- Output must include safe recovery command guidance
- No raw content / path leakage

---

## 12. DNS Apply / Check Separation

Rollback changes **only** the local DNS profile file.

- Rollback must **not** call `cf dns apply`
- Rollback must **not** call `cf dns apply --check`
- Rollback must **not** call Cloudflare API
- Success text must say: "DNS has not been applied" and "Cloudflare was not called"
- Any future apply/check after rollback must be a **separate explicit user command**

---

## 13. Full Wizard / Web / Bot / Console Boundary

Real rollback must remain **CLI-only**.

- No Full Wizard invocation
- No Web Panel button
- No Telegram Bot command
- No default console shortcut
- No beginner UI path
- Any future integration requires separate design and approval

---

## 14. Testing Strategy Without Touching Real /etc

Fake-root remains the test harness. Real `/etc` tests are **prohibited**.

**Test hooks can simulate:**
- Root gate (non-root refusal)
- Lock acquisition failure
- Metadata missing
- Metadata mismatch
- Legacy backup rejection
- Post-replace failure
- Concurrent write detection

**Source checks ensure:**
- No real `/etc` writes in tests
- No Cloudflare API calls
- No `cf dns apply` or `apply --check`
- No raw output leakage

**Real rollback implementation must be blocked until these fake-root tests exist.**

---

## 15. Staged Roadmap

| Version | Scope |
|---------|-------|
| **v2.1.25** | Docs-only real `/etc` rollback policy (this document) |
| **v2.1.26** | Fake-root profile management closeout doc |
| **v2.2.0-planning** | Production profile management scope decision |
| **v2.2.1** | Metadata / provenance design |
| **v2.2.2** | Fake-root metadata implementation |
| **v2.2.3** | Real `/etc` rollback design gate |
| **Real implementation** | Only after explicit approval |

---

## 16. Non-goals

This document does **not**:

- Implement real `/etc` rollback
- Implement production profile replacement
- Implement DNS apply/check integration
- Call Cloudflare API
- Add Full Wizard / Web / Bot / Console integration
- Implement auto-restore
- Create a release tag
