#!/usr/bin/env bash
# v2.5.2 Production DNS Readiness Flow Test
#
# Tests the Cloudflare domain/DNS readiness flow.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_dns_readiness.py"
FIXTURES="$REPO_DIR/tests/fixtures"

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
  local num="$1" label="$2" json="$3" pattern="$4"
  if echo "$json" | grep -qi "$pattern"; then
    fail "$num: $label — found '$pattern'"
  else
    ok "$num: $label"
  fi
}

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Prepare fake api-env with correct permissions
FAKE_ENV="$HOME/fake-cf.env"
cp "$FIXTURES/cf-api-env-fake.env" "$FAKE_ENV"
chmod 600 "$FAKE_ENV"

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production dns >/dev/null 2>&1; then
  ok "2: setup production dns exits 0"
else
  fail "2: setup production dns exits non-zero"
fi

# 3
if "$NANOBK" setup production dns --json >/dev/null 2>&1; then
  ok "3: setup production dns --json exits 0"
else
  fail "3: setup production dns --json exits non-zero"
fi

# 4
if "$NANOBK" beginner production dns >/dev/null 2>&1; then
  ok "4: beginner production dns exits 0"
else
  fail "4: beginner production dns exits non-zero"
fi

# 5
if "$NANOBK" beginner production dns --json >/dev/null 2>&1; then
  ok "5: beginner production dns --json exits 0"
else
  fail "5: beginner production dns --json exits non-zero"
fi

echo ""
echo "=== B. Missing profile / env ==="

# 6-9 — no profile, no api-env → should return ok with blocked
# (run before save test to avoid profile interference)
JSON=$("$NANOBK" setup production dns --json 2>&1)

check_json "6" "ok == true" "$JSON" "d['ok']" "True"
check_json "7" "next_step == connect_cloudflare" "$JSON" "d['next_step']" "connect_cloudflare"
check_no "8" "no CF_API_TOKEN" "$JSON" "CF_API_TOKEN"
check_no "9" "no api_env_path" "$JSON" "api_env_path"

# 10 — save with temp HOME (use --save flag)
if "$NANOBK" setup production dns --save --zone example.com --api-env "$FAKE_ENV" >/dev/null 2>&1; then
  ok "10: setup production dns --save --zone exits 0"
else
  fail "10: setup production dns --save exits non-zero"
fi

echo ""
echo "=== C. Fake Cloudflare zones ==="

# 11-14 — use fake zones fixture with fake api-env
JSON_CF=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf-zones-success.json" \
  NANOBK_TEST_DETECT_IPV4_FAIL=1 NANOBK_TEST_DETECT_IPV6_FAIL=1 \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --json 2>&1)

check_json "11" "selected_domain == example.com" "$JSON_CF" "d['selected_domain']" "example.com"
check_json "12" "zones_count == 2" "$JSON_CF" "d['cloudflare']['zones_count']" "2"
check_no "13" "no zone_id in output" "$JSON_CF" "zone_id"
check_no "14" "no raw API response" "$JSON_CF" "api.cloudflare.com"

echo ""
echo "=== D. IP detection ==="

