#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Unified Setup Status / Home Test
#
# Tests the unified setup status / CLI home overview.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.53-unified-setup-status-home.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_MODULE="$ROOT/lib/nanobk_setup_status.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.53"
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
echo "=== Unified Setup Status / Home Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. No profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. No profile ---"
echo ""

rm -f "$PROFILE_FILE" 2>/dev/null || true

A_JSON=$(python3 "$STATUS_MODULE" home --json 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" == "0" ]]; then
  pass "A1: no profile exits 0"
else
  fail "A1: no profile should exit 0, got $A_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_JSON" '"home_status": "no_profile"' "A2: status no_profile"
assert_contains "$A_JSON" '"not_configured"' "A3: profile not_configured"
assert_contains "$A_JSON" 'nanobk setup wizard' "A4: next action setup wizard"
assert_contains "$A_JSON" '"cloudflare_touched": "false"' "A5: cf touched false"
assert_contains "$A_JSON" '"dns_changed": false' "A6: dns_changed false"

A_TEXT=$(python3 "$STATUS_MODULE" home 2>&1)
assert_contains "$A_TEXT" "NanoBK Home" "A7: text has title"
assert_contains "$A_TEXT" "not_configured" "A8: text not configured"
assert_contains "$A_TEXT" "nanobk setup wizard" "A9: text next action"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Configured profile happy path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Configured profile ---"
echo ""

# Save a profile first
NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$ROOT/lib/nanobk_dns_setup_assistant.py" setup --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

# Save profile via setup profile save
python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web > /dev/null 2>&1

B_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$STATUS_MODULE" home --json 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: configured exits 0"
else
  fail "B1: configured should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_JSON" '"home_status": "ready_for_owner_review"' "B2: status ready"
assert_contains "$B_JSON" '"configured"' "B3: profile configured"
assert_contains "$B_JSON" '"zone_name": "example.com"' "B4: zone name"
assert_contains "$B_JSON" '"explanation"' "B5: has explanation"
assert_contains "$B_JSON" '"next_actions"' "B6: has next_actions"
assert_not_contains "$B_JSON" "$FIXTURES" "B7: no fixture path"
assert_not_contains "$B_JSON" "DUMMY_PLACEHOLDER" "B8: no token"

B_TEXT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$STATUS_MODULE" home 2>&1)

assert_contains "$B_TEXT" "ready_for_owner_review" "B9: text status"
assert_contains "$B_TEXT" "example.com" "B10: text zone"
assert_contains "$B_TEXT" "<redacted>" "B11: api-env redacted"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. nanobk setup status alias
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. setup status alias ---"
echo ""

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" setup status --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: setup status exits 0"
else
  fail "C1: setup status should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"home_status": "ready_for_owner_review"' "C2: setup status ready"
assert_contains "$C_JSON" '"explanation"' "C3: has explanation"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Unsafe profile permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Unsafe profile permission ---"
echo ""

chmod 644 "$PROFILE_FILE"

D_JSON=$(python3 "$STATUS_MODULE" home --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: unsafe profile exits non-zero ($D_RC)"
else
  fail "D1: unsafe profile should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" "blocked_profile_permission" "D2: status blocked"
assert_contains "$D_JSON" '"profile_path_printed": false' "D3: profile_path_printed false"
assert_not_contains "$D_JSON" "example.com" "D4: no zone name leaked"
assert_not_contains "$D_JSON" "DUMMY_PLACEHOLDER" "D5: no token"
assert_not_contains "$D_JSON" "~/.nanobk" "D6: no profile path"
assert_not_contains "$D_JSON" "setup-profile.json" "D7: no profile filename"

D_TEXT=$(python3 "$STATUS_MODULE" home 2>&1) || true
assert_not_contains "$D_TEXT" "~/.nanobk" "D8: no profile path in text"
assert_not_contains "$D_TEXT" "setup-profile.json" "D9: no profile filename in text"

# Clean up
rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Malformed profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Malformed profile ---"
echo ""

mkdir -p "$PROFILE_DIR"
echo "not valid json {{{" > "$PROFILE_FILE"
chmod 600 "$PROFILE_FILE"

E_JSON=$(python3 "$STATUS_MODULE" home --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: malformed profile exits non-zero ($E_RC)"
else
  fail "E1: malformed profile should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" "blocked_malformed_profile" "E2: status malformed"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. No IP
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. No IP ---"
echo ""

python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

F_JSON=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  python3 "$STATUS_MODULE" home --json 2>&1) && F_RC=0 || F_RC=$?

assert_contains "$F_JSON" "incomplete_no_ip" "F1: status incomplete_no_ip"
assert_contains "$F_JSON" "VPS" "F2: fix hints mention VPS"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Subdomain conflict
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Subdomain conflict ---"
echo ""

python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

G_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_proxy_occupied.json" \
  python3 "$STATUS_MODULE" home --json 2>&1) && G_RC=0 || G_RC=$?

assert_contains "$G_JSON" "blocked_subdomain_conflict" "G1: status conflict"
assert_contains "$G_JSON" "overwrite" "G2: mentions no overwrite"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Redaction ---"
echo ""

ALL_OUTPUTS="$A_JSON $A_TEXT $B_JSON $B_TEXT $C_JSON $D_JSON $E_JSON $F_JSON $G_JSON"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription" \
  "~/.nanobk" "setup-profile.json" "/root/" "/home/"; do
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

I_SRC=$(cat "$STATUS_MODULE")
for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"'; do
  if echo "$I_SRC" | grep -q "$method"; then
    fail "I: module contains '$method'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$method'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Help updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Help updated ---"
echo ""

J_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for pattern in "home" "setup status" "setup wizard" "setup dns" "setup profile save"; do
  if echo "$J_HELP" | grep -qi "$pattern"; then
    pass "J: help contains '$pattern'"
  else
    fail "J: help missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Console updated
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Console updated ---"
echo ""

for pattern in "Home / Setup status"; do
  if grep -q "$pattern" "$ROOT/bin/nanobk" 2>/dev/null; then
    pass "K: console contains '$pattern'"
  else
    fail "K: console missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Formatting checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Formatting checks ---"
echo ""

STATUS_LINES=$(wc -l < "$STATUS_MODULE")
SELF_LINES=$(wc -l < "$0")

if [[ "$STATUS_LINES" -ge 180 ]]; then
  pass "L1: status helper has $STATUS_LINES lines (>= 180)"
else
  fail "L1: status helper has only $STATUS_LINES lines (expected >= 180)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$SELF_LINES" -ge 220 ]]; then
  pass "L2: test script has $SELF_LINES lines (>= 220)"
else
  fail "L2: test script has only $SELF_LINES lines (expected >= 220)"
  ERRORS=$((ERRORS + 1))
fi

FIRST_LINE=$(head -1 "$0")
if [[ "$FIRST_LINE" == "#!/usr/bin/env bash" ]]; then
  pass "L3: first line is exactly shebang"
else
  fail "L3: first line is not shebang: $FIRST_LINE"
  ERRORS=$((ERRORS + 1))
fi

SECOND_LINE=$(sed -n '2p' "$0")
if [[ "$SECOND_LINE" == "set -Eeuo pipefail" ]]; then
  pass "L4: second line is exactly set -Eeuo pipefail"
else
  fail "L4: second line is not set -Eeuo pipefail: $SECOND_LINE"
  ERRORS=$((ERRORS + 1))
fi

if python3 -m py_compile "$STATUS_MODULE" 2>/dev/null; then
  pass "L5: status helper passes py_compile"
else
  fail "L5: status helper fails py_compile"
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
  echo "  All v2.2.53 Unified Setup Status / Home tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
