# v2.2.5 — Profile Backup Metadata/Provenance Design

## 1. Purpose

This document defines the metadata/provenance sidecar design for future
Cloudflare DNS profile backups. It specifies the backup identity model,
metadata schema fields, backup purpose policy, source profile identity,
schema marker, file mode and owner expectations, sha256/fingerprint policy,
legacy backup fail-closed policy, fake-root implementation prerequisites,
real `/etc` runtime gate, rollback/lock/auto-restore relationship, redaction
rules, and future test strategy.

This is a design document. It does not implement any new behavior. No real
`/etc` writes. No fake-root metadata writes. No runtime code changes.

---

## 2. Baseline

**Existing backup command (v2.1.20):**

- `nanobk cf dns profile backup` — fake-root-only backup command.
- Copies valid existing fake-root production profile byte-for-byte.
- Requires `--yes`, `--allow-production-output`, `--confirm-hostname EXACT`.
- Backup dir: `/etc/nanobk/backups` (under fake-root).
- Backup dir mode: `0700`.
- Backup file mode: `0600`.
- SHA-256 verification after copy.
- No metadata sidecar is created in v2.1.20.

**Existing rollback execute (v2.1.23–v2.1.24):**

- Fake-root-only rollback execute.
- Mandatory pre-rollback backup before replace.
- Current identity guard (stat + sha256).
- Final pre-replace identity comparison.
- Marker-scoped `os.replace()`.
- Post-replace validation failure reports `manual_recovery_required: true`.
- No auto-restore.
- No metadata sidecar validation.

**Existing rollback policy (v2.1.25):**

- Defines metadata sidecar file: `<backup-filename>.meta.json`.
- Required fields: `creator_command`, `nanobk_version`, `created_at`,
  `logical_source_path`, `profile_schema_version`, `source_file_mode`,
  `source_owner_uid`, `backup_sha256`, `hostname_redacted`, `backup_purpose`.
- Full sha256 stored but not printed by default.
- Metadata must be validated before real rollback.
- Metadata tampering (hash mismatch) must fail closed.
- Metadata missing must fail closed.
- Legacy backups without metadata are not accepted by the initial real `/etc`
  rollback policy.
- Any legacy backup override requires separate future design/spec and
  explicit approval.

**Existing closeout (v2.1.26):**

- v2.1 fake-root profile management line is closed.
- No real `/etc` rollback implemented.
- No metadata sidecar implemented.
- Real `/etc` requires v2.2 planning.

---

## 3. Product Safety Goal

Production profile backups must be trustworthy. A backup without provenance
is not trustworthy. Before any real `/etc` rollback can be considered, the
system must know:

- Who created the backup (which command, which version).
- When the backup was created.
- What the backup contains (schema, hostname, size, hash).
- Why the backup was created (normal or pre-rollback).
- Whether the backup is byte-for-byte identical to the source.

Metadata/provenance provides this information. Without it, real rollback
is unsafe.

---

## 4. Why Metadata/Provenance Is Required

**Without metadata:**

- The system cannot verify that a backup was created by NanoBK.
- The system cannot verify that a backup was created at a known time.
- The system cannot verify that a backup matches the expected schema.
- The system cannot verify that a backup is byte-for-byte identical to
  its source.
- The system cannot distinguish between a user-created backup and a
  manually copied file.
- The system cannot reject legacy or unknown-origin backups.
- The system cannot enforce the pre-rollback backup requirement.

**With metadata:**

- The system can verify backup origin and integrity.
- The system can reject unknown-origin backups.
- The system can enforce the pre-rollback backup requirement.
- The system can display safe summaries without exposing secrets.
- The system can provide recovery guidance with trustworthy backup IDs.

---

## 5. Scope Decision

**v2.2.5 is docs-only metadata/provenance design.**

No real `/etc` production profile write or rollback is allowed by v2.2.5.

Metadata/provenance must be designed before real `/etc` rollback can be
considered.

**v2.2.6 may implement metadata/provenance in fake-root only**, after this
document is accepted.

**Real `/etc` runtime remains blocked** until metadata implementation exists,
lock design is accepted, backup validation tests pass, rollback preview tests
pass, and explicit Owner approval is given.

---

## 6. Backup Identity Model

Each backup has a unique identity composed of:

- **Backup ID**: the filename only (e.g.,
  `cloudflare-dns-profile.20260608T120000Z.ab12cd34.json`).
