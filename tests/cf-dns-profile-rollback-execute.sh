#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Rollback Execute Test
#
# Tests nanobk cf dns profile rollback execute under fake-root.
# Fake-root only. No real /etc. No DNS apply/check. No Cloudflare calls.
#
# Usage:
#   bash tests/cf-dns-profile-rollback-execute.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"
PROFILE_PY="$ROOT/lib/nanobk_cf_dns_profile.py"

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
ROLLBACK_PHRASE="rollback profile"

# Profile A: current profile
PROFILE_A='{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}'
# Profile B: backup profile (different IP)
PROFILE_B='{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"198.51.100.20","defaultProxied":false}'

setup_fake_root() {
  local root="$1"
  mkdir -p "$root/etc/nanobk"
  chmod 700 "$root/etc/nanobk"
}

write_current_profile() {
  local root="$1"
  local content="${2:-$PROFILE_A}"
  printf '%s' "$content" > "$root/etc/nanobk/cloudflare-dns-profile.json"
  chmod 600 "$root/etc/nanobk/cloudflare-dns-profile.json"
}

write_backup_profile() {
  local root="$1"
  local backup_id="$2"
  local content="${3:-$PROFILE_B}"
  mkdir -p "$root/etc/nanobk/backups"
  chmod 700 "$root/etc/nanobk/backups"
  printf '%s' "$content" > "$root/etc/nanobk/backups/$backup_id"
  chmod 600 "$root/etc/nanobk/backups/$backup_id"
}

run_execute() {
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

  env "${env_args[@]}" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
    --backup-id "$VALID_BACKUP_ID" \
    --allow-production-output \
    --confirm-hostname proxy.example.com \
    --confirm-rollback-profile "$ROLLBACK_PHRASE" \
    --yes \
    "${extra_args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Rollback Execute Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(python3 "$PROFILE_PY" rollback execute --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "execute" "help mentions execute"
assert_contains "$HELP_OUTPUT" "confirm-rollback-profile" "help mentions confirm-rollback-profile"
assert_contains "$HELP_OUTPUT" "rollback" "help mentions rollback"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Real /etc blocked without fake-root ───────────────────────────────────

echo "--- B. Real /etc blocked without fake-root ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_contains "$NO_FAKE" "not enabled" "error says not enabled"

echo ""

# ── C. Partial fake-root hooks fail ─────────────────────────────────────────

echo "--- C. Partial fake-root hooks fail ---"
echo ""

PARTIAL1=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$PARTIAL1" '"ok": false' "only ROOT set fails"

PARTIAL2=$(NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$PARTIAL2" '"ok": false' "only ALLOW set fails"

echo ""

# ── D. Fake-root outside temp fails ─────────────────────────────────────────

echo "--- D. Fake-root outside temp fails ---"
echo ""

OUTSIDE_ROOT="/tmp/nanobk-outside-$$"
mkdir -p "$OUTSIDE_ROOT/etc/nanobk"
chmod 700 "$OUTSIDE_ROOT/etc/nanobk"
OUTSIDE_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$OUTSIDE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$OUTSIDE_OUT" '"ok": false' "outside-temp fails"
assert_not_contains "$OUTSIDE_OUT" "$OUTSIDE_ROOT" "no physical path"
rm -rf "$OUTSIDE_ROOT"

echo ""

# ── E. Backup ID traversal rejected ─────────────────────────────────────────

echo "--- E. Backup ID traversal rejected ---"
echo ""

TRAVERSAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "../etc/passwd" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$TRAVERSAL" '"ok": false' "traversal rejected"
assert_not_contains "$TRAVERSAL" "etc/passwd" "no raw traversal path"

SLASH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "subdir/file.bak" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$SLASH" '"ok": false' "path separator rejected"

BADFMT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "cloudflare-dns-profile.json.bad.bak" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BADFMT" '"ok": false' "invalid format rejected"

echo ""

# ── F. Missing --yes fails ──────────────────────────────────────────────────

echo "--- F. Missing --yes fails ---"
echo ""

NO_YES=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --json 2>&1 || true)
assert_contains "$NO_YES" '"ok": false' "missing --yes fails"
assert_contains "$NO_YES" "yes" "error mentions --yes"

echo ""

# ── G. Missing confirm-hostname fails ───────────────────────────────────────

echo "--- G. Missing confirm-hostname fails ---"
echo ""

NOCONF_ROOT="$TEST_TMPDIR/noconf"
setup_fake_root "$NOCONF_ROOT"
write_current_profile "$NOCONF_ROOT"
write_backup_profile "$NOCONF_ROOT" "$VALID_BACKUP_ID"
NO_CONF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$NOCONF_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$NO_CONF" '"ok": false' "missing confirm-hostname fails"
assert_contains "$NO_CONF" "confirmation_required" "has confirmation_required"
assert_contains "$NO_CONF" "confirmation_matched" "has confirmation_matched"

echo ""

# ── H. Confirm-hostname mismatch fails ──────────────────────────────────────

echo "--- H. Confirm-hostname mismatch fails ---"
echo ""

MISMATCH_ROOT="$TEST_TMPDIR/mismatch"
setup_fake_root "$MISMATCH_ROOT"
write_current_profile "$MISMATCH_ROOT"
write_backup_profile "$MISMATCH_ROOT" "$VALID_BACKUP_ID"
MISMATCH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISMATCH_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname wrong.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$MISMATCH" '"ok": false' "mismatch confirm fails"
assert_contains "$MISMATCH" "does not match" "mismatch error"
assert_not_contains "$MISMATCH" "proxy.example.com" "no raw expected hostname"
assert_not_contains "$MISMATCH" "wrong.example.com" "no raw provided hostname"

echo ""

# ── I. Missing rollback phrase fails ────────────────────────────────────────

echo "--- I. Missing rollback phrase fails ---"
echo ""

NOPHRASE_ROOT="$TEST_TMPDIR/nophrase"
setup_fake_root "$NOPHRASE_ROOT"
write_current_profile "$NOPHRASE_ROOT"
write_backup_profile "$NOPHRASE_ROOT" "$VALID_BACKUP_ID"
NO_PHRASE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$NOPHRASE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --yes --json 2>&1 || true)
assert_contains "$NO_PHRASE" '"ok": false' "missing phrase fails"
assert_contains "$NO_PHRASE" "rollback_phrase_required" "has rollback_phrase_required"
assert_contains "$NO_PHRASE" "rollback_phrase_matched" "has rollback_phrase_matched"

