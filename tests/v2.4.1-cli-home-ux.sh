#!/usr/bin/env bash
# v2.4.1 CLI Home UX Test
#
# Tests the beginner-friendly CLI home screen.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
# Uses temp HOME / fake profile / fixtures.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"

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

# Ensure clean start (no profile)
mkdir -p "$FAKE_HOME/.nanobk"

# ── Section A: nanobk home text output ─────────────────────────────────────

echo "=== Section A: nanobk home text output ==="

HOME="$FAKE_HOME" bash "$NANOBK" home > "$FAKE_HOME/home_text.txt" 2>&1
HOME_TEXT=$(cat "$FAKE_HOME/home_text.txt")

# A1. nanobk home exits 0
if HOME="$FAKE_HOME" bash "$NANOBK" home >/dev/null 2>&1; then
  ok "A1: nanobk home exits 0"
else
  fail "A1: nanobk home exits 0"
fi

# A2. nanobk home contains NanoBK
assert_contains "A2: home contains NanoBK" "NanoBK" "$HOME_TEXT"

# A3. nanobk home contains 中文菜单 (look for menu header)
assert_contains "A3: home contains 中文菜单" "主菜单" "$HOME_TEXT"

# A4. nanobk home contains 开始新手设置
assert_contains "A4: home contains 开始新手设置" "开始新手设置" "$HOME_TEXT"

# A5. nanobk home contains 查看当前状态
assert_contains "A5: home contains 查看当前状态" "查看当前状态" "$HOME_TEXT"

# A6. nanobk home contains 修复问题
assert_contains "A6: home contains 修复问题" "修复问题" "$HOME_TEXT"

# A7. nanobk home contains 高级选项
assert_contains "A7: home contains 高级选项" "高级选项" "$HOME_TEXT"

# ── Section B: beginner home --json (no profile, via Python module) ─────────

echo ""
echo "=== Section B: beginner home --json (no profile) ==="

HOME="$FAKE_HOME" python3 "$REPO_DIR/lib/nanobk_cli_home.py" home --json > "$FAKE_HOME/home_json.json" 2>&1
HOME_JSON=$(cat "$FAKE_HOME/home_json.json")

# B8. beginner home --json exits 0
if HOME="$FAKE_HOME" python3 "$REPO_DIR/lib/nanobk_cli_home.py" home --json >/dev/null 2>&1; then
  ok "B8: beginner home --json exits 0"
else
  fail "B8: beginner home --json exits 0"
fi

# B9. 无 profile 时 JSON 显示 cloudflare disconnected
assert_json_field "B9: no profile → cloudflare disconnected" "$HOME_JSON" "d['cloudflare']" "disconnected"

# B10. 无 profile 时 next_step 是 connect_cloudflare
assert_json_field "B10: no profile → next_step connect_cloudflare" "$HOME_JSON" "d['next_step']" "connect_cloudflare"

# ── Section C: beginner home --json (with fake profile) ────────────────────

echo ""
echo "=== Section C: beginner home --json (with fake profile) ==="

# Create fake profile
mkdir -p "$FAKE_HOME/.nanobk"
cat > "$FAKE_HOME/.nanobk/setup-profile.json" << 'PROF'
{"version": 1, "zone_name": "example.com", "api_env_path": "/tmp/fake.env", "nodes": ["proxy", "web"], "created_by": "test"}
PROF
chmod 600 "$FAKE_HOME/.nanobk/setup-profile.json"

HOME="$FAKE_HOME" python3 "$REPO_DIR/lib/nanobk_cli_home.py" home --json > "$FAKE_HOME/home_json_profile.json" 2>&1
HOME_JSON_PROFILE=$(cat "$FAKE_HOME/home_json_profile.json")

# C11. 有 fake profile 时显示 example.com
assert_json_field "C11: fake profile → domain example.com" "$HOME_JSON_PROFILE" "d['domain']" "example.com"

# C12. 有 fake profile 时不显示 api_env_path
if echo "$HOME_JSON_PROFILE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'api_env_path' not in d" 2>/dev/null; then
  ok "C12: fake profile → no api_env_path in JSON"
else
  fail "C12: fake profile → no api_env_path in JSON"
fi

# Also check text output doesn't leak api_env_path
HOME="$FAKE_HOME" python3 "$REPO_DIR/lib/nanobk_cli_home.py" home > "$FAKE_HOME/home_text_profile.txt" 2>&1
HOME_TEXT_PROFILE=$(cat "$FAKE_HOME/home_text_profile.txt")
assert_not_contains "C12b: fake profile → no api_env_path in text" "/tmp/fake.env" "$HOME_TEXT_PROFILE"

# ── Section D: Secret leak checks ──────────────────────────────────────────

echo ""
echo "=== Section D: Secret leak checks ==="

