#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner-Approved Cleanup Test
#
# Tests the non-public owner-approved cleanup path for verified disposable test records.
# Uses a local mock HTTP server. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.35-owner-approved-cleanup.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.35"

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

CLEANUP_APPROVAL="I UNDERSTAND THIS WILL DELETE ONE CLOUDFLARE DNS TEST RECORD"

echo ""
echo "=== Owner-Approved Cleanup Test ==="
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
            self.wfile.write(json.dumps({"success": True, "result": {"id": "fake", "status": "active"}}).encode())
        elif "/client/v4/zones/" in self.path and "/dns_records" in self.path:
            scenario = self.server.scenario
            if scenario == "cleanup_success":
                # One managed record found
                body = json.dumps({"success": True, "result": [
                    {"id": "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT", "type": "A", "name": "test", "content": "192.0.2.100", "proxied": False, "comment": "nanobk-test managed disposable record"}
                ]})
            elif scenario == "record_not_found":
                body = json.dumps({"success": True, "result": []})
            elif scenario == "multiple_records":
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-1", "type": "A", "name": "test", "content": "192.0.2.1", "proxied": False, "comment": "nanobk-test"},
                    {"id": "fake-2", "type": "A", "name": "test", "content": "192.0.2.2", "proxied": False, "comment": "nanobk-test"}
                ]})
            elif scenario == "not_managed":
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-unmanaged", "type": "A", "name": "test", "content": "192.0.2.1", "proxied": False, "comment": "some other comment"}
                ]})
            elif scenario == "not_dns_only":
                body = json.dumps({"success": True, "result": [
                    {"id": "fake-proxied", "type": "A", "name": "test", "content": "192.0.2.1", "proxied": True, "comment": "nanobk-test managed disposable record"}
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

    def do_DELETE(self):
        if "/client/v4/zones/" in self.path and "/dns_records/" in self.path:
            # Mock successful delete
            body = json.dumps({"success": True, "result": {"id": "deleted"}})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(405)
            self.end_headers()

    def do_POST(self):
        self.send_response(405)
        self.end_headers()

    def do_PUT(self):
        self.send_response(405)
        self.end_headers()

    def do_PATCH(self):
        self.send_response(405)
        self.end_headers()

    def log_message(self, format, *args):
        pass

port = int(sys.argv[1])
scenario = sys.argv[2] if len(sys.argv) > 2 else "cleanup_success"
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
# A. No cleanup flag
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. No cleanup flag ---"
echo ""

A_OUT=$("$RUNNER" --plan "$FIXTURES/runner_cleanup_no_flag_no_call.json" 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no cleanup flag exits 0"
else
  fail "A1: no cleanup flag should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_OUT" "Cleanup called: no" "A2: cleanup called no"
assert_contains "$A_OUT" "Cleanup approval present: no" "A3: cleanup approval no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Missing approval
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Missing approval ---"
echo ""

start_mock "cleanup_success"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_missing_approval.json")

B_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "2" ]]; then
  pass "B1: missing approval exits 2"
else
  fail "B1: missing approval should exit 2, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Cleanup approval present: no" "B2: cleanup approval no"
assert_contains "$B_OUT" "Cleanup called: no" "B3: cleanup called no"
assert_contains "$B_OUT" "cleanup approval missing" "B4: cleanup approval missing reason"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Cleanup success
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Cleanup success ---"
echo ""

start_mock "cleanup_success"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_success_local_mock.json")

C_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup --owner-cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && C_RC=0 || C_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$C_RC" == "0" ]]; then
  pass "C1: cleanup success exits 0"
else
  fail "C1: cleanup success should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Cloudflare GET called: yes" "C2: cf get called yes"
assert_contains "$C_OUT" "Cleanup precheck called: yes" "C3: cleanup precheck called"
assert_contains "$C_OUT" "Cleanup precheck succeeded: yes" "C4: cleanup precheck succeeded"
assert_contains "$C_OUT" "Cleanup record found: yes" "C5: record found yes"
assert_contains "$C_OUT" "Cleanup record single match: yes" "C6: single match yes"
assert_contains "$C_OUT" "Cleanup record managed: yes" "C7: managed yes"
assert_contains "$C_OUT" "Cleanup record DNS-only: yes" "C8: dns only yes"
assert_contains "$C_OUT" "Cleanup safe: yes" "C9: cleanup safe yes"
assert_contains "$C_OUT" "Cleanup prerequisites passed: yes" "C10: prereq passed"
assert_contains "$C_OUT" "Cleanup allowed: yes" "C11: cleanup allowed"
assert_contains "$C_OUT" "Cleanup called: yes" "C12: cleanup called"
assert_contains "$C_OUT" "Cleanup succeeded: yes" "C13: cleanup succeeded"
assert_contains "$C_OUT" "Deleted record category: one_disposable_test_record" "C14: deleted category"
assert_contains "$C_OUT" "Cleanup mutation method used: DELETE" "C15: mutation method DELETE"
assert_contains "$C_OUT" "Cleanup update called: no" "C16: update called no"
assert_contains "$C_OUT" "Cleanup create called: no" "C17: create called no"
assert_contains "$C_OUT" "Can apply: no" "C18: can apply no"
assert_contains "$C_OUT" "Mutation allowed: no" "C19: mutation allowed no"
assert_contains "$C_OUT" "Public apply allowed: no" "C20: public apply no"

assert_not_contains "$C_OUT" "$CLEANUP_APPROVAL" "C21: no approval phrase in output"
assert_not_contains "$C_OUT" "LOCAL_ONLY_ZONE_ID_NOT_FOR_OUTPUT" "C22: no zone id"
assert_not_contains "$C_OUT" "LOCAL_ONLY_RECORD_NAME_NOT_FOR_OUTPUT" "C23: no record name"
assert_not_contains "$C_OUT" "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT" "C24: no record id"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Record not found
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Record not found ---"
echo ""

start_mock "record_not_found"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_record_not_found.json")

D_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup --owner-cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && D_RC=0 || D_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$D_RC" == "2" ]]; then
  pass "D1: record not found exits 2"
else
  fail "D1: record not found should exit 2, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "Cleanup precheck succeeded: no" "D2: precheck succeeded no"
assert_contains "$D_OUT" "Cleanup record found: no" "D3: record found no"
assert_contains "$D_OUT" "Cleanup called: no" "D4: cleanup called no"
assert_contains "$D_OUT" "Cleanup prerequisites passed: no" "D5: prereq not passed"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Multiple records
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Multiple records ---"
echo ""

start_mock "multiple_records"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_multiple_records.json")

E_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup --owner-cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && E_RC=0 || E_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$E_RC" == "2" ]]; then
  pass "E1: multiple records exits 2"
else
  fail "E1: multiple records should exit 2, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "Cleanup precheck succeeded: no" "E2: precheck succeeded no"
assert_contains "$E_OUT" "Cleanup record single match: no" "E3: single match no"
assert_contains "$E_OUT" "Cleanup called: no" "E4: cleanup called no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Not managed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Not managed ---"
echo ""

start_mock "not_managed"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_not_managed.json")

F_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup --owner-cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && F_RC=0 || F_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$F_RC" == "2" ]]; then
  pass "F1: not managed exits 2"
else
  fail "F1: not managed should exit 2, got $F_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "Cleanup precheck succeeded: no" "F2: precheck succeeded no"
assert_contains "$F_OUT" "Cleanup record managed: no" "F3: managed no"
assert_contains "$F_OUT" "Cleanup called: no" "F4: cleanup called no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Not DNS-only
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Not DNS-only ---"
echo ""

start_mock "not_dns_only"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_cleanup_not_dns_only.json")

G_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-cleanup --owner-cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && G_RC=0 || G_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$G_RC" == "2" ]]; then
  pass "G1: not dns-only exits 2"
else
  fail "G1: not dns-only should exit 2, got $G_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$G_OUT" "Cleanup precheck succeeded: no" "G2: precheck succeeded no"
assert_contains "$G_OUT" "Cleanup record DNS-only: no" "G3: dns-only no"
assert_contains "$G_OUT" "Cleanup called: no" "G4: cleanup called no"

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
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT" "H7: no record id"
assert_not_contains "$ALL_OUTPUTS" "recordId" "H8: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "H9: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "H10: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "H11: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "raw API request" "H12: no raw API request"
assert_not_contains "$ALL_OUTPUTS" "raw API response" "H13: no raw API response"
assert_not_contains "$ALL_OUTPUTS" "/zones/" "H14: no /zones/"
assert_not_contains "$ALL_OUTPUTS" "dns_records" "H15: no dns_records"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "H16: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "H17: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "H18: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "H19: no apply --yes"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "H20: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "H20: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'owner-approved-cleanup\|allow-live-cleanup\|live_cleanup' "$loc" 2>/dev/null; then
    fail "I1: $loc references cleanup"
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

if bash "$ROOT/tests/v2.2.34-live-create-postcheck.sh" > /dev/null 2>&1; then
  pass "J1: v2.2.34 test passes"
else
  fail "J1: v2.2.34 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.33-owner-approved-live-create.sh" > /dev/null 2>&1; then
  pass "J2: v2.2.33 test passes"
else
  fail "J2: v2.2.33 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.35 Owner-Approved Cleanup tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
