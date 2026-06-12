#!/usr/bin/env bash
# v2.5.0 Production Setup Spine Test
#
# Tests the production setup integration spine.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
SPINE_PY="$REPO_DIR/lib/nanobk_production_setup_spine.py"

PASS=0
FAIL=0
NOTE_COUNT=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
note() { echo "NOTE: $1"; NOTE_COUNT=$((NOTE_COUNT + 1)); }

# Portable timeout helper
run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@" &
    local pid=$!
    ( sleep "$seconds" && kill "$pid" 2>/dev/null ) &
    local watcher=$!
    wait "$pid"
    local rc=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    return "$rc"
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

assert_not_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiF "$pattern"; then
    fail "$label (found: $pattern)"
  else
    ok "$label"
  fi
}

assert_json_field() {
  local label="$1" json="$2" jq_expr="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($jq_expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

# Use temp HOME to avoid interfering with real profile
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT

# ── Section A: Basic functionality ─────────────────────────────────────────

echo "=== Section A: Basic functionality ==="

# 1. python3 -m py_compile
if python3 -m py_compile "$SPINE_PY" 2>/dev/null; then
  ok "1: py_compile passes"
else
  fail "1: py_compile fails"
fi

# 2. nanobk setup production exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production >/dev/null 2>&1; then
  ok "2: nanobk setup production exits 0"
else
  fail "2: nanobk setup production exits 0"
fi

# 3. nanobk setup production --json exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production --json >/dev/null 2>&1; then
  ok "3: nanobk setup production --json exits 0"
else
  fail "3: nanobk setup production --json exits 0"
fi

# 4. nanobk setup production status exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production status >/dev/null 2>&1; then
  ok "4: nanobk setup production status exits 0"
else
  fail "4: nanobk setup production status exits 0"
fi

# 5. nanobk setup production plan exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production plan >/dev/null 2>&1; then
  ok "5: nanobk setup production plan exits 0"
else
  fail "5: nanobk setup production plan exits 0"
fi

# 6. nanobk beginner production exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner production >/dev/null 2>&1; then
  ok "6: nanobk beginner production exits 0"
else
  fail "6: nanobk beginner production exits 0"
fi

# 7. nanobk beginner production --json exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner production --json >/dev/null 2>&1; then
  ok "7: nanobk beginner production --json exits 0"
else
  fail "7: nanobk beginner production --json exits 0"
fi

# ── Section B: JSON schema ─────────────────────────────────────────────────

echo ""
echo "=== Section B: JSON schema ==="

JSON_OUTPUT=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production --json 2>&1)

# 8. JSON ok == true
assert_json_field "8: JSON ok == true" "$JSON_OUTPUT" "d['ok']" "True"

# 9. JSON mode == production_setup_v2_5
assert_json_field "9: JSON mode == production_setup_v2_5" "$JSON_OUTPUT" "d['mode']" "production_setup_v2_5"

# 10. JSON version == 2.5.0
assert_json_field "10: JSON version == 2.5.0" "$JSON_OUTPUT" "d['version']" "2.5.0"

# 11. JSON mutation == false
assert_json_field "11: JSON mutation == false" "$JSON_OUTPUT" "d['mutation']" "False"

# 12. JSON dangerous_actions_executed == false
assert_json_field "12: JSON dangerous_actions_executed == false" "$JSON_OUTPUT" "d['dangerous_actions_executed']" "False"

# 13. JSON safety == read_only
assert_json_field "13: JSON safety == read_only" "$JSON_OUTPUT" "d['safety']" "read_only"

# 14. JSON has steps array
if echo "$JSON_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d['steps'], list)" 2>/dev/null; then
  ok "14: JSON has steps array"
else
  fail "14: JSON missing steps array"
fi

# 15-28. steps contains all required stage IDs
REQUIRED_STAGES=(
  "install_ready"
  "cloudflare_login"
  "domain_select"
  "vps_ip_detect"
  "subdomain_plan"
  "dns_apply_gate"
  "cert_issue_gate"
  "vps_four_protocols"
  "worker_nanok"
  "worker_nanob"
  "subscription_token"
  "protocol_key_rotation"
  "bot_web_optional"
  "final_status"
)

STAGE_IDX=15
for stage_id in "${REQUIRED_STAGES[@]}"; do
  if echo "$JSON_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stage_ids = [s['id'] for s in d['steps']]
