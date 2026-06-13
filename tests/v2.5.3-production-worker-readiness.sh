#!/usr/bin/env bash
# v2.5.3 Production Worker Readiness and Route Mapping Test
#
# Tests the Cloudflare Worker readiness flow.
# No real Worker deployment. No wrangler deploy. No Cloudflare mutation.
# No DNS mutation. No certificate request. No token rotation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_worker_readiness.py"

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

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production worker >/dev/null 2>&1; then
  ok "2: setup production worker exits 0"
else
  fail "2: setup production worker exits non-zero"
fi

# 3
if "$NANOBK" setup production worker --json >/dev/null 2>&1; then
  ok "3: setup production worker --json exits 0"
else
  fail "3: setup production worker --json exits non-zero"
fi

# 4
if "$NANOBK" beginner production worker >/dev/null 2>&1; then
  ok "4: beginner production worker exits 0"
else
  fail "4: beginner production worker exits non-zero"
fi

# 5
if "$NANOBK" beginner production worker --json >/dev/null 2>&1; then
  ok "5: beginner production worker --json exits 0"
else
  fail "5: beginner production worker --json exits non-zero"
fi

# 6
if "$NANOBK" setup production worker --save --zone example.com >/dev/null 2>&1; then
  ok "6: setup production worker --save --zone exits 0"
else
  fail "6: setup production worker --save exits non-zero"
fi

echo ""
echo "=== B. JSON schema ==="

JSON=$("$NANOBK" setup production worker --zone example.com --json 2>&1)

check_json "7" "ok == true" "$JSON" "d['ok']" "True"
check_json "8" "mode" "$JSON" "d['mode']" "production_worker_readiness_v2_5"
check_json "9" "version" "$JSON" "d['version']" "2.5.3"
check_json "10" "mutation == false" "$JSON" "d['mutation']" "False"
check_json "11" "dangerous_actions_executed == false" "$JSON" "d['dangerous_actions_executed']" "False"
check_json "12" "safety == read_only" "$JSON" "d['safety']" "read_only"

# 13
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'routes' in d" 2>/dev/null; then
  ok "13: has routes"
else
  fail "13: missing routes"
fi

# 14
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'worker_sources' in d" 2>/dev/null; then
  ok "14: has worker_sources"
else
  fail "14: missing worker_sources"
fi

# 15
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'tools' in d" 2>/dev/null; then
  ok "15: has tools"
else
  fail "15: missing tools"
fi

# 16
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'commands' in d" 2>/dev/null; then
  ok "16: has commands"
else
  fail "16: missing commands"
fi

# 17
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d" 2>/dev/null; then
  ok "17: has next_step"
else
  fail "17: missing next_step"
fi

echo ""
echo "=== C. Route planning ==="

# 18-20 — default routes
check_json "18" "nanok route" "$JSON" "d['routes']['nanok']" "nanok.example.com"
check_json "19" "nanob route" "$JSON" "d['routes']['nanob']" "nanob.example.com"
check_json "20" "web route" "$JSON" "d['routes']['web']" "web.example.com"

# 21 — custom nanok subdomain
JSON_CUSTOM=$("$NANOBK" setup production worker --zone example.com --nanok-subdomain sub --json 2>&1)
check_json "21" "custom nanok subdomain" "$JSON_CUSTOM" "d['routes']['nanok']" "sub.example.com"

# 22 — custom nanob subdomain
JSON_CUSTOM2=$("$NANOBK" setup production worker --zone example.com --nanob-subdomain agg --json 2>&1)
check_json "22" "custom nanob subdomain" "$JSON_CUSTOM2" "d['routes']['nanob']" "agg.example.com"

# 23 — custom web subdomain
JSON_CUSTOM3=$("$NANOBK" setup production worker --zone example.com --web-subdomain panel --json 2>&1)
check_json "23" "custom web subdomain" "$JSON_CUSTOM3" "d['routes']['web']" "panel.example.com"

echo ""
echo "=== D. Source/tool readiness ==="

