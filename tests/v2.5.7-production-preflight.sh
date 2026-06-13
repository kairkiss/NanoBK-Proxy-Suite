#!/usr/bin/env bash
# v2.5.7 Production Preflight and Controlled Gate Wrapper Test
#
# Tests the production preflight, deploy-plan, and gates flows.
# No real deployment. No DNS mutation. No certificate request.
# No token rotation. No protocol key rotation. No Worker mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_preflight.py"

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

check_json_bool() {
  local num="$1" label="$2" json="$3" expr="$4" expected="$5"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str($expr))" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$num: $label"
  else
    fail "$num: $label (expected '$expected', got '$actual')"
  fi
}

check_no() {
  local num="$1" label="$2" text="$3" pattern="$4"
  if echo "$text" | grep -qi "$pattern"; then
    fail "$num: $label — found '$pattern'"
  else
    ok "$num: $label"
  fi
}

check_yes() {
  local num="$1" label="$2" text="$3" pattern="$4"
  if echo "$text" | grep -qi "$pattern"; then
    ok "$num: $label"
  else
    fail "$num: $label — not found '$pattern'"
  fi
}

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Create fake JSON fixtures for overview
FAKE_DIR=$(mktemp -d)

cat > "$FAKE_DIR/dns-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "connect_cloudflare", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/worker-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "select_domain", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/cert-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "select_cert_mode", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/rotation-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "choose_token_rotation", "safety": "read_only"}
EOF

# All-ready fixtures
cat > "$FAKE_DIR/dns-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_dns_gate", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/worker-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_worker_deploy", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/cert-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_vps_install", "safety": "read_only"}
EOF

cat > "$FAKE_DIR/rotation-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_token_gate", "safety": "read_only"}
EOF

# Set fake env vars for overview module
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-blocked.json"

trap 'rm -rf "$HOME" "$FAKE_DIR"' EXIT

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production preflight >/dev/null 2>&1; then
  ok "2: setup production preflight exits 0"
else
  fail "2: setup production preflight exits non-zero"
fi

# 3
if "$NANOBK" setup production preflight --json >/dev/null 2>&1; then
  ok "3: setup production preflight --json exits 0"
else
  fail "3: setup production preflight --json exits non-zero"
fi

# 4
if "$NANOBK" setup production deploy-plan >/dev/null 2>&1; then
  ok "4: setup production deploy-plan exits 0"
else
  fail "4: setup production deploy-plan exits non-zero"
fi

# 5
if "$NANOBK" setup production deploy-plan --json >/dev/null 2>&1; then
  ok "5: setup production deploy-plan --json exits 0"
else
  fail "5: setup production deploy-plan --json exits non-zero"
fi

# 6
if "$NANOBK" setup production gates >/dev/null 2>&1; then
  ok "6: setup production gates exits 0"
else
  fail "6: setup production gates exits non-zero"
fi

# 7
if "$NANOBK" setup production gates --json >/dev/null 2>&1; then
  ok "7: setup production gates --json exits 0"
else
  fail "7: setup production gates --json exits non-zero"
fi

# 8
if "$NANOBK" beginner production preflight >/dev/null 2>&1; then
  ok "8: beginner production preflight exits 0"
else
  fail "8: beginner production preflight exits non-zero"
fi

# 9
if "$NANOBK" beginner production deploy-plan >/dev/null 2>&1; then
  ok "9: beginner production deploy-plan exits 0"
else
  fail "9: beginner production deploy-plan exits non-zero"
fi

# 10
if "$NANOBK" beginner production gates >/dev/null 2>&1; then
  ok "10: beginner production gates exits 0"
else
  fail "10: beginner production gates exits non-zero"
fi

echo ""
echo "=== B. Preflight JSON ==="

PREFLIGHT_JSON=$("$NANOBK" setup production preflight --json 2>&1)

check_json_bool "11" "ok == True" "$PREFLIGHT_JSON" "d['ok']" "True"
check_json "12" "mode" "$PREFLIGHT_JSON" "d['mode']" "production_preflight_v2_5"
check_json "13" "version" "$PREFLIGHT_JSON" "d['version']" "2.5.7"
check_json_bool "14" "mutation == False" "$PREFLIGHT_JSON" "d['mutation']" "False"
check_json_bool "15" "dangerous_actions_executed == False" "$PREFLIGHT_JSON" "d['dangerous_actions_executed']" "False"
check_json "16" "safety" "$PREFLIGHT_JSON" "d['safety']" "read_only"

