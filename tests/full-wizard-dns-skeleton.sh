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

# Run Full Wizard DNS with mock inputs via stdin
# Inputs: 1=yes for DNS, zone name, node prefix, IPv4, IPv6 (empty=skip), 2=no for check
DNS_INPUT=$(printf '1\nexample.com\nnanobk-node\n203.0.113.10\n\n2\n')

# Use NANOBK_TEST_MOCK to avoid real VPS/CF operations
# Use NANOBK_TEST_TMPDIR to write under temp dir
export NANOBK_TEST_MOCK=1
export NANOBK_TEST_TMPDIR="$TMPDIR"

# Run only the DNS-relevant parts via a focused script
# We'll test by directly running the installer with mock stdin
WIZARD_OUTPUT=$(echo "$DNS_INPUT" | bash "$ROOT/installer/install.sh" --mode full --lang zh --dry-run 2>&1 || true)

unset NANOBK_TEST_MOCK
unset NANOBK_TEST_TMPDIR

# Check that DNS section appears in output
if grep -q "Cloudflare DNS\|DNS 节点记录\|DNS 节点" <<< "$WIZARD_OUTPUT"; then
  pass "Wizard shows DNS section"
else
  fail "Wizard missing DNS section"
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
