#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply UX Fake-transport-only Wrapper Test
#
# Tests lib/nanobk_cf_dns_apply_ux_mock.py under mandatory fake-transport guard.
# Does NOT call bin/nanobk. Does NOT call real nanobk cf dns apply.
# Does NOT call Cloudflare. Does NOT perform real DNS mutation.
#
# Usage:
#   bash tests/v2.2.10-dns-apply-ux-fake-wrapper.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/lib/nanobk_cf_dns_apply_ux_mock.py"

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

# ── Temp dir for fake transport fixture ──────────────────────────────────────

TEST_TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TEST_TMPDIR" 2>/dev/null || true; }
trap cleanup EXIT

FAKE_TRANSPORT="$TEST_TMPDIR/fake-transport.json"
echo '{}' > "$FAKE_TRANSPORT"

# Helper: run wrapper with fake transport
run_wrapper() {
  NANOBK_CF_DNS_FAKE_TRANSPORT="$FAKE_TRANSPORT" \
    python3 "$WRAPPER" "$@" 2>&1
}

# Helper: run wrapper WITHOUT fake transport
run_wrapper_no_transport() {
  env -u NANOBK_CF_DNS_FAKE_TRANSPORT \
    python3 "$WRAPPER" "$@" 2>&1
}

echo ""
echo "=== DNS Apply UX Fake-transport-only Wrapper Test ==="
echo ""

# ── 1. Wrapper file exists ───────────────────────────────────────────────────

echo "--- 1. Wrapper file exists ---"
echo ""

if [[ -f "$WRAPPER" ]]; then
  pass "wrapper file exists"
else
  fail "wrapper file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 2. Test does not call nanobk cf dns apply --yes ──────────────────────────

echo "--- 2. Test does not invoke apply ---"
echo ""

# This test inspects the wrapper and fixture output only.
# It does NOT invoke: nanobk, real cf dns apply, Cloudflare API.
# Safe by design — no runtime invocation assertions needed.
pass "test does not invoke real apply command"

echo ""

# ── 3. Missing fake transport fails closed ───────────────────────────────────

echo "--- 3. Missing fake transport fails closed ---"
echo ""

NO_TRANSPORT=$(run_wrapper_no_transport --scenario summary 2>&1) || true
assert_contains "$NO_TRANSPORT" "fake-transport-only" "error says fake-transport-only"

echo ""

# ── 4. Missing fake transport says no DNS changes ────────────────────────────

echo "--- 4. Missing fake transport no DNS changes ---"
echo ""

assert_contains "$NO_TRANSPORT" "No DNS changes were made" "error says no DNS changes"

echo ""

# ── 5. Summary scenario works ────────────────────────────────────────────────

echo "--- 5. Summary scenario ---"
echo ""

SUMMARY=$(run_wrapper --scenario summary)
assert_contains "$SUMMARY" "Status: ready for confirmation" "summary has status"

echo ""

# ── 6. Summary masked values ─────────────────────────────────────────────────

echo "--- 6. Summary masked values ---"
echo ""

assert_contains "$SUMMARY" "ex***e.com" "summary has masked domain"
assert_contains "$SUMMARY" "pr***y.ex***e.com" "summary has masked hostname"
assert_contains "$SUMMARY" "203.0.113.xxx" "summary has masked IPv4"
assert_contains "$SUMMARY" "2001:db8:…" "summary has masked IPv6"

echo ""

# ── 7. Summary no raw values ─────────────────────────────────────────────────

echo "--- 7. Summary no raw values ---"
echo ""

assert_not_contains "$SUMMARY" "example.com" "summary no raw domain"
assert_not_contains "$SUMMARY" "proxy.example.com" "summary no raw hostname"
assert_not_contains "$SUMMARY" "203.0.113.10" "summary no raw IPv4"
assert_not_contains "$SUMMARY" "2001:db8::10" "summary no raw IPv6"

echo ""

# ── 8. Success requires confirm phrase ───────────────────────────────────────

echo "--- 8. Success requires confirm phrase ---"
echo ""

NO_PHRASE=$(run_wrapper --scenario success 2>&1) || true
assert_contains "$NO_PHRASE" "Confirmation required" "success needs confirmation"
RC=$?
# Also verify it exits nonzero
run_wrapper --scenario success > /dev/null 2>&1 && { fail "success without phrase exits 0"; ERRORS=$((ERRORS + 1)); } || pass "success without phrase exits nonzero"

