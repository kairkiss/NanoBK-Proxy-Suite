#!/usr/bin/env bash
# v2.3.8 Full CLI Setup Flow Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
# No real DNS creation. No real certificate request. No real token rotation.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
HELPER="lib/nanobk_setup_flow.py"
FIXTURES="tests/fixtures/v2.3.8"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Common setup
setup_env() {
  mkdir -p "$HOME/.nanobk"
  chmod 700 "$HOME/.nanobk"
  cp "$FIXTURES/fake_cf_env.env" "$HOME/.nanobk/cloudflare.env"
  chmod 600 "$HOME/.nanobk/cloudflare.env"
  cat > "$HOME/.nanobk/setup-profile.json" <<PROFEOF
{
  "zone_name": "example.com",
  "api_env_path": "$HOME/.nanobk/cloudflare.env",
  "nodes": ["proxy", "web"]
}
PROFEOF
  chmod 600 "$HOME/.nanobk/setup-profile.json"
}

set_fixtures() {
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
  export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_both_owned.json"
  export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
  export NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
  export NANOBK_TOKEN_ROTATE_FAKE_RUN=1
  export NANOBK_TOKEN_ROTATE_FAKE_RESULT="$FIXTURES/rotation_success.json"
  export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
  export NANOBK_TEST_DETECTED_IPV6=""
  export NANOBK_TEST_DETECT_IPV4_FAIL=0
  export NANOBK_TEST_DETECT_IPV6_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
}

unset_fixtures() {
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_TOOLS 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_PORTS 2>/dev/null || true
  unset NANOBK_TOKEN_ROTATE_FAKE_RUN 2>/dev/null || true
  unset NANOBK_TOKEN_ROTATE_FAKE_RESULT 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV4 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV6 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL 2>/dev/null || true
}

# 1. Python compile
if python3 -m py_compile "$HELPER" 2>/dev/null; then
  ok "nanobk_setup_flow.py compiles"
else
  fail "nanobk_setup_flow.py compile error"
fi

