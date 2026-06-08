#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Production Writer Test
#
# Tests nanobk cf dns profile generate with production output path under fake-root.
# Real /etc writes are never performed.
#
# Usage:
#   bash tests/cf-dns-profile-production.sh

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

# ── Helper: run production generate ─────────────────────────────────────────

run_prod() {
  local extra_args=()
  local fake_root_set=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-fake-root) fake_root_set=0; shift ;;
      --no-confirm) extra_args+=("--confirm-hostname" "WRONG_HOST"); shift ;;
      --confirm) extra_args+=("--confirm-hostname" "proxy.example.com"); shift ;;
      --no-allow-prod) fake_root_set=2; shift ;;
      *) extra_args+=("$1"); shift ;;
    esac
  done

  local env_args=()
  if [[ "$fake_root_set" == "1" ]]; then
    env_args+=("NANOBK_TEST_PRODUCTION_PROFILE_ROOT=$FAKE_ROOT")
    env_args+=("NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1")
    env_args+=("NANOBK_TEST_TMPDIR=$TEST_TMPDIR")
  elif [[ "$fake_root_set" == "2" ]]; then
    env_args+=("NANOBK_TEST_PRODUCTION_PROFILE_ROOT=$FAKE_ROOT")
  fi

  env "${env_args[@]}" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
    --zone example.com --node proxy --ipv4 203.0.113.10 \
    --output /etc/nanobk/cloudflare-dns-profile.json \
    --yes --allow-production-output --confirm-hostname proxy.example.com \
    --allow-documentation-ips \
    "${extra_args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Production Writer Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "allow-production-output" "help mentions --allow-production-output"
assert_contains "$HELP_OUTPUT" "confirm-hostname" "help mentions --confirm-hostname"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. --yes alone insufficient ─────────────────────────────────────────────

echo "--- B. --yes alone insufficient ---"
echo ""

NO_ALLOW=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$NO_ALLOW" '"ok": false' "missing --allow-production-output fails"
assert_not_contains "$NO_ALLOW" "203.0.113.10" "no raw IP in error"

echo ""

# ── C. Missing confirm ──────────────────────────────────────────────────────

echo "--- C. Missing confirm ---"
echo ""

NO_CONFIRM=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$NO_CONFIRM" '"ok": false' "missing --confirm-hostname fails"
assert_contains "$NO_CONFIRM" "confirm-hostname" "error mentions confirm-hostname"

echo ""

# ── D. Confirmation mismatch ────────────────────────────────────────────────

echo "--- D. Confirmation mismatch ---"
echo ""

MISMATCH=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname wrong.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$MISMATCH" '"ok": false' "mismatch fails"
assert_contains "$MISMATCH" "does not match" "mismatch error message"
assert_not_contains "$MISMATCH" "proxy.example.com" "no raw expected hostname"
assert_not_contains "$MISMATCH" "wrong.example.com" "no raw provided hostname"

echo ""

# ── E. Real /etc blocked without fake-root ───────────────────────────────────

echo "--- E. Real /etc blocked without fake-root ---"
echo ""

NO_FAKE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$NO_FAKE" '"ok": false' "no fake-root fails"
assert_contains "$NO_FAKE" "not enabled" "error says not enabled"
assert_not_contains "$NO_FAKE" "203.0.113.10" "no raw IP"

echo ""

# ── F. Partial fake-root hooks fail ─────────────────────────────────────────

echo "--- F. Partial fake-root hooks fail ---"
echo ""

# Only ROOT set
PARTIAL1=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$FAKE_ROOT" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$PARTIAL1" '"ok": false' "only ROOT set fails"

