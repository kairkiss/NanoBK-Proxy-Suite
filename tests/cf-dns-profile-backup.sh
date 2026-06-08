#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Backup Test
#
# Tests nanobk cf dns profile backup under fake-root.
# Backup-only. No replace. No rollback. No real /etc.
#
# Usage:
#   bash tests/cf-dns-profile-backup.sh

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

setup_fake_root() {
  local root="$1"
  mkdir -p "$root/etc/nanobk"
  chmod 700 "$root/etc/nanobk"
}

write_source_profile() {
  local root="$1"
  local content="${2:-}"
  if [[ -z "$content" ]]; then
    content='{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}'
  fi
  printf '%s' "$content" > "$root/etc/nanobk/cloudflare-dns-profile.json"
  chmod 600 "$root/etc/nanobk/cloudflare-dns-profile.json"
}

run_backup() {
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

  env "${env_args[@]}" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
    --profile /etc/nanobk/cloudflare-dns-profile.json \
    --allow-production-output --confirm-hostname proxy.example.com \
    --yes \
    "${extra_args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Backup Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "backup" "help mentions backup"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Real /etc blocked without fake-root ───────────────────────────────────

echo "--- B. Real /etc blocked without fake-root ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_contains "$NO_FAKE" "not enabled" "error says not enabled"
assert_not_contains "$NO_FAKE" "203.0.113.10" "no raw IP"

echo ""

# ── C. Partial fake-root hooks fail ─────────────────────────────────────────

echo "--- C. Partial fake-root hooks fail ---"
echo ""

PARTIAL1=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$PARTIAL1" '"ok": false' "only ROOT set fails"

PARTIAL2=$(NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
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
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$OUTSIDE_OUT" '"ok": false' "outside-temp fails"
assert_not_contains "$OUTSIDE_OUT" "$OUTSIDE_ROOT" "no physical path"
rm -rf "$OUTSIDE_ROOT"

echo ""

# ── E. Parent directory failures ─────────────────────────────────────────────

echo "--- E. Parent directory failures ---"
echo ""

# Missing parent
EMPTY_ROOT="$TEST_TMPDIR/empty-root"
mkdir -p "$EMPTY_ROOT"
MISSING_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$EMPTY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$MISSING_OUT" '"ok": false' "missing parent fails"

# Symlink parent
SYMLINK_ROOT="$TEST_TMPDIR/symlink-root"
mkdir -p "$SYMLINK_ROOT/etc"
ln -sf /tmp "$SYMLINK_ROOT/etc/nanobk"
SYMLINK_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYMLINK_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$SYMLINK_OUT" '"ok": false' "symlink parent fails"

# Bad mode
MODE_ROOT="$TEST_TMPDIR/mode-root"
mkdir -p "$MODE_ROOT/etc/nanobk"
chmod 755 "$MODE_ROOT/etc/nanobk"
MODE_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$MODE_OUT" '"ok": false' "bad parent mode fails"

echo ""

# ── F. Source missing fails ──────────────────────────────────────────────────

echo "--- F. Source missing fails ---"
echo ""

MISSING_SRC_ROOT="$TEST_TMPDIR/missing-src-root"
setup_fake_root "$MISSING_SRC_ROOT"
MISSING_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISSING_SRC_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$MISSING_SRC" '"ok": false' "source missing fails"
assert_contains "$MISSING_SRC" "missing" "error says missing"

echo ""

# ── G. Source symlink fails ──────────────────────────────────────────────────

echo "--- G. Source symlink fails ---"
echo ""

SYMLINK_SRC_ROOT="$TEST_TMPDIR/symlink-src-root"
setup_fake_root "$SYMLINK_SRC_ROOT"
ln -sf /dev/null "$SYMLINK_SRC_ROOT/etc/nanobk/cloudflare-dns-profile.json"
SYMLINK_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYMLINK_SRC_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$SYMLINK_SRC" '"ok": false' "source symlink fails"

echo ""

# ── H. Source non-regular fails ──────────────────────────────────────────────

echo "--- H. Source non-regular fails ---"
echo ""

NONREG_ROOT="$TEST_TMPDIR/nonreg-root"
setup_fake_root "$NONREG_ROOT"
mkdir -p "$NONREG_ROOT/etc/nanobk/cloudflare-dns-profile.json"
NONREG_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$NONREG_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$NONREG_SRC" '"ok": false' "source non-regular fails"

echo ""

# ── I. Source invalid JSON fails ─────────────────────────────────────────────

echo "--- I. Source invalid JSON fails ---"
echo ""

INVALID_ROOT="$TEST_TMPDIR/invalid-root"
setup_fake_root "$INVALID_ROOT"
echo '{broken' > "$INVALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$INVALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
INVALID_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$INVALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$INVALID_SRC" '"ok": false' "invalid JSON fails"
assert_contains "$INVALID_SRC" "not valid JSON" "error says not valid JSON"
assert_not_contains "$INVALID_SRC" "broken" "no raw content"

echo ""

# ── J. Source unsupported schema fails ───────────────────────────────────────

echo "--- J. Source unsupported schema fails ---"
echo ""

UNSUP_ROOT="$TEST_TMPDIR/unsup-root"
setup_fake_root "$UNSUP_ROOT"
echo '{"secretToken":"abc","nodePrefix":"proxy"}' > "$UNSUP_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$UNSUP_ROOT/etc/nanobk/cloudflare-dns-profile.json"
UNSUP_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$UNSUP_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$UNSUP_SRC" '"ok": false' "unsupported schema fails"
assert_not_contains "$UNSUP_SRC" "abc" "no raw secret"

echo ""

# ── K. Source mode invalid fails ────────────────────────────────────────────

echo "--- K. Source mode invalid fails ---"
echo ""

MODE_SRC_ROOT="$TEST_TMPDIR/mode-src-root"
setup_fake_root "$MODE_SRC_ROOT"
echo '{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}' > "$MODE_SRC_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 644 "$MODE_SRC_ROOT/etc/nanobk/cloudflare-dns-profile.json"
MODE_SRC=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MODE_SRC_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$MODE_SRC" '"ok": false' "bad source mode fails"
assert_contains "$MODE_SRC" "0600" "error mentions 0600"

echo ""

# ── L. Missing --yes fails ──────────────────────────────────────────────────

echo "--- L. Missing --yes fails ---"
echo ""

NO_YES_ROOT="$TEST_TMPDIR/no-yes-root"
setup_fake_root "$NO_YES_ROOT"
write_source_profile "$NO_YES_ROOT"
NO_YES=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$NO_YES_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$NO_YES" '"ok": false' "missing --yes fails"
assert_contains "$NO_YES" "yes" "error mentions --yes"

echo ""

# ── M. Missing confirm fails ────────────────────────────────────────────────

echo "--- M. Missing confirm fails ---"
echo ""

NO_CONF_ROOT="$TEST_TMPDIR/no-conf-root"
setup_fake_root "$NO_CONF_ROOT"
write_source_profile "$NO_CONF_ROOT"
NO_CONF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$NO_CONF_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --yes \
  --json 2>&1 || true)
assert_contains "$NO_CONF" '"ok": false' "missing confirm fails"

echo ""

# ── N. Confirm mismatch fails ───────────────────────────────────────────────

echo "--- N. Confirm mismatch fails ---"
echo ""

MISMATCH_ROOT="$TEST_TMPDIR/mismatch-root"
setup_fake_root "$MISMATCH_ROOT"
write_source_profile "$MISMATCH_ROOT"
MISMATCH=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISMATCH_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname wrong.example.com --yes \
  --json 2>&1 || true)
