#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Replace Preview Test
#
# Tests nanobk cf dns profile replace preview under fake-root.
# Read-only. No backup. No replace. No real /etc.
#
# Usage:
#   bash tests/cf-dns-profile-replace-preview.sh

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

# ── Helper: set up fake-root with parent ─────────────────────────────────────

setup_fake_root() {
  local root="$1"
  mkdir -p "$root/etc/nanobk"
  chmod 700 "$root/etc/nanobk"
}

# ── Helper: run replace preview ─────────────────────────────────────────────

run_preview() {
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

  env "${env_args[@]}" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
    --zone example.com --node proxy --ipv4 203.0.113.10 \
    --output /etc/nanobk/cloudflare-dns-profile.json \
    --allow-production-output --confirm-hostname proxy.example.com \
    --allow-documentation-ips \
    "${extra_args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Replace Preview Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "preview" "help mentions preview"
assert_contains "$HELP_OUTPUT" "replace" "help mentions replace"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Real /etc blocked without fake-root ───────────────────────────────────

echo "--- B. Real /etc blocked without fake-root ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_contains "$NO_FAKE" "not enabled" "error says not enabled"
assert_not_contains "$NO_FAKE" "203.0.113.10" "no raw IP"

echo ""

# ── C. Partial fake-root hooks fail ─────────────────────────────────────────

echo "--- C. Partial fake-root hooks fail ---"
echo ""

PARTIAL1=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$PARTIAL1" '"ok": false' "only ROOT set fails"

PARTIAL2=$(NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
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
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$OUTSIDE_OUT" '"ok": false' "outside-temp fails"
assert_contains "$OUTSIDE_OUT" "temp root" "error mentions temp root"
assert_not_contains "$OUTSIDE_OUT" "203.0.113.10" "no raw IP"
assert_not_contains "$OUTSIDE_OUT" "$OUTSIDE_ROOT" "no physical path"
rm -rf "$OUTSIDE_ROOT"

echo ""

# ── E. Parent missing / symlink / 0755 fail ─────────────────────────────────

echo "--- E. Parent directory failures ---"
echo ""

# Missing parent
EMPTY_ROOT="$TEST_TMPDIR/empty-root"
mkdir -p "$EMPTY_ROOT"
MISSING_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$EMPTY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$MISSING_OUT" '"ok": false' "missing parent fails"

# Symlink parent
SYMLINK_ROOT="$TEST_TMPDIR/symlink-root"
mkdir -p "$SYMLINK_ROOT/etc"
ln -sf /tmp "$SYMLINK_ROOT/etc/nanobk"
SYMLINK_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYMLINK_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$SYMLINK_OUT" '"ok": false' "symlink parent fails"

# Bad mode
MODE_ROOT="$TEST_TMPDIR/mode-root"
mkdir -p "$MODE_ROOT/etc/nanobk"
chmod 755 "$MODE_ROOT/etc/nanobk"
MODE_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$MODE_OUT" '"ok": false' "bad parent mode fails"

echo ""

# ── F. Missing old profile ──────────────────────────────────────────────────

echo "--- F. Missing old profile ---"
echo ""

MISSING_ROOT="$TEST_TMPDIR/missing-root"
setup_fake_root "$MISSING_ROOT"
MISSING_PROF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MISSING_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)
assert_contains "$MISSING_PROF" '"ok": true' "missing profile ok: true"
assert_contains "$MISSING_PROF" '"old_profile_status": "missing"' "old status is missing"
assert_contains "$MISSING_PROF" '"replace_execute_ready": false' "execute not ready"
assert_not_contains "$MISSING_PROF" "203.0.113.10" "no raw IP"

echo ""

# ── G. Old profile symlink ──────────────────────────────────────────────────

echo "--- G. Old profile symlink ---"
echo ""

SYMLINK_PROF_ROOT="$TEST_TMPDIR/symlink-prof-root"
setup_fake_root "$SYMLINK_PROF_ROOT"
ln -sf /dev/null "$SYMLINK_PROF_ROOT/etc/nanobk/cloudflare-dns-profile.json"
SYMLINK_PROF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYMLINK_PROF_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)
assert_contains "$SYMLINK_PROF" '"old_profile_status": "symlink_blocked"' "symlink profile blocked"

echo ""

# ── H. Old profile invalid JSON ─────────────────────────────────────────────

echo "--- H. Old profile invalid JSON ---"
echo ""

INVALID_ROOT="$TEST_TMPDIR/invalid-root"
setup_fake_root "$INVALID_ROOT"
echo '{broken' > "$INVALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$INVALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
INVALID_PROF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$INVALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)
assert_contains "$INVALID_PROF" '"old_profile_status": "invalid_json"' "invalid JSON detected"
assert_not_contains "$INVALID_PROF" "broken" "no raw content leaked"

echo ""

# ── I. Old profile unsupported schema ───────────────────────────────────────

echo "--- I. Old profile unsupported schema ---"
echo ""

UNSUP_ROOT="$TEST_TMPDIR/unsup-root"
setup_fake_root "$UNSUP_ROOT"
echo '{"secretToken":"abc","nodePrefix":"proxy"}' > "$UNSUP_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$UNSUP_ROOT/etc/nanobk/cloudflare-dns-profile.json"
UNSUP_PROF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$UNSUP_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)
assert_contains "$UNSUP_PROF" '"old_profile_status": "unsupported_schema"' "unsupported schema detected"
assert_not_contains "$UNSUP_PROF" "abc" "no raw secret value"

