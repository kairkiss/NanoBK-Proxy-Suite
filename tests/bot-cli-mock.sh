#!/usr/bin/env bash
# NanoBK Proxy Suite — Bot CLI Mock Test
#
# Runs the bot's --self-test mode to validate core logic
# without connecting to Telegram or calling real nanobk commands.
#
# Usage:
#   bash tests/bot-cli-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== NanoBK Bot CLI Mock Test ==="
echo ""

# ── Syntax check ────────────────────────────────────────────────────────────

echo "--- Syntax checks ---"
echo ""

if python3 -m py_compile "$ROOT/bot/nanobk_bot.py" 2>/dev/null; then
  pass "nanobk_bot.py compiles"
else
  fail "nanobk_bot.py compilation failed"
  ERRORS=$((ERRORS + 1))
fi

if bash -n "$ROOT/bot/run.sh" 2>/dev/null; then
  pass "run.sh syntax"
else
  fail "run.sh syntax error"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Self-test ───────────────────────────────────────────────────────────────

echo "--- Running bot self-test ---"
echo ""

if python3 "$ROOT/bot/nanobk_bot.py" --self-test; then
  pass "bot --self-test passed"
else
  fail "bot --self-test failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Safety checks ───────────────────────────────────────────────────────────

echo "--- Safety checks ---"
echo ""

# No shell=True in bot code (excluding comments and docstrings)
if grep -v '^\s*#' "$ROOT/bot/nanobk_bot.py" | grep -v '"""' | grep -q "shell=True" 2>/dev/null; then
  fail "shell=True found in nanobk_bot.py (code)"
  ERRORS=$((ERRORS + 1))
else
  pass "No shell=True in nanobk_bot.py (code only)"
fi

# No real tokens in bot code
if grep -qE 'TELEGRAM_BOT_TOKEN="[0-9]+:' "$ROOT/bot/nanobk_bot.py" 2>/dev/null; then
  fail "Real bot token found in nanobk_bot.py"
  ERRORS=$((ERRORS + 1))
else
  pass "No real bot token in nanobk_bot.py"
fi

# .env is gitignored
if git -C "$ROOT" check-ignore "bot/.env" >/dev/null 2>&1; then
  pass "bot/.env is gitignored"
else
  fail "bot/.env is NOT gitignored"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All bot tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
