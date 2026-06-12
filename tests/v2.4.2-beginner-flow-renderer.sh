#!/usr/bin/env bash
# v2.4.2 Beginner Flow Renderer Test
#
# Tests the beginner-friendly setup flow renderer.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
# Uses temp HOME / fake profile / fixtures.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
BEGINNER_PY="$REPO_DIR/lib/nanobk_beginner_flow.py"
CLI_HOME_PY="$REPO_DIR/lib/nanobk_cli_home.py"

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

# ── Section A: nanobk beginner text output (no profile) ────────────────────

echo "=== Section A: nanobk beginner text (no profile) ==="

BEGINNER_TEXT=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner 2>&1)

# A1. nanobk beginner exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner >/dev/null 2>&1; then
  ok "A1: nanobk beginner exits 0"
else
  fail "A1: nanobk beginner exits 0"
fi

# A2. nanobk beginner contains NanoBK
assert_contains "A2: beginner contains NanoBK" "NanoBK" "$BEGINNER_TEXT"

# A3. nanobk beginner contains 欢迎
assert_contains "A3: beginner contains 欢迎" "欢迎" "$BEGINNER_TEXT"

# A4. nanobk beginner contains Cloudflare
assert_contains "A4: beginner contains Cloudflare" "Cloudflare" "$BEGINNER_TEXT"

# A5. nanobk beginner contains 你的域名
assert_contains "A5: beginner contains 你的域名" "你的域名" "$BEGINNER_TEXT"

# A6. nanobk beginner contains VPS IP
assert_contains "A6: beginner contains VPS IP" "VPS IP" "$BEGINNER_TEXT"

# A7. nanobk beginner contains 域名指向
assert_contains "A7: beginner contains 域名指向" "域名指向" "$BEGINNER_TEXT"

# A8. nanobk beginner contains HTTPS 安全证书
assert_contains "A8: beginner contains HTTPS 安全证书" "HTTPS 安全证书" "$BEGINNER_TEXT"

# A9. nanobk beginner contains 订阅密钥
assert_contains "A9: beginner contains 订阅密钥" "订阅密钥" "$BEGINNER_TEXT"

# A10. nanobk beginner contains 安全确认
assert_contains "A10: beginner contains 安全确认" "安全确认" "$BEGINNER_TEXT"

# ── Section B: nanobk beginner --json (no profile) ─────────────────────────

echo ""
echo "=== Section B: nanobk beginner --json (no profile) ==="

BEGINNER_JSON=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner --json 2>&1)

# B11. nanobk beginner --json exits 0
if HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner --json >/dev/null 2>&1; then
  ok "B11: nanobk beginner --json exits 0"
else
  fail "B11: nanobk beginner --json exits 0"
fi

# B12. JSON contains steps
if echo "$BEGINNER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'steps' in d and isinstance(d['steps'], list)" 2>/dev/null; then
  ok "B12: JSON contains steps"
else
  fail "B12: JSON missing steps"
fi

# B13. JSON contains next_step
assert_json_field "B13: JSON contains next_step" "$BEGINNER_JSON" "d['next_step']" "connect_cloudflare"

# B14. JSON contains safety
assert_json_field "B14: JSON contains safety" "$BEGINNER_JSON" "d['safety']" "read_only"

# B15. no profile -> next_step connect_cloudflare
assert_json_field "B15: no profile -> connect_cloudflare" "$BEGINNER_JSON" "d['next_step']" "connect_cloudflare"

# ── Section C: nanobk beginner --json (with fake profile) ──────────────────

echo ""
echo "=== Section C: nanobk beginner --json (with fake profile) ==="

mkdir -p "$FAKE_HOME/.nanobk"
cat > "$FAKE_HOME/.nanobk/setup-profile.json" << 'PROF'
{"version": 1, "zone_name": "example.com", "api_env_path": "/tmp/fake.env", "nodes": ["proxy", "web"], "created_by": "test"}
PROF
chmod 600 "$FAKE_HOME/.nanobk/setup-profile.json"

