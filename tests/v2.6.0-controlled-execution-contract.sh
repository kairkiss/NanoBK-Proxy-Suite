#!/usr/bin/env bash
# v2.6.0 Controlled Real Execution Contract Test
#
# Validates the preview-only execution contract and orchestrator skeleton.
# No real deployment. No DNS mutation. No certificate request.
# No token rotation. No protocol key rotation. No Worker mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
DOC="$REPO_DIR/docs/v2.6-controlled-execution-contract.md"
MODULE="$REPO_DIR/lib/nanobk_production_execute_plan.py"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

assert_json() {
  local label="$1" json="$2" expr="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$pattern"; then
    ok "$label"
  else
    fail "$label (missing: $pattern)"
  fi
}

assert_not_contains_ci() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiE "$pattern"; then
    fail "$label (found: $pattern)"
  else
    ok "$label"
  fi
}

assert_action_exists() {
  local label="$1" json="$2" action_id="$3"
  if echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = [a.get('id') for a in d.get('actions', [])]
assert '$action_id' in ids, ids
" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
  fi
}

assert_list_contains() {
  local label="$1" json="$2" field="$3" value="$4"
  if echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert '$value' in d.get('$field', []), d.get('$field', [])
" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
  fi
}

echo "=== v2.6.0 Controlled Execution Contract ==="

[[ -f "$DOC" ]] && ok "1: docs/v2.6-controlled-execution-contract.md exists" || fail "1: contract doc exists"

if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "2: py_compile execute-plan module"
else
  fail "2: py_compile execute-plan module"
fi

if "$NANOBK" setup production execute-plan >/dev/null 2>&1; then
  ok "3: setup production execute-plan exits 0"
else
  fail "3: setup production execute-plan exits 0"
fi

if "$NANOBK" setup production execute-plan --json >/dev/null 2>&1; then
  ok "4: setup production execute-plan --json exits 0"
else
  fail "4: setup production execute-plan --json exits 0"
fi

if "$NANOBK" beginner production execute-plan >/dev/null 2>&1; then
  ok "5: beginner alias exits 0"
else
  fail "5: beginner alias exits 0"
fi

JSON_OUT=$("$NANOBK" setup production execute-plan --json 2>&1)
TEXT_OUT=$("$NANOBK" setup production execute-plan 2>&1)
BEGINNER_TEXT=$("$NANOBK" beginner production execute-plan 2>&1)

if echo "$JSON_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  ok "6: JSON valid"
else
  fail "6: JSON valid"
fi

assert_json "7: JSON mode" "$JSON_OUT" "d['mode']" "production_execute_plan_v2_6"
assert_json "8: version" "$JSON_OUT" "d['version']" "2.6.0"
assert_json "9: mutation false" "$JSON_OUT" "d['mutation']" "False"
assert_json "10: dangerous_actions_executed false" "$JSON_OUT" "d['dangerous_actions_executed']" "False"
assert_json "11: execution_enabled false" "$JSON_OUT" "d['execution_enabled']" "False"
assert_json "12: policy preview_only" "$JSON_OUT" "d['policy']" "preview_only"
assert_json "13: safety read_only" "$JSON_OUT" "d['safety']" "read_only"

assert_action_exists "14: actions include dns_apply" "$JSON_OUT" "dns_apply"
assert_action_exists "15: actions include worker_deploy" "$JSON_OUT" "worker_deploy"
assert_action_exists "16: actions include cert_issue" "$JSON_OUT" "cert_issue"
assert_action_exists "17: actions include vps_install" "$JSON_OUT" "vps_install"
assert_action_exists "18: actions include token_rotate" "$JSON_OUT" "token_rotate"
assert_action_exists "19: actions include protocol_rotate" "$JSON_OUT" "protocol_rotate"

if echo "$JSON_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for action in d.get('actions', []):
    assert action.get('manual_only') is True, action
" 2>/dev/null; then
  ok "20: all actions manual_only true"
else
  fail "20: all actions manual_only true"
fi

if echo "$JSON_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for action in d.get('actions', []):
    assert action.get('will_modify') is True, action
" 2>/dev/null; then
  ok "21: dangerous actions will_modify true"
else
  fail "21: dangerous actions will_modify true"
fi