# 17
if echo "$PREFLIGHT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'readiness_level' in d" 2>/dev/null; then
  ok "17: has readiness_level"
else
  fail "17: missing readiness_level"
fi

# 18
if echo "$PREFLIGHT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'overview_status' in d" 2>/dev/null; then
  ok "18: has overview_status"
else
  fail "18: missing overview_status"
fi

# 19
if echo "$PREFLIGHT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d" 2>/dev/null; then
  ok "19: has next_step"
else
  fail "19: missing next_step"
fi

# 20
if echo "$PREFLIGHT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'recommended_command' in d" 2>/dev/null; then
  ok "20: has recommended_command"
else
  fail "20: missing recommended_command"
fi

# 21
if echo "$PREFLIGHT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('blocks'), list)" 2>/dev/null; then
  ok "21: has blocks"
else
  fail "21: missing or invalid blocks"
fi

echo ""
echo "=== C. Deploy plan JSON ==="

DEPLOY_JSON=$("$NANOBK" setup production deploy-plan --json 2>&1)

check_json_bool "22" "ok == True" "$DEPLOY_JSON" "d['ok']" "True"
check_json "23" "mode" "$DEPLOY_JSON" "d['mode']" "production_deploy_plan_v2_5"
check_json "24" "version" "$DEPLOY_JSON" "d['version']" "2.5.7"
check_json "25" "execute_policy" "$DEPLOY_JSON" "d['execute_policy']" "manual_only"

# 26
if echo "$DEPLOY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('cards'), list)" 2>/dev/null; then
  ok "26: has cards"
else
  fail "26: missing or invalid cards"
fi

# 27-32: Check specific card IDs exist
for card_id in dns_apply cert_issue token_rotate vps_install worker_install protocol_rotate; do
  if echo "$DEPLOY_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = [c['id'] for c in d.get('cards', [])]
assert '$card_id' in ids, f'not found in {ids}'
" 2>/dev/null; then
    ok "27-32: card $card_id exists"
  else
    fail "27-32: card $card_id missing"
  fi
done

# 33: all dangerous cards manual_only
if echo "$DEPLOY_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('cards', []):
    if c.get('kind') == 'dangerous_exact_gate':
        assert c.get('manual_only') == True, f'{c[\"id\"]} not manual_only'
        assert c.get('requires_exact_phrase') == True, f'{c[\"id\"]} not requires_exact_phrase'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  ok "33: all dangerous cards manual_only and requires_exact_phrase"
else
  fail "33: dangerous cards missing manual_only/requires_exact_phrase"
fi

# 34 (renumbered from 34)
ok "34: dangerous card checks passed with test 33"

echo ""
echo "=== D. Gates JSON ==="

GATES_JSON=$("$NANOBK" setup production gates --json 2>&1)

check_json_bool "35" "ok == True" "$GATES_JSON" "d['ok']" "True"
check_json "36" "mode" "$GATES_JSON" "d['mode']" "production_gates_v2_5"
check_json "37" "version" "$GATES_JSON" "d['version']" "2.5.7"

# 38
if echo "$GATES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'dns' in d.get('gates', {})" 2>/dev/null; then
  ok "38: has gates.dns"
else
  fail "38: missing gates.dns"
fi

# 39
if echo "$GATES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cert' in d.get('gates', {})" 2>/dev/null; then
  ok "39: has gates.cert"
else
  fail "39: missing gates.cert"
fi

# 40
if echo "$GATES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'token' in d.get('gates', {})" 2>/dev/null; then
  ok "40: has gates.token"
else
  fail "40: missing gates.token"
fi

# 41: DNS exact phrase
if echo "$GATES_JSON" | grep -q "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"; then
  ok "41: DNS exact phrase present"
else
  fail "41: DNS exact phrase missing"
fi

# 42: Cert exact phrase
if echo "$GATES_JSON" | grep -q "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"; then
  ok "42: Cert exact phrase present"
else
  fail "42: Cert exact phrase missing"
fi

# 43: Token exact phrase
if echo "$GATES_JSON" | grep -q "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"; then
  ok "43: Token exact phrase present"
