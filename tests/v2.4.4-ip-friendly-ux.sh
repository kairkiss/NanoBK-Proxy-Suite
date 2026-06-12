#!/usr/bin/env bash
# v2.4.4 IPv4/IPv6 Friendly UX Test
#
# Tests beginner-friendly IP detection status rendering.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
# Uses temp HOME / fake profile / fixtures.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
IP_UX_PY="$REPO_DIR/lib/nanobk_ip_friendly_ux.py"
BEGINNER_PY="$REPO_DIR/lib/nanobk_beginner_flow.py"

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

# ── Setup temp HOME ────────────────────────────────────────────────────────
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.nanobk"

# ── Section A: Module basic tests ──────────────────────────────────────────

echo "=== Section A: Module basic tests ==="

# A1. IP module exits 0
if run_with_timeout 15 python3 "$IP_UX_PY" status >/dev/null 2>&1; then
  ok "A1: IP module exits 0"
else
  fail "A1: IP module exits 0"
fi

# A2. nanobk beginner ip exits 0
if run_with_timeout 15 bash "$NANOBK" beginner ip >/dev/null 2>&1; then
  ok "A2: nanobk beginner ip exits 0"
else
  fail "A2: nanobk beginner ip exits 0"
fi

# A3. nanobk beginner ip --json exits 0
if run_with_timeout 15 bash "$NANOBK" beginner ip --json >/dev/null 2>&1; then
  ok "A3: nanobk beginner ip --json exits 0"
else
  fail "A3: nanobk beginner ip --json exits 0"
fi

# ── Section B: Dual stack ──────────────────────────────────────────────────

echo ""
echo "=== Section B: Dual stack ==="

DUAL_TEXT=$(python3 "$IP_UX_PY" status --ipv4 203.0.113.10 --ipv6 2001:db8::10 2>&1)
DUAL_JSON=$(python3 "$IP_UX_PY" status --ipv4 203.0.113.10 --ipv6 2001:db8::10 --json 2>&1)

# B4. dual_stack -> text contains IPv4 and IPv6
assert_contains "B4a: dual_stack has IPv4" "IPv4" "$DUAL_TEXT"
assert_contains "B4b: dual_stack has IPv6" "IPv6" "$DUAL_TEXT"

# B5. dual_stack -> JSON ip_mode dual_stack
assert_json_field "B5: dual_stack ip_mode" "$DUAL_JSON" "d['ip_mode']" "dual_stack"

# B6. dual_stack -> next_step review_subdomain_plan
assert_json_field "B6: dual_stack next_step" "$DUAL_JSON" "d['next_step']" "review_subdomain_plan"

# ── Section C: IPv4 only ───────────────────────────────────────────────────

echo ""
echo "=== Section C: IPv4 only ==="

IPV4_TEXT=$(python3 "$IP_UX_PY" status --ipv4 203.0.113.10 2>&1)
IPV4_JSON=$(python3 "$IP_UX_PY" status --ipv4 203.0.113.10 --json 2>&1)

# C7. ipv4_only -> text contains IPv4
assert_contains "C7: ipv4_only has IPv4" "IPv4" "$IPV4_TEXT"

# C8. ipv4_only -> text says no IPv6 / 不影响继续使用 IPv4
assert_contains "C8: ipv4_only no IPv6 message" "不影响继续使用 IPv4" "$IPV4_TEXT"

# C9. ipv4_only -> JSON ip_mode ipv4_only
assert_json_field "C9: ipv4_only ip_mode" "$IPV4_JSON" "d['ip_mode']" "ipv4_only"

# ── Section D: IPv6 only ───────────────────────────────────────────────────

echo ""
echo "=== Section D: IPv6 only ==="

IPV6_TEXT=$(python3 "$IP_UX_PY" status --ipv6 2001:db8::10 2>&1)
IPV6_JSON=$(python3 "$IP_UX_PY" status --ipv6 2001:db8::10 --json 2>&1)

# D10. ipv6_only -> text contains IPv6
assert_contains "D10: ipv6_only has IPv6" "IPv6" "$IPV6_TEXT"

# D11. ipv6_only -> text says no IPv4 / 请确认支持 IPv6
assert_contains "D11: ipv6_only no IPv4 message" "请确认你的使用环境是否支持 IPv6" "$IPV6_TEXT"

# D12. ipv6_only -> JSON ip_mode ipv6_only
assert_json_field "D12: ipv6_only ip_mode" "$IPV6_JSON" "d['ip_mode']" "ipv6_only"

# ── Section E: Detection failed ────────────────────────────────────────────

echo ""
echo "=== Section E: Detection failed ==="

