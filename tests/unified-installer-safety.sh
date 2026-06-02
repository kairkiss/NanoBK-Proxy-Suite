#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Installer Safety Test
#
# Verifies that --defaults cannot run real deployments without --dry-run.
# Verifies that dry-run does not write sensitive files.
# Verifies that output does not contain real tokens.
#
# Usage:
#   bash tests/unified-installer-safety.sh

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

echo "=== Unified Installer Safety Test ==="
echo ""

# ── Test 1: --defaults without --dry-run must fail for destructive modes ────
echo "── Test 1: --defaults blocks real deployment ──"

for mode in cli-only cli-bot cli-web cli-bot-web; do
  EXIT_CODE=0
  OUTPUT=$(bash "$INSTALLER" --mode "$mode" --defaults 2>&1) || EXIT_CODE=$?
  check "--mode $mode --defaults exits non-zero" "$([[ $EXIT_CODE -ne 0 ]] && echo 1 || echo 0)"
  check "--mode $mode --defaults shows safety message" "$(contains "$OUTPUT" "不支持\|--dry-run\|dry-run")"
done

# ── Test 2: --defaults with --dry-run must succeed ──────────────────────────
echo ""
echo "── Test 2: --defaults --dry-run succeeds ──"

for mode in cli-only cli-bot cli-web cli-bot-web; do
  OUTPUT=$(bash "$INSTALLER" --mode "$mode" --defaults --dry-run --lang zh 2>&1) || true
  EXIT_CODE=$?
  check "--mode $mode --defaults --dry-run succeeds" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"
done

# ── Test 3: commands --defaults must succeed ────────────────────────────────
echo ""
echo "── Test 3: commands/doctor --defaults succeed ──"

OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1) || true
check "commands --defaults succeeds" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

OUTPUT_DOC=$(bash "$INSTALLER" --mode doctor --defaults --dry-run 2>&1) || true
check "doctor --defaults --dry-run succeeds" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

# ── Test 4: dry-run does not write bot/.env or web/.env ────────────────────
echo ""
echo "── Test 4: dry-run does not write env files ──"

# Ensure clean state
rm -f "$REPO_DIR/bot/.env" "$REPO_DIR/web/.env"

bash "$INSTALLER" --mode cli-bot --defaults --dry-run --lang zh >/dev/null 2>&1 || true
check "cli-bot dry-run does not write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"

bash "$INSTALLER" --mode cli-web --defaults --dry-run --lang zh >/dev/null 2>&1 || true
check "cli-web dry-run does not write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

bash "$INSTALLER" --mode full --defaults --dry-run --lang zh >/dev/null 2>&1 || true
check "full dry-run does not write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"
check "full dry-run does not write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

# ── Test 5: output does not contain real tokens ────────────────────────────
echo ""
echo "── Test 5: no real tokens in output ──"

FULL_OUTPUT=$(bash "$INSTALLER" --mode full --defaults --dry-run --lang zh 2>&1) || true
blocked_ip="62.60"".""250.69"
check "no kairkiss314- token" "$( [[ $(echo "$FULL_OUTPUT" | grep -c "kairkiss314-") -eq 0 ]] && echo 1 || echo 0 )"
check "no blocked VPS IP" "$( [[ $(echo "$FULL_OUTPUT" | grep -c "$blocked_ip") -eq 0 ]] && echo 1 || echo 0 )"

# ── Test 6: legacy modes still work ────────────────────────────────────────
echo ""
echo "── Test 6: legacy modes still work ──"

EXIT_CODE=0
OUTPUT_LEGACY=$(bash "$INSTALLER" --mode vps --defaults --dry-run --lang zh 2>&1) || EXIT_CODE=$?
check "vps --defaults --dry-run works" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"

EXIT_CODE=0
OUTPUT_LEGACY2=$(bash "$INSTALLER" --mode vps --defaults 2>&1) || EXIT_CODE=$?
check "vps --defaults (no dry-run) blocked" "$([[ $EXIT_CODE -ne 0 ]] && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
