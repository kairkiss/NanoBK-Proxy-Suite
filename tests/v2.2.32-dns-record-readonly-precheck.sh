#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Record Read-only Precheck Test
#
# Tests the non-public DNS record read-only GET precheck in the dryrun wrapper.
# Uses a local mock HTTP server. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.32-dns-record-readonly-precheck.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.32"

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

echo ""
echo "=== DNS Record Read-only Precheck Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Start local mock HTTP server
# ══════════════════════════════════════════════════════════════════════════════

MOCK_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
MOCK_SERVER_PID=""

# Create mock server script
MOCK_SCRIPT=$(mktemp)
cat > "$MOCK_SCRIPT" << 'MOCKEOF'
import http.server
import json
import sys

class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/client/v4/user/tokens/verify":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            body = json.dumps({"success": True, "result": {"id": "fake", "status": "active"}})
            self.wfile.write(body.encode())

        elif "/client/v4/zones/" in self.path and "/dns_records" in self.path:
            # Check query params to determine mock response
            query = self.path.split("?")[1] if "?" in self.path else ""
            params = dict(p.split("=", 1) for p in query.split("&") if "=" in p)
            name = params.get("name", "")
            rtype = params.get("type", "A")

            # Determine response based on the mock scenario
            # Read scenario from env
            scenario = self.server.scenario

            if scenario == "safe_create":
                # Zero records
                body = json.dumps({"success": True, "result": []})
            elif scenario == "cname_conflict":
                # CNAME conflict
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-cname-001", "type": "CNAME", "name": name, "content": "other.example.com", "comment": ""}
                ]})
            elif scenario == "existing_unmanaged":
                # Existing unmanaged A record
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-a-001", "type": "A", "name": name, "content": "192.0.2.1", "comment": "some other comment"}
                ]})
            elif scenario == "existing_managed":
                # Existing managed test record
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-a-002", "type": "A", "name": name, "content": "192.0.2.2", "comment": "nanobk-test managed"}
                ]})
            elif scenario == "multiple_records":
                # Multiple matching records
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-a-003", "type": "A", "name": name, "content": "192.0.2.3", "comment": ""},
                    {"id": "fake-a-004", "type": "A", "name": name, "content": "192.0.2.4", "comment": ""}
                ]})
            else:
                body = json.dumps({"success": True, "result": []})

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        self.send_response(405)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress server logs

port = int(sys.argv[1])
scenario = sys.argv[2] if len(sys.argv) > 2 else "safe_create"
server = http.server.HTTPServer(("127.0.0.1", port), MockHandler)
server.scenario = scenario
server.serve_forever()
MOCKEOF

# Function to start mock server with a scenario
start_mock() {
  local scenario="$1"
  if [[ -n "$MOCK_SERVER_PID" ]]; then
    kill "$MOCK_SERVER_PID" 2>/dev/null || true
    sleep 0.2
  fi
  python3 "$MOCK_SCRIPT" "$MOCK_PORT" "$scenario" &
  MOCK_SERVER_PID=$!
  sleep 0.5
}

# Function to create temp plan with correct port
make_plan() {
  local fixture="$1"
  local temp_plan=$(mktemp)
  sed "s/__PORT__/$MOCK_PORT/g" "$fixture" > "$temp_plan"
  echo "$temp_plan"
}

# Cleanup on exit
cleanup() {
  kill "$MOCK_SERVER_PID" 2>/dev/null || true
  rm -f "$MOCK_SCRIPT"
}
trap cleanup EXIT

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. No probe without flag
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. No probe without flag ---"
echo ""

A_OUT=$("$RUNNER" --plan "$FIXTURES/runner_dns_precheck_no_probe_no_call.json" 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no probe exits 0"
else
  fail "A1: no probe should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_OUT" "DNS record GET called: no" "A2: dns record get called no"
assert_contains "$A_OUT" "Cloudflare GET called: no" "A3: cf get called no"
assert_contains "$A_OUT" "Can query: no" "A4: can query no"
assert_contains "$A_OUT" "DNS record precheck enabled: no" "A5: dns precheck disabled"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Safe create candidate
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Safe create candidate ---"
echo ""

start_mock "safe_create"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_safe_create_candidate.json")

B_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "0" ]]; then
  pass "B1: safe create exits 0"
else
  fail "B1: safe create should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Cloudflare GET called: yes" "B2: cf get called yes"
assert_contains "$B_OUT" "Cloudflare GET succeeded: yes" "B3: cf get succeeded yes"
assert_contains "$B_OUT" "DNS record GET called: yes" "B4: dns record get called yes"
assert_contains "$B_OUT" "DNS record GET succeeded: yes" "B5: dns record get succeeded yes"
assert_contains "$B_OUT" "Same-name CNAME absent: yes" "B6: cname absent yes"
assert_contains "$B_OUT" "Existing unmanaged record absent: yes" "B7: unmanaged absent yes"
assert_contains "$B_OUT" "Create-only-first safe: yes" "B8: create safe yes"
assert_contains "$B_OUT" "Record count category: zero" "B9: count zero"
assert_contains "$B_OUT" "Can apply: no" "B10: can apply no"
assert_contains "$B_OUT" "Mutation allowed: no" "B11: mutation allowed no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. CNAME conflict
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. CNAME conflict ---"
echo ""

