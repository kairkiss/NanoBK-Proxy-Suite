#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Beginner DNS Setup Assistant Test
#
# Tests the beginner DNS setup assistant.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.49-beginner-dns-setup-assistant.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_dns_setup_assistant.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.49"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}\u2713${NC} $*"; }
fail() { echo -e "  ${RED}\u2717${NC} $*" >&2; }

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

chmod 600 "$FIXTURES/safe_api_env.env"
chmod 644 "$FIXTURES/unsafe_world_readable_api_env.env"

echo ""
echo "=== Beginner DNS Setup Assistant Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Happy path: dual-stack, both available, plan ready
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Happy path ---"
echo ""

A_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: happy path exits 0"
else
  fail "A1: happy path should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_JSON" '"setup_status": "ready_for_owner_review"' "A2: setup_status ready"
assert_contains "$A_JSON" '"ok": true' "A3: ok true"
assert_contains "$A_JSON" '"dns_changed": false' "A4: dns_changed false"
assert_contains "$A_JSON" '"records_created": false' "A5: records_created false"
assert_contains "$A_JSON" '"production_apply_enabled": false' "A6: production_apply false"
assert_contains "$A_JSON" '"assistant_only": true' "A7: assistant_only true"
assert_contains "$A_JSON" '"plan_only": true' "A8: plan_only true"

A_TEXT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" 2>&1)

assert_contains "$A_TEXT" "IPv4: detected" "A9: text IPv4 detected"
assert_contains "$A_TEXT" "IPv6: detected" "A10: text IPv6 detected"
assert_contains "$A_TEXT" "ready_for_owner_review" "A11: text setup_status"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. IPv4 only
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. IPv4 only ---"
echo ""

B_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: IPv4-only exits 0"
else
  fail "B1: IPv4-only should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_JSON" '"setup_status": "ready_for_owner_review"' "B2: setup_status ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. IPv6 only
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. IPv6 only ---"
echo ""

C_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: IPv6-only exits 0"
else
  fail "C1: IPv6-only should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"setup_status": "ready_for_owner_review"' "C2: setup_status ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. No IP
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. No IP ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: no IP exits non-zero ($D_RC)"
else
  fail "D1: no IP should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" "incomplete_no_ip" "D2: setup_status incomplete_no_ip"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Proxy conflict
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Proxy conflict ---"
echo ""

E_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_proxy_occupied.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "0" ]]; then
  pass "E1: proxy conflict exits 0"
else
  fail "E1: proxy conflict should exit 0, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" "blocked_subdomain_conflict" "E2: setup_status blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Availability API failure
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Availability API failure ---"
echo ""

F_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_api_failure.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: API failure exits non-zero ($F_RC)"
else
  fail "F1: API failure should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Unsafe credential
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Unsafe credential ---"
echo ""

G_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$MODULE" setup --zone example.com --api-env "$FIXTURES/unsafe_world_readable_api_env.env" --json 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" != "0" ]]; then
  pass "G1: unsafe credential exits non-zero ($G_RC)"
else
  fail "G1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$G_JSON" "unsafe_world_readable" "G2: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. JSON shape
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. JSON shape ---"
echo ""

assert_contains "$A_JSON" '"setup_status"' "H1: setup_status field"
assert_contains "$A_JSON" '"nodes"' "H2: nodes field"
assert_contains "$A_JSON" '"ip_detection"' "H3: ip_detection field"
assert_contains "$A_JSON" '"preflight"' "H4: preflight field"
assert_contains "$A_JSON" '"safety"' "H5: safety field"
assert_contains "$A_JSON" '"label"' "H6: label field"
assert_contains "$A_JSON" '"hostname"' "H7: hostname field"
assert_contains "$A_JSON" '"availability"' "H8: availability field"
assert_contains "$A_JSON" '"plan_status"' "H9: plan_status field"
assert_contains "$A_JSON" '"a_record"' "H10: a_record field"
assert_contains "$A_JSON" '"aaaa_record"' "H11: aaaa_record field"
assert_contains "$A_JSON" '"requires_owner_approval"' "H12: requires_owner_approval"
assert_contains "$A_JSON" '"requires_cleanup_or_rollback_plan"' "H13: requires_cleanup"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Redaction ---"
echo ""

ALL_OUTPUTS="$A_JSON $A_TEXT $B_JSON $C_JSON $D_JSON $E_JSON $F_JSON $G_JSON"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription" "apply --yes"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "I: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Mutation guard — verify module source
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Mutation guard ---"
echo ""

J_SRC=$(cat "$MODULE")
for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"' \
  'apply --yes' 'create_record' 'delete_record' 'update_record'; do
  if echo "$J_SRC" | grep -q "$method"; then
    fail "J: module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "J: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Help updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Help updated ---"
echo ""

K_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for pattern in "setup dns" "初学者 DNS 设置助手" "cf dns availability summary" \
  "cf dns plan-generator" "cf dns create-preflight"; do
  if echo "$K_HELP" | grep -qi "$pattern"; then
    pass "K: help contains '$pattern'"
  else
    fail "K: help missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Console menu updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Console menu ---"
echo ""

for pattern in "Beginner DNS setup assistant" "VPS IP detect" "Check proxy/web availability" \
  "Generate DNS plan" "Create preflight summary" "Owner disposable smoke create"; do
  if grep -q "$pattern" "$ROOT/bin/nanobk" 2>/dev/null; then
    pass "L: console contains '$pattern'"
  else
    fail "L: console missing '$pattern'"
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
  echo "  All v2.2.49 Beginner DNS Setup Assistant tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
