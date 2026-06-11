#!/usr/bin/env bash
# v2.3.3 Domain/IP/Subdomain Planner Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
PLANNER="lib/nanobk_domain_planner.py"
FIXTURES="tests/fixtures/v2.3.3"

# Use temp HOME to avoid polluting real ~/.nanobk
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Common fake env setup
setup_fake_env() {
  mkdir -p "$HOME/.nanobk"
  cat > "$HOME/.nanobk/setup-profile.json" <<'EOF'
{
  "version": 1,
  "zone_name": "example.com",
  "api_env_path": "/tmp/fake-cloudflare.env",
  "nodes": ["proxy", "web"],
  "created_by": "test"
}
EOF
  chmod 600 "$HOME/.nanobk/setup-profile.json"
  cat > /tmp/fake-cloudflare.env <<'EOF'
CF_API_TOKEN="fake-token-for-test-only"
EOF
  chmod 600 /tmp/fake-cloudflare.env
}

set_ip_fixtures() {
  export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
  export NANOBK_TEST_DETECTED_IPV6=""
  export NANOBK_TEST_DETECT_IPV6_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
  export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
}

unset_all_fixtures() {
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV4 2>/dev/null || true
  unset NANOBK_TEST_DETECTED_IPV6 2>/dev/null || true
  unset NANOBK_TEST_DETECT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL 2>/dev/null || true
  unset NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL 2>/dev/null || true
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
}

# 1. Python compile
if python3 -m py_compile "$PLANNER" 2>/dev/null; then
  ok "nanobk_domain_planner.py compiles"
else
  fail "nanobk_domain_planner.py compile error"
fi

