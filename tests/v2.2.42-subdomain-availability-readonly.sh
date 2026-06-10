#!/usr/bin/env bash
# NanoBK Proxy Suite — Subdomain Availability Check Read-only Test
#
# Tests the read-only subdomain availability summary.
# Uses NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP for mock. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.42-subdomain-availability-readonly.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_availability.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.42"

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

# Portable file mode helper
nanobk_test_file_mode() {
  if stat -c '%a' "$1" 2>/dev/null; then
    return 0
  fi
  stat -f '%Lp' "$1"
}

# Ensure safe credential is 0600
chmod 600 "$FIXTURES/safe_api_env.env"
chmod 644 "$FIXTURES/unsafe_world_readable_api_env.env"

echo ""
echo "=== Subdomain Availability Check Read-only Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Module exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Module exists ---"
echo ""

if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Both subdomains available
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Both subdomains available ---"
echo ""

B_OUT=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: both available exits 0"
else
  fail "B1: both available should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "proxy." "B2: proxy hostname shown"
assert_contains "$B_OUT" "web." "B3: web hostname shown"
assert_contains "$B_OUT" "available" "B4: status available"

B_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1)

assert_contains "$B_JSON" '"ok": true' "B5: JSON ok true"
assert_contains "$B_JSON" '"all_available": true' "B6: JSON all_available true"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Proxy occupied, web available
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Proxy occupied, web available ---"
echo ""

C_OUT=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_proxy_occupied.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: proxy occupied exits 0"
else
  fail "C1: proxy occupied should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "conflict" "C2: proxy shows conflict"

C_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_proxy_occupied.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1)

assert_contains "$C_JSON" '"any_conflict": true' "C3: JSON any_conflict true"
assert_contains "$C_JSON" '"available": true' "C4: JSON web available"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Web occupied, proxy available
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Web occupied, proxy available ---"
echo ""

D_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_web_occupied.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: web occupied exits 0"
else
  fail "D1: web occupied should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"any_conflict": true' "D2: JSON any_conflict true"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Both occupied
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Both occupied ---"
echo ""

E_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_occupied.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "0" ]]; then
  pass "E1: both occupied exits 0"
else
  fail "E1: both occupied should exit 0, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" '"any_conflict": true' "E2: JSON any_conflict true"
assert_contains "$E_JSON" '"all_available": false' "E3: JSON all_available false"
assert_contains "$E_JSON" '"manual_review_required": true' "E4: JSON manual_review true"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. API failure
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. API failure ---"
echo ""

F_OUT=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_api_failure.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/safe_api_env.env" 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: API failure exits non-zero ($F_RC)"
else
  fail "F1: API failure should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$F_OUT" "available" "F2: no false available"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Missing credential
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Missing credential ---"
echo ""

G_OUT=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" != "0" ]]; then
  pass "G1: missing credential exits non-zero ($G_RC)"
else
  fail "G1: missing credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$G_OUT" "safe_api_env.env" "G2: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Unsafe credential permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Unsafe credential permission ---"
echo ""

H_OUT=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns availability summary --zone example.com --api-env "$FIXTURES/unsafe_world_readable_api_env.env" 2>&1) && H_RC=0 || H_RC=$?

if [[ "$H_RC" != "0" ]]; then
  pass "H1: unsafe credential exits non-zero ($H_RC)"
else
  fail "H1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$H_OUT" "Insecure" "H2: insecure permissions message"
assert_not_contains "$H_OUT" "unsafe_world_readable_api_env.env" "H3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Mutation guard — verify module source has no mutation methods
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Mutation guard ---"
echo ""

I_SRC=$(cat "$MODULE")
for method in "method=\"POST\"" "method=\"PATCH\"" "method=\"PUT\"" "method=\"DELETE\""; do
  if echo "$I_SRC" | grep -q "$method"; then
    fail "I: module contains $method"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no $method in module"
  fi
done

if echo "$I_SRC" | grep -q 'method="GET"'; then
  pass "I: module uses GET method only"
else
  fail "I: module should use GET method"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Safety scan — no sensitive values in output
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Safety scan ---"
echo ""

ALL_OUTPUTS="$B_OUT $B_JSON $C_OUT $C_JSON $D_JSON $E_JSON $F_OUT $G_OUT $H_OUT"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "safe_api_env.env" \
  "fake-zone-id" "Authorization:" "Bearer " "/dns_records" "/zones/" "api.cloudflare.com" \
  "workers.dev" "vless://" "trojan://" "hysteria2://" "tuic://" "PRIVATE KEY" "subscription"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "J: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "J: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. JSON shape
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. JSON shape ---"
echo ""

assert_contains "$B_JSON" '"ok"' "K1: ok field"
assert_contains "$B_JSON" '"zone_redacted"' "K2: zone_redacted field"
assert_contains "$B_JSON" '"hosts"' "K3: hosts field"
assert_contains "$B_JSON" '"mutation": false' "K4: mutation false"
assert_contains "$B_JSON" '"profile_write": false' "K5: profile_write false"
assert_not_contains "$B_JSON" "fake-zone-id" "K6: no zone id in JSON"
assert_not_contains "$B_JSON" "safe_api_env.env" "K7: no credential path in JSON"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.42 Subdomain Availability Read-only tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