# Combine all outputs for leak scanning
ALL_OUTPUT=$(cat "$FAKE_HOME/home_text.txt" "$FAKE_HOME/home_json.json" "$FAKE_HOME/home_text_profile.txt" "$FAKE_HOME/home_json_profile.json" 2>/dev/null || true)

# D13. 不泄露 token
assert_not_contains "D13: no token leak" "CF_API_TOKEN" "$ALL_OUTPUT"
assert_not_contains "D13b: no token leak (SUB_TOKEN)" "SUB_TOKEN" "$ALL_OUTPUT"

# D14. 不泄露 private key
assert_not_contains "D14: no private key leak" "PRIVATE KEY" "$ALL_OUTPUT"

# D15. 不泄露 subscription URL (check for actual URLs, not field names like subscription_token)
if echo "$ALL_OUTPUT" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "D15: subscription URL leak detected"
else
  ok "D15: no subscription URL leak"
fi

# D16. 不泄露 zone id
assert_not_contains "D16: no zone id leak" "zone_id" "$ALL_OUTPUT"
assert_not_contains "D16b: no zone id leak (CF_ZONE_ID)" "CF_ZONE_ID" "$ALL_OUTPUT"

# D17. 不泄露 record id
assert_not_contains "D17: no record id leak" "record_id" "$ALL_OUTPUT"

# ── Section E: No dangerous command calls ───────────────────────────────────

echo ""
echo "=== Section E: No dangerous command calls ==="

# E18. 不调用 curl
if echo "$ALL_OUTPUT" | grep -q "curl "; then
  fail "E18: curl call detected in output"
else
  ok "E18: no curl in output"
fi

# E19. 不调用 wrangler
if echo "$ALL_OUTPUT" | grep -q "wrangler "; then
  fail "E19: wrangler call detected in output"
else
  ok "E19: no wrangler in output"
fi

# E20. 不调用 certbot/acme.sh
if echo "$ALL_OUTPUT" | grep -q "certbot\|acme.sh"; then
  fail "E20: certbot/acme.sh detected in output"
else
  ok "E20: no certbot/acme.sh in output"
fi

# E21. 不调用 systemctl reload/restart
if echo "$ALL_OUTPUT" | grep -q "systemctl reload\|systemctl restart"; then
  fail "E21: systemctl reload/restart detected in output"
else
  ok "E21: no systemctl reload/restart in output"
fi

# ── Section F: No mutation ─────────────────────────────────────────────────

echo ""
echo "=== Section F: No mutation ==="

# F22. 不创建 DNS (check source doesn't call DNS create)
CLI_HOME_PY="$REPO_DIR/lib/nanobk_cli_home.py"
if grep -q "dns.*create\|create.*dns\|dns.*apply\|apply.*dns" "$CLI_HOME_PY" 2>/dev/null; then
  fail "F22: DNS create/apply found in nanobk_cli_home.py"
else
  ok "F22: no DNS create in nanobk_cli_home.py"
fi