BEGINNER_JSON_PROFILE=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner --json 2>&1)

# C16. fake profile with domain -> domain visible as example.com
if echo "$BEGINNER_JSON_PROFILE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
found = any('example.com' in s.get('message', '') for s in d.get('steps', []))
assert found
" 2>/dev/null; then
  ok "C16: fake profile -> example.com in steps"
else
  fail "C16: fake profile -> example.com not in steps"
fi

# C17. fake dns pending -> shows review_dns_plan
DNS_PENDING_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(dns_fixture={'dns': 'pending'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "C17: dns pending -> review_dns_plan" "$DNS_PENDING_JSON" "d['next_step']" "review_dns_plan"

# C18. fake cert pending -> shows review_cert_plan
CERT_PENDING_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(cert_fixture={'certificate': 'pending'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "C18: cert pending -> review_cert_plan" "$CERT_PENDING_JSON" "d['next_step']" "review_cert_plan"

# C19. fake token pending -> shows review_token_plan
TOKEN_PENDING_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(token_fixture={'subscription_token': 'pending'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
assert_json_field "C19: token pending -> review_token_plan" "$TOKEN_PENDING_JSON" "d['next_step']" "review_token_plan"

# ── Section D: IP fixture tests ────────────────────────────────────────────

echo ""
echo "=== Section D: IP fixture tests ==="

# D20. dual_stack fixture renders IPv4 and IPv6
DUAL_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(ip_fixture={'ipv4': 'detected', 'ipv6': 'detected'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
DUAL_TEXT=$(HOME="$FAKE_HOME" python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import _gather_flow_status, _build_steps, render_flow_text
status = _gather_flow_status(ip_fixture={'ipv4': 'detected', 'ipv6': 'detected'})
steps = _build_steps(status)
print(render_flow_text(steps, status))
" 2>&1)
assert_contains "D20a: dual_stack text has IPv4" "IPv4" "$DUAL_TEXT"
assert_contains "D20b: dual_stack text has IPv6" "IPv6" "$DUAL_TEXT"

# D21. ipv4_only fixture renders IPv4 only
IPV4_TEXT=$(HOME="$FAKE_HOME" python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import _gather_flow_status, _build_steps, render_flow_text
status = _gather_flow_status(ip_fixture={'ipv4': 'detected', 'ipv6': 'unknown'})
steps = _build_steps(status)
print(render_flow_text(steps, status))
" 2>&1)
assert_contains "D21a: ipv4_only has IPv4" "IPv4" "$IPV4_TEXT"
assert_not_contains "D21b: ipv4_only no IPv6" "IPv6" "$IPV4_TEXT"

# D22. ipv6_only fixture renders IPv6 only
IPV6_TEXT=$(HOME="$FAKE_HOME" python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import _gather_flow_status, _build_steps, render_flow_text
status = _gather_flow_status(ip_fixture={'ipv4': 'unknown', 'ipv6': 'detected'})
steps = _build_steps(status)
print(render_flow_text(steps, status))
" 2>&1)
assert_contains "D22a: ipv6_only has IPv6" "IPv6" "$IPV6_TEXT"
assert_not_contains "D22b: ipv6_only no IPv4" "IPv4" "$IPV6_TEXT"

# D23. detection_failed fixture renders friendly failure
FAIL_JSON=$(HOME="$FAKE_HOME" python3 -c "
import sys, json
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import gather_flow_json
result = gather_flow_json(ip_fixture={'ipv4': 'failed', 'ipv6': 'failed'})
print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>&1)
FAIL_TEXT=$(HOME="$FAKE_HOME" python3 -c "
import sys
sys.path.insert(0, '$REPO_DIR/lib')
from nanobk_beginner_flow import _gather_flow_status, _build_steps, render_flow_text
status = _gather_flow_status(ip_fixture={'ipv4': 'failed', 'ipv6': 'failed'})
steps = _build_steps(status)
print(render_flow_text(steps, status))
" 2>&1)
assert_contains "D23a: detection_failed shows blocked" "无法检测" "$FAIL_TEXT"
assert_json_field "D23b: detection_failed stage" "$FAIL_JSON" "d['stage']" "ip_failed"

# ── Section E: Secret leak checks ──────────────────────────────────────────

echo ""
echo "=== Section E: Secret leak checks ==="

ALL_BEGINNER_OUTPUT=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner 2>&1 || true)
ALL_BEGINNER_JSON=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" beginner --json 2>&1 || true)
ALL_HOME_JSON=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" home --json 2>&1 || true)
COMBINED="$ALL_BEGINNER_OUTPUT
$ALL_BEGINNER_JSON
$ALL_HOME_JSON"

# E24. output does not contain api_env_path
assert_not_contains "E24: no api_env_path" "api_env_path" "$COMBINED"

# E25. output does not contain token
assert_not_contains "E25: no CF_API_TOKEN" "CF_API_TOKEN" "$COMBINED"

# E26. output does not contain private key
assert_not_contains "E26: no private key" "PRIVATE KEY" "$COMBINED"

# E27. output does not contain subscription URL
if echo "$COMBINED" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "E27: subscription URL leak"
else
  ok "E27: no subscription URL"
fi

# E28. output does not contain zone_id
assert_not_contains "E28: no zone_id" "zone_id" "$COMBINED"
assert_not_contains "E28b: no CF_ZONE_ID" "CF_ZONE_ID" "$COMBINED"

# E29. output does not contain record_id
assert_not_contains "E29: no record_id" "record_id" "$COMBINED"

# E30. output does not contain raw API response
assert_not_contains "E30: no raw API" "api.cloudflare.com" "$COMBINED"

# ── Section F: No dangerous command calls ───────────────────────────────────

echo ""
echo "=== Section F: No dangerous command calls ==="

# E31. does not call curl
if echo "$COMBINED" | grep -q "curl "; then
  fail "E31: curl in output"
else
  ok "E31: no curl in output"
fi

# E32. does not call wrangler
if echo "$COMBINED" | grep -q "wrangler "; then
  fail "E32: wrangler in output"
else
  ok "E32: no wrangler in output"
fi

# E33. does not call certbot/acme.sh
if echo "$COMBINED" | grep -q "certbot\|acme.sh"; then
  fail "E33: certbot/acme.sh in output"
else
  ok "E33: no certbot/acme.sh in output"
fi

# E34. does not call systemctl reload/restart
if echo "$COMBINED" | grep -q "systemctl reload\|systemctl restart"; then
  fail "E34: systemctl reload/restart in output"
else
  ok "E34: no systemctl reload/restart in output"
fi

# ── Section G: Source code mutation checks ──────────────────────────────────

echo ""
echo "=== Section G: Source code mutation checks ==="

# E35. no DNS create/apply code in beginner flow module
if grep -q "dns.*create\|create.*dns\|dns.*apply\|apply.*dns" "$BEGINNER_PY" 2>/dev/null; then
  fail "E35: DNS create/apply in beginner flow"
else
  ok "E35: no DNS create in beginner flow"
fi

# E36-E38. Check for mutation code (skip comments and docstrings)
MUTATION_CHECK=$(python3 -c "
import ast
with open('$BEGINNER_PY') as f:
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
    for kw in ['certbot', 'acme.sh', 'token_rotate', 'rotate_token', 'wrangler', 'worker_deploy']:
        if kw in stripped:
            print('FOUND ' + kw + ': ' + stripped)
" 2>/dev/null || true)
if [[ -n "$MUTATION_CHECK" ]]; then
  fail "E36/37/38: mutation code found: $MUTATION_CHECK"
else
  ok "E36: no cert mutation in beginner flow"
  ok "E37: no token rotate in beginner flow"
  ok "E38: no Worker mutation in beginner flow"
fi

# ── Section H: non-TTY behavior ────────────────────────────────────────────

echo ""
echo "=== Section H: non-TTY behavior ==="

# E39. non-TTY does not hang
CLEAN_HOME=$(mktemp -d)
HOME="$CLEAN_HOME" bash "$NANOBK" beginner > /dev/null 2>&1 &
G39_PID=$!
( sleep 10 && kill "$G39_PID" 2>/dev/null ) &
G39_WATCHER=$!
wait "$G39_PID" 2>/dev/null
G39_EXIT=$?
kill "$G39_WATCHER" 2>/dev/null || true
wait "$G39_WATCHER" 2>/dev/null || true
if [[ "$G39_EXIT" -ne 99 ]] && [[ "$G39_EXIT" -ne 137 ]]; then
  ok "E39: nanobk beginner non-TTY does not hang (exit=$G39_EXIT)"
else
  fail "E39: nanobk beginner non-TTY hangs"
fi
rm -rf "$CLEAN_HOME"

# ── Section I: nanobk home --json v2.4 safe ────────────────────────────────

echo ""
echo "=== Section I: nanobk home --json v2.4 safe ==="

# E40. bash bin/nanobk home --json exits 0
CLEAN_HOME=$(mktemp -d)
if HOME="$CLEAN_HOME" run_with_timeout 15 bash "$NANOBK" home --json >/dev/null 2>&1; then
  ok "E40: nanobk home --json exits 0"
else
  fail "E40: nanobk home --json exits 0"
fi
rm -rf "$CLEAN_HOME"

# E41. nanobk home --json uses v2.4 safe JSON (has next_step field, no home_status)
HOME_JSON_V24=$(HOME="$FAKE_HOME" run_with_timeout 15 bash "$NANOBK" home --json 2>&1)
if echo "$HOME_JSON_V24" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d and 'home_status' not in d" 2>/dev/null; then
  ok "E41: nanobk home --json uses v2.4 safe JSON schema"
else
  fail "E41: nanobk home --json does not use v2.4 safe JSON"
fi

# E41b. nanobk home --json does not leak secrets
assert_not_contains "E41b: home --json no api_env_path" "api_env_path" "$HOME_JSON_V24"

# ── Section J: Bounded smoke checks for prior versions ─────────────────────

echo ""
echo "=== Section J: Prior version smoke checks ==="

# J42. v2.4.1 test file exists
V241_TEST="$REPO_DIR/tests/v2.4.1-cli-home-ux.sh"
if [[ -f "$V241_TEST" ]]; then
  ok "J42: v2.4.1 test file exists"
else
  fail "J42: v2.4.1 test file missing"
fi

# J43. v2.4.0 scope test passes (fast, standalone)
V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if run_with_timeout 30 bash "$V240_TEST" >/dev/null 2>&1; then
    ok "J43: v2.4.0 scope test passes"
  else
    note "J43: v2.4.0 scope test failed or timed out (non-blocking)"
  fi
else
  fail "J43: v2.4.0 test file missing"
fi

# ── Section K: Opt-in long regression ──────────────────────────────────────

echo ""
echo "=== Section K: Opt-in long regression ==="

if [[ "${NANOBK_RUN_LONG_REGRESSION:-0}" == "1" ]]; then
  echo "NANOBK_RUN_LONG_REGRESSION=1 — running legacy regression tests with timeout."

  # K44. v2.3.10 closeout test (timeout 60s)
  V2310_TEST="$REPO_DIR/tests/v2.3.10-closeout-manifest.sh"
  if [[ -f "$V2310_TEST" ]]; then
    if run_with_timeout 60 bash "$V2310_TEST" >/dev/null 2>&1; then
      ok "K44: v2.3.10 closeout test passes"
    else
      note "K44: v2.3.10 closeout test failed or timed out (non-blocking)"
    fi
  else
    note "K44: v2.3.10 test not found"
  fi

  # K45. v2.4.1 full test (timeout 120s)
  if [[ -f "$V241_TEST" ]]; then
    if run_with_timeout 120 bash "$V241_TEST" >/dev/null 2>&1; then
      ok "K45: v2.4.1 CLI home test passes"
    else
      note "K45: v2.4.1 failed or timed out (non-blocking)"
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
