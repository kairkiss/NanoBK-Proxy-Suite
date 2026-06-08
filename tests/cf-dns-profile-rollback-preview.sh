#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Rollback Preview Test
#
# Tests nanobk cf dns profile rollback preview under fake-root.
# Preview-only. No rollback execute. No real /etc.
#
# Usage:
#   bash tests/cf-dns-profile-rollback-preview.sh

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

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# ── Helpers ─────────────────────────────────────────────────────────────────

VALID_BACKUP_ID="cloudflare-dns-profile.json.20260608-120000.deadbeef.bak"

setup_fake_root() {
  local root="$1"
  mkdir -p "$root/etc/nanobk"
  chmod 700 "$root/etc/nanobk"
}

write_current_profile() {
  local root="$1"
  local content="${2:-}"
  if [[ -z "$content" ]]; then
    content='{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}'
  fi
  printf '%s' "$content" > "$root/etc/nanobk/cloudflare-dns-profile.json"
  chmod 600 "$root/etc/nanobk/cloudflare-dns-profile.json"
}

write_backup_profile() {
  local root="$1"
  local backup_id="$2"
  local content="${3:-}"
  if [[ -z "$content" ]]; then
    content='{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"198.51.100.20","defaultProxied":false}'
  fi
  mkdir -p "$root/etc/nanobk/backups"
  chmod 700 "$root/etc/nanobk/backups"
  printf '%s' "$content" > "$root/etc/nanobk/backups/$backup_id"
  chmod 600 "$root/etc/nanobk/backups/$backup_id"
}

run_rollback() {
  local extra_args=()
  local fake_root="$FAKE_ROOT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-fake-root) fake_root=""; shift ;;
      --fake-root) fake_root="$2"; shift 2 ;;
      *) extra_args+=("$1"); shift ;;
    esac
  done

  local env_args=()
  if [[ -n "$fake_root" ]]; then
    env_args+=("NANOBK_TEST_PRODUCTION_PROFILE_ROOT=$fake_root")
    env_args+=("NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1")
    env_args+=("NANOBK_TEST_TMPDIR=$TEST_TMPDIR")
  fi

  env "${env_args[@]}" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
    --backup-id "$VALID_BACKUP_ID" \
    --allow-production-output --confirm-hostname proxy.example.com \
    "${extra_args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Rollback Preview Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "rollback" "help mentions rollback"
assert_contains "$HELP_OUTPUT" "preview" "help mentions preview"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Real /etc blocked without fake-root ───────────────────────────────────

echo "--- B. Real /etc blocked without fake-root ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_contains "$NO_FAKE" "not enabled" "error says not enabled"

echo ""

# ── C. Partial fake-root hooks fail ─────────────────────────────────────────

echo "--- C. Partial fake-root hooks fail ---"
echo ""

PARTIAL1=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$PARTIAL1" '"ok": false' "only ROOT set fails"

