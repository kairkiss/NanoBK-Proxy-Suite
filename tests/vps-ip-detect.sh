#!/usr/bin/env bash
# NanoBK Proxy Suite — VPS IP Detection Test
#
# Tests nanobk vps ip detect [--json].
# All detection uses fixtures (NANOBK_IP_DETECT_FIXTURE).
# No real IPs, no external services, no network reads.
#
# Usage:
#   bash tests/vps-ip-detect.sh

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

# ── Helper: run IP detect ───────────────────────────────────────────────────

run_detect() {
  local fixture=""
  local args=("$NANOBK" --repo-dir "$ROOT" vps ip detect)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fixture) fixture="$2"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [[ -n "$fixture" ]]; then
    NANOBK_IP_DETECT_FIXTURE="$fixture" bash "${args[@]}" 2>&1
  else
    bash "${args[@]}" 2>&1
  fi
}

echo ""
echo "=== VPS IP Detection Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" vps ip detect --help 2>&1)
assert_contains "$HELP_OUTPUT" "Read-only" "help mentions Read-only"
assert_contains "$HELP_OUTPUT" "masked" "help mentions masked"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

# Top-level vps error
VPS_ERROR=$(bash "$NANOBK" --repo-dir "$ROOT" vps 2>&1 || true)
assert_contains "$VPS_ERROR" "ip" "vps usage mentions ip"

echo ""

# ── B. No fixture ───────────────────────────────────────────────────────────

echo "--- B. No fixture ---"
echo ""

NOFIX_OUT=$(run_detect)
assert_contains "$NOFIX_OUT" "manual_input_required: true" "no fixture requires manual input"
assert_contains "$NOFIX_OUT" "live detection not enabled" "no fixture explains deferred detection"
assert_not_contains "$NOFIX_OUT" "203.0.113" "no fixture has no real IP"
assert_not_contains "$NOFIX_OUT" "ifconfig.me" "no fixture has no external service"
assert_not_contains "$NOFIX_OUT" "Traceback" "no fixture has no traceback"

echo ""

# ── C. Dual-stack fixture ───────────────────────────────────────────────────

echo "--- C. Dual-stack fixture ---"
echo ""

DUAL_OUT=$(run_detect --fixture "$FIXTURES/dual-stack.json")
assert_contains "$DUAL_OUT" "IPv4" "dual-stack shows IPv4 section"
assert_contains "$DUAL_OUT" "IPv6" "dual-stack shows IPv6 section"
assert_contains "$DUAL_OUT" "203.0.113.xxx" "dual-stack shows masked IPv4"
assert_contains "$DUAL_OUT" "2001:db8:…" "dual-stack shows masked IPv6"
assert_contains "$DUAL_OUT" "dual_stack: true" "dual-stack shows dual_stack true"
assert_contains "$DUAL_OUT" "manual_input_required: false" "dual-stack shows no manual required"
assert_contains "$DUAL_OUT" "documentation" "dual-stack shows documentation scope"
assert_not_contains "$DUAL_OUT" "203.0.113.10" "dual-stack has no full IPv4"
assert_not_contains "$DUAL_OUT" "2001:0db8" "dual-stack has no full IPv6"

echo ""

# ── D. IPv4-only fixture ────────────────────────────────────────────────────

echo "--- D. IPv4-only fixture ---"
echo ""

IPV4_OUT=$(run_detect --fixture "$FIXTURES/ipv4-only.json")
assert_contains "$IPV4_OUT" "192.0.2.xxx" "ipv4-only shows masked IPv4"
assert_contains "$IPV4_OUT" "manual_input_required: false" "ipv4-only no manual required"
assert_not_contains "$IPV4_OUT" "192.0.2.42" "ipv4-only has no full IPv4"

echo ""

# ── E. IPv6-only fixture ────────────────────────────────────────────────────

echo "--- E. IPv6-only fixture ---"
echo ""

IPV6_OUT=$(run_detect --fixture "$FIXTURES/ipv6-only.json")
assert_contains "$IPV6_OUT" "2001:db8:…" "ipv6-only shows masked IPv6"
assert_contains "$IPV6_OUT" "documentation" "ipv6-only shows documentation scope"
assert_contains "$IPV6_OUT" "manual_input_required: false" "ipv6-only no manual required"
assert_not_contains "$IPV6_OUT" "2001:0db8" "ipv6-only has no full IPv6"

echo ""

# ── F. Private-only fixture ─────────────────────────────────────────────────

echo "--- F. Private-only fixture ---"
echo ""

PRIV_OUT=$(run_detect --fixture "$FIXTURES/private-only.json")
assert_contains "$PRIV_OUT" "private" "private-only shows private scope"
assert_contains "$PRIV_OUT" "ula" "private-only shows ULA scope"
assert_contains "$PRIV_OUT" "manual_input_required: true" "private-only requires manual input"
assert_not_contains "$PRIV_OUT" "10.0.0.1" "private-only has no full private IPv4"
assert_not_contains "$PRIV_OUT" "fd00::1" "private-only has no full ULA IPv6"

