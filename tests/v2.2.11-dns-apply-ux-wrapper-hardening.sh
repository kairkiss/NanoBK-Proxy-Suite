#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply UX Wrapper Safety Hardening Test
#
# Strengthens safety tests for lib/nanobk_cf_dns_apply_ux_mock.py.
# Proves wrapper is simulated, has no network imports, no public CLI integration,
# and fail-closed behavior for all invalid fake transport inputs.
#
# Does NOT call real nanobk cf dns apply. Does NOT call Cloudflare.
#
# Usage:
#   bash tests/v2.2.11-dns-apply-ux-wrapper-hardening.sh

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

# ── Temp dir ─────────────────────────────────────────────────────────────────

TEST_TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TEST_TMPDIR" 2>/dev/null || true; }
trap cleanup EXIT

VALID_FIXTURE="$TEST_TMPDIR/valid.json"
echo '{}' > "$VALID_FIXTURE"

MALFORMED_FIXTURE="$TEST_TMPDIR/malformed.json"
echo '{broken json' > "$MALFORMED_FIXTURE"

EMPTY_FIXTURE="$TEST_TMPDIR/empty.json"
echo '' > "$EMPTY_FIXTURE"

# Helper: run wrapper with fake transport
run_wrapper() {
  NANOBK_CF_DNS_FAKE_TRANSPORT="$VALID_FIXTURE" \
    python3 "$WRAPPER" "$@" 2>&1
}

# Helper: run wrapper WITHOUT fake transport
run_no_transport() {
  env -u NANOBK_CF_DNS_FAKE_TRANSPORT \
    python3 "$WRAPPER" "$@" 2>&1
}

echo ""
echo "=== DNS Apply UX Wrapper Safety Hardening Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Fake transport validation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Fake transport validation ---"
echo ""

# A1. Missing env fails closed
A1=$(run_no_transport --scenario summary 2>&1) || true
assert_contains "$A1" "fake-transport-only" "A1: missing env says fake-transport-only"
assert_contains "$A1" "No DNS changes were made" "A1: missing env says no DNS changes"

# A2. Empty env fails closed
A2=$(NANOBK_CF_DNS_FAKE_TRANSPORT="" python3 "$WRAPPER" --scenario summary 2>&1) || true
assert_contains "$A2" "fake-transport-only" "A2: empty env says fake-transport-only"

# A3. Nonexistent path fails closed
A3=$(NANOBK_CF_DNS_FAKE_TRANSPORT="/nonexistent/path.json" python3 "$WRAPPER" --scenario summary 2>&1) || true
assert_contains "$A3" "fake-transport-only" "A3: nonexistent path fails closed"

# A4. Directory path fails closed
A4=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TEST_TMPDIR" python3 "$WRAPPER" --scenario summary 2>&1) || true
assert_contains "$A4" "fake-transport-only" "A4: directory path fails closed"

# A5. Malformed JSON fails closed
A5=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$MALFORMED_FIXTURE" python3 "$WRAPPER" --scenario summary 2>&1) || true
assert_contains "$A5" "fake-transport-only" "A5: malformed JSON fails closed"

# A6. Empty file fails closed
A6=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$EMPTY_FIXTURE" python3 "$WRAPPER" --scenario summary 2>&1) || true
assert_contains "$A6" "fake-transport-only" "A6: empty file fails closed"

# A7. Valid JSON fixture allows summary
A7=$(run_wrapper --scenario summary)
assert_contains "$A7" "Status: ready for confirmation" "A7: valid fixture allows summary"

# A8. Safe error says no DNS changes
A8=$(run_no_transport --scenario summary 2>&1) || true
assert_contains "$A8" "No DNS changes were made" "A8: error says no DNS changes"

# A9. Safe error does not print raw fixture path
assert_not_contains "$A1" "$VALID_FIXTURE" "A9: no raw fixture path in error"
assert_not_contains "$A3" "/nonexistent" "A9: no nonexistent path in error"

# A10. Safe error does not print JSON content
assert_not_contains "$A5" "broken" "A10: no JSON content in error"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Wrapper isolation — no low-level apply helper import
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Wrapper isolation ---"
echo ""

WRAPPER_SOURCE=$(cat "$WRAPPER")