assert '$stage_id' in stage_ids
" 2>/dev/null; then
    ok "${STAGE_IDX}: steps contains $stage_id"
  else
    fail "${STAGE_IDX}: steps missing $stage_id"
  fi
  STAGE_IDX=$((STAGE_IDX + 1))
done

# ── Section C: Old ability mapping ─────────────────────────────────────────

echo ""
echo "=== Section C: Old ability mapping ==="

TEXT_OUTPUT=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" setup production 2>&1)

# 29. text output mentions nanobk install --mode vps
assert_contains "29: mentions nanobk install --mode vps" "nanobk install --mode vps" "$TEXT_OUTPUT"

# 30. text output mentions nanobk install --mode cloudflare
assert_contains "30: mentions nanobk install --mode cloudflare" "nanobk install --mode cloudflare" "$TEXT_OUTPUT"

# 31. text output mentions nanobk setup dns apply
assert_contains "31: mentions nanobk setup dns apply" "nanobk setup dns apply" "$TEXT_OUTPUT"

# 32. text output mentions nanobk setup cert issue
assert_contains "32: mentions nanobk setup cert issue" "nanobk setup cert issue" "$TEXT_OUTPUT"

# 33. text output mentions nanobk setup token rotate
assert_contains "33: mentions nanobk setup token rotate" "nanobk setup token rotate" "$TEXT_OUTPUT"

# 34. text output mentions nanobk rotate all
assert_contains "34: mentions nanobk rotate all" "nanobk rotate all" "$TEXT_OUTPUT"

# 35. text output mentions nanobk rotate hy2
assert_contains "35: mentions nanobk rotate hy2" "nanobk rotate hy2" "$TEXT_OUTPUT"

# 36. text output mentions nanobk rotate tuic
assert_contains "36: mentions nanobk rotate tuic" "nanobk rotate tuic" "$TEXT_OUTPUT"

# 37. text output mentions nanobk rotate reality
assert_contains "37: mentions nanobk rotate reality" "nanobk rotate reality" "$TEXT_OUTPUT"

# 38. text output mentions nanobk rotate trojan
assert_contains "38: mentions nanobk rotate trojan" "nanobk rotate trojan" "$TEXT_OUTPUT"

# Also check JSON output has old_capabilities
if echo "$JSON_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert isinstance(d.get('old_capabilities'), list)
cmds = [c['command'] for c in d['old_capabilities']]
for required in ['nanobk install --mode vps', 'nanobk install --mode cloudflare',
                 'nanobk setup dns apply', 'nanobk setup cert issue',
                 'nanobk setup token rotate', 'nanobk rotate all']:
    assert required in cmds, f'Missing: {required}'
" 2>/dev/null; then
  ok "38b: JSON old_capabilities has all required commands"
else
  fail "38b: JSON old_capabilities missing required commands"
fi

# ── Section D: Safety ──────────────────────────────────────────────────────

echo ""
echo "=== Section D: Safety ==="

ALL_OUTPUT="$TEXT_OUTPUT
$JSON_OUTPUT"

# 39. no CF_API_TOKEN
assert_not_contains "39: no CF_API_TOKEN" "CF_API_TOKEN" "$ALL_OUTPUT"

# 40. no ADMIN_TOKEN
assert_not_contains "40: no ADMIN_TOKEN" "ADMIN_TOKEN" "$ALL_OUTPUT"

# 41. no SUB_TOKEN
assert_not_contains "41: no SUB_TOKEN" "SUB_TOKEN" "$ALL_OUTPUT"

# 42. no PRIVATE KEY
assert_not_contains "42: no PRIVATE KEY" "PRIVATE KEY" "$ALL_OUTPUT"

# 43. no subscription URL
if echo "$ALL_OUTPUT" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "43: subscription URL leak"
else
  ok "43: no subscription URL"
fi

# 44. no zone_id
assert_not_contains "44: no zone_id" "zone_id" "$ALL_OUTPUT"

# 45. no record_id
assert_not_contains "45: no record_id" "record_id" "$ALL_OUTPUT"

# 46. no api_env_path
assert_not_contains "46: no api_env_path" "api_env_path" "$ALL_OUTPUT"

# 47. no api.cloudflare.com/client/v4
assert_not_contains "47: no CF API URL" "api.cloudflare.com/client/v4" "$ALL_OUTPUT"

# 48. no /dns_records
assert_not_contains "48: no /dns_records" "/dns_records" "$ALL_OUTPUT"

# ── Section E: Module safety (source code) ─────────────────────────────────

echo ""
echo "=== Section E: Module safety ==="

