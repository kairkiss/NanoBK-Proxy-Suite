#!/usr/bin/env bash
# NanoBK Proxy Suite — Dry-run Preflight Safety Test
#
# Verifies that dry-run mode is not affected by real port occupation.
# Dry-run should always report "assumed free (dry-run)" and never
# enter the core port conflict interactive menu.
#
# Usage:
#   bash tests/unified-dry-run-preflight.sh

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

echo "=== Dry-run Preflight Safety Test ==="
echo ""

# ── Test 1: full --dry-run --defaults not blocked by ports ──────────────────
echo "── Test 1: full --dry-run --defaults ──"

rm -f "$REPO_DIR/bot/.env" "$REPO_DIR/web/.env"

EXIT_CODE=0
OUTPUT=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "contains assumed free" "$(contains "$OUTPUT" "assumed free")"
check "contains dry-run" "$(contains "$OUTPUT" "dry-run")"
check "no port conflict menu" "$(not_contains "$OUTPUT" "端口冲突，已退出")"
check "no port conflict exit" "$(not_contains "$OUTPUT" "端口冲突，已退出")"
check "no real port occupied msg" "$(not_contains "$OUTPUT" "已被占用")"
check "does NOT write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"
check "does NOT write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

# ── Test 2: cli-only --dry-run --defaults ───────────────────────────────────
echo ""
echo "── Test 2: cli-only --dry-run --defaults ──"

EXIT_CODE=0
OUTPUT_CLI=$(bash "$INSTALLER" --mode cli-only --dry-run --defaults --lang zh 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "contains assumed free" "$(contains "$OUTPUT_CLI" "assumed free")"
check "no port conflict menu" "$(not_contains "$OUTPUT_CLI" "端口冲突，已退出")"
check "no port conflict exit" "$(not_contains "$OUTPUT_CLI" "端口冲突，已退出")"

# ── Test 3: cli-bot --dry-run --defaults ────────────────────────────────────
echo ""
echo "── Test 3: cli-bot --dry-run --defaults ──"

EXIT_CODE=0
OUTPUT_CB=$(bash "$INSTALLER" --mode cli-bot --dry-run --defaults --lang zh 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "contains assumed free" "$(contains "$OUTPUT_CB" "assumed free")"
check "no port conflict menu" "$(not_contains "$OUTPUT_CB" "端口冲突，已退出")"

# ── Test 4: cli-web --dry-run --defaults ────────────────────────────────────
echo ""
echo "── Test 4: cli-web --dry-run --defaults ──"

EXIT_CODE=0
OUTPUT_CW=$(bash "$INSTALLER" --mode cli-web --dry-run --defaults --lang zh 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "contains assumed free" "$(contains "$OUTPUT_CW" "assumed free")"
check "no port conflict menu" "$(not_contains "$OUTPUT_CW" "端口冲突，已退出")"

# ── Test 5: cli-bot-web --dry-run --defaults ────────────────────────────────
echo ""
echo "── Test 5: cli-bot-web --dry-run --defaults ──"

EXIT_CODE=0
OUTPUT_CBW=$(bash "$INSTALLER" --mode cli-bot-web --dry-run --defaults --lang zh 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
check "contains assumed free" "$(contains "$OUTPUT_CBW" "assumed free")"
check "no port conflict menu" "$(not_contains "$OUTPUT_CBW" "端口冲突，已退出")"

# ── Test 6: Static checks ──────────────────────────────────────────────────
echo ""
echo "── Test 6: Static checks ──"

check "DRY_RUN branch exists for ports" "$(grep -q 'DRY_RUN.*==.*1.*assumed free\|assumed free.*dry-run' "$INSTALLER" 2>/dev/null && echo 1 || echo 0)"
check "no handle_core_port_conflict in dry-run port path" "$(grep -B2 'assumed free' "$INSTALLER" | grep -q 'handle_core_port_conflict' && echo 0 || echo 1)"

# ss unavailable branch must not recurse
SS_BLOCK="$(grep -n -A8 -B2 'ss 不可用' "$INSTALLER" || true)"
check "ss unavailable branch does not recurse" "$(echo "$SS_BLOCK" | grep -q 'handle_core_port_conflict' && echo 0 || echo 1)"
check "ss unavailable branch has return 1" "$(echo "$SS_BLOCK" | grep -q 'return 1' && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
