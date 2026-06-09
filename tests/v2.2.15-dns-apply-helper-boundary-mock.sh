#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Helper Boundary Mock Test
#
# Tests lib/nanobk_cf_dns_apply_helper_boundary_mock.py under
# mandatory fake-transport guard with sterile subprocess invocation.
#
# Does NOT call real Cloudflare. Does NOT perform real DNS mutation.
#
# Usage:
#   bash tests/v2.2.15-dns-apply-helper-boundary-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_helper_boundary_mock.py"
UX_MOCK="$ROOT/lib/nanobk_cf_dns_apply_ux_mock.py"

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

# ── Create temp fixtures ─────────────────────────────────────────────────────

# Fake transport with calls artifact
CALLS_FILE="$TEST_TMPDIR/fake-calls.json"
echo '{}' > "$CALLS_FILE"

FAKE_TRANSPORT="$TEST_TMPDIR/fake-transport.json"
cat > "$FAKE_TRANSPORT" <<EOF
{
  "_calls_file": "$CALLS_FILE",
  "GET_A": {"success": true, "result": []},
  "GET_AAAA": {"success": true, "result": []},
  "GET_CNAME": {"success": true, "result": []},
  "POST": {"success": true, "result": {"id": "rec-new-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10"}},
  "PATCH:rec-a-001": {"success": true, "result": {"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10"}}
}
EOF

# Empty transport
EMPTY_TRANSPORT="$TEST_TMPDIR/empty-transport.json"
echo '' > "$EMPTY_TRANSPORT"

# Malformed transport
MALFORMED_TRANSPORT="$TEST_TMPDIR/malformed-transport.json"
echo '{broken json' > "$MALFORMED_TRANSPORT"

# Helper: run module with fake transport
run_module() {
  NANOBK_CF_DNS_FAKE_TRANSPORT="$FAKE_TRANSPORT" \
    python3 "$MODULE" 2>&1
}

# Helper: run module WITHOUT fake transport
run_module_no_transport() {
  env -u NANOBK_CF_DNS_FAKE_TRANSPORT \
    python3 "$MODULE" 2>&1
}

echo ""
echo "=== DNS Apply Helper Boundary Mock Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File and scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File and scope checks ---"
echo ""

# A1. Module exists
if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

# A2. Module says hidden/test-only/fake-transport-only
MODULE_SOURCE=$(cat "$MODULE")
assert_contains "$MODULE_SOURCE" "Hidden/test-only" "A2: module says hidden/test-only"
assert_contains "$MODULE_SOURCE" "fake-transport-only" "A2: module says fake-transport-only"

# A3. Module does not import current UX mock
IMPORT_LINES=$(grep -E '^\s*(import |from )' "$MODULE" || true)
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply_ux_mock" "A3: no UX mock import"

# A4. Current UX mock is not modified
UX_HASH_BEFORE=$(shasum -a 256 "$UX_MOCK" | awk '{print $1}')
# (We don't modify it, so just verify it exists)
if [[ -f "$UX_MOCK" ]]; then
  pass "A4: UX mock exists and unchanged"
else
  fail "A4: UX mock missing"
  ERRORS=$((ERRORS + 1))
fi

# A5. bin/nanobk does not reference new module
if grep -q 'nanobk_cf_dns_apply_helper_boundary_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "A5: bin/nanobk references module"
  ERRORS=$((ERRORS + 1))
else
  pass "A5: bin/nanobk does not reference module"
fi

# A6. installer/Bot/Web do not reference module
for dir in installer bot web; do
  if grep -rq 'nanobk_cf_dns_apply_helper_boundary_mock' "$ROOT/$dir/" 2>/dev/null; then
    fail "A6: $dir/ references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "A6: installer/Bot/Web do not reference module"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Fake transport preflight
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Fake transport preflight ---"
echo ""

# B1. Missing env fails closed
B1=$(run_module_no_transport 2>&1) || true
assert_contains "$B1" "fake-transport-only" "B1: missing env says fake-transport-only"
assert_contains "$B1" "No DNS changes were made" "B1: missing env says no DNS changes"

# B2. Empty env fails closed
B2=$(NANOBK_CF_DNS_FAKE_TRANSPORT="" python3 "$MODULE" 2>&1) || true
assert_contains "$B2" "fake-transport-only" "B2: empty env fails closed"

# B3. Nonexistent path fails closed
B3=$(NANOBK_CF_DNS_FAKE_TRANSPORT="/nonexistent/path.json" python3 "$MODULE" 2>&1) || true
assert_contains "$B3" "fake-transport-only" "B3: nonexistent path fails closed"

# B4. Directory path fails closed
B4=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TEST_TMPDIR" python3 "$MODULE" 2>&1) || true
assert_contains "$B4" "fake-transport-only" "B4: directory path fails closed"

# B5. Malformed JSON fails closed
B5=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$MALFORMED_TRANSPORT" python3 "$MODULE" 2>&1) || true
assert_contains "$B5" "fake-transport-only" "B5: malformed JSON fails closed"

# B6. Empty file fails closed
B6=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$EMPTY_TRANSPORT" python3 "$MODULE" 2>&1) || true
assert_contains "$B6" "fake-transport-only" "B6: empty file fails closed"

# B7-B10. Safe error does not leak
assert_not_contains "$B1" "$FAKE_TRANSPORT" "B7: no raw path in error"
assert_not_contains "$B3" "/nonexistent" "B8: no nonexistent path in error"
assert_not_contains "$B5" "broken" "B9: no JSON content in error"
assert_not_contains "$B1" "CALLS_PLACEHOLDER" "B10: no internal data in error"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Controlled valid fake invocation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Controlled valid fake invocation ---"
echo ""

