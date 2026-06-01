#!/usr/bin/env bash
# NanoBK Proxy Suite — Failure Recovery Test
#
# Verifies that the installer has proper failure recovery mechanisms.
#
# Usage:
#   bash tests/unified-failure-recovery.sh

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

no_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "0"
  else
    echo "1"
  fi
}

echo "=== Failure Recovery Test ==="
echo ""

# ── Test 1: Stage status tracking ───────────────────────────────────────────
echo "── Test 1: Stage status tracking ──"

check "has VPS_STAGE_STATUS" "$(has_pattern "$INSTALLER" "VPS_STAGE_STATUS")"
check "has CF_STAGE_STATUS" "$(has_pattern "$INSTALLER" "CF_STAGE_STATUS")"
check "has BOT_STAGE_STATUS" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS")"
check "has WEB_STAGE_STATUS" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS")"

# ── Test 2: Failure/skip states ─────────────────────────────────────────────
echo ""
echo "── Test 2: Failure/skip states ──"

check "has failed state" "$(has_pattern "$INSTALLER" 'status.*failed\|failed.*status')"
check "has skipped_dependency state" "$(has_pattern "$INSTALLER" 'skipped_dependency\|dependency missing')"
check "has control_only state" "$(has_pattern "$INSTALLER" 'control_only\|control plane only')"

# ── Test 3: Profile dependency check ────────────────────────────────────────
echo ""
echo "── Test 3: Profile dependency check ──"

check "checks profile.current.json before CF" "$(has_pattern "$INSTALLER" 'profile.current.json')"
check "has profile not found message" "$(has_pattern "$INSTALLER" 'profile.*not found\|profile.*不存在')"

# ── Test 4: Recovery commands ───────────────────────────────────────────────
echo ""
echo "── Test 4: Recovery commands ──"

check "has --mode vps recovery" "$(has_pattern "$INSTALLER" 'mode vps')"
check "has --mode cloudflare recovery" "$(has_pattern "$INSTALLER" 'mode cloudflare')"
check "has healthcheck recovery" "$(has_pattern "$INSTALLER" 'healthcheck')"
check "has nanobk cf verify" "$(has_pattern "$INSTALLER" 'nanobk cf verify')"

# ── Test 5: Token safety warnings ───────────────────────────────────────────
echo ""
echo "── Test 5: Token safety warnings ──"

check "has Bot token safety warning" "$(has_pattern "$INSTALLER" 'Bot Token.*敏感\|Bot Token.*sensitive')"
check "has no cat bot/.env warning" "$(has_pattern "$INSTALLER" '不要.*cat bot/.env\|Do NOT.*cat bot/.env')"
check "has no cat web/.env warning" "$(has_pattern "$INSTALLER" '不要.*cat web/.env\|Do NOT.*cat web/.env')"
check "has BotFather revoke reminder" "$(has_pattern "$INSTALLER" 'BotFather.*revoke\|BotFather.*regenerate')"

# ── Test 6: Cert-mode validation ────────────────────────────────────────────
echo ""
echo "── Test 6: Cert-mode validation ──"

check "has cert-mode validation" "$(has_pattern "$INSTALLER" '自签.*建议\|self-signed.*建议\|skip-cert-verify')"
check "has self- typo handling" "$(has_pattern "$INSTALLER" 'self-\|selfsigned')"
check "has cert-mode menu" "$(has_pattern "$INSTALLER" 'self-signed.*测试\|self-signed.*推荐\|证书模式')"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
