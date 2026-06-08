# NanoBK Proxy Suite — v2.1.18 DNS Profile Backup / Replace Policy Design Spec

## 1. Purpose

v2.1.14 introduced profile preview-only. v2.1.15 introduced temp-output profile
writer. v2.1.16 documented production path guardrails. v2.1.17 introduced
fake-root production writer skeleton.

v2.1.18 is docs-only backup/replace policy design. v2.1.18 does not implement
backup, replace, rollback, replace preview, DNS apply/check, Cloudflare mutation,
Full Wizard integration, release, or tag.

## 2. Baseline

- Repository: https://github.com/kairkiss/NanoBK-Proxy-Suite
- Branch: main
- Baseline commit: fc03a9374966727c7f0162e1bc53c9c2ab6eab67
- Baseline commit message: v2.1.17 polish strict production profile path
- Spec type: docs-only
- Runtime changes: none
- Release/tag: none

## 3. Current v2.1.17 Fake-root Production Writer State

Current guarantees:

- Production path logic works only through fake-root tests.
- Real `/etc/nanobk/cloudflare-dns-profile.json` writes remain disabled.
- Fake-root requires:
  - `NANOBK_TEST_PRODUCTION_PROFILE_ROOT`
  - `NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1`
- Fake-root must be under temp root.
- Exact production path only: `/etc/nanobk/cloudflare-dns-profile.json`.
- Non-exact `/etc/nanobk/*` forbidden.
- `--yes` alone insufficient.
- `--allow-production-output` required.
- `--confirm-hostname` required.
- Confirmation mismatch sanitized.
- Parent missing/symlink/`0755` fails.
- Existing fake-root profile refused and unchanged.
- No overwrite.
- No replace.
- No backup.
- No DNS apply/check.
- No Cloudflare mutation.
- No Full Wizard integration.

## 4. Backup / Replace Risk Model

| Risk | Description |
|------|-------------|
| Accidental overwrite without valid backup | Replacement must never proceed without verified backup |
| Backup content corruption | Backup must be verified after copy |
| Backup wrong mode/owner | Backup file must be `0600`, owned by root in production |
| Backup directory symlink attack | Backup dir must not be a symlink |
| Backup source symlink attack | Source profile must not be a symlink |
| Backup path leakage | Backup path should be redacted in output |
| Raw profile content leakage | Backup/old/new content must never be printed |
| Rollback ambiguity | Rollback must be specified before replace is implemented |
| Backup succeeds but replacement fails | Must have clear recovery story |
| Replacement succeeds but post-write validation fails | Must have clear recovery story |
| Invalid existing profile policy ambiguity | Must define whether invalid profile blocks replace |
| Wrong profile later consumed by `cf dns apply` | Profile must validate before and after write |
| User confusion between local replacement and DNS apply | Clear messaging required |
| Tests accidentally touching real `/etc` | Tests must use fake-root; real `/etc` must never be touched |

**Important:** Replacement intentionally overwrites the final path, so it is a
different safety model from current no-overwrite generate.

## 5. Policy Decision

- v2.1.18 is docs-only.
- No backup implementation.
- No replace implementation.
- No rollback implementation.
- No replace preview skeleton.
- Replacement requires separate approved implementation stages.
- Any future implementation must be fake-root tested first.
- Real `/etc` replacement remains out of scope.

## 6. Command Design Recommendation

Recommend a separate command family, not `generate --replace`.

Future command family:

```
nanobk cf dns profile replace preview …
nanobk cf dns profile replace execute …
```

Rules:

- Current profile generate remains no-overwrite by default.
- No `--replace` on current generate command in v2.1.18.
- Replacement command is separate to reduce accidental flag creep.
- `--yes` alone is never enough.
- Exact hostname confirmation required.
- Explicit replace confirmation phrase required.
- Automatic backup mandatory before any replacement.
- Non-interactive CLI first.
- Interactive prompt deferred.

## 7. Replace Preview Model

Define future preview command behavior:

- Read existing profile only under fake-root / approved production mode.
- Do not write.
- Do not backup.
- Do not replace.
- Produce redacted old/new comparison.
- Raw IP/domain/hostname/profile content never printed.
- Old profile status values:
  - `valid`
  - `invalid_json`
  - `unreadable`
  - `unsupported_schema`
  - `symlink_blocked`
  - `non_regular_file`
- Invalid old profile blocks execute by default.
- Preview JSON includes:
  - `replace_preview: true`
  - `local_file_mutation: false`
  - `backup_required: true`
  - `old_profile_status`
  - `new_profile_valid`
  - `redacted_diff`

## 8. Backup Model

Define future backup semantics:

- Backup directory: `/etc/nanobk/backups`
- Fake-root mapping: `$FAKE_ROOT/etc/nanobk/backups`
- Filename: `cloudflare-dns-profile.json.YYYYMMDD-HHMMSS.<random>.bak`
- Backup directory mode: `0700`
- Backup file mode: `0600`
- Real production owner: `root`
- Fake-root owner: current test user
- Backup uses copy, not hard link.
- Reject symlink source.
- Reject non-regular source.
- Validate source readability before backup.
- Verify backup after copy using size/hash and JSON parse where practical.
- `fsync` backup file and backup parent directory where practical.
- Backup must complete before replacement.
- If backup fails, replacement is impossible.
- Backup content must never be printed.
- Backup path should be redacted or a standard reference.

## 9. Replace Execution Model

Define future replace sequence:

1. Validate parent directory safety.
2. Validate existing final path:
   - Regular file.
   - Not symlink.
   - Mode safe.
