#!/usr/bin/env bash
# NanoBK Proxy Suite — Controlled Proxy DNS Create Preflight Test
#
# Tests the create-preflight command. Plan-only, no mutation.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.44-controlled-proxy-dns-create-preflight.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_create_preflight.py"
FIXTURES_42="$ROOT/tests/fixtures/v2.2.42"

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

chmod 600 "$FIXTURES_42/safe_api_env.env"

echo ""
echo "=== Controlled Proxy DNS Create Preflight Test ==="
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
# B. Dual-stack ready → preflight ready_for_owner_review
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Dual-stack ready ---"
echo ""

B_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.10" NANOBK_TEST_DETECTED_IPV6="2001:db8::10" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_42/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: dual-stack exits 0"
else
  fail "B1: dual-stack should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "ready_for_owner_review" "B2: preflight ready"
assert_contains "$B_OUT" "requires_owner_approval" "B3: execution gate"
assert_contains "$B_OUT" "Mutation allowed: false" "B4: mutation false"
assert_contains "$B_OUT" "Apply ready: false" "B5: apply_ready false"
assert_contains "$B_OUT" "Preflight-only: true" "B6: preflight_only true"
assert_contains "$B_OUT" "DNS changed: false" "B7: dns_changed false"
assert_contains "$B_OUT" "Overwrite existing: false" "B8: overwrite false"
assert_contains "$B_OUT" "Force: false" "B9: force false"
assert_contains "$B_OUT" "requires_owner_approval: true" "B10: requires owner approval"
assert_contains "$B_OUT" "requires_disposable_first: true" "B11: requires disposable"
assert_contains "$B_OUT" "requires_post_check: true" "B12: requires post check"
assert_contains "$B_OUT" "requires_cleanup_or_rollback_plan: true" "B13: requires cleanup"
assert_contains "$B_OUT" "A would create" "B14: would create A"

B_JSON=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.10" NANOBK_TEST_DETECTED_IPV6="2001:db8::10" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_42/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1)

assert_contains "$B_JSON" '"preflight_status": "ready_for_owner_review"' "B15: JSON preflight ready"
assert_contains "$B_JSON" '"mutation_allowed": false' "B16: JSON mutation false"
assert_contains "$B_JSON" '"apply_ready": false' "B17: JSON apply_ready false"
assert_contains "$B_JSON" '"preflight_only": true' "B18: JSON preflight_only true"
assert_contains "$B_JSON" '"records_created": false' "B19: JSON records_created false"
assert_contains "$B_JSON" '"overwrite_existing": false' "B20: JSON overwrite false"
assert_contains "$B_JSON" '"force": false' "B21: JSON force false"
assert_contains "$B_JSON" '"requires_owner_approval": true' "B22: JSON requires owner"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Proxy conflict → preflight blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Proxy conflict ---"
echo ""

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.20" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_42/fake_response_map_proxy_occupied.json" \
  "$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: conflict exits 0"
else
  fail "C1: conflict should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"preflight_status": "blocked"' "C2: JSON preflight blocked"
assert_contains "$C_JSON" '"blocked": true' "C3: JSON node blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. No public IP → preflight blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. No public IP ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_42/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: no IP exits 0"
else
  fail "D1: no IP should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"preflight_status": "blocked"' "D2: JSON preflight blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Unsafe credential → fail closed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Unsafe credential ---"
echo ""

chmod 644 "$FIXTURES_42/unsafe_world_readable_api_env.env"

E_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.30" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES_42/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/unsafe_world_readable_api_env.env" 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: unsafe credential exits non-zero ($E_RC)"
else
  fail "E1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "Insecure" "E2: insecure message"
assert_not_contains "$E_OUT" "unsafe_world_readable" "E3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Dangerous flags rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Dangerous flags rejected ---"
echo ""

for flag in "--apply" "--yes" "--force" "--overwrite"; do
  F_OUT=$("$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$FIXTURES_42/safe_api_env.env" "$flag" 2>&1) && F_RC=0 || F_RC=$?
  if [[ "$F_RC" != "0" ]]; then
    pass "F: $flag rejected (rc=$F_RC)"
  else
    fail "F: $flag should be rejected"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F2. --dry-run does not leak credential path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F2. --dry-run credential path redaction ---"