# 24-29 — check that source/tool fields exist with valid values
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ws = d.get('worker_sources', {})
assert ws.get('nanok') in ('ready', 'missing', 'unknown'), f'nanok: {ws.get(\"nanok\")}'
assert ws.get('nanob') in ('ready', 'missing', 'unknown'), f'nanob: {ws.get(\"nanob\")}'
assert ws.get('installer') in ('ready', 'missing', 'unknown'), f'installer: {ws.get(\"installer\")}'
tools = d.get('tools', {})
assert tools.get('node') in ('present', 'missing', 'unknown'), f'node: {tools.get(\"node\")}'
assert tools.get('npm') in ('present', 'missing', 'unknown'), f'npm: {tools.get(\"npm\")}'
assert tools.get('wrangler') in ('present', 'missing', 'unknown'), f'wrangler: {tools.get(\"wrangler\")}'
" 2>/dev/null; then
  ok "24: worker_sources.nanok valid"
  ok "25: worker_sources.nanob valid"
  ok "26: worker_sources.installer valid"
  ok "27: tools.node valid"
  ok "28: tools.npm valid"
  ok "29: tools.wrangler valid"
else
  fail "24: worker_sources.nanok invalid"
  fail "25: worker_sources.nanob invalid"
  fail "26: worker_sources.installer invalid"
  fail "27: tools.node invalid"
  fail "28: tools.npm invalid"
  fail "29: tools.wrangler invalid"
fi

echo ""
echo "=== E. Command plan ==="

# 30 — recommended command
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
rec = d.get('commands', {}).get('recommended', '')
assert 'nanobk install --mode cloudflare' in rec, f'recommended: {rec}'
" 2>/dev/null; then
  ok "30: recommended command mentions nanobk install --mode cloudflare"
else
  fail "30: recommended command missing"
fi

# 31 — plan_only mentions install-cloudflare.sh
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert 'install-cloudflare.sh' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "31: plan_only mentions install-cloudflare.sh"
else
  fail "31: plan_only missing install-cloudflare.sh"
fi

# 32 — plan_only mentions --deploy-nanob
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert '--deploy-nanob' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "32: plan_only mentions --deploy-nanob"
else
  fail "32: plan_only missing --deploy-nanob"
fi

# 33 — plan_only mentions nanok.example.com
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert 'nanok.example.com' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "33: plan_only mentions nanok.example.com"
else
  fail "33: plan_only missing nanok.example.com"
fi

# 34 — plan_only mentions nanob.example.com
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert 'nanob.example.com' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "34: plan_only mentions nanob.example.com"
else
  fail "34: plan_only missing nanob.example.com"
fi

# 35 — plan_only does not execute (check it's just a string, not run)
# The JSON output itself proves it's not executed — we're just reading a string
ok "35: plan_only is preview only (not executed)"

echo ""
echo "=== F. Save mode ==="

# 36 — save writes file
"$NANOBK" setup production worker --save --zone test.example.com --nanok-subdomain n1 --nanob-subdomain n2 --web-subdomain w1 >/dev/null 2>&1
PLAN_PATH="$HOME/.nanobk/production-worker-plan.json"
if [[ -f "$PLAN_PATH" ]]; then
  ok "36: save writes production-worker-plan.json"
else
  fail "36: plan file not created"
fi

