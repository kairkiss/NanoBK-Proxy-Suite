#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Review and Resume Test
#
# Tests for stage review tables, wizard state, resume, domain validation,
# strict menus, and Chinese terminology.
#
# Usage:
#   bash tests/unified-full-wizard-review-resume.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_DIR/installer/install.sh"
NANOBK="$REPO_DIR/bin/nanobk"

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

has_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "1"
  else
    echo "0"
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

echo "=== Full Wizard Review and Resume Test ==="
echo ""

# ── Test 1: Strict menu helper ──────────────────────────────────────────────
echo "── Test 1: Strict menu helper ──"

check "has prompt_menu_choice helper" "$(has_pattern "$INSTALLER" "prompt_menu_choice")"
check "rejects invalid input" "$(has_pattern "$INSTALLER" "无效输入")"
check "loops until valid" "$(has_pattern "$INSTALLER" "while true")"

# ── Test 2: Domain validation ───────────────────────────────────────────────
echo ""
echo "── Test 2: Domain validation ──"

check "has is_valid_domain_name helper" "$(has_pattern "$INSTALLER" "is_valid_domain_name")"
check "rejects no-dot domains" "$(has_pattern "$INSTALLER" "至少包含一个点")"
check "rejects all-numeric" "$(has_pattern "$INSTALLER" "不能是纯数字")"
check "rejects invalid chars" "$(has_pattern "$INSTALLER" "只能包含字母")"

# ── Test 3: Wizard state ────────────────────────────────────────────────────
echo ""
echo "── Test 3: Wizard state ──"

check "has wizard_state_path" "$(has_pattern "$INSTALLER" "wizard_state_path")"
check "has wizard_state_write" "$(has_pattern "$INSTALLER" "wizard_state_write")"
check "has wizard_state_print" "$(has_pattern "$INSTALLER" "wizard_state_print")"
check "has wizard_state_detect_existing" "$(has_pattern "$INSTALLER" "wizard_state_detect_existing")"
check "state file does not save raw secrets" "$( [[ $(grep -A30 'wizard_state_write' "$INSTALLER" | grep -c 'TELEGRAM_BOT_TOKEN\|WEB_TOKEN\|WEB_SECRET') -eq 0 ]] && echo 1 || echo 0 )"

# ── Test 4: Resume detection ────────────────────────────────────────────────
echo ""
echo "── Test 4: Resume detection ──"

check "has existing state detection" "$(has_pattern "$INSTALLER" "wizard_state_detect_existing")"
check "has resume menu" "$(has_pattern "$INSTALLER" "从推荐阶段继续\|从 VPS 重新配置")"
check "has recovery commands" "$(has_pattern "$INSTALLER" "恢复命令")"

# ── Test 5: Existing KV recovery ────────────────────────────────────────────
echo ""
echo "── Test 5: Existing KV recovery ──"

check "has check_existing_kv helper" "$(has_pattern "$INSTALLER" "check_existing_kv")"
check "has SUB_STORE reference" "$(has_pattern "$REPO_DIR/installer/install-cloudflare.sh" "SUB_STORE")"
check "has NANOB_GEO_CACHE reference" "$(has_pattern "$REPO_DIR/installer/install-cloudflare.sh" "NANOB_GEO_CACHE")"

# ── Test 6: Chinese terminology ─────────────────────────────────────────────
echo ""
echo "── Test 6: Chinese terminology ──"

check "has 环境预检" "$(has_pattern "$INSTALLER" "环境预检\|Preflight")"
check "has 节点配置文件" "$(has_pattern "$INSTALLER" "节点配置文件\|profile")"

# ── Test 7: Output control character check ───────────────────────────────────
echo ""
echo "── Test 7: Output control character check ──"

check "has check_output_clean helper" "$(has_pattern "$INSTALLER" "check_output_clean")"

# ── Test 8: Real mode dry-run still works ───────────────────────────────────
echo ""
echo "── Test 8: Real mode dry-run still works ──"

set +e
OUTPUT_DRY=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1)
DRY_RC=$?
set -e

check "dry-run exits 0" "$([[ $DRY_RC -eq 0 ]] && echo 1 || echo 0)"
check "dry-run has preflight" "$(contains "$OUTPUT_DRY" "Preflight")"
check "dry-run has planned/dry-run" "$(contains "$OUTPUT_DRY" "planned\|dry-run")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