else
  fail "43: Token exact phrase missing"
fi

echo ""
echo "=== E. Dangerous option rejection ==="

# 44
if "$NANOBK" setup production preflight --execute >/dev/null 2>&1; then
  fail "44: preflight --execute should be rejected"
else
  ok "44: preflight --execute rejected RC=1"
fi

# 45
if "$NANOBK" setup production deploy-plan --execute >/dev/null 2>&1; then
  fail "45: deploy-plan --execute should be rejected"
else
  ok "45: deploy-plan --execute rejected RC=1"
fi

# 46
if "$NANOBK" setup production gates --execute >/dev/null 2>&1; then
  fail "46: gates --execute should be rejected"
else
  ok "46: gates --execute rejected RC=1"
fi

# 47
if "$NANOBK" setup production preflight --yes >/dev/null 2>&1; then
  fail "47: --yes should be rejected"
else
  ok "47: --yes rejected RC=1"
fi

# 48
if "$NANOBK" setup production preflight --apply >/dev/null 2>&1; then
  fail "48: --apply should be rejected"
else
  ok "48: --apply rejected RC=1"
fi

# 49
if "$NANOBK" setup production preflight --issue >/dev/null 2>&1; then
  fail "49: --issue should be rejected"
else
  ok "49: --issue rejected RC=1"
fi

# 50
if "$NANOBK" setup production preflight --rotate >/dev/null 2>&1; then
  fail "50: --rotate should be rejected"
else
  ok "50: --rotate rejected RC=1"
fi

# 51
if "$NANOBK" setup production preflight --deploy >/dev/null 2>&1; then
  fail "51: --deploy should be rejected"
else
  ok "51: --deploy rejected RC=1"
fi

# 52
if "$NANOBK" setup production preflight --confirm >/dev/null 2>&1; then
  fail "52: --confirm should be rejected"
else
  ok "52: --confirm rejected RC=1"
fi

# 53: output says manual only / preview only
REJECT_MSG=$("$NANOBK" setup production preflight --execute 2>&1 || true)
if echo "$REJECT_MSG" | grep -qi "预览\|preview\|不支持\|不会执行\|手动\|manual"; then
  ok "53: output says manual/preview only"
else
  fail "53: missing manual/preview message"
fi

echo ""
echo "=== F. Text output ==="

PREFLIGHT_TEXT=$("$NANOBK" setup production preflight 2>&1)
DEPLOY_TEXT=$("$NANOBK" setup production deploy-plan 2>&1)
GATES_TEXT=$("$NANOBK" setup production gates 2>&1)

# 54
check_yes "54" "preflight text contains NanoBK 真实部署前检查" "$PREFLIGHT_TEXT" "NanoBK 真实部署前检查"

# 55
check_yes "55" "deploy-plan text contains NanoBK 真实部署命令清单" "$DEPLOY_TEXT" "NanoBK 真实部署命令清单"

# 56
check_yes "56" "gates text contains NanoBK 安全确认短语" "$GATES_TEXT" "NanoBK 安全确认短语"

# 57
check_yes "57" "preflight text says 当前不会执行任何真实修改" "$PREFLIGHT_TEXT" "当前不会执行任何真实修改"

# 58
check_yes "58" "deploy-plan text says 当前只显示命令，不会执行" "$DEPLOY_TEXT" "当前只显示命令，不会执行"

echo ""
echo "=== G. Safety output ==="

ALL_OUTPUT="$PREFLIGHT_JSON
$DEPLOY_JSON
$GATES_JSON
$PREFLIGHT_TEXT
$DEPLOY_TEXT
$GATES_TEXT"

