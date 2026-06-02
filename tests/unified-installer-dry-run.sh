#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Installer Dry-Run Test
#
# Tests that install.sh works correctly in dry-run mode
# without modifying the system.
#
# Usage:
#   bash tests/unified-installer-dry-run.sh

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
echo "=== Unified Installer Dry-Run Test ==="
echo ""

# ── Test 1: --help ──────────────────────────────────────────────────────────

echo "--- --help ---"
echo ""

check "install.sh --help" bash "$ROOT/installer/install.sh" --help

# ── Test 2: --mode commands --dry-run ───────────────────────────────────────

echo ""
echo "--- --mode commands --dry-run ---"
echo ""

CMD_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode commands --dry-run 2>&1 || true)

if grep -q "VPS 部署\|Cloudflare\|rotate" <<< "$CMD_OUTPUT"; then
  pass "--mode commands shows command templates"
else
  fail "--mode commands missing templates"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: --mode full --dry-run --defaults --lang zh ──────────────────────

echo ""
echo "--- --mode full --dry-run --defaults --lang zh ---"
echo ""

# full wizard with --defaults still prompts for Bot/Web tokens (no defaults).
# Use --yes to auto-accept all prompts.
FULL_ZH=$(bash "$ROOT/installer/install.sh" --mode full --dry-run --yes --lang zh 2>&1 || true)

if grep -q "DRY-RUN\|dry-run\|dry_run" <<< "$FULL_ZH"; then
  pass "full --dry-run --lang zh shows dry-run"
else
  fail "full --dry-run --lang zh missing dry-run"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "install-vps\|VPS" <<< "$FULL_ZH"; then
  pass "full --dry-run includes VPS command"
else
  fail "full --dry-run missing VPS command"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "healthcheck\|nanobk status" <<< "$FULL_ZH"; then
  pass "full --dry-run includes healthcheck/status"
else
  fail "full --dry-run missing healthcheck/status"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "preflight\|validate-profile-only" <<< "$FULL_ZH"; then
  pass "full --dry-run includes Cloudflare preflight/validation"
else
  fail "full --dry-run missing Cloudflare preflight/validation"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "bot/.env\|Would write bot" <<< "$FULL_ZH"; then
  pass "full --dry-run mentions bot/.env"
else
  fail "full --dry-run missing bot/.env"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "web/.env\|Would write web" <<< "$FULL_ZH"; then
  pass "full --dry-run mentions web/.env"
else
  fail "full --dry-run missing web/.env"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "Setup Summary\|NanoBK Setup" <<< "$FULL_ZH"; then
  pass "full --dry-run includes summary"
else
  fail "full --dry-run missing summary"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: --mode full --dry-run --defaults --lang en ──────────────────────

echo ""
echo "--- --mode full --dry-run --defaults --lang en ---"
echo ""

FULL_EN=$(bash "$ROOT/installer/install.sh" --mode full --dry-run --yes --lang en 2>&1 || true)

if grep -q "DRY-RUN\|dry-run" <<< "$FULL_EN"; then
  pass "full --dry-run --lang en shows dry-run"
else
  fail "full --dry-run --lang en missing dry-run"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "English UI is partial" <<< "$FULL_EN"; then
  pass "English UI partial warning shown"
else
  fail "English UI partial warning missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 5: dry-run does not write bot/.env ─────────────────────────────────

echo ""
echo "--- Safety checks ---"
echo ""

BOT_ENV="$ROOT/bot/.env"
WEB_ENV="$ROOT/web/.env"

BOT_WAS_ABSENT=0
WEB_WAS_ABSENT=0
[[ ! -f "$BOT_ENV" ]] && BOT_WAS_ABSENT=1
[[ ! -f "$WEB_ENV" ]] && WEB_WAS_ABSENT=1

bash "$ROOT/installer/install.sh" --mode full --dry-run --defaults --lang zh >/dev/null 2>&1 || true

if [[ "$BOT_WAS_ABSENT" == "1" ]] && [[ -f "$BOT_ENV" ]]; then
  fail "dry-run created bot/.env (should not)"
  ERRORS=$((ERRORS + 1))
  rm -f "$BOT_ENV"
else
  pass "dry-run did not create bot/.env"
fi

if [[ "$WEB_WAS_ABSENT" == "1" ]] && [[ -f "$WEB_ENV" ]]; then
  fail "dry-run created web/.env (should not)"
  ERRORS=$((ERRORS + 1))
  rm -f "$WEB_ENV"
else
  pass "dry-run did not create web/.env"
fi

# ── Test 6: dry-run does not write installer config ─────────────────────────

INSTALLER_CFG="${HOME}/.nanobk/installer.env"
CFG_WAS_ABSENT=0
[[ ! -f "$INSTALLER_CFG" ]] && CFG_WAS_ABSENT=1

bash "$ROOT/installer/install.sh" --mode full --dry-run --defaults --lang zh --save-config >/dev/null 2>&1 || true

if [[ "$CFG_WAS_ABSENT" == "1" ]] && [[ -f "$INSTALLER_CFG" ]]; then
  fail "dry-run created installer config (should not)"
  ERRORS=$((ERRORS + 1))
  rm -f "$INSTALLER_CFG"
else
  pass "dry-run did not create installer config"
fi

# ── Test 7: --mode doctor --dry-run ─────────────────────────────────────────

echo ""
echo "--- --mode doctor --dry-run ---"
echo ""

DOCTOR_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults 2>&1 || true)

if grep -q "DRY-RUN\|dry-run" <<< "$DOCTOR_OUTPUT"; then
  pass "doctor --dry-run shows dry-run"
else
  fail "doctor --dry-run missing dry-run"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 8: --mode test --dry-run ───────────────────────────────────────────

echo ""
echo "--- --mode test --dry-run ---"
echo ""

TEST_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode test --dry-run --defaults 2>&1 <<< "5" || true)

if grep -q "DRY-RUN\|dry-run" <<< "$TEST_OUTPUT"; then
  pass "test --dry-run shows dry-run"
else
  fail "test --dry-run missing dry-run"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All unified installer dry-run tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