echo ""

# ── J. Rollback phrase mismatch fails ───────────────────────────────────────

echo "--- J. Rollback phrase mismatch fails ---"
echo ""

WRONGPHRASE_ROOT="$TEST_TMPDIR/wrongphrase"
setup_fake_root "$WRONGPHRASE_ROOT"
write_current_profile "$WRONGPHRASE_ROOT"
write_backup_profile "$WRONGPHRASE_ROOT" "$VALID_BACKUP_ID"
WRONG_PHRASE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$WRONGPHRASE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "wrong phrase" \
  --yes --json 2>&1 || true)
assert_contains "$WRONG_PHRASE" '"ok": false' "wrong phrase fails"
assert_contains "$WRONG_PHRASE" "does not match" "phrase mismatch error"
assert_not_contains "$WRONG_PHRASE" "rollback profile" "no raw phrase in output"

echo ""

# ── K. Invalid current no-write ─────────────────────────────────────────────

echo "--- K. Invalid current no-write ---"
echo ""

# Invalid JSON
INV_CUR_ROOT="$TEST_TMPDIR/inv-cur"
setup_fake_root "$INV_CUR_ROOT"
echo '{broken' > "$INV_CUR_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$INV_CUR_ROOT/etc/nanobk/cloudflare-dns-profile.json"
write_backup_profile "$INV_CUR_ROOT" "$VALID_BACKUP_ID"
INV_CUR=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$INV_CUR_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$INV_CUR" '"ok": false' "current invalid JSON fails"
assert_contains "$INV_CUR" "not valid JSON" "current invalid JSON error"
assert_not_contains "$INV_CUR" "broken" "no raw content"
assert_contains "$INV_CUR" '"profile_replaced": false' "no replace on invalid current"

# Unsupported schema
UNSUP_CUR_ROOT="$TEST_TMPDIR/unsup-cur"
setup_fake_root "$UNSUP_CUR_ROOT"
echo '{"secretToken":"abc","nodePrefix":"proxy"}' > "$UNSUP_CUR_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$UNSUP_CUR_ROOT/etc/nanobk/cloudflare-dns-profile.json"
write_backup_profile "$UNSUP_CUR_ROOT" "$VALID_BACKUP_ID"
UNSUP_CUR=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$UNSUP_CUR_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$UNSUP_CUR" '"ok": false' "current unsupported schema fails"
assert_not_contains "$UNSUP_CUR" "abc" "no raw secret value"