assert_contains "22: text says 当前版本只显示执行计划" "当前版本只显示执行计划" "$TEXT_OUT"
assert_contains "23: text says 不会真的修改任何东西" "不会真的修改任何东西" "$TEXT_OUT"
assert_contains "24: text includes 域名指向" "域名指向" "$TEXT_OUT"
assert_contains "25: text includes 订阅服务入口" "订阅服务入口" "$TEXT_OUT"
assert_contains "26: text includes HTTPS 安全证书" "HTTPS 安全证书" "$TEXT_OUT"
assert_contains "27: text includes 代理服务安装" "代理服务安装" "$TEXT_OUT"
assert_contains "28: text includes 重新生成订阅密钥" "重新生成订阅密钥" "$TEXT_OUT"
assert_contains "29: text includes 更新代理通道密钥" "更新代理通道密钥" "$TEXT_OUT"

echo ""
echo "=== Dangerous args rejected ==="
for arg in --execute --yes --apply --issue --rotate --deploy --confirm; do
  if "$NANOBK" setup production execute-plan "$arg" >/dev/null 2>&1; then
    fail "30: dangerous arg $arg rejected"
  else
    ok "30: dangerous arg $arg rejected"
  fi
done

ALL_OUTPUT="$JSON_OUT $TEXT_OUT $BEGINNER_TEXT"
assert_not_contains_ci "31a: no raw token output" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|api[_-]?token|bearer[[:space:]]+[A-Za-z0-9._-]{20,}" "$ALL_OUTPUT"
assert_not_contains_ci "31b: no private key output" "PRIVATE KEY|BEGIN [A-Z ]*KEY" "$ALL_OUTPUT"
assert_not_contains_ci "31c: no subscription URL output" "subscription.*https?://|https?://[^[:space:]]*/sub" "$ALL_OUTPUT"
assert_not_contains_ci "31d: no zone_id output" "zone_id" "$ALL_OUTPUT"
assert_not_contains_ci "31e: no record_id output" "record_id" "$ALL_OUTPUT"
assert_not_contains_ci "31f: no api_env_path output" "api_env_path" "$ALL_OUTPUT"

echo ""
echo "=== Source safety ==="
SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "32a: no subprocess" "subprocess" "$SOURCE_TEXT"
assert_not_contains_ci "32b: no requests" "import requests|requests\\." "$SOURCE_TEXT"
assert_not_contains_ci "32c: no urlopen" "urlopen" "$SOURCE_TEXT"
assert_not_contains_ci "32d: no os.system" "os\\.system" "$SOURCE_TEXT"
assert_not_contains_ci "32e: no popen" "popen" "$SOURCE_TEXT"
assert_not_contains_ci "32f: no service control command" "systemctl[[:space:]].*(restart|reload)" "$SOURCE_TEXT"
assert_not_contains_ci "32g: no deploy CLI" "wrangler" "$SOURCE_TEXT"
assert_not_contains_ci "32h: no certificate CLI" "certbot" "$SOURCE_TEXT"
assert_not_contains_ci "32i: no rotate keys script" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "32j: no VPS installer script" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "32k: no Cloudflare installer script" "install-cloudflare\\.sh" "$SOURCE_TEXT"

assert_list_contains "32l: action type read_only defined" "$JSON_OUT" "supported_action_types" "read_only"
assert_list_contains "32m: action type local_write defined" "$JSON_OUT" "supported_action_types" "local_write"
assert_list_contains "32n: action type service_reload defined" "$JSON_OUT" "supported_action_types" "service_reload"
assert_list_contains "32o: policy manual_only defined" "$JSON_OUT" "supported_execution_policies" "manual_only"
assert_list_contains "32p: policy exact_gate_required defined" "$JSON_OUT" "supported_execution_policies" "exact_gate_required"

echo ""
echo "=== Regression smoke ==="
if [[ "${NANOBK_TEST_SKIP_REGRESSION:-1}" == "1" ]]; then
  ok "33: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  if bash "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/dev/null 2>&1; then
    ok "33: v2.5.11 closeout test passes"
  else
    fail "33: v2.5.11 closeout test passes"
  fi

  if bash "$REPO_DIR/tests/v2.5.7-production-preflight.sh" >/dev/null 2>&1; then
    ok "34: v2.5.7 preflight test passes"
  else
    fail "34: v2.5.7 preflight test passes"
  fi

  if bash "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then
    ok "35: v2.4.5 friendly gate wrappers test passes"
  else
    fail "35: v2.4.5 friendly gate wrappers test passes"
  fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