PARTIAL2=$(NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$PARTIAL2" '"ok": false' "only ALLOW set fails"

echo ""

# ── D. Fake-root outside temp fails ─────────────────────────────────────────

echo "--- D. Fake-root outside temp fails ---"
echo ""

OUTSIDE_ROOT="/tmp/nanobk-outside-$$"
mkdir -p "$OUTSIDE_ROOT/etc/nanobk"
chmod 700 "$OUTSIDE_ROOT/etc/nanobk"
OUTSIDE_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$OUTSIDE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$OUTSIDE_OUT" '"ok": false' "outside-temp fails"
assert_not_contains "$OUTSIDE_OUT" "$OUTSIDE_ROOT" "no physical path"
rm -rf "$OUTSIDE_ROOT"

echo ""

# ── E. Current profile failures ─────────────────────────────────────────────

echo "--- E. Current profile failures ---"
echo ""

# Current missing
MISS_ROOT="$TEST_TMPDIR/miss-cur"
setup_fake_root "$MISS_ROOT"
write_backup_profile "$MISS_ROOT" "$VALID_BACKUP_ID"
MISS_CUR=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISS_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$MISS_CUR" '"ok": false' "current missing fails"
assert_contains "$MISS_CUR" "missing" "current missing error"

# Current symlink
SYM_ROOT="$TEST_TMPDIR/sym-cur"
setup_fake_root "$SYM_ROOT"
ln -sf /dev/null "$SYM_ROOT/etc/nanobk/cloudflare-dns-profile.json"
write_backup_profile "$SYM_ROOT" "$VALID_BACKUP_ID"
SYM_CUR=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYM_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$SYM_CUR" '"ok": false' "current symlink fails"
assert_contains "$SYM_CUR" "symlink_blocked" "current symlink status"

echo ""

# ── F. Backup dir failures ──────────────────────────────────────────────────

echo "--- F. Backup dir failures ---"
echo ""

# Backup dir missing
BDIR_MISS_ROOT="$TEST_TMPDIR/bdir-miss"
setup_fake_root "$BDIR_MISS_ROOT"
write_current_profile "$BDIR_MISS_ROOT"
BDIR_MISS=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_MISS_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BDIR_MISS" '"ok": false' "backup dir missing fails"

# Backup dir symlink
BDIR_SYM_ROOT="$TEST_TMPDIR/bdir-sym"
setup_fake_root "$BDIR_SYM_ROOT"
write_current_profile "$BDIR_SYM_ROOT"
ln -sf /tmp "$BDIR_SYM_ROOT/etc/nanobk/backups"
BDIR_SYM=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_SYM_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BDIR_SYM" '"ok": false' "backup dir symlink fails"

# Backup dir bad mode
BDIR_MODE_ROOT="$TEST_TMPDIR/bdir-mode"
setup_fake_root "$BDIR_MODE_ROOT"
write_current_profile "$BDIR_MODE_ROOT"
mkdir -p "$BDIR_MODE_ROOT/etc/nanobk/backups"
chmod 755 "$BDIR_MODE_ROOT/etc/nanobk/backups"
BDIR_MODE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BDIR_MODE" '"ok": false' "backup dir bad mode fails"

echo ""

# ── G. Backup profile failures ──────────────────────────────────────────────

echo "--- G. Backup profile failures ---"
echo ""

# Backup missing
BMISS_ROOT="$TEST_TMPDIR/bmiss"
setup_fake_root "$BMISS_ROOT"
write_current_profile "$BMISS_ROOT"
mkdir -p "$BMISS_ROOT/etc/nanobk/backups"
chmod 700 "$BMISS_ROOT/etc/nanobk/backups"
BMISS=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BMISS_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BMISS" '"ok": false' "backup missing fails"
assert_contains "$BMISS" "missing" "backup missing error"

# Backup invalid JSON
BINV_ROOT="$TEST_TMPDIR/binv"
setup_fake_root "$BINV_ROOT"
write_current_profile "$BINV_ROOT"
write_backup_profile "$BINV_ROOT" "$VALID_BACKUP_ID" '{broken'
BINV=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BINV_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BINV" '"ok": false' "backup invalid JSON fails"
assert_contains "$BINV" "not valid JSON" "backup invalid JSON error"
assert_not_contains "$BINV" "broken" "no raw content"

echo ""

# ── H. Backup ID validation ────────────────────────────────────────────────

echo "--- H. Backup ID validation ---"
echo ""

# Traversal
TRAVERSAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "../etc/passwd" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$TRAVERSAL" '"ok": false' "traversal rejected"
assert_not_contains "$TRAVERSAL" "etc/passwd" "no raw traversal path"

# Path separator
SLASH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "subdir/file.bak" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$SLASH" '"ok": false' "path separator rejected"

# Invalid format
BADFMT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "cloudflare-dns-profile.json.bad.bak" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BADFMT" '"ok": false' "invalid format rejected"

echo ""

# ── I. Missing/mismatch confirm ─────────────────────────────────────────────

echo "--- I. Missing/mismatch confirm ---"
echo ""

# Missing confirm
NO_CONF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --json 2>&1 || true)
assert_contains "$NO_CONF" '"ok": false' "missing confirm fails"

# Mismatch confirm (set up current profile and backup in FAKE_ROOT)
setup_fake_root "$FAKE_ROOT"
write_current_profile "$FAKE_ROOT"
write_backup_profile "$FAKE_ROOT" "$VALID_BACKUP_ID"
MISMATCH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname wrong.example.com \
  --json 2>&1 || true)
assert_contains "$MISMATCH" '"ok": false' "mismatch confirm fails"
assert_contains "$MISMATCH" "does not match" "mismatch confirm error"
assert_not_contains "$MISMATCH" "proxy.example.com" "no raw expected hostname"
assert_not_contains "$MISMATCH" "wrong.example.com" "no raw provided hostname"

echo ""

# ── J. Current/backup hostname mismatch ─────────────────────────────────────

echo "--- J. Hostname mismatch ---"
echo ""

MISMATCH_ROOT="$TEST_TMPDIR/hostname-mismatch"
setup_fake_root "$MISMATCH_ROOT"
write_current_profile "$MISMATCH_ROOT"
write_backup_profile "$MISMATCH_ROOT" "$VALID_BACKUP_ID" '{"zoneName":"other.com","nodePrefix":"web","ipv4":"203.0.113.10","defaultProxied":false}'
HOST_MISMATCH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISMATCH_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$HOST_MISMATCH" '"ok": false' "hostname mismatch fails"
assert_contains "$HOST_MISMATCH" "do not match" "hostname mismatch error"
assert_not_contains "$HOST_MISMATCH" "proxy.example.com" "no raw hostname"
assert_not_contains "$HOST_MISMATCH" "other.com" "no raw backup zone"

echo ""

# ── K. Valid rollback preview ───────────────────────────────────────────────

echo "--- K. Valid rollback preview ---"
echo ""

