#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner Smoke Harness Test
#
# Tests the non-public owner smoke harness with local mock HTTP server.
# Does NOT call real Cloudflare. Does NOT mutate DNS.
#
# Usage:
#   bash tests/v2.2.36-owner-smoke-harness.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/scripts/dev/nanobk-cf-dns-owner-smoke"
FIXTURES="$ROOT/tests/fixtures/v2.2.36"

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

CREATE_APPROVAL="I UNDERSTAND THIS WILL CREATE ONE CLOUDFLARE DNS TEST RECORD"
CLEANUP_APPROVAL="I UNDERSTAND THIS WILL DELETE ONE CLOUDFLARE DNS TEST RECORD"

echo ""
echo "=== Owner Smoke Harness Test ==="
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
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == "/client/v4/user/tokens/verify":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "result": {"id": "fake", "status": "active"}}).encode())
        elif "/client/v4/zones/" in self.path and "/dns_records" in self.path:
            if not hasattr(self.server, 'get_count'):
                self.server.get_count = 0
            self.server.get_count += 1
            call_num = self.server.get_count

            # For smoke test: precheck returns zero, postcheck returns one managed record
            if call_num <= 1:
                # Precheck: zero records
                body = json.dumps({"success": True, "result": []})
            else:
                # Postcheck/cleanup precheck: one managed record
                body = json.dumps({"success": True, "result": [
                    {"id": "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT", "type": "A", "name": "test", "content": "192.0.2.100", "proxied": False, "comment": "nanobk-test managed disposable record"}
                ]})
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
                    "id": "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT",
                    "type": "A",
                    "name": "test",
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

    def do_DELETE(self):
        if "/client/v4/zones/" in self.path and "/dns_records/" in self.path:
            body = json.dumps({"success": True, "result": {"id": "deleted"}})
            self.send_response(200)
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

    def log_message(self, format, *args):
        pass

port = int(sys.argv[1])
server = http.server.HTTPServer(("127.0.0.1", port), MockHandler)
server.get_count = 0
server.serve_forever()
MOCKEOF

python3 "$MOCK_SCRIPT" "$MOCK_PORT" &
MOCK_SERVER_PID=$!
sleep 0.5

# Function to create temp plan with correct port
# Must use a path that contains .local-owner-plan.json for the harness to accept it
make_plan() {
  local fixture="$1"
  local temp_dir=$(mktemp -d)
  local temp_plan="$temp_dir/smoke.local-owner-plan.json"
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
# A. Harness exists and executable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Harness file checks ---"
echo ""

if [[ -x "$HARNESS" ]]; then
  pass "A1: harness exists and executable"
else
  fail "A1: harness does NOT exist or is NOT executable"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Success path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Success path ---"
echo ""

TEMP_PLAN=$(make_plan "$FIXTURES/owner_smoke_success.local-owner-plan.json")

B_OUT=$("$HARNESS" --plan "$TEMP_PLAN" --create-approval "$CREATE_APPROVAL" --cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "0" ]]; then
  pass "B1: success path exits 0"
else
  fail "B1: success path should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Owner smoke create: verified" "B2: create verified"
assert_contains "$B_OUT" "Owner smoke cleanup: succeeded" "B3: cleanup succeeded"
assert_contains "$B_OUT" "Owner smoke final: passed" "B4: final passed"
assert_contains "$B_OUT" "Raw values printed: no" "B5: raw values no"
assert_contains "$B_OUT" "Credential path printed: no" "B6: credential path no"
assert_contains "$B_OUT" "Token printed: no" "B7: token no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Missing plan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Missing plan ---"
echo ""

C_OUT=$("$HARNESS" --plan "/nonexistent/path.json" --create-approval "$CREATE_APPROVAL" --cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "4" ]]; then
  pass "C1: missing plan exits 4"
else
  fail "C1: missing plan should exit 4, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Missing create approval
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Missing create approval ---"
echo ""

TEMP_PLAN=$(make_plan "$FIXTURES/owner_smoke_success.local-owner-plan.json")

D_OUT=$("$HARNESS" --plan "$TEMP_PLAN" --create-approval "wrong phrase" --cleanup-approval "$CLEANUP_APPROVAL" 2>&1) && D_RC=0 || D_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$D_RC" != "0" ]]; then
  pass "D1: missing create approval exits non-zero ($D_RC)"
else
  fail "D1: missing create approval should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "Owner smoke create: failed" "D2: create failed"
assert_contains "$D_OUT" "Owner smoke cleanup: skipped" "D3: cleanup skipped"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Missing cleanup approval
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Missing cleanup approval ---"
echo ""

TEMP_PLAN=$(make_plan "$FIXTURES/owner_smoke_success.local-owner-plan.json")

E_OUT=$("$HARNESS" --plan "$TEMP_PLAN" --create-approval "$CREATE_APPROVAL" --cleanup-approval "wrong phrase" 2>&1) && E_RC=0 || E_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$E_RC" != "0" ]]; then
  pass "E1: missing cleanup approval exits non-zero ($E_RC)"
else
  fail "E1: missing cleanup approval should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "Owner smoke final: failed" "E2: final failed"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Safety scan ---"
echo ""

ALL_OUTPUTS="$B_OUT $C_OUT $D_OUT $E_OUT"

assert_not_contains "$ALL_OUTPUTS" "fake_test_token_do_not_use" "F1: no fake token"
assert_not_contains "$ALL_OUTPUTS" "CLOUDFLARE_API_TOKEN" "F2: no CLOUDFLARE_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN" "F3: no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "F4: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "Bearer" "F5: no Bearer"
assert_not_contains "$ALL_OUTPUTS" "REPLACE_WITH" "F6: no REPLACE_WITH"
assert_not_contains "$ALL_OUTPUTS" ".local-credential.env" "F7: no credential path"
assert_not_contains "$ALL_OUTPUTS" ".local-owner-plan.json" "F8: no plan path"
assert_not_contains "$ALL_OUTPUTS" "safe_token.env" "F9: no safe_token.env"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_ZONE_ID_NOT_FOR_OUTPUT" "F10: no zone id"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_RECORD_NAME_NOT_FOR_OUTPUT" "F11: no record name"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_EXPECTED_CONTENT_NOT_FOR_OUTPUT" "F12: no content"
assert_not_contains "$ALL_OUTPUTS" "LOCAL_ONLY_RECORD_ID_NOT_FOR_OUTPUT" "F13: no record id"
assert_not_contains "$ALL_OUTPUTS" "recordId" "F14: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "F15: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "F16: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "/zones/" "F17: no /zones/"
assert_not_contains "$ALL_OUTPUTS" "dns_records" "F18: no dns_records"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "F19: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "F20: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "F21: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "F22: no apply --yes"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "F23: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "F23: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'owner-smoke\|nanobk-cf-dns-owner-smoke' "$loc" 2>/dev/null; then
    fail "G1: $loc references smoke harness"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "G1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Compatibility
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Compatibility ---"
echo ""

if bash "$ROOT/tests/v2.2.35-owner-approved-cleanup.sh" > /dev/null 2>&1; then
  pass "H1: v2.2.35 test passes"
else
  fail "H1: v2.2.35 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.34-live-create-postcheck.sh" > /dev/null 2>&1; then
  pass "H2: v2.2.34 test passes"
else
  fail "H2: v2.2.34 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.36 Owner Smoke Harness tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
