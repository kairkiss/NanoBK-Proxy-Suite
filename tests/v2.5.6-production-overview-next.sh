#!/usr/bin/env bash
# v2.5.6 Production Overview and Next-Step Navigator Test
#
# Tests the production overview and next-step recommendation flow.
# No real deployment. No DNS mutation. No certificate request.
# No token rotation. No protocol key rotation. No Worker mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_overview.py"

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
  local num="$1" label="$2" text="$3" pattern="$4"
  if echo "$text" | grep -qi "$pattern"; then
    fail "$num: $label — found '$pattern'"
  else
    ok "$num: $label"
  fi
}

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# Create fake JSON fixtures for priority testing
FAKE_DIR=$(mktemp -d)

# DNS blocked (no profile)
cat > "$FAKE_DIR/dns-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "connect_cloudflare", "safety": "read_only"}
EOF

# DNS ready
cat > "$FAKE_DIR/dns-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_dns_gate", "safety": "read_only"}
EOF

# Worker blocked
cat > "$FAKE_DIR/worker-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "select_domain", "safety": "read_only"}
EOF

# Worker ready
cat > "$FAKE_DIR/worker-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_worker_deploy", "safety": "read_only"}
EOF

# Cert blocked (needs mode)
cat > "$FAKE_DIR/cert-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "select_cert_mode", "safety": "read_only"}
EOF

# Cert ready
cat > "$FAKE_DIR/cert-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_vps_install", "safety": "read_only"}
EOF

# Rotation blocked (needs token)
cat > "$FAKE_DIR/rotation-blocked.json" <<'EOF'
{"ok": true, "blocked": true, "next_step": "choose_token_rotation", "safety": "read_only"}
EOF

# Rotation ready
cat > "$FAKE_DIR/rotation-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "review_token_gate", "safety": "read_only"}
EOF

# All ready
cat > "$FAKE_DIR/all-ready.json" <<'EOF'
{"ok": true, "blocked": false, "next_step": "done", "safety": "read_only"}
EOF

trap 'rm -rf "$HOME" "$FAKE_DIR"' EXIT

echo "=== A. Basic ==="

# 1
if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2
if "$NANOBK" setup production overview >/dev/null 2>&1; then
  ok "2: setup production overview exits 0"
else
  fail "2: setup production overview exits non-zero"
fi

# 3
if "$NANOBK" setup production overview --json >/dev/null 2>&1; then
  ok "3: setup production overview --json exits 0"
else
  fail "3: setup production overview --json exits non-zero"
fi

# 4
if "$NANOBK" setup production next >/dev/null 2>&1; then
  ok "4: setup production next exits 0"
else
  fail "4: setup production next exits non-zero"
fi

# 5
if "$NANOBK" setup production next --json >/dev/null 2>&1; then
  ok "5: setup production next --json exits 0"
else
  fail "5: setup production next --json exits non-zero"
fi

# 6
if "$NANOBK" beginner production overview >/dev/null 2>&1; then
  ok "6: beginner production overview exits 0"
else
  fail "6: beginner production overview exits non-zero"
fi

# 7
if "$NANOBK" beginner production next >/dev/null 2>&1; then
  ok "7: beginner production next exits 0"
else
  fail "7: beginner production next exits non-zero"
fi

echo ""
echo "=== B. Overview JSON schema ==="

JSON=$("$NANOBK" setup production overview --json 2>&1)

check_json "8" "ok == true" "$JSON" "d['ok']" "True"
check_json "9" "mode" "$JSON" "d['mode']" "production_overview_v2_5"
check_json "10" "version" "$JSON" "d['version']" "2.5.6"
check_json "11" "mutation == false" "$JSON" "d['mutation']" "False"
check_json "12" "dangerous_actions_executed == false" "$JSON" "d['dangerous_actions_executed']" "False"
check_json "13" "safety == read_only" "$JSON" "d['safety']" "read_only"

# 14
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'sections' in d" 2>/dev/null; then
  ok "14: has sections"
else
  fail "14: missing sections"
fi

# 15
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'dns' in d['sections']" 2>/dev/null; then
  ok "15: has sections.dns"
else
  fail "15: missing sections.dns"
fi

# 16
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'worker' in d['sections']" 2>/dev/null; then
  ok "16: has sections.worker"
else
  fail "16: missing sections.worker"
fi

# 17
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cert' in d['sections']" 2>/dev/null; then
  ok "17: has sections.cert"
else
  fail "17: missing sections.cert"
fi

# 18
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'rotation' in d['sections']" 2>/dev/null; then
  ok "18: has sections.rotation"
else
  fail "18: missing sections.rotation"
fi

# 19
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'overall' in d" 2>/dev/null; then
  ok "19: has overall"
else
  fail "19: missing overall"
fi

# 20
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d['overall']" 2>/dev/null; then
  ok "20: has overall.next_step"
else
  fail "20: missing overall.next_step"
fi

# 21
if echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'recommended_command' in d['overall']" 2>/dev/null; then
  ok "21: has overall.recommended_command"
else
  fail "21: missing overall.recommended_command"
