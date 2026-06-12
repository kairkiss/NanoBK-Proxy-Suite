#!/usr/bin/env bash
# v2.3.6 Certificate Issue Gate Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
# No real certificate requests. No real service changes.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
HELPER="lib/nanobk_cert_issue_gate.py"
PREFLIGHT="lib/nanobk_cert_preflight.py"
FIXTURES="tests/fixtures/v2.3.6"
COMMAND_CAPTURE="/tmp/nanobk-cert-issue-cmd-$$.jsonl"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME" "$COMMAND_CAPTURE"' EXIT

# Common setup
setup_env() {
  mkdir -p "$HOME/.nanobk"
  cat > "$HOME/.nanobk/setup-profile.json" <<'EOF'
{"version":1,"zone_name":"example.com","api_env_path":"/tmp/fake-cf-env-236","nodes":["proxy","web"]}
EOF
  chmod 600 "$HOME/.nanobk/setup-profile.json"
  cat > /tmp/fake-cf-env-236 <<'EOF'
CF_API_TOKEN="fake-issue-token-236"
EOF
  chmod 600 /tmp/fake-cf-env-236
}

set_fixtures() {
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
  export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_both_owned.json"
  export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
  export NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
  export NANOBK_CERT_ISSUE_FAKE_RUN=1
  export NANOBK_CERT_ISSUE_FAKE_RESULT="$FIXTURES/issue_success.json"
  export NANOBK_CERT_ISSUE_FAKE_CAPTURE_COMMAND="$COMMAND_CAPTURE"
}

unset_fixtures() {
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_TOOLS 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_PORTS 2>/dev/null || true
  unset NANOBK_CERT_ISSUE_FAKE_RUN 2>/dev/null || true
  unset NANOBK_CERT_ISSUE_FAKE_RESULT 2>/dev/null || true
  unset NANOBK_CERT_ISSUE_FAKE_CAPTURE_COMMAND 2>/dev/null || true
}

CONFIRM="I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"

# 1. Python compile
if python3 -m py_compile "$HELPER" 2>/dev/null; then
  ok "nanobk_cert_issue_gate.py compiles"
else
  fail "nanobk_cert_issue_gate.py compile error"
fi