start_mock "cname_conflict"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_cname_conflict.json")

C_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && C_RC=0 || C_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$C_RC" != "0" ]]; then
  pass "C1: cname conflict exits non-zero ($C_RC)"
else
  fail "C1: cname conflict should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "same-name CNAME present" "C2: cname present reason"
assert_contains "$C_OUT" "Same-name CNAME absent: no" "C3: cname absent no"
assert_contains "$C_OUT" "Create-only-first safe: no" "C4: create safe no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Existing unmanaged record
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Existing unmanaged record ---"
echo ""

start_mock "existing_unmanaged"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_existing_unmanaged.json")

D_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && D_RC=0 || D_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$D_RC" != "0" ]]; then
  pass "D1: existing unmanaged exits non-zero ($D_RC)"
else
  fail "D1: existing unmanaged should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "existing unmanaged record present" "D2: unmanaged reason"
assert_contains "$D_OUT" "Existing unmanaged record absent: no" "D3: unmanaged absent no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Existing managed test record
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Existing managed test record ---"
echo ""

start_mock "existing_managed"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_existing_managed_test_record.json")

E_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && E_RC=0 || E_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$E_RC" != "0" ]]; then
  pass "E1: existing managed exits non-zero ($E_RC)"
else
  fail "E1: existing managed should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "managed test record present" "E2: managed reason"
assert_contains "$E_OUT" "Existing managed test record: yes" "E3: managed yes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Multiple records
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Multiple records ---"
echo ""

start_mock "multiple_records"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_multiple_records.json")

F_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && F_RC=0 || F_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$F_RC" != "0" ]]; then
  pass "F1: multiple records exits non-zero ($F_RC)"
else
  fail "F1: multiple records should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "multiple matching records" "F2: multiple reason"
assert_contains "$F_OUT" "Record count category: multiple" "F3: count multiple"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Timeout
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Timeout ---"
echo ""

# Don't start mock for timeout test (port 1 is unreachable)
TEMP_PLAN=$(make_plan "$FIXTURES/runner_dns_precheck_timeout.json")

G_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && G_RC=0 || G_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$G_RC" != "0" ]]; then
  pass "G1: timeout exits non-zero ($G_RC)"
else
  fail "G1: timeout should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

# Token verify times out first, so DNS record precheck doesn't run
assert_contains "$G_OUT" "DNS record GET succeeded: unknown" "G2: dns get succeeded unknown (precheck not reached)"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Safety scan ---"
echo ""

ALL_OUTPUTS="$A_OUT $B_OUT $C_OUT $D_OUT $E_OUT $F_OUT $G_OUT"

assert_not_contains "$ALL_OUTPUTS" "fake_test_token_do_not_use" "H1: no fake token"
assert_not_contains "$ALL_OUTPUTS" "CLOUDFLARE_API_TOKEN" "H2: no CLOUDFLARE_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN" "H3: no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "safe_token.env" "H4: no safe_token.env"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_ZONE_ID_NOT_FOR_OUTPUT" "H5: no zone id"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_RECORD_NAME_NOT_FOR_OUTPUT" "H6: no record name"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_EXPECTED_CONTENT_NOT_FOR_OUTPUT" "H7: no expected content"
assert_not_contains "$ALL_OUTPUTS" "recordId" "H8: no recordId"
assert_not_contains "$ALL_OUTPUTS" "recordId" "H9: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "H10: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "H11: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "H12: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "raw API request" "H13: no raw API request"
assert_not_contains "$ALL_OUTPUTS" "raw API response" "H14: no raw API response"
assert_not_contains "$ALL_OUTPUTS" "/zones/" "H15: no /zones/"
assert_not_contains "$ALL_OUTPUTS" "dns_records" "H16: no dns_records"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "H17: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "H18: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "H19: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "H20: no apply --yes"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "H21: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "H21: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'dns-record-readonly-precheck\|readonly_dns_record_precheck\|dns_record_get_called' "$loc" 2>/dev/null; then
    fail "I1: $loc references precheck"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "I1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Compatibility
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Compatibility ---"
echo ""

if bash "$ROOT/tests/v2.2.31-readonly-cloudflare-get-probe.sh" > /dev/null 2>&1; then
  pass "J1: v2.2.31 test passes"
else
  fail "J1: v2.2.31 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.29-local-credential-precheck.sh" > /dev/null 2>&1; then
  pass "J2: v2.2.29 test passes"
else
  fail "J2: v2.2.29 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.32 DNS Record Read-only Precheck tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
