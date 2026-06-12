#!/usr/bin/env bash
# v2.4.3 Subdomain Conflict UX Test
#
# Tests beginner-friendly proxy/web subdomain conflict handling.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
# Uses temp HOME / fake profile / fixtures.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
SUBDOMAIN_PY="$REPO_DIR/lib/nanobk_subdomain_conflict_ux.py"
BEGINNER_PY="$REPO_DIR/lib/nanobk_beginner_flow.py"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

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

# ── Setup temp HOME ────────────────────────────────────────────────────────
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.nanobk"

# ── Section A: Module basic tests ──────────────────────────────────────────

echo "=== Section A: Module basic tests ==="

# A1. module exits 0
if python3 "$SUBDOMAIN_PY" check --domain example.com >/dev/null 2>&1; then
  ok "A1: module exits 0"
else
  fail "A1: module exits 0"
fi

# A2. nanobk beginner subdomain exits 0
if bash "$NANOBK" beginner subdomain --domain example.com >/dev/null 2>&1; then
  ok "A2: nanobk beginner subdomain exits 0"
else
  fail "A2: nanobk beginner subdomain exits 0"
fi

# ── Section B: Both available ──────────────────────────────────────────────

echo ""
echo "=== Section B: Both available ==="

BOTH_AVAIL_JSON=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'available',
    'web.example.com': 'available'
})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)

BOTH_AVAIL_TEXT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain, render_plan_text
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'available',
    'web.example.com': 'available'
})
print(render_plan_text(result))
" 2>&1)

# B3. both available -> proxy.example.com available
assert_contains "B3: proxy available" "proxy.example.com 可以使用" "$BOTH_AVAIL_TEXT"

# B4. both available -> web.example.com available
assert_contains "B4: web available" "web.example.com 可以使用" "$BOTH_AVAIL_TEXT"

# B5. both available -> next_step review_dns_plan
assert_json_field "B5: both available -> review_dns_plan" "$BOTH_AVAIL_JSON" "d['next_step']" "review_dns_plan"

# ── Section C: Proxy occupied ──────────────────────────────────────────────

echo ""
echo "=== Section C: Proxy occupied ==="

PROXY_OCC_JSON=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'occupied',
    'web.example.com': 'available'
})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)

PROXY_OCC_TEXT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain, render_plan_text
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'occupied',
    'web.example.com': 'available'
})
print(render_plan_text(result))
" 2>&1)

# C6. proxy occupied -> shows "这个名字已经被用了"
assert_contains "C6: proxy occupied message" "这个名字已经被用了" "$PROXY_OCC_TEXT"

# C7. proxy occupied -> next_step ask_custom_subdomain
assert_json_field "C7: proxy occupied -> ask_custom_subdomain" "$PROXY_OCC_JSON" "d['next_step']" "ask_custom_subdomain"

# ── Section D: Web occupied ────────────────────────────────────────────────

echo ""
echo "=== Section D: Web occupied ==="

WEB_OCC_JSON=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'available',
    'web.example.com': 'occupied'
})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)

WEB_OCC_TEXT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain, render_plan_text
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'available',
    'web.example.com': 'occupied'
})
print(render_plan_text(result))
" 2>&1)

# D8. web occupied -> shows "这个名字已经被用了"
assert_contains "D8: web occupied message" "这个名字已经被用了" "$WEB_OCC_TEXT"

# D9. web occupied -> next_step ask_custom_subdomain
assert_json_field "D9: web occupied -> ask_custom_subdomain" "$WEB_OCC_JSON" "d['next_step']" "ask_custom_subdomain"

# ── Section E: Both occupied ───────────────────────────────────────────────

echo ""
echo "=== Section E: Both occupied ==="

BOTH_OCC_JSON=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'occupied',
    'web.example.com': 'occupied'
})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)

BOTH_OCC_TEXT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain, render_plan_text
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'occupied',
    'web.example.com': 'occupied'
})
print(render_plan_text(result))
" 2>&1)

# E10. both occupied -> both names shown as occupied
assert_contains "E10a: proxy occupied" "proxy.example.com 这个名字已经被用了" "$BOTH_OCC_TEXT"
assert_contains "E10b: web occupied" "web.example.com 这个名字已经被用了" "$BOTH_OCC_TEXT"

# E11. both occupied -> blocked true
assert_json_field "E11: both occupied -> blocked" "$BOTH_OCC_JSON" "d['blocked']" "True"

# ── Section F: Custom subdomain retry ──────────────────────────────────────

echo ""
echo "=== Section F: Custom subdomain retry ==="

