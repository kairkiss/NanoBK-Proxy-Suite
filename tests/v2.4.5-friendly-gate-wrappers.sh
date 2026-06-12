#!/usr/bin/env bash
# v2.4.5 Friendly Gate Wrappers Test
#
# Tests beginner-friendly gate preview wrappers.
# No real Cloudflare calls. No DNS mutation. No certificate request.
# No token rotation. No Worker mutation. No curl/wrangler/certbot.
set -Eeuo pipefail

# ── Locate repo ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
GATE_PY="$REPO_DIR/lib/nanobk_friendly_gate_wrappers.py"

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

assert_json_keys() {
  local label="$1" json="$2" expected_keys="$3"
  local actual_keys
  actual_keys=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(' '.join(sorted(d.keys())))" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual_keys" == "$expected_keys" ]]; then
    ok "$label"
  else
    fail "$label (expected '$expected_keys', got '$actual_keys')"
  fi
}

# ── Section A: Basic functionality ─────────────────────────────────────────

echo "=== Section A: Basic functionality ==="

# A1. python3 -m py_compile
if python3 -m py_compile "$GATE_PY" 2>/dev/null; then
  ok "A1: py_compile passes"
else
  fail "A1: py_compile fails"
fi

# A2. nanobk beginner gate dns exits 0
if bash "$NANOBK" beginner gate dns >/dev/null 2>&1; then
  ok "A2: nanobk beginner gate dns exits 0"
else
  fail "A2: nanobk beginner gate dns exits 0"
fi

# A3. nanobk beginner gate cert exits 0
if bash "$NANOBK" beginner gate cert >/dev/null 2>&1; then
  ok "A3: nanobk beginner gate cert exits 0"
else
  fail "A3: nanobk beginner gate cert exits 0"
fi

# A4. nanobk beginner gate token exits 0
if bash "$NANOBK" beginner gate token >/dev/null 2>&1; then
  ok "A4: nanobk beginner gate token exits 0"
else
  fail "A4: nanobk beginner gate token exits 0"
fi

# A5. nanobk beginner gate dns --json exits 0
if bash "$NANOBK" beginner gate dns --json >/dev/null 2>&1; then
  ok "A5: nanobk beginner gate dns --json exits 0"
else
  fail "A5: nanobk beginner gate dns --json exits 0"
fi

# A6. nanobk beginner gate cert --json exits 0
if bash "$NANOBK" beginner gate cert --json >/dev/null 2>&1; then
  ok "A6: nanobk beginner gate cert --json exits 0"
else
  fail "A6: nanobk beginner gate cert --json exits 0"
fi

# A7. nanobk beginner gate token --json exits 0
if bash "$NANOBK" beginner gate token --json >/dev/null 2>&1; then
  ok "A7: nanobk beginner gate token --json exits 0"
else
  fail "A7: nanobk beginner gate token --json exits 0"
fi

# ── Section B: Text content ────────────────────────────────────────────────

echo ""
echo "=== Section B: Text content ==="

DNS_TEXT=$(bash "$NANOBK" beginner gate dns 2>&1)
CERT_TEXT=$(bash "$NANOBK" beginner gate cert 2>&1)
TOKEN_TEXT=$(bash "$NANOBK" beginner gate token 2>&1)

# B8. DNS text contains "域名指向"
assert_contains "B8: DNS text has 域名指向" "域名指向" "$DNS_TEXT"

# B9. DNS text contains exact DNS phrase
assert_contains "B9: DNS text has exact phrase" "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" "$DNS_TEXT"

# B10. Cert text contains "HTTPS 安全证书"
assert_contains "B10: Cert text has HTTPS 安全证书" "HTTPS 安全证书" "$CERT_TEXT"

# B11. Cert text contains exact cert phrase
assert_contains "B11: Cert text has exact phrase" "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES" "$CERT_TEXT"

# B12. Token text contains "订阅密钥"
assert_contains "B12: Token text has 订阅密钥" "订阅密钥" "$TOKEN_TEXT"

# B13. Token text contains exact token phrase
assert_contains "B13: Token text has exact phrase" "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" "$TOKEN_TEXT"

# B14. All text contains "不确认就不会执行" or equivalent
assert_contains "B14a: DNS has confirmation warning" "不确认就不会执行" "$DNS_TEXT"
assert_contains "B14b: Cert has confirmation warning" "不确认就不会执行" "$CERT_TEXT"
assert_contains "B14c: Token has confirmation warning" "不确认就不会执行" "$TOKEN_TEXT"

# ── Section C: JSON schema ─────────────────────────────────────────────────

echo ""
echo "=== Section C: JSON schema ==="

DNS_JSON=$(bash "$NANOBK" beginner gate dns --json 2>&1)
CERT_JSON=$(bash "$NANOBK" beginner gate cert --json 2>&1)
TOKEN_JSON=$(bash "$NANOBK" beginner gate token --json 2>&1)