# 15-18 — fake IPv4 and IPv6
JSON_IP=$(NANOBK_TEST_DETECTED_IPV4=203.0.113.10 NANOBK_TEST_DETECTED_IPV6=2001:db8::10 \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-summary-proxy-available-web-conflict.json" \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --json 2>&1)

check_json "15" "IPv4 detected" "$JSON_IP" "d['vps_ip']['ipv4']['status']" "detected"
check_json "16" "IPv6 detected" "$JSON_IP" "d['vps_ip']['ipv6']['status']" "detected"

# 17 — IPv4 masked (203.0.113.10 -> 203.0.113.xxx)
check_json "17" "IPv4 masked" "$JSON_IP" "d['vps_ip']['ipv4']['masked']" "203.0.113.xxx"

# 18 — both failed
JSON_IP_FAIL=$(NANOBK_TEST_DETECT_IPV4_FAIL=1 NANOBK_TEST_DETECT_IPV6_FAIL=1 \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --json 2>&1)
check_json "18" "both failed -> next_step manual_ip_input" "$JSON_IP_FAIL" "d['next_step']" "manual_ip_input"

echo ""
echo "=== E. Subdomain availability ==="

# 19-24 — proxy available, web conflict (from fixture)
JSON_SUB=$(NANOBK_TEST_DETECTED_IPV4=203.0.113.10 NANOBK_TEST_DETECTED_IPV6=2001:db8::10 \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-summary-proxy-available-web-conflict.json" \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --json 2>&1)

# Fixture: proxy has empty result (available), web has A record (occupied)
check_json "19" "proxy available" "$JSON_SUB" "d['subdomains']['proxy']['status']" "available"
check_json "20" "web occupied" "$JSON_SUB" "d['subdomains']['web']['status']" "occupied"

# 21 — planned records exist (proxy available → A record planned)
RECORD_COUNT=$(echo "$JSON_SUB" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('planned_records', [])))" 2>/dev/null || echo "0")
if [[ "$RECORD_COUNT" -ge 1 ]]; then
  ok "21: planned proxy record exists"
else
  fail "21: planned proxy record missing (count=$RECORD_COUNT)"
fi

# 22 — planned records include proxy.example.com A record
if echo "$JSON_SUB" | python3 -c "
import sys, json
d = json.load(sys.stdin)
names = [r['name'] for r in d.get('planned_records', [])]
assert 'proxy.example.com' in names
" 2>/dev/null; then
  ok "22: planned record for proxy.example.com"
else
  fail "22: planned record for proxy.example.com missing"
fi

# 23 — blocked true (because web is occupied)
check_json "23" "blocked true" "$JSON_SUB" "d['blocked']" "True"

# 24 — next_step custom_subdomain
check_json "24" "next_step custom_subdomain" "$JSON_SUB" "d['next_step']" "custom_subdomain"

echo ""
echo "=== F. Conflict ==="

# 25-27 — check text output for conflict message
TEXT_SUB=$(NANOBK_TEST_DETECTED_IPV4=203.0.113.10 \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-summary-proxy-available-web-conflict.json" \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" 2>&1)

if echo "$TEXT_SUB" | grep -q "已经被用了"; then
  ok "25: text says 这个名字已经被用了"
else
  fail "25: text missing conflict message"
fi

# 26
if echo "$TEXT_SUB" | grep -q "不会覆盖"; then
  ok "26: text says 不会覆盖"
else
  fail "26: text missing 不会覆盖"
fi

# 27
if echo "$TEXT_SUB" | grep -q "不会删除"; then
  ok "27: text says 不会删除"
else
  fail "27: text missing 不会删除"
fi

# 28 — no DNS apply command executed
if echo "$TEXT_SUB" | grep -qi "dns apply.*--yes\|cf dns apply"; then
  fail "28: text contains DNS apply command"
else
  ok "28: no DNS apply command in text"
fi

echo ""
echo "=== G. Custom subdomain ==="

# 29 — --proxy-subdomain p2
JSON_CUSTOM=$(NANOBK_TEST_DETECTED_IPV4=203.0.113.10 \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-empty.json" \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --proxy-subdomain p2 --json 2>&1)

if echo "$JSON_CUSTOM" | python3 -c "
import sys, json
d = json.load(sys.stdin)
subs = d.get('subdomains', {})
assert 'p2' in subs, f'p2 not in {list(subs.keys())}'
assert subs['p2']['name'] == 'p2.example.com'
" 2>/dev/null; then
  ok "29: --proxy-subdomain p2 produces p2.example.com"
else
  fail "29: custom proxy subdomain not applied"
fi

# 30 — --web-subdomain panel
JSON_CUSTOM2=$(NANOBK_TEST_DETECTED_IPV4=203.0.113.10 \
  NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-empty.json" \
  "$NANOBK" setup production dns --zone example.com --api-env "$FAKE_ENV" --web-subdomain panel --json 2>&1)

if echo "$JSON_CUSTOM2" | python3 -c "
import sys, json
d = json.load(sys.stdin)
subs = d.get('subdomains', {})
assert 'panel' in subs, f'panel not in {list(subs.keys())}'
assert subs['panel']['name'] == 'panel.example.com'
" 2>/dev/null; then
  ok "30: --web-subdomain panel produces panel.example.com"
else
  fail "30: custom web subdomain not applied"
fi

# 31 — save writes local plan (use --save flag)
"$NANOBK" setup production dns --save --zone test.example.com --proxy-subdomain px --web-subdomain wx >/dev/null 2>&1
PLAN_PATH="$HOME/.nanobk/production-dns-plan.json"
if [[ -f "$PLAN_PATH" ]]; then
  ok "31: save writes local plan"
else
  fail "31: plan not created"
fi

# 32 — plan chmod 600
if [[ -f "$PLAN_PATH" ]]; then
  PERMS=$(stat -c '%a' "$PLAN_PATH" 2>/dev/null || stat -f '%Lp' "$PLAN_PATH" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    ok "32: plan chmod 600"
  else
    fail "32: plan perms=$PERMS (expected 600)"
  fi
else
  fail "32: plan not found"
fi

echo ""
echo "=== H. JSON safety ==="

ALL_JSON="$JSON
$JSON_CF
$JSON_IP
$JSON_SUB
$JSON_CUSTOM
$JSON_CUSTOM2"

check_no "33" "no CF_API_TOKEN" "$ALL_JSON" "CF_API_TOKEN"
check_no "34" "no ADMIN_TOKEN" "$ALL_JSON" "ADMIN_TOKEN"
check_no "35" "no SUB_TOKEN" "$ALL_JSON" "SUB_TOKEN"
check_no "36" "no PRIVATE KEY" "$ALL_JSON" "PRIVATE.KEY"
check_no "37" "no subscription URL" "$ALL_JSON" "subscription.*http"
check_no "38" "no zone_id" "$ALL_JSON" "zone_id"
check_no "39" "no record_id" "$ALL_JSON" "record_id"
check_no "40" "no api_env_path" "$ALL_JSON" "api_env_path"
check_no "41" "no api.cloudflare.com/client/v4" "$ALL_JSON" "api.cloudflare.com/client/v4"
check_no "42" "no /dns_records" "$ALL_JSON" "/dns_records"

echo ""
echo "=== I. Source safety ==="

# Check that dangerous constructs are not in executable code (skip comments and docstrings)
check_no_code() {
  local num="$1" label="$2" pattern="$3"
  # Check for the pattern outside of comment lines and docstrings
  if python3 -c "
import ast, sys
with open('$MODULE') as f:
    source = f.read()
tree = ast.parse(source)
# Check all string constants that are NOT docstrings
for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        # Skip docstrings (they are the first statement in a function/class/module body)
        continue
    if isinstance(node, ast.keyword):
        continue
# Check actual code - look for the pattern in non-string, non-comment contexts
import re
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

check_no_code "43" "subprocess import" "import subprocess"
check_no_code "44" "requests import" "import requests"
check_no_code "45" "urlopen import" "import urllib"
check_no_code "46" "POST" "POST"
check_no_code "47" "PATCH" "PATCH"
check_no_code "48" "DELETE" "DELETE"
check_no_code "49" "wrangler deploy" "wrangler.*deploy"
check_no_code "50" "systemctl restart" "systemctl.*restart"
check_no_code "51" "systemctl reload" "systemctl.*reload"
check_no_code "52" "cf dns apply --yes" "cf dns apply.*--yes"

echo ""
echo "=== J. Regression (narrow smoke) ==="

# 53-54: Check prior test files exist (fast, no execution)
for prior in v2.5.1-production-action-plan v2.5.0-production-setup-spine; do
  if [[ -f "$REPO_DIR/tests/${prior}.sh" ]]; then
    ok "prior test file exists: $prior"
  else
    fail "prior test file missing: $prior"
  fi
done

# 55: v2.4.0 scope test passes (fast, standalone)
if [[ -f "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" ]]; then
  if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
    ok "55: v2.4.0 scope test passes"
  else
    fail "55: v2.4.0 scope test fails"
  fi
else
  fail "55: v2.4.0 test file missing"
fi

# 56 — version check
JSON_VER=$("$NANOBK" setup production dns --json 2>&1)
check_json "56" "version == 2.5.2" "$JSON_VER" "d['version']" "2.5.2"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
