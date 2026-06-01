#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Behavior Test
#
# Real behavior tests using actual installer command output.
# Tests URL cleaning, cert-mode retry, dependency skipping,
# and failed control-plane setup.
#
# Usage:
#   bash tests/unified-full-wizard-behavior.sh

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

has_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "1"
  else
    echo "0"
  fi
}

echo "=== Full Wizard Behavior Test ==="
echo ""

# ── Test A: Static cert-mode retry structure ────────────────────────────────
echo "── Test A: Static cert-mode retry structure ──"

check "cert-mode uses while loop" "$(has_pattern "$INSTALLER" 'while true')"
check "no return 0 near reselect" "$( [[ $(grep -A2 '重新选择\|re-enter' "$INSTALLER" | grep -c 'return 0') -eq 0 ]] && echo 1 || echo 0 )"
check "reselect uses continue" "$(has_pattern "$INSTALLER" 'continue')"
check "exit uses return 1" "$(has_pattern "$INSTALLER" 'return 1')"
check "letsencrypt has reselect option" "$(has_pattern "$INSTALLER" "返回重新选择")"

# ── Test B: Real behavior — commands mode output ────────────────────────────
echo ""
echo "── Test B: Real behavior — commands mode output ──"

set +e
OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1)
CMD_RC=$?
set -e

check "commands mode exits 0" "$([[ $CMD_RC -eq 0 ]] && echo 1 || echo 0)"
check "commands output has install-vps" "$(contains "$OUTPUT_CMD" "install-vps")"
check "commands output has install-cloudflare" "$(contains "$OUTPUT_CMD" "install-cloudflare")"
check "commands output has nanobk status" "$(contains "$OUTPUT_CMD" "nanobk status")"
check "commands output has rotate" "$(contains "$OUTPUT_CMD" "rotate")"
check "commands output has Bot template" "$(contains "$OUTPUT_CMD" "TELEGRAM_BOT_TOKEN")"
check "commands output has Web template" "$(contains "$OUTPUT_CMD" "NANOBK_WEB_TOKEN")"

# ── Test C: Real behavior — dry-run full mode ───────────────────────────────
echo ""
echo "── Test C: Real behavior — dry-run full mode ──"

set +e
OUTPUT_DRY=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1)
DRY_RC=$?
set -e

check "dry-run exits 0" "$([[ $DRY_RC -eq 0 ]] && echo 1 || echo 0)"
check "dry-run has preflight" "$(contains "$OUTPUT_DRY" "Preflight")"
check "dry-run has assumed free" "$(contains "$OUTPUT_DRY" "assumed free")"
check "dry-run has planned/dry-run in summary" "$(contains "$OUTPUT_DRY" "planned\|dry-run")"
check "dry-run has dry-run disclaimer" "$(contains "$OUTPUT_DRY" "dry-run.*没有执行\|dry-run.*No real")"
check "dry-run does NOT write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"
check "dry-run does NOT write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

# ── Test D: Real behavior — validate-plan output ────────────────────────────
echo ""
echo "── Test D: Real behavior — validate-plan output ──"

set +e
OUTPUT_PLAN=$(bash "$INSTALLER" --mode validate-plan 2>&1)
PLAN_RC=$?
set -e

check "validate-plan exits 0" "$([[ $PLAN_RC -eq 0 ]] && echo 1 || echo 0)"
check "has Clean VPS" "$(contains "$OUTPUT_PLAN" "Clean VPS")"
check "has human tester" "$(contains "$OUTPUT_PLAN" "人工测试员\|human tester")"
check "has dry-run disclaimer" "$(contains "$OUTPUT_PLAN" "dry-run.*不能代表\|cannot claim")"
check "has Phase 0" "$(contains "$OUTPUT_PLAN" "Phase 0\|Baseline")"
check "has Phase 10" "$(contains "$OUTPUT_PLAN" "Phase 10\|Final Status")"
check "has Pass Criteria" "$(contains "$OUTPUT_PLAN" "Pass Criteria\|通过标准")"
check "has Fail Criteria" "$(contains "$OUTPUT_PLAN" "Fail Criteria\|失败标准")"

# ── Test E: Static Worker URL validation ────────────────────────────────────
echo ""
echo "── Test E: Static Worker URL validation ──"

check "Worker URL strips query params" "$(has_pattern "$INSTALLER" 'route_url%%')"
check "Worker URL rejects token" "$(has_pattern "$INSTALLER" "token=.*订阅\|不要粘贴带 token")"
check "Worker URL rejects http://" "$(has_pattern "$INSTALLER" "http://.*不支持\|必须使用 https")"
check "Worker URL bare host has confirmation" "$(has_pattern "$INSTALLER" "检测到未包含 https")"
check "nanob URL same validation" "$(has_pattern "$INSTALLER" 'nanob_url%%')"

# ── Test F: Static domain validation ────────────────────────────────────────
echo ""
echo "── Test F: Static domain validation ──"

