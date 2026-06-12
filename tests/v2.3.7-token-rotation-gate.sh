#!/usr/bin/env bash
# v2.3.7 Subscription Token Rotation Gate Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
# No real token rotation. No real Worker updates.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
HELPER="lib/nanobk_token_rotation_gate.py"
FIXTURES="tests/fixtures/v2.3.7"
COMMAND_CAPTURE="/tmp/nanobk-token-rotate-$$.jsonl"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME" "$COMMAND_CAPTURE"' EXIT

# Common setup
setup_env() {
  mkdir -p "$HOME/.nanobk"
  chmod 700 "$HOME/.nanobk"
  cp "$FIXTURES/fake_cf_env.env" "$HOME/.nanobk/cloudflare.env"
  chmod 600 "$HOME/.nanobk/cloudflare.env"
}

set_fixtures() {
  export NANOBK_TOKEN_ROTATE_FAKE_RUN=1
  export NANOBK_TOKEN_ROTATE_FAKE_RESULT="$FIXTURES/rotation_success.json"
  export NANOBK_TOKEN_ROTATE_FAKE_CAPTURE="$COMMAND_CAPTURE"
}

unset_fixtures() {
  unset NANOBK_TOKEN_ROTATE_FAKE_RUN 2>/dev/null || true
  unset NANOBK_TOKEN_ROTATE_FAKE_RESULT 2>/dev/null || true
  unset NANOBK_TOKEN_ROTATE_FAKE_CAPTURE 2>/dev/null || true
}

CONFIRM="I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"

# 1. Python compile
if python3 -m py_compile "$HELPER" 2>/dev/null; then
  ok "nanobk_token_rotation_gate.py compiles"
else
  fail "nanobk_token_rotation_gate.py compile error"
fi

# 2. nanobk setup token rotate --help
HELP_OUT=$(bash "$CLI" setup token rotate --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "token\|rotate\|轮换"; then
  ok "nanobk setup token rotate --help exists"
else
  fail "nanobk setup token rotate --help missing"
fi

# 3. nanobk token rotate --help
HELP_OUT2=$(bash "$CLI" token rotate --help 2>&1 || true)
if echo "$HELP_OUT2" | grep -qi "token\|rotate\|轮换"; then
  ok "nanobk token rotate --help exists"
else
  fail "nanobk token rotate --help missing"
fi

# 4. Plan-only mode does not rotate
setup_env
set_fixtures
rm -f "$COMMAND_CAPTURE"
PLAN_OUT=$(bash "$CLI" setup token rotate --worker-name nanobk-test-worker --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'token_rotation_plan', f'mode={d.get(\"mode\")}'
assert d.get('rotation_executed') == False, f'rotation_executed={d.get(\"rotation_executed\")}'
assert d.get('mutation') == False, f'mutation={d.get(\"mutation\")}'
" 2>/dev/null; then
  ok "Plan-only: mode=token_rotation_plan, rotation_executed=false, mutation=false"
else
  fail "Plan-only: unexpected output"
fi

# 5. Plan-only tokens masked
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sub_m = d.get('sub_token_masked','')
admin_m = d.get('admin_token_masked','')
assert sub_m and '...' in sub_m, f'sub_token_masked={sub_m}'
assert admin_m and '...' in admin_m, f'admin_token_masked={admin_m}'
# Ensure no full token leaked
s = json.dumps(d)
assert 'fake-rotate-token' not in s, 'full token leaked'
" 2>/dev/null; then
  ok "Plan-only: tokens masked, no full token"
else
  fail "Plan-only: token masking failed"
fi

# 6. Plan-only does not capture command
if [[ ! -f "$COMMAND_CAPTURE" ]] || [[ ! -s "$COMMAND_CAPTURE" ]]; then
  ok "Plan-only: no command captured"
else
  fail "Plan-only: command captured unexpectedly"
fi

# 7. --rotate without confirm: blocked
ROTATE_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --json 2>&1 || true)
if echo "$ROTATE_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('rotation_executed') == False
assert d.get('mutation') == False
assert 'confirm' in d.get('blocked_reason','').lower() or 'confirm' in d.get('hint','').lower()
" 2>/dev/null; then
  ok "--rotate without confirm: blocked"
else
  fail "--rotate without confirm: not blocked"
fi

# 8. Wrong confirm: blocked
WRONG_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --confirm "wrong phrase" --json 2>&1 || true)
if echo "$WRONG_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('rotation_executed') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "Wrong confirm: blocked"
else
  fail "Wrong confirm: not blocked"
