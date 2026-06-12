#!/usr/bin/env bash
# v2.5.1 Production Action Plan Test
#
# Tests the production action plan builder.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
SPINE_PY="$REPO_DIR/lib/nanobk_production_setup_spine.py"

PASS=0
FAIL=0

ok()   { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

echo "=== A. Basic commands ==="

# 1
if python3 -m py_compile "$SPINE_PY" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production actions >/dev/null 2>&1; then
  ok "2: nanobk setup production actions exits 0"
else
  fail "2: nanobk setup production actions exits 0"
fi

# 3
if "$NANOBK" setup production actions --json >/dev/null 2>&1; then
  ok "3: nanobk setup production actions --json exits 0"
else
  fail "3: nanobk setup production actions --json exits 0"
fi

# 4
if "$NANOBK" beginner production actions >/dev/null 2>&1; then
  ok "4: nanobk beginner production actions exits 0"
else
  fail "4: nanobk beginner production actions exits 0"
fi

# 5
if "$NANOBK" beginner production actions --json >/dev/null 2>&1; then
  ok "5: nanobk beginner production actions --json exits 0"
else
  fail "5: nanobk beginner production actions --json exits 0"
fi

echo ""
echo "=== B. JSON schema ==="

JSON=$("$NANOBK" setup production actions --json 2>&1)

check_field() {
  local num="$1" label="$2" expr="$3" expected="$4"
  local actual
  actual=$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$num: $label"
  else
    fail "$num: $label (expected '$expected', got '$actual')"
  fi
}

# 6
check_field "6" "JSON ok == true" "d['ok']" "True"
# 7
check_field "7" "JSON mode == production_actions_v2_5" "d['mode']" "production_actions_v2_5"
# 8
check_field "8" "JSON version == 2.5.1" "d['version']" "2.5.1"
# 9
check_field "9" "JSON mutation == false" "d['mutation']" "False"
# 10
check_field "10" "JSON dangerous_actions_executed == false" "d['dangerous_actions_executed']" "False"
# 11
check_field "11" "JSON safety == read_only" "d['safety']" "read_only"

# 12
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d['actions'], list)" 2>/dev/null; then
  ok "12: JSON has actions array"
else
  fail "12: JSON missing actions array"
fi

echo ""
echo "=== C. Required actions present ==="

check_action() {
  local num="$1" action_id="$2"
  if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = [a['id'] for a in d['actions']]
assert '$action_id' in ids
" 2>/dev/null; then
    ok "$num: action $action_id exists"
  else
    fail "$num: action $action_id missing"
  fi
}

# 13-24
check_action "13" "cloudflare_login"
check_action "14" "domain_select"
check_action "15" "vps_ip_detect"
check_action "16" "subdomain_plan"
check_action "17" "dns_apply_gate"
check_action "18" "cert_issue_gate"
check_action "19" "vps_four_protocols"
check_action "20" "worker_nanok"
check_action "21" "worker_nanob"
check_action "22" "subscription_token"
check_action "23" "protocol_key_rotation"
check_action "24" "final_status"

echo ""
echo "=== D. Command mapping ==="

TEXT=$("$NANOBK" setup production actions 2>&1)

check_text() {
  local num="$1" pattern="$2"
  if echo "$TEXT" | grep -qF "$pattern"; then
    ok "$num: output mentions $pattern"
  else
    fail "$num: output missing $pattern"
  fi
}

# 25-38
check_text "25" "nanobk cf connect"
check_text "26" "nanobk beginner ip"
check_text "27" "nanobk beginner subdomain"
check_text "28" "nanobk setup dns apply"
check_text "29" "nanobk setup cert issue"
check_text "30" "nanobk setup token rotate"
check_text "31" "nanobk install --mode vps"
check_text "32" "nanobk install --mode cloudflare"
check_text "33" "nanobk install --mode full"
check_text "34" "nanobk rotate all"
check_text "35" "nanobk rotate hy2"
check_text "36" "nanobk rotate tuic"
check_text "37" "nanobk rotate reality"
check_text "38" "nanobk rotate trojan"

echo ""
echo "=== E. Exact phrase gates ==="

