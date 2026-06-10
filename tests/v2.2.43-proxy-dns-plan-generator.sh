#!/usr/bin/env bash
# NanoBK Proxy Suite — Proxy DNS Plan Generator Test
#
# Tests the read-only proxy DNS plan generator.
# Uses env var mocks for IP detection and availability. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.43-proxy-dns-plan-generator.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_plan_generator.py"
FIXTURES_42="$ROOT/tests/fixtures/v2.2.42"
FIXTURES_43="$ROOT/tests/fixtures/v2.2.43"

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

# Ensure safe credential is 0600
chmod 600 "$FIXTURES_42/safe_api_env.env"

# Copy availability fixtures for v2.2.43 use
cp "$FIXTURES_42/fake_response_map_both_available.json" "$FIXTURES_43/" 2>/dev/null || true
cp "$FIXTURES_42/fake_response_map_proxy_occupied.json" "$FIXTURES_43/" 2>/dev/null || true
cp "$FIXTURES_42/fake_response_map_api_failure.json" "$FIXTURES_43/" 2>/dev/null || true

echo ""
echo "=== Proxy DNS Plan Generator Test ==="
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
# B. Proxy available + IPv4/IPv6 detected → plan_status=ready
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Dual-stack ready ---"
echo ""

B_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.10" NANOBK_TEST_DETECTED_IPV6="2001:db8::10" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: dual-stack ready exits 0"
else
  fail "B1: dual-stack ready should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "plan: ready" "B2: plan status ready"
assert_contains "$B_OUT" "A record: ready" "B3: A record ready"
assert_contains "$B_OUT" "AAAA record: ready" "B4: AAAA record ready"

B_JSON=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.10" NANOBK_TEST_DETECTED_IPV6="2001:db8::10" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1)

assert_contains "$B_JSON" '"plan_status": "ready"' "B5: JSON plan_status ready"
assert_contains "$B_JSON" '"a_record": "ready"' "B6: JSON A record ready"
assert_contains "$B_JSON" '"aaaa_record": "ready"' "B7: JSON AAAA record ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Proxy available + IPv4 only → A ready, AAAA skipped
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. IPv4 only ---"
echo ""

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.20" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: IPv4-only exits 0"
else
  fail "C1: IPv4-only should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"plan_status": "ready"' "C2: JSON plan ready"
assert_contains "$C_JSON" '"a_record": "ready"' "C3: JSON A ready"
assert_contains "$C_JSON" '"aaaa_record": "skipped"' "C4: JSON AAAA skipped"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Proxy available + IPv6 only → A skipped, AAAA ready
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. IPv6 only ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECTED_IPV6="2001:db8::30" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: IPv6-only exits 0"
else
  fail "D1: IPv6-only should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"plan_status": "ready"' "D2: JSON plan ready"
assert_contains "$D_JSON" '"a_record": "skipped"' "D3: JSON A skipped"
assert_contains "$D_JSON" '"aaaa_record": "ready"' "D4: JSON AAAA ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. No public IP → plan_status=blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. No public IP ---"
echo ""

E_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "0" ]]; then
  pass "E1: no IP exits 0"
else
  fail "E1: no IP should exit 0, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" '"plan_status": "blocked"' "E2: JSON plan blocked"
assert_contains "$E_JSON" '"a_record": "skipped"' "E3: JSON A skipped"
assert_contains "$E_JSON" '"aaaa_record": "skipped"' "E4: JSON AAAA skipped"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Proxy conflict → plan_status=blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Proxy conflict ---"
echo ""

F_JSON=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.40" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_proxy_occupied.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" == "0" ]]; then
  pass "F1: conflict exits 0"
else
  fail "F1: conflict should exit 0, got $F_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_JSON" '"plan_status": "blocked"' "F2: JSON plan blocked"
assert_contains "$F_JSON" '"any_conflict": true' "F3: JSON any_conflict true"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Availability failure → plan blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Availability failure ---"
echo ""

G_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.50" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_api_failure.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" != "0" ]]; then
  pass "G1: availability failure exits non-zero ($G_RC)"
else
  fail "G1: availability failure should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Unsafe credential permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Unsafe credential permission ---"
echo ""

chmod 644 "$FIXTURES_42/unsafe_world_readable_api_env.env"

H_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.60" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_43/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns plan-generator --zone example.com --api-env "$FIXTURES_42/unsafe_world_readable_api_env.env" 2>&1) && H_RC=0 || H_RC=$?

if [[ "$H_RC" != "0" ]]; then
  pass "H1: unsafe credential exits non-zero ($H_RC)"
else
  fail "H1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$H_OUT" "Insecure" "H2: insecure message"
assert_not_contains "$H_OUT" "unsafe_world_readable" "H3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Mutation guard — verify module source
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Mutation guard ---"
echo ""

I_SRC=$(cat "$MODULE")
for method in "method=\"POST\"" "method=\"PATCH\"" "method=\"PUT\"" "method=\"DELETE\"" "apply --yes" "create_record" "delete_record" "update_record"; do
  if echo "$I_SRC" | grep -q "$method"; then
    fail "I: module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. JSON shape stable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. JSON shape ---"
echo ""

assert_contains "$B_JSON" '"ok": true' "J1: ok field"
assert_contains "$B_JSON" '"plan_status"' "J2: plan_status field"
assert_contains "$B_JSON" '"zone_redacted"' "J3: zone_redacted"
assert_contains "$B_JSON" '"ip_detection"' "J4: ip_detection"
assert_contains "$B_JSON" '"ipv4"' "J5: ipv4"
assert_contains "$B_JSON" '"ipv6"' "J6: ipv6"
assert_contains "$B_JSON" '"nodes"' "J7: nodes"
assert_contains "$B_JSON" '"safety"' "J8: safety"
assert_contains "$B_JSON" '"plan_only": true' "J9: plan_only true"
assert_contains "$B_JSON" '"dns_changed": false' "J10: dns_changed false"
assert_contains "$B_JSON" '"mutation_allowed": false' "J11: mutation_allowed false"
assert_contains "$B_JSON" '"mutation": false' "J12: mutation false"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Redaction coverage
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Redaction ---"
echo ""

ALL_OUTPUTS="$B_OUT $B_JSON $C_JSON $D_JSON $E_JSON $F_JSON $G_OUT $H_OUT"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "safe_api_env.env" \
  "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " "/dns_records" "/zones/" \
  "api.cloudflare.com" "workers.dev" "vless://" "trojan://" "hysteria2://" "tuic://" \
  "PRIVATE KEY" "subscription" "apply --yes"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "K: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "K: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. CLI help
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. CLI help ---"
echo ""

L_HELP=$("$ROOT/bin/nanobk" cf dns plan-generator --help 2>&1) && L_RC=0 || L_RC=$?

if echo "$L_HELP" | grep -q "plan-generator\|generate"; then
  pass "L1: help shows plan-generator"
else
  fail "L1: help should show plan-generator"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.43 Proxy DNS Plan Generator tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
