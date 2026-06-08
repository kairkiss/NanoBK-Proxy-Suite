# NanoBK Proxy Suite — v2.1.16 Production DNS Profile Guardrails Design Spec

## 1. Purpose

v2.1.14 introduced profile preview-only. v2.1.15 introduced temp-output profile
writer. v2.1.16 is a docs-only production path guardrails spec.

The future production target is:

```
/etc/nanobk/cloudflare-dns-profile.json
```

This spec does not implement production writing. This spec does not approve DNS
apply, Cloudflare mutation, Full Wizard integration, release, or tag.

## 2. Baseline

- Repository: https://github.com/kairkiss/NanoBK-Proxy-Suite
- Branch: main
- Baseline commit: 0780bcb5c7a07f657407e8b08136bdf1cb1874b0
- Baseline commit message: v2.1.15 polish profile finalize cleanup test
- Spec type: docs-only
- Runtime changes: none
- Release/tag: none

## 3. Current Temp-Output Writer State

v2.1.15 guarantees:

- Writes only allowed temp/test output paths.
- Blocks `/etc/nanobk`.
- Rejects existing output files.
- Rejects final symlink and unsafe symlink parents.
- Writes with mode `0600`.
- Validates before and after write.
- Uses no-overwrite finalization (hard-link, no rename fallback).
- Cleans temp file on post-write finalization failure.
- Dry-run hides raw zone/IP/path.
- CLI output hides raw IP/zone/hostname/path.
- No Cloudflare mutation.
- No DNS mutation.
- No `cf dns apply`.
- No `cf dns apply --check`.
- No Full Wizard integration.

## 4. Production Path Risk Model

| Risk | Description |
|------|-------------|
| Root/sudo behavior | Production path requires root; command must not call sudo internally |
| Parent directory ownership/mode | `/etc/nanobk` ownership and mode must be safe |
| Accidental overwrite | Existing profile must never be silently overwritten |
| Unsafe backup | Backup must succeed before replacement; first writer skips backup |
| Rollback ambiguity | Rollback story must be clear before replacement is allowed |
| Symlink race | Final path and parent must not be symlinks |
| Hard-link limitations | Some filesystems may not support hard links; fail closed |
| Partial file on failure | No partial final file on any failure path |
| Confusion with DNS apply | Local profile write must not be confused with DNS apply |
| Raw value leakage | Raw IP/domain/hostname/confirmation must not appear in output |
| Wrong zone/node/IP | Validation must catch invalid or mismatched values |
| Bad profile consumed by apply | Profile must validate before and after write |
| Full Wizard inconsistency | New CLI writer must not accidentally change Full Wizard behavior |
| Tests touching real `/etc` | Tests must use fake-root; real `/etc` must never be touched |

**Important:** The existing Full Wizard production writer uses older shell behavior
and must not be copied blindly into the new CLI production writer.

## 5. Recommended Production Command Shape

```
nanobk cf dns profile generate \
  --zone DOMAIN \
  --node NODE \
  --ipv4 VALUE \
  [--ipv6 VALUE] \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes \
  --allow-production-output \
  --confirm-hostname EXACT_HOSTNAME \
  [--json]
```

Rules:

- Same profile generate command family.
- `--yes` alone is insufficient for production.
- `--allow-production-output` required.
- `--confirm-hostname` required.
- Production remains CLI-only first.
- No beginner console integration.
- No Full Wizard integration.
- No Web/Bot integration.
- No DNS apply/check.
- No Cloudflare mutation.

## 6. Confirmation Model

- Expected confirmation is exact raw `${node}.${zone}`.
- User provides it via `--confirm-hostname`.
- Command compares internally.
- Command never prints the provided raw confirmation.
- Command never prints expected raw confirmation.
- Mismatch error: `confirmation hostname does not match target`.
- JSON may include `confirmation_required: true` and `confirmation_matched: false`.
- JSON must not include raw confirmation value.
- Dry-run must hide confirmation arg.
- Interactive prompt can be planned later, not first production writer.

## 7. Existing File / Overwrite Policy

First production writer policy:

- Existing `/etc/nanobk/cloudflare-dns-profile.json` means fail.
- No changes made.
- No overwrite.
- No replace.
- No backup in first writer.
- No `--replace`.
- No `--force`.
- Output says existing profile found and no changes were made.
- Replacement must wait for backup/rollback stage.

## 8. Backup and Rollback Model

Future, not implemented yet:

- Backup dir: `/etc/nanobk/backups`
- Backup filename: `cloudflare-dns-profile.json.YYYYMMDD-HHMMSS.<random>.bak`
- Backup mode `0600`.
- Backup must succeed before replacement.
- Rollback command planned separately.
- Backup/rollback must not print raw profile content.
- Backup path may be printed only as standard/redacted path.
- Backup/replace is not part of first production writer.

## 9. Parent Directory and Permissions Policy