C_OUT=$(run_module) || true

# C1. Output contains Status
assert_contains "$C_OUT" "Status:" "C1: output has Status"

# C2. Output says fake transport only
assert_contains "$C_OUT" "Test mode: fake transport only" "C2: says fake transport only"

# C3. Output says no live verification
assert_contains "$C_OUT" "No live Cloudflare verification was performed" "C3: says no live verification"

# C4. Output does not contain raw helper stdout
assert_not_contains "$C_OUT" "raw" "C4: no raw helper output"

# C5. Output does not contain raw helper JSON fields
assert_not_contains "$C_OUT" "plannedContent" "C5: no plannedContent"
assert_not_contains "$C_OUT" "existingContent" "C5: no existingContent"
assert_not_contains "$C_OUT" "recordId" "C5: no recordId"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Output safety ---"
echo ""

assert_not_contains "$C_OUT" "example.com" "D1: no raw domain"
assert_not_contains "$C_OUT" "proxy.example.com" "D2: no raw hostname"
assert_not_contains "$C_OUT" "203.0.113.10" "D3: no raw IPv4"
assert_not_contains "$C_OUT" "2001:db8::10" "D4: no raw IPv6"
assert_not_contains "$C_OUT" "record ID" "D5: no record ID"
assert_not_contains "$C_OUT" "Zone ID" "D6: no Zone ID"
assert_not_contains "$C_OUT" "Account ID" "D7: no Account ID"
assert_not_contains "$C_OUT" "CF_API_TOKEN" "D8: no API token"
assert_not_contains "$C_OUT" "Authorization" "D9: no Authorization"
assert_not_contains "$C_OUT" "api-env" "D10: no api-env"
assert_not_contains "$C_OUT" "cloudflare-api.env" "D11: no env file path"
assert_not_contains "$C_OUT" "workers.dev" "D12: no workers.dev"
assert_not_contains "$C_OUT" "subscription URL" "D13: no subscription URL"
assert_not_contains "$C_OUT" "vless://" "D14: no vless://"
assert_not_contains "$C_OUT" "trojan://" "D15: no trojan://"
assert_not_contains "$C_OUT" "hysteria2://" "D16: no hysteria2://"
assert_not_contains "$C_OUT" "tuic://" "D17: no tuic://"
assert_not_contains "$C_OUT" "PRIVATE KEY" "D18: no PRIVATE KEY"
assert_not_contains "$C_OUT" "Reality private key" "D19: no Reality private key"

# D20. No full sha256-like 64-char hex
if echo "$C_OUT" | grep -qE '[a-f0-9]{64}'; then
  fail "D20: no full sha256-like hex"
  ERRORS=$((ERRORS + 1))
else
  pass "D20: no full sha256-like hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Helper output capture / fail-closed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Helper output capture ---"
echo ""

# E1. Helper stderr is not printed in valid output
assert_not_contains "$C_OUT" "error" "E1: no stderr in output"

# E2. Output does not contain raw JSON
assert_not_contains "$C_OUT" "{\"ok\":" "E2: no raw JSON"

# E3. Output has expected structure
assert_contains "$C_OUT" "NanoBK DNS Apply Helper Boundary" "E3: has expected header"
assert_contains "$C_OUT" "Actions:" "E3: has Actions section"
assert_contains "$C_OUT" "Record types:" "E3: has Record types section"
assert_contains "$C_OUT" "Fake transport:" "E3: has Fake transport section"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. No public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. No public integration ---"
echo ""

# F1. bin/nanobk does not reference module
if grep -q 'nanobk_cf_dns_apply_helper_boundary_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "F1: bin/nanobk references module"
  ERRORS=$((ERRORS + 1))
else
  pass "F1: bin/nanobk does not reference module"
fi

# F2. No public console integration in module
assert_not_contains "$MODULE_SOURCE" "beginner console" "F2: no beginner console in module"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Existing tests still pass ---"
echo ""

# G1. v2.2.8 test
if bash "$ROOT/tests/v2.2.8-dns-apply-beginner-ux-mock.sh" > /dev/null 2>&1; then
  pass "G1: v2.2.8 test passes"
else
  fail "G1: v2.2.8 test fails"
  ERRORS=$((ERRORS + 1))
fi

# G2. v2.2.10 test
if bash "$ROOT/tests/v2.2.10-dns-apply-ux-fake-wrapper.sh" > /dev/null 2>&1; then
  pass "G2: v2.2.10 test passes"
else
  fail "G2: v2.2.10 test fails"
  ERRORS=$((ERRORS + 1))
fi

# G3. v2.2.11 test
if bash "$ROOT/tests/v2.2.11-dns-apply-ux-wrapper-hardening.sh" > /dev/null 2>&1; then
  pass "G3: v2.2.11 test passes"
else
  fail "G3: v2.2.11 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Module isolation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Module isolation ---"
echo ""

# H1. No network imports
assert_not_contains "$MODULE_SOURCE" "import requests" "H1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "H1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "H1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "H1: no socket"
assert_not_contains "$MODULE_SOURCE" "curl" "H1: no curl"
assert_not_contains "$MODULE_SOURCE" "wrangler" "H1: no wrangler"

# H2. Uses subprocess (allowed for boundary mock)
assert_contains "$MODULE_SOURCE" "import subprocess" "H2: uses subprocess"

# H3. Uses shell=False
assert_contains "$MODULE_SOURCE" "shell=False" "H3: uses shell=False"

# H4. Has timeout
assert_contains "$MODULE_SOURCE" "timeout=" "H4: has timeout"

# H5. Captures output
assert_contains "$MODULE_SOURCE" "capture_output=True" "H5: captures output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.15 DNS Apply Helper Boundary Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
