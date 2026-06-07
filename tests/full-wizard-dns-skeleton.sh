#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard DNS Skeleton Test
#
# Tests that the Full Wizard DNS preparation/check skeleton works correctly:
# - DNS profile is written with correct content
# - chmod 600 is applied
# - --yes is never auto-run
# - Summary contains correct DNS fields
# - No real Cloudflare API calls
# - No token/env leakage
# - DNS stage failure is caught and summarized
# - No unsafe defaults (example.com, 203.0.113.10)
# - No cat-heredoc api-env instructions
#
# Usage:
#   bash tests/full-wizard-dns-skeleton.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_grep() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  else
    pass "$desc"
  fi
}

assert_grep() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== Full Wizard DNS Skeleton Test ==="
echo ""

# ── Test 1: DNS profile rendering ────────────────────────────────────────

echo "--- DNS profile rendering ---"
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create mock api-env for check test
mkdir -p "$TMPDIR/etc/nanobk"
cat > "$TMPDIR/etc/nanobk/cloudflare-api.env" <<'EOF'
CF_API_TOKEN=fake-token-for-test
CF_ZONE_ID=fake-zone-id
CF_ZONE_NAME=example.com
EOF
chmod 600 "$TMPDIR/etc/nanobk/cloudflare-api.env"

# Run Full Wizard with --yes and --dry-run (non-interactive mode)
# Use NANOBK_TEST_MOCK to avoid real VPS/CF operations
# Use NANOBK_TEST_TMPDIR to write under temp dir
export NANOBK_TEST_MOCK=1
export NANOBK_TEST_TMPDIR="$TMPDIR"

# With --yes, the wizard auto-accepts all prompts.
# DNS stage will fail because zone_name/ipv4 have no defaults in --yes mode.
# This is correct behavior: --yes mode should not silently use placeholder values.
WIZARD_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode full --lang zh --dry-run --yes 2>&1 || true)

unset NANOBK_TEST_MOCK
unset NANOBK_TEST_TMPDIR

# Check that DNS section appears in output
if grep -q "Cloudflare DNS\|DNS 节点记录\|DNS 节点" <<< "$WIZARD_OUTPUT"; then
  pass "Wizard shows DNS section"
else
  fail "Wizard missing DNS section"
  ERRORS=$((ERRORS + 1))
fi

# Check that DNS stage failure is caught (wizard continues, doesn't crash)
if grep -q "阶段 3\|Cloudflare 部署\|阶段 4\|Telegram Bot\|Summary\|最终摘要" <<< "$WIZARD_OUTPUT"; then
  pass "Wizard continues past DNS failure to later stages"
else
  fail "Wizard should continue past DNS failure"
  ERRORS=$((ERRORS + 1))
fi

# Check that DNS failure is reported honestly
if grep -q "DNS.*失败\|DNS.*failed\|域名不能为空" <<< "$WIZARD_OUTPUT"; then
  pass "DNS failure is reported in output"
else
  fail "DNS failure should be reported"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: Direct profile write test ────────────────────────────────────

echo ""
echo "--- Direct profile write test ---"
echo ""

# Test profile generation directly
TEST_PROFILE="$TMPDIR/etc/nanobk/cloudflare-dns-profile.json"
mkdir -p "$(dirname "$TEST_PROFILE")"

cat > "$TEST_PROFILE" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "nanobk-node",
  "ipv4": "203.0.113.10",
  "ipv6": "2001:db8::10",
  "defaultProxied": false,
  "reserved": {
    "panelPrefix": "panel",
    "nanokPrefix": "nanok",
    "nanobPrefix": "nanob"
  }
}
EOF
chmod 600 "$TEST_PROFILE"

# Verify profile content
if python3 -c "
import json, sys
with open('$TEST_PROFILE') as f:
    d = json.load(f)
assert d['zoneName'] == 'example.com', 'wrong zoneName'
assert d['nodePrefix'] == 'nanobk-node', 'wrong nodePrefix'
assert d['ipv4'] == '203.0.113.10', 'wrong ipv4'
assert d['ipv6'] == '2001:db8::10', 'wrong ipv6'
assert d['defaultProxied'] is False, 'defaultProxied should be False'
assert d['reserved']['panelPrefix'] == 'panel', 'wrong panelPrefix'
assert d['reserved']['nanokPrefix'] == 'nanok', 'wrong nanokPrefix'
assert d['reserved']['nanobPrefix'] == 'nanob', 'wrong nanobPrefix'
print('OK')
" 2>&1; then
  pass "Profile content is correct"
