#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — v2.2 Closeout Regression Test
#
# Final regression covering CLI, setup profile, wizard, DNS, home/status,
# Web /api/home, Bot /home, renderer/adapters, redaction, and no-mutation.
#
# Usage:
#   bash tests/v2.2.55-closeout-regression.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

echo ""
echo "=== v2.2 Closeout Regression ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. CLI command surface
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. CLI command surface ---"
echo ""

A_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for cmd in "home" "setup status" "setup wizard" "setup dns" "setup profile save" "setup profile show" "setup profile clear"; do
  if echo "$A_HELP" | grep -qi "$cmd"; then
    pass "A: help contains '$cmd'"
  else
    fail "A: help missing '$cmd'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Setup profile lifecycle
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Setup profile lifecycle ---"
echo ""

# Save
B_SAVE=$(python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web --json 2>&1) && B_RC=0 || B_RC=$?
if [[ "$B_RC" == "0" ]]; then
  pass "B1: save exits 0"
else
  fail "B1: save should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

# File mode
if [[ -f "$PROFILE_FILE" ]]; then
  B_MODE=$(stat -f '%Lp' "$PROFILE_FILE" 2>/dev/null || stat -c '%a' "$PROFILE_FILE" 2>/dev/null)
  if [[ "$B_MODE" == "600" ]]; then
    pass "B2: profile mode 0600"
  else
    fail "B2: profile mode should be 600, got $B_MODE"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Show
B_SHOW=$(python3 "$ROOT/lib/nanobk_setup_profile.py" show --json 2>&1)
assert_contains "$B_SHOW" '"ok": true' "B3: show ok true"
assert_contains "$B_SHOW" "example.com" "B4: show zone"
assert_not_contains "$B_SHOW" "$FIXTURES" "B5: no fixture path in show"
assert_not_contains "$B_SHOW" "DUMMY_PLACEHOLDER" "B6: no token in show"

# Clear
python3 "$ROOT/lib/nanobk_setup_profile.py" clear > /dev/null 2>&1
if [[ ! -f "$PROFILE_FILE" ]]; then
  pass "B7: profile cleared"
else
  fail "B7: profile should be cleared"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Setup wizard non-interactive
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Setup wizard ---"
echo ""

rm -f "$PROFILE_FILE" 2>/dev/null || true

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" setup wizard --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web --yes --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: wizard exits 0"
else
  fail "C1: wizard should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" '"ok": true' "C2: wizard ok true"
assert_contains "$C_JSON" "ready_for_owner_review" "C3: wizard ready"
assert_contains "$C_JSON" '"saved": true' "C4: profile saved"
assert_contains "$C_JSON" '"dns_changed": false' "C5: dns_changed false"
assert_contains "$C_JSON" '"records_created": false' "C6: records_created false"
assert_contains "$C_JSON" '"production_apply_enabled": false' "C7: production false"
assert_contains "$C_JSON" '"explanation"' "C8: explanation exists"
assert_not_contains "$C_JSON" "$FIXTURES" "C9: no fixture path"
assert_not_contains "$C_JSON" "DUMMY_PLACEHOLDER" "C10: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Setup DNS with saved profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Setup DNS with profile ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" setup dns --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: setup dns exits 0"
else
  fail "D1: setup dns should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" "ready_for_owner_review" "D2: setup_status ready"
assert_contains "$D_JSON" '"explanation"' "D3: explanation exists"
assert_contains "$D_JSON" '"next_actions"' "D4: next_actions exists"
assert_not_contains "$D_JSON" "$FIXTURES" "D5: no fixture path"
assert_not_contains "$D_JSON" "DUMMY_PLACEHOLDER" "D6: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Home / setup status
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Home / setup status ---"
echo ""

E_HOME=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" home --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "0" ]]; then
  pass "E1: home exits 0"
else
  fail "E1: home should exit 0, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_HOME" "ready_for_owner_review" "E2: home_status ready"
assert_contains "$E_HOME" '"configured"' "E3: profile configured"
assert_contains "$E_HOME" '"explanation"' "E4: explanation exists"
assert_contains "$E_HOME" '"next_actions"' "E5: next_actions exists"
assert_contains "$E_HOME" '"read_only": true' "E6: read_only true"
assert_contains "$E_HOME" '"dns_changed": false' "E7: dns_changed false"
assert_contains "$E_HOME" '"production_apply_enabled": false' "E8: production false"
assert_not_contains "$E_HOME" "$FIXTURES" "E9: no fixture path"
assert_not_contains "$E_HOME" "DUMMY_PLACEHOLDER" "E10: no token"

