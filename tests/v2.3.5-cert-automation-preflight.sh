#!/usr/bin/env bash
# v2.3.5 Certificate Automation Preflight Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
# No real certificate requests. No real service changes.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
HELPER="lib/nanobk_cert_preflight.py"
FIXTURES="tests/fixtures/v2.3.5"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Common setup
setup_env() {
  mkdir -p "$HOME/.nanobk"
  cat > "$HOME/.nanobk/setup-profile.json" <<'EOF'
{"version":1,"zone_name":"example.com","api_env_path":"/tmp/fake-cf-env-235","nodes":["proxy","web"]}
EOF
  chmod 600 "$HOME/.nanobk/setup-profile.json"
  cat > /tmp/fake-cf-env-235 <<'EOF'
CF_API_TOKEN="fake-cert-token-235"
EOF
  chmod 600 /tmp/fake-cf-env-235
}

set_fixtures() {
  export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
  export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_both_owned.json"
  export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":false,"certbot":false}'
  export NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
}

unset_fixtures() {
  unset NANOBK_CF_ZONES_FAKE_RESPONSE 2>/dev/null || true
  unset NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_TOOLS 2>/dev/null || true
  unset NANOBK_CERT_PREFLIGHT_FAKE_PORTS 2>/dev/null || true
}

# 1. Python compile
if python3 -m py_compile "$HELPER" 2>/dev/null; then
  ok "nanobk_cert_preflight.py compiles"
else
  fail "nanobk_cert_preflight.py compile error"
fi