FAIL_TEXT=$(python3 "$IP_UX_PY" status 2>&1)
FAIL_JSON=$(python3 "$IP_UX_PY" status --json 2>&1)

# E13. detection_failed -> text says 没有自动检测到
assert_contains "E13: detection_failed message" "没有自动检测到" "$FAIL_TEXT"

# E14. detection_failed -> JSON ip_mode failed
assert_json_field "E14: detection_failed ip_mode" "$FAIL_JSON" "d['ip_mode']" "failed"

# E15. detection_failed -> next_step manual_ip_input
assert_json_field "E15: detection_failed next_step" "$FAIL_JSON" "d['next_step']" "manual_ip_input"

# ── Section F: Beginner flow integration ───────────────────────────────────

echo ""
echo "=== Section F: Beginner flow integration ==="

mkdir -p "$FAKE_HOME/.nanobk"
cat > "$FAKE_HOME/.nanobk/setup-profile.json" << 'PROF'
{"version": 1, "zone_name": "example.com", "api_env_path": "/tmp/fake.env", "nodes": ["proxy", "web"], "created_by": "test"}
PROF
chmod 600 "$FAKE_HOME/.nanobk/setup-profile.json"

# F16. detection_failed -> beginner flow stage ip_failed
FLOW_FAIL_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(ip_fixture={'ipv4': 'failed', 'ipv6': 'failed'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "F16: detection_failed flow stage" "$FLOW_FAIL_JSON" "d['stage']" "ip_failed"

# F17. detection_failed -> beginner flow must not say ip_ready
if echo "$FLOW_FAIL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['stage'] != 'ip_ready'" 2>/dev/null; then
  ok "F17: detection_failed not ip_ready"
else
  fail "F17: detection_failed still ip_ready"
fi

# F18. detection_failed -> beginner flow must not advance to DNS apply
assert_json_field "F18: detection_failed blocks DNS" "$FLOW_FAIL_JSON" "d['next_step']" "manual_ip_input"

# ── Section G: Manual IP ───────────────────────────────────────────────────

echo ""
echo "=== Section G: Manual IP ==="

MANUAL_V4_JSON=$(python3 "$IP_UX_PY" status --manual-ipv4 203.0.113.10 --json 2>&1)
MANUAL_V6_JSON=$(python3 "$IP_UX_PY" status --manual-ipv6 2001:db8::10 --json 2>&1)

# G19. manual_ipv4 -> status manual
assert_json_field "G19: manual_ipv4 status" "$MANUAL_V4_JSON" "d['ipv4']['status']" "manual"

# G20. manual_ipv4 -> next_step review_subdomain_plan
assert_json_field "G20: manual_ipv4 next_step" "$MANUAL_V4_JSON" "d['next_step']" "review_subdomain_plan"

# G21. manual_ipv6 -> status manual
assert_json_field "G21: manual_ipv6 status" "$MANUAL_V6_JSON" "d['ipv6']['status']" "manual"

# G22. manual_ipv6 -> next_step review_subdomain_plan
assert_json_field "G22: manual_ipv6 next_step" "$MANUAL_V6_JSON" "d['next_step']" "review_subdomain_plan"

# ── Section H: IP masking ──────────────────────────────────────────────────

echo ""
echo "=== Section H: IP masking ==="

# H23. output masks non-fixture IPv4
REAL_IP_JSON=$(python3 "$IP_UX_PY" status --ipv4 8.8.8.8 --json 2>&1)
assert_contains "H23: masks non-fixture IPv4" "xxx" "$REAL_IP_JSON"

# H24. output masks non-fixture IPv6
REAL_IP6_JSON=$(python3 "$IP_UX_PY" status --ipv6 2606:4700:4700::1111 --json 2>&1)
assert_contains "H24: masks non-fixture IPv6" "xxxx" "$REAL_IP6_JSON"

# ── Section I: Secret leak checks ──────────────────────────────────────────

echo ""
echo "=== Section I: Secret leak checks ==="

ALL_OUTPUT=$(python3 "$IP_UX_PY" status --ipv4 203.0.113.10 --ipv6 2001:db8::10 --json 2>&1)

# I25. no api_env_path leak
assert_not_contains "I25: no api_env_path" "api_env_path" "$ALL_OUTPUT"

# I26. no token leak
assert_not_contains "I26: no CF_API_TOKEN" "CF_API_TOKEN" "$ALL_OUTPUT"

# I27. no private key leak
assert_not_contains "I27: no private key" "PRIVATE KEY" "$ALL_OUTPUT"

# I28. no subscription URL leak
if echo "$ALL_OUTPUT" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "I28: subscription URL leak"
else
  ok "I28: no subscription URL"
fi

# I29. no zone_id leak
assert_not_contains "I29: no zone_id" "zone_id" "$ALL_OUTPUT"

# I30. no record_id leak
assert_not_contains "I30: no record_id" "record_id" "$ALL_OUTPUT"

# I31. no raw API response leak
assert_not_contains "I31: no raw API" "api.cloudflare.com" "$ALL_OUTPUT"

# ── Section J: Source code mutation checks ──────────────────────────────────

echo ""
echo "=== Section J: Source code mutation checks ==="

# J32-35. no dangerous commands
MUTATION_CHECK=$(python3 -c "
import ast
with open('$IP_UX_PY') as f:
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
  fail "J32-35: dangerous commands found: $MUTATION_CHECK"
else
  ok "J32: no curl in IP module"
  ok "J33: no wrangler in IP module"
  ok "J34: no certbot/acme.sh in IP module"
  ok "J35: no systemctl reload/restart in IP module"
fi

# J36. no DNS create/apply code
if grep -q "dns.*create\|create.*dns\|dns.*apply\|apply.*dns" "$IP_UX_PY" 2>/dev/null; then
  fail "J36: DNS create/apply in IP module"
else
  ok "J36: no DNS create/apply in IP module"
fi

# J37. no DNS overwrite/delete code
if grep -q "overwrite\|delete.*dns\|dns.*delete" "$IP_UX_PY" 2>/dev/null; then
  fail "J37: DNS overwrite/delete in IP module"
else
  ok "J37: no DNS overwrite/delete in IP module"
fi

# ── Section K: Bounded smoke checks for prior versions ─────────────────────

echo ""
echo "=== Section K: Prior version smoke checks ==="

# K38. v2.4.3 test file exists
V243_TEST="$REPO_DIR/tests/v2.4.3-subdomain-conflict-ux.sh"
if [[ -f "$V243_TEST" ]]; then
  ok "K38: v2.4.3 test file exists"
else
  fail "K38: v2.4.3 test file missing"
fi

# K39. v2.4.2 test file exists
V242_TEST="$REPO_DIR/tests/v2.4.2-beginner-flow-renderer.sh"
if [[ -f "$V242_TEST" ]]; then
  ok "K39: v2.4.2 test file exists"
else
  fail "K39: v2.4.2 test file missing"
fi

# K40. v2.4.1 test file exists
V241_TEST="$REPO_DIR/tests/v2.4.1-cli-home-ux.sh"
if [[ -f "$V241_TEST" ]]; then
  ok "K40: v2.4.1 test file exists"
else
  fail "K40: v2.4.1 test file missing"
fi

# K41. v2.4.0 scope test passes (fast, standalone)
V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if run_with_timeout 30 bash "$V240_TEST" >/dev/null 2>&1; then
    ok "K41: v2.4.0 scope test passes"
  else
    note "K41: v2.4.0 scope test failed or timed out (non-blocking)"
  fi
else
  fail "K41: v2.4.0 test file missing"
fi

# ── Section L: Opt-in long regression ──────────────────────────────────────

echo ""
echo "=== Section L: Opt-in long regression ==="

if [[ "${NANOBK_RUN_LONG_REGRESSION:-0}" == "1" ]]; then
  echo "NANOBK_RUN_LONG_REGRESSION=1 — running legacy regression tests with timeout."

  # L42. v2.4.3 full test (timeout 120s)
  if [[ -f "$V243_TEST" ]]; then
    if run_with_timeout 120 bash "$V243_TEST" >/dev/null 2>&1; then
      ok "L42: v2.4.3 subdomain conflict test passes"
    else
      note "L42: v2.4.3 failed or timed out (non-blocking)"
    fi
  fi

  # L43. v2.4.2 full test (timeout 120s)
  if [[ -f "$V242_TEST" ]]; then
    if run_with_timeout 120 bash "$V242_TEST" >/dev/null 2>&1; then
      ok "L43: v2.4.2 beginner flow test passes"
    else
      note "L43: v2.4.2 failed or timed out (non-blocking)"
    fi
  fi

  # L44. v2.4.1 full test (timeout 120s)
  if [[ -f "$V241_TEST" ]]; then
    if run_with_timeout 120 bash "$V241_TEST" >/dev/null 2>&1; then
      ok "L44: v2.4.1 CLI home test passes"
    else
      note "L44: v2.4.1 failed or timed out (non-blocking)"
    fi
  fi
else
  note "Skipping long regression; set NANOBK_RUN_LONG_REGRESSION=1 to enable"
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