E_STATUS=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json" \
  "$ROOT/bin/nanobk" setup status --json 2>&1) && E_RC2=0 || E_RC2=$?

if [[ "$E_RC2" == "0" ]]; then
  pass "E11: setup status exits 0"
else
  fail "E11: setup status should exit 0, got $E_RC2"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_STATUS" "ready_for_owner_review" "E12: setup status ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Web route static contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Web route contract ---"
echo ""

WEB_FILE="$ROOT/web/app.py"

if grep -q '@app.route("/api/home")' "$WEB_FILE"; then
  pass "F1: web has /api/home route"
else
  fail "F1: web missing /api/home route"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'require_login' "$WEB_FILE"; then
  pass "F2: web has require_login"
else
  fail "F2: web missing require_login"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'run_nanobk.*home' "$WEB_FILE"; then
  pass "F3: web calls run_nanobk home"
else
  fail "F3: web missing run_nanobk home"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'redact_json' "$WEB_FILE"; then
  pass "F4: web uses redact_json"
else
  fail "F4: web missing redact_json"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Bot command static contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Bot command contract ---"
echo ""

BOT_FILE="$ROOT/bot/nanobk_bot.py"

if grep -q 'cmd_home' "$BOT_FILE"; then
  pass "G1: bot has cmd_home"
else
  fail "G1: bot missing cmd_home"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'is_owner.*update' "$BOT_FILE"; then
  pass "G2: bot uses is_owner gate"
else
  fail "G2: bot missing is_owner gate"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'get_home_text' "$BOT_FILE"; then
  pass "G3: bot uses get_home_text"
else
  fail "G3: bot missing get_home_text"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'CommandHandler.*"home".*cmd_home' "$BOT_FILE"; then
  pass "G4: bot registers /home"
else
  fail "G4: bot missing /home registration"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'CommandHandler.*"setup_status".*cmd_home' "$BOT_FILE"; then
  pass "G5: bot registers /setup_status"
else
  fail "G5: bot missing /setup_status registration"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'help_home' "$BOT_FILE"; then
  pass "G6: bot help includes /home"
else
  fail "G6: bot help missing /home"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Renderer/adapter contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Renderer/adapter contract ---"
echo ""

for module in "$ROOT/lib/nanobk_home_render.py" "$ROOT/lib/nanobk_web_home_adapter.py" "$ROOT/lib/nanobk_bot_home_adapter.py"; do
  name=$(basename "$module")
  if grep -q 'requires_auth' "$module"; then
    pass "H: $name has requires_auth"
  else
    fail "H: $name missing requires_auth"
    ERRORS=$((ERRORS + 1))
  fi
  if grep -q 'read_only' "$module"; then
    pass "H: $name has read_only"
  else
    fail "H: $name missing read_only"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Global redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Global redaction scan ---"
echo ""

# Collect all outputs from this test run
ALL="$A_HELP $B_SAVE $B_SHOW $C_JSON $D_JSON $E_HOME $E_STATUS"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription" \
  "~/.nanobk" "setup-profile.json" "/root/" "/home/"; do
  if echo "$ALL" | grep -qi "$forbidden"; then
    fail "I: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Global mutation guard (new CLI/home/Web/Bot bridge files only)
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Mutation guard ---"
echo ""

for module in "$ROOT/lib/nanobk_home_render.py" "$ROOT/lib/nanobk_web_home_adapter.py" "$ROOT/lib/nanobk_bot_home_adapter.py" "$ROOT/lib/nanobk_setup_status.py"; do
  name=$(basename "$module")
  for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"'; do
    if grep -q "$method" "$module" 2>/dev/null; then
      fail "J: $name contains '$method'"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

# Check Web route doesn't have mutation methods
if grep -q 'method="POST"\|method="PATCH"\|method="PUT"\|method="DELETE"' "$ROOT/lib/nanobk_web_home_adapter.py" 2>/dev/null; then
  fail "J: web adapter has mutation methods"
  ERRORS=$((ERRORS + 1))
else
  pass "J: web adapter no mutation methods"
fi

# Check Bot adapter doesn't have mutation methods
if grep -q 'method="POST"\|method="PATCH"\|method="PUT"\|method="DELETE"' "$ROOT/lib/nanobk_bot_home_adapter.py" 2>/dev/null; then
  fail "J: bot adapter has mutation methods"
  ERRORS=$((ERRORS + 1))
else
  pass "J: bot adapter no mutation methods"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Cleanup
# ══════════════════════════════════════════════════════════════════════════════

rm -f "$PROFILE_FILE" 2>/dev/null || true

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.55 Closeout Regression tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
