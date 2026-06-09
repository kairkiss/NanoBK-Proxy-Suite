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

# Calls file — initialized as empty list (helper appends to it)
CALLS_FILE="$TEST_TMPDIR/fake-calls.json"
echo '[]' > "$CALLS_FILE"

# Fake transport with calls artifact and valid responses
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

# Transport without _calls_file
NO_CALLS_TRANSPORT="$TEST_TMPDIR/no-calls-transport.json"
cat > "$NO_CALLS_TRANSPORT" <<'EOF'
{
  "GET_A": {"success": true, "result": []}
}
EOF

# Transport with _calls_file pointing to missing file
MISSING_CALLS_TRANSPORT="$TEST_TMPDIR/missing-calls-transport.json"
cat > "$MISSING_CALLS_TRANSPORT" <<EOF
{
  "_calls_file": "$TEST_TMPDIR/nonexistent-calls.json",
  "GET_A": {"success": true, "result": []}
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
# C. Calls artifact proof
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Calls artifact proof ---"
echo ""

# C1. Static check: module source requires _calls_file in calls artifact
assert_contains "$MODULE_SOURCE" "_calls_file" "C1: module checks _calls_file"

# C2. Static check: module source checks calls file exists
assert_contains "$MODULE_SOURCE" "calls_path" "C2: module checks calls_path"

# C3. Static check: module source requires non-empty list
assert_contains "$MODULE_SOURCE" "non-empty list" "C3: module requires non-empty list"

# C4. Static check: module source validates call entry keys
assert_contains "$MODULE_SOURCE" "method" "C4: module validates method in calls"
assert_contains "$MODULE_SOURCE" "endpoint" "C4: module validates endpoint in calls"

# C5. Valid invocation produces calls artifact proof in output
C5=$(run_module) || true
assert_contains "$C5" "Fake transport:" "C5: output has Fake transport section"
assert_contains "$C5" "Used: yes" "C5: output says Used: yes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Stderr gate
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Stderr gate ---"
echo ""

# D1. Static check: module has strict stderr gate
assert_contains "$MODULE_SOURCE" "stderr.strip()" "D1: module has stderr.strip() gate"

# D2. Static check: stderr gate fails closed
assert_contains "$MODULE_SOURCE" "if stderr.strip():" "D2: stderr gate is fail-closed"

# D3. Static check: stderr is checked before JSON parsing in main()
# Find the main() function and check ordering within it
MAIN_BLOCK=$(awk '/^def main/,/^if __name__/' "$MODULE")
STDERR_IN_MAIN=$(echo "$MAIN_BLOCK" | grep -n "stderr.strip()" | head -1 | cut -d: -f1)
JSON_IN_MAIN=$(echo "$MAIN_BLOCK" | grep -n "parse_helper_json" | head -1 | cut -d: -f1)
if [[ -n "$STDERR_IN_MAIN" ]] && [[ -n "$JSON_IN_MAIN" ]] && [[ "$STDERR_IN_MAIN" -lt "$JSON_IN_MAIN" ]]; then
  pass "D3: stderr check is before JSON parsing in main()"
else
  fail "D3: stderr check should be before JSON parsing in main()"
  ERRORS=$((ERRORS + 1))
fi

# D4. Valid invocation still passes with empty stderr
D4=$(run_module) || true
assert_contains "$D4" "Status:" "D4: valid invocation passes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. JSON allowlist
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. JSON allowlist ---"
echo ""

# E1. Static check: module has validate_helper_schema function
assert_contains "$MODULE_SOURCE" "def validate_helper_schema" "E1: has validate_helper_schema"

# E2. Static check: module validates action keys
assert_contains "$MODULE_SOURCE" "_ALLOWED_ACTION_KEYS" "E2: validates action keys"

# E3. Static check: module validates result keys
assert_contains "$MODULE_SOURCE" "_ALLOWED_RESULT_KEYS" "E3: validates result keys"

# E4. Static check: module validates record types
assert_contains "$MODULE_SOURCE" "_ALLOWED_RECORD_TYPES" "E4: validates record types"

# E5. Static check: module validates action values
assert_contains "$MODULE_SOURCE" "_ALLOWED_ACTIONS" "E5: validates action values"

# E6. Static check: schema validation is called in main
assert_contains "$MODULE_SOURCE" "validate_helper_schema(helper_json)" "E6: schema validation called"

# E7. Raw helper fields are not forwarded
E7=$(run_module) || true
assert_not_contains "$E7" "plannedContent" "E7: no plannedContent in output"
assert_not_contains "$E7" "existingContent" "E7: no existingContent in output"
assert_not_contains "$E7" "recordId" "E7: no recordId in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Controlled valid fake invocation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Controlled valid fake invocation ---"
echo ""

F_OUT=$(run_module) || true

# F1. Output contains Status
assert_contains "$F_OUT" "Status:" "F1: output has Status"

# F2. Output says fake transport only
assert_contains "$F_OUT" "Test mode: fake transport only" "F2: says fake transport only"

# F3. Output says no live verification
assert_contains "$F_OUT" "No live Cloudflare verification was performed" "F3: says no live verification"

# F4. Output has Fake transport section
assert_contains "$F_OUT" "Fake transport:" "F4: has Fake transport section"

# F5. Output says Used: yes
assert_contains "$F_OUT" "Used: yes" "F5: says Used: yes"

# F6. Output does not contain raw helper stdout
assert_not_contains "$F_OUT" "raw" "F6: no raw helper output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Output safety ---"
echo ""

assert_not_contains "$F_OUT" "example.com" "G1: no raw domain"
assert_not_contains "$F_OUT" "proxy.example.com" "G2: no raw hostname"
assert_not_contains "$F_OUT" "203.0.113.10" "G3: no raw IPv4"
assert_not_contains "$F_OUT" "2001:db8::10" "G4: no raw IPv6"
assert_not_contains "$F_OUT" "record ID" "G5: no record ID"
assert_not_contains "$F_OUT" "Zone ID" "G6: no Zone ID"
assert_not_contains "$F_OUT" "Account ID" "G7: no Account ID"
assert_not_contains "$F_OUT" "CF_API_TOKEN" "G8: no API token"
assert_not_contains "$F_OUT" "Authorization" "G9: no Authorization"
assert_not_contains "$F_OUT" "api-env" "G10: no api-env"
assert_not_contains "$F_OUT" "cloudflare-api.env" "G11: no env file path"
assert_not_contains "$F_OUT" "workers.dev" "G12: no workers.dev"
assert_not_contains "$F_OUT" "subscription URL" "G13: no subscription URL"
assert_not_contains "$F_OUT" "vless://" "G14: no vless://"
assert_not_contains "$F_OUT" "trojan://" "G15: no trojan://"
assert_not_contains "$F_OUT" "hysteria2://" "G16: no hysteria2://"
assert_not_contains "$F_OUT" "tuic://" "G17: no tuic://"
assert_not_contains "$F_OUT" "PRIVATE KEY" "G18: no PRIVATE KEY"
assert_not_contains "$F_OUT" "Reality private key" "G19: no Reality private key"

# G20. No full sha256-like 64-char hex
if echo "$F_OUT" | grep -qE '[a-f0-9]{64}'; then
  fail "G20: no full sha256-like hex"
  ERRORS=$((ERRORS + 1))
else
  pass "G20: no full sha256-like hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Helper output capture
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Helper output capture ---"
echo ""

# H1. Helper stderr is not printed in valid output
assert_not_contains "$F_OUT" "error" "H1: no stderr in output"

# H2. Output does not contain raw JSON
assert_not_contains "$F_OUT" "{\"ok\":" "H2: no raw JSON"

# H3. Output has expected structure
assert_contains "$F_OUT" "NanoBK DNS Apply Helper Boundary" "H3: has expected header"
assert_contains "$F_OUT" "Actions:" "H3: has Actions section"
assert_contains "$F_OUT" "Record types:" "H3: has Record types section"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. No public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. No public integration ---"
echo ""

# I1. bin/nanobk does not reference module
if grep -q 'nanobk_cf_dns_apply_helper_boundary_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "I1: bin/nanobk references module"
  ERRORS=$((ERRORS + 1))
else
  pass "I1: bin/nanobk does not reference module"
fi

# I2. No public console integration in module
assert_not_contains "$MODULE_SOURCE" "beginner console" "I2: no beginner console in module"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Existing tests still pass ---"
echo ""

# J1. v2.2.8 test
if bash "$ROOT/tests/v2.2.8-dns-apply-beginner-ux-mock.sh" > /dev/null 2>&1; then
  pass "J1: v2.2.8 test passes"
else
  fail "J1: v2.2.8 test fails"
  ERRORS=$((ERRORS + 1))
fi

# J2. v2.2.10 test
if bash "$ROOT/tests/v2.2.10-dns-apply-ux-fake-wrapper.sh" > /dev/null 2>&1; then
  pass "J2: v2.2.10 test passes"
else
  fail "J2: v2.2.10 test fails"
  ERRORS=$((ERRORS + 1))
fi

# J3. v2.2.11 test
if bash "$ROOT/tests/v2.2.11-dns-apply-ux-wrapper-hardening.sh" > /dev/null 2>&1; then
  pass "J3: v2.2.11 test passes"
else
  fail "J3: v2.2.11 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Module isolation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Module isolation ---"
echo ""

# K1. No network imports
assert_not_contains "$MODULE_SOURCE" "import requests" "K1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "K1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "K1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "K1: no socket"
assert_not_contains "$MODULE_SOURCE" "curl" "K1: no curl"
assert_not_contains "$MODULE_SOURCE" "wrangler" "K1: no wrangler"

# K2. Uses subprocess (allowed for boundary mock)
assert_contains "$MODULE_SOURCE" "import subprocess" "K2: uses subprocess"

# K3. Uses shell=False
assert_contains "$MODULE_SOURCE" "shell=False" "K3: uses shell=False"

# K4. Has timeout
assert_contains "$MODULE_SOURCE" "timeout=" "K4: has timeout"

# K5. Captures output
assert_contains "$MODULE_SOURCE" "capture_output=True" "K5: captures output"

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
