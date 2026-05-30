#!/usr/bin/env bash
# NanoBK Proxy Suite — Installed Layout Rotate Test
#
# Validates that rotate-keys.sh works from the installed layout:
#   /opt/nanobk/bin/rotate-keys.sh → /opt/nanobk/lib/common.sh + profile.sh
#
# Requirements: jq
#
# Usage:
#   bash tests/installed-layout-rotate.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-installed-layout-test"

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
echo "=== Installed Layout Rotate Test ==="
echo ""

# ── Prerequisites ───────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  fail "jq is required"
  echo "  Install: brew install jq  OR  sudo apt-get install -y jq"
  exit 1
fi
pass "jq found"

# ── Generate installed layout ───────────────────────────────────────────────

echo ""
echo "--- Generating installed layout ---"
echo ""

rm -rf "$TMP"

bash "$ROOT/installer/install-vps.sh" --render-only --yes \
  --install-dir "$TMP/opt/nanobk" \
  --config-dir "$TMP/etc/nanobk" \
  --domain test.example.com \
  --vps-ip 198.51.100.10 \
  --cert-mode self-signed

echo ""

# ── Check installed files exist ─────────────────────────────────────────────

echo "--- Checking installed files ---"
echo ""

check "bin/rotate-keys.sh" test -f "$TMP/opt/nanobk/bin/rotate-keys.sh"
check "bin/healthcheck.sh" test -f "$TMP/opt/nanobk/bin/healthcheck.sh"
check "lib/common.sh"      test -f "$TMP/opt/nanobk/lib/common.sh"
check "lib/profile.sh"     test -f "$TMP/opt/nanobk/lib/profile.sh"
check "lib/os.sh"          test -f "$TMP/opt/nanobk/lib/os.sh"
check "lib/download.sh"    test -f "$TMP/opt/nanobk/lib/download.sh"

echo ""

# ── Test rotate tuic from installed layout ──────────────────────────────────

echo "--- Testing rotate tuic from installed layout ---"
echo ""

if bash "$TMP/opt/nanobk/bin/rotate-keys.sh" --yes \
  --protocol tuic \
  --skip-cloudflare \
  --skip-services \
  --allow-placeholder-reality \
  --config-dir "$TMP/etc/nanobk" 2>&1; then
  pass "rotate tuic from installed layout"
else
  fail "rotate tuic from installed layout"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Test rotate reality from installed layout ───────────────────────────────

echo "--- Testing rotate reality from installed layout ---"
echo ""

if bash "$TMP/opt/nanobk/bin/rotate-keys.sh" --yes \
  --protocol reality \
  --skip-cloudflare \
  --skip-services \
  --allow-placeholder-reality \
  --config-dir "$TMP/etc/nanobk" 2>&1; then
  pass "rotate reality from installed layout"
else
  fail "rotate reality from installed layout"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Test rotate all from installed layout ───────────────────────────────────

echo "--- Testing rotate all from installed layout ---"
echo ""

if bash "$TMP/opt/nanobk/bin/rotate-keys.sh" --yes \
  --protocol all \
  --skip-cloudflare \
  --skip-services \
  --allow-placeholder-reality \
  --config-dir "$TMP/etc/nanobk" 2>&1; then
  pass "rotate all from installed layout"
else
  fail "rotate all from installed layout"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Verify profile and secrets ──────────────────────────────────────────────

echo "--- Verifying results ---"
echo ""

PROFILE="$TMP/etc/nanobk/profile.current.json"
SECRETS="$TMP/etc/nanobk/secrets.private.env"

check "profile.current.json exists" test -f "$PROFILE"
check "secrets.private.env exists" test -f "$SECRETS"

# Profile has all four protocols
if [[ -f "$PROFILE" ]]; then
  check "profile has hy2"     jq -e '.hy2' "$PROFILE"
  check "profile has tuic"    jq -e '.tuic' "$PROFILE"
  check "profile has reality" jq -e '.reality' "$PROFILE"
  check "profile has trojan"  jq -e '.trojan' "$PROFILE"
fi

# Reality private key NOT in profile
if [[ -f "$PROFILE" ]]; then
  if grep -q 'privateKey' "$PROFILE" 2>/dev/null; then
    fail "Reality private key leaked into profile"
    ERRORS=$((ERRORS + 1))
  else
    pass "Reality private key NOT in profile"
  fi
fi

# Secrets permissions
if [[ -f "$SECRETS" ]]; then
  local_perms=$(stat -c '%a' "$SECRETS" 2>/dev/null || stat -f '%Lp' "$SECRETS" 2>/dev/null || echo "unknown")
  if [[ "$local_perms" == "600" ]]; then
    pass "secrets.private.env permissions: 600"
  else
    fail "secrets.private.env permissions: ${local_perms}"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All installed layout tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