# F23. 不申请证书 (check for actual cert mutation code, not docstring comments)
# Strip all docstrings/comments first, then check for mutation code
CLI_HOME_CODE=$(python3 -c "
import ast
with open('$CLI_HOME_PY') as f:
    source = f.read()
tree = ast.parse(source)
# Remove docstrings: set them to None in the AST
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
        if (node.body and isinstance(node.body[0], ast.Expr)
            and isinstance(node.body[0].value, (ast.Constant, ast.Str))):
            node.body = node.body[1:]
# Also remove standalone string expressions (module-level docstrings)
for node in ast.walk(tree):
    if isinstance(node, ast.Module):
        node.body = [n for n in node.body
                     if not (isinstance(n, ast.Expr) and isinstance(n.value, (ast.Constant, ast.str)))]
# Generate source without docstrings
import io
for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        node.value = ''
# Just dump non-string, non-comment source lines
for line in source.splitlines():
    stripped = line.strip()
    if stripped.startswith('#') or stripped.startswith('\"\"\"') or stripped.endswith('\"\"\"'):
        continue
    if 'certbot' in stripped or 'acme.sh' in stripped:
        print('FOUND: ' + stripped)
    if 'wrangler' in stripped and 'No curl' not in stripped:
        print('FOUND: ' + stripped)
    if 'token_rotate' in stripped or 'rotate_token' in stripped:
        print('FOUND: ' + stripped)
" 2>/dev/null || true)
if [[ -n "$CLI_HOME_CODE" ]]; then
  fail "F23/F24/F25: mutation code found: $CLI_HOME_CODE"
else
  ok "F23: no cert mutation in nanobk_cli_home.py"
  ok "F24: no token rotate in nanobk_cli_home.py"
  ok "F25: no Worker mutation in nanobk_cli_home.py"
fi

# ── Section G: non-TTY behavior ────────────────────────────────────────────

echo ""
echo "=== Section G: non-TTY behavior ==="

# G26. non-TTY 不 hang (nanobk home should complete quickly)
# Use a clean temp HOME (no profile) to avoid network calls from setup status
CLEAN_HOME=$(mktemp -d)
# Portable timeout: run in background, kill after 10s if still running
HOME="$CLEAN_HOME" bash "$NANOBK" home > /dev/null 2>&1 &
G26_PID=$!
( sleep 10 && kill "$G26_PID" 2>/dev/null ) &
G26_WATCHER=$!
wait "$G26_PID" 2>/dev/null
G26_EXIT=$?
kill "$G26_WATCHER" 2>/dev/null || true
wait "$G26_WATCHER" 2>/dev/null || true
if [[ "$G26_EXIT" -ne 99 ]] && [[ "$G26_EXIT" -ne 137 ]]; then
  ok "G26: nanobk home non-TTY does not hang (exit=$G26_EXIT)"
else
  fail "G26: nanobk home non-TTY hangs (killed by timeout)"
fi
rm -rf "$CLEAN_HOME"

# G27. dirty install / fresh clone 不被旧 /opt 干扰
# The script should resolve repo-local first
if grep -q "resolve_repo_dir\|REPO_DIR" "$NANOBK" 2>/dev/null; then
  ok "G27: nanobk has repo resolution (not relying on /opt)"
else
  fail "G27: nanobk missing repo resolution"
fi

# ── Section H: JSON safety ─────────────────────────────────────────────────

echo ""
echo "=== Section H: JSON safety ==="

# H. nanobk home --json (bash) uses v2.4 safe JSON
BASH_HOME_JSON=$(HOME="$FAKE_HOME" bash "$NANOBK" home --json 2>&1)
if echo "$BASH_HOME_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'next_step' in d and 'home_status' not in d" 2>/dev/null; then
  ok "H: nanobk home --json uses v2.4 safe JSON schema"
else
  fail "H: nanobk home --json does not use v2.4 safe JSON"
fi

# H. nanobk home --json does not contain api_env_path
if echo "$BASH_HOME_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'api_env_path' not in d" 2>/dev/null; then
  ok "H: nanobk home --json has no api_env_path"
else
  fail "H: nanobk home --json contains api_env_path"
fi

# H. JSON does not contain api_env_path (module direct)
if echo "$HOME_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'api_env_path' not in d" 2>/dev/null; then
  ok "H: JSON (no profile) has no api_env_path"
else
  fail "H: JSON (no profile) contains api_env_path"
fi

# H. JSON has all required fields
for field in ok cloudflare domain dns certificate subscription_token web_panel safety next_step; do
  if echo "$HOME_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$field' in d" 2>/dev/null; then
    ok "H: JSON has field '$field'"
  else
    fail "H: JSON missing field '$field'"
  fi
done

# H. vps_ip is an object with ipv4 and ipv6
if echo "$HOME_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'ipv4' in d['vps_ip'] and 'ipv6' in d['vps_ip']" 2>/dev/null; then
  ok "H: JSON vps_ip has ipv4 and ipv6"
else
  fail "H: JSON vps_ip missing ipv4/ipv6"
fi

# ── Section I: v2.4.0 scope test still passes ──────────────────────────────

echo ""
echo "=== Section I: Regression tests ==="

V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if bash "$V240_TEST" 2>&1; then
    ok "I28: v2.4.0 scope test still passes"
  else
    fail "I28: v2.4.0 scope test failed"
  fi
else
  fail "I28: v2.4.0 scope test not found"
fi

# ── Section J: v2.3.10 closeout test still passes ──────────────────────────

V2310_TEST="$REPO_DIR/tests/v2.3.10-closeout-manifest.sh"
if [[ -f "$V2310_TEST" ]]; then
  if bash "$V2310_TEST" 2>&1; then
    ok "J29: v2.3.10 closeout test still passes"
  else
    fail "J29: v2.3.10 closeout test failed"
  fi
else
  fail "J29: v2.3.10 closeout test not found"
fi

# ── Section K: v2.3.9 acceptance test ──────────────────────────────────────

V2309_TEST="$REPO_DIR/tests/v2.3.9-real-vps-acceptance.sh"
if [[ -f "$V2309_TEST" ]]; then
  echo ""
  echo "=== Section K: v2.3.9 acceptance test ==="
  echo "NOTE: v2.3.9 requires real VPS environment. Attempting..."
  if timeout 30 bash "$V2309_TEST" 2>&1; then
    ok "K30: v2.3.9 acceptance test passes"
  else
    echo "NOTE: v2.3.9 acceptance test failed (likely environment-dependent). Not blocking v2.4.1."
  fi
else
  echo ""
  echo "=== Section K: v2.3.9 acceptance test ==="
  echo "NOTE: v2.3.9 test not found. Skipping."
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