- **Backup path**: the full filesystem path under the backup directory.
- **Metadata sidecar**: a JSON file with the same name plus `.metadata.json`
  suffix.

**Backup ID rules:**

- Must be filename-only (no directory component).
- Must reject absolute paths.
- Must reject `..` traversal.
- Must reject `/` or `\` path separators.
- Must reject symlink escape.
- Must match a strict regex pattern.

**Example backup file pair:**

```
/etc/nanobk/backups/
  cloudflare-dns-profile.20260608T120000Z.ab12cd34.json
  cloudflare-dns-profile.20260608T120000Z.ab12cd34.json.metadata.json
```

The metadata sidecar belongs to exactly one backup file. The backup file
and metadata sidecar must be created together.

---

## 7. Metadata Sidecar File Model

The metadata sidecar is a JSON file that accompanies each backup.

**File properties:**

- Format: JSON (valid, parseable).
- Filename: `<backup-filename>.metadata.json`.
- File mode: `0600` (owner read/write only).
- Created atomically alongside the backup file.
- Belongs to exactly one backup file.

**Relationship:**

- Backup file: `cloudflare-dns-profile.20260608T120000Z.ab12cd34.json`
- Metadata sidecar: `cloudflare-dns-profile.20260608T120000Z.ab12cd34.json.metadata.json`

**Validation:**

- Metadata must be valid JSON.
- Metadata must contain all required fields.
- Metadata `backup_id` must match the actual backup filename.
- Metadata `backup_sha256` must match the actual backup file content.
- Metadata `source_sha256` must match the source file at creation time.
- Any validation failure must fail closed.

---

## 8. Required Metadata Fields

The metadata sidecar must contain the following fields:

```json
{
  "metadata_schema_version": "1",
  "backup_id": "cloudflare-dns-profile.20260608T120000Z.ab12cd34.json",
  "backup_purpose": "normal",
  "created_at_utc": "2026-06-08T12:00:00Z",
  "created_by_command": "nanobk cf dns profile backup ...",
  "nanobk_version": "2.x",
  "source_logical_path": "/etc/nanobk/cloudflare-dns-profile.json",
  "source_path_kind": "production",
  "profile_schema_marker": "cloudflare_dns_profile_v1",
  "profile_hostname_redacted": "ex***e.com",
  "profile_fields_redacted": {
    "zone_name": "ex***e.com",
    "record_names": ["pr***y.ex***e.com", "we*.ex***e.com"]
  },
  "source_file_mode": "0600",
  "source_owner_expected": "root:root",
  "source_size_bytes": 1234,
  "source_sha256": "<full sha256 in metadata file>",
  "source_sha256_fingerprint": "abcd1234",
  "backup_file_mode": "0600",
  "backup_size_bytes": 1234,
  "backup_sha256": "<full sha256 in metadata file>",
  "backup_sha256_fingerprint": "abcd1234",
  "backup_byte_for_byte": true,
  "created_under_fake_root": true,
  "real_etc_runtime": false
}
```

**Field descriptions:**

| Field | Description |
|-------|-------------|
| `metadata_schema_version` | Schema version marker for future compatibility |
| `backup_id` | Filename-only backup identifier |
| `backup_purpose` | `normal` or `pre_rollback` |
| `created_at_utc` | ISO 8601 timestamp of backup creation |
| `created_by_command` | Command that created this backup |
| `nanobk_version` | NanoBK version at creation time |
| `source_logical_path` | Expected production profile path |
| `source_path_kind` | `production` or `fake_root` |
| `profile_schema_marker` | Profile schema version marker |
| `profile_hostname_redacted` | Masked hostname for display |
| `profile_fields_redacted` | Redacted structured fields for display |
| `source_file_mode` | Octal mode of source file at creation |
| `source_owner_expected` | Expected owner (e.g., `root:root`) |
| `source_size_bytes` | Size of source file at creation |
| `source_sha256` | Full SHA-256 of source file content |
| `source_sha256_fingerprint` | First 8 hex chars of source SHA-256 |
| `backup_file_mode` | Octal mode of backup file |
| `backup_size_bytes` | Size of backup file |
| `backup_sha256` | Full SHA-256 of backup file content |
| `backup_sha256_fingerprint` | First 8 hex chars of backup SHA-256 |
| `backup_byte_for_byte` | Whether backup is byte-for-byte identical to source |
| `created_under_fake_root` | Whether this was created under fake-root test mode |
| `real_etc_runtime` | Whether real `/etc` was involved |

**Security rules for metadata:**

- The metadata file may contain full sha256 for machine validation.
- User-facing output must show fingerprint only, not full sha256.
- Metadata must not contain raw secrets.
- Metadata must not contain raw tokens.
- Metadata must not contain private keys.
- Metadata must not contain protocol links.
- Metadata must not contain subscription URLs.
- Metadata must not contain raw env content.
- Metadata must not contain raw workers.dev URLs.
- Metadata may contain redacted structured fields only.

---

## 9. Backup Purpose Policy

Allowed `backup_purpose` values:

| Value | Meaning |
|-------|---------|
| `normal` | User/operator requested backup before planned change or maintenance |
| `pre_rollback` | Mandatory backup automatically created immediately before rollback execute |

**Rules:**

- `pre_rollback` backup is mandatory before rollback execute.
- `pre_rollback` backup must have metadata.
- Rollback execute must fail closed if pre-rollback backup metadata cannot
  be written or validated.
- `backup_purpose` must not be free-form text.
- Unknown or missing `backup_purpose` must fail closed.

---

## 10. Source Profile Identity Policy

Source identity checks are required for future rollback safety.

**Rules:**

- Source logical path must match expected production profile path.
- Backup metadata must refer to the exact logical source path.
- Profile schema marker must match expected schema.
- Hostname/domain identity must match current target.
- Current profile identity must be checked before rollback.
- Selected backup identity must be checked before rollback.
- Final pre-replace identity comparison must happen immediately before
  replace.
- Mismatch must fail closed.

**Critical statement:**

A backup without metadata is not trustworthy for real rollback.

---

## 11. Profile Schema Marker Policy

The `profile_schema_marker` field identifies the schema version of the
profile at the time of backup.

**Rules:**

- Must match a known schema version (e.g., `cloudflare_dns_profile_v1`).
- Unknown schema markers must fail closed.
- Schema marker must be validated before rollback.
- Schema evolution must be handled by bumping the marker version.

---

## 12. File Mode and Owner Expectation Policy

**Backup directory:**

- Mode: `0700` (owner read/write/execute only).
- Path: `/etc/nanobk/backups`.

**Backup file:**

- Mode: `0600` (owner read/write only).
- Created atomically (temp + hard link or os.replace).

**Metadata sidecar:**

- Mode: `0600` (owner read/write only).
- Created atomically alongside backup file.

**Source file (production):**

- Expected mode: `0600`.
- Expected owner: `root:root`.
- Mode and owner are recorded in metadata for validation.

**Source file (fake-root):**

- Mode and owner expectations may differ under test mode.
- `created_under_fake_root: true` indicates test mode.

---

## 13. SHA-256 and Fingerprint Policy

**Full SHA-256:**

- Stored in metadata file for machine validation.
- Used to verify backup integrity (byte-for-byte match).
- Used to verify source identity at creation time.
- Must NOT be printed in user-facing output.

**Fingerprint:**

- First 8 hex characters of SHA-256.
- Used in user-facing output for safe display.
- Format: `sha256:abcd1234`.
- Sufficient for human identification without exposing full hash.

**Rules:**

- Full sha256 is in metadata file only.
- User-facing output shows fingerprint only.
- Full sha256 must not appear in console, Bot, or Web output.
- Full sha256 must not appear in error messages.

---

## 14. Legacy Backup Fail-closed Policy

**Legacy backups** are backups created without a metadata sidecar.

**Policy:**

Legacy backups without metadata must fail closed for real rollback.

**There must be no `--accept-legacy-backup` exception.**

**Rationale:**

- Legacy backups have no provenance.
- Legacy backups cannot be verified for integrity.
- Legacy backups may contain invalid or malicious content.
- Legacy backups may have been created by unknown tools.
- Accepting legacy backups would undermine the entire metadata model.

**Advanced mode exception:**

Legacy backups may be listed as manual recovery candidates in advanced mode,
but must not be accepted by automated real rollback. This allows operators
to manually inspect and restore legacy backups if needed, without the system
automatically trusting them.

---

## 15. Fake-root Implementation Prerequisites

Before implementing metadata/provenance in fake-root, the following must
be in place:

1. This design document is accepted.
2. Metadata schema is finalized.
3. Backup ID validation regex is defined.
4. Metadata sidecar creation logic is designed.
5. Metadata validation logic is designed.
6. Legacy backup detection logic is designed.
7. Test hooks for metadata failure simulation are designed.
8. Focused test script is designed.

**v2.2.6 scope:**

- Implement metadata sidecar creation in fake-root backup command.
- Implement metadata validation in fake-root rollback preview/execute.
- Implement legacy backup rejection in fake-root rollback.
- Add test hooks for metadata failure simulation.
- Add focused test: `tests/cf-dns-profile-backup-metadata.sh`.

**v2.2.6 does NOT:**

- Implement real `/etc` writes.
- Implement real rollback.
- Implement lock.
- Implement auto-restore.

---

## 16. Real /etc Runtime Gate

Real `/etc` production profile write and rollback remain blocked.

**Requirements before real `/etc` can be considered:**

1. Metadata/provenance is implemented in fake-root.
2. Lock design is accepted.
3. Backup validation tests pass.
4. Rollback preview tests pass.
5. Rollback execute tests pass (fake-root).
6. Legacy backup rejection tests pass.
7. Pre-rollback backup with metadata tests pass.
8. Explicit Owner approval is given.

**Real `/etc` must stay blocked until all of the above are satisfied.**

---

## 17. Rollback Relationship

**Rollback preview:**

- Can inspect metadata to display backup provenance.
- Shows backup ID, created_at, purpose, fingerprint, schema marker.
- Does not perform mutation.

**Rollback execute:**

- Must validate metadata before replace.
- Must create pre-rollback backup with metadata before replacing current
  profile.
- Must fail closed if pre-rollback backup metadata cannot be written or
  validated.
- Must fail closed if selected backup metadata is invalid or missing.
- Must not auto-restore unless auto-restore policy is separately approved.
- Post-replace validation failure should report `manual_recovery_required: true`
  unless auto-restore is designed and approved.

---

## 18. Lock Relationship

Real `/etc` operations require a lock to prevent concurrent writes.

**Lock design (from v2.1.25 policy):**

- Lock path: `/etc/nanobk/.nanobk-profile-lock`.
- Lock primitive: `fcntl.flock()` (advisory, Linux/macOS compatible).
- Lock scope: held across read, validate, backup, metadata, temp write,
  atomic replace, post-check.
- Lock failure: immediate fail, no blocking wait.

**v2.2.5 decision:**

- Lock is not implemented in v2.2.5.
- Lock is not implemented in v2.2.6 (fake-root only).
- Lock is required for real `/etc` runtime.
- Lock design is documented here for completeness.

**Fake-root metadata implementation may simulate lock or defer lock until
real design gate.** The decision should be recorded in the v2.2.6
implementation document.

---

## 19. Auto-restore Relationship

**Auto-restore is not part of v2.2.5.**

**Auto-restore is not part of v2.2.6 unless explicitly approved.**

**Auto-restore requires separate policy** because it introduces another
write after failure. Writing to production `/etc` after a failed replace
could mask underlying issues.

**Until auto-restore is designed and approved:**

- Post-replace validation failure reports `manual_recovery_required: true`.
- Output includes redacted pre-rollback backup ID.
- Output includes safe recovery command guidance.
- No automatic writes after failure.

---

## 20. Redaction and Display Rules

**Never print in user-facing output:**

- Raw token
- Private key
- Reality private key
- Protocol link (`hysteria2://`, `tuic://`, `vless://`, `trojan://`)
- Subscription URL
- `workers.dev` URL
- Raw env content
- Raw profile secret
- Authorization header
- Full SHA-256