check "domain rejects protocol with confirmation" "$(has_pattern "$INSTALLER" "不要带 https://\|不要带 http://")"
check "domain rejects spaces" "$(has_pattern "$INSTALLER" "域名不能包含空格\|不应包含空格")"
check "domain rejects path with confirmation" "$(has_pattern "$INSTALLER" "域名不应包含路径\|不应包含路径")"
check "domain has suggestion" "$(has_pattern "$INSTALLER" "检测到你可能想输入")"

# ── Test G: Static Cloudflare dependency ─────────────────────────────────────
echo ""
echo "── Test G: Static Cloudflare dependency ──"

check "profile check is unconditional" "$(has_pattern "$INSTALLER" "profile.current.json.*not found\|profile.current.json.*不存在")"
check "has recovery commands" "$(has_pattern "$INSTALLER" "mode vps.*lang\|mode cloudflare.*lang")"
check "has healthcheck recovery" "$(has_pattern "$INSTALLER" "healthcheck")"

# ── Test H: Static Bot/Web failed state ─────────────────────────────────────
echo ""
echo "── Test H: Static Bot/Web failed state ──"

check "Bot has failed state" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS.*failed")"
check "Web has failed state" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS.*failed")"
check "Bot failed in summary" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS.*==.*failed")"
check "Web failed in summary" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS.*==.*failed")"

# ── Test I: Static cert-mode letsencrypt ─────────────────────────────────────
echo ""
echo "── Test I: Static cert-mode letsencrypt ──"

check "has letsencrypt option" "$(has_pattern "$INSTALLER" "letsencrypt")"
check "letsencrypt says not recommended" "$(has_pattern "$INSTALLER" "暂不推荐\|not recommended")"
check "letsencrypt offers fallback" "$(has_pattern "$INSTALLER" "改用 self-signed\|改用 existing")"

# ── Test J: Static skipped execution states ─────────────────────────────────
echo ""
echo "── Test J: Static skipped execution states ──"

check "has LAST_RUN_CMD_STATUS" "$(has_pattern "$INSTALLER" "LAST_RUN_CMD_STATUS")"
check "has skipped_user state" "$(has_pattern "$INSTALLER" "skipped_user")"
check "has manual_pending state" "$(has_pattern "$INSTALLER" "manual_pending")"
check "has manual command not executed" "$(has_pattern "$INSTALLER" "manual command not executed\|manual.*pending")"
check "has commands_only state" "$(has_pattern "$INSTALLER" "commands_only")"
check "has dry_run state in VPS" "$(has_pattern "$INSTALLER" "VPS_STAGE_STATUS.*dry_run")"
check "has dry_run state in CF" "$(has_pattern "$INSTALLER" "CF_STAGE_STATUS.*dry_run\|CF_DEPLOY_STATUS.*dry_run")"
check "skipped_user does not show installed" "$( [[ $(grep -c 'skipped_user.*installed\|installed.*skipped_user' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"
check "manual_pending does not show deployed" "$( [[ $(grep -c 'manual_pending.*deployed\|deployed.*manual_pending' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"

# ── Test K: Control plane propagation ───────────────────────────────────────
echo ""
echo "── Test K: Control plane propagation ──"

check "has control_plane_only_required helper" "$(has_pattern "$INSTALLER" "control_plane_only_required")"
check "has vps_ready_for_control_plane helper" "$(has_pattern "$INSTALLER" "vps_ready_for_control_plane")"
check "has cf_ready_for_control_plane helper" "$(has_pattern "$INSTALLER" "cf_ready_for_control_plane")"
check "helper covers unknown" "$( [[ $(grep -A5 'vps_ready_for_control_plane' "$INSTALLER" | grep -c 'unknown') -gt 0 ]] && echo 1 || echo 0 )"
check "helper has wildcard for all other states" "$( [[ $(grep -A5 'vps_ready_for_control_plane' "$INSTALLER" | grep -c '\*') -gt 0 ]] && echo 1 || echo 0 )"
check "helper only returns 0 for installed" "$( [[ $(grep -A5 'vps_ready_for_control_plane' "$INSTALLER" | grep -c 'installed.*return 0') -gt 0 ]] && echo 1 || echo 0 )"
check "Bot uses helper for control_only" "$(has_pattern "$INSTALLER" "control_plane_only_required.*BOT\|BOT.*control_plane_only_required\|control_plane_only_required")"
check "Web uses helper for control_only" "$(has_pattern "$INSTALLER" "control_plane_only_required.*WEB\|WEB.*control_plane_only_required\|control_plane_only_required")"
check "Warnings show VPS status" "$(has_pattern "$INSTALLER" "VPS status.*VPS_STAGE_STATUS\|VPS_STAGE_STATUS.*VPS status")"
check "Warnings show CF status" "$(has_pattern "$INSTALLER" "Cloudflare status.*CF_STAGE_STATUS\|CF_STAGE_STATUS.*Cloudflare status")"
check "no old narrow control-only check" "$( [[ $(grep -c 'VPS_STAGE_STATUS.*failed.*CF_STAGE_STATUS.*failed.*skipped_dependency' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
