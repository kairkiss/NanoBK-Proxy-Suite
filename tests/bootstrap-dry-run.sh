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
if echo "$HELP_OUTPUT" | grep -q "Remote Bootstrap"; then
  pass "--help shows usage"
else
  fail "--help missing expected text"
  ERRORS=$((ERRORS + 1))
fi

# ── --dry-run (clone to temp dir) ───────────────────────────────────────────

echo ""
echo "--- --dry-run ---"
echo ""

DRY_OUTPUT=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-bootstrap-dry-test-$$ 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

if echo "$DRY_OUTPUT" | grep -q "DRY-RUN"; then
  pass "--dry-run shows DRY-RUN"
else
  fail "--dry-run missing DRY-RUN marker"
  ERRORS=$((ERRORS + 1))
fi

if echo "$DRY_OUTPUT" | grep -q "git clone"; then
  pass "--dry-run shows clone command"
else
  fail "--dry-run missing clone command"
  ERRORS=$((ERRORS + 1))
fi

if echo "$DRY_OUTPUT" | grep -q "install.sh"; then
  pass "--dry-run shows install.sh launch"
else
  fail "--dry-run missing install.sh launch"
  ERRORS=$((ERRORS + 1))
fi

# ── --dry-run with passthrough args ─────────────────────────────────────────

echo ""
echo "--- --dry-run with passthrough ---"
echo ""

PASSTHROUGH_OUTPUT=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-passthrough-test-$$ -- --mode commands 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

if echo "$PASSTHROUGH_OUTPUT" | grep -q "\-\-mode commands"; then
  pass "passthrough --mode commands"
else
  fail "passthrough args not forwarded"
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