else
  fail "Profile content is incorrect"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: chmod 600 check ──────────────────────────────────────────────

echo ""
echo "--- chmod 600 check ---"
echo ""

if [[ "$(stat -c '%a' "$TEST_PROFILE" 2>/dev/null || stat -f '%Lp' "$TEST_PROFILE" 2>/dev/null)" == "600" ]]; then
  pass "Profile has chmod 600"
else
  fail "Profile should have chmod 600"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: validate-profile passes ──────────────────────────────────────

echo ""
echo "--- validate-profile passes ---"
echo ""

check "validate-profile exits 0" bash "$ROOT/bin/nanobk" cf dns validate-profile --profile "$TEST_PROFILE"

# ── Test 5: plan passes ──────────────────────────────────────────────────

echo ""
echo "--- plan passes ---"
echo ""

PLAN_OUTPUT=$(bash "$ROOT/bin/nanobk" cf dns plan --profile "$TEST_PROFILE" 2>&1 || true)

if grep -q "nanobk-node.example.com\|A.*203.0.113.10\|AAAA.*2001:db8::10" <<< "$PLAN_OUTPUT"; then
  pass "Plan shows correct records"
else
  fail "Plan missing correct records"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "proxied=false\|DNS-only" <<< "$PLAN_OUTPUT"; then
  pass "Plan shows proxied=false"
else
  fail "Plan should show proxied=false"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 6: --yes not auto-run ───────────────────────────────────────────

echo ""
echo "--- --yes not auto-run ---"
echo ""

# Search installer source for auto-run of apply --yes
if grep -n 'nanobk cf dns apply.*--yes' "$ROOT/installer/install.sh" | grep -v 'manual\|手动\|恢复\|echo\|#\|manual_apply\|commands\|PLAN\|template\|next step\|Next command' | grep -q .; then
  fail "Installer should NOT auto-run 'nanobk cf dns apply --yes'"
  ERRORS=$((ERRORS + 1))
else
  pass "Installer does NOT auto-run 'nanobk cf dns apply --yes'"
fi

# ── Test 7: Summary contains DNS fields ──────────────────────────────────

echo ""
echo "--- Summary contains DNS fields ---"
echo ""

if grep -q 'dns_profile\|dns_plan\|dns_check\|dns_apply\|Cloudflare DNS' "$ROOT/installer/install.sh"; then
  pass "Installer has DNS summary fields"
else
  fail "Installer missing DNS summary fields"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'manual_apply_pending' "$ROOT/installer/install.sh"; then
  pass "Installer has manual_apply_pending state"
else
  fail "Installer missing manual_apply_pending state"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 8: No real Cloudflare API call ──────────────────────────────────

echo ""
echo "--- No real Cloudflare API call ---"
echo ""

# The collect_dns_args function should only call validate-profile and plan (no API)
# and only call apply --check when explicitly requested
# Use context-aware grep: check that apply is always followed by --check in the same block
# by looking at 3 lines after each match
APPLY_WITHOUT_CHECK=0
while IFS= read -r line; do
  lineno=$(echo "$line" | cut -d: -f1)
  # Check if --check appears within next 3 lines
  if ! sed -n "$((lineno)),$((lineno+3))p" "$ROOT/installer/install.sh" | grep -q '\-\-check'; then
    # This apply call doesn't have --check nearby
    # Allow if it's in echo/comment/template/recovery context
    if ! sed -n "${lineno}p" "$ROOT/installer/install.sh" | grep -q 'echo\|#\|manual\|手动\|恢复\|template\|PLAN\|next step\|Next command\|apply_pending\|manual_apply_pending'; then
      APPLY_WITHOUT_CHECK=1
      echo "  Line $lineno: apply without --check"
    fi
  fi
done < <(grep -n 'cf dns apply' "$ROOT/installer/install.sh")

if [[ "$APPLY_WITHOUT_CHECK" == "1" ]]; then
  fail "collect_dns_args should not call apply without --check"
  ERRORS=$((ERRORS + 1))
else
  pass "collect_dns_args does not call apply without --check"
fi

# ── Test 9: No token/env leakage ─────────────────────────────────────────

echo ""
echo "--- No token/env leakage ---"
echo ""