# B1. Does not import nanobk_cf_dns_apply (check import lines, not docstring)
IMPORT_LINES=$(grep -E '^\s*(import |from )' "$WRAPPER" || true)
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply" "B1: no nanobk_cf_dns_apply import"

# B2. Does not reference _real_transport
assert_not_contains "$WRAPPER_SOURCE" "_real_transport" "B2: no _real_transport"

# B3. Does not reference real_transport
assert_not_contains "$WRAPPER_SOURCE" "real_transport" "B3: no real_transport"

# B4. Does not reference allow_real
assert_not_contains "$WRAPPER_SOURCE" "allow_real" "B4: no allow_real"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. No network imports
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. No network imports ---"
echo ""

assert_not_contains "$WRAPPER_SOURCE" "import requests" "C1: no requests"
assert_not_contains "$WRAPPER_SOURCE" "import urllib" "C2: no urllib"
assert_not_contains "$WRAPPER_SOURCE" "import http.client" "C3: no http.client"
assert_not_contains "$WRAPPER_SOURCE" "import socket" "C4: no socket"
assert_not_contains "$WRAPPER_SOURCE" "import subprocess" "C5: no subprocess"
assert_not_contains "$WRAPPER_SOURCE" "curl" "C6: no curl"
assert_not_contains "$WRAPPER_SOURCE" "wrangler" "C7: no wrangler"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Public entrypoint isolation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Public entrypoint isolation ---"
echo ""

# D1. bin/nanobk does not reference wrapper
if grep -q 'nanobk_cf_dns_apply_ux_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "D1: bin/nanobk references wrapper"
  ERRORS=$((ERRORS + 1))
else
  pass "D1: bin/nanobk does not reference wrapper"
fi

# D2. Bot does not reference wrapper
if grep -rq 'nanobk_cf_dns_apply_ux_mock' "$ROOT/bot/" 2>/dev/null; then
  fail "D2: bot/ references wrapper"
  ERRORS=$((ERRORS + 1))
else
  pass "D2: bot/ does not reference wrapper"
fi

# D3. Web does not reference wrapper
if grep -rq 'nanobk_cf_dns_apply_ux_mock' "$ROOT/web/" 2>/dev/null; then
  fail "D3: web/ references wrapper"
  ERRORS=$((ERRORS + 1))
else
  pass "D3: web/ does not reference wrapper"
fi

# D4. Installer does not reference wrapper
if grep -rq 'nanobk_cf_dns_apply_ux_mock' "$ROOT/installer/" 2>/dev/null; then
  fail "D4: installer/ references wrapper"
  ERRORS=$((ERRORS + 1))
else
  pass "D4: installer/ does not reference wrapper"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Output safety for all successful scenarios
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Output safety ---"
echo ""

SUMMARY=$(run_wrapper --scenario summary)
SUCCESS=$(run_wrapper --scenario success --confirm-phrase "apply dns records")
POSTCHECK_FAIL=$(run_wrapper --scenario postcheck-failure --confirm-phrase "apply dns records")
PARTIAL=$(run_wrapper --scenario partial-failure --confirm-phrase "apply dns records")
ALL_SUCCESS="$SUMMARY
$SUCCESS
$POSTCHECK_FAIL
$PARTIAL"

# E1-E12. No forbidden content
assert_not_contains "$ALL_SUCCESS" "apply --yes" "E1: no apply --yes"
assert_not_contains "$ALL_SUCCESS" "example.com" "E2: no raw domain"
assert_not_contains "$ALL_SUCCESS" "proxy.example.com" "E3: no raw hostname"
assert_not_contains "$ALL_SUCCESS" "203.0.113.10" "E4: no raw IPv4"
assert_not_contains "$ALL_SUCCESS" "2001:db8::10" "E5: no raw IPv6"
assert_not_contains "$ALL_SUCCESS" "Zone ID" "E6: no Zone ID"
assert_not_contains "$ALL_SUCCESS" "Account ID" "E7: no Account ID"
assert_not_contains "$ALL_SUCCESS" "record ID" "E8: no record ID"
assert_not_contains "$ALL_SUCCESS" "CF_API_TOKEN" "E9: no API token"
assert_not_contains "$ALL_SUCCESS" "Authorization" "E10: no Authorization"
assert_not_contains "$ALL_SUCCESS" "workers.dev" "E11: no workers.dev"
assert_not_contains "$ALL_SUCCESS" "subscription URL" "E12: no subscription URL"