- Production writer requires root privileges.
- Command must not call `sudo` internally.
- If not root, fail with: `root privileges are required for production profile path`.
- `/etc/nanobk` must be exact parent.
- If parent missing, first production writer should fail with guidance, or creation
  must be separately approved.
- Preferred first production writer: fail if parent missing.
- If later creation is approved:
  - Create exact `/etc/nanobk`.
  - Mode `0700`.
  - Root-owned when run as root.
  - Never loosen existing parent permissions automatically.
- If existing parent is symlink, fail.
- If existing parent ownership/mode is unsafe, fail.
- Do not auto-chown/chmod existing parent in first production writer.

## 10. Atomic Write Model

- Same-directory temp file.
- Mode `0600`.
- `fsync` file.
- Hard-link finalization for no-overwrite.
- No rename fallback.
- No replace fallback.
- `lstat` final path immediately before link.
- Fail closed if hard-link unsupported.
- Cleanup temp on failure.
- Verify final file mode `0600`.
- Re-read and validate final profile.
- `fsync` parent directory after successful link/unlink where practical.
- No partial final file on failure.

## 11. Output and JSON Contract

Production success should include:

```json
{
  "ok": true,
  "mutation": false,
  "local_file_mutation": true,
  "dns_mutation": false,
  "cloudflare_mutation": false,
  "dns_apply": false,
  "profile_written": true,
  "production_profile_written": true,
  "profile_write_mode": "production",
  "output_path_class": "production",
  "file_mode": "600",
  "backup_created": false,
  "confirmation_required": true,
  "confirmation_matched": true
}
```

Text must prominently say:

- Local production DNS profile was written.
- Raw IP values were stored and intentionally not printed.
- DNS has not been applied.
- No DNS records were created, updated, or deleted.
- Run validate/plan next; apply remains manual and separate.

Do not print:

- Raw IP.
- Raw zone/domain/hostname.
- Raw confirmation hostname.
- Raw profile content.
- Token/env/Authorization.
- Protocol/subscription URL.

## 12. Production Dry-Run Model

- Dry-run short-circuits before helper execution or production filesystem checks.
- Dry-run writes nothing.
- Dry-run does not read `/etc`.
- Dry-run hides raw zone/IP/confirm/path.
- Dry-run returns 0.
- Dry-run text: `[DRY-RUN] production DNS profile generation would run; raw inputs are hidden; no filesystem checks performed`.

## 13. Fake-Root Test Model

Future test-only hooks:

```
NANOBK_TEST_PRODUCTION_PROFILE_ROOT=/tmp/...
NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1
```

Rules:

- Fake-root only active when both env vars are set.
- Fake-root must resolve under temp root.
- Tests never touch real `/etc`.
- Production path is logically `/etc/nanobk/cloudflare-dns-profile.json`.
- Implementation maps it to: `$NANOBK_TEST_PRODUCTION_PROFILE_ROOT/etc/nanobk/cloudflare-dns-profile.json`.
- Output must still behave like production but not print raw fake path.
- If only one hook is set, fail.
- Fake-root is forbidden outside tests.

## 14. Production Writer Test Strategy

Future tests:

- Help text.
- Missing `--allow-production-output`.
- Missing `--confirm-hostname`.
- `--yes` alone insufficient.
- Confirmation mismatch sanitized.
- Dry-run hides raw zone/IP/confirm/path and performs no filesystem checks.
- Fake-root successful production write.
- File mode `0600`.
- Parent missing behavior.
- Parent symlink rejection.
- Unsafe parent mode/owner rejection if feasible.
- Existing production profile refusal.
- No overwrite.
- No replace.
- No backup in first writer.
- No raw IP/zone/confirm/path output.
- Profile validates after write.
- Source checks: no Cloudflare API, no apply/check, no HTTP mutation methods,
  no curl/wget, no external IP echo, no interface reads.
- Test proves real `/etc` not touched.

## 15. Interaction with Existing Components

- Temp writer remains unchanged.
- Preview remains unchanged.
- Production writer remains CLI-only.
- Beginner console does not auto-run it.
- Full Wizard remains unchanged.
- Web/Bot remain unchanged.
- DNS apply helper remains unchanged.
- Release/tag remains Owner-approved only.

## 16. Recommended Roadmap

- **v2.1.16** — production path guardrails design doc (this document)
- **v2.1.17** — fake-root production writer skeleton, no overwrite, no replace
- **v2.1.18** — backup/replace planning
- **v2.1.19** — backup/replace implementation or closeout, separately approved
- Full Wizard guidance-only planning remains deferred

## 17. Explicit Non-Goals

v2.1.16 does not implement:

- Production writer.
- Fake-root code.
- Backup.
- Replace.
- Rollback.
- Full Wizard integration.
- Web/Bot integration.
- DNS apply/check.
- Cloudflare mutation.
- Release/tag.
