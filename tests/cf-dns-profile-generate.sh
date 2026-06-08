#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Generate Test
#
# Tests nanobk cf dns profile generate --zone DOMAIN --node NODE --ipv4 VALUE --output PATH --yes [--json] [--allow-documentation-ips].
# Writes only to temp/test paths. No Cloudflare calls. No DNS apply/check.
#
# Usage:
#   bash tests/cf-dns-profile-generate.sh

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

# ── Helper: run generate ────────────────────────────────────────────────────

GENERATE_OUT_PATH=""

run_generate() {
  local out_path="$TEST_TMPDIR/profile-$(date +%s%N).json"
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$out_path" --yes --allow-documentation-ips)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-allow) args=("${args[@]/--allow-documentation-ips/}"); shift ;;
      --no-yes) args=("${args[@]/--yes/}"); shift ;;
      --ipv6) args+=("--ipv6" "$2"); shift 2 ;;
      --zone) args=("${args[@]/--zone example.com/--zone $2}"); shift 2 ;;
      --node) args=("${args[@]/--node proxy/--node $2}"); shift 2 ;;
      --ipv4) args=("${args[@]/--ipv4 203.0.113.10/--ipv4 $2}"); shift 2 ;;
      --output) args=("${args[@]/--output $out_path/--output $2}"); out_path="$2"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  GENERATE_OUT_PATH="$out_path"
  NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "${args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Generate Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "generate" "help mentions generate"
assert_contains "$HELP_OUTPUT" "generate" "help mentions generate"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Missing args ─────────────────────────────────────────────────────────

echo "--- B. Missing args ---"
echo ""

# Missing zone
MISS_ZONE=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --node proxy --ipv4 203.0.113.10 --output "$TEST_TMPDIR/x.json" --yes --json 2>&1 || true)
if echo "$MISS_ZONE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "missing zone JSON is valid"
else
  fail "missing zone JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MISS_ZONE" '"ok": false' "missing zone has ok: false"
assert_not_contains "$MISS_ZONE" "Traceback" "missing zone has no Traceback"

# Missing node
MISS_NODE=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --ipv4 203.0.113.10 --output "$TEST_TMPDIR/x.json" --yes --json 2>&1 || true)
assert_contains "$MISS_NODE" '"ok": false' "missing node has ok: false"

# Missing ipv4
MISS_IPV4=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --output "$TEST_TMPDIR/x.json" --yes --json 2>&1 || true)
assert_contains "$MISS_IPV4" '"ok": false' "missing ipv4 has ok: false"

# Missing output
MISS_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --yes --json --allow-documentation-ips 2>&1 || true)
assert_contains "$MISS_OUT" '"ok": false' "missing output has ok: false"

# Missing yes
MISS_YES=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$TEST_TMPDIR/x.json" --json --allow-documentation-ips 2>&1 || true)
assert_contains "$MISS_YES" '"ok": false' "missing yes has ok: false"
assert_contains "$MISS_YES" "yes" "missing yes mentions --yes"

echo ""

# ── C. Dry-run privacy ─────────────────────────────────────────────────────

echo "--- C. Dry-run privacy ---"
echo ""

# Command-level dry-run
DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output /tmp/x.json --yes --allow-documentation-ips --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "203.0.113.10" "command-level dry-run hides raw IP"
assert_not_contains "$DRY_LOCAL" "example.com" "command-level dry-run hides raw zone"
assert_not_contains "$DRY_LOCAL" "/tmp/x.json" "command-level dry-run hides raw path"
assert_not_contains "$DRY_LOCAL" "Local profile" "command-level dry-run does NOT execute"

# Global dry-run
DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output /tmp/x.json --yes --allow-documentation-ips 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "203.0.113.10" "global dry-run hides raw IP"
assert_not_contains "$DRY_GLOBAL" "example.com" "global dry-run hides raw zone"
assert_not_contains "$DRY_GLOBAL" "/tmp/x.json" "global dry-run hides raw path"

echo ""

# ── D. Successful temp write ────────────────────────────────────────────────

echo "--- D. Successful temp write ---"
echo ""

GEN_PATH="$TEST_TMPDIR/success-$(date +%s%N).json"
GEN_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$GEN_PATH" --yes --allow-documentation-ips 2>&1)
GEN_RC=$?

if [[ $GEN_RC -eq 0 ]]; then
  pass "generate exits 0"
else
  fail "generate exits $GEN_RC"
  ERRORS=$((ERRORS + 1))
fi

# File exists
if [[ -f "$GEN_PATH" ]]; then
  pass "profile file exists"
else
  fail "profile file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