echo ""

SENSITIVE_PATH="/root/NanoBK-Proxy-Suite/.nanobk-local/cloudflare.local-credential.env"

F2_OUT=$("$ROOT/bin/nanobk" cf dns create-preflight --zone example.com --api-env "$SENSITIVE_PATH" --dry-run 2>&1) && F2_RC=0 || F2_RC=$?

if [[ "$F2_RC" == "0" ]]; then
  pass "F2-1: --dry-run exits 0"
else
  fail "F2-1: --dry-run should exit 0, got $F2_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$F2_OUT" "/root/" "F2-2: no /root/ in dry-run"
assert_not_contains "$F2_OUT" ".nanobk-local" "F2-3: no .nanobk-local in dry-run"
assert_not_contains "$F2_OUT" "cloudflare.local-credential.env" "F2-4: no credential filename"
assert_not_contains "$F2_OUT" "$SENSITIVE_PATH" "F2-5: no full path"
assert_not_contains "$F2_OUT" "CF_API_TOKEN" "F2-6: no CF_API_TOKEN"
assert_not_contains "$F2_OUT" "CLOUDFLARE_API_TOKEN" "F2-7: no CLOUDFLARE_API_TOKEN"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F3. Global --dry-run flag does not leak credential path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F3. Global --dry-run credential path redaction ---"
echo ""

F3_OUT=$("$ROOT/bin/nanobk" --dry-run cf dns create-preflight --zone example.com --api-env "$SENSITIVE_PATH" 2>&1) && F3_RC=0 || F3_RC=$?

if [[ "$F3_RC" == "0" ]]; then
  pass "F3-1: global --dry-run exits 0"
else
  fail "F3-1: global --dry-run should exit 0, got $F3_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$F3_OUT" "/root/" "F3-2: no /root/ in global dry-run"
assert_not_contains "$F3_OUT" ".nanobk-local" "F3-3: no .nanobk-local in global dry-run"
assert_not_contains "$F3_OUT" "cloudflare.local-credential.env" "F3-4: no credential filename"
assert_not_contains "$F3_OUT" "$SENSITIVE_PATH" "F3-5: no full path"
assert_not_contains "$F3_OUT" "CF_API_TOKEN" "F3-6: no CF_API_TOKEN"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Mutation guard — verify module source
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Mutation guard ---"
echo ""

G_SRC=$(cat "$MODULE")
for method in "method=\"POST\"" "method=\"PATCH\"" "method=\"PUT\"" "method=\"DELETE\"" "apply --yes" "create_record" "delete_record" "update_record"; do
  if echo "$G_SRC" | grep -q "$method"; then
    fail "G: module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "G: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Redaction coverage
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Redaction ---"
echo ""

ALL_OUTPUTS="$B_OUT $B_JSON $C_JSON $D_JSON $E_OUT"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "safe_api_env.env" \
  "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " "/dns_records" "/zones/" \
  "api.cloudflare.com" "workers.dev" "vless://" "trojan://" "hysteria2://" "tuic://" \
  "PRIVATE KEY" "subscription" "apply --yes"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "H: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "H: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. JSON shape
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. JSON shape ---"
echo ""

assert_contains "$B_JSON" '"ok": true' "I1: ok field"
assert_contains "$B_JSON" '"preflight_status"' "I2: preflight_status"
assert_contains "$B_JSON" '"execution_gate"' "I3: execution_gate"
assert_contains "$B_JSON" '"create_candidates"' "I4: create_candidates"
assert_contains "$B_JSON" '"safety"' "I5: safety"
assert_contains "$B_JSON" '"would_create"' "I6: would_create"
assert_contains "$B_JSON" '"requires_owner_approval"' "I7: requires_owner_approval"
assert_contains "$B_JSON" '"requires_disposable_first"' "I8: requires_disposable_first"
assert_contains "$B_JSON" '"requires_post_check"' "I9: requires_post_check"
assert_contains "$B_JSON" '"requires_cleanup_or_rollback_plan"' "I10: requires_cleanup"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.44 Controlled DNS Create Preflight tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
