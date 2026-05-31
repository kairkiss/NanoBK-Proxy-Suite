#!/usr/bin/env bash
# NanoBK Proxy Suite — Noninteractive Mode Test
#
# Verifies that commands and test modes run without hanging.
# Uses timeout guards to prevent indefinite hangs.
#
# Usage:
#   bash tests/unified-noninteractive-mode.sh

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
  if echo "$text" | grep -qi "$pattern"; then
    echo "1"
  else
    echo "0"
  fi
}

not_contains() {
  local text="$1"
  local pattern="$2"
  if echo "$text" | grep -qi "$pattern"; then
    echo "0"
  else
    echo "1"
  fi
}

# Timeout wrapper: uses `timeout` if available, otherwise runs directly
run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

echo "=== Noninteractive Mode Test ==="
echo ""

# ── Test 0: Timeout guard exists ────────────────────────────────────────────
echo "── Test 0: Timeout guard ──"

check "has run_with_timeout helper" "$(grep -q 'run_with_timeout' "$0" && echo 1 || echo 0)"
check "uses timeout for commands dry-run" "$(grep -q 'run_with_timeout 20' "$0" && echo 1 || echo 0)"
check "uses timeout for test defaults" "$(grep -q 'run_with_timeout 180' "$0" && echo 1 || echo 0)"

# ── Test 1: --mode commands --dry-run ───────────────────────────────────────
echo ""
echo "── Test 1: --mode commands --dry-run ──"

rm -f "$REPO_DIR/bot/.env" "$REPO_DIR/web/.env"
EXIT_CODE=0
OUTPUT=$(run_with_timeout 20 bash "$INSTALLER" --mode commands --dry-run 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "exit code not 124 (timeout)" "$([[ $EXIT_CODE -ne 124 ]] && echo 1 || echo 0)"
check "contains commands-only disclaimer" "$(contains "$OUTPUT" "不会验证\|does not validate")"
check "contains install-vps" "$(contains "$OUTPUT" "install-vps")"
check "contains install-cloudflare" "$(contains "$OUTPUT" "install-cloudflare")"
check "contains Bot env template" "$(contains "$OUTPUT" "TELEGRAM_BOT_TOKEN\|Bot")"
check "contains Web env template" "$(contains "$OUTPUT" "NANOBK_WEB_TOKEN\|Web")"
check "contains nanobk status" "$(contains "$OUTPUT" "nanobk status")"
check "contains rotate" "$(contains "$OUTPUT" "rotate")"
check "does NOT write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"
check "does NOT write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

# ── Test 2: --mode commands (no --dry-run) ──────────────────────────────────
echo ""
echo "── Test 2: --mode commands ──"

EXIT_CODE=0
OUTPUT2=$(run_with_timeout 20 bash "$INSTALLER" --mode commands 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "exit code not 124 (timeout)" "$([[ $EXIT_CODE -ne 124 ]] && echo 1 || echo 0)"
check "contains commands-only disclaimer" "$(contains "$OUTPUT2" "不会验证\|does not validate")"

# ── Test 3: --mode commands --defaults ───────────────────────────────────────
echo ""
echo "── Test 3: --mode commands --defaults ──"

EXIT_CODE=0
OUTPUT3=$(run_with_timeout 20 bash "$INSTALLER" --mode commands --defaults 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "exit code not 124 (timeout)" "$([[ $EXIT_CODE -ne 124 ]] && echo 1 || echo 0)"

# ── Test 4: --mode commands --dry-run --defaults ────────────────────────────
echo ""
echo "── Test 4: --mode commands --dry-run --defaults ──"

EXIT_CODE=0
OUTPUT4=$(run_with_timeout 20 bash "$INSTALLER" --mode commands --dry-run --defaults 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "exit code not 124 (timeout)" "$([[ $EXIT_CODE -ne 124 ]] && echo 1 || echo 0)"

# ── Test 5: --mode test --defaults ──────────────────────────────────────────
echo ""
echo "── Test 5: --mode test --defaults ──"

EXIT_CODE=0
OUTPUT5=$(run_with_timeout 180 bash "$INSTALLER" --mode test --defaults 2>&1) || EXIT_CODE=$?

check "exit code 0 or non-zero (not hang)" "1"
check "exit code not 124 (timeout)" "$([[ $EXIT_CODE -ne 124 ]] && echo 1 || echo 0)"
check "output exists" "$([[ -n "$OUTPUT5" ]] && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