# File mode 600
if [[ -f "$GEN_PATH" ]]; then
  FILE_MODE=$(stat -f '%Lp' "$GEN_PATH" 2>/dev/null || stat -c '%a' "$GEN_PATH" 2>/dev/null || echo "unknown")
  if [[ "$FILE_MODE" == "600" ]]; then
    pass "profile file mode is 600"
  else
    fail "profile file mode is $FILE_MODE (expected 600)"
    ERRORS=$((ERRORS + 1))
  fi
fi

# File contains raw IPs (this is expected — file has raw values)
if [[ -f "$GEN_PATH" ]]; then
  FILE_CONTENT=$(cat "$GEN_PATH")
  assert_contains "$FILE_CONTENT" "203.0.113.10" "file contains raw IPv4"
  assert_contains "$FILE_CONTENT" "example.com" "file contains raw zone"
  assert_contains "$FILE_CONTENT" "proxy" "file contains raw node"
fi

# File is valid JSON
if [[ -f "$GEN_PATH" ]]; then
  if python3 -c "import json; json.load(open('$GEN_PATH'))" 2>/dev/null; then
    pass "file is valid JSON"
  else
    fail "file is NOT valid JSON"
    ERRORS=$((ERRORS + 1))
  fi
fi

# CLI output does NOT contain raw IPs
assert_not_contains "$GEN_OUT" "203.0.113.10" "CLI output has no raw IPv4"
assert_not_contains "$GEN_OUT" "example.com" "CLI output has no raw zone"
assert_not_contains "$GEN_OUT" "proxy.example.com" "CLI output has no raw hostname"

echo ""

# ── E. Existing file refusal ────────────────────────────────────────────────

echo "--- E. Existing file refusal ---"
echo ""

EXIST_PATH="$TEST_TMPDIR/existing-$(date +%s%N).json"
echo '{"test": true}' > "$EXIST_PATH"
EXIST_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$EXIST_PATH" --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$EXIST_OUT" "Error" "existing file is refused"
# Existing content unchanged
EXIST_CONTENT=$(cat "$EXIST_PATH")
assert_contains "$EXIST_CONTENT" "test" "existing file content unchanged"
assert_not_contains "$EXIST_OUT" "203.0.113.10" "existing refusal has no raw IP"

echo ""

# ── F. Production path blocked ──────────────────────────────────────────────

echo "--- F. Production path blocked ---"
echo ""

ETC_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output /etc/nanobk/cloudflare-dns-profile.json --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$ETC_OUT" "Error" "/etc path is blocked"
assert_not_contains "$ETC_OUT" "203.0.113.10" "/etc block has no raw IP"

ETC2_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output /etc/nanobk/foo.json --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$ETC2_OUT" "Error" "/etc/nanobk/foo is blocked"

echo ""

# ── G. Outside temp root blocked ────────────────────────────────────────────

echo "--- G. Outside temp root blocked ---"
echo ""

HOME_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output /home/user/profile.json --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$HOME_OUT" "Error" "/home path is blocked"

REL_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output relative/path.json --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$REL_OUT" "Error" "relative path is blocked"

echo ""

# ── H. Invalid input no write ───────────────────────────────────────────────

echo "--- H. Invalid input no write ---"
echo ""

# Invalid zone
BAD_ZONE_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone "http://bad" --node proxy --ipv4 203.0.113.10 --output "$TEST_TMPDIR/bad-zone.json" --yes --allow-documentation-ips 2>&1 || true)
assert_contains "$BAD_ZONE_OUT" "Error" "invalid zone reports error"
assert_not_contains "$BAD_ZONE_OUT" "203.0.113.10" "invalid zone has no raw IP"
if [[ ! -f "$TEST_TMPDIR/bad-zone.json" ]]; then
  pass "invalid zone creates no file"
else
  fail "invalid zone created a file"
  ERRORS=$((ERRORS + 1))
fi

# Private IP
PRIV_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 10.0.0.1 --output "$TEST_TMPDIR/priv.json" --yes 2>&1 || true)
assert_contains "$PRIV_OUT" "Error" "private IP reports error"
assert_not_contains "$PRIV_OUT" "10.0.0.1" "private IP error has no raw IP"

echo ""

# ── I. Dual-stack temp write ────────────────────────────────────────────────

echo "--- I. Dual-stack temp write ---"
echo ""

DUAL_PATH="$TEST_TMPDIR/dual-$(date +%s%N).json"
DUAL_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --ipv6 "2001:db8::10" --output "$DUAL_PATH" --yes --allow-documentation-ips --json 2>&1)

if echo "$DUAL_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "dual-stack JSON is valid"
else
  fail "dual-stack JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$DUAL_OUT" '"ok": true' "dual-stack JSON has ok: true"