**Allowed display:**

- Backup ID (filename only)
- `created_at_utc`
- `backup_purpose`
- Redacted hostname
- SHA-256 fingerprint (first 8 hex chars)
- File mode
- Source logical path (only if not secret)
- Status word (from state vocabulary)

**Advanced mode does NOT bypass redaction.** Advanced mode may show
additional diagnostic detail, but secrets and full hashes remain hidden.

---

## 21. Error States and Failure Policy

| Error state | Behavior |
|-------------|----------|
| Metadata file missing | Fail closed; backup not trusted |
| Metadata file invalid JSON | Fail closed; backup not trusted |
| Metadata schema version unknown | Fail closed; backup not trusted |
| Metadata `backup_id` mismatch | Fail closed; backup not trusted |
| Metadata `backup_sha256` mismatch | Fail closed; backup integrity failure |
| Metadata `source_sha256` mismatch | Fail closed; source identity failure |
| Metadata `backup_purpose` unknown | Fail closed; purpose not trusted |
| Metadata `profile_schema_marker` unknown | Fail closed; schema not trusted |
| Metadata `source_logical_path` mismatch | Fail closed; source path not trusted |
| Legacy backup (no metadata) | Fail closed for real rollback |
| Pre-rollback metadata write failure | Fail closed; no replace |
| Pre-rollback metadata validation failure | Fail closed; no replace |