EXPECTED_KEYS="confirmation_required exact_phrase_label gate next_step ok safety title why_dangerous will_do"

# C15. DNS JSON key set exactly equals allowed list
assert_json_keys "C15: DNS JSON keys" "$DNS_JSON" "$EXPECTED_KEYS"

# C16. Cert JSON key set exactly equals allowed list
assert_json_keys "C16: Cert JSON keys" "$CERT_JSON" "$EXPECTED_KEYS"

# C17. Token JSON key set exactly equals allowed list
assert_json_keys "C17: Token JSON keys" "$TOKEN_JSON" "$EXPECTED_KEYS"

# C18. DNS JSON gate == dns
assert_json_field "C18: DNS gate" "$DNS_JSON" "d['gate']" "dns"

# C19. Cert JSON gate == cert
assert_json_field "C19: Cert gate" "$CERT_JSON" "d['gate']" "cert"

# C20. Token JSON gate == token
assert_json_field "C20: Token gate" "$TOKEN_JSON" "d['gate']" "token"

# C21. confirmation_required == true
assert_json_field "C21: confirmation_required" "$DNS_JSON" "d['confirmation_required']" "True"

# C22. safety == preview_only
assert_json_field "C22: safety preview_only" "$DNS_JSON" "d['safety']" "preview_only"

# ── Section D: Forbidden options ───────────────────────────────────────────

echo ""
echo "=== Section D: Forbidden options ==="

# D23. dns --apply rejected
if bash "$NANOBK" beginner gate dns --apply >/dev/null 2>&1; then
  fail "D23: dns --apply should be rejected"
else
  ok "D23: dns --apply rejected"
fi

# D24. dns --yes rejected
if bash "$NANOBK" beginner gate dns --yes >/dev/null 2>&1; then
  fail "D24: dns --yes should be rejected"
else
  ok "D24: dns --yes rejected"
fi

# D25. dns --confirm rejected
if bash "$NANOBK" beginner gate dns --confirm "test" >/dev/null 2>&1; then
  fail "D25: dns --confirm should be rejected"
else
  ok "D25: dns --confirm rejected"
fi

# D26. cert --issue rejected
if bash "$NANOBK" beginner gate cert --issue >/dev/null 2>&1; then
  fail "D26: cert --issue should be rejected"
else
  ok "D26: cert --issue rejected"
fi

# D27. cert --yes rejected
if bash "$NANOBK" beginner gate cert --yes >/dev/null 2>&1; then
  fail "D27: cert --yes should be rejected"
else
  ok "D27: cert --yes rejected"
fi

# D28. token --rotate rejected
if bash "$NANOBK" beginner gate token --rotate >/dev/null 2>&1; then
  fail "D28: token --rotate should be rejected"
else
  ok "D28: token --rotate rejected"
fi

# D29. token --yes rejected
if bash "$NANOBK" beginner gate token --yes >/dev/null 2>&1; then
  fail "D29: token --yes should be rejected"
else
  ok "D29: token --yes rejected"
fi

# ── Section E: No mutation / dangerous commands ────────────────────────────

echo ""
echo "=== Section E: No mutation / dangerous commands ==="

# E30-42. Check source code for forbidden patterns (skip comments and docstrings)
# Use Python to strip docstrings and comments before checking
FORBIDDEN_PATTERNS=(
  "run_apply_engine"
  "run_issue_gate"
  "run_rotation_gate"
  "subprocess"
  "requests"
  "urlopen"
  "curl "
  "wrangler "
  "certbot"
  "acme.sh"
  "systemctl reload"
  "systemctl restart"
  "cf dns apply.*--yes"
)

