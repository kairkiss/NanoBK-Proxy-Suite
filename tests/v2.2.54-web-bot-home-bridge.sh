#!/usr/bin/env bash
set -Eeuo pipefail

# NanoBK Proxy Suite — Web/Bot Home Bridge Test
#
# Tests the read-only Web/Bot home bridge.
# Uses env var mocks. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.54-web-bot-home-bridge.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_MODULE="$ROOT/lib/nanobk_home_render.py"
WEB_ADAPTER="$ROOT/lib/nanobk_web_home_adapter.py"
BOT_ADAPTER="$ROOT/lib/nanobk_bot_home_adapter.py"
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

echo ""
echo "=== Web/Bot Home Bridge Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Renderer no profile
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Renderer no profile ---"
echo ""

rm -f "$PROFILE_FILE" 2>/dev/null || true

A_HOME=$(NANOBK_TEST_DETECT_IPV4_FAIL=1 NANOBK_TEST_DETECT_IPV6_FAIL=1   python3 -c "
import sys, os, json
sys.path.insert(0, os.path.join('$ROOT', 'lib'))
from nanobk_setup_status import run_home
print(json.dumps(run_home()))
" 2>&1)

A_TEXT=$(echo "$A_HOME" | python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
home = json.load(sys.stdin)
from nanobk_home_render import render_home_text
print(render_home_text(home, target='cli'))
" 2>&1)

assert_contains "$A_TEXT" "NanoBK Home" "A1: text has title"
assert_contains "$A_TEXT" "not_configured" "A2: text not configured"
assert_contains "$A_TEXT" "nanobk setup wizard" "A3: text next action"
assert_not_contains "$A_TEXT" "~/.nanobk" "A4: no profile path"
assert_not_contains "$A_TEXT" "setup-profile.json" "A5: no profile filename"
assert_not_contains "$A_TEXT" "DUMMY_PLACEHOLDER" "A6: no token"

A_BOT=$(echo "$A_HOME" | python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
home = json.load(sys.stdin)
from nanobk_home_render import render_home_text
print(render_home_text(home, target='bot'))
" 2>&1)

assert_contains "$A_BOT" "NanoBK Home" "A7: bot has title"
assert_contains "$A_BOT" "nanobk setup wizard" "A8: bot next action"
assert_not_contains "$A_BOT" "~/.nanobk" "A9: bot no profile path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Renderer ready
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Renderer ready ---"
echo ""

python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" --nodes proxy,web > /dev/null 2>&1

B_HOME=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888"   NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json"   python3 -c "
import sys, os, json
sys.path.insert(0, os.path.join('$ROOT', 'lib'))
from nanobk_setup_status import run_home
print(json.dumps(run_home()))
" 2>&1)

B_TEXT=$(echo "$B_HOME" | python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
home = json.load(sys.stdin)
from nanobk_home_render import render_home_text
print(render_home_text(home, target='cli'))
" 2>&1)

assert_contains "$B_TEXT" "ready_for_owner_review" "B1: text status"
assert_contains "$B_TEXT" "example.com" "B2: text zone"
assert_contains "$B_TEXT" "<redacted>" "B3: text api-env redacted"
assert_contains "$B_TEXT" "Next actions:" "B4: text has next actions"
assert_not_contains "$B_TEXT" "DUMMY_PLACEHOLDER" "B5: no token"

B_CARD=$(echo "$B_HOME" | python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
home = json.load(sys.stdin)
from nanobk_home_render import render_home_card
print(json.dumps(render_home_card(home)))
" 2>&1)

assert_contains "$B_CARD" '"requires_auth": true' "B6: card requires_auth"
assert_not_contains "$B_CARD" "DUMMY_PLACEHOLDER" "B7: card no token"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Web adapter JSON
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Web adapter JSON ---"
echo ""

python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

C_JSON=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888"   NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json"   python3 -c "
import sys, os, json
sys.path.insert(0, os.path.join('$ROOT', 'lib'))
from nanobk_web_home_adapter import get_home_json
print(json.dumps(get_home_json()))
" 2>&1)

assert_contains "$C_JSON" '"ok": true' "C1: web ok true"
assert_contains "$C_JSON" '"read_only": true' "C2: web read_only"
assert_contains "$C_JSON" '"dns_changed": false' "C3: web dns_changed false"
assert_contains "$C_JSON" '"production_apply_enabled": false' "C4: web production false"
assert_contains "$C_JSON" '"requires_auth": true' "C5: web requires_auth"
assert_contains "$C_JSON" '"api_env_path_printed": false' "C6: web api_env_path_printed"
assert_contains "$C_JSON" '"profile_path_printed": false' "C7: web profile_path_printed"
assert_not_contains "$C_JSON" "DUMMY_PLACEHOLDER" "C8: web no token"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Bot adapter text
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Bot adapter text ---"
echo ""

python3 "$ROOT/lib/nanobk_setup_profile.py" save --zone example.com --api-env "$FIXTURES/safe_api_env.env" > /dev/null 2>&1

D_TEXT=$(NANOBK_TEST_DETECTED_IPV4="8.8.8.8" NANOBK_TEST_DETECTED_IPV6="2001:4860:4860::8888"   NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/fake_response_map_both_available.json"   python3 -c "
import sys, os
sys.path.insert(0, os.path.join('$ROOT', 'lib'))
from nanobk_bot_home_adapter import get_home_text
print(get_home_text())
" 2>&1)

assert_contains "$D_TEXT" "NanoBK Home" "D1: bot text title"
assert_contains "$D_TEXT" "ready_for_owner_review" "D2: bot text status"
assert_contains "$D_TEXT" "example.com" "D3: bot text zone"
assert_contains "$D_TEXT" "nanobk setup dns" "D4: bot text next action"
assert_not_contains "$D_TEXT" "DUMMY_PLACEHOLDER" "D5: bot no token"
assert_not_contains "$D_TEXT" "~/.nanobk" "D6: bot no profile path"
assert_not_contains "$D_TEXT" "setup-profile.json" "D7: bot no profile filename"

rm -f "$PROFILE_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Auth guard contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Auth guard contract ---"
echo ""

E_WEB=$(NANOBK_TEST_DETECT_IPV4_FAIL=1 NANOBK_TEST_DETECT_IPV6_FAIL=1   python3 -c "
import sys, os, json
sys.path.insert(0, os.path.join('$ROOT', 'lib'))
from nanobk_web_home_adapter import get_home_json
print(json.dumps(get_home_json()))
" 2>&1)

assert_contains "$E_WEB" '"requires_auth": true' "E1: web JSON requires_auth"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Redaction ---"
echo ""

ALL_OUTPUTS="$A_TEXT $A_BOT $B_TEXT $B_CARD $C_JSON $D_TEXT $E_WEB"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN"   "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer "   "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://"   "hysteria2://" "tuic://" "PRIVATE KEY" "subscription"   "~/.nanobk" "setup-profile.json" "/root/" "/home/"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "F: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "F: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Mutation guard
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# G1. Web real route exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G1. Web real route ---"
echo ""

WEB_FILE="$ROOT/web/app.py"

if grep -q '/api/home' "$WEB_FILE"; then
  pass "G1-1: web has /api/home route"
else
  fail "G1-1: web missing /api/home route"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'require_login' "$WEB_FILE"; then
  pass "G1-2: web /api/home has require_login"
else
  fail "G1-2: web /api/home missing require_login"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'run_nanobk.*home' "$WEB_FILE"; then
  pass "G1-3: web /api/home calls run_nanobk home"
else
  fail "G1-3: web /api/home missing run_nanobk home call"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'redact_json' "$WEB_FILE"; then
  pass "G1-4: web /api/home uses redact_json"
else
  fail "G1-4: web /api/home missing redact_json"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G2. Bot real command exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G2. Bot real command ---"
echo ""

BOT_FILE="$ROOT/bot/nanobk_bot.py"

if grep -q 'cmd_home' "$BOT_FILE"; then
  pass "G2-1: bot has cmd_home handler"
else
  fail "G2-1: bot missing cmd_home handler"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'CommandHandler.*"home".*cmd_home' "$BOT_FILE"; then
  pass "G2-2: bot registers CommandHandler home"
else
  fail "G2-2: bot missing CommandHandler home registration"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'CommandHandler.*"setup_status".*cmd_home' "$BOT_FILE"; then
  pass "G2-3: bot registers CommandHandler setup_status"
else
  fail "G2-3: bot missing CommandHandler setup_status registration"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'is_owner.*update' "$BOT_FILE"; then
  pass "G2-4: bot cmd_home uses is_owner gate"
else
  fail "G2-4: bot cmd_home missing is_owner gate"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'get_home_text' "$BOT_FILE"; then
  pass "G2-5: bot cmd_home uses get_home_text adapter"
else
  fail "G2-5: bot cmd_home missing get_home_text adapter"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'help_home' "$BOT_FILE"; then
  pass "G2-6: bot help includes /home"
else
  fail "G2-6: bot help missing /home"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Mutation guard ---
echo ""

for module in "$RENDER_MODULE" "$WEB_ADAPTER" "$BOT_ADAPTER"; do
  for method in 'method="POST"' 'method="PATCH"' 'method="PUT"' 'method="DELETE"'; do
    if grep -q "$method" "$module" 2>/dev/null; then
      fail "G: $(basename "$module") contains '$method'"
      ERRORS=$((ERRORS + 1))
    else
      pass "G: $(basename "$module") no '$method'"
    fi
  done
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Help/console stability
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Help/console stability ---"
echo ""

H_HELP=$("$ROOT/bin/nanobk" --help 2>&1)

for pattern in "home" "setup status" "setup wizard" "setup dns" "setup profile save"; do
  if echo "$H_HELP" | grep -qi "$pattern"; then
    pass "H: help contains '$pattern'"
  else
    fail "H: help missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Formatting checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Formatting checks ---"
echo ""

RENDER_LINES=$(wc -l < "$RENDER_MODULE")
WEB_LINES=$(wc -l < "$WEB_ADAPTER")
BOT_LINES=$(wc -l < "$BOT_ADAPTER")
SELF_LINES=$(wc -l < "$0")

if [[ "$RENDER_LINES" -ge 120 ]]; then
  pass "I1: render helper has $RENDER_LINES lines (>= 120)"
else
  fail "I1: render helper has only $RENDER_LINES lines (expected >= 120)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$WEB_LINES" -ge 80 ]]; then
  pass "I2: web adapter has $WEB_LINES lines (>= 80)"
else
  fail "I2: web adapter has only $WEB_LINES lines (expected >= 80)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$BOT_LINES" -ge 80 ]]; then
  pass "I3: bot adapter has $BOT_LINES lines (>= 80)"
else
  fail "I3: bot adapter has only $BOT_LINES lines (expected >= 80)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$SELF_LINES" -ge 220 ]]; then
  pass "I4: test script has $SELF_LINES lines (>= 220)"
else
  fail "I4: test script has only $SELF_LINES lines (expected >= 220)"
  ERRORS=$((ERRORS + 1))
fi

FIRST_LINE=$(head -1 "$0")
if [[ "$FIRST_LINE" == "#!/usr/bin/env bash" ]]; then
  pass "I5: first line is exactly shebang"
else
  fail "I5: first line is not shebang: $FIRST_LINE"
  ERRORS=$((ERRORS + 1))
fi

SECOND_LINE=$(sed -n '2p' "$0")
if [[ "$SECOND_LINE" == "set -Eeuo pipefail" ]]; then
  pass "I6: second line is exactly set -Eeuo pipefail"
else
  fail "I6: second line is not set -Eeuo pipefail: $SECOND_LINE"
  ERRORS=$((ERRORS + 1))
fi

for module in "$RENDER_MODULE" "$WEB_ADAPTER" "$BOT_ADAPTER"; do
  if python3 -m py_compile "$module" 2>/dev/null; then
    pass "I7: $(basename "$module") passes py_compile"
  else
    fail "I7: $(basename "$module") fails py_compile"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

rm -f "$PROFILE_FILE" 2>/dev/null || true

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "  All v2.2.54 Web/Bot Home Bridge tests passed!"
  exit 0
else
  echo "  ${ERRORS} test(s) failed."
  exit 1
fi