fi

# 9. Missing worker-name in rotate mode: blocked
NO_WORKER=$(bash "$CLI" setup token rotate --rotate --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$NO_WORKER" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
" 2>/dev/null; then
  ok "Missing worker-name: blocked"
else
  fail "Missing worker-name: not blocked"
fi

# 10. Production worker name nanok: blocked
PROD_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanok --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$PROD_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert '生产' in d.get('blocked_reason','') or 'production' in d.get('blocked_reason','').lower() or 'nanok' in d.get('blocked_reason','')
" 2>/dev/null; then
  ok "Production worker nanok: blocked"
else
  fail "Production worker nanok: not blocked"
fi

# 11. Production domain marker: blocked
mkdir -p "$HOME/.nanobk"
cat > "$HOME/.nanobk/cloudflare.env" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ROUTE_URL="https://nanok.biankai314.uk"
EOF
chmod 600 "$HOME/.nanobk/cloudflare.env"
PROD_DOM=$(bash "$CLI" setup token rotate --rotate --worker-name test-worker --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$PROD_DOM" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
" 2>/dev/null; then
  ok "Production domain nanok.biankai314.uk: blocked"
else
  fail "Production domain: not blocked"
fi

# Restore env
setup_env
set_fixtures

# 12. Correct confirm + fake worker update success: rotated
rm -f "$COMMAND_CAPTURE"
ROTATED_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$ROTATED_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'rotated', f'mode={d.get(\"mode\")}'
assert d.get('rotation_executed') == True, f'rotation_executed={d.get(\"rotation_executed\")}'
assert d.get('mutation') == True, f'mutation={d.get(\"mutation\")}'
assert d.get('worker_name') == 'nanobk-test-worker'
assert d.get('worker_updated') == True
assert d.get('raw_tokens_printed') == False
assert d.get('raw_worker_script_printed') == False
" 2>/dev/null; then
  ok "Correct confirm + fake update: rotated"
else
  fail "Correct confirm + fake update: unexpected"
fi

# 13. Fake capture exists
if [[ -f "$COMMAND_CAPTURE" ]] && [[ -s "$COMMAND_CAPTURE" ]]; then
  ok "Command capture file created"
else
  fail "Command capture file not created"
fi

# 14. Fake capture details
if [[ -f "$COMMAND_CAPTURE" ]]; then
  CAPTURE_CHECK=$(python3 -c "
import json, sys
with open('$COMMAND_CAPTURE') as f:
    lines = [l.strip() for l in f if l.strip()]
assert len(lines) >= 1, 'no captures'
c = json.loads(lines[0])
assert c.get('worker_name') == 'nanobk-test-worker', f'worker_name={c.get(\"worker_name\")}'
assert c.get('token_kind') == 'both', f'token_kind={c.get(\"token_kind\")}'
assert c.get('raw_tokens_printed') == False
assert c.get('raw_worker_script_printed') == False
assert c.get('contains_production_worker') == False
print('OK')
" 2>&1 || true)
  if echo "$CAPTURE_CHECK" | grep -q "OK"; then
    ok "Capture: worker_name, token_kind, no raw tokens, no production worker"
  else
    fail "Capture: unexpected details"
  fi
fi

# 15. token-kind sub only
rm -f "$COMMAND_CAPTURE"
SUB_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --token-kind sub --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$SUB_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('token_kind') == 'sub', f'token_kind={d.get(\"token_kind\")}'
" 2>/dev/null; then
  ok "token-kind sub only works"
else
  fail "token-kind sub only failed"
fi

# 16. token-kind admin only
rm -f "$COMMAND_CAPTURE"
ADMIN_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --token-kind admin --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$ADMIN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('token_kind') == 'admin', f'token_kind={d.get(\"token_kind\")}'
" 2>/dev/null; then
  ok "token-kind admin only works"
else
  fail "token-kind admin only failed"
fi

# 17. Fake update error
rm -f "$COMMAND_CAPTURE"
export NANOBK_TOKEN_ROTATE_FAKE_RESULT="$FIXTURES/rotation_error.json"
ERR_OUT=$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$ERR_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'failed', f'mode={d.get(\"mode\")}'
assert d.get('rotation_executed') == True, f'rotation_executed={d.get(\"rotation_executed\")}'
assert d.get('mutation') == False, f'mutation={d.get(\"mutation\")}'
assert d.get('error'), 'missing error'
" 2>/dev/null; then
  ok "Fake update error: ok=false, mode=failed, rotation_executed=true"
else
  fail "Fake update error: unexpected"
fi

# Restore fixtures
set_fixtures

# 18. No secret leaks
LEAK_OUT=""
LEAK_OUT+="$(bash "$CLI" setup token rotate --worker-name nanobk-test-worker --json 2>&1 || true)"
LEAK_OUT+="$(bash "$CLI" setup token rotate --rotate --worker-name nanobk-test-worker --confirm "$CONFIRM" --json 2>&1 || true)"
LEAK_OK=1
# Check for actual secret leaks (not safety field names like raw_tokens_printed: false)
for leak in "fake-rotate-token-237" "CF_API_TOKEN=" "api.cloudflare.com/client/v4"; do
  if echo "$LEAK_OUT" | grep -qi "$leak"; then
    fail "Output leaks: $leak"
    LEAK_OK=0
  fi
done
# Check that no full token value appears (not masked)
if echo "$LEAK_OUT" | python3 -c "
import json,sys,re
text = sys.stdin.read()
# Check no unmasked token-like strings (43+ char alphanumeric)
tokens = re.findall(r'[A-Za-z0-9_-]{43,}', text)
# Filter out known safe patterns (confirmation phrases, field values)
safe = {'IUNDERSTANDNANOBKWILLROTATESUBSCRIPTIONTOKENS'}
for t in tokens:
  if t not in safe and '...' not in t:
    print(f'LEAK: {t[:10]}...', file=sys.stderr)
    sys.exit(1)
# Also verify raw_tokens_printed is false
for line in text.splitlines():
  if 'raw_tokens_printed' in line or 'raw_worker_script_printed' in line:
    if 'true' in line.lower():
      print(f'SAFETY VIOLATION: {line.strip()}', file=sys.stderr)
      sys.exit(1)
" 2>/dev/null; then
  true
else
  fail "Output contains unmasked token or safety violation"
  LEAK_OK=0
fi
if [[ "$LEAK_OK" == "1" ]]; then
  ok "No secret leaks in token rotation output"
fi

# 19. No dangerous patterns in helper
DANGEROUS_FOUND=$(grep -nE "systemctl.*(reload|restart)|nginx.*-s.*reload|service.*reload|owner.smoke.create|acme\.sh|certbot|DELETE.*dns|PATCH.*dns" "$HELPER" 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*"""' | grep -v 'No ' || true)
if [[ -z "$DANGEROUS_FOUND" ]]; then
  ok "No dangerous patterns in helper"
else
  fail "Helper contains dangerous patterns: $DANGEROUS_FOUND"
fi

# 20. No mutation without --rotate + exact confirm
NOROTATE=$(bash "$CLI" setup token rotate --worker-name nanobk-test-worker --json 2>&1 || true)
if echo "$NOROTATE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('rotation_executed') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "No mutation without --rotate + exact confirm"
else
  fail "Mutation without proper flags"
fi

# 21. TTY menu has token rotation entry
unset_fixtures
MENU_OUT=$(printf '1\n6\n8\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -80 || true)
if echo "$MENU_OUT" | grep -qi "Token 轮换\|token.*rotate"; then
  ok "TTY setup menu has token rotation entry"
else
  fail "TTY setup menu missing token rotation entry"
fi

# 22. v2.3.6 tests still pass
V236_OUT=$(bash tests/v2.3.6-cert-issue-gate.sh 2>&1 || true)
if echo "$V236_OUT" | grep -q "All v2.3.6 certificate issue gate checks passed"; then
  ok "v2.3.6 cert issue gate test still passes"
else
  fail "v2.3.6 cert issue gate test failed"
  echo "$V236_OUT" | tail -5
fi

# 23. v2.3.5 tests still pass
V235_OUT=$(bash tests/v2.3.5-cert-automation-preflight.sh 2>&1 || true)
if echo "$V235_OUT" | grep -q "All v2.3.5 certificate preflight checks passed"; then
  ok "v2.3.5 cert preflight test still passes"
else
  fail "v2.3.5 cert preflight test failed"
  echo "$V235_OUT" | tail -5
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.7 token rotation gate checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
