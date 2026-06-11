#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Setup Explain Next Actions Test
#
# Tests the setup result explanation helper.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.52-setup-explain-next-actions.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSISTANT_MODULE="$ROOT/lib/nanobk_dns_setup_assistant.py"
WIZARD_MODULE="$ROOT/lib/nanobk_setup_wizard.py"
EXPLAIN_MODULE="$ROOT/lib/nanobk_setup_explain.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.52"
PROFILE_DIR="$HOME/.nanobk"
PROFILE_FILE="$PROFILE_DIR/setup-profile.json"

pass() { echo "  [OK] $*"; }
fail() { echo "  [FAIL] $*" >&2; }

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

rm -f "$PROFILE_FILE" 2>/dev/null || true
chmod 600 "$FIXTURES/safe_api_env.env"
chmod 644 "$FIXTURES/unsafe_world_readable_api_env.env"

echo ""
echo "=== Setup Explain Next Actions Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. ready_for_owner_review explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. ready_for_owner_review explanation ---"
echo ""

A_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && A_RC=0 || A_RC=$?

assert_contains "$A_JSON" '"explanation"' "A1: JSON has explanation"
assert_contains "$A_JSON" '"summary_title"' "A2: has summary_title"
assert_contains "$A_JSON" '"plain_status"' "A3: has plain_status"
assert_contains "$A_JSON" '"completed"' "A4: has completed"
assert_contains "$A_JSON" '"not_done"' "A5: has not_done"
assert_contains "$A_JSON" '"why_blocked"' "A6: has why_blocked"
assert_contains "$A_JSON" '"next_actions"' "A7: has next_actions"
assert_contains "$A_JSON" '"fix_hints"' "A8: has fix_hints"
assert_contains "$A_JSON" '"Ready for owner review"' "A9: summary_title correct"
assert_contains "$A_JSON" 'nanobk setup dns' "A10: next action has setup dns"
assert_contains "$A_JSON" 'create-preflight' "A11: next action has create-preflight"
assert_contains "$A_JSON" '<redacted>' "A12: api-env redacted in next action"

A_TEXT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" 2>&1)

assert_contains "$A_TEXT" "What this means:" "A13: text has What this means"
assert_contains "$A_TEXT" "Completed:" "A14: text has Completed"
assert_contains "$A_TEXT" "Not done:" "A15: text has Not done"
assert_contains "$A_TEXT" "Why NanoBK stopped here:" "A16: text has Why blocked"
assert_contains "$A_TEXT" "Next actions:" "A17: text has Next actions"
assert_contains "$A_TEXT" "nanobk setup dns" "A18: text next action has setup dns"
assert_contains "$A_TEXT" "<redacted>" "A19: text api-env redacted"
assert_not_contains "$A_TEXT" "$FIXTURES" "A20: no fixture path in text"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. No IP explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. No IP explanation ---"
echo ""

B_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && B_RC=0 || B_RC=$?

assert_contains "$B_JSON" '"incomplete_no_ip"' "B1: status incomplete_no_ip"
assert_contains "$B_JSON" "No public IP" "B2: summary mentions no IP"
assert_contains "$B_JSON" "VPS" "B3: fix hints mention VPS"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Conflict explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Conflict explanation ---"
echo ""

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_proxy_occupied.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && C_RC=0 || C_RC=$?

assert_contains "$C_JSON" "blocked_subdomain_conflict" "C1: status conflict"
assert_contains "$C_JSON" "existing" "C2: mentions existing records"
assert_contains "$C_JSON" "overwrite" "C3: mentions no overwrite"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Availability failure explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Availability failure explanation ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_api_failure.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --json 2>&1) && D_RC=0 || D_RC=$?

assert_contains "$D_JSON" "manual_review_required" "D1: status manual_review"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Credential blocked explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Credential blocked explanation ---"
echo ""

E_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/unsafe_world_readable_api_env.env" --json 2>&1) && E_RC=0 || E_RC=$?