echo ""

# ── G. Multiple IPv4 candidates ─────────────────────────────────────────────

echo "--- G. Multiple IPv4 candidates ---"
echo ""

MULTI_OUT=$(run_detect --fixture "$FIXTURES/multiple-ipv4.json")
assert_contains "$MULTI_OUT" "manual_input_required: true" "multiple IPv4 requires manual input"
assert_contains "$MULTI_OUT" "203.0.113.xxx" "multiple shows first masked IPv4"
assert_contains "$MULTI_OUT" "198.51.100.xxx" "multiple shows second masked IPv4"
assert_not_contains "$MULTI_OUT" "203.0.113.10" "multiple has no full IPv4"
assert_not_contains "$MULTI_OUT" "198.51.100.20" "multiple has no full IPv4"

echo ""

# ── H. Link-local / ULA IPv6 only ──────────────────────────────────────────

echo "--- H. Link-local / ULA IPv6 only ---"
echo ""

LL_OUT=$(run_detect --fixture "$FIXTURES/link-local-ipv6-only.json")
assert_contains "$LL_OUT" "link_local" "link-local shows link_local scope"
assert_contains "$LL_OUT" "manual_input_required: true" "link-local requires manual input"
assert_not_contains "$LL_OUT" "fe80::1" "link-local has no full IPv6"

ULA_OUT=$(run_detect --fixture "$FIXTURES/ula-ipv6-only.json")
assert_contains "$ULA_OUT" "ula" "ULA shows ula scope"
assert_contains "$ULA_OUT" "manual_input_required: true" "ULA requires manual input"

echo ""

# ── I. No addresses ─────────────────────────────────────────────────────────

echo "--- I. No addresses ---"
echo ""

EMPTY_OUT=$(run_detect --fixture "$FIXTURES/no-addresses.json")
assert_contains "$EMPTY_OUT" "manual_input_required: true" "no addresses requires manual input"
assert_contains "$EMPTY_OUT" "unavailable" "no addresses shows unavailable"

echo ""

# ── J. Malformed fixture ────────────────────────────────────────────────────

echo "--- J. Malformed fixture ---"
echo ""

MAL_OUT=$(run_detect --fixture "$FIXTURES/malformed.json" || true)
assert_contains "$MAL_OUT" "invalid JSON" "malformed shows invalid JSON"
assert_not_contains "$MAL_OUT" "Traceback" "malformed has no traceback"

echo ""

# ── K. JSON mode ────────────────────────────────────────────────────────────

echo "--- K. JSON mode ---"
echo ""

# Dual-stack JSON
JSON_DUAL=$(run_detect --fixture "$FIXTURES/dual-stack.json" --json)
if echo "$JSON_DUAL" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "dual-stack JSON is valid"
else
  fail "dual-stack JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_DUAL" '"ok": true' "JSON has ok: true"
assert_contains "$JSON_DUAL" '"mutation": false' "JSON has mutation: false"
assert_contains "$JSON_DUAL" '"dns_target_ready": true' "JSON has dns_target_ready: true"
assert_contains "$JSON_DUAL" '"dual_stack": true' "JSON has dual_stack: true"
assert_contains "$JSON_DUAL" '"manual_input_required": false' "JSON has manual_input_required: false"
assert_not_contains "$JSON_DUAL" "203.0.113.10" "JSON has no full IPv4"
assert_not_contains "$JSON_DUAL" "2001:0db8" "JSON has no full IPv6"
assert_not_contains "$JSON_DUAL" "hysteria2://" "JSON has no protocol URI"
assert_not_contains "$JSON_DUAL" "workers.dev" "JSON has no workers.dev"

# No-fixture JSON
JSON_NOFIX=$(run_detect --json)
if echo "$JSON_NOFIX" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "no-fixture JSON is valid"
else
  fail "no-fixture JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_NOFIX" '"manual_input_required": true' "no-fixture JSON requires manual"

# Private-only JSON
JSON_PRIV=$(run_detect --fixture "$FIXTURES/private-only.json" --json)
assert_contains "$JSON_PRIV" '"dns_target_ready": false' "private JSON has dns_target_ready: false"
assert_not_contains "$JSON_PRIV" "10.0.0.1" "private JSON has no full IP"

echo ""

# ── L. Safety source checks ─────────────────────────────────────────────────

echo "--- L. Safety source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_ip_detect.py")

# No external IP echo services
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"
assert_not_contains "$HELPER_SRC" "icanhazip" "no icanhazip"
assert_not_contains "$HELPER_SRC" "cloudflare.com/cdn-cgi" "no cloudflare trace"
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "api.cloudflare.com" "no Cloudflare API URL"
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All vps-ip-detect tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