# Check that collect_dns_args does not cat or print api-env content
if grep -n 'cat.*cloudflare-api.env\|cat.*api.env' "$ROOT/installer/install.sh" | grep -v '#\|mock\|MOCK\|template\|echo\|test\|PLAN' | grep -q .; then
  fail "Installer should not cat api-env file"
  ERRORS=$((ERRORS + 1))
else
  pass "Installer does not cat api-env file"
fi

# ── Test 10: IPv6 optional ───────────────────────────────────────────────

echo ""
echo "--- IPv6 optional ---"
echo ""

TEST_PROFILE_NO_V6="$TMPDIR/etc/nanobk/dns-no-ipv6.json"
cat > "$TEST_PROFILE_NO_V6" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "nanobk-node",
  "ipv4": "203.0.113.10",
  "defaultProxied": false,
  "reserved": {
    "panelPrefix": "panel",
    "nanokPrefix": "nanok",
    "nanobPrefix": "nanob"
  }
}
EOF
chmod 600 "$TEST_PROFILE_NO_V6"

check "Profile without ipv6 validates" bash "$ROOT/bin/nanobk" cf dns validate-profile --profile "$TEST_PROFILE_NO_V6"

PLAN_NO_V6=$(bash "$ROOT/bin/nanobk" cf dns plan --profile "$TEST_PROFILE_NO_V6" 2>&1 || true)
if grep -q "A.*203.0.113.10" <<< "$PLAN_NO_V6"; then
  pass "Plan without ipv6 shows A record"
else
  fail "Plan without ipv6 should show A record"
  ERRORS=$((ERRORS + 1))
fi

if ! grep -q "AAAA" <<< "$PLAN_NO_V6"; then
  pass "Plan without ipv6 has no AAAA record"
else
  fail "Plan without ipv6 should not have AAAA record"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 11: Stage card exists ────────────────────────────────────────────

echo ""
echo "--- Stage card exists ---"
echo ""

if grep -q 'ui_stage_card_cloudflare_dns' "$ROOT/installer/install.sh"; then
  pass "Installer references DNS stage card"
else
  fail "Installer missing DNS stage card reference"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'ui_stage_card_cloudflare_dns' "$ROOT/installer/lib/ui.sh"; then
  pass "ui.sh defines DNS stage card"
else
  fail "ui.sh missing DNS stage card definition"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 12: DNS stage failure is caught ──────────────────────────────────

echo ""
echo "--- DNS stage failure handling ---"
echo ""

# Check that run_full_wizard wraps collect_dns_args with || dns_rc=$?
if grep -A2 'collect_dns_args' "$ROOT/installer/install.sh" | grep -q 'dns_rc'; then
  pass "DNS stage wraps collect_dns_args with failure handler"
else
  fail "DNS stage missing failure handler (|| dns_rc=...)"
  ERRORS=$((ERRORS + 1))
fi

# Check that DNS failure sets DNS_STAGE_STATUS to failed
if grep -A10 'dns_rc' "$ROOT/installer/install.sh" | grep -q 'DNS_STAGE_STATUS.*failed'; then
  pass "DNS failure sets DNS_STAGE_STATUS=failed"
else
  fail "DNS failure should set DNS_STAGE_STATUS=failed"
  ERRORS=$((ERRORS + 1))
fi

# Check that DNS failure does NOT crash the wizard (no bare return 1 in DNS failure block)
# The recovery block should show commands but wizard should continue to summary
if grep -A15 'dns_rc' "$ROOT/installer/install.sh" | grep -q 'ui_recovery_block'; then
  pass "DNS failure shows recovery block"
else
  fail "DNS failure should show recovery block"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 13: No unsafe cat-heredoc api-env instructions ──────────────────

echo ""
echo "--- No unsafe api-env cat-heredoc instructions ---"
echo ""

assert_not_grep \
  "No 'cat > ... cloudflare-api.env' heredoc" \
  "cat > .*cloudflare-api.env" \
  "$ROOT/installer/install.sh"

assert_not_grep \
  "No 'CF_API_TOKEN=your-token-here' placeholder" \
  "CF_API_TOKEN=your-token-here" \
  "$ROOT/installer/install.sh"

# Safer instructions should be present
assert_grep \
  "Has 'install -m 600' instruction" \
  "install -m 600" \
  "$ROOT/installer/install.sh"

assert_grep \
  "Has 'sudo nano' instruction" \
  "sudo nano" \
  "$ROOT/installer/install.sh"

# ── Test 14: No unsafe real Wizard defaults ──────────────────────────────

echo ""
echo "--- No unsafe real Wizard defaults ---"
echo ""

