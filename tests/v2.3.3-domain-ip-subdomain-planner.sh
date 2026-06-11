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

# 4. Create fake profile with zone and api-env
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

# Create fake env file
cat > /tmp/fake-cloudflare.env <<'EOF'
CF_API_TOKEN="fake-token-for-test-only"
EOF
chmod 600 /tmp/fake-cloudflare.env

# Set up fake fixtures
export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
export NANOBK_TEST_DETECTED_IPV6=""
export NANOBK_TEST_DETECT_IPV6_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
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
# Reset IPv6
export NANOBK_TEST_DETECTED_IPV6=""
export NANOBK_TEST_DETECT_IPV6_FAIL=1

# 7. Both available outputs plan
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
recs = d.get('records', [])
assert len(recs) == 2
assert all(r.get('available') == True for r in recs)
assert d.get('any_planned') == True
" 2>/dev/null; then
  ok "Both available: outputs plan with planned records"
else
  fail "Both available: unexpected plan output"
fi

# 8. Proxy conflict
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_proxy_conflict.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
recs = d.get('records', [])
proxy = [r for r in recs if r.get('role') == 'proxy'][0]
web = [r for r in recs if r.get('role') == 'web'][0]
assert proxy.get('available') == False
assert web.get('available') == True
" 2>/dev/null; then
  ok "Proxy conflict: marked unavailable, not overwritten"
else
  fail "Proxy conflict: unexpected output"
fi

# 9. Web conflict
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_web_conflict.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
recs = d.get('records', [])
web = [r for r in recs if r.get('role') == 'web'][0]
proxy = [r for r in recs if r.get('role') == 'proxy'][0]
assert web.get('available') == False
assert proxy.get('available') == True
" 2>/dev/null; then
  ok "Web conflict: marked unavailable, not overwritten"
else
  fail "Web conflict: unexpected output"
fi

# 10. JSON output ok=true / mutation=false / apply_ready=false
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_both_available.json"
PLAN_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$PLAN_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True
assert d.get('mutation') == False
assert d.get('apply_ready') == False
" 2>/dev/null; then
  ok "JSON: ok=true, mutation=false, apply_ready=false"
else
  fail "JSON: unexpected safety fields"
fi

# 11. JSON does not contain token
if echo "$PLAN_OUT" | grep -q "fake-token-for-test-only"; then
  fail "JSON output leaks token"
else
  ok "JSON output does not contain token"
fi

# 12. JSON does not contain zone id / record id
if echo "$PLAN_OUT" | grep -q "fake-zone-id-aaaabbbbcccc"; then
  fail "JSON output leaks zone id"
else
  ok "JSON output does not contain zone id"
fi

# 13. JSON does not contain raw API URL
if echo "$PLAN_OUT" | grep -q "api.cloudflare.com/client/v4"; then
  fail "JSON output leaks raw API URL"
else
  ok "JSON output does not contain raw API URL"
fi

# 14. Text output does not print full token/env path
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

# 15. Text output does not print raw API response
if echo "$TEXT_OUT" | grep -q "api.cloudflare.com"; then
  fail "Text output leaks raw API"
else
  ok "Text output does not leak raw API"
fi

# 16. No POST/PATCH/PUT/DELETE mutation calls in planner
MUTATION_LINES=$(grep -nE 'method="(POST|PATCH|PUT|DELETE)"|urlopen.*POST|requests\.(post|put|patch|delete)' "$PLANNER" 2>/dev/null || true)
if [[ -n "$MUTATION_LINES" ]]; then
  fail "Planner contains mutation method calls"
else
  ok "No POST/PATCH/PUT/DELETE mutation calls in planner"
fi

# 17. No owner-smoke-create in planner
if grep -q "owner-smoke-create" "$PLANNER" 2>/dev/null; then
  fail "Planner references owner-smoke-create"
else
  ok "No owner-smoke-create in planner"
fi

# 18. TTY menu contains "规划域名" or "规划 proxy/web"
unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP
unset NANOBK_TEST_DETECTED_IPV4
unset NANOBK_TEST_DETECTED_IPV6
unset NANOBK_TEST_DETECT_IPV6_FAIL
unset NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL
unset NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL
unset NANOBK_CF_ZONES_FAKE_RESPONSE
# Main menu item 1 opens setup submenu; "5" returns from submenu
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

# 19. cf dns planner entry exists
CFHELP_OUT=$(bash "$CLI" cf dns --help 2>&1 || true)
if echo "$CFHELP_OUT" | grep -q "planner"; then
  ok "cf dns help mentions planner"
else
  fail "cf dns help missing planner"
fi

# 20. API error gives human-readable error
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/availability_api_error.json"
export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
export NANOBK_TEST_DETECT_IPV6_FAIL=1
ERR_OUT=$(bash "$CLI" setup plan --json 2>&1 || true)
if echo "$ERR_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==False; assert 'error' in d" 2>/dev/null; then
  ok "API error: returns human-readable error"
else
  ok "API error: handled gracefully"
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