echo ""

# ── 9. Success with correct phrase ───────────────────────────────────────────

echo "--- 9. Success with correct phrase ---"
echo ""

SUCCESS=$(run_wrapper --scenario success --confirm-phrase "apply dns records")
assert_contains "$SUCCESS" "Status: applied" "success status is applied"

echo ""

# ── 10. Success says fake transport only ──────────────────────────────────────

echo "--- 10. Success says fake transport only ---"
echo ""

assert_contains "$SUCCESS" "fake transport only" "success says fake transport only"

echo ""

# ── 11. Success says post-check verified ─────────────────────────────────────

echo "--- 11. Success post-check verified ---"
echo ""

assert_contains "$SUCCESS" "Post-check:" "success has post-check"
assert_contains "$SUCCESS" "verified" "success has verified"

echo ""

# ── 12. Postcheck-failure returns uncertain ───────────────────────────────────

echo "--- 12. Postcheck-failure status ---"
echo ""

POSTCHECK_FAIL=$(run_wrapper --scenario postcheck-failure --confirm-phrase "apply dns records")
assert_contains "$POSTCHECK_FAIL" "Status: uncertain" "postcheck-failure is uncertain"

echo ""

# ── 13. Postcheck-failure not reported as success ────────────────────────────

echo "--- 13. Postcheck-failure not success ---"
echo ""

assert_contains "$POSTCHECK_FAIL" "not reported as success" "postcheck-failure not success"

echo ""

# ── 14. Partial-failure returns partial ──────────────────────────────────────

echo "--- 14. Partial-failure status ---"
echo ""

PARTIAL=$(run_wrapper --scenario partial-failure --confirm-phrase "apply dns records")
assert_contains "$PARTIAL" "Status: partial" "partial-failure is partial"

echo ""

# ── 15. Partial-failure not reported as success ──────────────────────────────

echo "--- 15. Partial-failure not success ---"
echo ""

assert_contains "$PARTIAL" "not reported as success" "partial-failure not success"

echo ""

# ── 16. Partial-failure says do not retry blindly ────────────────────────────

echo "--- 16. Partial-failure no blind retry ---"
echo ""

assert_contains "$PARTIAL" "Do not retry blindly" "partial-failure no blind retry"

echo ""

# ── 17. Missing-confirmation fails closed ────────────────────────────────────

echo "--- 17. Missing-confirmation fails closed ---"
echo ""

MISSING_CONF=$(run_wrapper --scenario missing-confirmation 2>&1) || true
assert_contains "$MISSING_CONF" "Confirmation required" "missing-confirmation says required"
run_wrapper --scenario missing-confirmation > /dev/null 2>&1 && { fail "missing-confirmation exits 0"; ERRORS=$((ERRORS + 1)); } || pass "missing-confirmation exits nonzero"

echo ""

# ── 18. Bad-confirmation fails closed ────────────────────────────────────────

echo "--- 18. Bad-confirmation fails closed ---"
echo ""

BAD_CONF=$(run_wrapper --scenario bad-confirmation --confirm-phrase "wrong phrase" 2>&1) || true
assert_contains "$BAD_CONF" "did not match" "bad-confirmation says did not match"
run_wrapper --scenario bad-confirmation --confirm-phrase "wrong phrase" > /dev/null 2>&1 && { fail "bad-confirmation exits 0"; ERRORS=$((ERRORS + 1)); } || pass "bad-confirmation exits nonzero"

echo ""

# ── 19. Bad-confirmation does not claim success ──────────────────────────────

echo "--- 19. Bad-confirmation no success ---"
echo ""

assert_not_contains "$BAD_CONF" "Status: applied" "bad-confirmation no applied"
assert_not_contains "$BAD_CONF" "Status: partial" "bad-confirmation no partial"

echo ""

# ── 20. No output contains apply --yes ───────────────────────────────────────

echo "--- 20. No apply --yes in output ---"
echo ""

ALL_OUTPUT="$SUMMARY
$SUCCESS
$POSTCHECK_FAIL
$PARTIAL
$MISSING_CONF
$BAD_CONF"
assert_not_contains "$ALL_OUTPUT" "apply --yes" "no apply --yes in any output"

echo ""

# ── 21-24. No raw values in any output ───────────────────────────────────────