# Bad mode
MODE_CUR_ROOT="$TEST_TMPDIR/mode-cur"
setup_fake_root "$MODE_CUR_ROOT"
write_current_profile "$MODE_CUR_ROOT"
chmod 644 "$MODE_CUR_ROOT/etc/nanobk/cloudflare-dns-profile.json"
write_backup_profile "$MODE_CUR_ROOT" "$VALID_BACKUP_ID"
MODE_CUR=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MODE_CUR_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$MODE_CUR" '"ok": false' "current bad mode fails"
assert_contains "$MODE_CUR" "mode_invalid" "current mode invalid status"

echo ""

# ── L. Invalid backup no-write ──────────────────────────────────────────────

echo "--- L. Invalid backup no-write ---"
echo ""

# Missing backup
BMISS_ROOT="$TEST_TMPDIR/bmiss"
setup_fake_root "$BMISS_ROOT"
write_current_profile "$BMISS_ROOT"
mkdir -p "$BMISS_ROOT/etc/nanobk/backups"
chmod 700 "$BMISS_ROOT/etc/nanobk/backups"
BMISS=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BMISS_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BMISS" '"ok": false' "backup missing fails"
assert_contains "$BMISS" "missing" "backup missing error"

# Invalid JSON
BINV_ROOT="$TEST_TMPDIR/binv"
setup_fake_root "$BINV_ROOT"
write_current_profile "$BINV_ROOT"
write_backup_profile "$BINV_ROOT" "$VALID_BACKUP_ID" '{broken'
BINV=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BINV_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BINV" '"ok": false' "backup invalid JSON fails"
assert_not_contains "$BINV" "broken" "no raw content"

# Unsupported schema
BUNSUP_ROOT="$TEST_TMPDIR/bunsup"
setup_fake_root "$BUNSUP_ROOT"
write_current_profile "$BUNSUP_ROOT"
mkdir -p "$BUNSUP_ROOT/etc/nanobk/backups"
chmod 700 "$BUNSUP_ROOT/etc/nanobk/backups"
echo '{"secretToken":"abc","nodePrefix":"proxy"}' > "$BUNSUP_ROOT/etc/nanobk/backups/$VALID_BACKUP_ID"
chmod 600 "$BUNSUP_ROOT/etc/nanobk/backups/$VALID_BACKUP_ID"
BUNSUP=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BUNSUP_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BUNSUP" '"ok": false' "backup unsupported schema fails"
assert_not_contains "$BUNSUP" "abc" "no raw secret value"

# Bad mode
BMODE_ROOT="$TEST_TMPDIR/bmode"
setup_fake_root "$BMODE_ROOT"
write_current_profile "$BMODE_ROOT"
write_backup_profile "$BMODE_ROOT" "$VALID_BACKUP_ID"
chmod 644 "$BMODE_ROOT/etc/nanobk/backups/$VALID_BACKUP_ID"
BMODE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BMODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BMODE" '"ok": false' "backup bad mode fails"
assert_contains "$BMODE" "mode_invalid" "backup mode invalid status"

echo ""

# ── M. Current/backup hostname mismatch no-write ────────────────────────────

echo "--- M. Current/backup hostname mismatch ---"
echo ""

MISMATCH_ROOT="$TEST_TMPDIR/hostname-mismatch"
setup_fake_root "$MISMATCH_ROOT"
write_current_profile "$MISMATCH_ROOT"
write_backup_profile "$MISMATCH_ROOT" "$VALID_BACKUP_ID" '{"zoneName":"other.com","nodePrefix":"web","ipv4":"203.0.113.10","defaultProxied":false}'
HOST_MISMATCH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISMATCH_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$HOST_MISMATCH" '"ok": false' "hostname mismatch fails"
assert_contains "$HOST_MISMATCH" "do not match" "hostname mismatch error"
assert_not_contains "$HOST_MISMATCH" "other.com" "no raw backup zone"

echo ""

# ── N. Backup dir bad cases ─────────────────────────────────────────────────

echo "--- N. Backup dir bad cases ---"
echo ""

