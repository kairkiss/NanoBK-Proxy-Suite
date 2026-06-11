#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Guided CLI Setup Wizard Test
#
# Tests the guided CLI setup wizard.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.51-guided-cli-setup-wizard.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIZARD_MODULE="$ROOT/lib/nanobk_setup_wizard.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.51"
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

# Clean up any existing profile before tests
rm -f "$PROFILE_FILE" 2>/dev/null || true

chmod 600 "$FIXTURES/safe_api_env.env"
chmod 644 "$FIXTURES/unsafe_world_readable_api_env.env"

echo ""
echo "=== Guided CLI Setup Wizard Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Non-interactive happy path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Non-interactive happy path ---"
echo ""

A_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --nodes proxy,web --yes --json 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: non-interactive exits 0"
else
  fail "A1: non-interactive should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_JSON" '"wizard_status": "ready_for_owner_review"' "A2: wizard_status ready"
assert_contains "$A_JSON" '"saved": true' "A3: profile saved"
assert_contains "$A_JSON" '"setup_status": "ready_for_owner_review"' "A4: setup_status ready"
assert_contains "$A_JSON" '"dns_changed": false' "A5: dns_changed false"
assert_contains "$A_JSON" '"records_created": false' "A6: records_created false"
assert_contains "$A_JSON" '"production_apply_enabled": false' "A7: production_apply false"
assert_contains "$A_JSON" '"wizard_only": true' "A8: wizard_only true"

A_TEXT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --nodes proxy,web --yes 2>&1)

assert_contains "$A_TEXT" "ready_for_owner_review" "A9: text final status"
assert_contains "$A_TEXT" "Production proxy/web DNS creation remains blocked" "A10: text blocked message"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Interactive happy path (simulated)
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Non-interactive with profile save ---"
echo ""

# Clean profile first
rm -f "$PROFILE_FILE" 2>/dev/null || true

B_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" --yes --json 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: non-interactive with save exits 0"
else
  fail "B1: non-interactive with save should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_JSON" '"wizard_status": "ready_for_owner_review"' "B2: wizard_status ready"
assert_contains "$B_JSON" '"saved": true' "B3: profile saved"

# Verify profile was actually saved to disk
if [[ -f "$PROFILE_FILE" ]]; then
  pass "B4: profile file exists on disk"
else
  fail "B4: profile file should exist on disk"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Cancelled
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Cancelled (simulated interactive) ---"
echo ""

# Clean profile first
rm -f "$PROFILE_FILE" 2>/dev/null || true

# Note: true interactive cancel requires TTY; test the --yes=false path via code inspection
# Instead, verify that missing --yes without args fails gracefully
C_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --json 2>&1 < /dev/null) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: cancelled exits 0"
else
  fail "C1: cancelled should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"wizard_status": "cancelled"' "C2: wizard_status cancelled"
assert_contains "$C_JSON" '"saved": false' "C3: profile not saved"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Missing args non-interactive
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Missing args non-interactive ---"
echo ""

D_JSON=$(python3 "$WIZARD_MODULE" wizard --yes --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: missing args exits non-zero ($D_RC)"
else
  fail "D1: missing args should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"wizard_status": "blocked"' "D2: wizard_status blocked"
assert_not_contains "$D_JSON" "safe_api_env.env" "D3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Unsafe api-env permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Unsafe api-env permission ---"
echo ""

E_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/unsafe_world_readable_api_env.env" \
  --yes --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: unsafe api-env exits non-zero ($E_RC)"
else
  fail "E1: unsafe api-env should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

if echo "$E_JSON" | grep -q '"wizard_status": "blocked'; then
  pass "E2: wizard_status blocked"
else
  fail "E2: wizard_status should be blocked"
  ERRORS=$((ERRORS + 1))
fi
assert_not_contains "$E_JSON" "unsafe_world_readable" "E3: no credential path"
assert_not_contains "$E_JSON" "DUMMY_PLACEHOLDER" "E4: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Profile permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Profile permission ---"
echo ""

# Clean and save a profile
rm -f "$PROFILE_FILE" 2>/dev/null || true

NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --yes --json > /dev/null 2>&1

if [[ -f "$PROFILE_FILE" ]]; then
  F_MODE=$(stat -f '%Lp' "$PROFILE_FILE" 2>/dev/null || stat -c '%a' "$PROFILE_FILE" 2>/dev/null)
  if [[ "$F_MODE" == "600" ]]; then
    pass "F1: profile mode 0600"
  else
    fail "F1: profile mode should be 600, got $F_MODE"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "F1: profile file not created"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Explicit nodes
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Explicit nodes ---"
echo ""

G_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$WIZARD_MODULE" wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --nodes proxy --yes --json 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" == "0" ]]; then
  pass "G1: explicit nodes exits 0"
else
  fail "G1: explicit nodes should exit 0, got $G_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$G_JSON" '"label": "proxy"' "G2: proxy node present"
assert_not_contains "$G_JSON" '"label": "web"' "G3: no web node"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. JSON shape stable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. JSON shape ---"
echo ""

