#!/usr/bin/env bash
# NanoBK Proxy Suite — Live Create Post-check Test
#
# Tests the post-check after owner-approved one-record live create.
# Uses a local mock HTTP server. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.34-live-create-postcheck.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.34"

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
echo "=== Live Create Post-check Test ==="
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
            query = self.path.split("?")[1] if "?" in self.path else ""
            # Determine if this is precheck (first GET) or postcheck (second GET)
            # We track call count on the server object
            if not hasattr(self.server, 'get_count'):
                self.server.get_count = 0
            self.server.get_count += 1
            call_num = self.server.get_count

            if scenario == "postcheck_success":
                if call_num <= 1:
                    # Precheck: zero records
                    body = json.dumps({"success": True, "result": []})
                else:
                    # Postcheck: one managed record
                    body = json.dumps({"success": True, "result": [
                        {"id": "fake-created", "type": "A", "name": "test", "content": "192.0.2.100", "proxied": False, "comment": "nanobk-test managed disposable record"}
                    ]})
            elif scenario == "postcheck_not_found":
                if call_num <= 1:
                    body = json.dumps({"success": True, "result": []})
                else:
                    # Postcheck: zero records (not found)
                    body = json.dumps({"success": True, "result": []})
            elif scenario == "postcheck_multiple":
                if call_num <= 1:
                    body = json.dumps({"success": True, "result": []})
                else:
                    # Postcheck: multiple records
                    body = json.dumps({"success": True, "result": [
                        {"id": "fake-1", "type": "A", "name": "test", "content": "192.0.2.1", "proxied": False, "comment": "nanobk-test"},
                        {"id": "fake-2", "type": "A", "name": "test", "content": "192.0.2.2", "proxied": False, "comment": "nanobk-test"}
                    ]})
            elif scenario == "postcheck_not_dns_only":
                if call_num <= 1:
                    body = json.dumps({"success": True, "result": []})
                else:
                    # Postcheck: proxied=true
                    body = json.dumps({"success": True, "result": [
                        {"id": "fake-created", "type": "A", "name": "test", "content": "192.0.2.100", "proxied": True, "comment": "nanobk-test managed"}
                    ]})
            elif scenario == "postcheck_not_managed":
                if call_num <= 1:
                    body = json.dumps({"success": True, "result": []})
                else:
                    # Postcheck: no managed marker
                    body = json.dumps({"success": True, "result": [
                        {"id": "fake-created", "type": "A", "name": "test", "content": "192.0.2.100", "proxied": False, "comment": "some other comment"}
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
        pass

port = int(sys.argv[1])
scenario = sys.argv[2] if len(sys.argv) > 2 else "postcheck_success"
server = http.server.HTTPServer(("127.0.0.1", port), MockHandler)
server.scenario = scenario
server.get_count = 0
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

A_OUT=$("$RUNNER" --plan "$FIXTURES/runner_live_create_postcheck_no_live_no_call.json" 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no live flag exits 0"
else
  fail "A1: no live flag should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_OUT" "Live create called: no" "A2: live create called no"
assert_contains "$A_OUT" "Live create post-check called: no" "A3: postcheck called no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Post-check success
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Post-check success ---"
echo ""

start_mock "postcheck_success"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_postcheck_success.json")

B_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "0" ]]; then
  pass "B1: postcheck success exits 0"
else
  fail "B1: postcheck success should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Live create called: yes" "B2: live create called yes"
assert_contains "$B_OUT" "Live create succeeded: yes" "B3: live create succeeded yes"
assert_contains "$B_OUT" "Live create post-check called: yes" "B4: postcheck called yes"
assert_contains "$B_OUT" "Live create post-check succeeded: yes" "B5: postcheck succeeded yes"
assert_contains "$B_OUT" "Created record found: yes" "B6: record found yes"
assert_contains "$B_OUT" "Created record type match: yes" "B7: type match yes"
assert_contains "$B_OUT" "Created record DNS-only: yes" "B8: dns only yes"
assert_contains "$B_OUT" "Created record managed: yes" "B9: managed yes"
assert_contains "$B_OUT" "Post-check record count category: one" "B10: count one"
assert_contains "$B_OUT" "Status: live_create_verified" "B11: status live_create_verified"
assert_contains "$B_OUT" "Can apply: no" "B12: can apply no"
assert_contains "$B_OUT" "Mutation allowed: no" "B13: mutation allowed no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Post-check not found
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Post-check not found ---"
echo ""

start_mock "postcheck_not_found"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_postcheck_not_found.json")

C_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && C_RC=0 || C_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$C_RC" == "3" ]]; then
  pass "C1: postcheck not found exits 3"
else
  fail "C1: postcheck not found should exit 3, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Live create succeeded: yes" "C2: live create succeeded"
assert_contains "$C_OUT" "Live create post-check called: yes" "C3: postcheck called"
assert_contains "$C_OUT" "Live create post-check succeeded: yes" "C4: postcheck GET succeeded"
assert_contains "$C_OUT" "Created record found: no" "C5: record not found"
assert_contains "$C_OUT" "created record not found" "C6: not found reason"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Multiple matching records
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Multiple matching records ---"
echo ""

start_mock "postcheck_multiple"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_postcheck_multiple.json")

D_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && D_RC=0 || D_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$D_RC" == "3" ]]; then
  pass "D1: multiple records exits 3"
else
  fail "D1: multiple records should exit 3, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "multiple matching records" "D2: multiple reason"
assert_contains "$D_OUT" "Post-check record count category: multiple" "D3: count multiple"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Not DNS-only
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Not DNS-only ---"
echo ""

start_mock "postcheck_not_dns_only"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_postcheck_not_dns_only.json")

E_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && E_RC=0 || E_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$E_RC" == "3" ]]; then
  pass "E1: not dns-only exits 3"
else
  fail "E1: not dns-only should exit 3, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "created record not DNS-only" "E2: not dns-only reason"
assert_contains "$E_OUT" "Created record DNS-only: no" "E3: dns only no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Not managed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Not managed ---"
echo ""

start_mock "postcheck_not_managed"
TEMP_PLAN=$(make_plan "$FIXTURES/runner_live_create_postcheck_not_managed.json")

F_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe --allow-live-create --owner-approval "$APPROVAL_PHRASE" 2>&1) && F_RC=0 || F_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$F_RC" == "3" ]]; then
  pass "F1: not managed exits 3"
else
  fail "F1: not managed should exit 3, got $F_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "created record not managed" "F2: not managed reason"
assert_contains "$F_OUT" "Created record managed: no" "F3: managed no"

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
  if [[ -e "$loc" ]] && grep -rq 'live-create-postcheck\|live_create_postcheck\|postcheck_called' "$loc" 2>/dev/null; then
    fail "H1: $loc references postcheck"
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

if bash "$ROOT/tests/v2.2.33-owner-approved-live-create.sh" > /dev/null 2>&1; then
  pass "I1: v2.2.33 test passes"
else
  fail "I1: v2.2.33 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.32-dns-record-readonly-precheck.sh" > /dev/null 2>&1; then
  pass "I2: v2.2.32 test passes"
else
  fail "I2: v2.2.32 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.34 Live Create Post-check tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