# Backup dir symlink
BDIR_SYM_ROOT="$TEST_TMPDIR/bdir-sym"
setup_fake_root "$BDIR_SYM_ROOT"
write_current_profile "$BDIR_SYM_ROOT"
ln -sf /tmp "$BDIR_SYM_ROOT/etc/nanobk/backups"
BDIR_SYM=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_SYM_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BDIR_SYM" '"ok": false' "backup dir symlink fails"

# Backup dir regular file
BDIR_FILE_ROOT="$TEST_TMPDIR/bdir-file"
setup_fake_root "$BDIR_FILE_ROOT"
write_current_profile "$BDIR_FILE_ROOT"
echo "not a dir" > "$BDIR_FILE_ROOT/etc/nanobk/backups"
BDIR_FILE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_FILE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BDIR_FILE" '"ok": false' "backup dir regular file fails"

# Backup dir bad mode
BDIR_MODE_ROOT="$TEST_TMPDIR/bdir-mode"
setup_fake_root "$BDIR_MODE_ROOT"
write_current_profile "$BDIR_MODE_ROOT"
mkdir -p "$BDIR_MODE_ROOT/etc/nanobk/backups"
chmod 755 "$BDIR_MODE_ROOT/etc/nanobk/backups"
BDIR_MODE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$BDIR_MODE" '"ok": false' "backup dir bad mode fails"

echo ""

# ── O. Successful rollback ──────────────────────────────────────────────────

echo "--- O. Successful rollback ---"
echo ""

VALID_ROOT="$TEST_TMPDIR/valid-root"
setup_fake_root "$VALID_ROOT"
write_current_profile "$VALID_ROOT" "$PROFILE_A"
write_backup_profile "$VALID_ROOT" "$VALID_BACKUP_ID" "$PROFILE_B"

VALID_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$VALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1)

# Validate JSON
if echo "$VALID_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "valid execute JSON is valid"
else
  fail "valid execute JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$VALID_OUT" '"ok": true' "ok: true"
assert_contains "$VALID_OUT" '"rollback_execute": true' "rollback_execute: true"
assert_contains "$VALID_OUT" '"rollback_performed": true' "rollback_performed: true"
assert_contains "$VALID_OUT" '"profile_replaced": true' "profile_replaced: true"
assert_contains "$VALID_OUT" '"pre_rollback_backup_created": true' "pre_rollback_backup_created: true"
assert_contains "$VALID_OUT" '"manual_recovery_required": false' "manual_recovery_required: false"
assert_contains "$VALID_OUT" '"local_file_mutation": true' "local_file_mutation: true"
assert_contains "$VALID_OUT" '"current_profile_status_before": "valid"' "current status before valid"
assert_contains "$VALID_OUT" '"backup_profile_status": "valid"' "backup status valid"
assert_contains "$VALID_OUT" '"final_profile_status": "valid"' "final status valid"
assert_contains "$VALID_OUT" '"current_identity_checked": true' "identity checked"
assert_contains "$VALID_OUT" '"confirmation_required": true' "confirmation_required"
assert_contains "$VALID_OUT" '"confirmation_matched": true' "confirmation_matched"
assert_contains "$VALID_OUT" '"rollback_phrase_required": true' "rollback_phrase_required"
assert_contains "$VALID_OUT" '"rollback_phrase_matched": true' "rollback_phrase_matched"
assert_contains "$VALID_OUT" '"production_fake_root": true' "production_fake_root"

# Verify final profile byte-for-byte equals PROFILE_B
FINAL_PROFILE="$VALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
FINAL_BYTES=$(cat "$FINAL_PROFILE")
EXPECTED_BYTES=$(printf '%s' "$PROFILE_B")
if [[ "$FINAL_BYTES" == "$EXPECTED_BYTES" ]]; then
  pass "final profile equals selected backup (byte-for-byte)"
else
  fail "final profile does not equal selected backup"
  ERRORS=$((ERRORS + 1))
fi

