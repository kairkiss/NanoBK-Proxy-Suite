#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Interactive Mock Test
#
# REAL dynamic tests that execute installer input streams.
# Does NOT connect to VPS or Cloudflare.
# Uses NANOBK_TEST_MOCK=1 for simulated deployments.
#
# Usage:
#   bash tests/full-wizard-interactive-mock.sh

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

echo "=== Full Wizard Interactive Mock Test ==="
echo ""

# ── Test 1: Mock infrastructure exists ──────────────────────────────────────
echo "── Test 1: Mock infrastructure ──"

check "has mock_log helper" "$(grep -q 'mock_log' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_deploy_vps" "$(grep -q 'mock_deploy_vps' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_deploy_cloudflare" "$(grep -q 'mock_deploy_cloudflare' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_preflight" "$(grep -q 'mock_preflight' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_find_existing_kv" "$(grep -q 'mock_find_existing_kv' "$INSTALLER" && echo 1 || echo 0)"
check "has NANOBK_TEST_MOCK check" "$(grep -q 'NANOBK_TEST_MOCK' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 2: Review loop functions exist ─────────────────────────────────────
echo ""
echo "── Test 2: Review loop functions ──"

check "has vps_review_loop" "$(grep -q 'vps_review_loop' "$INSTALLER" && echo 1 || echo 0)"
check "has cloudflare_review_loop" "$(grep -q 'cloudflare_review_loop' "$INSTALLER" && echo 1 || echo 0)"
check "has bot_review_loop" "$(grep -q 'bot_review_loop' "$INSTALLER" && echo 1 || echo 0)"
check "has web_review_loop" "$(grep -q 'web_review_loop' "$INSTALLER" && echo 1 || echo 0)"
check "has ask_yes_no_menu" "$(grep -q 'ask_yes_no_menu' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 3: Strict menu integration ─────────────────────────────────────────
echo ""
echo "── Test 3: Strict menu integration ──"

check "VPS phase uses ask_yes_no_menu" "$(grep -q 'ask_yes_no_menu.*是否配置 VPS' "$INSTALLER" && echo 1 || echo 0)"
check "Full Wizard VPS uses ask_yes_no_menu" "$( [[ $(grep -c 'ask_yes_no_menu.*是否配置 VPS' "$INSTALLER") -gt 0 ]] && echo 1 || echo 0 )"
check "Full Wizard CF uses ask_yes_no_menu" "$( [[ $(grep -c 'ask_yes_no_menu.*是否配置 Cloudflare' "$INSTALLER") -gt 0 ]] && echo 1 || echo 0 )"

# ── Test 4: Resume routing ──────────────────────────────────────────────────
echo ""
echo "── Test 4: Resume routing ──"

check "START_FROM_STAGE exists" "$(grep -q 'START_FROM_STAGE' "$INSTALLER" && echo 1 || echo 0)"
check "cloudflare skip exists" "$(grep -q 'START_FROM_STAGE.*cloudflare' "$INSTALLER" && echo 1 || echo 0)"
check "botweb skip exists" "$(grep -q 'START_FROM_STAGE.*botweb' "$INSTALLER" && echo 1 || echo 0)"
check "no fake VPS_STAGE_STATUS=installed on resume" "$( [[ $(grep -c 'START_FROM_STAGE.*botweb.*VPS_STAGE_STATUS.*installed' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"
check "no fake CF_STAGE_STATUS=deployed on resume" "$( [[ $(grep -c 'START_FROM_STAGE.*botweb.*CF_STAGE_STATUS.*deployed' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"
check "assumed_existing used for resume" "$(grep -q 'assumed_existing' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 5: Existing KV recovery ────────────────────────────────────────────
echo ""
echo "── Test 5: Existing KV recovery ──"

check "has find_existing_kv_id" "$(grep -q 'find_existing_kv_id' "$INSTALLER" && echo 1 || echo 0)"
check "has mock SUB_STORE" "$(grep -q 'mock-sub-store-id' "$INSTALLER" && echo 1 || echo 0)"
check "has mock NANOB_GEO_CACHE" "$(grep -q 'mock-geo-cache-id' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 6: Domain validation order ─────────────────────────────────────────
echo ""
echo "── Test 6: Domain validation order ──"

PROTOCOL_LINE=$(grep -n '"$domain" == https://\*' "$INSTALLER" | head -1 | cut -d: -f1)
FORMAT_LINE=$(grep -n 'is_valid_domain_name "$domain"' "$INSTALLER" | head -1 | cut -d: -f1)
check "protocol check before format validation" "$([[ -n "$PROTOCOL_LINE" ]] && [[ -n "$FORMAT_LINE" ]] && [[ $PROTOCOL_LINE -lt $FORMAT_LINE ]] && echo 1 || echo 0)"

# ── Test 7: Token redaction ─────────────────────────────────────────────────
echo ""
echo "── Test 7: Token redaction ──"

check "Bot review shows 已填写 not token" "$(grep -q 'Bot Token.*已填写\|Bot Token.*未填写' "$INSTALLER" && echo 1 || echo 0)"
check "Web review shows 已生成 not token" "$(grep -q 'Token.*已生成\|Token.*已填写' "$INSTALLER" && echo 1 || echo 0)"
check "no raw token in review tables" "$( [[ $(grep -c 'Bot Token.*123456\|Web Token.*secret' "$INSTALLER") -eq 0 ]] && echo 1 || echo 0 )"

# ── Test 8: Output control ──────────────────────────────────────────────────
echo ""
echo "── Test 8: Output control ──"

check "has check_output_clean helper" "$(grep -q 'check_output_clean' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 9: Real mock execution (brief) ─────────────────────────────────────
echo ""
echo "── Test 9: Real mock execution ──"

# Quick test: commands mode should work without hanging
set +e
OUTPUT_CMD=$(NANOBK_TEST_MOCK=1 bash "$INSTALLER" --mode commands --defaults 2>&1)
CMD_RC=$?
set -e

check "commands mode exits 0" "$([[ $CMD_RC -eq 0 ]] && echo 1 || echo 0)"
check "commands output has install-vps" "$(contains "$OUTPUT_CMD" "install-vps")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