assert_contains "$A_JSON" '"ok": true' "H1: ok field"
assert_contains "$A_JSON" '"wizard_status"' "H2: wizard_status field"
assert_contains "$A_JSON" '"profile"' "H3: profile field"
assert_contains "$A_JSON" '"setup"' "H4: setup field"
assert_contains "$A_JSON" '"safety"' "H5: safety field"
assert_contains "$A_JSON" '"zone_name"' "H6: zone_name field"
assert_contains "$A_JSON" '"nodes"' "H7: nodes field"
assert_contains "$A_JSON" '"ip_detection"' "H8: ip_detection field"
assert_contains "$A_JSON" '"wizard_only"' "H9: wizard_only field"
assert_contains "$A_JSON" '"assistant_only"' "H10: assistant_only field"
assert_contains "$A_JSON" '"plan_only"' "H11: plan_only field"
assert_contains "$A_JSON" '"api_env_path_printed": false' "H12: api_env_path_printed false"
assert_contains "$A_JSON" '"profile_path_printed": false' "H13: profile_path_printed false"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Redaction ---"
echo ""

ALL_OUTPUTS="$A_JSON $A_TEXT $B_JSON $C_JSON $D_JSON $E_JSON $G_JSON"

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
# J. Mutation guard
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Mutation guard ---"
echo ""

J_SRC=$(cat "$WIZARD_MODULE")
for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"' \
  'apply --yes' 'create_record' 'delete_record' 'update_record' 'owner.smoke.create('; do
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

for pattern in "setup wizard" "setup dns" "setup profile save" "setup profile show" "setup profile clear"; do
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

# Check menu labels exist
for pattern in "Guided setup wizard" "Beginner DNS setup assistant" "VPS IP detect" \
  "Check proxy/web availability" "Generate DNS plan" "Create preflight summary" \
  "Owner disposable smoke create" "Save setup profile" "Show setup profile" \
  "Clear setup profile" "Back"; do
  if grep -q "$pattern" "$ROOT/bin/nanobk" 2>/dev/null; then
    pass "L: console contains '$pattern'"
  else
    fail "L: console missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check correct numbering in menu display
MENU_SRC=$(sed -n '/console_dns_submenu/,/^}/p' "$ROOT/bin/nanobk")

for num_label in "1) Guided setup wizard" "2) Beginner DNS setup assistant" \
  "3) VPS IP detect" "4) Check proxy/web availability" "5) Generate DNS plan" \
  "6) Create preflight summary" "7) Owner disposable smoke create" \
  "8) Save setup profile" "9) Show setup profile" "10) Clear setup profile" \
  "11) Back"; do
  if echo "$MENU_SRC" | grep -q "$num_label"; then
    pass "L: menu has '$num_label'"
  else
    fail "L: menu missing '$num_label'"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check prompt matches
if echo "$MENU_SRC" | grep -q 'Select \[1-11\]'; then
  pass "L: prompt is Select [1-11]"
else
  fail "L: prompt should be Select [1-11]"
  ERRORS=$((ERRORS + 1))
fi

# Check for stale duplicate numbering (e.g. two "2)" entries)
DUPES=$(echo "$MENU_SRC" | grep -oE '^\s+[0-9]+\)' | sort | uniq -d)
if [[ -z "$DUPES" ]]; then
  pass "L: no duplicate menu numbers"
else
  fail "L: duplicate menu numbers found: $DUPES"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# M. Formatting checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- M. Formatting checks ---"
echo ""

WIZARD_LINES=$(wc -l < "$WIZARD_MODULE")
SELF_LINES=$(wc -l < "$0")

if [[ "$WIZARD_LINES" -ge 180 ]]; then
  pass "M1: wizard helper has $WIZARD_LINES lines (>= 180)"
else
  fail "M1: wizard helper has only $WIZARD_LINES lines (expected >= 180)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$SELF_LINES" -ge 220 ]]; then
  pass "M2: test script has $SELF_LINES lines (>= 220)"
else
  fail "M2: test script has only $SELF_LINES lines (expected >= 220)"
  ERRORS=$((ERRORS + 1))
fi

FIRST_LINE=$(head -1 "$0")
if [[ "$FIRST_LINE" == "#!/usr/bin/env bash" ]]; then
  pass "M3: first line is exactly shebang"
else
  fail "M3: first line is not shebang: $FIRST_LINE"
  ERRORS=$((ERRORS + 1))
fi

SECOND_LINE=$(sed -n '2p' "$0")
if [[ "$SECOND_LINE" == "set -Eeuo pipefail" ]]; then
  pass "M4: second line is exactly set -Eeuo pipefail"
else
  fail "M4: second line is not set -Eeuo pipefail: $SECOND_LINE"
  ERRORS=$((ERRORS + 1))
fi

if python3 -m py_compile "$WIZARD_MODULE" 2>/dev/null; then
  pass "M5: wizard helper passes py_compile"
else
  fail "M5: wizard helper fails py_compile"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

# Clean up profile
rm -f "$PROFILE_FILE" 2>/dev/null || true

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.51 Guided CLI Setup Wizard tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