# Verify pre-rollback backup exists and equals original PROFILE_A
PRE_BACKUP=$(ls "$VALID_ROOT/etc/nanobk/backups/" | grep "pre-rollback" | head -1)
if [[ -n "$PRE_BACKUP" ]]; then
  pass "pre-rollback backup exists"
  PRE_BACKUP_BYTES=$(cat "$VALID_ROOT/etc/nanobk/backups/$PRE_BACKUP")
  EXPECTED_A=$(printf '%s' "$PROFILE_A")
  if [[ "$PRE_BACKUP_BYTES" == "$EXPECTED_A" ]]; then
    pass "pre-rollback backup equals original current (byte-for-byte)"
  else
    fail "pre-rollback backup does not equal original current"
    ERRORS=$((ERRORS + 1))
  fi

  # Check pre-backup mode
  PRE_MODE=$(stat -f '%Lp' "$VALID_ROOT/etc/nanobk/backups/$PRE_BACKUP" 2>/dev/null || stat -c '%a' "$VALID_ROOT/etc/nanobk/backups/$PRE_BACKUP" 2>/dev/null)
  if [[ "$PRE_MODE" == "600" ]]; then
    pass "pre-rollback backup mode is 0600"
  else
    fail "pre-rollback backup mode is $PRE_MODE (expected 600)"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "pre-rollback backup not found"
  ERRORS=$((ERRORS + 1))
fi

# Check backup dir mode
BDIR_MODE=$(stat -f '%Lp' "$VALID_ROOT/etc/nanobk/backups" 2>/dev/null || stat -c '%a' "$VALID_ROOT/etc/nanobk/backups" 2>/dev/null)
if [[ "$BDIR_MODE" == "700" ]]; then
  pass "backup dir mode is 0700"
else
  fail "backup dir mode is $BDIR_MODE (expected 700)"
  ERRORS=$((ERRORS + 1))
fi

# No raw values in output
assert_not_contains "$VALID_OUT" "203.0.113.10" "no raw current IP"
assert_not_contains "$VALID_OUT" "198.51.100.20" "no raw backup IP"
assert_not_contains "$VALID_OUT" "example.com" "no raw zone"
assert_not_contains "$VALID_OUT" "proxy.example.com" "no raw hostname"
assert_not_contains "$VALID_OUT" "$VALID_ROOT" "no physical path"
assert_not_contains "$VALID_OUT" "rollback profile" "no raw rollback phrase in JSON"
# backup_id_redacted contains the full filename (that IS the id), so deadbeef is expected there
assert_contains "$VALID_OUT" "backup_id_redacted" "has backup_id_redacted field"

# Text output test
VALID_TEXT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$VALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes 2>&1)
assert_contains "$VALID_TEXT" "Rollback executed under fake-root test mode" "text success message"
assert_contains "$VALID_TEXT" "replaced with selected backup" "text replaced message"
assert_contains "$VALID_TEXT" "Pre-rollback backup was created" "text pre-backup message"
assert_contains "$VALID_TEXT" "DNS has not been applied" "text no DNS apply"
assert_contains "$VALID_TEXT" "Cloudflare was not called" "text no Cloudflare"
assert_not_contains "$VALID_TEXT" "203.0.113.10" "text no raw current IP"
assert_not_contains "$VALID_TEXT" "198.51.100.20" "text no raw backup IP"

echo ""

# ── P. Dry-run ──────────────────────────────────────────────────────────────

echo "--- P. Dry-run ---"
echo ""

DRY_ROOT="$TEST_TMPDIR/dry-root"
setup_fake_root "$DRY_ROOT"
write_current_profile "$DRY_ROOT"

# Command-level dry-run
DRY_CMD=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --dry-run 2>&1)
assert_contains "$DRY_CMD" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_CMD" "rollback_execute" "dry-run does not execute helper"
assert_not_contains "$DRY_CMD" "$VALID_BACKUP_ID" "dry-run hides backup-id"
assert_not_contains "$DRY_CMD" "proxy.example.com" "dry-run hides hostname"
assert_not_contains "$DRY_CMD" "rollback profile" "dry-run hides rollback phrase"

# Global dry-run
DRY_GLOBAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "rollback_execute" "global dry-run does not execute"

# Verify no files changed after dry-run
if [[ ! -f "$DRY_ROOT/etc/nanobk/backups/"*pre-rollback* ]]; then
  pass "no pre-rollback backup after dry-run"
else
  fail "pre-rollback backup created during dry-run"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Q. Failure hooks ────────────────────────────────────────────────────────

echo "--- Q. Failure hooks ---"
echo ""

