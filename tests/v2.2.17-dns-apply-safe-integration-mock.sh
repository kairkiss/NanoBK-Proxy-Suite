#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Safe Integration Mock Test
#
# Tests lib/nanobk_cf_dns_apply_safe_integration_mock.py under
# mandatory fake-transport guard connecting boundary mock to safe renderer.
#
# Does NOT call real Cloudflare. Does NOT perform real DNS mutation.
#
# Usage:
#   bash tests/v2.2.17-dns-apply-safe-integration-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_safe_integration_mock.py"

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

# Calls file — initialized as empty list
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

# Helper: run module without fake transport (capture stderr separately)
run_module_no_transport() {
  env -u NANOBK_CF_DNS_FAKE_TRANSPORT \
    python3 "$MODULE" 2>/dev/null
}

run_module_no_transport_stderr() {
  env -u NANOBK_CF_DNS_FAKE_TRANSPORT \
    python3 "$MODULE" 2>&1 1>/dev/null
}

echo ""
echo "=== DNS Apply Safe Integration Mock Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

# A1. Integration module exists
if [[ -f "$MODULE" ]]; then
  pass "A1: integration module exists"
else
  fail "A1: integration module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

MODULE_SOURCE=$(cat "$MODULE")

# A2. Module says hidden/test-only/fake-only
assert_contains "$MODULE_SOURCE" "Hidden/test-only" "A2: module says hidden/test-only"
assert_contains "$MODULE_SOURCE" "fake-only" "A2: module says fake-only"

# A3. Module says no Cloudflare/no DNS mutation
assert_contains "$MODULE_SOURCE" "Never calls Cloudflare" "A3: says no Cloudflare"
assert_contains "$MODULE_SOURCE" "Never performs real DNS mutation" "A3: says no DNS mutation"

# A4. Module imports boundary mock
IMPORT_LINES=$(grep -E '^\s*(import |from )' "$MODULE" || true)
assert_contains "$IMPORT_LINES" "nanobk_cf_dns_apply_helper_boundary_mock" "A4: imports boundary mock"

# A5. Module imports safe renderer
assert_contains "$IMPORT_LINES" "nanobk_cf_dns_apply_safe_renderer" "A5: imports safe renderer"

# A6. Module does not import low-level helper directly
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply " "A6: no low-level helper import"

# A7. Module has no public CLI wording
assert_not_contains "$MODULE_SOURCE" "public CLI" "A7: no public CLI wording"

# A8. bin/nanobk does not reference integration module
if grep -q 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "A8: bin/nanobk references integration module"
  ERRORS=$((ERRORS + 1))
else
  pass "A8: bin/nanobk does not reference integration module"
fi

# A9. installer/Bot/Web do not reference integration module
for dir in installer bot web; do
  if grep -rq 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/$dir/" 2>/dev/null; then
    fail "A9: $dir/ references integration module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "A9: installer/Bot/Web do not reference integration module"

# A10. Module documents nonzero helper exit handling precisely
assert_contains "$MODULE_SOURCE" "nonzero helper exit is allowed" "A10: documents nonzero helper exit handling"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Fake transport preflight
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Fake transport preflight ---"
echo ""

# B1. Missing env fails closed
B1_STDERR=$(run_module_no_transport_stderr) || true
assert_contains "$B1_STDERR" "fake-only" "B1: missing env says fake-only"
assert_contains "$B1_STDERR" "No DNS changes were made" "B1: missing env says no DNS changes"

# B2. Empty env fails closed
B2_STDERR=$(NANOBK_CF_DNS_FAKE_TRANSPORT="" python3 "$MODULE" 2>&1 1>/dev/null) || true
assert_contains "$B2_STDERR" "fake-only" "B2: empty env fails closed"

# B3. Nonexistent file fails closed
B3_STDERR=$(NANOBK_CF_DNS_FAKE_TRANSPORT="/nonexistent/path.json" python3 "$MODULE" 2>&1 1>/dev/null) || true
assert_contains "$B3_STDERR" "fake-only" "B3: nonexistent file fails closed"