# 2. nanobk setup cert plan --help
HELP_OUT=$(bash "$CLI" setup cert plan --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qi "cert\|证书\|preflight\|预检"; then
  ok "nanobk setup cert plan --help exists"
else
  fail "nanobk setup cert plan --help missing"
fi

# 3. nanobk cert plan --help
HELP_OUT2=$(bash "$CLI" cert plan --help 2>&1 || true)
if echo "$HELP_OUT2" | grep -qi "cert\|证书\|preflight\|预检"; then
  ok "nanobk cert plan --help exists"
else
  fail "nanobk cert plan --help missing"
fi

# 4. No profile: beginner hint
rm -rf "$HOME/.nanobk"
NO_PROF_OUT=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$NO_PROF_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert 'profile' in d.get('error','').lower() or 'cf connect' in d.get('error','').lower()
" 2>/dev/null; then
  ok "No profile: gives beginner hint"
else
  fail "No profile: unexpected output"
fi

# 5. With profile: reads zone
setup_env
set_fixtures
JSON_OUT=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$JSON_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('zone_name') == 'example.com', f'zone={d.get(\"zone_name\")}'
assert d.get('mode') == 'cert_preflight'
" 2>/dev/null; then
  ok "With profile: reads zone correctly"
else
  fail "With profile: unexpected output"
fi

# 6. Both DNS present and owned: ok=true
if echo "$JSON_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
domains = d.get('domains', [])
assert len(domains) == 2, f'domains count={len(domains)}'
for dom in domains:
  assert dom.get('dns_present') == True, f'{dom.get(\"name\")}: dns_present={dom.get(\"dns_present\")}'
  assert dom.get('nanobk_owned') == True, f'{dom.get(\"name\")}: nanobk_owned={dom.get(\"nanobk_owned\")}'
" 2>/dev/null; then
  ok "Both DNS present and NanoBK-owned"
else
  fail "Both DNS not properly detected"
fi

# 7. Proxy missing: ok=false or domains show missing
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_proxy_missing.json"
PROXY_MISS=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$PROXY_MISS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
domains = d.get('domains', [])
proxy = next((dom for dom in domains if 'proxy' in dom.get('name','')), None)
assert proxy is not None
# proxy should have dns_present=False
assert proxy.get('dns_present') == False, f'proxy dns_present={proxy.get(\"dns_present\")}'
" 2>/dev/null; then
  ok "Proxy missing: dns_present=false"
else
  fail "Proxy missing: not detected"
fi

# 8. Web missing: domains show missing
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_web_missing.json"
WEB_MISS=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$WEB_MISS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
domains = d.get('domains', [])
web = next((dom for dom in domains if 'web' in dom.get('name','')), None)
assert web is not None
assert web.get('dns_present') == False, f'web dns_present={web.get(\"dns_present\")}'
" 2>/dev/null; then
  ok "Web missing: dns_present=false"
else
  fail "Web missing: not detected"
fi

# 9. Non-NanoBK-owned: manual review hint
unset_fixtures
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_unowned.json"
UNOWNED=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$UNOWNED" | python3 -c "
import json,sys
d=json.load(sys.stdin)
domains = d.get('domains', [])
for dom in domains:
  if dom.get('dns_present'):
    assert dom.get('nanobk_owned') == False, f'{dom.get(\"name\")}: should not be nanobk owned'
" 2>/dev/null; then
  ok "Non-NanoBK-owned: nanobk_owned=false"
else
  fail "Non-NanoBK-owned: not properly detected"
fi

# 10. acme.sh present
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
ACME_OUT=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$ACME_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('tools',{}).get('acme_sh') == True
assert d.get('tools',{}).get('certbot') == False
" 2>/dev/null; then
  ok "acme.sh present detection"
else
  fail "acme.sh present detection failed"
fi

# 11. certbot present
export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":false,"certbot":true}'
CERTBOT_OUT=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$CERTBOT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('tools',{}).get('acme_sh') == False
assert d.get('tools',{}).get('certbot') == True
" 2>/dev/null; then
  ok "certbot present detection"
else
  fail "certbot present detection failed"
fi

# 12. Port 80 free
unset_fixtures
setup_env
set_fixtures
export NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
PORT_OUT=$(bash "$CLI" setup cert plan --json 2>&1 || true)
if echo "$PORT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ports',{}).get('80') == 'free'
" 2>/dev/null; then
  ok "Port 80 free detection"
else
  fail "Port 80 free detection failed"
fi

# 13. Port 443 listening
if echo "$PORT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ports',{}).get('443') == 'listening'
" 2>/dev/null; then
  ok "Port 443 listening detection"
else
  fail "Port 443 listening detection failed"
fi

# 14. Default recommendation: dns-01-cloudflare
if echo "$PORT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('recommended_method') == 'dns-01-cloudflare', f'method={d.get(\"recommended_method\")}'
" 2>/dev/null; then
  ok "Default recommendation: dns-01-cloudflare"
else
  fail "Default recommendation wrong"
fi

# 15. JSON: issue_executed=false
if echo "$PORT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('issue_executed') == False
" 2>/dev/null; then
  ok "JSON: issue_executed=false"
else
  fail "JSON: issue_executed not false"
fi

# 16. JSON: mutation=false
if echo "$PORT_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "JSON: mutation=false"
else
  fail "JSON: mutation not false"
fi

# 17. No secret leaks
LEAK_OK=1
for leak in "fake-cert-token-235" "fake-zone-id-aaaabbbbcccc" "api.cloudflare.com/client/v4" "/dns_records" "PRIVATE KEY" "SUB_TOKEN=" "ADMIN_TOKEN=" "subscription"; do
  if echo "$PORT_OUT" | grep -qi "$leak"; then
    fail "Output leaks: $leak"
    LEAK_OK=0
  fi
done
if [[ "$LEAK_OK" == "1" ]]; then
  ok "No secret leaks in cert preflight output"
fi

# 18. No acme.sh --issue, certbot certonly, systemctl reload, etc.
# Only check actual code lines, not comments/docstrings
DANGEROUS_FOUND=$(grep -nE "acme\.sh.*--issue|certbot.*certonly|systemctl.*(reload|restart)|nginx.*-s.*reload|service.*reload" "$HELPER" 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*"""' | grep -v 'No ' || true)
if [[ -z "$DANGEROUS_FOUND" ]]; then
  ok "No dangerous commands in helper"
else
  fail "Helper contains dangerous commands: $DANGEROUS_FOUND"
fi

# 19. No POST/PATCH/PUT/DELETE
DANGEROUS_METHODS=$(grep -nE 'method="(POST|PATCH|PUT|DELETE)"' "$HELPER" 2>/dev/null || true)
if [[ -z "$DANGEROUS_METHODS" ]]; then
  ok "No POST/PATCH/PUT/DELETE in helper"
else
  fail "Helper contains POST/PATCH/PUT/DELETE"
fi

# 20. No owner-smoke-create
if grep -q "owner-smoke-create" "$HELPER" 2>/dev/null; then
  fail "Helper references owner-smoke-create"
else
  ok "No owner-smoke-create in helper"
fi

# 21. TTY menu has cert entry
unset_fixtures
MENU_OUT=$(printf '1\n4\n6\n' | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -80 || true)
if echo "$MENU_OUT" | grep -q "证书\|cert"; then
  ok "TTY menu has cert entry"
else
  fail "TTY menu missing cert entry"
fi

# 22. API error handling — strict: must fail or show error domains + blocked method
setup_env
set_fixtures
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_api_error.json"
API_ERR=$(bash "$CLI" setup cert plan --json 2>&1 || true)
API_ERR_OK=0
if echo "$API_ERR" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('ok') == False:
  assert 'error' in d and d['error'], 'missing error field'
else:
  domains = d.get('domains', [])
  assert any(dom.get('status') == 'error' or dom.get('error') for dom in domains), 'no domain error'
  assert d.get('recommended_method') == 'blocked', f'method={d.get(\"recommended_method\")}'
" 2>/dev/null; then
  API_ERR_OK=1
fi
if [[ "$API_ERR_OK" == "1" ]]; then
  ok "API error handling"
else
  fail "API error: not properly handled"
fi
# API error output must not leak secrets
API_ERR_LEAK=0
for leak in "fake-cert-token-235" "fake-zone-id-aaaabbbbcccc" "api.cloudflare.com/client/v4" "/dns_records" "raw"; do
  if echo "$API_ERR" | grep -qi "$leak"; then
    fail "API error output leaks: $leak"
    API_ERR_LEAK=1
  fi
done
if [[ "$API_ERR_LEAK" == "0" ]]; then
  ok "API error output: no secret leaks"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.5 certificate preflight checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