assert_contains "$E_JSON" "blocked_credential" "E1: status blocked_credential"
assert_contains "$E_JSON" "0600" "E2: mentions permission 0600"
assert_not_contains "$E_JSON" "unsafe_world_readable" "E3: no credential path"
assert_not_contains "$E_JSON" "DUMMY_PLACEHOLDER" "E4: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Cancelled wizard explanation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Cancelled wizard explanation ---"
echo ""

F_JSON=$(python3 "$WIZARD_MODULE" wizard --json 2>&1 < /dev/null) && F_RC=0 || F_RC=$?

assert_contains "$F_JSON" '"wizard_status": "cancelled"' "F1: wizard_status cancelled"
assert_contains "$F_JSON" '"explanation"' "F2: has explanation"
assert_contains "$F_JSON" "cancelled" "F3: mentions cancelled"
assert_contains "$F_JSON" "nanobk setup wizard" "F4: next action rerun wizard"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. JSON shape stable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. JSON shape ---"
echo ""

assert_contains "$A_JSON" '"summary_title": "Ready for owner review"' "G1: summary_title"
assert_contains "$A_JSON" '"plain_status"' "G2: plain_status"
assert_contains "$A_JSON" '"completed"' "G3: completed array"
assert_contains "$A_JSON" '"not_done"' "G4: not_done array"
assert_contains "$A_JSON" '"why_blocked"' "G5: why_blocked array"
assert_contains "$A_JSON" '"next_actions"' "G6: next_actions array"
assert_contains "$A_JSON" '"fix_hints"' "G7: fix_hints array"
assert_contains "$A_JSON" '"dns_changed": false' "G8: safety dns_changed"
assert_contains "$A_JSON" '"records_created": false' "G9: safety records_created"
assert_contains "$A_JSON" '"production_apply_enabled": false' "G10: safety production_apply"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Redaction ---"
echo ""

ALL_OUTPUTS="$A_JSON $A_TEXT $B_JSON $C_JSON $D_JSON $E_JSON $F_JSON"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "H: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "H: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Mutation guard
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Mutation guard ---"
echo ""

I_SRC=$(cat "$EXPLAIN_MODULE")
for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"'; do
  if echo "$I_SRC" | grep -q "$method"; then
    fail "I: explain module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Help unchanged
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Help unchanged ---"
echo ""

J_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for pattern in "setup wizard" "setup dns" "setup profile save" "setup profile show" "setup profile clear"; do
  if echo "$J_HELP" | grep -qi "$pattern"; then
    pass "J: help contains '$pattern'"
  else
    fail "J: help missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Formatting checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Formatting checks ---"
echo ""

EXPLAIN_LINES=$(wc -l < "$EXPLAIN_MODULE")
SELF_LINES=$(wc -l < "$0")

if [[ "$EXPLAIN_LINES" -ge 160 ]]; then
  pass "K1: explain helper has $EXPLAIN_LINES lines (>= 160)"
else
  fail "K1: explain helper has only $EXPLAIN_LINES lines (expected >= 160)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$SELF_LINES" -ge 220 ]]; then
  pass "K2: test script has $SELF_LINES lines (>= 220)"
else
  fail "K2: test script has only $SELF_LINES lines (expected >= 220)"
  ERRORS=$((ERRORS + 1))
fi

FIRST_LINE=$(head -1 "$0")
if [[ "$FIRST_LINE" == "#!/usr/bin/env bash" ]]; then
  pass "K3: first line is exactly shebang"
else
  fail "K3: first line is not shebang: $FIRST_LINE"
  ERRORS=$((ERRORS + 1))
fi

SECOND_LINE=$(sed -n '2p' "$0")
if [[ "$SECOND_LINE" == "set -Eeuo pipefail" ]]; then
  pass "K4: second line is exactly set -Eeuo pipefail"
else
  fail "K4: second line is not set -Eeuo pipefail: $SECOND_LINE"
  ERRORS=$((ERRORS + 1))
fi

if python3 -m py_compile "$EXPLAIN_MODULE" 2>/dev/null; then
  pass "K5: explain helper passes py_compile"
else
  fail "K5: explain helper fails py_compile"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

rm -f "$PROFILE_FILE" 2>/dev/null || true

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.52 Setup Explain Next Actions tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