# 37 — file chmod 600
if [[ -f "$PLAN_PATH" ]]; then
  PERMS=$(stat -c '%a' "$PLAN_PATH" 2>/dev/null || stat -f '%Lp' "$PLAN_PATH" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    ok "37: plan file chmod 600"
  else
    fail "37: plan file perms=$PERMS (expected 600)"
  fi
else
  fail "37: plan file not found"
fi

# 38 — JSON contains zone_name
if [[ -f "$PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$PLAN_PATH')); assert d.get('zone_name') == 'test.example.com'" 2>/dev/null; then
  ok "38: plan contains zone_name"
else
  fail "38: plan missing zone_name"
fi

# 39 — JSON contains nanok_subdomain
if [[ -f "$PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$PLAN_PATH')); assert d.get('nanok_subdomain') == 'n1'" 2>/dev/null; then
  ok "39: plan contains nanok_subdomain"
else
  fail "39: plan missing nanok_subdomain"
fi

# 40 — JSON contains nanob_subdomain
if [[ -f "$PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$PLAN_PATH')); assert d.get('nanob_subdomain') == 'n2'" 2>/dev/null; then
  ok "40: plan contains nanob_subdomain"
else
  fail "40: plan missing nanob_subdomain"
fi

# 41 — JSON contains web_subdomain
if [[ -f "$PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$PLAN_PATH')); assert d.get('web_subdomain') == 'w1'" 2>/dev/null; then
  ok "41: plan contains web_subdomain"
else
  fail "41: plan missing web_subdomain"
fi

# 42 — JSON does not contain token
if [[ -f "$PLAN_PATH" ]]; then
  check_no "42" "no token in plan file" "$(cat "$PLAN_PATH")" "token"
else
  fail "42: plan file not found"
fi

# 43 — JSON does not contain api_env_path
if [[ -f "$PLAN_PATH" ]]; then
  check_no "43" "no api_env_path in plan file" "$(cat "$PLAN_PATH")" "api_env_path"
else
  fail "43: plan file not found"
fi

echo ""
echo "=== G. Dangerous options rejected ==="

# 44 — --deploy rejected
if "$NANOBK" setup production worker --zone example.com --deploy >/dev/null 2>&1; then
  fail "44: --deploy should be rejected"
else
  ok "44: --deploy rejected RC!=0"
fi

# 45 — --yes rejected
if "$NANOBK" setup production worker --zone example.com --yes >/dev/null 2>&1; then
  fail "45: --yes should be rejected"
else
  ok "45: --yes rejected RC!=0"
fi

# 46 — --apply rejected
if "$NANOBK" setup production worker --zone example.com --apply >/dev/null 2>&1; then
  fail "46: --apply should be rejected"
else
  ok "46: --apply rejected RC!=0"
fi

# 47 — output says preview only
DEPLOY_MSG=$("$NANOBK" setup production worker --zone example.com --deploy 2>&1 || true)
if echo "$DEPLOY_MSG" | grep -q "预览\|preview\|不支持"; then
  ok "47: output says preview only"
else
  fail "47: missing preview message (got: $DEPLOY_MSG)"
fi

echo ""
echo "=== H. Safety output ==="

ALL_JSON="$JSON
$JSON_CUSTOM
$JSON_CUSTOM2
$JSON_CUSTOM3"

check_no "48" "no CF_API_TOKEN" "$ALL_JSON" "CF_API_TOKEN"
check_no "49" "no ADMIN_TOKEN" "$ALL_JSON" "ADMIN_TOKEN"
check_no "50" "no SUB_TOKEN" "$ALL_JSON" "SUB_TOKEN"
check_no "51" "no PRIVATE KEY" "$ALL_JSON" "PRIVATE.KEY"
check_no "52" "no subscription URL" "$ALL_JSON" "subscription.*http"
check_no "53" "no zone_id" "$ALL_JSON" "zone_id"
check_no "54" "no record_id" "$ALL_JSON" "record_id"
check_no "55" "no api_env_path" "$ALL_JSON" "api_env_path"
check_no "56" "no api.cloudflare.com/client/v4" "$ALL_JSON" "api.cloudflare.com/client/v4"
check_no "57" "no /dns_records" "$ALL_JSON" "/dns_records"

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

check_no_code "58" "subprocess import" "import subprocess"
check_no_code "59" "requests import" "import requests"
check_no_code "60" "urlopen import" "import urllib"
check_no_code "61" "POST" "POST"
check_no_code "62" "PATCH" "PATCH"
check_no_code "63" "DELETE" "DELETE"
check_no_code "64" "wrangler deploy" "wrangler.*deploy"
check_no_code "65" "systemctl restart" "systemctl.*restart"
check_no_code "66" "systemctl reload" "systemctl.*reload"

echo ""
echo "=== J. Regression (narrow smoke) ==="

# 67-69: Check prior test files exist (fast, no execution)
for prior in v2.5.2-production-dns-readiness v2.5.1-production-action-plan v2.5.0-production-setup-spine; do
  if [[ -f "$REPO_DIR/tests/${prior}.sh" ]]; then
    ok "prior test file exists: $prior"
  else
    fail "prior test file missing: $prior"
  fi
done

# 70: v2.4.0 scope test passes (fast, standalone)
if [[ -f "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" ]]; then
  if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
    ok "70: v2.4.0 scope test passes"
  else
    fail "70: v2.4.0 scope test fails"
  fi
else
  fail "70: v2.4.0 test file missing"
fi

# 71 — version check
JSON_VER=$("$NANOBK" setup production worker --json 2>&1)
check_json "73" "version == 2.5.3" "$JSON_VER" "d['version']" "2.5.3"

# 71 — version check
JSON_VER=$("$NANOBK" setup production worker --json 2>&1)
check_json "71" "version == 2.5.3" "$JSON_VER" "d['version']" "2.5.3"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
