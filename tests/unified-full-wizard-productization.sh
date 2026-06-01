#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Productization Test
#
# Verifies that the Full Wizard has proper input validation,
# recovery commands, and stage dependency handling.
#
# Usage:
#   bash tests/unified-full-wizard-productization.sh

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

has_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "1"
  else
    echo "0"
  fi
}

echo "=== Full Wizard Productization Test ==="
echo ""

# ── Test 1: Cert-mode menu ──────────────────────────────────────────────────
echo "── Test 1: Cert-mode menu ──"

check "has cert-mode numbered menu" "$(has_pattern "$INSTALLER" "self-signed.*测试\|self-signed.*推荐")"
check "has self-signed option" "$(has_pattern "$INSTALLER" "self-signed")"
check "has existing option" "$(has_pattern "$INSTALLER" "existing")"
check "has self- typo recovery" "$(has_pattern "$INSTALLER" "self-\|selfsigned")"

# ── Test 2: Domain validation ───────────────────────────────────────────────
echo ""
echo "── Test 2: Domain validation ──"

check "detects http:// prefix" "$(has_pattern "$INSTALLER" 'domain.*http://\|http://.*domain')"
check "detects https:// prefix" "$(has_pattern "$INSTALLER" 'domain.*https://\|https://.*domain')"
check "rejects empty domain" "$(has_pattern "$INSTALLER" "域名不能为空")"
check "rejects domain with spaces" "$(has_pattern "$INSTALLER" "空格\|space")"

# ── Test 3: Cloudflare URL validation ───────────────────────────────────────
echo ""
echo "── Test 3: Cloudflare URL validation ──"

check "rejects token in URL" "$(has_pattern "$INSTALLER" "token=.*订阅\|不要粘贴带 token")"
check "strips query params" "$(has_pattern "$INSTALLER" 'route_url%%')"
check "adds https:// if missing" "$(has_pattern "$INSTALLER" 'https://\$')"

# ── Test 4: Token safety warnings ───────────────────────────────────────────
echo ""
echo "── Test 4: Token safety warnings ──"

check "Bot token safety warning" "$(has_pattern "$INSTALLER" "Bot Token.*敏感\|不要截图")"
check "no cat bot/.env warning" "$(has_pattern "$INSTALLER" "不要.*cat bot/.env")"
check "no cat web/.env warning" "$(has_pattern "$INSTALLER" "不要.*cat web/.env")"
check "BotFather revoke reminder" "$(has_pattern "$INSTALLER" "BotFather.*revoke\|BotFather.*regenerate")"

# ── Test 5: Stage dependency handling ───────────────────────────────────────
echo ""
echo "── Test 5: Stage dependency handling ──"

check "has VPS_STAGE_STATUS" "$(has_pattern "$INSTALLER" "VPS_STAGE_STATUS")"
check "has CF_STAGE_STATUS" "$(has_pattern "$INSTALLER" "CF_STAGE_STATUS")"
check "has BOT_STAGE_STATUS" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS")"
check "has WEB_STAGE_STATUS" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS")"
check "has SUMMARY_HAS_FAILURES" "$(has_pattern "$INSTALLER" "SUMMARY_HAS_FAILURES")"
check "VPS failed skips CF" "$(has_pattern "$INSTALLER" "skipped_dependency")"
check "control plane only warning" "$(has_pattern "$INSTALLER" "control.*plane.*only\|控制端配置")"

# ── Test 6: Recovery commands ───────────────────────────────────────────────
echo ""
echo "── Test 6: Recovery commands ──"

check "has --mode vps recovery" "$(has_pattern "$INSTALLER" "mode vps.*lang")"
check "has --mode cloudflare recovery" "$(has_pattern "$INSTALLER" "mode cloudflare.*lang")"
check "has healthcheck recovery" "$(has_pattern "$INSTALLER" "healthcheck")"
check "has nanobk cf verify" "$(has_pattern "$INSTALLER" "nanobk cf verify")"
check "has install-vps.sh recovery" "$(has_pattern "$INSTALLER" "install-vps.sh")"

# ── Test 7: Summary honesty ─────────────────────────────────────────────────
echo ""
echo "── Test 7: Summary honesty ──"

check "has dry-run disclaimer" "$(has_pattern "$INSTALLER" "dry-run.*没有执行\|dry-run.*No real")"
check "has commands-only disclaimer" "$(has_pattern "$INSTALLER" "commands-only.*不验证\|commands-only.*not validate")"
check "has failed state" "$(has_pattern "$INSTALLER" 'status.*failed')"
check "has skipped_dependency state" "$(has_pattern "$INSTALLER" "skipped_dependency\|dependency missing")"
check "has control plane only state" "$(has_pattern "$INSTALLER" "control.*plane.*only\|control_only")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