# 39
dns_phrase=$(echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d['actions']:
    if a['id'] == 'dns_apply_gate':
        print(a['requires_exact_phrase'])
" 2>/dev/null || echo "ERROR")
if [[ "$dns_phrase" == "True" ]]; then
  ok "39: DNS action requires_exact_phrase == true"
else
  fail "39: DNS action requires_exact_phrase (got '$dns_phrase')"
fi

# 40
cert_phrase=$(echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d['actions']:
    if a['id'] == 'cert_issue_gate':
        print(a['requires_exact_phrase'])
" 2>/dev/null || echo "ERROR")
if [[ "$cert_phrase" == "True" ]]; then
  ok "40: Cert action requires_exact_phrase == true"
else
  fail "40: Cert action requires_exact_phrase (got '$cert_phrase')"
fi

# 41
token_phrase=$(echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d['actions']:
    if a['id'] == 'subscription_token':
        print(a['requires_exact_phrase'])
" 2>/dev/null || echo "ERROR")
if [[ "$token_phrase" == "True" ]]; then
  ok "41: Token action requires_exact_phrase == true"
else
  fail "41: Token action requires_exact_phrase (got '$token_phrase')"
fi

# 42-44: check exact phrases are present in JSON
if echo "$JSON" | grep -qF "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"; then
  ok "42: DNS exact phrase present"
else
  fail "42: DNS exact phrase missing"
fi

if echo "$JSON" | grep -qF "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"; then
  ok "43: Cert exact phrase present"
else
  fail "43: Cert exact phrase missing"
fi

if echo "$JSON" | grep -qF "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"; then
  ok "44: Token exact phrase present"
else
  fail "44: Token exact phrase missing"
fi

echo ""
echo "=== F. Safety ==="

# 45-54: JSON safety
ALL="$JSON
$TEXT"

check_no() {
  local num="$1" label="$2" pattern="$3"
  if echo "$ALL" | grep -qi "$pattern"; then
    fail "$num: $label found"
  else
    ok "$num: $label not found"
  fi
}

check_no "45" "CF_API_TOKEN" "CF_API_TOKEN"
check_no "46" "ADMIN_TOKEN" "ADMIN_TOKEN"
check_no "47" "SUB_TOKEN" "SUB_TOKEN"
check_no "48" "PRIVATE KEY" "PRIVATE.KEY"
check_no "49" "subscription URL" "subscription.*http"
check_no "50" "zone_id" "zone_id"
check_no "51" "record_id" "record_id"
check_no "52" "api_env_path" "api_env_path"
check_no "53" "api.cloudflare.com/client/v4" "api.cloudflare.com/client/v4"
check_no "54" "/dns_records" "/dns_records"

# 55-61: module safety
check_no_module() {
  local num="$1" label="$2" pattern="$3"
  if grep -qi "$pattern" "$SPINE_PY" 2>/dev/null; then
    fail "$num: $label found in module"
  else
    ok "$num: $label not in module"
  fi
}

check_no_module "55" "subprocess import" "import subprocess"
check_no_module "56" "requests import" "import requests"
check_no_module "57" "urlopen import" "import urllib"
check_no_module "58" "systemctl restart" "systemctl.*restart"
check_no_module "59" "systemctl reload" "systemctl.*reload"
check_no_module "60" "wrangler deploy" "wrangler.*deploy"
check_no_module "61" "cf dns apply --yes" "cf dns apply.*--yes"

echo ""
echo "=== G. Regression ==="

# 62
if bash "$REPO_DIR/tests/v2.5.0-production-setup-spine.sh" >/dev/null 2>&1; then
  ok "62: v2.5.0 test passes"
else
  fail "62: v2.5.0 test fails"
fi

# 63
if bash "$REPO_DIR/tests/v2.4.7-closeout-manifest.sh" >/dev/null 2>&1; then
  ok "63: v2.4.7 test passes"
else
  fail "63: v2.4.7 test fails"
fi

# 64
if bash "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then
  ok "64: v2.4.5 test passes"
else
  fail "64: v2.4.5 test fails"
fi

# 65
if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
  ok "65: v2.4.0 test passes"
else
  fail "65: v2.4.0 test fails"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
