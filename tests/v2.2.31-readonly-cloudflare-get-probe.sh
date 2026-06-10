#!/usr/bin/env bash
# NanoBK Proxy Suite — Read-only Cloudflare GET Probe Test
#
# Tests the non-public read-only Cloudflare GET probe in the dryrun wrapper.
# Uses a local mock HTTP server. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.31-readonly-cloudflare-get-probe.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.31"

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
echo "=== Read-only Cloudflare GET Probe Test ==="
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
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        self.send_response(405)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress server logs

port = int(sys.argv[1])
server = http.server.HTTPServer(("127.0.0.1", port), MockHandler)
server.serve_forever()
MOCKEOF

python3 "$MOCK_SCRIPT" "$MOCK_PORT" &
MOCK_SERVER_PID=$!
sleep 0.5

# Cleanup on exit
cleanup() {
  kill "$MOCK_SERVER_PID" 2>/dev/null || true
  rm -f "$MOCK_SCRIPT"
}
trap cleanup EXIT

# Verify mock server is running
if kill -0 "$MOCK_SERVER_PID" 2>/dev/null; then
  pass "Mock server started on port $MOCK_PORT"
else
  fail "Mock server failed to start"
  exit 1
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. No probe without flag
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. No probe without flag ---"
echo ""

A_OUT=$("$RUNNER" --plan "$FIXTURES/runner_probe_absent_no_call.json" 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no probe exits 0"
else
  fail "A1: no probe should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_OUT" "Cloudflare GET called: no" "A2: cf get called no"
assert_contains "$A_OUT" "Read-only probe allowed: no" "A3: probe allowed no"
assert_contains "$A_OUT" "Can query: no" "A4: can query no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Probe with local mock
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Probe with local mock ---"
echo ""

# Create temp plan with correct port
TEMP_PLAN=$(mktemp)
sed "s/__PORT__/$MOCK_PORT/g" "$FIXTURES/runner_readonly_probe_ready_local_mock.json" > "$TEMP_PLAN"

B_OUT=$("$RUNNER" --plan "$TEMP_PLAN" --allow-readonly-probe 2>&1) && B_RC=0 || B_RC=$?
rm -f "$TEMP_PLAN"

if [[ "$B_RC" == "0" ]]; then
  pass "B1: probe with mock exits 0"
else
  fail "B1: probe with mock should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Token loaded: yes" "B2: token loaded yes"
assert_contains "$B_OUT" "Token printed: no" "B3: token printed no"
assert_contains "$B_OUT" "Cloudflare GET called: yes" "B4: cf get called yes"
assert_contains "$B_OUT" "Cloudflare GET succeeded: yes" "B5: cf get succeeded yes"
assert_contains "$B_OUT" "API response printed: no" "B6: api response no"
assert_contains "$B_OUT" "Mutation method used: no" "B7: mutation method no"
assert_contains "$B_OUT" "Can apply: no" "B8: can apply no"
assert_contains "$B_OUT" "Mutation allowed: no" "B9: mutation allowed no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Missing token
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Missing token ---"
echo ""

C_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_missing_token.json" --allow-readonly-probe 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" != "0" ]]; then
  pass "C1: missing token exits non-zero ($C_RC)"
else
  fail "C1: missing token should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Token loaded: no" "C2: token loaded no"
assert_not_contains "$C_OUT" "missing_token.env" "C3: no credential path"
assert_not_contains "$C_OUT" "SOME_OTHER_KEY" "C4: no credential content"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Empty token
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Empty token ---"
echo ""

D_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_empty_token.json" --allow-readonly-probe 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: empty token exits non-zero ($D_RC)"
else
  fail "D1: empty token should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "Token loaded: no" "D2: token loaded no"
assert_not_contains "$D_OUT" "empty_token.env" "D3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Timeout
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Timeout ---"
echo ""

E_OUT=$("$RUNNER" --plan "$FIXTURES/runner_uncertain_probe_timeout.json" --allow-readonly-probe 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: timeout exits non-zero ($E_RC)"
else
  fail "E1: timeout should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "Cloudflare GET called: yes" "E2: cf get called yes"
assert_contains "$E_OUT" "Cloudflare GET succeeded: no" "E3: cf get succeeded no"
assert_not_contains "$E_OUT" "fake_test_token_do_not_use" "E4: no token in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Mutation method attempt
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Mutation method attempt ---"
echo ""

F_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_mutation_method_attempt.json" --allow-readonly-probe 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: mutation method exits non-zero ($F_RC)"
else
  fail "F1: mutation method should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$F_OUT" "fake_test_token_do_not_use" "F2: no token in output"

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
assert_not_contains "$ALL_OUTPUTS" "empty_token.env" "G5: no empty_token.env"
assert_not_contains "$ALL_OUTPUTS" "missing_token.env" "G6: no missing_token.env"
assert_not_contains "$ALL_OUTPUTS" "example.com" "G7: no example.com"
assert_not_contains "$ALL_OUTPUTS" "203.0.113" "G8: no IPv4"
assert_not_contains "$ALL_OUTPUTS" "2001:db8" "G9: no IPv6"
assert_not_contains "$ALL_OUTPUTS" "recordId" "G10: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "G11: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "G12: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "G13: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "G14: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "G15: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "G16: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "G17: no apply --yes"
assert_not_contains "$ALL_OUTPUTS" "raw API response" "G18: no raw API response"
assert_not_contains "$ALL_OUTPUTS" "/zones/" "G19: no /zones/"
assert_not_contains "$ALL_OUTPUTS" "dns_records" "G20: no dns_records"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "G21: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "G21: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'readonly-cloudflare-get-probe\|allow-readonly-probe\|cloudflare_get_called' "$loc" 2>/dev/null; then
    fail "H1: $loc references probe"
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

# Note: v2.2.27 test has a pre-existing unbound variable bug (set -u + declare -A).
# v2.2.28 and v2.2.30 depend on v2.2.27 transitively, so we test v2.2.29 directly.
if bash "$ROOT/tests/v2.2.29-local-credential-precheck.sh" > /dev/null 2>&1; then
  pass "I1: v2.2.29 test passes"
else
  fail "I1: v2.2.29 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.31 Read-only Cloudflare GET Probe tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