**All failure states must:**

- Produce a safe error message (no raw content leakage).
- Report `manual_recovery_required: true` if in rollback context.
- Include redacted backup ID in error output.
- Include safe recovery guidance.

---

## 22. Future Test Strategy

Future tests should verify the metadata/provenance design without
implementing real `/etc` writes.

### tests/v2.2.5-profile-metadata-schema-doc.sh

**Purpose:** Verify the metadata schema design is complete.

**Assertions (future/mock):**

- Metadata schema contains `metadata_schema_version`.
- Metadata schema contains `backup_id`.
- Metadata schema contains `backup_purpose`.
- Metadata schema contains `created_at_utc`.
- Metadata schema contains `created_by_command`.
- Metadata schema contains `nanobk_version`.
- Metadata schema contains `source_logical_path`.
- Metadata schema contains `profile_schema_marker`.
- Metadata schema contains `source_sha256`.
- Metadata schema contains `backup_sha256`.
- Metadata schema contains `source_sha256_fingerprint`.
- Metadata schema contains `backup_sha256_fingerprint`.
- Metadata schema contains `backup_byte_for_byte`.
- Metadata schema contains `created_under_fake_root`.
- Metadata schema contains `real_etc_runtime`.
- `backup_purpose` is enum-only (`normal`, `pre_rollback`).