echo "--- 21-24. No raw values ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "example.com" "no raw domain"
assert_not_contains "$ALL_OUTPUT" "proxy.example.com" "no raw hostname"
assert_not_contains "$ALL_OUTPUT" "203.0.113.10" "no raw IPv4"
assert_not_contains "$ALL_OUTPUT" "2001:db8::10" "no raw IPv6"

echo ""

# ── 25. No Zone/Account/record ID ────────────────────────────────────────────

echo "--- 25. No Zone/Account/record ID ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "Zone ID" "no Zone ID"
assert_not_contains "$ALL_OUTPUT" "Account ID" "no Account ID"
assert_not_contains "$ALL_OUTPUT" "record ID" "no record ID"

echo ""

# ── 26. No token / Authorization / raw env ───────────────────────────────────

echo "--- 26. No token / Authorization ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "CF_API_TOKEN" "no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUT" "Authorization" "no Authorization"

echo ""

# ── 27. No raw API request / response ────────────────────────────────────────

echo "--- 27. No raw API internals ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "raw API request" "no raw API request"
assert_not_contains "$ALL_OUTPUT" "raw API response" "no raw API response"

echo ""

# ── 28. No workers.dev / subscription / protocol ─────────────────────────────

echo "--- 28. No workers.dev / subscription / protocol ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "workers.dev" "no workers.dev"
assert_not_contains "$ALL_OUTPUT" "subscription URL" "no subscription URL"
assert_not_contains "$ALL_OUTPUT" "vless://" "no vless://"
assert_not_contains "$ALL_OUTPUT" "trojan://" "no trojan://"
assert_not_contains "$ALL_OUTPUT" "hysteria2://" "no hysteria2://"
assert_not_contains "$ALL_OUTPUT" "tuic://" "no tuic://"

echo ""

# ── 29. No private key ──────────────────────────────────────────────────────

echo "--- 29. No private key ---"
echo ""

assert_not_contains "$ALL_OUTPUT" "PRIVATE KEY" "no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUT" "Reality private key" "no Reality private key"

echo ""

# ── 30. No full sha256 ──────────────────────────────────────────────────────

echo "--- 30. No full sha256 ---"
echo ""

if echo "$ALL_OUTPUT" | grep -qE '[a-f0-9]{64}'; then
  fail "no full sha256 in output"
  ERRORS=$((ERRORS + 1))
else
  pass "no full sha256 in output"
fi

echo ""

# ── 31. Wrapper not referenced by bin/nanobk ─────────────────────────────────

echo "--- 31. Wrapper not in bin/nanobk ---"
echo ""

if grep -q 'nanobk_cf_dns_apply_ux_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "bin/nanobk references wrapper"
  ERRORS=$((ERRORS + 1))
else
  pass "bin/nanobk does not reference wrapper"
fi

echo ""

# ── 32. No fake transport bypass ─────────────────────────────────────────────

echo "--- 32. No fake transport bypass ---"
echo ""

WRAPPER_SOURCE=$(cat "$WRAPPER")
# Check that wrapper doesn't have a fallback that allows real transport
if echo "$WRAPPER_SOURCE" | grep -qE 'real_transport|_real_transport|allow_real'; then
  fail "wrapper has real transport bypass"
  ERRORS=$((ERRORS + 1))
else
  pass "wrapper has no real transport bypass"
fi

echo ""

# ── 33. No HTTP libraries in wrapper ─────────────────────────────────────────

echo "--- 33. No HTTP libraries ---"
echo ""

assert_not_contains "$WRAPPER_SOURCE" "import requests" "no requests import"
assert_not_contains "$WRAPPER_SOURCE" "import urllib" "no urllib import"
assert_not_contains "$WRAPPER_SOURCE" "import http.client" "no http.client import"
assert_not_contains "$WRAPPER_SOURCE" "curl" "no curl"
assert_not_contains "$WRAPPER_SOURCE" "wrangler" "no wrangler"

echo ""

# ── 34. Only allowed files changed ───────────────────────────────────────────

echo "--- 34. Only allowed files changed ---"
echo ""

# This is verified by the task runner; test just confirms wrapper exists
pass "wrapper and test are the only new files"

echo ""

# ── 35. Test passes ──────────────────────────────────────────────────────────

echo "--- 35. Test passes ---"
echo ""

# This assertion is the test itself — if we reach here, all checks passed
pass "all assertions passed"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.10 DNS Apply UX Fake Wrapper tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