assert_contains "$MISMATCH" '"ok": false' "mismatch confirm fails"
assert_contains "$MISMATCH" "does not match" "error says does not match"
assert_not_contains "$MISMATCH" "proxy.example.com" "no raw expected hostname"
assert_not_contains "$MISMATCH" "wrong.example.com" "no raw provided hostname"

echo ""

# ── O. Backup dir symlink fails ─────────────────────────────────────────────

echo "--- O. Backup dir symlink fails ---"
echo ""

BDIR_SYM_ROOT="$TEST_TMPDIR/bdir-sym-root"
setup_fake_root "$BDIR_SYM_ROOT"
write_source_profile "$BDIR_SYM_ROOT"
ln -sf /tmp "$BDIR_SYM_ROOT/etc/nanobk/backups"
BDIR_SYM=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_SYM_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$BDIR_SYM" '"ok": false' "backup dir symlink fails"

echo ""

# ── P. Backup dir regular file fails ────────────────────────────────────────

echo "--- P. Backup dir regular file fails ---"
echo ""

BDIR_FILE_ROOT="$TEST_TMPDIR/bdir-file-root"
setup_fake_root "$BDIR_FILE_ROOT"
write_source_profile "$BDIR_FILE_ROOT"
echo "not a dir" > "$BDIR_FILE_ROOT/etc/nanobk/backups"
BDIR_FILE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_FILE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$BDIR_FILE" '"ok": false' "backup dir file fails"

