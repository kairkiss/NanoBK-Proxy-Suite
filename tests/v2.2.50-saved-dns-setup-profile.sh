#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Saved DNS Setup Profile Test
#
# Tests the saved DNS setup profile functionality.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.50-saved-dns-setup-profile.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_MODULE="$ROOT/lib/nanobk_setup_profile.py"
ASSISTANT_MODULE="$ROOT/lib/nanobk_dns_setup_assistant.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.50"
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
echo "=== Saved DNS Setup Profile Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Save profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Save profile ---"
echo ""

A_OUT=$(python3 "$PROFILE_MODULE" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: save exits 0"
else
  fail "A1: save should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

if [[ -f "$PROFILE_FILE" ]]; then
  pass "A2: profile file created"
else
  fail "A2: profile file not created"
  ERRORS=$((ERRORS + 1))
fi

# Check file mode
A_MODE=$(stat -f '%Lp' "$PROFILE_FILE" 2>/dev/null || stat -c '%a' "$PROFILE_FILE" 2>/dev/null)
if [[ "$A_MODE" == "600" ]]; then
  pass "A3: profile mode 0600"
else
  fail "A3: profile mode should be 600, got $A_MODE"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$A_OUT" "$FIXTURES/safe_api_env.env" "A4: no credential path in output"
assert_not_contains "$A_OUT" "DUMMY_PLACEHOLDER" "A5: no token in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Show profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Show profile ---"
echo ""

B_OUT=$(python3 "$PROFILE_MODULE" show 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: show exits 0"
else
  fail "B1: show should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "example.com" "B2: shows zone"
assert_contains "$B_OUT" "proxy" "B3: shows proxy node"
assert_contains "$B_OUT" "web" "B4: shows web node"
assert_contains "$B_OUT" "configured" "B5: api_env_configured"
assert_not_contains "$B_OUT" "$FIXTURES/safe_api_env.env" "B6: no credential path"

B_JSON=$(python3 "$PROFILE_MODULE" show --json 2>&1)

assert_contains "$B_JSON" '"ok": true' "B7: JSON ok true"
assert_contains "$B_JSON" '"zone_name": "example.com"' "B8: JSON zone"
assert_contains "$B_JSON" '"api_env_configured": true' "B9: JSON api_env_configured"
assert_contains "$B_JSON" '"api_env_path_printed": false' "B10: JSON path not printed"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Clear profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Clear profile ---"
echo ""

C_OUT=$(python3 "$PROFILE_MODULE" clear 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: clear exits 0"
else
  fail "C1: clear should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

if [[ ! -f "$PROFILE_FILE" ]]; then
  pass "C2: profile file deleted"
else
  fail "C2: profile file should be deleted"
  ERRORS=$((ERRORS + 1))
fi

# Second clear should be safe
C2_OUT=$(python3 "$PROFILE_MODULE" clear 2>&1) && C2_RC=0 || C2_RC=$?

if [[ "$C2_RC" == "0" ]]; then
  pass "C3: second clear exits 0"
else
  fail "C3: second clear should exit 0, got $C2_RC"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Setup dns uses profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Setup dns uses profile ---"
echo ""

# Save a profile first
python3 "$PROFILE_MODULE" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web > /dev/null 2>&1

D_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: setup with profile exits 0"
else
  fail "D1: setup with profile should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"setup_status": "ready_for_owner_review"' "D2: setup_status ready"
assert_contains "$D_JSON" '"zone_name": "example.com"' "D3: uses profile zone"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Explicit args override profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Explicit args override profile ---"
echo ""

E_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ASSISTANT_MODULE" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "0" ]]; then
  pass "E1: explicit args exit 0"
else
  fail "E1: explicit args should exit 0, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" '"zone_name": "example.com"' "E2: uses explicit zone"
assert_contains "$E_JSON" '"label": "proxy"' "E3: uses explicit nodes (proxy only)"
assert_not_contains "$E_JSON" '"label": "web"' "E4: no web node (explicit override)"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Missing profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Missing profile ---"
echo ""

# Clear profile first
python3 "$PROFILE_MODULE" clear > /dev/null 2>&1

F_OUT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$ASSISTANT_MODULE" setup --json 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: missing profile exits non-zero ($F_RC)"
else
  fail "F1: missing profile should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "No setup profile found" "F2: helpful message"
assert_not_contains "$F_OUT" "$FIXTURES" "F3: no fixture path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Unsafe profile permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Unsafe profile permission ---"
echo ""

# Save profile then chmod 0644
python3 "$PROFILE_MODULE" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1
chmod 644 "$PROFILE_FILE"

G_OUT=$(python3 "$PROFILE_MODULE" show --json 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" != "0" ]]; then
  pass "G1: unsafe profile exits non-zero ($G_RC)"
else
  fail "G1: unsafe profile should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$G_OUT" "insecure" "G2: insecure message"
assert_not_contains "$G_OUT" "DUMMY_PLACEHOLDER" "G3: no token"

# Clean up
rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Malformed profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Malformed profile ---"
echo ""

mkdir -p "$PROFILE_DIR"
echo "not valid json {{{" > "$PROFILE_FILE"
chmod 600 "$PROFILE_FILE"

H_OUT=$(python3 "$PROFILE_MODULE" show --json 2>&1) && H_RC=0 || H_RC=$?

if [[ "$H_RC" != "0" ]]; then
  pass "H1: malformed profile exits non-zero ($H_RC)"
else
  fail "H1: malformed profile should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$H_OUT" "malformed" "H2: malformed message"

# Clean up
rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Redaction ---"
echo ""

# Save profile for redaction check
python3 "$PROFILE_MODULE" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

I_SHOW=$(python3 "$PROFILE_MODULE" show 2>&1)
I_JSON=$(python3 "$PROFILE_MODULE" show --json 2>&1)

ALL_OUTPUTS="$A_OUT $B_OUT $B_JSON $C_OUT $D_JSON $E_JSON $F_OUT $G_OUT $H_OUT $I_SHOW $I_JSON"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "I: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$forbidden'"
  fi
done

# Clean up
rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Help updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Help updated ---"
echo ""

J_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for pattern in "setup dns" "setup profile save" "setup profile show" "setup profile clear"; do
  if echo "$J_HELP" | grep -qi "$pattern"; then
    pass "J: help contains '$pattern'"
  else
    fail "J: help missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Console menu updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Console menu ---"
echo ""

for pattern in "Save setup profile" "Show setup profile" "Clear setup profile"; do
  if grep -q "$pattern" "$ROOT/bin/nanobk" 2>/dev/null; then
    pass "K: console contains '$pattern'"
  else
    fail "K: console missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. No mutation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. No mutation ---"
echo ""

L_SRC=$(cat "$PROFILE_MODULE")
for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"'; do
  if echo "$L_SRC" | grep -q "$method"; then
    fail "L: module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "L: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# M. Formatting checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- M. Formatting checks ---"
echo ""

PROFILE_LINES=$(wc -l < "$PROFILE_MODULE")
SELF_LINES=$(wc -l < "$0")

if [[ "$PROFILE_LINES" -ge 120 ]]; then
  pass "M1: profile helper has $PROFILE_LINES lines (>= 120)"
else
  fail "M1: profile helper has only $PROFILE_LINES lines (expected >= 120)"
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

if python3 -m py_compile "$PROFILE_MODULE" 2>/dev/null; then
  pass "M5: profile helper passes py_compile"
else
  fail "M5: profile helper fails py_compile"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.50 Saved DNS Setup Profile tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
