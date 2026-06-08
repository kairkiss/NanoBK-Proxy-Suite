#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Target Preview Test
#
# Tests nanobk cf dns target preview --zone DOMAIN [--node NODE] --ip-fixture PATH [--json].
# Uses existing IP fixtures. No Cloudflare calls. No DNS mutation.
#
# Usage:
#   bash tests/cf-dns-target-preview.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"
FIXTURES="$ROOT/tests/fixtures/ip-detect"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

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

# ── Helper: run target preview ──────────────────────────────────────────────

run_preview() {
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns target preview)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      *) args+=("$1"); shift ;;
    esac
  done
  bash "${args[@]}" 2>&1
}

echo ""
echo "=== DNS Target Preview Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns target preview --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "preview" "help mentions preview"
assert_contains "$HELP_OUTPUT" "read-only" "help mentions read-only"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

# Top-level target error
TARGET_ERROR=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns target 2>&1 || true)
assert_contains "$TARGET_ERROR" "preview" "target usage mentions preview"

echo ""

# ── B. Missing zone ─────────────────────────────────────────────────────────

echo "--- B. Missing zone ---"
echo ""

MISSING_ZONE=$(run_preview --ip-fixture "$FIXTURES/dual-stack.json" 2>&1 || true)
assert_contains "$MISSING_ZONE" "required" "missing zone reports required"
assert_not_contains "$MISSING_ZONE" "Traceback" "missing zone has no traceback"

echo ""

# ── C. Missing ip-fixture ───────────────────────────────────────────────────

echo "--- C. Missing ip-fixture ---"
echo ""

MISSING_FIX=$(run_preview --zone example.com 2>&1 || true)
assert_contains "$MISSING_FIX" "error" "missing fixture reports error"
assert_not_contains "$MISSING_FIX" "Traceback" "missing fixture has no traceback"

echo ""

# ── D. Default node ─────────────────────────────────────────────────────────

echo "--- D. Default node ---"
echo ""

DEFAULT_NODE=$(run_preview --zone example.com --ip-fixture "$FIXTURES/ipv4-only.json")
assert_contains "$DEFAULT_NODE" "proxy.ex***e.com" "default node uses proxy"
assert_not_contains "$DEFAULT_NODE" "example.com" "default node has no raw zone"

echo ""

# ── E. Invalid zone ─────────────────────────────────────────────────────────

echo "--- E. Invalid zone ---"
echo ""

BAD_ZONE=$(run_preview --zone "http://example.com/path" --ip-fixture "$FIXTURES/dual-stack.json" 2>&1 || true)
assert_contains "$BAD_ZONE" "Error" "invalid zone reports Error"
assert_not_contains "$BAD_ZONE" "Traceback" "invalid zone has no traceback"

echo ""

# ── F. Invalid node ─────────────────────────────────────────────────────────

echo "--- F. Invalid node ---"
echo ""

BAD_NODE=$(run_preview --zone example.com --node "../bad" --ip-fixture "$FIXTURES/dual-stack.json" 2>&1 || true)
assert_contains "$BAD_NODE" "Error" "invalid node reports Error"
assert_not_contains "$BAD_NODE" "Traceback" "invalid node has no traceback"

echo ""

# ── G. Dual-stack fixture ───────────────────────────────────────────────────

echo "--- G. Dual-stack fixture ---"
echo ""

DUAL=$(run_preview --zone example.com --ip-fixture "$FIXTURES/dual-stack.json")
assert_contains "$DUAL" "A" "dual-stack shows A record"
assert_contains "$DUAL" "AAAA" "dual-stack shows AAAA record"
assert_contains "$DUAL" "203.0.113.xxx" "dual-stack shows masked IPv4"
assert_contains "$DUAL" "2001:db8:…" "dual-stack shows masked IPv6"
assert_contains "$DUAL" "target_ready: true" "dual-stack target_ready true"
assert_contains "$DUAL" "dual_stack: true" "dual-stack dual_stack true"
assert_not_contains "$DUAL" "203.0.113.10" "dual-stack has no full IPv4"
assert_not_contains "$DUAL" "example.com" "dual-stack has no raw zone in output"

echo ""

# ── H. IPv4-only fixture ────────────────────────────────────────────────────

echo "--- H. IPv4-only fixture ---"
echo ""

IPV4=$(run_preview --zone example.com --ip-fixture "$FIXTURES/ipv4-only.json")
assert_contains "$IPV4" "A " "ipv4-only shows A record"
assert_not_contains "$IPV4" "AAAA" "ipv4-only has no AAAA"
assert_contains "$IPV4" "192.0.2.xxx" "ipv4-only shows masked IPv4"
assert_contains "$IPV4" "target_ready: true" "ipv4-only target_ready true"
assert_not_contains "$IPV4" "192.0.2.42" "ipv4-only has no full IPv4"

echo ""

# ── I. IPv6-only fixture ────────────────────────────────────────────────────

echo "--- I. IPv6-only fixture ---"
echo ""