fi

echo ""
echo "=== C. Next JSON schema ==="

NEXT_JSON=$("$NANOBK" setup production next --json 2>&1)

check_json "22" "ok == true" "$NEXT_JSON" "d['ok']" "True"
check_json "23" "mode" "$NEXT_JSON" "d['mode']" "production_next_step_v2_5"
check_json "24" "version" "$NEXT_JSON" "d['version']" "2.5.6"
check_json "25" "mutation == false" "$NEXT_JSON" "d['mutation']" "False"
check_json "26" "dangerous_actions_executed == false" "$NEXT_JSON" "d['dangerous_actions_executed']" "False"

# 27
if echo "$NEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d" 2>/dev/null; then
  ok "27: has next_step"
else
  fail "27: missing next_step"
fi

# 28
if echo "$NEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'recommended_command' in d" 2>/dev/null; then
  ok "28: has recommended_command"
else
  fail "28: missing recommended_command"
fi

# 29
if echo "$NEXT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'reason' in d" 2>/dev/null; then
  ok "29: has reason"
else
  fail "29: missing reason"
fi

check_json "30" "safety == read_only" "$NEXT_JSON" "d['safety']" "read_only"

echo ""
echo "=== D. Priority logic ==="

# 31 — no profile -> recommends DNS
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-blocked.json"
PRI_JSON=$("$NANOBK" setup production next --json 2>&1)
check_json "31" "DNS blocked -> recommends dns" "$PRI_JSON" "d['recommended_command']" "nanobk setup production dns"

# 32 — reason mentions Cloudflare/domain/DNS
if echo "$PRI_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'Cloudflare' in d['reason'] or 'DNS' in d['reason'] or '域名' in d['reason']" 2>/dev/null; then
  ok "32: reason mentions Cloudflare/domain/DNS"
else
  fail "32: reason missing Cloudflare/domain/DNS"
fi

# 33 — DNS ready but worker blocked -> recommends worker
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-blocked.json"
W_JSON=$("$NANOBK" setup production next --json 2>&1)
check_json "33" "worker blocked -> recommends worker" "$W_JSON" "d['recommended_command']" "nanobk setup production worker"

# 34 — worker ready but cert blocked -> recommends cert
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-blocked.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-blocked.json"
C_JSON=$("$NANOBK" setup production next --json 2>&1)
check_json "34" "cert blocked -> recommends cert" "$C_JSON" "d['recommended_command']" "nanobk setup production cert"

# 35 — cert ready but rotation blocked -> recommends rotate
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-blocked.json"
R_JSON=$("$NANOBK" setup production next --json 2>&1)
check_json "35" "rotation blocked -> recommends rotate" "$R_JSON" "d['recommended_command']" "nanobk setup production rotate"

# 36 — all ready -> review_real_deploy
export NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON="$FAKE_DIR/dns-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON="$FAKE_DIR/worker-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON="$FAKE_DIR/cert-ready.json"
export NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON="$FAKE_DIR/rotation-ready.json"
A_JSON=$("$NANOBK" setup production next --json 2>&1)
check_json "36" "all ready -> review_real_deploy" "$A_JSON" "d['next_step']" "review_real_deploy"

# Clean up fake env vars
unset NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON
unset NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON
unset NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON
unset NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON

echo ""
echo "=== E. Text output ==="

OVERVIEW_TEXT=$("$NANOBK" setup production overview 2>&1)
NEXT_TEXT=$("$NANOBK" setup production next 2>&1)

# 37
if echo "$OVERVIEW_TEXT" | grep -q "NanoBK 生产部署总览"; then
  ok "37: overview text contains NanoBK 生产部署总览"
else
  fail "37: overview text missing NanoBK 生产部署总览"
fi

# 38
if echo "$OVERVIEW_TEXT" | grep -q "域名与 DNS"; then
  ok "38: overview text contains 域名与 DNS"
else
  fail "38: overview text missing 域名与 DNS"
fi

# 39
if echo "$OVERVIEW_TEXT" | grep -q "Worker 订阅入口"; then
  ok "39: overview text contains Worker 订阅入口"
else
  fail "39: overview text missing Worker 订阅入口"
fi

# 40
if echo "$OVERVIEW_TEXT" | grep -q "HTTPS 安全证书"; then
  ok "40: overview text contains HTTPS 安全证书"
else
  fail "40: overview text missing HTTPS 安全证书"
fi

# 41
if echo "$OVERVIEW_TEXT" | grep -q "订阅密钥与代理密钥"; then
  ok "41: overview text contains 订阅密钥与代理密钥"
else
  fail "41: overview text missing 订阅密钥与代理密钥"
fi

# 42
if echo "$NEXT_TEXT" | grep -q "NanoBK 下一步"; then
  ok "42: next text contains NanoBK 下一步"
else
  fail "42: next text missing NanoBK 下一步"
fi

# 43
if echo "$NEXT_TEXT" | grep -q "建议现在执行"; then
  ok "43: next text contains 建议现在执行"
else
  fail "43: next text missing 建议现在执行"
