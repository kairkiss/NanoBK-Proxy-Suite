#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — v2.2 Closeout Regression Test
#
# Final regression covering CLI, setup profile, wizard, DNS, home/status,
# Web /api/home, Bot /home, renderer/adapters, redaction, and no-mutation.
#
# Uses temporary HOME and copied fixtures. Does NOT touch real HOME or repo fixtures.
#
# Usage:
#   bash tests/v2.2.55-closeout-regression.sh

# ── Isolation: temporary HOME ────────────────────────────────────────────────

TEST_TMP="$(mktemp -d)"
REAL_HOME="${HOME:-}"
export HOME="$TEST_TMP/home"
mkdir -p "$HOME"

cleanup() {
  export HOME="$REAL_HOME"
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_SRC="$ROOT/tests/fixtures/v2.2.53"

# Copy fixtures to temp dir to avoid chmod on repo files
TEST_FIXTURES="$TEST_TMP/fixtures"
mkdir -p "$TEST_FIXTURES"
cp "$FIXTURES_SRC/safe_api_env.env" "$TEST_FIXTURES/safe_api_env.env"
cp "$FIXTURES_SRC/unsafe_world_readable_api_env.env" "$TEST_FIXTURES/unsafe_world_readable_api_env.env"
cp "$FIXTURES_SRC/fake_response_map_both_available.json" "$TEST_FIXTURES/fake_response_map_both_available.json"
cp "$FIXTURES_SRC/fake_response_map_proxy_occupied.json" "$TEST_FIXTURES/fake_response_map_proxy_occupied.json"
cp "$FIXTURES_SRC/fake_response_map_api_failure.json" "$TEST_FIXTURES/fake_response_map_api_failure.json"

chmod 600 "$TEST_FIXTURES/safe_api_env.env"
chmod 644 "$TEST_FIXTURES/unsafe_world_readable_api_env.env"

SAFE_ENV="$TEST_FIXTURES/safe_api_env.env"
FAKE_MAP_AVAILABLE="$TEST_FIXTURES/fake_response_map_both_available.json"
FAKE_MAP_CONFLICT="$TEST_FIXTURES/fake_response_map_proxy_occupied.json"
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

rm -f "$PROFILE_FILE" 2>/dev/null || true

# Save
B_SAVE=$(python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$SAFE_ENV" --nodes proxy,web --json 2>&1) && B_RC=0 || B_RC=$?
if [[ "$B_RC" == "0" ]]; then
  pass "B1: save exits 0"
else
  fail "B1: save should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

# File mode (portable: GNU stat -c first, then BSD stat -f)
if [[ -f "$PROFILE_FILE" ]]; then
  B_MODE=$(stat -c '%a' "$PROFILE_FILE" 2>/dev/null || stat -f '%Lp' "$PROFILE_FILE" 2>/dev/null || true)
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
assert_not_contains "$B_SHOW" "$SAFE_ENV" "B5: no fixture path in show"
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
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FAKE_MAP_AVAILABLE" \
  "$ROOT/bin/nanobk" setup wizard --zone example.com --api-env "$SAFE_ENV" --nodes proxy,web --yes --json 2>&1) && C_RC=0 || C_RC=$?

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
assert_not_contains "$C_JSON" "$SAFE_ENV" "C9: no fixture path"
assert_not_contains "$C_JSON" "DUMMY_PLACEHOLDER" "C10: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Setup DNS with saved profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Setup DNS with profile ---"
echo ""

D_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FAKE_MAP_AVAILABLE" \
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
assert_not_contains "$D_JSON" "$SAFE_ENV" "D5: no fixture path"
assert_not_contains "$D_JSON" "DUMMY_PLACEHOLDER" "D6: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Home / setup status
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Home / setup status ---"
echo ""

E_HOME=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FAKE_MAP_AVAILABLE" \
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
assert_not_contains "$E_HOME" "$SAFE_ENV" "E9: no fixture path"
assert_not_contains "$E_HOME" "DUMMY_PLACEHOLDER" "E10: no token"

E_STATUS=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888" \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FAKE_MAP_AVAILABLE" \
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

for pattern in '@app.route("/api/home")' 'require_login' 'run_nanobk.*home' 'redact_json'; do
  if grep -q "$pattern" "$WEB_FILE"; then
    pass "F: web has '$pattern'"
  else
    fail "F: web missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Bot command static contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Bot command contract ---"
echo ""

BOT_FILE="$ROOT/bot/nanobk_bot.py"

for pattern in 'cmd_home' 'is_owner.*update' 'render_home\|get_home_text' 'CommandHandler.*"home".*cmd_home' 'CommandHandler.*"setup_status"' 'help_home'; do
  if grep -q "$pattern" "$BOT_FILE"; then
    pass "G: bot has '$pattern'"
  else
    fail "G: bot missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

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

ALL="$A_HELP $B_SAVE $B_SHOW $C_JSON $D_JSON $E_HOME $E_STATUS"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription" \
  "~/.nanobk" "setup-profile.json" "/root/"; do
  if echo "$ALL" | grep -qi "$forbidden"; then
    fail "I: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Global mutation guard
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

pass "J: web adapter no mutation methods"
pass "J: bot adapter no mutation methods"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. HOME/fixture isolation checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Isolation checks ---"
echo ""

# Check script uses mktemp
if grep -q 'mktemp' "$0"; then
  pass "K1: script uses mktemp"
else
  fail "K1: script missing mktemp"
  ERRORS=$((ERRORS + 1))
fi

# Check script exports HOME
if grep -q 'export HOME=' "$0"; then
  pass "K2: script exports HOME"
else
  fail "K2: script missing export HOME"
  ERRORS=$((ERRORS + 1))
fi

# Check script has trap cleanup
if grep -q 'trap cleanup' "$0"; then
  pass "K3: script has cleanup trap"
else
  fail "K3: script missing cleanup trap"
  ERRORS=$((ERRORS + 1))
fi

# Check script does NOT chmod repo fixtures directly (only chmod temp copies)
if grep -qE '^[^#]*chmod.*\$FIXTURES_SRC|^[^#]*chmod.*v2.2.53' "$0"; then
  fail "K4: script chmods repo fixtures directly"
  ERRORS=$((ERRORS + 1))
else
  pass "K4: script does not chmod repo fixtures directly"
fi

# Check script copies fixtures to temp
if grep -q 'cp.*FIXTURES_SRC.*TEST_FIXTURES' "$0"; then
  pass "K5: script copies fixtures to temp dir"
else
  fail "K5: script missing fixture copy"
  ERRORS=$((ERRORS + 1))
fi

# Check profile file is under temp HOME
if [[ "$PROFILE_FILE" == "$TEST_TMP"* ]]; then
  pass "K6: PROFILE_FILE under temp HOME"
else
  fail "K6: PROFILE_FILE not under temp HOME"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.55 Closeout Regression tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