# 2. nanobk setup flow --help
HELP_OUT=$(bash "$CLI" setup flow --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "flow\|setup\|设置"; then
  ok "nanobk setup flow --help exists"
else
  fail "nanobk setup flow --help missing"
fi

# 3. nanobk setup run --help
HELP_OUT2=$(bash "$CLI" setup run --help 2>&1 || true)
if echo "$HELP_OUT2" | grep -qi "flow\|setup\|设置"; then
  ok "nanobk setup run --help exists"
else
  fail "nanobk setup run --help missing"
fi

# 4. No profile/env: flow does not crash, outputs cf_connect next step
rm -rf "$HOME/.nanobk"
NOPROF_OUT=$(bash "$CLI" setup flow --json 2>&1 || true)
if echo "$NOPROF_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
steps = d.get('steps', [])
cf_step = next((s for s in steps if s['id'] == 'cf_connect'), None)
assert cf_step is not None, 'missing cf_connect step'
assert cf_step['status'] == 'missing_input', f'cf_connect status={cf_step[\"status\"]}'
" 2>/dev/null; then
  ok "No profile: flow runs, cf_connect=missing_input"
else
  fail "No profile: flow crashed or unexpected"
fi

# 4b. No profile: no dangerous placeholder commands with (未指定)
if echo "$NOPROF_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
for s in steps:
    cmd = s.get('command') or ''
    assert '(未指定)' not in cmd, f'step {s[\"id\"]} has placeholder: {cmd}'
    if s['id'] in ('dns_apply_execute', 'cert_issue_execute'):
        assert s['status'] != 'manual_confirm_required' or s.get('command'), \
            f'step {s[\"id\"]} is manual_confirm but has no command'
        assert '--zone' not in cmd or '(未指定)' not in cmd, \
            f'step {s[\"id\"]} has dangerous placeholder: {cmd}'
" 2>/dev/null; then
  ok "No profile: no dangerous placeholder commands"
else
  fail "No profile: contains dangerous placeholder commands"
fi

# 4c. No profile: dns_apply_execute and cert_issue_execute are missing_input
if echo "$NOPROF_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
dns_exec = next((s for s in steps if s['id'] == 'dns_apply_execute'), None)
cert_exec = next((s for s in steps if s['id'] == 'cert_issue_execute'), None)
assert dns_exec is not None, 'missing dns_apply_execute'
assert cert_exec is not None, 'missing cert_issue_execute'
assert dns_exec['status'] == 'missing_input', f'dns_apply_execute status={dns_exec[\"status\"]}'
assert cert_exec['status'] == 'missing_input', f'cert_issue_execute status={cert_exec[\"status\"]}'
" 2>/dev/null; then
  ok "No profile: dangerous steps are missing_input"
else
  fail "No profile: dangerous steps not properly gated"
fi

# 5. With fake profile/env: can identify zone
setup_env
set_fixtures
FLOW_OUT=$(bash "$CLI" setup flow --json 2>&1 || true)
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
steps = d.get('steps', [])
cf_step = next((s for s in steps if s['id'] == 'cf_connect'), None)
assert cf_step is not None, 'missing cf_connect step'
assert 'example.com' in cf_step.get('detail',''), f'detail={cf_step.get(\"detail\",\"\")}'
" 2>/dev/null; then
  ok "With profile: identifies zone example.com"
else
  fail "With profile: zone not identified"
fi

# 6. Domain planner step can run
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
dp = next((s for s in steps if s['id'] == 'domain_plan'), None)
assert dp is not None, 'missing domain_plan step'
assert dp['status'] in ('ready','partial'), f'domain_plan status={dp[\"status\"]}'
" 2>/dev/null; then
  ok "Domain planner step ran successfully"
else
  fail "Domain planner step failed"
fi

# 7. DNS apply step is plan-only, mutation=false
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mutation') == False, f'mutation={d.get(\"mutation\")}'
steps = d.get('steps', [])
dns_plan = next((s for s in steps if s['id'] == 'dns_apply_plan'), None)
assert dns_plan is not None, 'missing dns_apply_plan step'
assert dns_plan['status'] in ('ready','blocked'), f'dns_apply_plan status={dns_plan[\"status\"]}'
" 2>/dev/null; then
  ok "DNS apply step: plan-only, mutation=false"
else
  fail "DNS apply step: unexpected"
fi

# 8. Cert preflight step is read-only
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
cp = next((s for s in steps if s['id'] == 'cert_preflight'), None)
assert cp is not None, 'missing cert_preflight step'
assert cp['status'] in ('ready','blocked'), f'cert_preflight status={cp[\"status\"]}'
" 2>/dev/null; then
  ok "Cert preflight step: read-only"
else
  fail "Cert preflight step: unexpected"
fi

# 9. Cert issue step is plan-only
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
ci = next((s for s in steps if s['id'] == 'cert_issue_execute'), None)
assert ci is not None, 'missing cert_issue_execute step'
assert ci['status'] == 'manual_confirm_required', f'cert_issue status={ci[\"status\"]}'
" 2>/dev/null; then
  ok "Cert issue step: manual_confirm_required"
else
  fail "Cert issue step: unexpected"
fi

# 10. Token rotation step is plan-only
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
tr = next((s for s in steps if s['id'] == 'token_rotation_plan'), None)
assert tr is not None, 'missing token_rotation_plan step'
assert tr['status'] in ('ready','blocked','missing_input'), f'token_rotation status={tr[\"status\"]}'
" 2>/dev/null; then
  ok "Token rotation step: plan-only"
else
  fail "Token rotation step: unexpected"
fi

# 11. Flow JSON: mutation=false, dangerous_actions_executed=false, setup_complete=false
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mutation') == False
assert d.get('dangerous_actions_executed') == False
assert d.get('setup_complete') == False
" 2>/dev/null; then
  ok "Flow JSON: mutation=false, dangerous_actions=false, setup_complete=false"
else
  fail "Flow JSON: unexpected safety fields"
fi

# 12. Flow output contains manual_confirm_required steps
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
manual = [s for s in steps if s.get('status') == 'manual_confirm_required']
assert len(manual) >= 2, f'expected >=2 manual steps, got {len(manual)}'
" 2>/dev/null; then
  ok "Flow contains manual_confirm_required steps"
else
  fail "Flow missing manual_confirm_required steps"
fi

# 13. Flow output contains DNS apply exact command but does not execute
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
dns_exec = next((s for s in steps if s['id'] == 'dns_apply_execute'), None)
assert dns_exec is not None, 'missing dns_apply_execute'
cmd = dns_exec.get('command','')
assert '--apply' in cmd, f'command missing --apply: {cmd}'
assert 'CONFIRM' in cmd.upper() or 'confirm' in cmd.lower(), f'command missing confirm: {cmd}'
" 2>/dev/null; then
  ok "DNS apply command shown but not executed"
else
  fail "DNS apply command missing or wrong"
fi

# 14. Flow output contains cert issue exact command
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
ci = next((s for s in steps if s['id'] == 'cert_issue_execute'), None)
assert ci is not None
cmd = ci.get('command','')
assert '--issue' in cmd, f'command missing --issue: {cmd}'
" 2>/dev/null; then
  ok "Cert issue command shown but not executed"
else
  fail "Cert issue command missing or wrong"
fi

# 15. Flow output contains token rotate command
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
steps = d.get('steps', [])
tr = next((s for s in steps if s['id'] == 'token_rotation_plan'), None)
assert tr is not None
cmd = tr.get('command') or ''
# May be None if production blocked, that's OK
" 2>/dev/null; then
  ok "Token rotation step present in flow"
else
  fail "Token rotation step missing"
fi

# 16. Production worker plan-only warning: nanok ready_to_rotate=false
PROD_PLAN=$(bash "$CLI" setup token rotate --worker-name nanok --json 2>&1 || true)
if echo "$PROD_PLAN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('ready_to_rotate') == False, f'ready_to_rotate={d.get(\"ready_to_rotate\")}'
nc = d.get('next_command') or ''
assert '--rotate' not in nc, f'next_command should not contain --rotate: {nc}'
" 2>/dev/null; then
  ok "Production worker nanok plan-only: ready_to_rotate=false, no rotate command"
else
  fail "Production worker nanok plan-only: unexpected"
fi

# 17. No secret leaks
LEAK_OUT=""
LEAK_OUT+="$(bash "$CLI" setup flow --json 2>&1 || true)"
LEAK_OUT+="$(bash "$CLI" setup token rotate --worker-name nanobk-test-worker --json 2>&1 || true)"
LEAK_OK=1
for leak in "fake-rotate-token-237" "CF_API_TOKEN=" "api.cloudflare.com/client/v4" "fake-zone-id"; do
  if echo "$LEAK_OUT" | grep -qi "$leak"; then
    fail "Output leaks: $leak"
    LEAK_OK=0
  fi
done
if echo "$LEAK_OUT" | python3 -c "
import json,sys,re
text = sys.stdin.read()
tokens = re.findall(r'[A-Za-z0-9_-]{43,}', text)
safe = {'IUNDERSTANDNANOBKWILLROTATESUBSCRIPTIONTOKENS'}
for t in tokens:
  if t not in safe and '...' not in t:
    print(f'LEAK: {t[:10]}...', file=sys.stderr)
    sys.exit(1)
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
  ok "No secret leaks in flow output"
fi

# 18. No dangerous patterns in helper
DANGEROUS_FOUND=$(grep -nE "systemctl.*(reload|restart)|nginx.*-s.*reload|service.*reload|owner.smoke.create|acme\.sh.*--issue|certbot.*certonly|POST.*dns|DELETE.*dns|PATCH.*dns" "$HELPER" 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*"""' | grep -v 'No ' || true)
if [[ -z "$DANGEROUS_FOUND" ]]; then
  ok "No dangerous patterns in setup flow helper"
else
  fail "Helper contains dangerous patterns: $DANGEROUS_FOUND"
fi

# 19. TTY setup menu has setup flow entry
unset_fixtures
MENU_OUT=$(printf '1\n1\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -100 || true)
if echo "$MENU_OUT" | grep -qi "一键设置流程\|setup flow"; then
  ok "TTY setup menu has setup flow entry"
else
  fail "TTY setup menu missing setup flow entry"
fi

# 20. v2.3.7 tests still pass
V237_OUT=$(bash tests/v2.3.7-token-rotation-gate.sh 2>&1 || true)
if echo "$V237_OUT" | grep -q "All v2.3.7 token rotation gate checks passed"; then
  ok "v2.3.7 token rotation gate test still passes"
else
  fail "v2.3.7 token rotation gate test failed"
  echo "$V237_OUT" | tail -5
fi

# 21. v2.3.6 tests still pass
V236_OUT=$(bash tests/v2.3.6-cert-issue-gate.sh 2>&1 || true)
if echo "$V236_OUT" | grep -q "All v2.3.6 certificate issue gate checks passed"; then
  ok "v2.3.6 cert issue gate test still passes"
else
  fail "v2.3.6 cert issue gate test failed"
  echo "$V236_OUT" | tail -5
fi

# 22. v2.3.5 tests still pass
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
  echo "All v2.3.8 full CLI setup flow checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