# Q-A: PREBACKUP_FAIL
QPA_ROOT="$TEST_TMPDIR/qpa"
setup_fake_root "$QPA_ROOT"
write_current_profile "$QPA_ROOT"
write_backup_profile "$QPA_ROOT" "$VALID_BACKUP_ID"
QPA_OUT=$(NANOBK_TEST_FORCE_ROLLBACK_PREBACKUP_FAIL=1 \
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$QPA_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$QPA_OUT" '"ok": false' "PREBACKUP_FAIL: ok false"
assert_contains "$QPA_OUT" '"profile_replaced": false' "PREBACKUP_FAIL: no replace"
assert_contains "$QPA_OUT" '"pre_rollback_backup_created": false' "PREBACKUP_FAIL: no pre-backup"
assert_contains "$QPA_OUT" "test hook" "PREBACKUP_FAIL: test hook message"

# Q-B: AFTER_PREBACKUP_FAIL
QPB_ROOT="$TEST_TMPDIR/qpb"
setup_fake_root "$QPB_ROOT"
write_current_profile "$QPB_ROOT"
write_backup_profile "$QPB_ROOT" "$VALID_BACKUP_ID"
QPB_OUT=$(NANOBK_TEST_FORCE_ROLLBACK_AFTER_PREBACKUP_FAIL=1 \
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$QPB_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$QPB_OUT" '"ok": false' "AFTER_PREBACKUP_FAIL: ok false"
assert_contains "$QPB_OUT" '"pre_rollback_backup_created": true' "AFTER_PREBACKUP_FAIL: pre-backup created"
assert_contains "$QPB_OUT" '"profile_replaced": false' "AFTER_PREBACKUP_FAIL: no replace"
assert_contains "$QPB_OUT" '"local_file_mutation": true' "AFTER_PREBACKUP_FAIL: local mutation"
assert_contains "$QPB_OUT" '"manual_recovery_required": false' "AFTER_PREBACKUP_FAIL: no manual recovery"

# Q-C: TEMP_WRITE_FAIL
QPC_ROOT="$TEST_TMPDIR/qpc"
setup_fake_root "$QPC_ROOT"
write_current_profile "$QPC_ROOT"
write_backup_profile "$QPC_ROOT" "$VALID_BACKUP_ID"
QPC_OUT=$(NANOBK_TEST_FORCE_ROLLBACK_TEMP_WRITE_FAIL=1 \
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$QPC_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$QPC_OUT" '"ok": false' "TEMP_WRITE_FAIL: ok false"
assert_contains "$QPC_OUT" '"profile_replaced": false' "TEMP_WRITE_FAIL: no replace"

# Q-D: AFTER_TEMP_WRITE_FAIL
QPD_ROOT="$TEST_TMPDIR/qpd"
setup_fake_root "$QPD_ROOT"
write_current_profile "$QPD_ROOT"
write_backup_profile "$QPD_ROOT" "$VALID_BACKUP_ID"
QPD_OUT=$(NANOBK_TEST_FORCE_ROLLBACK_AFTER_TEMP_WRITE_FAIL=1 \
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$QPD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$QPD_OUT" '"ok": false' "AFTER_TEMP_WRITE_FAIL: ok false"
assert_contains "$QPD_OUT" '"profile_replaced": false' "AFTER_TEMP_WRITE_FAIL: no replace"

# Q-E: AFTER_REPLACE_VALIDATE_FAIL
QPE_ROOT="$TEST_TMPDIR/qpe"
setup_fake_root "$QPE_ROOT"
write_current_profile "$QPE_ROOT"
write_backup_profile "$QPE_ROOT" "$VALID_BACKUP_ID"
QPE_OUT=$(NANOBK_TEST_FORCE_ROLLBACK_AFTER_REPLACE_VALIDATE_FAIL=1 \
  NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$QPE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile rollback execute \
  --backup-id "$VALID_BACKUP_ID" \
  --allow-production-output \
  --confirm-hostname proxy.example.com \
  --confirm-rollback-profile "$ROLLBACK_PHRASE" \
  --yes --json 2>&1 || true)
assert_contains "$QPE_OUT" '"ok": false' "AFTER_REPLACE_VALIDATE_FAIL: ok false"
assert_contains "$QPE_OUT" '"profile_replaced": true' "AFTER_REPLACE_VALIDATE_FAIL: replaced"
assert_contains "$QPE_OUT" '"pre_rollback_backup_created": true' "AFTER_REPLACE_VALIDATE_FAIL: pre-backup"
assert_contains "$QPE_OUT" '"manual_recovery_required": true' "AFTER_REPLACE_VALIDATE_FAIL: manual recovery"

echo ""

# ── R. Current identity guard ───────────────────────────────────────────────

echo "--- R. Current identity guard ---"
echo ""

# This is best tested via the AFTER_PREBACKUP_FAIL hook which triggers
# between pre-backup creation and the replace. If the identity check
# passes (as it does in the hook), the pre-backup is reported as created.
# A real identity change would require filesystem-level race simulation.
# The hook test in Q-B validates the code path exists.
assert_contains "$QPB_OUT" '"current_identity_checked": true' "identity checked in after-prebackup path"

echo ""

# ── S. Source checks ────────────────────────────────────────────────────────

echo "--- S. Source checks ---"
echo ""

EXECUTE_BLOCK=$(awk '/^# ── rollback-execute start/,/^# ── rollback-execute end/' "$PROFILE_PY")

# Exactly one os.replace inside the marker block
REPLACE_COUNT=$(echo "$EXECUTE_BLOCK" | grep -c "os\.replace(" || true)
if [[ "$REPLACE_COUNT" -eq 1 ]]; then
  pass "exactly one os.replace in rollback-execute block"
else
  fail "expected 1 os.replace, found $REPLACE_COUNT"
  ERRORS=$((ERRORS + 1))
fi

# No os.replace outside the marker block
OUTSIDE_BLOCK=$(awk '
  /^# ── rollback-execute start/ { inside=1; next }
  /^# ── rollback-execute end/ { inside=0; next }
  !inside { print }
' "$PROFILE_PY")
OUTSIDE_REPLACE=$(echo "$OUTSIDE_BLOCK" | grep -c "os\.replace(" || true)
if [[ "$OUTSIDE_REPLACE" -eq 0 ]]; then
  pass "no os.replace outside rollback-execute block"
else
  fail "found os.replace outside rollback-execute block"
  ERRORS=$((ERRORS + 1))
fi

# No os.rename anywhere in the execute block
assert_not_contains "$EXECUTE_BLOCK" "os.rename(" "no os.rename in execute block"

# No cf dns apply
assert_not_contains "$EXECUTE_BLOCK" "cf dns apply" "no cf dns apply"
assert_not_contains "$EXECUTE_BLOCK" "apply --check" "no apply --check"

# No HTTP mutation methods
assert_not_contains "$EXECUTE_BLOCK" 'method="POST"' "no method=POST"
assert_not_contains "$EXECUTE_BLOCK" 'method="PATCH"' "no method=PATCH"
assert_not_contains "$EXECUTE_BLOCK" 'method="DELETE"' "no method=DELETE"
assert_not_contains "$EXECUTE_BLOCK" 'method="PUT"' "no method=PUT"
assert_not_contains "$EXECUTE_BLOCK" "method='POST'" "no method='POST'"
assert_not_contains "$EXECUTE_BLOCK" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$EXECUTE_BLOCK" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$EXECUTE_BLOCK" "method='PUT'" "no method='PUT'"

# No external tools
assert_not_contains "$EXECUTE_BLOCK" "curl" "no curl"
assert_not_contains "$EXECUTE_BLOCK" "wget" "no wget"
assert_not_contains "$EXECUTE_BLOCK" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$EXECUTE_BLOCK" "ipify" "no ipify"
assert_not_contains "$EXECUTE_BLOCK" "ident.me" "no ident.me"
assert_not_contains "$EXECUTE_BLOCK" "icanhazip" "no icanhazip"
assert_not_contains "$EXECUTE_BLOCK" "cloudflare.com/cdn-cgi" "no cloudflare trace"

# No interface reads
assert_not_contains "$EXECUTE_BLOCK" "ip addr" "no ip addr"
assert_not_contains "$EXECUTE_BLOCK" "ip route" "no ip route"
assert_not_contains "$EXECUTE_BLOCK" "/proc/net" "no /proc/net"

# No raw path printing patterns
assert_not_contains "$EXECUTE_BLOCK" "print(physical" "no print(physical"
assert_not_contains "$EXECUTE_BLOCK" "print(backup_path" "no print(backup_path"
assert_not_contains "$EXECUTE_BLOCK" "print(pre_backup_path" "no print(pre_backup_path"

# No Cloudflare API
assert_not_contains "$EXECUTE_BLOCK" "api.cloudflare.com" "no api.cloudflare.com"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-rollback-execute tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