echo ""

# ── Q. Backup dir bad mode fails ────────────────────────────────────────────

echo "--- Q. Backup dir bad mode fails ---"
echo ""

BDIR_MODE_ROOT="$TEST_TMPDIR/bdir-mode-root"
setup_fake_root "$BDIR_MODE_ROOT"
write_source_profile "$BDIR_MODE_ROOT"
mkdir -p "$BDIR_MODE_ROOT/etc/nanobk/backups"
chmod 755 "$BDIR_MODE_ROOT/etc/nanobk/backups"
BDIR_MODE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BDIR_MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1 || true)
assert_contains "$BDIR_MODE" '"ok": false' "backup dir bad mode fails"
assert_contains "$BDIR_MODE" '"ok": false' "bad mode backup fails"

echo ""

# ── R. Backup success ───────────────────────────────────────────────────────

echo "--- R. Backup success ---"
echo ""

SUCCESS_ROOT="$TEST_TMPDIR/success-root"
setup_fake_root "$SUCCESS_ROOT"
write_source_profile "$SUCCESS_ROOT"
SOURCE_CONTENT=$(cat "$SUCCESS_ROOT/etc/nanobk/cloudflare-dns-profile.json")

SUCCESS_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SUCCESS_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1)

if echo "$SUCCESS_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "backup JSON is valid"
else
  fail "backup JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$SUCCESS_OUT" '"ok": true' "ok: true"
assert_contains "$SUCCESS_OUT" '"backup_created": true' "backup_created: true"
assert_contains "$SUCCESS_OUT" '"backup_only": true' "backup_only: true"
assert_contains "$SUCCESS_OUT" '"profile_replaced": false' "profile_replaced: false"
assert_contains "$SUCCESS_OUT" '"rollback_performed": false' "rollback_performed: false"
assert_contains "$SUCCESS_OUT" '"dns_mutation": false' "dns_mutation: false"
assert_contains "$SUCCESS_OUT" '"cloudflare_mutation": false' "cloudflare_mutation: false"
assert_contains "$SUCCESS_OUT" '"dns_apply": false' "dns_apply: false"
assert_contains "$SUCCESS_OUT" '"backup_sha256_computed": true' "sha256 computed"
assert_contains "$SUCCESS_OUT" '"backup_mode": "600"' "backup mode 600"
assert_contains "$SUCCESS_OUT" '"production_fake_root": true' "fake root true"
assert_not_contains "$SUCCESS_OUT" "203.0.113.10" "no raw IP"
assert_not_contains "$SUCCESS_OUT" "example.com" "no raw zone"
assert_not_contains "$SUCCESS_OUT" "proxy.example.com" "no raw hostname"
assert_not_contains "$SUCCESS_OUT" "$SUCCESS_ROOT" "no physical path"