# B4. Malformed JSON fails closed
B4_STDERR=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$MALFORMED_TRANSPORT" python3 "$MODULE" 2>&1 1>/dev/null) || true
assert_contains "$B4_STDERR" "fake-only" "B4: malformed JSON fails closed"

# B5. Empty file fails closed
B5_STDERR=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$EMPTY_TRANSPORT" python3 "$MODULE" 2>&1 1>/dev/null) || true
assert_contains "$B5_STDERR" "fake-only" "B5: empty file fails closed"

# B6-B8. Error output does not leak raw path/JSON/content
assert_not_contains "$B1_STDERR" "$FAKE_TRANSPORT" "B6: no raw path in error"
assert_not_contains "$B3_STDERR" "/nonexistent" "B7: no nonexistent path in error"
assert_not_contains "$B4_STDERR" "broken" "B8: no JSON content in error"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Valid fake integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Valid fake integration ---"
echo ""

C_OUT=$(run_module) || true

# C1. Output contains safe summary header
assert_contains "$C_OUT" "NanoBK DNS Apply — Safe Summary" "C1: has safe summary header"

# C2. Output contains Status
assert_contains "$C_OUT" "Status:" "C2: has Status"

# C3. Output contains Mode: fake_only
assert_contains "$C_OUT" "Mode: fake_only" "C3: has Mode: fake_only"

# C4. Output contains Actions section
assert_contains "$C_OUT" "Actions:" "C4: has Actions section"

# C5. Output contains Record types
assert_contains "$C_OUT" "Record types:" "C5: has Record types section"

# C6. Output contains test mode notice
assert_contains "$C_OUT" "Test mode: fake transport only" "C6: has test mode notice"

# C7. Output says no live verification
assert_contains "$C_OUT" "No live Cloudflare verification was performed" "C7: says no live verification"

# C8. Output says no deletes
assert_contains "$C_OUT" "No DNS records were deleted" "C8: says no deletes"

# C9. Output has safe counts (Create and A/AAAA)
assert_contains "$C_OUT" "Create:" "C9: has Create count"
assert_contains "$C_OUT" "A:" "C9: has A count"
assert_contains "$C_OUT" "AAAA:" "C9: has AAAA count"

# C10. Calls artifact proof: module calls check_calls_artifact on transport copy
assert_contains "$MODULE_SOURCE" "check_calls_artifact(transport_with_calls)" "C10: calls artifact checked on transport copy"

# C11. Static check: module invokes check_calls_artifact from boundary mock
assert_contains "$MODULE_SOURCE" "check_calls_artifact" "C11: module checks calls artifact"

# C12. Output contains safe fake transport proof wording
assert_contains "$C_OUT" "Fake transport:" "C12: has fake transport proof section"
assert_contains "$C_OUT" "Used: yes" "C12: fake transport used"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Raw output never printed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Raw output never printed ---"
echo ""

assert_not_contains "$C_OUT" "example.com" "D1: no example.com"
assert_not_contains "$C_OUT" "node.example.com" "D2: no node.example.com"
assert_not_contains "$C_OUT" "203.0.113.10" "D3: no raw IPv4"
assert_not_contains "$C_OUT" "2001:db8::10" "D4: no raw IPv6"
assert_not_contains "$C_OUT" "rec-new-001" "D5: no rec-new-001"
assert_not_contains "$C_OUT" "recordId" "D6: no recordId"
assert_not_contains "$C_OUT" "plannedContent" "D7: no plannedContent"
assert_not_contains "$C_OUT" "existingContent" "D8: no existingContent"
assert_not_contains "$C_OUT" "raw helper" "D9: no raw helper"
assert_not_contains "$C_OUT" "{\"ok\":" "D10: no raw JSON"
assert_not_contains "$C_OUT" "/zones/" "D11: no /zones/"
assert_not_contains "$C_OUT" "dns_records" "D12: no dns_records"
assert_not_contains "$C_OUT" "Authorization" "D13: no Authorization"
assert_not_contains "$C_OUT" "CF_API_TOKEN" "D14: no CF_API_TOKEN"
assert_not_contains "$C_OUT" "api-env" "D15: no api-env"
assert_not_contains "$C_OUT" "apply --yes" "D16: no apply --yes"