# Only ALLOW set
PARTIAL2=$(NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$PARTIAL2" '"ok": false' "only ALLOW set fails"

echo ""

# ── G. Parent missing fails ─────────────────────────────────────────────────

echo "--- G. Parent missing fails ---"
echo ""

EMPTY_ROOT="$TEST_TMPDIR/empty-root"
mkdir -p "$EMPTY_ROOT"
MISSING_PARENT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$EMPTY_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$MISSING_PARENT" '"ok": false' "missing parent fails"
assert_contains "$MISSING_PARENT" "parent" "error mentions parent"

echo ""

# ── H. Parent symlink fails ─────────────────────────────────────────────────

echo "--- H. Parent symlink fails ---"
echo ""

SYMLINK_ROOT="$TEST_TMPDIR/symlink-root"
mkdir -p "$SYMLINK_ROOT/etc"
ln -sf /tmp "$SYMLINK_ROOT/etc/nanobk"
SYMLINK_PARENT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$SYMLINK_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$SYMLINK_PARENT" '"ok": false' "symlink parent fails"
assert_contains "$SYMLINK_PARENT" "symlink" "error mentions symlink"

echo ""

# ── I. Unsafe parent mode fails ─────────────────────────────────────────────

echo "--- I. Unsafe parent mode fails ---"
echo ""

MODE_ROOT="$TEST_TMPDIR/mode-root"
mkdir -p "$MODE_ROOT/etc/nanobk"
chmod 755 "$MODE_ROOT/etc/nanobk"
BAD_MODE=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$MODE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$BAD_MODE" '"ok": false' "bad parent mode fails"
assert_contains "$BAD_MODE" "0700" "error mentions 0700"

echo ""

# ── I2. Non-exact /etc/nanobk paths are forbidden ───────────────────────────

echo "--- I2. Non-exact /etc/nanobk paths are forbidden ---"
echo ""

GOOD_ROOT="$TEST_TMPDIR/strict-root"
mkdir -p "$GOOD_ROOT/etc/nanobk"
chmod 700 "$GOOD_ROOT/etc/nanobk"

# /etc/nanobk/foo.json
FOO_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$GOOD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/foo.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$FOO_OUT" '"ok": false' "/etc/nanobk/foo.json forbidden"
assert_not_contains "$FOO_OUT" "203.0.113.10" "foo.json has no raw IP"
assert_not_contains "$FOO_OUT" "$GOOD_ROOT" "foo.json has no fake-root path"
if [[ ! -f "$GOOD_ROOT/etc/nanobk/foo.json" ]]; then
  pass "foo.json not created"
else
  fail "foo.json was created"
  ERRORS=$((ERRORS + 1))
fi

# /etc/nanobk/cloudflare-dns-profile.json.bak
BAK_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$GOOD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json.bak \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$BAK_OUT" '"ok": false' ".bak file forbidden"
assert_not_contains "$BAK_OUT" "$GOOD_ROOT" ".bak has no fake-root path"

# /etc/nanobk/subdir/cloudflare-dns-profile.json
SUB_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$GOOD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/subdir/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$SUB_OUT" '"ok": false' "subdir path forbidden"
assert_not_contains "$SUB_OUT" "$GOOD_ROOT" "subdir has no fake-root path"

# /etc/other.json
OTHER_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$GOOD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/other.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$OTHER_OUT" '"ok": false' "/etc/other.json forbidden"
assert_not_contains "$OTHER_OUT" "$GOOD_ROOT" "other.json has no fake-root path"

echo ""

# ── I3. Fake-root outside temp fails ────────────────────────────────────────

echo "--- I3. Fake-root outside temp fails ---"
echo ""

OUTSIDE_ROOT="/tmp/nanobk-outside-$$"
mkdir -p "$OUTSIDE_ROOT/etc/nanobk"
chmod 700 "$OUTSIDE_ROOT/etc/nanobk"
OUTSIDE_TMP="$TEST_TMPDIR/inside-tmp"
mkdir -p "$OUTSIDE_TMP"
OUTSIDE_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$OUTSIDE_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$OUTSIDE_TMP" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$OUTSIDE_OUT" '"ok": false' "outside-temp fake-root fails"
assert_contains "$OUTSIDE_OUT" "temp root" "error mentions temp root"
assert_not_contains "$OUTSIDE_OUT" "203.0.113.10" "outside-temp has no raw IP"
assert_not_contains "$OUTSIDE_OUT" "$OUTSIDE_ROOT" "outside-temp has no fake-root path"
rm -rf "$OUTSIDE_ROOT"

echo ""

# ── J. Fake-root success ────────────────────────────────────────────────────

echo "--- J. Fake-root success ---"
echo ""

GOOD_ROOT="$TEST_TMPDIR/good-root"
mkdir -p "$GOOD_ROOT/etc/nanobk"
chmod 700 "$GOOD_ROOT/etc/nanobk"
PROD_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$GOOD_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1)

if echo "$PROD_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "production JSON is valid"
else
  fail "production JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$PROD_OUT" '"ok": true' "production ok: true"
assert_contains "$PROD_OUT" '"production_profile_written": true' "production_profile_written: true"
assert_contains "$PROD_OUT" '"profile_write_mode": "production"' "mode is production"
assert_contains "$PROD_OUT" '"output_path_class": "production"' "class is production"
assert_contains "$PROD_OUT" '"production_fake_root": true' "fake_root: true"
assert_contains "$PROD_OUT" '"confirmation_required": true' "confirmation_required: true"
assert_contains "$PROD_OUT" '"confirmation_matched": true' "confirmation_matched: true"
assert_contains "$PROD_OUT" '"dns_mutation": false' "dns_mutation: false"
assert_contains "$PROD_OUT" '"cloudflare_mutation": false' "cloudflare_mutation: false"
assert_contains "$PROD_OUT" '"dns_apply": false' "dns_apply: false"
assert_not_contains "$PROD_OUT" "203.0.113.10" "no raw IP in output"
assert_not_contains "$PROD_OUT" "example.com" "no raw zone in output"
assert_not_contains "$PROD_OUT" "proxy.example.com" "no raw hostname in output"
assert_not_contains "$PROD_OUT" "$GOOD_ROOT" "no physical fake-root path in output"