VALID_ROOT="$TEST_TMPDIR/valid-root"
setup_fake_root "$VALID_ROOT"
write_current_profile "$VALID_ROOT"
write_backup_profile "$VALID_ROOT" "$VALID_BACKUP_ID"

VALID_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$VALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1)

if echo "$VALID_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "valid rollback JSON is valid"
else
  fail "valid rollback JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$VALID_OUT" '"ok": true' "ok: true"
assert_contains "$VALID_OUT" '"rollback_preview": true' "rollback_preview: true"
assert_contains "$VALID_OUT" '"rollback_performed": false' "rollback_performed: false"
assert_contains "$VALID_OUT" '"profile_replaced": false' "profile_replaced: false"
assert_contains "$VALID_OUT" '"pre_rollback_backup_created": false' "pre_rollback_backup_created: false"
assert_contains "$VALID_OUT" '"local_file_mutation": false' "local_file_mutation: false"
assert_contains "$VALID_OUT" '"current_profile_status": "valid"' "current status valid"
assert_contains "$VALID_OUT" '"backup_profile_status": "valid"' "backup status valid"
assert_contains "$VALID_OUT" '"rollback_execute_ready": false' "execute not ready"
assert_contains "$VALID_OUT" '"rollback execute is not implemented"' "blocked reason"
assert_contains "$VALID_OUT" '"ipv4_changed": true' "IP changed detected"
assert_not_contains "$VALID_OUT" "203.0.113.10" "no raw current IP"
assert_not_contains "$VALID_OUT" "198.51.100.20" "no raw backup IP"
assert_not_contains "$VALID_OUT" "example.com" "no raw zone"
assert_not_contains "$VALID_OUT" "proxy.example.com" "no raw hostname"
assert_not_contains "$VALID_OUT" "$VALID_ROOT" "no physical path"

# Verify no files changed
if [[ ! -f "$VALID_ROOT/etc/nanobk/backups/new-backup.bak" ]]; then
  pass "no new backup file created"
else
  fail "new backup file was created"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── L. Dry-run ──────────────────────────────────────────────────────────────

echo "--- L. Dry-run ---"
echo ""

DRY_ROOT="$TEST_TMPDIR/dry-root"
setup_fake_root "$DRY_ROOT"
write_current_profile "$DRY_ROOT"

DRY_LOCAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "rollback_execute_ready" "dry-run does not execute helper"
assert_not_contains "$DRY_LOCAL" "$VALID_BACKUP_ID" "dry-run hides backup-id"

DRY_GLOBAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile rollback preview \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output --confirm-hostname proxy.example.com \
  2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "rollback_execute_ready" "global dry-run does not execute"

echo ""

# ── M. Source checks ────────────────────────────────────────────────────────

echo "--- M. Source checks ---"
echo ""

ROLLBACK_BLOCK=$(awk '/^# ── rollback-preview start/,/^# ── rollback-preview end/' "$ROOT/lib/nanobk_cf_dns_profile.py")

# No overwrite/replace primitives
assert_not_contains "$ROLLBACK_BLOCK" "os.replace(" "no os.replace"
assert_not_contains "$ROLLBACK_BLOCK" "os.rename(" "no os.rename"

# No mutation paths
assert_not_contains "$ROLLBACK_BLOCK" "cf dns apply" "no cf dns apply"
assert_not_contains "$ROLLBACK_BLOCK" "apply --check" "no apply --check"

# No HTTP mutation methods
assert_not_contains "$ROLLBACK_BLOCK" 'method="POST"' "no method=POST"
assert_not_contains "$ROLLBACK_BLOCK" 'method="PATCH"' "no method=PATCH"
assert_not_contains "$ROLLBACK_BLOCK" 'method="DELETE"' "no method=DELETE"
assert_not_contains "$ROLLBACK_BLOCK" 'method="PUT"' "no method=PUT"
assert_not_contains "$ROLLBACK_BLOCK" "method='POST'" "no method='POST'"
assert_not_contains "$ROLLBACK_BLOCK" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$ROLLBACK_BLOCK" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$ROLLBACK_BLOCK" "method='PUT'" "no method='PUT'"

# No external tools
assert_not_contains "$ROLLBACK_BLOCK" "curl" "no curl"
assert_not_contains "$ROLLBACK_BLOCK" "wget" "no wget"
assert_not_contains "$ROLLBACK_BLOCK" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$ROLLBACK_BLOCK" "ipify" "no ipify"
assert_not_contains "$ROLLBACK_BLOCK" "ident.me" "no ident.me"
assert_not_contains "$ROLLBACK_BLOCK" "icanhazip" "no icanhazip"
assert_not_contains "$ROLLBACK_BLOCK" "cloudflare.com/cdn-cgi" "no cloudflare trace"

# No interface reads
assert_not_contains "$ROLLBACK_BLOCK" "ip addr" "no ip addr"
assert_not_contains "$ROLLBACK_BLOCK" "ip route" "no ip route"
assert_not_contains "$ROLLBACK_BLOCK" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-rollback-preview tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