# D18. No calls file path leaked
assert_not_contains "$C_OUT" "$CALLS_FILE" "D18: no calls file path"
assert_not_contains "$C_OUT" "fake-calls.json" "D18: no calls artifact filename"

# D19. No fake transport keys or API details
assert_not_contains "$C_OUT" "GET_A" "D19: no fake transport key"
assert_not_contains "$C_OUT" "POST" "D19: no fake POST detail"
assert_not_contains "$C_OUT" "PATCH" "D19: no fake PATCH detail"

# D20. No full sha256-like 64-char hex
if echo "$C_OUT" | grep -qE '[a-f0-9]{64}'; then
  fail "D17: no full sha256-like hex"
  ERRORS=$((ERRORS + 1))
else
  pass "D17: no full sha256-like hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Renderer safety gate used
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Renderer safety gate used ---"
echo ""

# E1. Integration imports render_from_helper_json
assert_contains "$MODULE_SOURCE" "render_from_helper_json" "E1: imports render_from_helper_json"

# E2. Integration imports UnsafeOutputError
assert_contains "$MODULE_SOURCE" "UnsafeOutputError" "E2: imports UnsafeOutputError"

# E3. Integration catches UnsafeOutputError
assert_contains "$MODULE_SOURCE" "except UnsafeOutputError" "E3: catches UnsafeOutputError"

# E4. Integration has own final forbidden scan
assert_contains "$MODULE_SOURCE" "_assert_integration_safe" "E4: has own final forbidden scan"
assert_contains "$MODULE_SOURCE" "_INTEGRATION_FORBIDDEN_PATTERNS" "E4: has forbidden patterns"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. No public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. No public integration ---"
echo ""

# F1. No reference in bin/nanobk
if grep -q 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "F1: bin/nanobk references integration"
  ERRORS=$((ERRORS + 1))
else
  pass "F1: bin/nanobk does not reference integration"
fi

# F2. No reference in installer
if grep -rq 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/installer/" 2>/dev/null; then
  fail "F2: installer references integration"
  ERRORS=$((ERRORS + 1))
else
  pass "F2: installer does not reference integration"
fi

# F3. No reference in bot
if grep -rq 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/bot/" 2>/dev/null; then
  fail "F3: bot references integration"
  ERRORS=$((ERRORS + 1))
else
  pass "F3: bot does not reference integration"
fi

# F4. No reference in web
if grep -rq 'nanobk_cf_dns_apply_safe_integration_mock' "$ROOT/web/" 2>/dev/null; then
  fail "F4: web references integration"
  ERRORS=$((ERRORS + 1))
else
  pass "F4: web does not reference integration"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Module isolation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Module isolation ---"
echo ""

# G1. No network imports
assert_not_contains "$MODULE_SOURCE" "import requests" "G1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "G1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "G1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "G1: no socket"
assert_not_contains "$MODULE_SOURCE" "import curl" "G1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "G1: no wrangler"

# G2. Subprocess is NOT directly imported (uses boundary mock)
assert_not_contains "$MODULE_SOURCE" "import subprocess" "G2: no direct subprocess import"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.8-dns-apply-beginner-ux-mock.sh" \
  "v2.2.10-dns-apply-ux-fake-wrapper.sh" \
  "v2.2.11-dns-apply-ux-wrapper-hardening.sh" \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "H: $test_file passes"
  else
    fail "H: $test_file fails"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.17 DNS Apply Safe Integration Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