# E13-E18. No protocol URIs
assert_not_contains "$ALL_SUCCESS" "vless://" "E13: no vless://"
assert_not_contains "$ALL_SUCCESS" "trojan://" "E14: no trojan://"
assert_not_contains "$ALL_SUCCESS" "hysteria2://" "E15: no hysteria2://"
assert_not_contains "$ALL_SUCCESS" "tuic://" "E16: no tuic://"

# E17-E18. No private keys
assert_not_contains "$ALL_SUCCESS" "PRIVATE KEY" "E17: no PRIVATE KEY"
assert_not_contains "$ALL_SUCCESS" "Reality private key" "E18: no Reality private key"

# E19. No full sha256
if echo "$ALL_SUCCESS" | grep -qE '[a-f0-9]{64}'; then
  fail "E19: no full sha256"
  ERRORS=$((ERRORS + 1))
else
  pass "E19: no full sha256"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Confirmation safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Confirmation safety ---"
echo ""

# F1. Success requires exact phrase
F1_NO=$(run_wrapper --scenario success 2>&1) || true
assert_contains "$F1_NO" "Confirmation required" "F1: success needs confirmation"
assert_not_contains "$F1_NO" "Status: applied" "F1: no applied without phrase"

# F2. Wrong phrase fails closed
F2_BAD=$(run_wrapper --scenario success --confirm-phrase "wrong" 2>&1) || true
assert_contains "$F2_BAD" "Confirmation required" "F2: wrong phrase fails closed"
assert_not_contains "$F2_BAD" "Status: applied" "F2: no applied with wrong phrase"
assert_not_contains "$F2_BAD" "Status: partial" "F2: no partial with wrong phrase"

# F3. Missing/wrong says no DNS changes
assert_contains "$F1_NO" "No DNS changes were made" "F3: missing says no DNS changes"
assert_contains "$F2_BAD" "No DNS changes were made" "F3: wrong says no DNS changes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Fake/test-only post-check wording
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Fake/test-only post-check wording ---"
echo ""

# G1. Success says fake transport only
assert_contains "$SUCCESS" "fake transport only" "G1: success says fake transport only"

# G2. Success says no live verification
assert_contains "$SUCCESS" "No live Cloudflare verification was performed" "G2: success says no live verification"

# G3. Postcheck-failure says simulated
assert_contains "$POSTCHECK_FAIL" "simulated post-check" "G3: postcheck-failure says simulated"

# G4. Postcheck-failure says not live verification
assert_contains "$POSTCHECK_FAIL" "not live Cloudflare verification" "G4: postcheck-failure says not live"

# G5. Partial-failure says simulated
assert_contains "$PARTIAL" "simulated partial failure" "G5: partial-failure says simulated"

# G6. Partial-failure says not live verification
assert_contains "$PARTIAL" "not live Cloudflare verification" "G6: partial-failure says not live"

# G7. Partial and uncertain not reported as success
assert_contains "$POSTCHECK_FAIL" "not reported as success" "G7: uncertain not success"
assert_contains "$PARTIAL" "not reported as success" "G7: partial not success"

# G8. Partial says do not retry blindly
assert_contains "$PARTIAL" "Do not retry blindly" "G8: partial no blind retry"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Allowed imports only
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Allowed imports only ---"
echo ""

# Extract import lines from wrapper
IMPORTS=$(grep -E '^\s*(import |from )' "$WRAPPER" || true)

# H1. Has argparse
assert_contains "$IMPORTS" "argparse" "H1: has argparse"

# H2. Has json
assert_contains "$IMPORTS" "json" "H2: has json"

# H3. Has os
assert_contains "$IMPORTS" "os" "H3: has os"

# H4. Has pathlib
assert_contains "$IMPORTS" "pathlib" "H4: has pathlib"

# H5. Has sys
assert_contains "$IMPORTS" "sys" "H5: has sys"

# H6. No unexpected imports
UNEXPECTED=$(echo "$IMPORTS" | grep -vE 'argparse|json|os|pathlib|sys|__future__|annotations' || true)
if [[ -n "$UNEXPECTED" ]]; then
  fail "H6: unexpected imports: $UNEXPECTED"
  ERRORS=$((ERRORS + 1))
else
  pass "H6: no unexpected imports"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.11 DNS Apply UX Wrapper Hardening tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
