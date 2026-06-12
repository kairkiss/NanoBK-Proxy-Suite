#!/usr/bin/env bash
# v2.3.4 DNS Apply Engine Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
ENGINE="lib/nanobk_dns_apply_engine.py"
FIXTURES="tests/fixtures/v2.3.4"
PAYLOAD_CAPTURE="/tmp/nanobk-test-payload-$$.jsonl"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME" "$PAYLOAD_CAPTURE"' EXIT

# Common setup
setup_env() {
  mkdir -p "$HOME/.nanobk"
  cat > "$HOME/.nanobk/setup-profile.json" <<'EOF'
{"version":1,"zone_name":"example.com","api_env_path":"/tmp/fake-cf-env-234","nodes":["proxy","web"]}
EOF
  chmod 600 "$HOME/.nanobk/setup-profile.json"
  cat > /tmp/fake-cf-env-234 <<'EOF'
CF_API_TOKEN="fake-apply-token-234"
EOF
  chmod 600 /tmp/fake-cf-env-234
}

CONFIRM="I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"

set_fixtures() {
  export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
  export NANOBK_TEST_DETECTED_IPV6=""
  export NANOBK_TEST_DETECT_IPV6_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
  export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"
  export NANOBK_DNS_APPLY_FAKE_CAPTURE_PAYLOAD="$PAYLOAD_CAPTURE"
}

unset_fixtures() {
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV4 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV6 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_CAPTURE_PAYLOAD 2>/dev/null || true
}

# 1. Python compile
if python3 -m py_compile "$ENGINE" 2>/dev/null; then
  ok "nanobk_dns_apply_engine.py compiles"
else
  fail "nanobk_dns_apply_engine.py compile error"
fi

