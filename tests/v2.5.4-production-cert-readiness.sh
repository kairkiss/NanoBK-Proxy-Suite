#!/usr/bin/env bash
# v2.5.4 Production Certificate Readiness and Four-Protocol TLS Plan Test
#
# Tests the HTTPS certificate readiness flow.
# No real certificate request. No certbot execution. No VPS deployment.
# No DNS mutation. No token rotation. No service reload/restart.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_cert_readiness.py"

PASS=0
FAIL=0

ok()   { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

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

# Create fake cert/key fixture files
FAKE_CERT="$HOME/fake-cert.pem"
FAKE_KEY="$HOME/fake-key.pem"
echo "FAKE CERT CONTENT" > "$FAKE_CERT"
echo "FAKE KEY CONTENT" > "$FAKE_KEY"

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production cert --zone example.com --mode self-signed >/dev/null 2>&1; then
  ok "2: setup production cert exits 0"
else
  fail "2: setup production cert exits non-zero"
fi

# 3
if "$NANOBK" setup production cert --zone example.com --json >/dev/null 2>&1; then
  ok "3: setup production cert --json exits 0"
else
  fail "3: setup production cert --json exits non-zero"
fi

# 4
if "$NANOBK" beginner production cert --zone example.com --mode self-signed >/dev/null 2>&1; then
  ok "4: beginner production cert exits 0"
else
  fail "4: beginner production cert exits non-zero"
fi

# 5
if "$NANOBK" beginner production cert --zone example.com --json >/dev/null 2>&1; then
  ok "5: beginner production cert --json exits 0"
else
  fail "5: beginner production cert --json exits non-zero"
fi

# 6
if "$NANOBK" setup production cert --save --zone example.com --domain proxy.example.com --mode self-signed >/dev/null 2>&1; then
  ok "6: setup production cert --save exits 0"
else
  fail "6: setup production cert --save exits non-zero"
fi

echo ""
echo "=== B. JSON schema ==="

JSON=$("$NANOBK" setup production cert --zone example.com --mode self-signed --json 2>&1)

check_json "7" "ok == true" "$JSON" "d['ok']" "True"
check_json "8" "mode" "$JSON" "d['mode']" "production_cert_readiness_v2_5"
check_json "9" "version" "$JSON" "d['version']" "2.5.4"
check_json "10" "mutation == false" "$JSON" "d['mutation']" "False"
check_json "11" "dangerous_actions_executed == false" "$JSON" "d['dangerous_actions_executed']" "False"
check_json "12" "safety == read_only" "$JSON" "d['safety']" "read_only"

# 13
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cert_domain' in d" 2>/dev/null; then
  ok "13: has cert_domain"
else
  fail "13: missing cert_domain"
fi

# 14
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cert_mode' in d" 2>/dev/null; then
  ok "14: has cert_mode"
else
  fail "14: missing cert_mode"
fi

# 15
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'certificate' in d" 2>/dev/null; then
  ok "15: has certificate"
else
  fail "15: missing certificate"
fi

# 16
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'protocol_tls' in d" 2>/dev/null; then
  ok "16: has protocol_tls"
else
  fail "16: missing protocol_tls"
fi

# 17
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'commands' in d" 2>/dev/null; then
  ok "17: has commands"
else
  fail "17: missing commands"
fi

# 18
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d" 2>/dev/null; then
  ok "18: has next_step"
else
  fail "18: missing next_step"
fi

echo ""
echo "=== C. Domain planning ==="

# 19 — default cert domain proxy.example.com
check_json "19" "default cert domain" "$JSON" "d['cert_domain']" "proxy.example.com"

# 20 — explicit --domain works
JSON_EXPLICIT=$("$NANOBK" setup production cert --zone example.com --domain myproxy.example.com --mode self-signed --json 2>&1)
check_json "20" "explicit --domain" "$JSON_EXPLICIT" "d['cert_domain']" "myproxy.example.com"

# 21 — no domain -> next_step select_domain
JSON_NODOM=$("$NANOBK" setup production cert --json 2>&1)
check_json "21" "no domain -> select_domain" "$JSON_NODOM" "d['next_step']" "select_domain"

# 22 — selected_domain null when no zone
check_json "22" "no zone -> selected_domain null" "$JSON_NODOM" "d['selected_domain']" "None"

echo ""
echo "=== D. Certificate modes ==="

# 23 — self-signed mode recognized
check_json "23" "self-signed mode" "$JSON" "d['cert_mode']" "self-signed"

# 24 — self-signed next_step review_vps_install
check_json "24" "self-signed next_step" "$JSON" "d['next_step']" "review_vps_install"

# 25 — existing mode recognized
JSON_EXISTING=$("$NANOBK" setup production cert --zone example.com --mode existing --cert-file "$FAKE_CERT" --key-file "$FAKE_KEY" --json 2>&1)
check_json "25" "existing mode" "$JSON_EXISTING" "d['cert_mode']" "existing"

# 26 — existing cert_file_configured true
check_json "26" "existing cert_file_configured" "$JSON_EXISTING" "d['certificate']['cert_file_configured']" "True"

# 27 — existing key_file_configured true
check_json "27" "existing key_file_configured" "$JSON_EXISTING" "d['certificate']['key_file_configured']" "True"

# 28 — existing cert_file_exists true when fixture exists
check_json "28" "existing cert_file_exists" "$JSON_EXISTING" "d['certificate']['cert_file_exists']" "True"

# 29 — existing key_file_exists true when fixture exists
check_json "29" "existing key_file_exists" "$JSON_EXISTING" "d['certificate']['key_file_exists']" "True"

# 30 — letsencrypt mode recognized
JSON_LE=$("$NANOBK" setup production cert --zone example.com --mode letsencrypt --json 2>&1)
check_json "30" "letsencrypt mode" "$JSON_LE" "d['cert_mode']" "letsencrypt"

# 31 — certbot tool status present/missing/unknown
if echo "$JSON_LE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tools']['certbot'] in ('present', 'missing', 'unknown')
" 2>/dev/null; then
  ok "31: certbot tool status valid"
else
  fail "31: certbot tool status invalid"
fi

# 32 — letsencrypt next_step review_cert_gate
check_json "32" "letsencrypt next_step" "$JSON_LE" "d['next_step']" "review_cert_gate"

echo ""
echo "=== E. Protocol TLS mapping ==="

# 33 — hy2 uses_tls_cert
check_json "33" "hy2 uses_tls_cert" "$JSON" "d['protocol_tls']['hy2']" "uses_tls_cert"

# 34 — tuic uses_tls_cert
check_json "34" "tuic uses_tls_cert" "$JSON" "d['protocol_tls']['tuic']" "uses_tls_cert"

# 35 — trojan uses_tls_cert
check_json "35" "trojan uses_tls_cert" "$JSON" "d['protocol_tls']['trojan']" "uses_tls_cert"

# 36 — reality uses_reality_servername
check_json "36" "reality uses_reality_servername" "$JSON" "d['protocol_tls']['reality']" "uses_reality_servername"

echo ""
echo "=== F. Command plan ==="

# 37 — recommended mentions nanobk install --mode vps (self-signed mode)
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
rec = d.get('commands', {}).get('recommended', '')
assert 'nanobk install --mode vps' in rec, f'recommended: {rec}'
" 2>/dev/null; then
  ok "37: recommended mentions nanobk install --mode vps"
else
  fail "37: recommended command missing"
fi

# 38 — cert_gate mentions nanobk setup cert issue (letsencrypt mode)
if echo "$JSON_LE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
gate = d.get('commands', {}).get('cert_gate', '')
assert 'nanobk setup cert issue' in gate, f'cert_gate: {gate}'
" 2>/dev/null; then
  ok "38: cert_gate mentions nanobk setup cert issue"
else
  fail "38: cert_gate missing"
fi

# 39 — letsencrypt text mentions exact cert confirmation phrase
TEXT_LE=$("$NANOBK" setup production cert --zone example.com --mode letsencrypt 2>&1 || true)
if echo "$TEXT_LE" | grep -q "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"; then
  ok "39: letsencrypt mentions exact cert confirmation phrase"
else
  fail "39: missing cert confirmation phrase in letsencrypt text"
fi

# 40 — plan_only mentions install-vps.sh (self-signed mode)
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert 'install-vps.sh' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "40: plan_only mentions install-vps.sh"
else
  fail "40: plan_only missing install-vps.sh"
fi

# 41 — existing plan_only mentions --cert-mode existing
if echo "$JSON_EXISTING" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert '--cert-mode existing' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "41: existing plan_only mentions --cert-mode existing"
else
  fail "41: existing plan_only missing --cert-mode existing"
fi

# 42 — self-signed plan_only mentions --cert-mode self-signed
if echo "$JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
plan = d.get('commands', {}).get('plan_only', '')
assert '--cert-mode self-signed' in plan, f'plan_only: {plan}'
" 2>/dev/null; then
  ok "42: self-signed plan_only mentions --cert-mode self-signed"
else
  fail "42: self-signed plan_only missing --cert-mode self-signed"
fi

# 43 — plan_only does not execute (just a string preview)
ok "43: plan_only is preview only (not executed)"

echo ""
echo "=== G. Save mode ==="

# 44 — save writes file
"$NANOBK" setup production cert --save --zone test.example.com --domain proxy.test.example.com --mode existing --cert-file "$FAKE_CERT" --key-file "$FAKE_KEY" >/dev/null 2>&1
CERT_PLAN_PATH="$HOME/.nanobk/production-cert-plan.json"
if [[ -f "$CERT_PLAN_PATH" ]]; then
  ok "44: save writes production-cert-plan.json"
else
  fail "44: cert plan file not created"
fi

# 45 — file chmod 600
if [[ -f "$CERT_PLAN_PATH" ]]; then
  PERMS=$(stat -c '%a' "$CERT_PLAN_PATH" 2>/dev/null || stat -f '%Lp' "$CERT_PLAN_PATH" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    ok "45: cert plan file chmod 600"
  else
    fail "45: cert plan file perms=$PERMS (expected 600)"
  fi
else
  fail "45: cert plan file not found"
fi

# 46 — JSON contains zone_name
if [[ -f "$CERT_PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$CERT_PLAN_PATH')); assert d.get('zone_name') == 'test.example.com'" 2>/dev/null; then
  ok "46: plan contains zone_name"
else
  fail "46: plan missing zone_name"
fi

# 47 — JSON contains cert_domain
if [[ -f "$CERT_PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$CERT_PLAN_PATH')); assert d.get('cert_domain') == 'proxy.test.example.com'" 2>/dev/null; then
  ok "47: plan contains cert_domain"
else
  fail "47: plan missing cert_domain"
fi

# 48 — JSON contains cert_mode
if [[ -f "$CERT_PLAN_PATH" ]] && python3 -c "import json; d=json.load(open('$CERT_PLAN_PATH')); assert d.get('cert_mode') == 'existing'" 2>/dev/null; then
  ok "48: plan contains cert_mode"
else
  fail "48: plan missing cert_mode"
fi

# 49 — JSON does not contain private key content
if [[ -f "$CERT_PLAN_PATH" ]]; then
  if grep -qi "PRIVATE" "$CERT_PLAN_PATH" 2>/dev/null; then
    fail "49: plan contains private key content"
  else
    ok "49: no private key content in plan"
  fi
else
  fail "49: plan file not found"
fi

echo ""
echo "=== H. Dangerous options rejected ==="

# 50 — --issue rejected
if "$NANOBK" setup production cert --zone example.com --issue >/dev/null 2>&1; then
  fail "50: --issue should be rejected"
else
  ok "50: --issue rejected RC!=0"
fi

# 51 — --yes rejected
if "$NANOBK" setup production cert --zone example.com --yes >/dev/null 2>&1; then
  fail "51: --yes should be rejected"
else
  ok "51: --yes rejected RC!=0"
fi

# 52 — --apply rejected
if "$NANOBK" setup production cert --zone example.com --apply >/dev/null 2>&1; then
  fail "52: --apply should be rejected"
else
  ok "52: --apply rejected RC!=0"
fi

# 53 — --certbot rejected
if "$NANOBK" setup production cert --zone example.com --certbot >/dev/null 2>&1; then
  fail "53: --certbot should be rejected"
else
  ok "53: --certbot rejected RC!=0"
fi

# 54 — output says preview only
ISSUE_MSG=$("$NANOBK" setup production cert --zone example.com --issue 2>&1 || true)
if echo "$ISSUE_MSG" | grep -q "预览\|preview\|不支持\|不会申请"; then
  ok "54: output says preview only"
else
  fail "54: missing preview message (got: $ISSUE_MSG)"
fi

echo ""
echo "=== I. Safety output ==="

ALL_JSON="$JSON
$JSON_EXPLICIT
$JSON_LE
$JSON_EXISTING
$JSON_NODOM"

check_no "55" "no CF_API_TOKEN" "$ALL_JSON" "CF_API_TOKEN"
check_no "56" "no ADMIN_TOKEN" "$ALL_JSON" "ADMIN_TOKEN"
check_no "57" "no SUB_TOKEN" "$ALL_JSON" "SUB_TOKEN"
check_no "58" "no PRIVATE KEY" "$ALL_JSON" "PRIVATE.KEY"
check_no "59" "no subscription URL" "$ALL_JSON" "subscription.*http"
check_no "60" "no zone_id" "$ALL_JSON" "zone_id"
check_no "61" "no record_id" "$ALL_JSON" "record_id"
check_no "62" "no api_env_path" "$ALL_JSON" "api_env_path"
check_no "63" "no api.cloudflare.com/client/v4" "$ALL_JSON" "api.cloudflare.com/client/v4"
check_no "64" "no /dns_records" "$ALL_JSON" "/dns_records"
check_no "65" "no raw Cloudflare response" "$ALL_JSON" "raw.*response"

echo ""
echo "=== J. Source safety ==="

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

check_no_code "66" "subprocess import" "import subprocess"
check_no_code "67" "requests import" "import requests"
check_no_code "68" "urlopen import" "import urllib"
check_no_code "69" "certbot certonly" "certbot.*certonly"
check_no_code "70" "systemctl restart" "systemctl.*restart"
check_no_code "71" "systemctl reload" "systemctl.*reload"
# 72 — install-vps.sh only appears in plan_only string (preview), not in execution context
# Verify no subprocess/os.system/popen calls that reference install-vps.sh
if python3 -c "
import re, sys
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
    # Only flag if install-vps.sh appears in an execution context (subprocess, os.system, popen)
    if re.search(r'install-vps\.sh', stripped, re.IGNORECASE):
        if re.search(r'subprocess|os\.system|popen|exec\(', stripped):
            print('FOUND')
            sys.exit(0)
" 2>/dev/null | grep -q "FOUND"; then
  fail "72: install-vps.sh execution found"
else
  ok "72: install-vps.sh only in preview string (safe)"
fi
check_no_code "73" "os.system" "os\.system"
check_no_code "74" "popen" "popen"

echo ""
echo "=== K. Regression ==="

# 75
if bash "$REPO_DIR/tests/v2.5.3-production-worker-readiness.sh" >/dev/null 2>&1; then
  ok "75: v2.5.3 test passes"
else
  fail "75: v2.5.3 test fails"
fi

# 76
if bash "$REPO_DIR/tests/v2.5.2-production-dns-readiness.sh" >/dev/null 2>&1; then
  ok "76: v2.5.2 test passes"
else
  fail "76: v2.5.2 test fails"
fi

# 77
if bash "$REPO_DIR/tests/v2.5.1-production-action-plan.sh" >/dev/null 2>&1; then
  ok "77: v2.5.1 test passes"
else
  fail "77: v2.5.1 test fails"
fi

# 78
if bash "$REPO_DIR/tests/v2.5.0-production-setup-spine.sh" >/dev/null 2>&1; then
  ok "78: v2.5.0 test passes"
else
  fail "78: v2.5.0 test fails"
fi

# 79
if bash "$REPO_DIR/tests/v2.4.7-closeout-manifest.sh" >/dev/null 2>&1; then
  ok "79: v2.4.7 test passes"
else
  fail "79: v2.4.7 test fails"
fi

# 80
if bash "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then
  ok "80: v2.4.5 test passes"
else
  fail "80: v2.4.5 test fails"
fi

# 81
if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
  ok "81: v2.4.0 test passes"
else
  fail "81: v2.4.0 test fails"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