# 2. nanobk setup cert issue --help
HELP_OUT=$(bash "$CLI" setup cert issue --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "cert\|证书\|issue\|签发"; then
  ok "nanobk setup cert issue --help exists"
else
  fail "nanobk setup cert issue --help missing"
fi

# 3. nanobk cert issue --help
HELP_OUT2=$(bash "$CLI" cert issue --help 2>&1 || true)
if echo "$HELP_OUT2" | grep -qi "cert\|证书\|issue\|签发"; then
  ok "nanobk cert issue --help exists"
else
  fail "nanobk cert issue --help missing"
fi

# 4. Plan-only mode does not issue
setup_env
set_fixtures
rm -f "$COMMAND_CAPTURE"
PLAN_OUT=$(bash "$CLI" setup cert issue --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'cert_issue_plan', f'mode={d.get(\"mode\")}'
assert d.get('issue_executed') == False, f'issue_executed={d.get(\"issue_executed\")}'
assert d.get('mutation') == False, f'mutation={d.get(\"mutation\")}'
" 2>/dev/null; then
  ok "Plan-only: mode=cert_issue_plan, issue_executed=false, mutation=false"
else
  fail "Plan-only: unexpected output"
fi

# 5. Plan-only ready_to_issue=true when preflight ready
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ready_to_issue') == True, f'ready_to_issue={d.get(\"ready_to_issue\")}'
" 2>/dev/null; then
  ok "Plan-only: ready_to_issue=true when preflight ready"
else
  fail "Plan-only: ready_to_issue not true"
fi

# 6. Plan-only does not capture command
if [[ ! -f "$COMMAND_CAPTURE" ]] || [[ ! -s "$COMMAND_CAPTURE" ]]; then
  ok "Plan-only: no command captured"
else
  fail "Plan-only: command captured unexpectedly"
fi

# 7. --issue without confirm: blocked
ISSUE_OUT=$(bash "$CLI" setup cert issue --issue --json 2>&1 || true)
if echo "$ISSUE_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('issue_executed') == False
assert d.get('mutation') == False
assert 'confirm' in d.get('blocked_reason','').lower() or 'confirm' in d.get('hint','').lower()
" 2>/dev/null; then
  ok "--issue without confirm: blocked"
else
  fail "--issue without confirm: not blocked"
fi

# 8. Wrong confirm: blocked
WRONG_OUT=$(bash "$CLI" setup cert issue --issue --confirm "wrong phrase" --json 2>&1 || true)
if echo "$WRONG_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('issue_executed') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "Wrong confirm: blocked"
else
  fail "Wrong confirm: not blocked"
fi

# 9. Correct confirm + fake issue success: issued
rm -f "$COMMAND_CAPTURE"
ISSUED_OUT=$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$ISSUED_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'issued', f'mode={d.get(\"mode\")}'
assert d.get('issue_executed') == True, f'issue_executed={d.get(\"issue_executed\")}'
assert d.get('mutation') == True, f'mutation={d.get(\"mutation\")}'
assert 'example.com' in str(d.get('domains', []))
assert d.get('tool') == 'acme.sh'
assert d.get('method') == 'dns-01-cloudflare'
assert d.get('service_reloaded') == False
assert d.get('config_modified') == False
assert d.get('private_key_printed') == False
" 2>/dev/null; then
  ok "Correct confirm + fake issue: issued"
else
  fail "Correct confirm + fake issue: unexpected"
fi

# 10. Fake command capture exists
if [[ -f "$COMMAND_CAPTURE" ]] && [[ -s "$COMMAND_CAPTURE" ]]; then
  ok "Command capture file created"
else
  fail "Command capture file not created"
fi

# 11. Command capture details
if [[ -f "$COMMAND_CAPTURE" ]]; then
  CAPTURE_CHECK=$(python3 -c "
import json, sys
with open('$COMMAND_CAPTURE') as f:
    lines = [l.strip() for l in f if l.strip()]
assert len(lines) >= 1, 'no captures'
c = json.loads(lines[0])
assert c.get('tool') == 'acme.sh', f'tool={c.get(\"tool\")}'
assert c.get('method') == 'dns-01-cloudflare', f'method={c.get(\"method\")}'
domains = c.get('domains', [])
assert any('proxy' in d for d in domains), f'no proxy in {domains}'
assert any('web' in d for d in domains), f'no web in {domains}'
assert c.get('contains_reload') == False, 'contains_reload'
assert c.get('contains_installcert') == False, 'contains_installcert'
print('OK')
" 2>&1 || true)
  if echo "$CAPTURE_CHECK" | grep -q "OK"; then
    ok "Command capture: tool=acme.sh, method=dns-01-cloudflare, no reload/installcert"
  else
    fail "Command capture: unexpected details"
  fi
fi

# 12. DNS missing: blocked
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_proxy_missing.json"
unset NANOBK_CERT_ISSUE_FAKE_RUN
unset NANOBK_CERT_ISSUE_FAKE_RESULT
DNS_MISS=$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$DNS_MISS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'blocked', f'mode={d.get(\"mode\")}'
assert d.get('issue_executed') == False
" 2>/dev/null; then
  ok "DNS missing: blocked, issue_executed=false"
else
  fail "DNS missing: not blocked"
fi

# 13. Unowned DNS: blocked
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_unowned.json"
UNOWNED=$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$UNOWNED" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'blocked', f'mode={d.get(\"mode\")}'
" 2>/dev/null; then
  ok "Unowned DNS: blocked"
else
  fail "Unowned DNS: not blocked"
fi

# 14. acme.sh missing: blocked
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":false,"certbot":false}'
NO_ACME=$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$NO_ACME" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'blocked', f'mode={d.get(\"mode\")}'
assert 'acme' in d.get('blocked_reason','').lower() or '未安装' in d.get('blocked_reason','')
" 2>/dev/null; then
  ok "acme.sh missing: blocked"
else
  fail "acme.sh missing: not blocked"
fi

# 15. recommended_method blocked/manual: blocked
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_proxy_missing.json"
# First check plan-only shows blocked method
BLOCKED_METHOD=$(bash "$CLI" setup cert issue --json 2>&1 || true)
if echo "$BLOCKED_METHOD" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('method') == 'blocked', f'method={d.get(\"method\")}'
assert d.get('ready_to_issue') == False
" 2>/dev/null; then
  ok "DNS missing: method=blocked, ready_to_issue=false"
else
  fail "DNS missing: method not blocked"
fi

# 16. Fake issue error
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_ISSUE_FAKE_RUN=1
export NANOBK_CERT_ISSUE_FAKE_RESULT="$FIXTURES/issue_error.json"
export NANOBK_CERT_ISSUE_FAKE_CAPTURE_COMMAND="$COMMAND_CAPTURE"
rm -f "$COMMAND_CAPTURE"
ERR_OUT=$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$ERR_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'failed', f'mode={d.get(\"mode\")}'
assert d.get('issue_executed') == True, f'issue_executed={d.get(\"issue_executed\")}'
assert d.get('mutation') == False, f'mutation={d.get(\"mutation\")}'
assert d.get('error'), 'missing error'
" 2>/dev/null; then
  ok "Fake issue error: ok=false, mode=failed, issue_executed=true"
else
  fail "Fake issue error: unexpected"
fi

# 17. No secret leaks
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_ISSUE_FAKE_RUN=1
export NANOBK_CERT_ISSUE_FAKE_RESULT="$FIXTURES/issue_success.json"
LEAK_OUT=""
LEAK_OUT+="$(bash "$CLI" setup cert issue --json 2>&1 || true)"
LEAK_OUT+="$(bash "$CLI" setup cert issue --issue --confirm "$CONFIRM" --json 2>&1 || true)"
LEAK_OK=1
for leak in "fake-issue-token-236" "fake-zone-id-aaaabbbbcccc" "api.cloudflare.com/client/v4" "/dns_records" "PRIVATE KEY" "SUB_TOKEN=" "ADMIN_TOKEN=" "subscription" "raw"; do
  if echo "$LEAK_OUT" | grep -qi "$leak"; then
    fail "Output leaks: $leak"
    LEAK_OK=0
  fi
done
if [[ "$LEAK_OK" == "1" ]]; then
  ok "No secret leaks in cert issue output"
fi

# 18. No dangerous commands in issue helper — only check subprocess/exec lines
DANGEROUS_FOUND=$(grep -nE "subprocess\.(run|call|Popen|check_call).*systemctl|subprocess\.(run|call|Popen|check_call).*reload|subprocess\.(run|call|Popen|check_call).*restart|subprocess\.(run|call|Popen|check_call).*install.cert|subprocess\.(run|call|Popen|check_call).*reloadcmd|os\.system.*reload|os\.system.*restart" "$HELPER" 2>/dev/null || true)
if [[ -z "$DANGEROUS_FOUND" ]]; then
  ok "No dangerous commands in issue helper"
else
  fail "Issue helper contains dangerous commands: $DANGEROUS_FOUND"
fi

# 19. No Cloudflare POST/PATCH/PUT/DELETE in issue helper
DANGEROUS_METHODS=$(grep -nE 'method="(POST|PATCH|PUT|DELETE)"' "$HELPER" 2>/dev/null || true)
if [[ -z "$DANGEROUS_METHODS" ]]; then
  ok "No POST/PATCH/PUT/DELETE in issue helper"
else
  fail "Issue helper contains POST/PATCH/PUT/DELETE"
fi

# 20. No owner-smoke-create
if grep -q "owner-smoke-create" "$HELPER" 2>/dev/null; then
  fail "Issue helper references owner-smoke-create"
else
  ok "No owner-smoke-create in issue helper"
fi

# 21. TTY menu has cert issue entry
unset_fixtures
MENU_OUT=$(printf '1\n5\n7\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -80 || true)
if echo "$MENU_OUT" | grep -q "证书签发"; then
  ok "TTY setup menu has cert issue entry"
else
  fail "TTY setup menu missing cert issue entry"
fi

# 22. Run v2.3.5 test to verify fix
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
  echo "All v2.3.6 certificate issue gate checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