# 49. module does not import subprocess
if python3 -c "
import ast
with open('$SPINE_PY') as f:
    tree = ast.parse(f.read())
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            assert 'subprocess' not in alias.name
    elif isinstance(node, ast.ImportFrom):
        if node.module and 'subprocess' in node.module:
            raise AssertionError('subprocess import found')
" 2>/dev/null; then
  ok "49: module does not import subprocess"
else
  fail "49: module imports subprocess"
fi

# 50. module does not import requests
if python3 -c "
import ast
with open('$SPINE_PY') as f:
    tree = ast.parse(f.read())
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            assert 'requests' not in alias.name
    elif isinstance(node, ast.ImportFrom):
        if node.module and 'requests' in node.module:
            raise AssertionError('requests import found')
" 2>/dev/null; then
  ok "50: module does not import requests"
else
  fail "50: module imports requests"
fi

# 51. module does not import urlopen
if python3 -c "
import ast
with open('$SPINE_PY') as f:
    tree = ast.parse(f.read())
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            assert 'urllib' not in alias.name
    elif isinstance(node, ast.ImportFrom):
        if node.module and 'urllib' in node.module:
            raise AssertionError('urllib import found')
" 2>/dev/null; then
  ok "51: module does not import urlopen"
else
  fail "51: module imports urlopen"
fi

# 52. module does not contain systemctl restart
if grep -q "systemctl.*restart" "$SPINE_PY" 2>/dev/null; then
  fail "52: module contains systemctl restart"
else
  ok "52: no systemctl restart in module"
fi

# 53. module does not contain systemctl reload
if grep -q "systemctl.*reload" "$SPINE_PY" 2>/dev/null; then
  fail "53: module contains systemctl reload"
else
  ok "53: no systemctl reload in module"
fi

# 54. module does not contain wrangler deploy
if grep -q "wrangler.*deploy" "$SPINE_PY" 2>/dev/null; then
  fail "54: module contains wrangler deploy"
else
  ok "54: no wrangler deploy in module"
fi

# 55. module does not contain cf dns apply --yes
if grep -q "cf dns apply.*--yes" "$SPINE_PY" 2>/dev/null; then
  fail "55: module contains cf dns apply --yes"
else
  ok "55: no cf dns apply --yes in module"
fi

# ── Section F: Regression ──────────────────────────────────────────────────

echo ""
echo "=== Section F: Regression ==="

# 56. v2.4.7 closeout manifest test
V247_TEST="$REPO_DIR/tests/v2.4.7-closeout-manifest.sh"
if [[ -f "$V247_TEST" ]]; then
  if run_with_timeout 30 bash "$V247_TEST" >/dev/null 2>&1; then
    ok "56: v2.4.7 closeout manifest test passes"
  else
    fail "56: v2.4.7 closeout manifest test failed"
  fi
else
  fail "56: v2.4.7 test not found"
fi

# 57. v2.4.5 test
V245_TEST="$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh"
if [[ -f "$V245_TEST" ]]; then
  if run_with_timeout 120 bash "$V245_TEST" >/dev/null 2>&1; then
    ok "57: v2.4.5 test passes"
  else
    fail "57: v2.4.5 test failed"
  fi
else
  fail "57: v2.4.5 test not found"
fi

# 58. v2.4.4 test
V244_TEST="$REPO_DIR/tests/v2.4.4-ip-friendly-ux.sh"
if [[ -f "$V244_TEST" ]]; then
  if run_with_timeout 120 bash "$V244_TEST" >/dev/null 2>&1; then
    ok "58: v2.4.4 test passes"
  else
    fail "58: v2.4.4 test failed"
  fi
else
  fail "58: v2.4.4 test not found"
fi

# 59. v2.4.3 test
V243_TEST="$REPO_DIR/tests/v2.4.3-subdomain-conflict-ux.sh"
if [[ -f "$V243_TEST" ]]; then
  if run_with_timeout 120 bash "$V243_TEST" >/dev/null 2>&1; then
    ok "59: v2.4.3 test passes"
  else
    fail "59: v2.4.3 test failed"
  fi
else
  fail "59: v2.4.3 test not found"
fi

# 60. v2.4.0 test
V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if run_with_timeout 30 bash "$V240_TEST" >/dev/null 2>&1; then
    ok "60: v2.4.0 test passes"
  else
    fail "60: v2.4.0 test failed"
  fi
else
  fail "60: v2.4.0 test not found"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=============================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL ${PASS} TESTS PASSED (${NOTE_COUNT} notes)"
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed (${NOTE_COUNT} notes)."
  exit 1
fi