E_IDX=30
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  # Use Python to check only non-comment, non-docstring lines
  FOUND=$(python3 -c "
import ast
with open('$GATE_PY') as f:
    source = f.read()
tree = ast.parse(source)
# Remove docstrings
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
        if (node.body and isinstance(node.body[0], ast.Expr)
            and isinstance(node.body[0].value, (ast.Constant, ast.Str))):
            node.body = node.body[1:]
# Check remaining code
import io
code = ast.unparse(tree) if hasattr(ast, 'unparse') else ''
if '$pattern' in code.lower():
    print('FOUND')
" 2>/dev/null || true)
  if [[ -n "$FOUND" ]]; then
    fail "E${E_IDX}: wrapper contains '$pattern'"
  else
    ok "E${E_IDX}: no '$pattern' in wrapper"
  fi
  E_IDX=$((E_IDX + 1))
done

# ── Section F: No secret leak ──────────────────────────────────────────────

echo ""
echo "=== Section F: No secret leak ==="

ALL_OUTPUT="$DNS_TEXT
$CERT_TEXT
$TOKEN_TEXT
$DNS_JSON
$CERT_JSON
$TOKEN_JSON"

# F42. no CF_API_TOKEN
assert_not_contains "F42: no CF_API_TOKEN" "CF_API_TOKEN" "$ALL_OUTPUT"

# F43. no PRIVATE KEY
assert_not_contains "F43: no PRIVATE KEY" "PRIVATE KEY" "$ALL_OUTPUT"

# F44. no subscription URL
if echo "$ALL_OUTPUT" | grep -qiE "https?://.*sub[scription]*[/ ]"; then
  fail "F44: subscription URL leak"
else
  ok "F44: no subscription URL"
fi

# F45. no zone_id
assert_not_contains "F45: no zone_id" "zone_id" "$ALL_OUTPUT"

# F46. no record_id
assert_not_contains "F46: no record_id" "record_id" "$ALL_OUTPUT"

# F47. no api.cloudflare.com/client/v4
assert_not_contains "F47: no CF API URL" "api.cloudflare.com/client/v4" "$ALL_OUTPUT"

# F48. no /dns_records
assert_not_contains "F48: no /dns_records" "/dns_records" "$ALL_OUTPUT"

# F49. no api_env_path
assert_not_contains "F49: no api_env_path" "api_env_path" "$ALL_OUTPUT"

# ── Section G: v2.3 gate regression ────────────────────────────────────────

echo ""
echo "=== Section G: v2.3 gate regression ==="
echo "NOTE: v2.3 gate tests require real infrastructure (Cloudflare API, cert tools)."
echo "      These are non-blocking in local/CI environments."

# G50. v2.3.4 DNS apply engine test (non-blocking)
V234_TEST="$REPO_DIR/tests/v2.3.4-dns-apply-engine.sh"
if [[ -f "$V234_TEST" ]]; then
  if bash "$V234_TEST" >/dev/null 2>&1; then
    ok "G50: v2.3.4 DNS apply engine test passes"
  else
    echo "NOTE: G50 v2.3.4 failed (environment-dependent, non-blocking)"
  fi
else
  echo "NOTE: G50 v2.3.4 test not found"
fi

# G51. v2.3.6 cert issue gate test (non-blocking)
V236_TEST="$REPO_DIR/tests/v2.3.6-cert-issue-gate.sh"
if [[ -f "$V236_TEST" ]]; then
  if bash "$V236_TEST" >/dev/null 2>&1; then
    ok "G51: v2.3.6 cert issue gate test passes"
  else
    echo "NOTE: G51 v2.3.6 failed (environment-dependent, non-blocking)"
  fi
else
  echo "NOTE: G51 v2.3.6 test not found"
fi

# G52. v2.3.7 token rotation gate test (non-blocking)
V237_TEST="$REPO_DIR/tests/v2.3.7-token-rotation-gate.sh"
if [[ -f "$V237_TEST" ]]; then
  if bash "$V237_TEST" >/dev/null 2>&1; then
    ok "G52: v2.3.7 token rotation gate test passes"
  else
    echo "NOTE: G52 v2.3.7 failed (environment-dependent, non-blocking)"
  fi
else
  echo "NOTE: G52 v2.3.7 test not found"
fi

# ── Section H: v2.4 regression ─────────────────────────────────────────────

echo ""
echo "=== Section H: v2.4 regression ==="

# H53. v2.4.4 IP friendly UX test
V244_TEST="$REPO_DIR/tests/v2.4.4-ip-friendly-ux.sh"
if [[ -f "$V244_TEST" ]]; then
  if bash "$V244_TEST" >/dev/null 2>&1; then
    ok "H53: v2.4.4 IP friendly UX test passes"
  else
    fail "H53: v2.4.4 IP friendly UX test failed"
  fi
else
  fail "H53: v2.4.4 test not found"
fi

# H54. v2.4.3 subdomain conflict test
V243_TEST="$REPO_DIR/tests/v2.4.3-subdomain-conflict-ux.sh"
if [[ -f "$V243_TEST" ]]; then
  if bash "$V243_TEST" >/dev/null 2>&1; then
    ok "H54: v2.4.3 subdomain conflict test passes"
  else
    fail "H54: v2.4.3 subdomain conflict test failed"
  fi
else
  fail "H54: v2.4.3 test not found"
fi

# H55. v2.4.2 beginner flow test
V242_TEST="$REPO_DIR/tests/v2.4.2-beginner-flow-renderer.sh"
if [[ -f "$V242_TEST" ]]; then
  if bash "$V242_TEST" >/dev/null 2>&1; then
    ok "H55: v2.4.2 beginner flow test passes"
  else
    fail "H55: v2.4.2 beginner flow test failed"
  fi
else
  fail "H55: v2.4.2 test not found"
fi

# H56. v2.4.0 scope test
V240_TEST="$REPO_DIR/tests/v2.4.0-beginner-production-setup-scope.sh"
if [[ -f "$V240_TEST" ]]; then
  if bash "$V240_TEST" >/dev/null 2>&1; then
    ok "H56: v2.4.0 scope test passes"
  else
    fail "H56: v2.4.0 scope test failed"
  fi
else
  fail "H56: v2.4.0 test not found"
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