# 2. --help exists
HELP_OUT=$(bash "$CLI" setup plan --help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "规划\|plan"; then
  ok "nanobk setup plan --help exists"
else
  fail "nanobk setup plan --help missing"
fi

# 3. No profile gives beginner prompt
rm -rf "$HOME/.nanobk"
NOPLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$NOPLAN_OUT" | grep -qi "cf connect\|setup profile\|未找到"; then
  ok "No profile: gives beginner prompt"
else
  fail "No profile: unexpected output"
fi

# 4. Setup fake env
setup_fake_env
set_ip_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"

# 5. IPv4 fixture detection
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ipv4_detected')==True" 2>/dev/null; then
  ok "IPv4 detected from fixture"
else
  fail "IPv4 not detected from fixture"
fi

# 6. IPv4+IPv6 detection
export NANOBK_TEST_DETECTED_IPV6="2001:db8::10"
export NANOBK_TEST_DETECT_IPV6_FAIL=""
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ipv4_detected')==True; assert d.get('ipv6_detected')==True" 2>/dev/null; then
  ok "IPv4+IPv6 detected from fixtures"
else
  fail "IPv4+IPv6 not both detected"
fi
export NANOBK_TEST_DETECTED_IPV6=""
export NANOBK_TEST_DETECT_IPV6_FAIL=1

# 7. Both available: ok=true, apply_ready=false, mutation=false
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mutation') == False
assert d.get('apply_ready') == False
recs = d.get('records', [])
assert len(recs) == 2
assert all(r.get('available') == True for r in recs)
assert d.get('any_planned') == True
" 2>/dev/null; then
  ok "Both available: ok=true, apply_ready=false, mutation=false, planned records"
else
  fail "Both available: unexpected plan output"
fi

# 8. Proxy conflict: ok=true, proxy unavailable, web available, proxy not planned
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_proxy_conflict.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
recs = d.get('records', [])
proxy = [r for r in recs if r.get('role') == 'proxy'][0]
web = [r for r in recs if r.get('role') == 'web'][0]
assert proxy.get('available') == False
assert proxy.get('planned') == False
assert web.get('available') == True
" 2>/dev/null; then
  ok "Proxy conflict: ok=true, proxy unavailable+unplanned, web available"
else
  fail "Proxy conflict: unexpected output"
fi

# 9. Web conflict: ok=true, web unavailable, proxy available
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_web_conflict.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
recs = d.get('records', [])
web = [r for r in recs if r.get('role') == 'web'][0]
proxy = [r for r in recs if r.get('role') == 'proxy'][0]
assert web.get('available') == False
assert web.get('planned') == False
assert proxy.get('available') == True
" 2>/dev/null; then
  ok "Web conflict: ok=true, web unavailable+unplanned, proxy available"
else
  fail "Web conflict: unexpected output"
fi

# 10. JSON does not contain token
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | grep -q "fake-token-for-test-only"; then
  fail "JSON output leaks token"
else
  ok "JSON output does not contain token"
fi

# 11. JSON does not contain zone id
if echo "$PLAN_OUT" | grep -q "fake-zone-id-aaaabbbbcccc"; then
  fail "JSON output leaks zone id"
else
  ok "JSON output does not contain zone id"
fi

# 12. JSON does not contain raw API URL
if echo "$PLAN_OUT" | grep -q "api.cloudflare.com/client/v4"; then
  fail "JSON output leaks raw API URL"
else
  ok "JSON output does not contain raw API URL"
fi

# 13. Text output does not leak token/env path/raw API
TEXT_OUT=$(bash "$CLI" setup plan 2>&1 || true)
if echo "$TEXT_OUT" | grep -q "fake-token-for-test-only"; then
  fail "Text output leaks token"
else
  ok "Text output does not leak token"
fi
if echo "$TEXT_OUT" | grep -q "fake-cloudflare.env"; then
  fail "Text output leaks env path"
else
  ok "Text output does not leak env path"
fi
if echo "$TEXT_OUT" | grep -q "api.cloudflare.com"; then
  fail "Text output leaks raw API"
else
  ok "Text output does not leak raw API"
fi

# 14. No POST/PATCH/PUT/DELETE mutation calls in planner
MUTATION_LINES=$(grep -nE 'method="(POST|PATCH|PUT|DELETE)"|urlopen.*POST|requests\.(post|put|patch|delete)' "$PLANNER" 2>/dev/null || true)
if [[ -n "$MUTATION_LINES" ]]; then
  fail "Planner contains mutation method calls"
else
  ok "No POST/PATCH/PUT/DELETE mutation calls in planner"
fi

# 15. No owner-smoke-create in planner
if grep -q "owner-smoke-create" "$PLANNER" 2>/dev/null; then
  fail "Planner references owner-smoke-create"
else
  ok "No owner-smoke-create in planner"
fi

# 16. API error fails the planner (ok=false)
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_api_error.json"
export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
export NANOBK_TEST_DETECT_IPV6_FAIL=1
ERR_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$ERR_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False, f'ok should be False, got {d.get(\"ok\")}'
assert d.get('mutation') == False, f'mutation should be False'
assert d.get('apply_ready') == False, f'apply_ready should be False'
assert 'error' in d, 'error field missing'
assert len(d.get('error','')) > 0, 'error is empty'
" 2>/dev/null; then
  ok "API error: ok=false, mutation=false, apply_ready=false, error present"
else
  fail "API error: did not return expected failure"
fi

# 17. API error output does not leak secrets
if echo "$ERR_OUT" | grep -q "fake-token-for-test-only"; then
  fail "API error output leaks token"
else
  ok "API error output does not leak token"
fi
if echo "$ERR_OUT" | grep -q "fake-zone-id-aaaabbbbcccc"; then
  fail "API error output leaks zone id"
else
  ok "API error output does not leak zone id"
fi
if echo "$ERR_OUT" | grep -q "api.cloudflare.com/client/v4"; then
  fail "API error output leaks raw API URL"
else
  ok "API error output does not leak raw API URL"
fi
if echo "$ERR_OUT" | grep -q "/dns_records"; then
  fail "API error output leaks /dns_records"
else
  ok "API error output does not leak /dns_records"
fi

# 18. profile_loaded semantics: profile used, no override
unset_all_fixtures
setup_fake_env
set_ip_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('profile_loaded') == True, f'profile_loaded={d.get(\"profile_loaded\")}'
assert d.get('overrides_used') == False, f'overrides_used={d.get(\"overrides_used\")}'
" 2>/dev/null; then
  ok "profile_loaded=true, overrides_used=false when using profile"
else
  fail "profile_loaded/overrides_used semantics wrong for profile case"
fi

# 19. overrides_used=true when --zone and --api-env given
PLAN_OUT=$(bash "$CLI" setup plan --zone example.com --api-env /tmp/fake-cloudflare.env --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('overrides_used') == True, f'overrides_used={d.get(\"overrides_used\")}'
" 2>/dev/null; then
  ok "overrides_used=true when --zone and --api-env given"
else
  fail "overrides_used not true with explicit overrides"
fi

# 20. TTY menu contains "规划域名"
unset_all_fixtures
MENU_OUT=$(printf '1\n5\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -80 || true)
if echo "$MENU_OUT" | grep -q "规划域名\|规划 proxy"; then
  ok "TTY setup menu contains '规划域名'"
else
  fail "TTY setup menu missing '规划域名'"
fi

DNS_MENU_OUT=$(echo "4" | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -80 || true)
if echo "$DNS_MENU_OUT" | grep -q "规划 proxy/web"; then
  ok "DNS menu contains '规划 proxy/web'"
else
  fail "DNS menu missing '规划 proxy/web'"
fi

# 21. cf dns planner entry exists
CFHELP_OUT=$(bash "$CLI" cf dns --help 2>&1 || true)
if echo "$CFHELP_OUT" | grep -q "planner"; then
  ok "cf dns help mentions planner"
else
  fail "cf dns help missing planner"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.3 domain IP subdomain planner checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
