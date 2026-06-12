#!/usr/bin/env bash
# v2.3.2 Cloudflare Zone Onboarding Test
#
# Lightweight test using fake fixtures. No real Cloudflare calls.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# Portable file mode: GNU stat -c first, then BSD stat -f
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "unknown"; }

CLI="bin/nanobk"
ONBOARDING="lib/nanobk_cf_onboarding.py"
FIXTURES="tests/fixtures/v2.3.2"

# Use temp HOME to avoid polluting real ~/.nanobk
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# 1. Python compile
if python3 -m py_compile "$ONBOARDING" 2>/dev/null; then
  ok "nanobk_cf_onboarding.py compiles"
else
  fail "nanobk_cf_onboarding.py compile error"
fi

# 2. --help exists
HELP_OUT=$(bash "$CLI" cf connect --help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "Cloudflare"; then
  ok "nanobk cf connect --help exists"
else
  fail "nanobk cf connect --help missing"
fi

# 3. Two zones with --yes auto-selects first
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_two.json"
OUT=$(bash "$CLI" cf connect --api-token "fake-token-for-test-only" --yes --json 2>&1 || true)
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==True; assert d.get('zone_name')=='example.com'; assert d.get('mutation')==False" 2>/dev/null; then
  ok "Two zones: auto-selects first zone"
else
  fail "Two zones: did not auto-select first zone"
fi

# 4. cloudflare.env created
if [[ -f "$HOME/.nanobk/cloudflare.env" ]]; then
  ok "cloudflare.env created"
else
  fail "cloudflare.env not created"
fi

# 5. cloudflare.env permissions 600
ENV_MODE="$(file_mode "$HOME/.nanobk/cloudflare.env")"
if [[ "$ENV_MODE" == "600" ]]; then
  ok "cloudflare.env permissions 600"
else
  fail "cloudflare.env permissions $ENV_MODE (expected 600)"
fi

# 6. setup-profile.json permissions 600
PROFILE_MODE="$(file_mode "$HOME/.nanobk/setup-profile.json")"
if [[ "$PROFILE_MODE" == "600" ]]; then
  ok "setup-profile.json permissions 600"
else
  fail "setup-profile.json permissions $PROFILE_MODE (expected 600)"
fi

# 7. Profile saves zone_name
if python3 -c "import json; d=json.load(open('$HOME/.nanobk/setup-profile.json')); assert d.get('zone_name')=='example.com'" 2>/dev/null; then
  ok "Profile saves zone_name"
else
  fail "Profile does not save zone_name correctly"
fi

# 8. Profile saves api_env_path but output doesn't print it
if python3 -c "import json; d=json.load(open('$HOME/.nanobk/setup-profile.json')); assert 'api_env_path' in d" 2>/dev/null; then
  ok "Profile saves api_env_path"
else
  fail "Profile does not save api_env_path"
fi
if echo "$OUT" | grep -q "cloudflare.env"; then
  fail "JSON output leaks api_env_path"
else
  ok "JSON output does not print api_env_path"
fi

# 9. Reset for single zone test
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_one.json"
OUT=$(bash "$CLI" cf connect --api-token "fake-token-for-test-only" --yes --json 2>&1 || true)
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==True; assert d.get('zone_name')=='example.com'" 2>/dev/null; then
  ok "Single zone: auto-selects only zone"
else
  fail "Single zone: did not auto-select"
fi

# 10. Zero zones
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_empty.json"
OUT=$(bash "$CLI" cf connect --api-token "fake-token-for-test-only" --yes --json 2>&1 || true)
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==False; assert d.get('status')=='no_zones'" 2>/dev/null; then
  ok "Zero zones: returns no_zones status"
else
  fail "Zero zones: unexpected response"
fi

# 11. Invalid token / API error
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_error.json"
OUT=$(bash "$CLI" cf connect --api-token "fake-invalid-token" --yes --json 2>&1 || true)
if echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==False; assert 'error' in d" 2>/dev/null; then
  ok "Invalid token: returns error"
else
  fail "Invalid token: unexpected response"
fi

# 12. No secret leaks
unset NANOBK_CF_ZONES_FAKE_RESPONSE
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_two.json"
ALL_OUT=$(bash "$CLI" cf connect --api-token "super-secret-fake-token" --yes --json 2>&1 || true)
for leak in "CF_API_TOKEN=" "super-secret-fake-token" "api.cloudflare.com/client/v4" "/zones/" "fake-zone-id" "PRIVATE KEY" "SUB_TOKEN=" "ADMIN_TOKEN=" "token="; do
  if echo "$ALL_OUT" | grep -q "$leak"; then
    fail "Output leaks: $leak"
  else
    ok "No leak: $leak"
  fi
done

# 13. No POST/PATCH/PUT/DELETE mutation calls in onboarding module
# Check for actual mutation method calls, not docstring mentions
MUTATION_LINES=$(grep -nE 'method="(POST|PATCH|PUT|DELETE)"|urlopen.*POST|requests\.(post|put|patch|delete)' "$ONBOARDING" 2>/dev/null || true)
if [[ -n "$MUTATION_LINES" ]]; then
  fail "Onboarding module contains mutation method calls"
else
  ok "No POST/PATCH/PUT/DELETE mutation calls in onboarding"
fi

# 14. No owner-smoke-create auto-execution
if grep -q "owner-smoke-create.*--owner-approve" "$ONBOARDING" 2>/dev/null; then
  fail "Onboarding module calls owner-smoke-create"
else
  ok "No owner-smoke-create in onboarding"
fi

# 15. TTY menu contains "连接 Cloudflare"
unset NANOBK_CF_ZONES_FAKE_RESPONSE
MENU_OUT=$(echo "4" | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null | head -60 || true)
if echo "$MENU_OUT" | grep -q "连接 Cloudflare"; then
  ok "TTY menu contains '连接 Cloudflare'"
else
  fail "TTY menu missing '连接 Cloudflare'"
fi

# 16. No-args non-TTY JSON returns error (does not hang)
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_two.json"
NOARG_OUT=$(bash "$CLI" cf connect --json 2>&1 || true)
if echo "$NOARG_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('ok')==False; assert 'error' in d" 2>/dev/null; then
  ok "No-args non-TTY JSON returns error without hanging"
else
  fail "No-args non-TTY JSON did not return expected error"
fi

# 17. Interactive prompt text exists in onboarding helper
if grep -q "请粘贴 Cloudflare API token" "$ONBOARDING" 2>/dev/null; then
  ok "Onboarding helper contains interactive prompt text"
else
  fail "Onboarding helper missing interactive prompt text"
fi

# 18. Non-interactive stdin token via helper completes onboarding
# Use NANOBK_TEST_FORCE_INTERACTIVE to skip TTY check in Python helper,
# but do NOT set NANOBK_TEST_FORCE_TTY to avoid terminal blocking in CI/background.
# NANOBK_TEST_FORCE_INTERACTIVE makes helper use stdin instead of /dev/tty.
rm -rf "$HOME/.nanobk"
export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_two.json"
export NANOBK_TEST_FORCE_INTERACTIVE=1
INTERACTIVE_OUT=$(printf 'fake-interactive-token-for-test\n' | \
  NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones_two.json" \
  NANOBK_TEST_FORCE_INTERACTIVE=1 \
  HOME="$HOME" \
  python3 "$ONBOARDING" --yes 2>&1 || true)
unset NANOBK_TEST_FORCE_INTERACTIVE
if echo "$INTERACTIVE_OUT" | grep -q "连接成功\|example.com"; then
  ok "Interactive stdin token completes onboarding"
else
  fail "Interactive stdin token did not complete"
fi

# 19. Interactive output does not leak token
if echo "$INTERACTIVE_OUT" | grep -q "fake-interactive-token-for-test"; then
  fail "Interactive output leaks token"
else
  ok "Interactive output does not leak token"
fi

# 20. Interactive onboarding created profile
if python3 -c "import json; d=json.load(open('$HOME/.nanobk/setup-profile.json')); assert d.get('zone_name')=='example.com'" 2>/dev/null; then
  ok "Interactive onboarding saved profile"
else
  fail "Interactive onboarding did not save profile"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.2 Cloudflare zone onboarding checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