echo ""

# ── J. Valid old + valid new ────────────────────────────────────────────────

echo "--- J. Valid old + valid new ---"
echo ""

VALID_ROOT="$TEST_TMPDIR/valid-root"
setup_fake_root "$VALID_ROOT"
echo '{"zoneName":"example.com","nodePrefix":"proxy","ipv4":"203.0.113.10","defaultProxied":false}' > "$VALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
chmod 600 "$VALID_ROOT/etc/nanobk/cloudflare-dns-profile.json"
VALID_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$VALID_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 198.51.100.20 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)

if echo "$VALID_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "valid preview JSON is valid"
else
  fail "valid preview JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$VALID_OUT" '"ok": true' "ok: true"
assert_contains "$VALID_OUT" '"replace_preview": true' "replace_preview: true"
assert_contains "$VALID_OUT" '"local_file_mutation": false' "local_file_mutation: false"
assert_contains "$VALID_OUT" '"backup_required": true' "backup_required: true"
assert_contains "$VALID_OUT" '"backup_created": false' "backup_created: false"
assert_contains "$VALID_OUT" '"profile_replaced": false' "profile_replaced: false"
assert_contains "$VALID_OUT" '"old_profile_status": "valid"' "old status valid"
assert_contains "$VALID_OUT" '"new_profile_valid": true' "new valid"
assert_contains "$VALID_OUT" '"replace_execute_ready": false' "execute not ready"
assert_contains "$VALID_OUT" '"rollback policy is not implemented"' "blocked reason present"
assert_contains "$VALID_OUT" '"ipv4_redacted_changed": true' "IP changed detected"
assert_contains "$VALID_OUT" '"old_summary"' "old_summary present"
assert_contains "$VALID_OUT" '"new_summary"' "new_summary present"
assert_not_contains "$VALID_OUT" "203.0.113.10" "no raw old IP"
assert_not_contains "$VALID_OUT" "198.51.100.20" "no raw new IP"
assert_not_contains "$VALID_OUT" "example.com" "no raw zone"
assert_not_contains "$VALID_OUT" "proxy.example.com" "no raw hostname"
assert_not_contains "$VALID_OUT" "$VALID_ROOT" "no physical fake-root path"

echo ""

# ── K. New profile invalid ──────────────────────────────────────────────────

echo "--- K. New profile invalid ---"
echo ""

BAD_NEW_ROOT="$TEST_TMPDIR/bad-new-root"
setup_fake_root "$BAD_NEW_ROOT"
BAD_NEW_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$BAD_NEW_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 10.0.0.1 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com \
  --json 2>&1 || true)
assert_contains "$BAD_NEW_OUT" '"ok": false' "invalid new IP fails"
assert_not_contains "$BAD_NEW_OUT" "10.0.0.1" "no raw IP"

echo ""

# ── L. Confirmation missing/mismatch ────────────────────────────────────────

echo "--- L. Confirmation missing/mismatch ---"
echo ""

# Missing
NO_CONF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$NO_CONF" '"ok": false' "missing confirm fails"
assert_contains "$NO_CONF" "confirm-hostname" "error mentions confirm-hostname"

# Mismatch
BAD_CONF=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname wrong.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$BAD_CONF" '"ok": false' "mismatch confirm fails"
assert_contains "$BAD_CONF" "does not match" "mismatch error"
assert_not_contains "$BAD_CONF" "proxy.example.com" "no raw expected hostname"
assert_not_contains "$BAD_CONF" "wrong.example.com" "no raw provided hostname"

echo ""

# ── M. Dry-run ──────────────────────────────────────────────────────────────

echo "--- M. Dry-run ---"
echo ""

DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com \
  --allow-documentation-ips --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "203.0.113.10" "dry-run hides raw IP"
assert_not_contains "$DRY_LOCAL" "example.com" "dry-run hides raw zone"
assert_not_contains "$DRY_LOCAL" "proxy.example.com" "dry-run hides raw confirm"

DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile replace preview \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --allow-production-output --confirm-hostname proxy.example.com \
  --allow-documentation-ips 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "203.0.113.10" "global dry-run hides raw IP"

echo ""

# ── N. Source checks ────────────────────────────────────────────────────────

echo "--- N. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_profile.py")

# No mutation paths
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"

# No HTTP mutation methods
assert_not_contains "$HELPER_SRC" 'method="POST"' "no method=POST"
assert_not_contains "$HELPER_SRC" 'method="PATCH"' "no method=PATCH"
assert_not_contains "$HELPER_SRC" 'method="DELETE"' "no method=DELETE"
assert_not_contains "$HELPER_SRC" 'method="PUT"' "no method=PUT"
assert_not_contains "$HELPER_SRC" "method='POST'" "no method='POST'"
assert_not_contains "$HELPER_SRC" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$HELPER_SRC" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$HELPER_SRC" "method='PUT'" "no method='PUT'"

# No external tools
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"
assert_not_contains "$HELPER_SRC" "icanhazip" "no icanhazip"
assert_not_contains "$HELPER_SRC" "cloudflare.com/cdn-cgi" "no cloudflare trace"

# No network interface reads
assert_not_contains "$HELPER_SRC" "ip addr" "no ip addr"
assert_not_contains "$HELPER_SRC" "ip route" "no ip route"
assert_not_contains "$HELPER_SRC" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-replace-preview tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
