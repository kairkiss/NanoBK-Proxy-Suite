#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Beginner Flow Test
#
# Tests the unified beginner installer in dry-run and commands-only modes.
# Verifies output contains expected stages and does not write sensitive files.
#
# Usage:
#   bash tests/unified-beginner-flow.sh

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

echo "=== Unified Beginner Flow Test ==="
echo ""

# ── Test 1: --mode full --dry-run --defaults --lang zh ─────────────────────
echo "── Test 1: full --dry-run --defaults --lang zh ──"

OUTPUT=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || true

check "contains preflight" "$(contains "$OUTPUT" "Preflight")"
check "contains VPS 部署" "$(contains "$OUTPUT" "VPS")"
check "contains Cloudflare" "$(contains "$OUTPUT" "Cloudflare\|cloudflare")"
check "contains Bot" "$(contains "$OUTPUT" "Bot\|bot/.env")"
check "contains Web" "$(contains "$OUTPUT" "Web Panel\|web/.env")"
check "contains Summary" "$(contains "$OUTPUT" "Summary\|摘要")"
check "contains DRY-RUN" "$(contains "$OUTPUT" "DRY-RUN\|dry-run")"
check "does NOT write bot/.env" "$( [[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0 )"
check "does NOT write web/.env" "$( [[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0 )"

# ── Test 2: --mode full --dry-run --defaults --lang en ─────────────────────
echo ""
echo "── Test 2: full --dry-run --defaults --lang en ──"

OUTPUT_EN=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang en 2>&1) || true

check "contains English partial warning" "$(contains "$OUTPUT_EN" "partial\|English")"
check "contains preflight" "$(contains "$OUTPUT_EN" "Preflight")"
check "contains VPS" "$(contains "$OUTPUT_EN" "VPS")"
check "does NOT write bot/.env" "$( [[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0 )"
check "does NOT write web/.env" "$( [[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0 )"

# ── Test 3: --mode commands --defaults ──────────────────────────────────────
echo ""
echo "── Test 3: commands --defaults ──"

OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1) || true

check "contains VPS install" "$(contains "$OUTPUT_CMD" "install-vps")"
check "contains Cloudflare preflight" "$(contains "$OUTPUT_CMD" "preflight")"
check "contains Cloudflare deploy" "$(contains "$OUTPUT_CMD" "install-cloudflare")"
check "contains Bot env template" "$(contains "$OUTPUT_CMD" "TELEGRAM_BOT_TOKEN\|bot/.env")"
check "contains Web env template" "$(contains "$OUTPUT_CMD" "NANOBK_WEB_TOKEN\|web/.env")"
check "contains SSH tunnel" "$(contains "$OUTPUT_CMD" "ssh -L")"
check "contains healthcheck" "$(contains "$OUTPUT_CMD" "healthcheck")"
check "contains nanobk status" "$(contains "$OUTPUT_CMD" "nanobk status")"
check "contains rotate" "$(contains "$OUTPUT_CMD" "rotate")"

# ── Test 4: --mode cli-bot --dry-run --defaults ────────────────────────────
echo ""
echo "── Test 4: cli-bot --dry-run --defaults ──"

OUTPUT_CB=$(bash "$INSTALLER" --mode cli-bot --dry-run --defaults --lang zh 2>&1) || true

check "contains VPS" "$(contains "$OUTPUT_CB" "VPS")"
check "contains Bot" "$(contains "$OUTPUT_CB" "Bot\|bot/.env")"
check "does NOT write bot/.env" "$( [[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0 )"

# ── Test 5: --mode cli-web --dry-run --defaults ────────────────────────────
echo ""
echo "── Test 5: cli-web --dry-run --defaults ──"

OUTPUT_CW=$(bash "$INSTALLER" --mode cli-web --dry-run --defaults --lang zh 2>&1) || true

check "contains VPS" "$(contains "$OUTPUT_CW" "VPS")"
check "contains Web" "$(contains "$OUTPUT_CW" "Web Panel\|web/.env")"
check "contains Preflight" "$(contains "$OUTPUT_CW" "Preflight")"
check "does NOT write web/.env" "$( [[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0 )"

# ── Test 6: combo modes include Preflight ───────────────────────────────────
echo ""
echo "── Test 6: combo modes include Preflight ──"

OUTPUT_CLI=$(bash "$INSTALLER" --mode cli-only --dry-run --defaults --lang zh 2>&1) || true
check "cli-only includes Preflight" "$(contains "$OUTPUT_CLI" "Preflight")"

OUTPUT_CB=$(bash "$INSTALLER" --mode cli-bot --dry-run --defaults --lang zh 2>&1) || true
check "cli-bot includes Preflight" "$(contains "$OUTPUT_CB" "Preflight")"

OUTPUT_CBW=$(bash "$INSTALLER" --mode cli-bot-web --dry-run --defaults --lang zh 2>&1) || true
check "cli-bot-web includes Preflight" "$(contains "$OUTPUT_CBW" "Preflight")"

# ── Test 7: summary uses honest states in dry-run ───────────────────────────
echo ""
echo "── Test 7: summary uses honest states ──"

OUTPUT_FULL=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || true
check "dry-run summary has planned or dry-run" "$(contains "$OUTPUT_FULL" "planned\|dry-run")"
check "dry-run summary does NOT show installed" "$( [[ $(grep -c "status:  installed" <<< "$OUTPUT_FULL") -eq 0 ]] && echo 1 || echo 0 )"
check "dry-run summary does NOT show verified" "$( [[ $(grep -c "status:  verified" <<< "$OUTPUT_FULL") -eq 0 ]] && echo 1 || echo 0 )"
check "full dry-run has assumed free" "$(contains "$OUTPUT_FULL" "assumed free")"
check "dry-run summary says no real deployment" "$(contains "$OUTPUT_FULL" "dry-run.*没有执行\|dry-run.*No real\|dry-run 摘要")"
check "dry-run has no healthcheck passed" "$( [[ $(grep -c "healthcheck passed" <<< "$OUTPUT_FULL") -eq 0 ]] && echo 1 || echo 0 )"
check "dry-run has no Cloudflare verified" "$( [[ $(grep -c "Cloudflare.*verified\|nanok.*verified" <<< "$OUTPUT_FULL") -eq 0 ]] && echo 1 || echo 0 )"

OUTPUT_CLI_DRY=$(bash "$INSTALLER" --mode cli-only --dry-run --defaults --lang zh 2>&1) || true
check "cli-only dry-run has assumed free" "$(contains "$OUTPUT_CLI_DRY" "assumed free")"

# commands-only boundary
OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1) || true
check "commands-only says does not validate" "$(contains "$OUTPUT_CMD" "不会验证\|does not validate")"

# ── Test 8: install.sh --help shows new modes ──────────────────────────────
echo ""
echo "── Test 8: help shows new modes ──"

HELP=$(bash "$INSTALLER" --help 2>&1) || true

check "help contains cli-only" "$(contains "$HELP" "cli-only")"
check "help contains cli-bot" "$(contains "$HELP" "cli-bot")"
check "help contains cli-web" "$(contains "$HELP" "cli-web")"
check "help contains cli-bot-web" "$(contains "$HELP" "cli-bot-web")"
check "help contains Full Recommended" "$(contains "$HELP" "Full Recommended\|full")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
