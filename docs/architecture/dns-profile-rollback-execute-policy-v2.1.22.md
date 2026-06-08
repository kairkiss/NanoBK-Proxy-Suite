# NanoBK Proxy Suite — v2.1.22 Rollback Execute Policy Spec

## 1. Purpose

Rollback execute will restore a selected backup profile over the current
production profile path. It is a local profile replacement operation, not DNS
mutation.

v2.1.21 implemented rollback preview (read-only comparison). v2.1.22 defines
the policy for rollback execute, which actually replaces the current profile
with a selected backup.

## 2. Non-Goals

- No DNS apply.
- No Cloudflare call.
- No real `/etc` enablement in first implementation.
- No Full Wizard integration.
- No Web/Bot integration.
- No auto-restore in first implementation.
- No raw content output.
- No release/tag.

## 3. Command Shape

Future command:

```
nanobk cf dns profile rollback execute \
  --backup-id BACKUP_ID \
  --allow-production-output \
  --confirm-hostname EXACT_HOSTNAME \
  --confirm-rollback-profile "rollback profile" \
  --yes \
  [--json]
```

Clarify:

- Preview and execute stay separate.
- `--yes` is mandatory.
- `--confirm-hostname` is mandatory.
- `--confirm-rollback-profile "rollback profile"` is mandatory and exact/case-sensitive.
- `--allow-production-output` is mandatory.
- Fake-root hooks are mandatory in first implementation.
- Real `/etc` rollback remains blocked.

## 4. Fake-Root Model

Use:

- `NANOBK_TEST_PRODUCTION_PROFILE_ROOT`
- `NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1`

Rules:

- Fake-root must be absolute.
- Fake-root must not be symlink.
- Fake-root must resolve under `NANOBK_TEST_TMPDIR` or system temp root.
- Physical fake-root paths must never be printed.
- Even root user cannot write real `/etc` in first implementation.

## 5. Backup ID Model

Rollback execute accepts backup filename only.

Pattern:

```
^cloudflare-dns-profile\.json\.[0-9]{8}-[0-9]{6}\.[0-9a-f]{8}\.bak$
```

Reject:

- Absolute paths.
- Slashes.
- `..`
- Subdirs.
- Weird suffixes.
- Physical paths.

Map only to fake-root backup dir.

## 6. Current Identity / Race Model

Issue:

- User can preview rollback.
- Current profile may change before execute.
- Executing may overwrite a changed current profile.

Policy decision:

- First fake-root execute skeleton does not require user-provided current hash.
- Execute performs fresh validation immediately before replacement.
- Execute creates verified pre-rollback backup immediately before replacement.
- Full sha256 is not printed.
- Future metadata/current identity guard is deferred.

## 7. Pre-Rollback Backup Model

Before replacing current profile, execute must create a pre-rollback backup.

Filename:

```
cloudflare-dns-profile.json.pre-rollback.YYYYMMDD-HHMMSS.<random>.bak
```

Rules:

- Backup dir `/etc/nanobk/backups`.
- Fake-root mapped only.
- Backup dir mode `0700`.
- Backup file mode `0600`.
- Byte-for-byte copy of current profile.
- Verify size/hash/JSON parse.
- `fsync` file and dir where practical.
- Fail closed if pre-backup fails.
- Output only redacted pre-backup id.
- No full sha256.
- No raw content.

## 8. Atomic Replace Model

Define strict sequence:

1. Validate fake-root.
2. Validate current parent mode `0700`.
3. Validate backup dir mode `0700`.
4. Validate current profile: exists, non-symlink, regular, mode `0600`, valid JSON, supported schema.
5. Validate selected backup profile: exists, non-symlink, regular, mode `0600`, valid JSON, supported schema.
6. Validate current/backup hostname match.
7. Validate confirmations.
8. Read selected backup bytes.
9. Create verified pre-rollback backup of current.
10. Create same-dir temp file with mode `0600`.
11. Write selected backup bytes.
12. `fsync` temp file.
13. Validate temp JSON/profile.
14. Re-stat current profile just before replace.
15. Use `os.replace(temp, current_profile)` only in rollback-execute block.
16. `fsync` parent directory where practical.
17. Re-read final profile.
18. Validate final profile.
19. Compare final bytes/hash to selected backup bytes.
20. Return success.

## 9. Allowed Replace Primitive

Policy:

- `os.replace()` is allowed only inside future rollback-execute start/end marker block.
- `os.rename()` remains banned.
- No `rm -f`, no force delete of final profile.
- Tests must source-check block scope.

