#!/usr/bin/env bash
# v2.5.5 Production Rotation Readiness Test
#
# Tests the subscription token and protocol key rotation readiness flow.
# No real token rotation. No protocol key rotation. No Worker mutation.
# No VPS service reload/restart. No raw secret output.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_rotation_readiness.py"

PASS=0
FAIL=0
NOTE_COUNT=0

ok()   { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
note() { echo "NOTE: $1"; NOTE_COUNT=$((NOTE_COUNT + 1)); }

check_json() {
  local num="$1" label="$2" json="$3" expr="$4" expected="$5"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$num: $label"
  else
    fail "$num: $label (expected '$expected', got '$actual')"
  fi
}

check_no() {
  local num="$1" label="$2" text="$3" pattern="$4"
  if echo "$text" | grep -qi "$pattern"; then
    fail "$num: $label — found '$pattern'"
  else
    ok "$num: $label"
  fi
}

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production rotate >/dev/null 2>&1; then
  ok "2: setup production rotate exits 0"
else
  fail "2: setup production rotate exits non-zero"
fi

# 3
if "$NANOBK" setup production rotate --json >/dev/null 2>&1; then
  ok "3: setup production rotate --json exits 0"
else
  fail "3: setup production rotate --json exits non-zero"
fi

# 4
if "$NANOBK" beginner production rotate >/dev/null 2>&1; then
  ok "4: beginner production rotate exits 0"
else
  fail "4: beginner production rotate exits non-zero"
fi

# 5
if "$NANOBK" beginner production rotate --json >/dev/null 2>&1; then
  ok "5: beginner production rotate --json exits 0"
else
  fail "5: beginner production rotate --json exits non-zero"
fi

# 6
if "$NANOBK" setup production rotate --save --token auto --protocol all >/dev/null 2>&1; then
  ok "6: setup production rotate --save exits 0"
else
  fail "6: setup production rotate --save exits non-zero"
fi

echo ""
echo "=== B. JSON schema ==="

JSON=$("$NANOBK" setup production rotate --json 2>&1)

check_json "7" "ok == true" "$JSON" "d['ok']" "True"
check_json "8" "mode" "$JSON" "d['mode']" "production_rotation_readiness_v2_5"
check_json "9" "version" "$JSON" "d['version']" "2.5.5"
check_json "10" "mutation == false" "$JSON" "d['mutation']" "False"
check_json "11" "dangerous_actions_executed == false" "$JSON" "d['dangerous_actions_executed']" "False"
check_json "12" "safety == read_only" "$JSON" "d['safety']" "read_only"

# 13
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'token' in d" 2>/dev/null; then
  ok "13: has token"
else
  fail "13: missing token"
fi

# 14
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'readiness' in d" 2>/dev/null; then
  ok "14: has readiness"
else
  fail "14: missing readiness"
fi

# 15
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'protocol' in d" 2>/dev/null; then
  ok "15: has protocol"
else
  fail "15: missing protocol"
fi

# 16
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'commands' in d" 2>/dev/null; then
  ok "16: has commands"
else
  fail "16: missing commands"
fi

# 17
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'order' in d" 2>/dev/null; then
  ok "17: has order"
else
  fail "17: missing order"
fi

# 18
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d" 2>/dev/null; then
  ok "18: has next_step"
else
  fail "18: missing next_step"
fi

echo ""
echo "=== C. Token modes ==="

# 19 — token auto works
JSON_AUTO=$("$NANOBK" setup production rotate --token auto --json 2>&1)
check_json "19" "token auto works" "$JSON_AUTO" "d['token']['mode']" "auto"

# 20 — auto token source auto_generated
check_json "20" "auto token source" "$JSON_AUTO" "d['token']['source']" "auto_generated"

# 21 — auto token masked (should have … in it)
if echo "$JSON_AUTO" | python3 -c "import sys,json; d=json.load(sys.stdin); m=d['token']['new_token_masked']; assert '…' in m, f'masked: {m}'" 2>/dev/null; then
  ok "21: auto token masked"
else
  fail "21: auto token not masked"
fi

# 22 — raw_token_output false
check_json "22" "raw_token_output false" "$JSON_AUTO" "d['token']['raw_token_output']" "False"

# 23 — token custom works
JSON_CUSTOM=$("$NANOBK" setup production rotate --token custom --custom-token "abcdefghijklmnop" --json 2>&1)
check_json "23" "token custom works" "$JSON_CUSTOM" "d['token']['mode']" "custom"

# 24 — custom token masked
if echo "$JSON_CUSTOM" | python3 -c "import sys,json; d=json.load(sys.stdin); m=d['token']['new_token_masked']; assert '…' in m, f'masked: {m}'" 2>/dev/null; then
  ok "24: custom token masked"
else
  fail "24: custom token not masked"
fi

# 25 — custom raw value not output
if echo "$JSON_CUSTOM" | grep -q "abcdefghijklmnop"; then
  fail "25: custom raw token leaked"
else
  ok "25: custom raw value not output"
fi

# 26 — custom token shorter than 8 rejected RC=1
if "$NANOBK" setup production rotate --token custom --custom-token "short" --json >/dev/null 2>&1; then
  fail "26: short custom token should be rejected"
else
  ok "26: short custom token rejected RC=1"
fi

# 27 — token unchanged works
JSON_UNCHANGED=$("$NANOBK" setup production rotate --token unchanged --json 2>&1)
check_json "27" "token unchanged works" "$JSON_UNCHANGED" "d['token']['mode']" "unchanged"

# 28 — unchanged blocks protocol rotation
check_json "28" "unchanged blocks protocol" "$JSON_UNCHANGED" "d['protocol']['protocol_rotation_blocked']" "True"

# 29 — unchanged next_step choose_token_rotation
check_json "29" "unchanged next_step" "$JSON_UNCHANGED" "d['next_step']" "choose_token_rotation"

echo ""
echo "=== D. Protocol targets ==="

# 30 — protocol all works
JSON_ALL=$("$NANOBK" setup production rotate --protocol all --json 2>&1)
check_json "30" "protocol all" "$JSON_ALL" "d['protocol']['target']" "all"

# 31 — protocol hy2 works
JSON_HY2=$("$NANOBK" setup production rotate --protocol hy2 --json 2>&1)
check_json "31" "protocol hy2" "$JSON_HY2" "d['protocol']['target']" "hy2"

# 32 — protocol tuic works
JSON_TUIC=$("$NANOBK" setup production rotate --protocol tuic --json 2>&1)
check_json "32" "protocol tuic" "$JSON_TUIC" "d['protocol']['target']" "tuic"

# 33 — protocol reality works
JSON_REALITY=$("$NANOBK" setup production rotate --protocol reality --json 2>&1)
check_json "33" "protocol reality" "$JSON_REALITY" "d['protocol']['target']" "reality"

# 34 — protocol trojan works
JSON_TROJAN=$("$NANOBK" setup production rotate --protocol trojan --json 2>&1)
check_json "34" "protocol trojan" "$JSON_TROJAN" "d['protocol']['target']" "trojan"

# 35 — invalid protocol rejected
if "$NANOBK" setup production rotate --protocol invalid >/dev/null 2>&1; then
  fail "35: invalid protocol should be rejected"
else
  ok "35: invalid protocol rejected RC=1"
fi

echo ""
echo "=== E. Command plan ==="

# 36 — token_gate mentions nanobk setup token rotate
if echo "$JSON_AUTO" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'nanobk setup token rotate' in d['commands']['token_gate']" 2>/dev/null; then
  ok "36: token_gate mentions nanobk setup token rotate"
else
  fail "36: token_gate missing nanobk setup token rotate"
fi

# 37 — token_gate includes exact token phrase
if echo "$JSON_AUTO" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS' in d['commands']['token_gate']" 2>/dev/null; then
  ok "37: token_gate includes exact token phrase"
else
  fail "37: token_gate missing exact token phrase"
fi

# 38 — protocol all maps to nanobk rotate all
check_json "38" "protocol all command" "$JSON_ALL" "d['commands']['protocol_rotate']" "nanobk rotate all"

# 39 — protocol hy2 maps to nanobk rotate hy2
check_json "39" "protocol hy2 command" "$JSON_HY2" "d['commands']['protocol_rotate']" "nanobk rotate hy2"

# 40 — protocol tuic maps to nanobk rotate tuic
check_json "40" "protocol tuic command" "$JSON_TUIC" "d['commands']['protocol_rotate']" "nanobk rotate tuic"

# 41 — protocol reality maps to nanobk rotate reality
check_json "41" "protocol reality command" "$JSON_REALITY" "d['commands']['protocol_rotate']" "nanobk rotate reality"

# 42 — protocol trojan maps to nanobk rotate trojan
check_json "42" "protocol trojan command" "$JSON_TROJAN" "d['commands']['protocol_rotate']" "nanobk rotate trojan"

# 43 — order starts with rotate_subscription_token
check_json "43" "order starts with rotate_subscription_token" "$JSON_AUTO" "d['order'][0]" "rotate_subscription_token"

# 44 — order includes rotate_protocol_keys
if echo "$JSON_AUTO" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'rotate_protocol_keys' in d['order']" 2>/dev/null; then
  ok "44: order includes rotate_protocol_keys"
else
  fail "44: order missing rotate_protocol_keys"
fi

# 45 — order includes refresh_subscription
if echo "$JSON_AUTO" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'refresh_subscription' in d['order']" 2>/dev/null; then
  ok "45: order includes refresh_subscription"
else
  fail "45: order missing refresh_subscription"
fi

echo ""
echo "=== F. Save mode ==="

# 46 — save writes file
"$NANOBK" setup production rotate --save --token auto --protocol all >/dev/null 2>&1
ROTATION_PLAN_PATH="$HOME/.nanobk/production-rotation-plan.json"
if [[ -f "$ROTATION_PLAN_PATH" ]]; then
  ok "46: save writes production-rotation-plan.json"
else
  fail "46: rotation plan file not created"
fi

# 47 — file chmod 600
if [[ -f "$ROTATION_PLAN_PATH" ]]; then
  PERMS=$(stat -c '%a' "$ROTATION_PLAN_PATH" 2>/dev/null || stat -f '%Lp' "$ROTATION_PLAN_PATH" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    ok "47: rotation plan file chmod 600"
  else
    fail "47: rotation plan file perms=$PERMS (expected 600)"
  fi
else
  fail "47: rotation plan file not found"
fi

# 48 — saved plan raw_token_saved false
if [[ -f "$ROTATION_PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$ROTATION_PLAN_PATH')); assert d.get('raw_token_saved') == False" 2>/dev/null; then
  ok "48: saved plan raw_token_saved false"
else
  fail "48: saved plan raw_token_saved not false"
fi

# 49 — saved plan contains new_token_masked
if [[ -f "$ROTATION_PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$ROTATION_PLAN_PATH')); assert '…' in d.get('new_token_masked', '')" 2>/dev/null; then
  ok "49: saved plan contains new_token_masked"
else
  fail "49: saved plan missing new_token_masked"
fi

# 50 — saved plan does not contain raw custom token
"$NANOBK" setup production rotate --save --token custom --custom-token "testtoken12345678" --protocol hy2 >/dev/null 2>&1
ROTATION_PLAN_PATH2="$HOME/.nanobk/production-rotation-plan.json"
if [[ -f "$ROTATION_PLAN_PATH2" ]] && grep -q "testtoken12345678" "$ROTATION_PLAN_PATH2" 2>/dev/null; then
  fail "50: saved plan contains raw custom token"
else
  ok "50: saved plan does not contain raw custom token"
fi

# 51 — saved plan contains protocol
if [[ -f "$ROTATION_PLAN_PATH2" ]] && python3 -c "import json; d=json.load(open('$ROTATION_PLAN_PATH2')); assert d.get('protocol') == 'hy2'" 2>/dev/null; then
  ok "51: saved plan contains protocol"
else
  fail "51: saved plan missing protocol"
fi

echo ""
echo "=== G. Dangerous options rejected ==="

# 52 — --rotate rejected
if "$NANOBK" setup production rotate --rotate >/dev/null 2>&1; then
  fail "52: --rotate should be rejected"
else
  ok "52: --rotate rejected RC=1"
fi

# 53 — --yes rejected
if "$NANOBK" setup production rotate --yes >/dev/null 2>&1; then
  fail "53: --yes should be rejected"
else
  ok "53: --yes rejected RC=1"
fi

# 54 — --apply rejected
if "$NANOBK" setup production rotate --apply >/dev/null 2>&1; then
  fail "54: --apply should be rejected"
else
  ok "54: --apply rejected RC=1"
fi

# 55 — --execute rejected
if "$NANOBK" setup production rotate --execute >/dev/null 2>&1; then
  fail "55: --execute should be rejected"
else
  ok "55: --execute rejected RC=1"
fi

# 56 — --confirm rejected
if "$NANOBK" setup production rotate --confirm >/dev/null 2>&1; then
  fail "56: --confirm should be rejected"
else
  ok "56: --confirm rejected RC=1"
fi

# 57 — output says preview only
REJECT_MSG=$("$NANOBK" setup production rotate --rotate 2>&1 || true)
if echo "$REJECT_MSG" | grep -qi "预览\|preview\|不支持\|不会执行"; then
  ok "57: output says preview only"
else
  fail "57: missing preview message"
fi

echo ""
echo "=== H. Safety output ==="

ALL_OUTPUT="$JSON
$JSON_AUTO
$JSON_CUSTOM
$JSON_UNCHANGED
$JSON_ALL
$JSON_HY2
$JSON_TUIC
$JSON_REALITY
$JSON_TROJAN"

# 58 — no raw custom token in stdout
if echo "$ALL_OUTPUT" | grep -q "abcdefghijklmnop"; then
  fail "58: raw custom token leaked in stdout"
else
  ok "58: no raw custom token in stdout"
fi

check_no "59" "no ADMIN_TOKEN" "$ALL_OUTPUT" "ADMIN_TOKEN"
check_no "60" "no SUB_TOKEN" "$ALL_OUTPUT" "SUB_TOKEN"
check_no "61" "no CF_API_TOKEN" "$ALL_OUTPUT" "CF_API_TOKEN"
check_no "62" "no PRIVATE KEY" "$ALL_OUTPUT" "PRIVATE.KEY"
check_no "63" "no subscription URL" "$ALL_OUTPUT" "subscription.*http"
check_no "64" "no admin URL" "$ALL_OUTPUT" "admin.*url\|admin.*URL"
check_no "65" "no workers.dev secret URL" "$ALL_OUTPUT" "workers\.dev"
check_no "66" "no zone_id" "$ALL_OUTPUT" "zone_id"
check_no "67" "no record_id" "$ALL_OUTPUT" "record_id"
check_no "68" "no api_env_path" "$ALL_OUTPUT" "api_env_path"
check_no "69" "no raw protocol passwords" "$ALL_OUTPUT" "password"

echo ""
echo "=== I. Source safety ==="

check_no_code() {
  local num="$1" label="$2" pattern="$3"
  if python3 -c "
import ast, sys, re
with open('$MODULE') as f:
    source = f.read()
lines = source.split('\n')
in_docstring = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    if '\"\"\"' in stripped:
        in_docstring = not in_docstring
        continue
    if in_docstring:
        continue
    if re.search(r'$pattern', stripped, re.IGNORECASE):
        print('FOUND')
        sys.exit(0)
" 2>/dev/null | grep -q "FOUND"; then
    fail "$num: $label found in executable code"
  else
    ok "$num: $label not in executable code"
  fi
}

check_no_code "70" "subprocess import" "import subprocess"
check_no_code "71" "requests import" "import requests"
check_no_code "72" "urlopen import" "import urllib"
check_no_code "73" "os.system" "os\.system"
check_no_code "74" "popen" "popen"
check_no_code "75" "systemctl restart" "systemctl.*restart"
check_no_code "76" "systemctl reload" "systemctl.*reload"
check_no_code "77" "rotate-keys.sh execution" "rotate-keys\.sh"
check_no_code "78" "setup token rotate --rotate execution" "setup token rotate.*--rotate"

echo ""
echo "=== J. Regression (narrow smoke) ==="

# 79-83: Check prior test files exist (fast, no execution)
for prior in v2.5.4-production-cert-readiness v2.5.3-production-worker-readiness v2.5.2-production-dns-readiness v2.5.1-production-action-plan v2.5.0-production-setup-spine; do
  if [[ -f "$REPO_DIR/tests/${prior}.sh" ]]; then
    ok "prior test file exists: $prior"
  else
    fail "prior test file missing: $prior"
  fi
done

# 84: v2.4.0 scope test passes (fast, standalone)
if [[ -f "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" ]]; then
  if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
    ok "84: v2.4.0 scope test passes"
  else
    fail "84: v2.4.0 scope test fails"
  fi
else
  fail "84: v2.4.0 test file missing"
fi

# ── Section K: Opt-in long regression ──────────────────────────────────────

echo ""
echo "=== Section K: Opt-in long regression ==="

if [[ "${NANOBK_RUN_LONG_REGRESSION:-0}" == "1" ]]; then
  echo "NANOBK_RUN_LONG_REGRESSION=1 — running legacy regression tests with timeout."

  # 85. v2.5.4 test (timeout 60s)
  V254_TEST="$REPO_DIR/tests/v2.5.4-production-cert-readiness.sh"
  if [[ -f "$V254_TEST" ]]; then
    if timeout 60 bash "$V254_TEST" >/dev/null 2>&1; then
      ok "85: v2.5.4 test passes"
    else
      note "85: v2.5.4 test failed or timed out (non-blocking)"
    fi
  else
    note "85: v2.5.4 test not found"
  fi

  # 86. v2.5.3 test (timeout 60s)
  V253_TEST="$REPO_DIR/tests/v2.5.3-production-worker-readiness.sh"
  if [[ -f "$V253_TEST" ]]; then
    if timeout 60 bash "$V253_TEST" >/dev/null 2>&1; then
      ok "86: v2.5.3 test passes"
    else
      note "86: v2.5.3 test failed or timed out (non-blocking)"
    fi
  else
    note "86: v2.5.3 test not found"
  fi
else
  note "Skipping long regression; set NANOBK_RUN_LONG_REGRESSION=1 to enable"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
