#!/usr/bin/env bash
# NanoBK Proxy Suite — Summary Honesty Test
#
# Verifies that the summary output is honest about deployment states.
#
# Usage:
#   bash tests/unified-summary-honesty.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_DIR/installer/install.sh"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

contains() {
  local text="$1"
  local pattern="$2"
  if grep -qi -- "$pattern" <<< "$text"; then
    echo "1"
  else
    echo "0"
  fi
}

not_contains() {
  local text="$1"
  local pattern="$2"
  if grep -qi -- "$pattern" <<< "$text"; then
    echo "0"
  else
    echo "1"
  fi
}

echo "=== Summary Honesty Test ==="
echo ""

# ── Test 1: dry-run summary ─────────────────────────────────────────────────
echo "── Test 1: dry-run summary honesty ──"

OUTPUT=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || true

check "has planned or dry-run" "$(contains "$OUTPUT" "planned\|dry-run")"
check "does NOT show installed" "$(not_contains "$OUTPUT" "status:  installed")"
check "does NOT show verified" "$(not_contains "$OUTPUT" "status:  verified")"
check "has dry-run disclaimer" "$(contains "$OUTPUT" "dry-run.*没有执行\|dry-run.*No real")"
check "does NOT show real tokens" "$(not_contains "$OUTPUT" "kairkiss314-")"

# ── Test 2: commands-only disclaimer ────────────────────────────────────────
echo ""
echo "── Test 2: commands-only disclaimer ──"

OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1) || true

check "has commands-only disclaimer" "$(contains "$OUTPUT_CMD" "commands-only.*不验证\|commands-only.*not validate\|commands-only.*不输出\|commands-only.*只输出")"

# ── Test 3: static checks ───────────────────────────────────────────────────
echo ""
echo "── Test 3: static checks ──"

has_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "1"
  else
    echo "0"
  fi
}

check "has failed state in summary" "$(has_pattern "$INSTALLER" 'status.*failed')"
check "has skipped_dependency in summary" "$(has_pattern "$INSTALLER" "skipped.*dependency\|dependency.*missing")"
check "has control_only in summary" "$(has_pattern "$INSTALLER" "control.*plane.*only\|control_only")"
check "has dry_run in summary" "$(has_pattern "$INSTALLER" "planned.*dry-run\|dry-run")"
check "has dry-run disclaimer" "$(has_pattern "$INSTALLER" "dry-run.*没有执行\|dry-run.*No real")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
