#!/usr/bin/env bash
# NanoBK Proxy Suite — Web Panel Mock Test
#
# Runs the web panel's --self-test mode to validate core logic
# without starting Flask server or calling real nanobk commands.
#
# Usage:
#   bash tests/web-panel-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== NanoBK Web Panel Mock Test ==="
echo ""

# ── Syntax check ────────────────────────────────────────────────────────────

echo "--- Syntax checks ---"
echo ""

if python3 -m py_compile "$ROOT/web/app.py" 2>/dev/null; then
  pass "app.py compiles"
else
  fail "app.py compilation failed"
  ERRORS=$((ERRORS + 1))
fi

if bash -n "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh syntax"
else
  fail "run.sh syntax error"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Self-test ───────────────────────────────────────────────────────────────

echo "--- Running web panel self-test ---"
echo ""

if python3 "$ROOT/web/app.py" --self-test; then
  pass "web panel --self-test passed"
else
  fail "web panel --self-test failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Safety checks ───────────────────────────────────────────────────────────

echo "--- Safety checks ---"
echo ""

# No shell=True in web code (excluding comments/docstrings)
if grep -v '^\s*#' "$ROOT/web/app.py" | grep -v '"""' | grep -q "shell=True" 2>/dev/null; then
  fail "shell=True found in app.py (code)"
  ERRORS=$((ERRORS + 1))
else
  pass "No shell=True in app.py (code only)"
fi

# No real tokens in web code
if grep -qE 'NANOBK_WEB_TOKEN="[A-Za-z0-9]{10,}"' "$ROOT/web/app.py" 2>/dev/null; then
  fail "Real web token found in app.py"
  ERRORS=$((ERRORS + 1))
else
  pass "No real web token in app.py"
fi

# .env is gitignored
if git -C "$ROOT" check-ignore "web/.env" >/dev/null 2>&1; then
  pass "web/.env is gitignored"
else
  fail "web/.env is NOT gitignored"
  ERRORS=$((ERRORS + 1))
fi

# .venv is gitignored
if git -C "$ROOT" check-ignore "web/.venv/" >/dev/null 2>&1; then
  pass "web/.venv is gitignored"
else
  fail "web/.venv is NOT gitignored"
  ERRORS=$((ERRORS + 1))
fi

# strip_ansi exists
if grep -q "def strip_ansi" "$ROOT/web/app.py" 2>/dev/null; then
  pass "strip_ansi function exists"
else
  fail "strip_ansi function missing"
  ERRORS=$((ERRORS + 1))
fi

# safe_output calls strip_ansi
if grep -A8 "def safe_output" "$ROOT/web/app.py" | grep -q "strip_ansi" 2>/dev/null; then
  pass "safe_output calls strip_ansi"
else
  fail "safe_output does not call strip_ansi"
  ERRORS=$((ERRORS + 1))
fi

# run.sh contains venv guidance
if grep -q "python3-venv\|python.*venv" "$ROOT/web/run.sh" 2>/dev/null; then
  pass "web/run.sh contains venv guidance"
else
  fail "web/run.sh missing venv guidance"
  ERRORS=$((ERRORS + 1))
fi

# Default host is 127.0.0.1
if grep -q '127.0.0.1' "$ROOT/web/.env.example" 2>/dev/null; then
  pass ".env.example binds to 127.0.0.1"
else
  fail ".env.example missing 127.0.0.1"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All web panel tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
