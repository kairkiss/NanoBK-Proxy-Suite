#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner-Approved Live Create Test
#
# Tests the non-public owner-approved one-record live create path.
# Uses a local mock HTTP server. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.33-owner-approved-live-create.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.33"

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

APPROVAL_PHRASE="I UNDERSTAND THIS WILL CREATE ONE CLOUDFLARE DNS TEST RECORD"

echo ""
echo "=== Owner-Approved Live Create Test ==="
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
            scenario = self.server.scenario
            if scenario == "safe_create":
                # Zero records — safe to create
                body = json.dumps({"success": True, "result": []})
            elif scenario == "cname_conflict":
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-cname", "type": "CNAME", "name": "test", "content": "other", "comment": ""}
                ]})
            elif scenario == "existing_unmanaged":
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-a", "type": "A", "name": "test", "content": "192.0.2.1", "comment": "other"}
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
        if "/client/v4/zones/" in self.path and "/dns_records" in self.path:
            # Mock successful create
            body = json.dumps({
                "success": True,
                "result": {
                    "id": "fake-created-record-id",
                    "type": "A",
                    "name": "test-record",
                    "content": "192.0.2.100",
                    "proxied": False,
                    "comment": "nanobk-test managed disposable record"
                }
            })
            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(405)
            self.end_headers()

    def do_PUT(self):
        self.send_response(405)
        self.end_headers()

    def do_PATCH(self):
        self.send_response(405)
        self.end_headers()

    def do_DELETE(self):
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
# A. No live flag
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. No live flag ---"
echo ""

A_OUT=$("$RUNNER" --plan "$FIXTURES/runner_live_create_no_probe_no_call.json" 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no live flag exits 0"
else
  fail "A1: no live flag should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_OUT" "Live create called: no" "A2: live create called no"
assert_contains "$A_OUT" "Owner approval present: no" "A3: owner approval no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Missing approval
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Missing approval ---"
echo ""

start_mock "safe_create"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_missing_approval.json")

B_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "2" ]]; then
  pass "B1: missing approval exits 2"
else
  fail "B1: missing approval should exit 2, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Owner approval present: no" "B2: owner approval no"
assert_contains "$B_OUT" "Live create called: no" "B3: live create called no"
assert_contains "$B_OUT" "owner approval missing" "B4: owner approval missing reason"
assert_not_contains "$B_OUT" "$APPROVAL_PHRASE" "B5: no approval phrase in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Safe live create success
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Safe live create success ---"
echo ""

start_mock "safe_create"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_success_local_mock.json")

C_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && C_RC=0 || C_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$C_RC" == "0" ]]; then
  pass "C1: safe live create exits 0"
else
  fail "C1: safe live create should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Cloudflare GET called: yes" "C2: cf get called yes"
assert_contains "$C_OUT" "Cloudflare GET succeeded: yes" "C3: cf get succeeded yes"
assert_contains "$C_OUT" "DNS record GET called: yes" "C4: dns record get called yes"
assert_contains "$C_OUT" "DNS record GET succeeded: yes" "C5: dns record get succeeded yes"
assert_contains "$C_OUT" "Create-only-first safe: yes" "C6: create safe yes"
assert_contains "$C_OUT" "Owner approval present: yes" "C7: owner approval yes"
assert_contains "$C_OUT" "Live create prerequisites passed: yes" "C8: prereq passed yes"
assert_contains "$C_OUT" "Live create allowed: yes" "C9: live create allowed yes"
assert_contains "$C_OUT" "Live create called: yes" "C10: live create called yes"
assert_contains "$C_OUT" "Live create succeeded: yes" "C11: live create succeeded yes"
assert_contains "$C_OUT" "Created record category: one_disposable_test_record" "C12: created record category"
assert_contains "$C_OUT" "Live create proxied: false" "C13: proxied false"
assert_contains "$C_OUT" "Live mutation method used: POST" "C14: mutation method POST"
assert_contains "$C_OUT" "Delete called: no" "C15: delete called no"
assert_contains "$C_OUT" "Update called: no" "C16: update called no"
assert_contains "$C_OUT" "Can apply: no" "C17: can apply no"
assert_contains "$C_OUT" "Mutation allowed: no" "C18: mutation allowed no"
assert_contains "$C_OUT" "Public apply allowed: no" "C19: public apply no"