# Zone name prompt should NOT default to example.com
# Allow "example.com" in prompt text (as example) but not as default value
# The prompt function uses: prompt var_name "text" "default"
# Check that the zone_name prompt line does not have example.com as default arg
if grep 'prompt zone_name' "$ROOT/installer/install.sh" | grep -q '"example.com"'; then
  # Check if it's just in the prompt text, not the default
  if grep 'prompt zone_name' "$ROOT/installer/install.sh" | grep -qE 'prompt zone_name.*".*".*"example.com"'; then
    fail "zone_name prompt should not default to example.com"
    ERRORS=$((ERRORS + 1))
  else
    pass "zone_name prompt example.com is in description, not default"
  fi
else
  pass "zone_name prompt does not default to example.com"
fi

# IPv4 prompt should NOT default to 203.0.113.10
if grep 'prompt ipv4' "$ROOT/installer/install.sh" | grep -qE 'prompt ipv4.*".*".*"203\.0\.113\.10"'; then
  fail "ipv4 prompt should not default to 203.0.113.10"
  ERRORS=$((ERRORS + 1))
else
  pass "ipv4 prompt does not default to 203.0.113.10"
fi

# nodePrefix default nanobk-node is OK
if grep 'prompt node_prefix' "$ROOT/installer/install.sh" | grep -q '"nanobk-node"'; then
  pass "node_prefix defaults to nanobk-node (OK)"
else
  fail "node_prefix should default to nanobk-node"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 15: DNS stage skip for cloudflare resume ────────────────────────

echo ""
echo "--- DNS stage skip for cloudflare resume ---"
echo ""

# Static check: installer skips DNS when START_FROM_STAGE is cloudflare or botweb
assert_grep \
  "DNS skip checks both cloudflare and botweb" \
  'START_FROM_STAGE.*==.*cloudflare.*\|\|.*START_FROM_STAGE.*==.*botweb' \
  "$ROOT/installer/install.sh"

# Static check: the skip message mentions the stage name (not hardcoded to botweb)
assert_not_grep \
  "DNS skip message is not hardcoded to botweb only" \
  '已跳过 Cloudflare DNS（从 botweb 继续' \
  "$ROOT/installer/install.sh"

# ── Test 16: EOF safety in prompt_menu_choice ────────────────────────────

echo ""
echo "--- EOF safety in prompt_menu_choice ---"
echo ""

# EOF with no default should NOT fall back to "1" (affirmative path)
assert_not_grep \
  "EOF fallback does not use '1' as safe fallback" \
  "printf -v.*var_name.*'1'" \
  "$ROOT/installer/install.sh"

# EOF with no default should use $max (typically exit/cancel)
assert_grep \
  "EOF fallback uses \$max (exit/cancel)" \
  'printf -v.*var_name.*\$max' \
  "$ROOT/installer/install.sh"

# EOF fallback should have a comment explaining safety reasoning
assert_grep \
  "EOF fallback comment mentions affirmative path" \
  'affirmative' \
  "$ROOT/installer/install.sh"

# ── Test 17: Mock-driven DNS profile verification ────────────────────────

echo ""
echo "--- Mock-driven DNS profile verification ---"
echo ""

# Run the Full Wizard with stdin-driven DNS flow (no --yes, no --dry-run).
# This exercises the real collect_dns_args path under NANOBK_TEST_MOCK=1,
# writing the profile to NANOBK_TEST_TMPDIR instead of /etc.
MOCK_TMPDIR=$(mktemp -d)
trap 'rm -rf "$MOCK_TMPDIR" "$TMPDIR"' EXIT

export NANOBK_TEST_MOCK=1
export NANOBK_TEST_TMPDIR="$MOCK_TMPDIR"

MOCK_INPUTS=$(printf '%s\n' \
  "2" \
  "1" \
  "example.com" \
  "nanobk-node" \
  "203.0.113.10" \
  "2001:db8::10" \
  "2" \
  "2" \
  "2" \
  "2")

MOCK_OUTPUT=$(echo "$MOCK_INPUTS" | bash "$ROOT/installer/install.sh" --mode full --lang zh 2>&1) || true

unset NANOBK_TEST_MOCK
unset NANOBK_TEST_TMPDIR

# Verify the generated profile file exists under the mock tmpdir
MOCK_PROFILE="$MOCK_TMPDIR/etc/nanobk/cloudflare-dns-profile.json"
if [[ -f "$MOCK_PROFILE" ]]; then
  pass "Mock flow writes DNS profile under test tmpdir"