# Verify backup file exists and matches source
BACKUP_DIR="$SUCCESS_ROOT/etc/nanobk/backups"
BACKUP_FILE=$(ls "$BACKUP_DIR"/*.bak 2>/dev/null | head -1)
if [[ -n "$BACKUP_FILE" ]]; then
  pass "backup file exists"
  BACKUP_MODE=$(stat -f '%Lp' "$BACKUP_FILE" 2>/dev/null || stat -c '%a' "$BACKUP_FILE" 2>/dev/null || echo "unknown")
  if [[ "$BACKUP_MODE" == "600" ]]; then
    pass "backup file mode is 600"
  else
    fail "backup file mode is $BACKUP_MODE"
    ERRORS=$((ERRORS + 1))
  fi
  BACKUP_CONTENT=$(cat "$BACKUP_FILE")
  if [[ "$BACKUP_CONTENT" == "$SOURCE_CONTENT" ]]; then
    pass "backup content matches source"
  else
    fail "backup content does not match source"
    ERRORS=$((ERRORS + 1))
  fi
  # Source unchanged
  CURRENT_SOURCE=$(cat "$SUCCESS_ROOT/etc/nanobk/cloudflare-dns-profile.json")
  if [[ "$CURRENT_SOURCE" == "$SOURCE_CONTENT" ]]; then
    pass "source unchanged"
  else
    fail "source was changed"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "backup file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── S. Existing backup dir success ──────────────────────────────────────────

echo "--- S. Existing backup dir success ---"
echo ""

EXIST_BDIR_ROOT="$TEST_TMPDIR/exist-bdir-root"
setup_fake_root "$EXIST_BDIR_ROOT"
write_source_profile "$EXIST_BDIR_ROOT"
mkdir -p "$EXIST_BDIR_ROOT/etc/nanobk/backups"
chmod 700 "$EXIST_BDIR_ROOT/etc/nanobk/backups"
# Create existing backup
echo "old" > "$EXIST_BDIR_ROOT/etc/nanobk/backups/old.bak"

EXIST_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$EXIST_BDIR_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --json 2>&1)
assert_contains "$EXIST_OUT" '"ok": true' "existing dir backup ok"
assert_contains "$EXIST_OUT" '"backup_created": true' "existing dir backup created"

# Verify new file exists alongside old
NEW_FILES=$(ls "$EXIST_BDIR_ROOT/etc/nanobk/backups/"*.bak 2>/dev/null | wc -l)
if [[ "$NEW_FILES" -ge 2 ]]; then
  pass "new backup created alongside existing"
else
  fail "expected >= 2 backup files, got $NEW_FILES"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── T. Dry-run ──────────────────────────────────────────────────────────────

echo "--- T. Dry-run ---"
echo ""

DRY_ROOT="$TEST_TMPDIR/dry-root"
setup_fake_root "$DRY_ROOT"
write_source_profile "$DRY_ROOT"

DRY_LOCAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "Backup created" "dry-run does not create backup"

DRY_GLOBAL=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$DRY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile backup \
  --profile /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --yes \
  2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "Backup created" "global dry-run does not create backup"

echo ""

# ── U. Source checks ────────────────────────────────────────────────────────

echo "--- U. Source checks ---"
echo ""

# Extract backup-only block
BACKUP_BLOCK=$(awk '/^# ── backup-only start/,/^# ── backup-only end/' "$ROOT/lib/nanobk_cf_dns_profile.py")

# No overwrite/replace primitives in backup block
assert_not_contains "$BACKUP_BLOCK" "os.replace(" "backup block has no os.replace"
assert_not_contains "$BACKUP_BLOCK" "os.rename(" "backup block has no os.rename"

# No mutation paths
assert_not_contains "$BACKUP_BLOCK" "cf dns apply" "backup block has no cf dns apply"
assert_not_contains "$BACKUP_BLOCK" "apply --check" "backup block has no apply --check"
assert_not_contains "$BACKUP_BLOCK" "--force" "backup block has no --force"

# No HTTP mutation methods
assert_not_contains "$BACKUP_BLOCK" 'method="POST"' "no method=POST"
assert_not_contains "$BACKUP_BLOCK" 'method="PATCH"' "no method=PATCH"
assert_not_contains "$BACKUP_BLOCK" 'method="DELETE"' "no method=DELETE"
assert_not_contains "$BACKUP_BLOCK" 'method="PUT"' "no method=PUT"
assert_not_contains "$BACKUP_BLOCK" "method='POST'" "no method='POST'"
assert_not_contains "$BACKUP_BLOCK" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$BACKUP_BLOCK" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$BACKUP_BLOCK" "method='PUT'" "no method='PUT'"

# No external tools
assert_not_contains "$BACKUP_BLOCK" "curl" "no curl"
assert_not_contains "$BACKUP_BLOCK" "wget" "no wget"
assert_not_contains "$BACKUP_BLOCK" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$BACKUP_BLOCK" "ipify" "no ipify"
assert_not_contains "$BACKUP_BLOCK" "ident.me" "no ident.me"
assert_not_contains "$BACKUP_BLOCK" "icanhazip" "no icanhazip"
assert_not_contains "$BACKUP_BLOCK" "cloudflare.com/cdn-cgi" "no cloudflare trace"

# No interface reads
assert_not_contains "$BACKUP_BLOCK" "ip addr" "no ip addr"
assert_not_contains "$BACKUP_BLOCK" "ip route" "no ip route"
assert_not_contains "$BACKUP_BLOCK" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-backup tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
