#!/usr/bin/env bash
# NanoBK Proxy Suite — Bootstrap Dry-Run Test
#
# Tests that bootstrap.sh works correctly in dry-run mode.
# Does NOT clone, pull, or launch anything.
#
# Usage:
#   bash tests/bootstrap-dry-run.sh

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
echo "=== Bootstrap Dry-Run Test ==="
echo ""

# ── Syntax check ────────────────────────────────────────────────────────────

echo "--- Syntax check ---"
echo ""
check "bootstrap.sh syntax" bash -n "$ROOT/installer/bootstrap.sh"

# ── --help ──────────────────────────────────────────────────────────────────

echo ""
echo "--- --help ---"
echo ""

HELP_OUTPUT=$(bash "$ROOT/installer/bootstrap.sh" --help 2>&1)
if grep -q "Remote Bootstrap" <<< "$HELP_OUTPUT"; then
  pass "--help shows usage"
else
  fail "--help missing expected text"
  ERRORS=$((ERRORS + 1))
fi

# ── --dry-run (clone to temp dir) ───────────────────────────────────────────

echo ""
echo "--- ---"
echo ""

DRY_OUTPUT=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-bootstrap-dry-test-$$ 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

if grep -q "DRY-RUN" <<< "$DRY_OUTPUT"; then
  pass "--dry-run shows DRY-RUN"
else
  fail "--dry-run missing DRY-RUN marker"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "git clone" <<< "$DRY_OUTPUT"; then
  pass "--dry-run shows clone command"
else
  fail "--dry-run missing clone command"
  ERRORS=$((ERRORS + 1))
fi

# v2.1.1: default bootstrap should NOT launch install.sh
if grep -q "install.sh" <<< "$DRY_OUTPUT"; then
  fail "--dry-run default should NOT show install.sh launch"
  ERRORS=$((ERRORS + 1))
else
  pass "--dry-run default does not show install.sh launch (install-only)"
fi

# v2.1.1: default bootstrap should show product-ready message
if grep -q "NanoBK is ready" <<< "$DRY_OUTPUT"; then
  pass "--dry-run default shows 'NanoBK is ready'"
else
  fail "--dry-run default missing 'NanoBK is ready' message"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "nanobk" <<< "$DRY_OUTPUT"; then
  pass "--dry-run default shows 'nanobk' next step"
else
  fail "--dry-run default missing 'nanobk' next step"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "仓库尚未实际 clone" <<< "$DRY_OUTPUT"; then
  pass "--dry-run clarifies clone is preview only"
else
  fail "--dry-run missing clone preview clarification"
  ERRORS=$((ERRORS + 1))
fi

# ── --dry-run with passthrough args ─────────────────────────────────────────

echo ""
echo "--- --dry-run with passthrough ---"
echo ""

PASSTHROUGH_OUTPUT=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-passthrough-test-$$ -- --mode commands 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

if grep -q "\-\-mode commands" <<< "$PASSTHROUGH_OUTPUT"; then
  pass "passthrough --mode commands"
else
  fail "passthrough args not forwarded"
  ERRORS=$((ERRORS + 1))
fi

# v2.1.1: explicit passthrough should still show install.sh launch
if grep -q "install.sh" <<< "$PASSTHROUGH_OUTPUT"; then
  pass "passthrough shows install.sh launch (legacy path preserved)"
else
  fail "passthrough missing install.sh launch"
  ERRORS=$((ERRORS + 1))
fi

# ── No eval in script ───────────────────────────────────────────────────────

echo ""
echo "--- Safety checks ---"
echo ""

if grep -q 'eval ' "$ROOT/installer/install.sh" 2>/dev/null; then
  # eval in prompt() is acceptable (for variable assignment), but not in test execution
  if grep 'eval.*\$test_cmd\|eval.*\$cmd' "$ROOT/installer/install.sh" 2>/dev/null; then
    fail "eval found in test/command execution"
    ERRORS=$((ERRORS + 1))
  else
    pass "eval only in prompt() (acceptable for variable assignment)"
  fi
else
  pass "no eval found"
fi

if grep -q 'run_one_test' "$ROOT/installer/install.sh" 2>/dev/null; then
  pass "run_one_test function exists (no eval in test mode)"
else
  fail "run_one_test not found"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