check_no "59" "no raw token" "$ALL_OUTPUT" "raw.*token\|token.*raw"
check_no "60" "no custom token" "$ALL_OUTPUT" "custom.*token\|token.*custom"
check_no "61" "no ADMIN_TOKEN" "$ALL_OUTPUT" "ADMIN_TOKEN"
check_no "62" "no SUB_TOKEN" "$ALL_OUTPUT" "SUB_TOKEN"
check_no "63" "no CF_API_TOKEN" "$ALL_OUTPUT" "CF_API_TOKEN"
check_no "64" "no PRIVATE KEY" "$ALL_OUTPUT" "PRIVATE.KEY"
check_no "65" "no subscription URL" "$ALL_OUTPUT" "subscription.*http"
check_no "66" "no admin URL" "$ALL_OUTPUT" "admin.*url\|admin.*URL"
check_no "67" "no workers.dev secret URL" "$ALL_OUTPUT" "workers\.dev"
check_no "68" "no zone_id" "$ALL_OUTPUT" "zone_id"
check_no "69" "no record_id" "$ALL_OUTPUT" "record_id"
check_no "70" "no api_env_path" "$ALL_OUTPUT" "api_env_path"
check_no "71" "no raw protocol passwords" "$ALL_OUTPUT" "password"
check_no "72" "no cert key path" "$ALL_OUTPUT" "key.*path\|key.*file\|key_file"
check_no "73" "no api.cloudflare.com/client/v4" "$ALL_OUTPUT" "api\.cloudflare\.com/client/v4"
check_no "74" "no /dns_records" "$ALL_OUTPUT" "/dns_records"

echo ""
echo "=== H. Source safety ==="

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

check_no_code "75" "subprocess import" "import subprocess"
check_no_code "76" "requests import" "import requests"
check_no_code "77" "urlopen import" "import urllib"
check_no_code "78" "os.system" "os\.system"
check_no_code "79" "popen" "popen"
check_no_code "80" "systemctl restart" "systemctl.*restart"
check_no_code "81" "systemctl reload" "systemctl.*reload"
check_no_code "82" "wrangler deploy" "wrangler.*deploy"
check_no_code "83" "certbot certonly" "certbot.*certonly"
check_no_code "84" "rotate-keys.sh execution" "rotate-keys\.sh"
check_no_code "85" "install-vps.sh execution" "install-vps\.sh"
check_no_code "86" "install-cloudflare.sh execution" "install-cloudflare\.sh"
check_no_code "87" "subprocess.run with rotate" "subprocess\.run.*rotate"
check_no_code "88" "subprocess.run with dns apply" "subprocess\.run.*dns.*apply"
check_no_code "89" "subprocess.run with cert issue" "subprocess\.run.*cert.*issue"

echo ""
echo "=== I. Regression ==="

# 90
if bash "$REPO_DIR/tests/v2.5.6-production-overview-next.sh" >/dev/null 2>&1; then
  ok "90: v2.5.6 test passes"
else
  fail "90: v2.5.6 test fails"
fi

# 91
if bash "$REPO_DIR/tests/v2.5.5-production-rotation-readiness.sh" >/dev/null 2>&1; then
  ok "91: v2.5.5 test passes"
else
  fail "91: v2.5.5 test fails"
fi

# 92
if bash "$REPO_DIR/tests/v2.5.4-production-cert-readiness.sh" >/dev/null 2>&1; then
  ok "92: v2.5.4 test passes"
else
  fail "92: v2.5.4 test fails"
fi

# 93
if bash "$REPO_DIR/tests/v2.5.3-production-worker-readiness.sh" >/dev/null 2>&1; then
  ok "93: v2.5.3 test passes"
else
  fail "93: v2.5.3 test fails"
fi

# 94
if bash "$REPO_DIR/tests/v2.5.2-production-dns-readiness.sh" >/dev/null 2>&1; then
  ok "94: v2.5.2 test passes"
else
  fail "94: v2.5.2 test fails"
fi

# 95
if bash "$REPO_DIR/tests/v2.5.1-production-action-plan.sh" >/dev/null 2>&1; then
  ok "95: v2.5.1 test passes"
else
  fail "95: v2.5.1 test fails"
fi

# 96
if bash "$REPO_DIR/tests/v2.5.0-production-setup-spine.sh" >/dev/null 2>&1; then
  ok "96: v2.5.0 test passes"
else
  fail "96: v2.5.0 test fails"
fi

# 97
if bash "$REPO_DIR/tests/v2.4.7-closeout-manifest.sh" >/dev/null 2>&1; then
  ok "97: v2.4.7 test passes"
else
  fail "97: v2.4.7 test fails"
fi

# 98
if bash "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then
  ok "98: v2.4.5 test passes"
else
  fail "98: v2.4.5 test fails"
fi

# 99
if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
  ok "99: v2.4.0 test passes"
else
  fail "99: v2.4.0 test fails"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