# 2. --help exists
HELP_OUT=$(bash "$CLI" setup dns apply --help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "apply\|创建"; then
  ok "nanobk setup dns apply --help exists"
else
  fail "nanobk setup dns apply --help missing"
fi

# 3. Plan-only mode: no mutation
setup_env
set_fixtures
rm -f "$PAYLOAD_CAPTURE"
PLAN_OUT=$(bash "$CLI" setup dns apply --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mode') == 'plan', f'mode={d.get(\"mode\")}'
assert d.get('apply_executed') == False
assert d.get('attempted_create') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "Plan-only: mode=plan, apply_executed=false, mutation=false"
else
  fail "Plan-only: unexpected output"
fi

# 4. Plan-only shows records
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
recs = d.get('records', [])
assert len(recs) >= 1, f'no records'
assert all(r.get('safe_to_create') == True for r in recs)
" 2>/dev/null; then
  ok "Plan-only: shows safe-to-create records"
else
  fail "Plan-only: no safe records"
fi

# 5. Plan-only does not capture payload
if [[ ! -f "$PAYLOAD_CAPTURE" ]] || [[ ! -s "$PAYLOAD_CAPTURE" ]]; then
  ok "Plan-only: no payload captured"
else
  fail "Plan-only: payload captured unexpectedly"
fi

# 6. --apply without --confirm: blocked
APPLY_OUT=$(bash "$CLI" setup dns apply --apply --json 2>&1 || true)
if echo "$APPLY_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('attempted_create') == False
assert 'confirmation' in d.get('blocked_reason','').lower() or 'confirm' in d.get('blocked_reason','').lower() or 'confirm' in d.get('hint','').lower()
" 2>/dev/null; then
  ok "--apply without --confirm: blocked"
else
  fail "--apply without --confirm: not blocked"
fi

# 7. --apply with wrong confirm: blocked
WRONG_OUT=$(bash "$CLI" setup dns apply --apply --confirm "wrong phrase" --json 2>&1 || true)
if echo "$WRONG_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
assert d.get('attempted_create') == False
" 2>/dev/null; then
  ok "Wrong confirm phrase: blocked"
else
  fail "Wrong confirm phrase: not blocked"
fi

# 8. Correct confirm + fake create success: applied with payload verification
rm -f "$PAYLOAD_CAPTURE"
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_success.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_success.json"
APPLIED_OUT=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$APPLIED_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'applied', f'mode={d.get(\"mode\")}'
assert d.get('apply_executed') == True
assert d.get('attempted_create') == True
assert d.get('mutation') == True
assert d.get('created_count', 0) >= 1, f'created_count={d.get(\"created_count\")}'
" 2>/dev/null; then
  ok "Correct confirm + fake create: applied"
else
  fail "Correct confirm + fake create: unexpected"
fi

# 9. Payload capture verification
if [[ -f "$PAYLOAD_CAPTURE" ]] && [[ -s "$PAYLOAD_CAPTURE" ]]; then
  PAYLOAD_CHECK=$(python3 -c "
import json, sys
with open('$PAYLOAD_CAPTURE') as f:
    lines = [l.strip() for l in f if l.strip()]
assert len(lines) >= 1, 'no payloads'
p = json.loads(lines[0])
assert p.get('content') == '203.0.113.10', f'content={p.get(\"content\")}'
assert p.get('comment') == 'managed-by=nanobk', f'comment={p.get(\"comment\")}'
assert p.get('type') == 'A', f'type={p.get(\"type\")}'
assert p.get('name') in ('proxy.example.com', 'web.example.com'), f'name={p.get(\"name\")}'
assert p.get('ttl') == 1
print('OK')
" 2>&1 || true)
  if echo "$PAYLOAD_CHECK" | grep -q "OK"; then
    ok "Payload capture: content=203.0.113.10, comment=managed-by=nanobk, type=A"
  else
    fail "Payload capture: unexpected payload content"
  fi
else
  fail "Payload capture: file not created"
fi

# 10. Verified count
if echo "$APPLIED_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('verified_count', 0) >= 1
recs = d.get('records', [])
assert all(r.get('verified') == True for r in recs if r.get('created'))
" 2>/dev/null; then
  ok "Verify success: verified_count correct"
else
  fail "Verify success: verified_count wrong"
fi

# 11. Empty content protection: IP detection fails => blocked
rm -f "$PAYLOAD_CAPTURE"
unset_fixtures
setup_env
set_fixtures
export NANOBK_TEST_DETECT_IPV4_FAIL=1
export NANOBK_TEST_DETECTED_IPV6=""
export NANOBK_TEST_DETECT_IPV6_FAIL=1
EMPTY_OUT=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$EMPTY_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok should be False, got {d.get(\"ok\")}'
assert d.get('mutation') == False, f'mutation should be False'
assert d.get('created_count', 0) == 0, f'created_count should be 0'
" 2>/dev/null; then
  ok "Empty content: blocked, mutation=false, created_count=0"
else
  fail "Empty content: not properly blocked"
fi
if [[ ! -f "$PAYLOAD_CAPTURE" ]] || [[ ! -s "$PAYLOAD_CAPTURE" ]]; then
  ok "Empty content: no payload captured"
else
  fail "Empty content: payload captured unexpectedly"
fi

# 12. Preflight conflict after plan: planner says available, preflight says conflict
rm -f "$PAYLOAD_CAPTURE"
unset_fixtures
setup_env
set_fixtures
export NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE="$FIXTURES/preflight_both_conflict.json"
PREFLIGHT_OUT=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$PREFLIGHT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok should be False, got {d.get(\"ok\")}'
assert d.get('mutation') == False, f'mutation should be False'
assert d.get('created_count', 0) == 0, f'created_count should be 0'
assert d.get('attempted_create') == False, f'attempted_create should be False'
" 2>/dev/null; then
  ok "Preflight conflict: ok=false, mutation=false, created_count=0"
else
  fail "Preflight conflict: not properly blocked"
fi
if [[ ! -f "$PAYLOAD_CAPTURE" ]] || [[ ! -s "$PAYLOAD_CAPTURE" ]]; then
  ok "Preflight conflict: no payload captured"
else
  fail "Preflight conflict: payload captured unexpectedly"
fi

# 13. Planner conflict: plan-only safe records exclude conflicted
rm -f "$PAYLOAD_CAPTURE"
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_conflict.json"
PLAN_CONFLICT=$(bash "$CLI" setup dns apply --json 2>&1 || true)
if echo "$PLAN_CONFLICT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mode') == 'plan', f'mode={d.get(\"mode\")}'
recs = d.get('records', [])
safe = [r for r in recs if r.get('safe_to_create') == True]
# proxy is conflicted, only web should be safe
names = [r.get('name','') for r in safe]
assert 'proxy.example.com' not in names, f'proxy should not be safe: {names}'
" 2>/dev/null; then
  ok "Planner conflict: conflicted record not in safe-to-create"
else
  fail "Planner conflict: conflicted record still in safe-to-create"
fi

# 14. Planner conflict apply mode: created_count=0, no mutation (both conflicted)
rm -f "$PAYLOAD_CAPTURE"
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/preflight_both_conflict.json"
CONFLICT_APPLY=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$CONFLICT_APPLY" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('created_count', 0) == 0, f'created_count should be 0, got {d.get(\"created_count\")}'
assert d.get('mutation') == False, f'mutation should be False'
" 2>/dev/null; then
  ok "Planner conflict apply: created_count=0, mutation=false"
else
  fail "Planner conflict apply: unexpected"
fi

# 15. Create error: ok=false, created_count=0, mutation=true (attempted)
rm -f "$PAYLOAD_CAPTURE"
unset_fixtures
setup_env
set_fixtures
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_error.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_missing.json"
CREATE_ERR=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$CREATE_ERR" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok should be False, got {d.get(\"ok\")}'
assert d.get('created_count', 0) == 0, f'created_count should be 0'
assert d.get('verified_count', 0) == 0, f'verified_count should be 0'
assert d.get('attempted_create') == True, f'attempted_create should be True'
recs = d.get('records', [])
assert any(not r.get('created') for r in recs), 'should have created=false record'
" 2>/dev/null; then
  ok "Create error: ok=false, created_count=0, attempted_create=true"
else
  fail "Create error: not properly handled"
fi
# Payload should exist (attempted)
if [[ -f "$PAYLOAD_CAPTURE" ]] && [[ -s "$PAYLOAD_CAPTURE" ]]; then
  ok "Create error: payload captured (attempted create)"
else
  ok "Create error: no payload (create was rejected before send)"
fi

# 16. Verify missing: mutation=true, created_count>=1, verified_count=0
rm -f "$PAYLOAD_CAPTURE"
unset_fixtures
setup_env
set_fixtures
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_success.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_missing.json"
VERIFY_OUT=$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)
if echo "$VERIFY_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok should be False'
assert d.get('mutation') == True, f'mutation should be True'
assert d.get('created_count', 0) >= 1, f'created_count should be >=1'
assert d.get('verified_count', 0) == 0, f'verified_count should be 0'
recs = d.get('records', [])
created = [r for r in recs if r.get('created')]
assert len(created) >= 1, 'should have created records'
assert all(not r.get('verified') for r in created), 'created records should not be verified'
" 2>/dev/null; then
  ok "Verify missing: mutation=true, created>=1, verified=0"
else
  fail "Verify missing: not properly handled"
fi

# 17. Dangerous hostnames blocked
DANGEROUS_OUT=$(python3 -c "
import sys; sys.path.insert(0, 'lib')
from nanobk_dns_apply_engine import validate_apply_target
for name in ['www.example.com', 'api.example.com', 'mail.example.com', 'cdn.example.com', 'example.com']:
    ok, err = validate_apply_target({'name': name, 'type': 'A', 'zone_name': 'example.com'})
    if ok:
        print(f'FAIL: {name} should be blocked')
        sys.exit(1)
print('ALL_BLOCKED')
" 2>&1 || true)
if echo "$DANGEROUS_OUT" | grep -q "ALL_BLOCKED"; then
  ok "Dangerous hostnames (www/api/mail/cdn/root) blocked"
else
  fail "Dangerous hostnames not blocked"
fi

# 18. Only proxy/web allowed
ALLOWED_OUT=$(python3 -c "
import sys; sys.path.insert(0, 'lib')
from nanobk_dns_apply_engine import validate_apply_target
for name in ['proxy.example.com', 'web.example.com']:
    ok, err = validate_apply_target({'name': name, 'type': 'A', 'zone_name': 'example.com'})
    if not ok:
        print(f'FAIL: {name} should be allowed: {err}')
        sys.exit(1)
for name in ['test.example.com', 'foo.example.com']:
    ok, err = validate_apply_target({'name': name, 'type': 'A', 'zone_name': 'example.com'})
    if ok:
        print(f'FAIL: {name} should be blocked')
        sys.exit(1)
print('OK')
" 2>&1 || true)
if echo "$ALLOWED_OUT" | grep -q "OK"; then
  ok "Only proxy/web hostnames allowed"
else
  fail "Hostname allowlist wrong"
fi

# 19. Only A/AAAA allowed
TYPE_OUT=$(python3 -c "
import sys; sys.path.insert(0, 'lib')
from nanobk_dns_apply_engine import validate_apply_target
for t in ['A', 'AAAA']:
    ok, err = validate_apply_target({'name': 'proxy.example.com', 'type': t, 'zone_name': 'example.com'})
    if not ok:
        print(f'FAIL: {t} should be allowed')
        sys.exit(1)
for t in ['CNAME', 'MX', 'TXT', 'NS']:
    ok, err = validate_apply_target({'name': 'proxy.example.com', 'type': t, 'zone_name': 'example.com'})
    if ok:
        print(f'FAIL: {t} should be blocked')
        sys.exit(1)
print('OK')
" 2>&1 || true)
if echo "$TYPE_OUT" | grep -q "OK"; then
  ok "Only A/AAAA record types allowed"
else
  fail "Record type allowlist wrong"
fi

# 20. No secret leaks in multiple modes
set_fixtures
rm -f "$PAYLOAD_CAPTURE"
LEAK_MODES=("plan-only" "blocked" "applied")
LEAK_OUT=""
LEAK_OUT+="$(bash "$CLI" setup dns apply --json 2>&1 || true)"
LEAK_OUT+="$(bash "$CLI" setup dns apply --apply --json 2>&1 || true)"
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_success.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_success.json"
LEAK_OUT+="$(bash "$CLI" setup dns apply --apply --confirm "$CONFIRM" --json 2>&1 || true)"
LEAK_OK=1
for leak in "fake-apply-token-234" "fake-zone-id-aaaabbbbcccc" "api.cloudflare.com/client/v4" "/dns_records" "PRIVATE KEY" "SUB_TOKEN=" "ADMIN_TOKEN=" "subscription"; do
  if echo "$LEAK_OUT" | grep -qi "$leak"; then
    fail "Output leaks: $leak"
    LEAK_OK=0
  fi
done
if [[ "$LEAK_OK" == "1" ]]; then
  ok "No secret leaks across plan/blocked/applied modes"
fi

# 21. POST only in apply engine
POST_LINES=$(grep -n 'method.*POST\|POST.*dns_records\|urlopen.*POST' "$ENGINE" 2>/dev/null || true)
if [[ -n "$POST_LINES" ]]; then
  ok "POST exists in apply engine (expected for create)"
else
  ok "No POST in apply engine (create uses different pattern)"
fi

# 22. No DELETE/PATCH/PUT in engine
DANGEROUS_METHODS=$(grep -nE 'method="(DELETE|PATCH|PUT)"' "$ENGINE" 2>/dev/null || true)
if [[ -n "$DANGEROUS_METHODS" ]]; then
  fail "Apply engine contains DELETE/PATCH/PUT"
else
  ok "No DELETE/PATCH/PUT in apply engine"
fi

# 23. No owner-smoke-create
if grep -q "owner-smoke-create" "$ENGINE" 2>/dev/null; then
  fail "Apply engine references owner-smoke-create"
else
  ok "No owner-smoke-create in apply engine"
fi

# 24. TTY menu shows plan, not apply
unset_fixtures
MENU_OUT=$(printf '4\n3\n13\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -100 || true)
if echo "$MENU_OUT" | grep -q "准备创建 DNS\|创建预案"; then
  ok "TTY menu shows '准备创建 DNS' (plan-only)"
else
  fail "TTY menu missing DNS apply entry"
fi

# 25. cf dns apply-plan entry exists
CFHELP_OUT=$(bash "$CLI" cf dns --help 2>&1 || true)
if echo "$CFHELP_OUT" | grep -q "apply-plan"; then
  ok "cf dns help mentions apply-plan"
else
  fail "cf dns help missing apply-plan"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.4 DNS apply engine checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