assert_not_contains "$C_OUT" "$APPROVAL_PHRASE" "C20: no approval phrase in output"
assert_not_contains "$C_OUT" "LOCAL_ONLY_ZONE_ID_NOT_FOR_OUTPUT" "C21: no zone id in output"
assert_not_contains "$C_OUT" "LOCAL_ONLY_RECORD_NAME_NOT_FOR_OUTPUT" "C22: no record name in output"
assert_not_contains "$C_OUT" "LOCAL_ONLY_EXPECTED_CONTENT_NOT_FOR_OUTPUT" "C23: no content in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Existing unmanaged
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Existing unmanaged ---"
echo ""

start_mock "existing_unmanaged"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_existing_unmanaged.json")

D_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && D_RC=0 || D_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$D_RC" == "2" ]]; then
  pass "D1: existing unmanaged exits 2"
else
  fail "D1: existing unmanaged should exit 2, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "existing unmanaged record present" "D2: unmanaged reason"
assert_contains "$D_OUT" "Live create called: no" "D3: live create called no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. CNAME conflict
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. CNAME conflict ---"
echo ""

start_mock "cname_conflict"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_cname_conflict.json")

E_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && E_RC=0 || E_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$E_RC" == "2" ]]; then
  pass "E1: cname conflict exits 2"
else
  fail "E1: cname conflict should exit 2, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "same-name CNAME present" "E2: cname reason"
assert_contains "$E_OUT" "Live create called: no" "E3: live create called no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Unsafe update requested
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Unsafe update requested ---"
echo ""

start_mock "safe_create"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_unsafe_update_requested.json")

F_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && F_RC=0 || F_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$F_RC" == "2" ]]; then
  pass "F1: unsafe update exits 2"
else
  fail "F1: unsafe update should exit 2, got $F_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "Live create prerequisites passed: no" "F2: prereq not passed"
assert_contains "$F_OUT" "Live create called: no" "F3: live create called no"
assert_contains "$F_OUT" "Live create allowed: no" "F4: live create allowed no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Safety scan ---"
echo ""

ALL_OUTPUTS="$A_OUT $B_OUT $C_OUT $D_OUT $E_OUT $F_OUT"

assert_not_contains "$ALL_OUTPUTS" "fake_test_token_do_not_use" "G1: no fake token"
assert_not_contains "$ALL_OUTPUTS" "CLOUDFLARE_API_TOKEN" "G2: no CLOUDFLARE_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN" "G3: no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "safe_token.env" "G4: no safe_token.env"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_ZONE_ID_NOT_FOR_OUTPUT" "G5: no zone id"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_RECORD_NAME_NOT_FOR_OUTPUT" "G6: no record name"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_EXPECTED_CONTENT_NOT_FOR_OUTPUT" "G7: no expected content"
assert_not_contains "$ALL_OUTPUTS" "recordId" "G8: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "G9: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "G10: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "G11: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "raw API request" "G12: no raw API request"
assert_not_contains "$ALL_OUTPUTS" "raw API response" "G13: no raw API response"
assert_not_contains "$ALL_OUTPUTS" "/zones/" "G14: no /zones/"
assert_not_contains "$ALL_OUTPUTS" "dns_records" "G15: no dns_records"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "G16: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "G17: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "G18: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "G19: no apply --yes"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "G20: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "G20: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'owner-approved-live-create\|allow-live-create\|live_create_called' "$loc" 2>/dev/null; then
    fail "H1: $loc references live create"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "H1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Compatibility
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Compatibility ---"
echo ""

if bash "$ROOT/tests/v2.2.32-dns-record-readonly-precheck.sh" > /dev/null 2>&1; then
  pass "I1: v2.2.32 test passes"
else
  fail "I1: v2.2.32 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.31-readonly-cloudflare-get-probe.sh" > /dev/null 2>&1; then
  pass "I2: v2.2.31 test passes"
else
  fail "I2: v2.2.31 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.33 Owner-Approved Live Create tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
