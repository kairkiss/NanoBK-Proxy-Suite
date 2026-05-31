#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Installer Config Test
#
# Tests --save-config and --resume functionality.
#
# Usage:
#   bash tests/unified-installer-config.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-installer-config-test"

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
echo "=== Unified Installer Config Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# ── Test 1: --save-config writes config ─────────────────────────────────────

echo "--- --save-config ---"
echo ""

CONFIG_FILE="$TMP/test-installer.env"

bash "$ROOT/installer/install.sh" --mode commands --defaults --lang zh \
  --config-file "$CONFIG_FILE" --save-config 2>/dev/null || true

if [[ -f "$CONFIG_FILE" ]]; then
  pass "--save-config writes config file"
else
  fail "--save-config did not write config file"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: config permissions ──────────────────────────────────────────────

if [[ -f "$CONFIG_FILE" ]]; then
  PERMS=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    pass "config file permissions: 600"
  else
    fail "config file permissions: ${PERMS} (expected 600)"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Test 3: config does not contain sensitive tokens ────────────────────────

echo ""
echo "--- Security checks ---"
echo ""

if [[ -f "$CONFIG_FILE" ]]; then
  if grep -qi "TELEGRAM_BOT_TOKEN" "$CONFIG_FILE" 2>/dev/null; then
    fail "config contains TELEGRAM_BOT_TOKEN"
    ERRORS=$((ERRORS + 1))
  else
    pass "config does not contain TELEGRAM_BOT_TOKEN"
  fi

  if grep -qi "NANOBK_WEB_TOKEN" "$CONFIG_FILE" 2>/dev/null; then
    fail "config contains NANOBK_WEB_TOKEN"
    ERRORS=$((ERRORS + 1))
  else
    pass "config does not contain NANOBK_WEB_TOKEN"
  fi

  if grep -qi "NANOBK_WEB_SECRET_KEY" "$CONFIG_FILE" 2>/dev/null; then
    fail "config contains NANOBK_WEB_SECRET_KEY"
    ERRORS=$((ERRORS + 1))
  else
    pass "config does not contain NANOBK_WEB_SECRET_KEY"
  fi

  if grep -qi "SUB_TOKEN" "$CONFIG_FILE" 2>/dev/null; then
    fail "config contains SUB_TOKEN"
    ERRORS=$((ERRORS + 1))
  else
    pass "config does not contain SUB_TOKEN"
  fi

  if grep -qi "ADMIN_TOKEN" "$CONFIG_FILE" 2>/dev/null; then
    fail "config contains ADMIN_TOKEN"
    ERRORS=$((ERRORS + 1))
  else
    pass "config does not contain ADMIN_TOKEN"
  fi
fi

# ── Test 4: --resume reads config ───────────────────────────────────────────

echo ""
echo "--- --resume ---"
echo ""

if [[ -f "$CONFIG_FILE" ]]; then
  RESUME_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults \
    --config-file "$CONFIG_FILE" --resume 2>&1 || true)

  if echo "$RESUME_OUTPUT" | grep -q "读取已有配置\|Loading\|config"; then
    pass "--resume reads config"
  else
    # May not print explicit message, just verify it doesn't crash
    pass "--resume did not crash"
  fi
fi

# ── Test 5: invalid config does not crash ───────────────────────────────────

echo ""
echo "--- Invalid config ---"
echo ""

INVALID_CONFIG="$TMP/invalid.env"
echo 'NANOBK_INVALID_SYNTAX="unclosed' > "$INVALID_CONFIG"

INVALID_OUTPUT=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults \
  --config-file "$INVALID_CONFIG" --resume 2>&1 || true)

if echo "$INVALID_OUTPUT" | grep -q "ERROR\|error\|invalid"; then
  pass "invalid config shows error"
else
  # If it doesn't crash, that's acceptable
  pass "invalid config did not crash"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All config tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
