#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Backup Metadata/Provenance Test
#
# Tests metadata sidecar creation, validation, legacy rejection,
# and rollback integration under fake-root.
# No real /etc. No lock. No auto-restore.
#
# Usage:
#   bash tests/cf-dns-profile-backup-metadata.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

# ── Temp dir cleanup ────────────────────────────────────────────────────────

TEST_TMPDIR=$(mktemp -d)
FAKE_ROOT="$TEST_TMPDIR/fake-root"
mkdir -p "$FAKE_ROOT"

cleanup() {
  rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (unexpected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── Helpers ─────────────────────────────────────────────────────────────────

setup_fake_root() {
  local root="$1"
  mkdir -p "$root/etc/nanobk"
  chmod 700 "$root/etc/nanobk"
}

write_source_profile() {
  local root="$1"
  printf '%s' '{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}' \
    > "$root/etc/nanobk/cloudflare-dns-profile.json"
  chmod 600 "$root/etc/nanobk/cloudflare-dns-profile.json"
}

run_backup() {
  local root="$1"
  shift
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$root" \
  NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 \
  NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
    bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
    --profile /etc/nanobk/cloudflare-dns-profile.json \
    --allow-production-output --confirm-hostname proxy.example.com \
    --yes "$@" 2>&1
}

run_rollback_preview() {
  local root="$1"
  local backup_id="$2"
  shift 2
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$root" \
  NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 \
  NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
    bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
    --backup-id "$backup_id" \
    --allow-production-output --confirm-hostname proxy.example.com \
    "$@" 2>&1
}

run_rollback_execute() {
  local root="$1"
  local backup_id="$2"
  shift 2
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$root" \
  NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 \
  NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
    bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
    --backup-id "$backup_id" \
    --allow-production-output --confirm-hostname proxy.example.com \
    --confirm-rollback-profile "rollback profile" \
    --yes "$@" 2>&1
}

get_backup_filename() {
  local root="$1"
  ls "$root/etc/nanobk/backups/"*.bak 2>/dev/null | head -1 | xargs basename
}

echo ""
echo "=== DNS Profile Backup Metadata/Provenance Test ==="
echo ""

# ── 1. Backup creates metadata sidecar ──────────────────────────────────────

echo "--- 1. Backup creates metadata sidecar ---"
echo ""

META_ROOT="$TEST_TMPDIR/meta-root"
setup_fake_root "$META_ROOT"
write_source_profile "$META_ROOT"

META_OUT=$(run_backup "$META_ROOT" --json)
assert_contains "$META_OUT" '"ok": true' "backup ok"
assert_contains "$META_OUT" '"metadata_created": true' "metadata_created: true"
assert_contains "$META_OUT" '"backup_sha256_fingerprint"' "fingerprint in result"

# Verify metadata file exists
BACKUP_DIR="$META_ROOT/etc/nanobk/backups"
META_FILE=$(ls "$BACKUP_DIR"/*.metadata.json 2>/dev/null | head -1)
if [[ -n "$META_FILE" ]]; then
  pass "metadata sidecar file exists"
else
  fail "metadata sidecar file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 2. Backup directory mode is 0700 ────────────────────────────────────────

echo "--- 2. Backup directory mode ---"
echo ""

DIR_MODE=$(stat -f '%Lp' "$BACKUP_DIR" 2>/dev/null || stat -c '%a' "$BACKUP_DIR" 2>/dev/null || echo "unknown")
if [[ "$DIR_MODE" == "700" ]]; then
  pass "backup directory mode is 0700"
else
  fail "backup directory mode is $DIR_MODE (expected 700)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 3. Backup file mode is 0600 ─────────────────────────────────────────────

echo "--- 3. Backup file mode ---"
echo ""

BACKUP_FILE=$(ls "$BACKUP_DIR"/*.bak 2>/dev/null | head -1)
BACKUP_MODE=$(stat -f '%Lp' "$BACKUP_FILE" 2>/dev/null || stat -c '%a' "$BACKUP_FILE" 2>/dev/null || echo "unknown")
if [[ "$BACKUP_MODE" == "600" ]]; then
  pass "backup file mode is 0600"
else
  fail "backup file mode is $BACKUP_MODE (expected 600)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 4. Metadata file mode is 0600 ───────────────────────────────────────────

echo "--- 4. Metadata file mode ---"
echo ""

META_MODE=$(stat -f '%Lp' "$META_FILE" 2>/dev/null || stat -c '%a' "$META_FILE" 2>/dev/null || echo "unknown")
if [[ "$META_MODE" == "600" ]]; then
  pass "metadata file mode is 0600"
else
  fail "metadata file mode is $META_MODE (expected 600)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 5. Metadata JSON contains all required fields ───────────────────────────

echo "--- 5. Metadata required fields ---"
echo ""

META_CONTENT=$(cat "$META_FILE")
for field in metadata_schema_version backup_id backup_purpose created_at_utc \
             created_by_command nanobk_version source_logical_path \
             source_path_kind profile_schema_marker profile_hostname_redacted \
             profile_fields_redacted source_file_mode source_owner_expected \
             source_size_bytes source_sha256 source_sha256_fingerprint \
             backup_file_mode backup_size_bytes backup_sha256 \
             backup_sha256_fingerprint backup_byte_for_byte \
             created_under_fake_root real_etc_runtime; do
  if echo "$META_CONTENT" | grep -q "\"$field\""; then
    pass "metadata has field: $field"
  else
    fail "metadata missing field: $field"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ── 6. Metadata backup_id matches backup filename ───────────────────────────

echo "--- 6. Metadata backup_id matches ---"
echo ""

BACKUP_FILENAME=$(basename "$BACKUP_FILE")
META_BACKUP_ID=$(echo "$META_CONTENT" | python3 -c "import json,sys; print(json.load(sys.stdin)['backup_id'])" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$META_BACKUP_ID" == "$BACKUP_FILENAME" ]]; then
  pass "metadata backup_id matches filename"
else
  fail "metadata backup_id mismatch: $META_BACKUP_ID != $BACKUP_FILENAME"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 7. Metadata backup_purpose=normal ────────────────────────────────────────

echo "--- 7. Metadata backup_purpose ---"
echo ""

META_PURPOSE=$(echo "$META_CONTENT" | python3 -c "import json,sys; print(json.load(sys.stdin)['backup_purpose'])" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$META_PURPOSE" == "normal" ]]; then
  pass "metadata backup_purpose is normal"
else
  fail "metadata backup_purpose is $META_PURPOSE (expected normal)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 8. Fingerprint in output, full sha256 not in output ──────────────────────

echo "--- 8. Fingerprint vs full sha256 ---"
echo ""

# Fingerprint should be in output
assert_contains "$META_OUT" '"backup_sha256_fingerprint"' "fingerprint in JSON output"

# Full sha256 should NOT be in user-facing output (64-char hex)
if echo "$META_OUT" | grep -Eq '[a-f0-9]{64}'; then
  fail "full sha256 not printed in user-facing output"
  ERRORS=$((ERRORS + 1))
else
  pass "full sha256 not printed in user-facing output"
fi

# Full sha256 IS allowed in metadata file (for machine validation)
if echo "$META_CONTENT" | grep -Eq '[a-f0-9]{64}'; then
  pass "full sha256 in metadata file (machine validation)"
else
  fail "full sha256 missing from metadata file"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 9. Metadata does not contain raw secrets ─────────────────────────────────

echo "--- 9. Metadata redaction ---"
echo ""

assert_not_contains "$META_CONTENT" "203.0.113.10" "no raw IP in metadata"
assert_not_contains "$META_CONTENT" "example.com" "no raw zone in metadata (masked)"
assert_not_contains "$META_CONTENT" "proxy.example.com" "no raw hostname in metadata (masked)"
assert_not_contains "$META_CONTENT" "token" "no token in metadata"
assert_not_contains "$META_CONTENT" "private" "no private in metadata"
assert_not_contains "$META_CONTENT" "hysteria2://" "no protocol link in metadata"
assert_not_contains "$META_CONTENT" "workers.dev" "no workers.dev in metadata"

echo ""

# ── 10. Rollback preview validates metadata and succeeds ────────────────────

echo "--- 10. Rollback preview with valid metadata ---"
echo ""

PREVIEW_OUT=$(run_rollback_preview "$META_ROOT" "$BACKUP_FILENAME" --json)
assert_contains "$PREVIEW_OUT" '"ok": true' "rollback preview ok"
assert_contains "$PREVIEW_OUT" '"metadata_validated": true' "metadata_validated: true"
assert_contains "$PREVIEW_OUT" '"metadata_summary"' "metadata_summary present"

echo ""

# ── 11. Rollback preview fails closed if metadata missing ───────────────────

echo "--- 11. Rollback preview fails on missing metadata ---"
echo ""

# Create a backup without metadata (simulate legacy)
LEGACY_ROOT="$TEST_TMPDIR/legacy-root"
setup_fake_root "$LEGACY_ROOT"
write_source_profile "$LEGACY_ROOT"

# Create backup manually (no metadata)
mkdir -p "$LEGACY_ROOT/etc/nanobk/backups"
chmod 700 "$LEGACY_ROOT/etc/nanobk/backups"
cp "$LEGACY_ROOT/etc/nanobk/cloudflare-dns-profile.json" \
   "$LEGACY_ROOT/etc/nanobk/backups/cloudflare-dns-profile.json.20260101-000000.aabbccdd.bak"
chmod 600 "$LEGACY_ROOT/etc/nanobk/backups/cloudflare-dns-profile.json.20260101-000000.aabbccdd.bak"

LEGACY_PREVIEW=$(run_rollback_preview "$LEGACY_ROOT" "cloudflare-dns-profile.json.20260101-000000.aabbccdd.bak" --json 2>&1 || true)
assert_contains "$LEGACY_PREVIEW" '"ok": false' "legacy backup preview fails"
assert_contains "$LEGACY_PREVIEW" "metadata" "error mentions metadata"

echo ""

# ── 12. Rollback preview fails closed if metadata invalid JSON ───────────────

echo "--- 12. Rollback preview fails on invalid metadata JSON ---"
echo ""

INVALID_META_ROOT="$TEST_TMPDIR/invalid-meta-root"
setup_fake_root "$INVALID_META_ROOT"
write_source_profile "$INVALID_META_ROOT"

# Run backup, then corrupt metadata
run_backup "$INVALID_META_ROOT" --json > /dev/null 2>&1
INVALID_BACKUP=$(ls "$INVALID_META_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
INVALID_BACKUP_ID=$(basename "$INVALID_BACKUP")
INVALID_META_PATH="${INVALID_BACKUP}.metadata.json"
echo "{invalid json" > "$INVALID_META_PATH"
chmod 600 "$INVALID_META_PATH"

INVALID_PREVIEW=$(run_rollback_preview "$INVALID_META_ROOT" "$INVALID_BACKUP_ID" --json 2>&1 || true)
assert_contains "$INVALID_PREVIEW" '"ok": false' "invalid metadata preview fails"
assert_contains "$INVALID_PREVIEW" "not valid JSON" "error says not valid JSON"

echo ""

# ── 13. Rollback preview fails closed if backup_id mismatch ─────────────────

echo "--- 13. Rollback preview fails on backup_id mismatch ---"
echo ""

MISMATCH_ROOT="$TEST_TMPDIR/mismatch-meta-root"
setup_fake_root "$MISMATCH_ROOT"
write_source_profile "$MISMATCH_ROOT"

run_backup "$MISMATCH_ROOT" --json > /dev/null 2>&1
MISMATCH_BACKUP=$(ls "$MISMATCH_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
MISMATCH_BACKUP_ID=$(basename "$MISMATCH_BACKUP")
MISMATCH_META_PATH="${MISMATCH_BACKUP}.metadata.json"

# Corrupt backup_id in metadata
python3 -c "
import json
with open('$MISMATCH_META_PATH') as f:
    d = json.load(f)
d['backup_id'] = 'wrong-id.bak'
with open('$MISMATCH_META_PATH', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
chmod 600 "$MISMATCH_META_PATH"

MISMATCH_PREVIEW=$(run_rollback_preview "$MISMATCH_ROOT" "$MISMATCH_BACKUP_ID" --json 2>&1 || true)
assert_contains "$MISMATCH_PREVIEW" '"ok": false' "backup_id mismatch preview fails"
assert_contains "$MISMATCH_PREVIEW" "backup_id" "error mentions backup_id"

echo ""

# ── 14. Rollback preview fails closed if backup_sha256 mismatch ─────────────

echo "--- 14. Rollback preview fails on sha256 mismatch ---"
echo ""

SHA_ROOT="$TEST_TMPDIR/sha-mismatch-root"
setup_fake_root "$SHA_ROOT"
write_source_profile "$SHA_ROOT"

run_backup "$SHA_ROOT" --json > /dev/null 2>&1
SHA_BACKUP=$(ls "$SHA_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
SHA_BACKUP_ID=$(basename "$SHA_BACKUP")
SHA_META_PATH="${SHA_BACKUP}.metadata.json"

# Corrupt sha256 in metadata
python3 -c "
import json
with open('$SHA_META_PATH') as f:
    d = json.load(f)
d['backup_sha256'] = '0' * 64
with open('$SHA_META_PATH', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
chmod 600 "$SHA_META_PATH"

SHA_PREVIEW=$(run_rollback_preview "$SHA_ROOT" "$SHA_BACKUP_ID" --json 2>&1 || true)
assert_contains "$SHA_PREVIEW" '"ok": false' "sha256 mismatch preview fails"
assert_contains "$SHA_PREVIEW" "sha256" "error mentions sha256"

echo ""

# ── 15. Rollback preview fails closed on unknown backup_purpose ─────────────

echo "--- 15. Rollback preview fails on unknown purpose ---"
echo ""

PURPOSE_ROOT="$TEST_TMPDIR/purpose-root"
setup_fake_root "$PURPOSE_ROOT"
write_source_profile "$PURPOSE_ROOT"

run_backup "$PURPOSE_ROOT" --json > /dev/null 2>&1
PURPOSE_BACKUP=$(ls "$PURPOSE_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
PURPOSE_BACKUP_ID=$(basename "$PURPOSE_BACKUP")
PURPOSE_META_PATH="${PURPOSE_BACKUP}.metadata.json"

# Corrupt purpose in metadata
python3 -c "
import json
with open('$PURPOSE_META_PATH') as f:
    d = json.load(f)
d['backup_purpose'] = 'unknown_purpose'
with open('$PURPOSE_META_PATH', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
chmod 600 "$PURPOSE_META_PATH"

PURPOSE_PREVIEW=$(run_rollback_preview "$PURPOSE_ROOT" "$PURPOSE_BACKUP_ID" --json 2>&1 || true)
assert_contains "$PURPOSE_PREVIEW" '"ok": false' "unknown purpose preview fails"
assert_contains "$PURPOSE_PREVIEW" "purpose" "error mentions purpose"

echo ""

# ── 16. Rollback execute creates pre_rollback backup with metadata ───────────

echo "--- 16. Rollback execute pre-rollback metadata ---"
echo ""

EXEC_ROOT="$TEST_TMPDIR/exec-root"
setup_fake_root "$EXEC_ROOT"
write_source_profile "$EXEC_ROOT"

# Create backup first
run_backup "$EXEC_ROOT" --json > /dev/null 2>&1
EXEC_BACKUP=$(ls "$EXEC_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
EXEC_BACKUP_ID=$(basename "$EXEC_BACKUP")

# Modify source so rollback actually changes something
printf '%s' '{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.20","defaultProxied":false}' \
  > "$EXEC_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$EXEC_ROOT/etc/nanobk/cloudflare-dns-profile.json"

EXEC_OUT=$(run_rollback_execute "$EXEC_ROOT" "$EXEC_BACKUP_ID" --json)
assert_contains "$EXEC_OUT" '"ok": true' "rollback execute ok"
assert_contains "$EXEC_OUT" '"pre_rollback_backup_created": true' "pre-rollback backup created"
assert_contains "$EXEC_OUT" '"pre_rollback_metadata_created": true' "pre-rollback metadata created"
assert_contains "$EXEC_OUT" '"pre_rollback_metadata_validated": true' "pre-rollback metadata validated"
assert_contains "$EXEC_OUT" '"backup_metadata_validated": true' "backup metadata validated"

# Verify pre-rollback metadata file exists
PRE_ROLLBACK_FILES=$(ls "$EXEC_ROOT/etc/nanobk/backups/"*pre-rollback*.metadata.json 2>/dev/null | wc -l)
if [[ "$PRE_ROLLBACK_FILES" -ge 1 ]]; then
  pass "pre-rollback metadata file exists"
else
  fail "pre-rollback metadata file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 17. Rollback execute fails closed if pre-rollback metadata fails ────────

echo "--- 17. Rollback execute fails on pre-rollback metadata failure ---"
echo ""

PRE_FAIL_ROOT="$TEST_TMPDIR/pre-fail-root"
setup_fake_root "$PRE_FAIL_ROOT"
write_source_profile "$PRE_FAIL_ROOT"

run_backup "$PRE_FAIL_ROOT" --json > /dev/null 2>&1
PRE_FAIL_BACKUP=$(ls "$PRE_FAIL_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | head -1)
PRE_FAIL_BACKUP_ID=$(basename "$PRE_FAIL_BACKUP")

# Modify source
printf '%s' '{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.30","defaultProxied":false}' \
  > "$PRE_FAIL_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$PRE_FAIL_ROOT/etc/nanobk/cloudflare-dns-profile.json"

PRE_FAIL_OUT=$(NANOBK_TEST_FORCE_PRE_ROLLBACK_METADATA_FAIL=1 \
  run_rollback_execute "$PRE_FAIL_ROOT" "$PRE_FAIL_BACKUP_ID" --json 2>&1 || true)
assert_contains "$PRE_FAIL_OUT" '"ok": false' "pre-rollback metadata fail causes rollback failure"
assert_contains "$PRE_FAIL_OUT" "metadata" "error mentions metadata"

echo ""

# ── 18. Legacy backup without metadata is rejected ──────────────────────────

echo "--- 18. Legacy backup rejection ---"
echo ""

# Already tested in #11, but verify the specific error
assert_contains "$LEGACY_PREVIEW" "legacy" "error mentions legacy"

echo ""

# ── 19. No --accept-legacy-backup ───────────────────────────────────────────

echo "--- 19. No --accept-legacy-backup flag ---"
echo ""

if grep -rq -- '--accept-legacy-backup' "$ROOT/lib/nanobk_cf_dns_profile.py" 2>/dev/null; then
  fail "--accept-legacy-backup exists in code"
  ERRORS=$((ERRORS + 1))
else
  pass "no --accept-legacy-backup in code"
fi

echo ""

# ── 20. Real /etc remains blocked ───────────────────────────────────────────

echo "--- 20. Real /etc blocked ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_not_contains "$NO_FAKE" "203.0.113.10" "no raw IP in error"

echo ""

# ── 21. Full sha256 not printed in user-facing output ───────────────────────

echo "--- 21. Full sha256 not in user-facing output ---"
echo ""

# Text output
TEXT_ROOT="$TEST_TMPDIR/text-root"
setup_fake_root "$TEXT_ROOT"
write_source_profile "$TEXT_ROOT"
TEXT_OUT=$(run_backup "$TEXT_ROOT")
if echo "$TEXT_OUT" | grep -Eq '[a-f0-9]{64}'; then
  fail "full sha256 not in text output"
  ERRORS=$((ERRORS + 1))
else
  pass "full sha256 not in text output"
fi
assert_contains "$TEXT_OUT" "sha256:" "fingerprint shown in text output"

echo ""

# ── 22. Exactly one os.replace() in rollback-execute marker block ────────────

echo "--- 22. os.replace() invariant ---"
echo ""

# Count os.replace in entire file
TOTAL_REPLACE=$(grep -c 'os.replace(' "$ROOT/lib/nanobk_cf_dns_profile.py" || true)
if [[ "$TOTAL_REPLACE" == "1" ]]; then
  pass "exactly one os.replace() in file"
else
  fail "expected 1 os.replace(), found $TOTAL_REPLACE"
  ERRORS=$((ERRORS + 1))
fi

# Verify it's inside rollback-execute marker block
MARKER_BLOCK=$(awk '/# rollback-execute start/,/# rollback-execute end/' "$ROOT/lib/nanobk_cf_dns_profile.py")
MARKER_REPLACE=$(echo "$MARKER_BLOCK" | grep -c 'os.replace(' || true)
if [[ "$MARKER_REPLACE" == "1" ]]; then
  pass "os.replace() inside rollback-execute marker block"
else
  fail "os.replace() not inside marker block"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 23. Zero os.replace() outside marker block ──────────────────────────────

echo "--- 23. Zero os.replace() outside marker block ---"
echo ""

# Remove marker block and check for os.replace
OUTSIDE_BLOCK=$(echo "$MARKER_BLOCK" | python3 -c "
import sys
text = sys.stdin.read()
# Remove the marker block content
" 2>/dev/null || true)

# Simpler: just verify total == marker count
if [[ "$TOTAL_REPLACE" == "$MARKER_REPLACE" ]]; then
  pass "no os.replace() outside marker block"
else
  fail "os.replace() found outside marker block"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 24. Zero os.rename() ────────────────────────────────────────────────────

echo "--- 24. Zero os.rename() ---"
echo ""

TOTAL_RENAME=$(grep -c 'os.rename(' "$ROOT/lib/nanobk_cf_dns_profile.py" || true)
if [[ "$TOTAL_RENAME" == "0" ]]; then
  pass "no os.rename() in file"
else
  fail "found $TOTAL_RENAME os.rename() calls"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-backup-metadata tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