# F12. custom proxy available -> can_use
CUSTOM_AVAIL=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import retry_subdomain
result = retry_subdomain('example.com', 'proxy', 'myproxy', {'myproxy.example.com': 'available'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "F12: custom proxy available -> can_use" "$CUSTOM_AVAIL" "d['action']" "can_use"

# F13. custom web available -> can_use
CUSTOM_WEB_AVAIL=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import retry_subdomain
result = retry_subdomain('example.com', 'web', 'myweb', {'myweb.example.com': 'available'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "F13: custom web available -> can_use" "$CUSTOM_WEB_AVAIL" "d['action']" "can_use"

# F14. custom still occupied -> still ask_custom_subdomain
CUSTOM_STILL_OCC=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import retry_subdomain
result = retry_subdomain('example.com', 'proxy', 'myproxy', {'myproxy.example.com': 'occupied'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "F14: custom still occupied -> still_occupied" "$CUSTOM_STILL_OCC" "d['action']" "still_occupied"

# F15. empty custom name -> exit_or_back
CUSTOM_EMPTY=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import retry_subdomain
result = retry_subdomain('example.com', 'proxy', '', {})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "F15: empty custom -> exit_or_back" "$CUSTOM_EMPTY" "d['action']" "exit_or_back"

# ── Section G: Safety checks ───────────────────────────────────────────────

echo ""
echo "=== Section G: Safety checks ==="

ALL_OUTPUT=$(python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain, render_plan_text, retry_subdomain, render_retry_text

# Both available
p1 = plan_subdomain('example.com', availability={'proxy.example.com': 'available', 'web.example.com': 'available'})
print(render_plan_text(p1))

# Both occupied
p2 = plan_subdomain('example.com', availability={'proxy.example.com': 'occupied', 'web.example.com': 'occupied'})
print(render_plan_text(p2))

# Retry
r1 = retry_subdomain('example.com', 'proxy', 'myproxy', {'myproxy.example.com': 'available'})
print(render_retry_text(r1))
" 2>&1 || true)

# G16/17. no overwrite/delete action text (safety text "不会覆盖" is OK)
# The text says "不会覆盖，也不会删除已有配置" which is correct safety language.
# Check that no "执行覆盖" or "执行删除" appears.
if echo "$ALL_OUTPUT" | grep -q "执行覆盖\|执行删除\|将覆盖\|将删除"; then
  fail "G16/17: overwrite/delete action text found"
else
  ok "G16/17: no overwrite/delete action text"
fi

# ── Section H: Source code mutation checks ──────────────────────────────────

echo ""
echo "=== Section H: Source code mutation checks ==="

# H18. no DNS create/apply code
if grep -q "dns.*create\|create.*dns\|dns.*apply\|apply.*dns" "$SUBDOMAIN_PY" 2>/dev/null; then
  fail "H18: DNS create/apply in subdomain module"
else
  ok "H18: no DNS create in subdomain module"
fi

# H19-22. no dangerous commands
MUTATION_CHECK=$(python3 -c "
import ast
with open('$SUBDOMAIN_PY') as f:
    source = f.read()
in_docstring = False
for line in source.splitlines():
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    if '\"\"\"' in stripped:
        in_docstring = not in_docstring
        continue
    if in_docstring:
        continue
    for kw in ['certbot', 'acme.sh', 'curl ', 'wrangler ', 'systemctl reload', 'systemctl restart']:
        if kw in stripped:
            print('FOUND ' + kw + ': ' + stripped)
" 2>/dev/null || true)
if [[ -n "$MUTATION_CHECK" ]]; then
  fail "H19-22: dangerous commands found: $MUTATION_CHECK"
else
  ok "H19: no curl in subdomain module"
  ok "H20: no wrangler in subdomain module"
  ok "H21: no certbot/acme.sh in subdomain module"
  ok "H22: no systemctl reload/restart in subdomain module"
fi

# ── Section I: Secret leak checks ──────────────────────────────────────────

echo ""
echo "=== Section I: Secret leak checks ==="

ALL_JSON=$(python3 "$SUBDOMAIN_PY" check --domain example.com --json 2>&1 || true)

# I23. no token/private key/subscription URL leak
assert_not_contains "I23a: no CF_API_TOKEN" "CF_API_TOKEN" "$ALL_JSON"
assert_not_contains "I23b: no PRIVATE KEY" "PRIVATE KEY" "$ALL_JSON"
if echo "$ALL_JSON" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "I23c: subscription URL leak"
else
  ok "I23c: no subscription URL"
fi

# I24. no zone_id leak
assert_not_contains "I24: no zone_id" "zone_id" "$ALL_JSON"
assert_not_contains "I24b: no CF_ZONE_ID" "CF_ZONE_ID" "$ALL_JSON"

# I25. no record_id leak
assert_not_contains "I25: no record_id" "record_id" "$ALL_JSON"

# I26. no api_env_path leak
assert_not_contains "I26: no api_env_path" "api_env_path" "$ALL_JSON"

# ── Section J: JSON safety ─────────────────────────────────────────────────

echo ""
echo "=== Section J: JSON safety ==="

# J27. JSON parseable
if echo "$ALL_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  ok "J27: JSON parseable"
else
  fail "J27: JSON not parseable"
fi

# J28. JSON has safety read_only
assert_json_field "J28: JSON safety read_only" "$ALL_JSON" "d['safety']" "read_only"

# J29. JSON has blocked field
if echo "$ALL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'blocked' in d" 2>/dev/null; then
  ok "J29: JSON has blocked field"
else
  fail "J29: JSON missing blocked field"
fi

# ── Section K: Conflict state blocking ─────────────────────────────────────

echo ""
echo "=== Section K: Conflict state blocking ==="

# K30. conflict state does not advance to DNS apply
# When there's a conflict, next_step should be ask_custom_subdomain, not review_dns_plan
CONFLICT_JSON=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_subdomain_conflict_ux import plan_subdomain
result = plan_subdomain('example.com', availability={
    'proxy.example.com': 'occupied',
    'web.example.com': 'occupied'
})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "K30: conflict blocks DNS apply" "$CONFLICT_JSON" "d['next_step']" "ask_custom_subdomain"

# ── Section L: Integration with beginner flow ──────────────────────────────

echo ""
echo "=== Section L: Integration with beginner flow ==="

mkdir -p "$FAKE_HOME/.nanobk"
cat > "$FAKE_HOME/.nanobk/setup-profile.json" << 'PROF'
{"version": 1, "zone_name": "example.com", "api_env_path": "/tmp/fake.env", "nodes": ["proxy", "web"], "created_by": "test"}
PROF
chmod 600 "$FAKE_HOME/.nanobk/setup-profile.json"

# Test beginner flow with subdomain conflict
FLOW_CONFLICT_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(
    ip_fixture={'ipv4': 'detected', 'ipv6': 'unknown'},
    subdomain_fixture={'availability': {'proxy.example.com': 'occupied', 'web.example.com': 'available'}}
)
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)

FLOW_CONFLICT_TEXT=$(HOME="$FAKE_HOME" python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import _gather_flow_status, _build_steps, render_flow_text
status = _gather_flow_status(
    ip_fixture={'ipv4': 'detected', 'ipv6': 'unknown'},
    subdomain_fixture={'availability': {'proxy.example.com': 'occupied', 'web.example.com': 'available'}}
)
steps = _build_steps(status)
print(render_flow_text(steps, status))
" 2>&1)

# L31. flow shows conflict message
assert_contains "L31: flow shows conflict" "这个名字已经被用了" "$FLOW_CONFLICT_TEXT"

# L32. flow next_step is ask_custom_subdomain
assert_json_field "L32: flow next_step ask_custom_subdomain" "$FLOW_CONFLICT_JSON" "d['next_step']" "ask_custom_subdomain"

# L33. flow stage is dns_conflict
assert_json_field "L33: flow stage dns_conflict" "$FLOW_CONFLICT_JSON" "d['stage']" "dns_conflict"

# ── Section M: Regression tests ────────────────────────────────────────────

echo ""
echo "=== Section M: Regression tests ==="

# M34. v2.4.2 beginner flow test still passes
V242_TEST="$REPO_DIR/tests/v2.4.2-beginner-flow-renderer.sh"
if [[ -f "$V242_TEST" ]]; then
  if bash "$V242_TEST" >/dev/null 2>&1; then
    ok "M34: v2.4.2 beginner flow test still passes"
  else
    fail "M34: v2.4.2 beginner flow test failed"
  fi
else
  fail "M34: v2.4.2 test not found"
fi

# M35. v2.4.1 CLI home test still passes
V241_TEST="$REPO_DIR/tests/v2.4.1-cli-home-ux.sh"
if [[ -f "$V241_TEST" ]]; then
  if bash "$V241_TEST" >/dev/null 2>&1; then
    ok "M35: v2.4.1 CLI home test still passes"
  else
    fail "M35: v2.4.1 CLI home test failed"
  fi
else
  fail "M35: v2.4.1 test not found"
fi

# M36. v2.4.0 scope test still passes
V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if bash "$V240_TEST" >/dev/null 2>&1; then
    ok "M36: v2.4.0 scope test still passes"
  else
    fail "M36: v2.4.0 scope test failed"
  fi
else
  fail "M36: v2.4.0 test not found"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=============================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL ${PASS} TESTS PASSED"
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