## 10. Post-Replace Failure Policy

First implementation policy:

- Validate all known conditions before replace.
- If post-replace validation unexpectedly fails:
  - Do NOT auto-restore in first implementation.
  - Report `manual_recovery_required: true`.
  - Report `profile_replaced: true`.
  - Report `pre_rollback_backup_created: true`.
  - Include only redacted pre-backup id.
- Auto-restore requires a separate future policy/spec.

## 11. Confirmation Model

Require:

- `--yes`
- Exact `--confirm-hostname`
- Exact `--confirm-rollback-profile "rollback profile"`

JSON failure fields:

- `confirmation_required`
- `confirmation_matched`
- `rollback_phrase_required`
- `rollback_phrase_matched`

Never print raw expected/provided hostname or phrase.

## 12. Dry-Run Model

Global and command-level dry-run for execute must short-circuit in `bin/nanobk`.

Dry-run must:

- Return 0.
- Not execute helper.
- Not read current profile.
- Not read backup file.
- Not create pre-rollback backup.
- Not create temp file.
- Not replace profile.
- Hide raw backup-id / hostname / phrase.

## 13. JSON Contract

Success JSON:

```json
{
  "ok": true,
  "mutation": false,
  "local_file_mutation": true,
  "dns_mutation": false,
  "cloudflare_mutation": false,
  "dns_apply": false,
  "rollback_execute": true,
  "rollback_performed": true,
  "profile_replaced": true,
  "pre_rollback_backup_created": true,
  "current_profile_status_before": "valid",
  "backup_profile_status": "valid",
  "final_profile_status": "valid",
  "backup_id_redacted": "...",
  "pre_rollback_backup_id_redacted": "...",
  "confirmation_required": true,
  "confirmation_matched": true,
  "rollback_phrase_required": true,
  "rollback_phrase_matched": true,
  "production_fake_root": true,
  "manual_recovery_required": false
}
```

Failure states:

- Before pre-backup: `profile_replaced: false`, `pre_rollback_backup_created: false`.
- After pre-backup but before replace: `profile_replaced: false`, `pre_rollback_backup_created: true`.
- After replace but final validation failed: `profile_replaced: true`, `pre_rollback_backup_created: true`, `manual_recovery_required: true`.

## 14. Text Output Contract

Success text must say:

- Rollback executed under fake-root test mode.
- Current profile was replaced with selected backup profile.
- Pre-rollback backup was created.
- DNS has not been applied.
- Cloudflare was not called.
- Raw profile/backup content intentionally not printed.

Failure text must be sanitized.

## 15. Future Tests

Document future test file: `tests/cf-dns-profile-rollback-execute.sh`

Required coverage:

- Help.
- Real `/etc` blocked.
- Partial fake-root hooks fail.
- Fake-root outside temp fails.
- Backup-id traversal rejected.
- Missing `--yes`.
- Missing/mismatched hostname.
- Missing/mismatched rollback phrase.
- Invalid current/backup no-write.
- Hostname mismatch no-write.
- Pre-backup failure no replace.
- Temp write failure no replace.
- Success byte-for-byte restore.
- Pre-backup byte-for-byte current.
- Modes `0600`/`0700`.
- No raw output.
- Dry-run no helper execution.
- Failure hooks.
- Source checks.

## 16. Source-Check Strategy

Future implementation should add:

```
# rollback-execute start
...
# rollback-execute end
```

Tests should allow `os.replace(` only inside that block.

Ban:

- `os.rename(`
- `cf dns apply`
- `apply --check`
- `api.cloudflare.com`
- HTTP mutation methods
- `curl`/`wget`
- External IP echo
- Interface reads
- Raw path/content printing

## 17. Interaction with Future Replace Execute

- Rollback execute should come before replace execute.
- Rollback execute is simpler because target bytes are from an existing backup.
- Replace execute can later reuse pre-backup + temp + replace + validate framework.

## 18. Roadmap

- **v2.1.22** — rollback execute policy/spec only (this document)
- **v2.1.23** — fake-root rollback execute skeleton
- **v2.1.24** — rollback execute polish/failure hooks
- **v2.1.25** — replace execute planning
- **v2.1.26+** — fake-root replace execute
- Full Wizard integration still deferred

## 19. Explicit Non-Goals

v2.1.22 does not implement:

- Rollback execute.
- Replace execute.
- Pre-rollback backup.
- Profile replacement.
- Real `/etc` changes.
- Cloudflare mutation.
- DNS mutation.
- DNS apply/check.
- Full Wizard integration.
- Web/Bot integration.
- Release/tag.