# Verify file exists and is valid
PROD_FILE="$GOOD_ROOT/etc/nanobk/cloudflare-dns-profile.json"
if [[ -f "$PROD_FILE" ]]; then
  pass "production file exists"
  FILE_MODE=$(stat -f '%Lp' "$PROD_FILE" 2>/dev/null || stat -c '%a' "$PROD_FILE" 2>/dev/null || echo "unknown")
  if [[ "$FILE_MODE" == "600" ]]; then
    pass "production file mode is 600"
  else
    fail "production file mode is $FILE_MODE (expected 600)"
    ERRORS=$((ERRORS + 1))
  fi
  # File contains raw IPs (expected)
  FILE_CONTENT=$(cat "$PROD_FILE")
  assert_contains "$FILE_CONTENT" "203.0.113.10" "file contains raw IPv4"
  assert_contains "$FILE_CONTENT" "example.com" "file contains raw zone"
else
  fail "production file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── K. Existing production profile refusal ──────────────────────────────────

echo "--- K. Existing production profile refusal ---"
echo ""

EXIST_ROOT="$TEST_TMPDIR/exist-root"
mkdir -p "$EXIST_ROOT/etc/nanobk"
chmod 700 "$EXIST_ROOT/etc/nanobk"
echo '{"existing": true}' > "$EXIST_ROOT/etc/nanobk/cloudflare-dns-profile.json"
EXIST_OUT=$(NANOBK_TEST_PRODUCTION_PROFILE_ROOT="$EXIST_ROOT" NANOBK_TEST_ALLOW_PRODUCTION_ROOT=1 NANOBK_TEST_TMPDIR="$TEST_TMPDIR" \
  bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com --allow-documentation-ips \
  --json 2>&1 || true)
assert_contains "$EXIST_OUT" '"ok": false' "existing profile fails"
assert_contains "$EXIST_OUT" "already exists" "error says already exists"
# Existing content unchanged
EXIST_CONTENT=$(cat "$EXIST_ROOT/etc/nanobk/cloudflare-dns-profile.json")
assert_contains "$EXIST_CONTENT" "existing" "existing file unchanged"

echo ""

# ── L. Dry-run ──────────────────────────────────────────────────────────────

echo "--- L. Dry-run ---"
echo ""

DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com \
  --allow-documentation-ips --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "203.0.113.10" "dry-run hides raw IP"
assert_not_contains "$DRY_LOCAL" "example.com" "dry-run hides raw zone"
assert_not_contains "$DRY_LOCAL" "proxy.example.com" "dry-run hides raw confirm"
assert_not_contains "$DRY_LOCAL" "/etc/nanobk" "dry-run hides raw path"

DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile generate \
  --zone example.com --node proxy --ipv4 203.0.113.10 \
  --output /etc/nanobk/cloudflare-dns-profile.json \
  --yes --allow-production-output --confirm-hostname proxy.example.com \
  --allow-documentation-ips 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "203.0.113.10" "global dry-run hides raw IP"
assert_not_contains "$DRY_GLOBAL" "example.com" "global dry-run hides raw zone"

echo ""

# ── M. Source checks ────────────────────────────────────────────────────────

echo "--- M. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_profile.py")

# Check outside rollback-execute block (os.replace is allowed inside it)
HELPER_SRC_OUTSIDE_ROLLBACK=$(awk '
  /^# ── rollback-execute start/ { inside=1; next }
  /^# ── rollback-execute end/ { inside=0; next }
  !inside { print }
' "$ROOT/lib/nanobk_cf_dns_profile.py")

# No overwrite primitives (outside rollback-execute block)
assert_not_contains "$HELPER_SRC_OUTSIDE_ROLLBACK" "os.rename(tmp_path" "no os.rename fallback"
assert_not_contains "$HELPER_SRC_OUTSIDE_ROLLBACK" "os.replace(" "no os.replace overwrite"

# No mutation paths
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"

# No HTTP mutation methods (double-quote)
assert_not_contains "$HELPER_SRC" 'method="POST"' "no method=\"POST\""
assert_not_contains "$HELPER_SRC" 'method="PATCH"' "no method=\"PATCH\""
assert_not_contains "$HELPER_SRC" 'method="DELETE"' "no method=\"DELETE\""
assert_not_contains "$HELPER_SRC" 'method="PUT"' "no method=\"PUT\""

# No HTTP mutation methods (single-quote)
assert_not_contains "$HELPER_SRC" "method='POST'" "no method='POST'"
assert_not_contains "$HELPER_SRC" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$HELPER_SRC" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$HELPER_SRC" "method='PUT'" "no method='PUT'"

# No external tools
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"

# No external IP echo services
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"
assert_not_contains "$HELPER_SRC" "icanhazip" "no icanhazip"
assert_not_contains "$HELPER_SRC" "cloudflare.com/cdn-cgi" "no cloudflare trace"

# No network interface reads
assert_not_contains "$HELPER_SRC" "ip addr" "no ip addr"
assert_not_contains "$HELPER_SRC" "ip route" "no ip route"
assert_not_contains "$HELPER_SRC" "ifconfig" "no ifconfig"
assert_not_contains "$HELPER_SRC" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-production tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