### tests/v2.2.5-profile-metadata-redaction-doc.sh

**Purpose:** Verify metadata output does not expose secrets.

**Assertions (future/mock):**

- User-facing output does not contain full SHA-256.
- User-facing output shows fingerprint only.
- Metadata does not contain raw tokens.
- Metadata does not contain private keys.
- Metadata does not contain protocol links.
- Metadata does not contain subscription URLs.
- Metadata does not contain raw env content.

### tests/v2.2.5-profile-metadata-legacy-fail-closed-doc.sh

**Purpose:** Verify legacy backup policy.

**Assertions (future/mock):**

- Legacy backups without metadata fail closed for real rollback.
- No `--accept-legacy-backup` exception exists.
- Legacy backups may be listed in advanced mode.
- Legacy backups are not accepted by automated rollback.

### tests/v2.2.5-profile-metadata-real-etc-gate-doc.sh

**Purpose:** Verify real `/etc` remains blocked.

**Assertions (future/mock):**

- Real `/etc` runtime is blocked.
- `real_etc_runtime` is `false` in all metadata.
- No real `/etc` write exists in codebase.
- Real `/etc` requires metadata implementation first.
- Real `/etc` requires lock design first.
- Real `/etc` requires explicit Owner approval.

---

## 23. Explicit Non-goals

v2.2.5 does **not**:

- Implement metadata sidecar runtime.
- Implement fake-root metadata write.
- Implement real `/etc` writes.
- Implement real rollback.
- Implement lock.
- Implement auto-restore.
- Modify `lib/nanobk_cf_dns_profile.py`.
- Modify runtime code.
- Modify `bin/nanobk`.
- Modify installer scripts.
- Modify Bot/Web runtime.
- Implement DNS mutation.
- Implement DNS-01.
- Implement Tunnel/Access.
- Create a release tag.

---

## 24. Acceptance Criteria

This document is accepted when:

1. All 24 sections are present and complete.
2. Scope decision is explicit (docs-only, no real `/etc`).
3. Metadata sidecar model is defined with file pair and validation rules.
4. All required metadata fields are specified.
5. Backup purpose policy is enum-only with fail-closed.
6. Source identity policy is comprehensive.
7. SHA-256/fingerprint policy distinguishes machine vs user-facing display.
8. Legacy backup fail-closed policy is explicit with no exceptions.
9. Fake-root implementation prerequisites are listed.
10. Real `/etc` runtime gate is explicit.
11. Rollback relationship is defined.
12. Lock relationship is defined.
13. Auto-restore relationship is defined.
14. Redaction/display rules are comprehensive.
15. Error states and failure policy are covered.
16. Future test strategy covers schema, redaction, legacy, and gate.
17. Non-goals are explicit.
18. No runtime code is changed.
19. No secrets or protocol links are printed.