assert_contains "$DUAL_OUT" '"profile_written": true' "dual-stack JSON has profile_written: true"
assert_contains "$DUAL_OUT" '"local_file_mutation": true' "dual-stack JSON has local_file_mutation: true"
assert_contains "$DUAL_OUT" '"dns_mutation": false' "dual-stack JSON has dns_mutation: false"
assert_contains "$DUAL_OUT" '"profile_write_mode": "temp_output"' "dual-stack JSON has mode temp_output"
assert_not_contains "$DUAL_OUT" "203.0.113.10" "dual-stack JSON has no raw IPv4"
assert_not_contains "$DUAL_OUT" "2001:0db8" "dual-stack JSON has no raw IPv6"
assert_not_contains "$DUAL_OUT" "example.com" "dual-stack JSON has no raw zone"

# File contains raw IPs
if [[ -f "$DUAL_PATH" ]]; then
  DUAL_FILE=$(cat "$DUAL_PATH")
  assert_contains "$DUAL_FILE" "203.0.113.10" "dual-stack file has raw IPv4"
  assert_contains "$DUAL_FILE" "2001:db8::10" "dual-stack file has raw IPv6"
fi

echo ""

# ── J. Finalization failure does not overwrite ──────────────────────────────

echo "--- J. Finalization failure does not overwrite ---"
echo ""

# Test hook: simulate finalization failure
FAIL_PATH="$TEST_TMPDIR/fail-$(date +%s%N).json"
FAIL_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" NANOBK_TEST_FORCE_PROFILE_FINALIZE_FAIL=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$FAIL_PATH" --yes --allow-documentation-ips --json 2>&1 || true)
if echo "$FAIL_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "finalize-fail JSON is valid"
else
  fail "finalize-fail JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$FAIL_OUT" '"ok": false' "finalize-fail has ok: false"
assert_contains "$FAIL_OUT" '"profile_written": false' "finalize-fail has profile_written: false"
assert_not_contains "$FAIL_OUT" "203.0.113.10" "finalize-fail has no raw IP"

# No final file created
if [[ ! -f "$FAIL_PATH" ]]; then
  pass "finalize-fail creates no final file"
else
  fail "finalize-fail created a final file"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── K. Post-write finalization failure cleanup ──────────────────────────────

echo "--- K. Post-write finalization failure cleanup ---"
echo ""

# Test hook: simulate failure after temp write/chmod but before hard-link
POSTWRITE_DIR="$TEST_TMPDIR/postwrite-$(date +%s%N)"
mkdir -p "$POSTWRITE_DIR"
POSTWRITE_PATH="$POSTWRITE_DIR/profile.json"
POSTWRITE_OUT=$(NANOBK_TEST_TMPDIR="$TEST_TMPDIR" NANOBK_TEST_FORCE_PROFILE_FINALIZE_FAIL_AFTER_WRITE=1 bash "$NANOBK" --repo-dir "$ROOT" cf dns profile generate --zone example.com --node proxy --ipv4 203.0.113.10 --output "$POSTWRITE_PATH" --yes --allow-documentation-ips --json 2>&1 || true)
if echo "$POSTWRITE_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "post-write-fail JSON is valid"
else
  fail "post-write-fail JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$POSTWRITE_OUT" '"ok": false' "post-write-fail has ok: false"
assert_contains "$POSTWRITE_OUT" '"profile_written": false' "post-write-fail has profile_written: false"
assert_contains "$POSTWRITE_OUT" '"local_file_mutation": false' "post-write-fail has local_file_mutation: false"
assert_not_contains "$POSTWRITE_OUT" "203.0.113.10" "post-write-fail has no raw IP"
assert_not_contains "$POSTWRITE_OUT" "example.com" "post-write-fail has no raw zone"

# No final file created
if [[ ! -f "$POSTWRITE_PATH" ]]; then
  pass "post-write-fail creates no final file"
else
  fail "post-write-fail created a final file"
  ERRORS=$((ERRORS + 1))
fi

# No leftover temp files
LEFTOVER_TMP=$(find "$POSTWRITE_DIR" -name '.nanobk-profile-*.tmp' 2>/dev/null | head -1)
if [[ -z "$LEFTOVER_TMP" ]]; then
  pass "post-write-fail leaves no temp files"
else
  fail "post-write-fail left temp file: $LEFTOVER_TMP"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── L. Source checks ────────────────────────────────────────────────────────

echo "--- L. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_profile.py")

# No-overwrite finalization: no rename/replace fallback
assert_not_contains "$HELPER_SRC" "os.rename(tmp_path" "no os.rename fallback"
assert_not_contains "$HELPER_SRC" "os.replace(" "no os.replace overwrite"

# No-overwrite primitive present
if grep -q "os.link(" "$ROOT/lib/nanobk_cf_dns_profile.py"; then
  pass "helper uses os.link (no-overwrite primitive)"
else
  fail "helper missing os.link (no-overwrite primitive)"
  ERRORS=$((ERRORS + 1))
fi

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
assert_not_contains "$HELPER_SRC" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-generate tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