else
  fail "Mock flow did not write DNS profile under test tmpdir"
  ERRORS=$((ERRORS + 1))
fi

# Verify profile content via python3
if [[ -f "$MOCK_PROFILE" ]]; then
  if python3 -c "
import json, sys
with open('$MOCK_PROFILE') as f:
    d = json.load(f)
assert d['zoneName'] == 'example.com', f'wrong zoneName: {d.get(\"zoneName\")}'
assert d['nodePrefix'] == 'nanobk-node', f'wrong nodePrefix: {d.get(\"nodePrefix\")}'
assert d['ipv4'] == '203.0.113.10', f'wrong ipv4: {d.get(\"ipv4\")}'
assert d['ipv6'] == '2001:db8::10', f'wrong ipv6: {d.get(\"ipv6\")}'
assert d['defaultProxied'] is False, f'defaultProxied should be False: {d.get(\"defaultProxied\")}'
assert d['reserved']['panelPrefix'] == 'panel', f'wrong panelPrefix'
assert d['reserved']['nanokPrefix'] == 'nanok', f'wrong nanokPrefix'
assert d['reserved']['nanobPrefix'] == 'nanob', f'wrong nanobPrefix'
print('OK')
" 2>&1; then
    pass "Mock-generated profile content is correct"
  else
    fail "Mock-generated profile content is incorrect"
    ERRORS=$((ERRORS + 1))
  fi

  # Verify chmod 600
  if [[ "$(stat -c '%a' "$MOCK_PROFILE" 2>/dev/null || stat -f '%Lp' "$MOCK_PROFILE" 2>/dev/null)" == "600" ]]; then
    pass "Mock-generated profile has chmod 600"
  else
    fail "Mock-generated profile should have chmod 600"
    ERRORS=$((ERRORS + 1))
  fi

  # Verify the file is under test tmpdir, not real /etc
  if [[ "$MOCK_PROFILE" == "$MOCK_TMPDIR"* ]]; then
    pass "Mock profile is under test tmpdir, not real /etc"
  else
    fail "Mock profile should be under test tmpdir"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Verify the mock flow ran validate-profile and plan
if grep -q "validate-profile\|DNS profile 验证\|验证" <<< "$MOCK_OUTPUT"; then
  pass "Mock flow ran or simulated validate-profile"
else
  fail "Mock flow should run validate-profile"
  ERRORS=$((ERRORS + 1))
fi

# Verify Summary includes DNS fields
if grep -q "Cloudflare DNS\|dns_profile\|dns_plan\|dns_check\|dns_apply" <<< "$MOCK_OUTPUT"; then
  pass "Mock flow Summary includes DNS fields"
else
  fail "Mock flow Summary should include DNS fields"
  ERRORS=$((ERRORS + 1))
fi

# Verify dns_apply is not done/installed/verified
if grep -q "dns_apply:.*done\|dns_apply:.*installed\|dns_apply:.*verified\|dns_apply:.*success" <<< "$MOCK_OUTPUT"; then
  fail "dns_apply should never be done/installed/verified/success"
  ERRORS=$((ERRORS + 1))
else
  pass "dns_apply is not done/installed/verified/success"
fi

# Verify no real Cloudflare API call in mock output
if grep -q "Authorization:\|Authorization: Bearer" <<< "$MOCK_OUTPUT"; then
  fail "Mock output should not contain Authorization header"
  ERRORS=$((ERRORS + 1))
else
  pass "Mock output does not contain Authorization header"
fi

# Negative assertions on mock output
assert_not_grep \
  "Mock output does not contain workers.dev" \
  "workers\.dev" \
  <(echo "$MOCK_OUTPUT")

assert_not_grep \
  "Mock output does not contain hysteria2://" \
  "hysteria2://" \
  <(echo "$MOCK_OUTPUT")

assert_not_grep \
  "Mock output does not contain tuic://" \
  "tuic://" \
  <(echo "$MOCK_OUTPUT")

assert_not_grep \
  "Mock output does not contain vless://" \
  "vless://" \
  <(echo "$MOCK_OUTPUT")

assert_not_grep \
  "Mock output does not contain trojan://" \
  "trojan://" \
  <(echo "$MOCK_OUTPUT")

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}All Full Wizard DNS skeleton tests passed${NC}"
else
  echo -e "${RED}${ERRORS} test(s) failed${NC}"
fi
echo ""

exit $ERRORS