IPV6=$(run_preview --zone example.com --ip-fixture "$FIXTURES/ipv6-only.json")
assert_contains "$IPV6" "AAAA" "ipv6-only shows AAAA record"
assert_contains "$IPV6" "2001:db8:…" "ipv6-only shows masked IPv6"
assert_contains "$IPV6" "target_ready: true" "ipv6-only target_ready true"
assert_not_contains "$IPV6" "2001:0db8" "ipv6-only has no full IPv6"

echo ""

# ── J. Private-only fixture ─────────────────────────────────────────────────

echo "--- J. Private-only fixture ---"
echo ""

PRIV=$(run_preview --zone example.com --ip-fixture "$FIXTURES/private-only.json")
assert_contains "$PRIV" "target_ready: false" "private target_ready false"
assert_contains "$PRIV" "manual_input_required: true" "private requires manual input"
assert_not_contains "$PRIV" "10.0.0.1" "private has no full IPv4"
assert_not_contains "$PRIV" "fd00::1" "private has no full ULA IPv6"

echo ""

# ── K. Multiple IPv4 fixture ────────────────────────────────────────────────

echo "--- K. Multiple IPv4 fixture ---"
echo ""

MULTI=$(run_preview --zone example.com --ip-fixture "$FIXTURES/multiple-ipv4.json")
assert_contains "$MULTI" "target_ready: false" "multiple target_ready false"
assert_contains "$MULTI" "manual_input_required: true" "multiple requires manual input"
assert_not_contains "$MULTI" "203.0.113.10" "multiple has no full IPv4"

echo ""

# ── L. No-address fixture ───────────────────────────────────────────────────

echo "--- L. No-address fixture ---"
echo ""

EMPTY=$(run_preview --zone example.com --ip-fixture "$FIXTURES/no-addresses.json")
assert_contains "$EMPTY" "target_ready: false" "no-address target_ready false"
assert_contains "$EMPTY" "manual_input_required: true" "no-address requires manual"

echo ""

# ── M. Malformed fixture ────────────────────────────────────────────────────

echo "--- M. Malformed fixture ---"
echo ""

MAL=$(run_preview --zone example.com --ip-fixture "$FIXTURES/malformed.json" 2>&1 || true)
assert_contains "$MAL" "Error" "malformed reports Error"
assert_not_contains "$MAL" "Traceback" "malformed has no traceback"

MAL_JSON=$(run_preview --zone example.com --ip-fixture "$FIXTURES/malformed.json" --json 2>&1 || true)
if echo "$MAL_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "malformed JSON is valid"
else
  fail "malformed JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MAL_JSON" '"ok": false' "malformed JSON has ok: false"

echo ""

# ── N. JSON mode dual-stack ─────────────────────────────────────────────────

echo "--- N. JSON mode dual-stack ---"
echo ""

JSON_DUAL=$(run_preview --zone example.com --ip-fixture "$FIXTURES/dual-stack.json" --json)
if echo "$JSON_DUAL" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "dual-stack JSON is valid"
else
  fail "dual-stack JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_DUAL" '"ok": true' "JSON has ok: true"
assert_contains "$JSON_DUAL" '"mutation": false' "JSON has mutation: false"
assert_contains "$JSON_DUAL" '"profile_write": false' "JSON has profile_write: false"
assert_contains "$JSON_DUAL" '"target_ready": true' "JSON has target_ready: true"
assert_contains "$JSON_DUAL" '"dual_stack": true' "JSON has dual_stack: true"
assert_contains "$JSON_DUAL" '"stack_mode": "dual_stack"' "JSON has stack_mode: dual_stack"
assert_not_contains "$JSON_DUAL" "203.0.113.10" "JSON has no full IPv4"
assert_not_contains "$JSON_DUAL" "2001:0db8" "JSON has no full IPv6"
assert_not_contains "$JSON_DUAL" "example.com" "JSON has no raw zone"
assert_not_contains "$JSON_DUAL" "proxy.example.com" "JSON has no raw hostname"
assert_not_contains "$JSON_DUAL" "hysteria2://" "JSON has no protocol URI"
assert_not_contains "$JSON_DUAL" "workers.dev" "JSON has no workers.dev"

echo ""

# ── O. Dry-run ──────────────────────────────────────────────────────────────

echo "--- O. Dry-run ---"
echo ""

DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns target preview --zone example.com --ip-fixture "$FIXTURES/dual-stack.json" 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "NanoBK DNS target preview" "global dry-run does NOT execute helper"

DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns target preview --zone example.com --ip-fixture "$FIXTURES/dual-stack.json" --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "NanoBK DNS target preview" "command-level dry-run does NOT execute helper"

echo ""

# ── P. Source checks ────────────────────────────────────────────────────────

echo "--- P. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_targets.py")
assert_not_contains "$HELPER_SRC" "api.cloudflare.com" "no Cloudflare API URL"
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"
assert_not_contains "$HELPER_SRC" "cloudflare-dns-profile.json" "no profile path"
assert_not_contains "$HELPER_SRC" "/etc/nanobk" "no /etc/nanobk"
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-target-preview tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