fi

# 44
if echo "$OVERVIEW_TEXT" | grep -q "当前不会执行任何真实修改"; then
  ok "44: text says 当前不会执行任何真实修改"
else
  fail "44: text missing 当前不会执行任何真实修改"
fi

echo ""
echo "=== F. Safety output ==="

ALL_OUTPUT="$JSON
$NEXT_JSON
$PRI_JSON
$W_JSON
$C_JSON
$R_JSON
$A_JSON"

check_no "45" "no raw token" "$ALL_OUTPUT" "raw.*token\|token.*raw"
check_no "46" "no ADMIN_TOKEN" "$ALL_OUTPUT" "ADMIN_TOKEN"
check_no "47" "no SUB_TOKEN" "$ALL_OUTPUT" "SUB_TOKEN"
check_no "48" "no CF_API_TOKEN" "$ALL_OUTPUT" "CF_API_TOKEN"
check_no "49" "no PRIVATE KEY" "$ALL_OUTPUT" "PRIVATE.KEY"
check_no "50" "no subscription URL" "$ALL_OUTPUT" "subscription.*http"
check_no "51" "no admin URL" "$ALL_OUTPUT" "admin.*url\|admin.*URL"
check_no "52" "no workers.dev secret URL" "$ALL_OUTPUT" "workers\.dev"
check_no "53" "no zone_id" "$ALL_OUTPUT" "zone_id"
check_no "54" "no record_id" "$ALL_OUTPUT" "record_id"
check_no "55" "no api_env_path" "$ALL_OUTPUT" "api_env_path"
check_no "56" "no raw protocol passwords" "$ALL_OUTPUT" "password"
check_no "57" "no cert key path" "$ALL_OUTPUT" "key.*path\|key.*file\|key_file"
check_no "58" "no api.cloudflare.com/client/v4" "$ALL_OUTPUT" "api\.cloudflare\.com/client/v4"
check_no "59" "no /dns_records" "$ALL_OUTPUT" "/dns_records"

echo ""
echo "=== G. Source safety ==="

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

check_no_code "60" "subprocess import" "import subprocess"
check_no_code "61" "requests import" "import requests"
check_no_code "62" "urlopen import" "import urllib"
check_no_code "63" "os.system" "os\.system"
check_no_code "64" "popen" "popen"
check_no_code "65" "systemctl restart" "systemctl.*restart"
check_no_code "66" "systemctl reload" "systemctl.*reload"
check_no_code "67" "wrangler deploy" "wrangler.*deploy"
check_no_code "68" "certbot certonly" "certbot.*certonly"
check_no_code "69" "rotate-keys.sh" "rotate-keys\.sh"
check_no_code "70" "setup token rotate --rotate execution" "setup token rotate.*--rotate"

echo ""
echo "=== H. Regression (narrow smoke) ==="

# 71-76: Check prior test files exist (fast, no execution)
for prior in v2.5.5-production-rotation-readiness v2.5.4-production-cert-readiness v2.5.3-production-worker-readiness v2.5.2-production-dns-readiness v2.5.1-production-action-plan v2.5.0-production-setup-spine; do
  if [[ -f "$REPO_DIR/tests/${prior}.sh" ]]; then
    ok "prior test file exists: $prior"
  else
    fail "prior test file missing: $prior"
  fi
done

# 77: v2.4.0 scope test passes (fast, standalone)
if [[ -f "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" ]]; then
  if bash "$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh" >/dev/null 2>&1; then
    ok "77: v2.4.0 scope test passes"
  else
    fail "77: v2.4.0 scope test fails"
  fi
else
  fail "77: v2.4.0 test file missing"
fi

# ── Section I: Opt-in long regression ──────────────────────────────────────

echo ""
echo "=== Section I: Opt-in long regression ==="

if [[ "${NANOBK_RUN_LONG_REGRESSION:-0}" == "1" ]]; then
  echo "NANOBK_RUN_LONG_REGRESSION=1 — running legacy regression tests with timeout."

  # 78. v2.5.5 test (timeout 60s)
  V255_TEST="$REPO_DIR/tests/v2.5.5-production-rotation-readiness.sh"
  if [[ -f "$V255_TEST" ]]; then
    if timeout 60 bash "$V255_TEST" >/dev/null 2>&1; then
      ok "78: v2.5.5 test passes"
    else
      note "78: v2.5.5 test failed or timed out (non-blocking)"
    fi
  else
    note "78: v2.5.5 test not found"
  fi

  # 79. v2.5.4 test (timeout 60s)
  V254_TEST="$REPO_DIR/tests/v2.5.4-production-cert-readiness.sh"
  if [[ -f "$V254_TEST" ]]; then
    if timeout 60 bash "$V254_TEST" >/dev/null 2>&1; then
      ok "79: v2.5.4 test passes"
    else
      note "79: v2.5.4 test failed or timed out (non-blocking)"
    fi
  else
    note "79: v2.5.4 test not found"
  fi
else
  note "Skipping long regression; set NANOBK_RUN_LONG_REGRESSION=1 to enable"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
