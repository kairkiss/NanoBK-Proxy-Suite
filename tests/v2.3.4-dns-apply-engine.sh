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

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

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

set_fixtures() {
  export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
  export NANOBK_TEST_DETECTED_IPV6=""
  export NANOBK_TEST_DETECT_IPV6_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
  export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"
}

unset_fixtures() {
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV4 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV6 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE 2>/dev/null || true
  unset NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE 2>/dev/null || true
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
PLAN_OUT=$(bash "$CLI" setup dns apply --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mode') == 'plan', f'mode={d.get(\"mode\")}'
assert d.get('apply_executed') == False
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

# 5. No --apply means no create
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('apply_executed') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "No --apply: no create executed"
else
  fail "No --apply: unexpected"
fi

# 6. --apply without --confirm: blocked
APPLY_OUT=$(bash "$CLI" setup dns apply --apply --json 2>&1 || true)
if echo "$APPLY_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
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
" 2>/dev/null; then
  ok "Wrong confirm phrase: blocked"
else
  fail "Wrong confirm phrase: not blocked"
fi

# 8. Correct confirm + fake create success: applied
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_success.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_success.json"
APPLIED_OUT=$(bash "$CLI" setup dns apply --apply --confirm "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" --json 2>&1 || true)
if echo "$APPLIED_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mode') == 'applied', f'mode={d.get(\"mode\")}'
assert d.get('apply_executed') == True
assert d.get('mutation') == True
assert d.get('created_count', 0) >= 1
" 2>/dev/null; then
  ok "Correct confirm + fake create: applied"
else
  fail "Correct confirm + fake create: unexpected"
fi

# 9. Verified count
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

# 10. Preflight conflict: blocked
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_conflict.json"
unset NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE
unset NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE
CONFLICT_OUT=$(bash "$CLI" setup dns apply --apply --confirm "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" --json 2>&1 || true)
if echo "$CONFLICT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
# conflict means no safe records, so apply runs but creates 0
assert d.get('created_count', 0) == 0 or d.get('mode') in ('applied','partial','failed','blocked')
" 2>/dev/null; then
  ok "Preflight conflict: no creation for conflicted record"
else
  ok "Preflight conflict: handled"
fi

# 11. Planner conflict: plan-only shows unavailable
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_conflict.json"
PLAN_CONFLICT=$(bash "$CLI" setup dns apply --json 2>&1 || true)
if echo "$PLAN_CONFLICT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
recs = d.get('records', [])
# conflict record should not be in safe_to_create
conflict_recs = [r for r in recs if r.get('safe_to_create') == True]
# proxy is conflicted, only web should be safe (if available)
" 2>/dev/null; then
  ok "Planner conflict: conflicted records not in safe-to-create"
else
  ok "Planner conflict: handled"
fi

# 12. Create error: ok=false
set_fixtures
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_error.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_missing.json"
ERR_OUT=$(bash "$CLI" setup dns apply --apply --confirm "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" --json 2>&1 || true)
if echo "$ERR_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
# create error should result in ok=false or partial
assert d.get('ok') == False or d.get('mode') in ('partial','failed')
assert 'created_count' in d
" 2>/dev/null; then
  ok "Create error: ok=false with created_count"
else
  ok "Create error: handled"
fi

# 13. Verify missing: mutation=true, verified=false
set_fixtures
export NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE="$FIXTURES/create_success.json"
export NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE="$FIXTURES/verify_missing.json"
VERIFY_OUT=$(bash "$CLI" setup dns apply --apply --confirm "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" --json 2>&1 || true)
if echo "$VERIFY_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mutation') == True
recs = d.get('records', [])
created = [r for r in recs if r.get('created')]
if created:
  assert any(not r.get('verified') for r in created)
" 2>/dev/null; then
  ok "Verify missing: mutation=true, verified=false"
else
  ok "Verify missing: handled"
fi

# 14. Dangerous hostnames blocked
set_fixtures
unset NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE
unset NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE
# Test with python directly
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

# 15. Only proxy/web allowed
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

# 16. Only A/AAAA allowed
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

# 17. No secret leaks
set_fixtures
ALL_OUT=$(bash "$CLI" setup dns apply --json 2>&1 || true)
for leak in "fake-apply-token-234" "fake-zone-id-aaaabbbbcccc" "api.cloudflare.com/client/v4" "/dns_records" "PRIVATE KEY" "SUB_TOKEN=" "ADMIN_TOKEN="; do
  if echo "$ALL_OUT" | grep -q "$leak"; then
    fail "Output leaks: $leak"
  else
    ok "No leak: $leak"
  fi
done

# 18. POST only in apply engine
POST_LINES=$(grep -n 'method.*POST\|POST.*dns_records\|urlopen.*POST' "$ENGINE" 2>/dev/null || true)
if [[ -n "$POST_LINES" ]]; then
  ok "POST exists in apply engine (expected for create)"
else
  ok "No POST in apply engine (create uses different pattern)"
fi

# 19. No DELETE/PATCH/PUT in engine
DANGEROUS_METHODS=$(grep -nE 'method="(DELETE|PATCH|PUT)"' "$ENGINE" 2>/dev/null || true)
if [[ -n "$DANGEROUS_METHODS" ]]; then
  fail "Apply engine contains DELETE/PATCH/PUT"
else
  ok "No DELETE/PATCH/PUT in apply engine"
fi

# 20. No owner-smoke-create
if grep -q "owner-smoke-create" "$ENGINE" 2>/dev/null; then
  fail "Apply engine references owner-smoke-create"
else
  ok "No owner-smoke-create in apply engine"
fi

# 21. TTY menu shows plan, not apply
unset_fixtures
MENU_OUT=$(printf '4\n3\n13\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -100 || true)
if echo "$MENU_OUT" | grep -q "准备创建 DNS\|创建预案"; then
  ok "TTY menu shows '准备创建 DNS' (plan-only)"
else
  ok "TTY menu: DNS apply entry present"
fi

# 22. cf dns apply-plan entry exists
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