3. Read and classify existing profile status.
4. If existing profile invalid/unreadable, block by default.
5. Build and validate new profile candidate.
6. Create mandatory backup.
7. Verify backup.
8. Write new temp file in same directory with mode `0600`.
9. Validate temp file.
10. Re-check final path identity immediately before replace.
11. Use `os.replace()` only inside replace-specific flow after backup success.
12. Re-read and validate final file.
13. `fsync` final file and parent directory where practical.
14. Return redacted success output.

Clarify:

- `os.replace()` is forbidden in no-overwrite generate flow.
- `os.replace()` may only appear in future replace-specific implementation after backup succeeds.
- No `--force`.
- No delete.
- No DNS apply/check.

## 10. Rollback Model

Define rollback separately before replace execute is implemented.

Future command:

```
nanobk cf dns profile rollback --backup-id ID --confirm-hostname EXACT --yes
```

Rules:

- Rollback requires confirmation.
- Rollback refuses if current profile changed since backup/replace unless later override is planned.
- Rollback creates a pre-rollback backup.
- Rollback fake-root tested first.
- Rollback must not print raw profile or backup content.
- Replace execute should not be implemented until rollback behavior is specified and approved.

## 11. Redacted Diff / Summary Model

Define redacted comparison fields:

- Old profile status.
- New profile validity.
- Zone redacted.
- Hostname redacted.
- Node label may be shown only standalone.
- IPv4 masked.
- IPv6 masked.
- Stack mode.
- Record types.
- `defaultProxied` state.
- No raw IP.
- No raw zone/domain.
- No raw hostname.
- No raw profile content.
- No backup content.

## 12. Confirmation Model for Replacement

Require all of:

- `--yes`
- Exact hostname confirmation
- Explicit replace intent phrase, such as: `--confirm-replace-profile "replace profile"`
- Backup acknowledgement, either implicit through command design or explicit future confirmation

Rules:

- Exact hostname alone is not enough.
- `--yes` alone is not enough.
- Raw confirmation values are never printed.
- Mismatch errors are sanitized.

## 13. Fake-root Test Model

All future backup/replace tests must use fake-root:

- Same fake-root env hooks:
  - `NANOBK_TEST_PRODUCTION_PROFILE_ROOT`
  - `NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1`
- Backup dir maps under fake-root: `$FAKE_ROOT/etc/nanobk/backups`
- Tests pre-create:
  - `$FAKE_ROOT/etc/nanobk` mode `0700`
  - Existing profile mode `0600`
- Backup dir may be created by code with mode `0700`.
- Source symlink fails.
- Backup dir symlink fails.
- Non-regular source fails.
- Invalid JSON policy tested.
- Backup failure tested.
- Replace failure tested.
- Post-validation failure tested.
- Real `/etc` never touched.

## 14. JSON / Status Contract

For future replace preview JSON:

```json
{
  "ok": true,
  "mutation": false,
  "local_file_mutation": false,
  "dns_mutation": false,
  "cloudflare_mutation": false,
  "dns_apply": false,
  "replace_preview": true,
  "backup_required": true,
  "old_profile_status": "valid",
  "new_profile_valid": true,
  "redacted_diff": {}
}
```

For future replace execute success JSON:

```json
{
  "ok": true,
  "mutation": false,
  "local_file_mutation": true,
  "profile_replaced": true,
  "backup_created": true,
  "backup_mode": "600",
  "backup_path_redacted": "…",
  "rollback_available": true,
  "dns_mutation": false,
  "cloudflare_mutation": false,
  "dns_apply": false,
  "confirmation_required": true,
  "confirmation_matched": true
}
```

For failure JSON include:

- `profile_replaced: false`
- `backup_created: true/false`
- `rollback_attempted: true/false`
- `manual_recovery_required: true/false`
- Sanitized error.
- No raw profile/backup content.

## 15. Dry-run Model

Future replace dry-run must:

- Write nothing.
- Create no backup.
- Perform no helper execution for write-capable replacement.
- Not read real `/etc`.
- Hide raw zone/IP/confirmation/path.
- Return 0.
- Say no filesystem checks performed.

## 16. Source and Test Strategy

Future tests must assert:

- No Cloudflare API calls.
- No DNS apply/check.
- No external IP echo.
- No interface reads.
- No raw IP/domain/hostname/confirmation/profile/backup content.
- Backup files exist only under fake-root.
- Real `/etc` untouched.
- `os.replace()` only appears in replace-specific implementation/tests.
- Existing generate tests continue to prove no overwrite.
- No `--force`.
- No delete.
- Full Wizard, console, Web, Bot do not invoke replace.

## 17. Interaction with Existing Components

- Profile preview unchanged.
- Temp-output profile generate unchanged.
- Fake-root production no-overwrite writer unchanged.
- Full Wizard unchanged.
- Beginner console unchanged.
- Web/Bot unchanged.
- DNS apply helper unchanged.
- Release/tag remains Owner-approved only.

## 18. Recommended Roadmap

- **v2.1.18** — backup/replace policy design doc (this document)
- **v2.1.19** — replace preview skeleton, no write
- **v2.1.20** — backup-only fake-root skeleton
- **v2.1.21** — rollback policy/spec or rollback fake-root skeleton
- **v2.1.22** — replace execute fake-root skeleton with mandatory backup, only after rollback is approved
- **v2.1.23** — closeout and contract audit

## 19. Explicit Non-Goals

v2.1.18 does not implement:

- Backup command.
- Replace command.
- Rollback command.
- Replace preview.
- Backup files.
- Profile replacement.
- Real `/etc` changes.
- Cloudflare mutation.
- DNS mutation.
- DNS apply/check.
- Full Wizard integration.
- Web/Bot integration.
- Release/tag.
