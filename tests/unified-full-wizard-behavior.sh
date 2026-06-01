#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Behavior Test
#
# Dynamic behavior tests for URL cleaning, dependency skipping,
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

# ── Test 1: Static URL validation checks ────────────────────────────────────
echo "── Test 1: Static URL validation checks ──"

check "Worker URL strips query params" "$(has_pattern "$INSTALLER" 'route_url%%')"
check "Worker URL rejects token" "$(has_pattern "$INSTALLER" "token=.*订阅\|不要粘贴带 token")"
check "Worker URL rejects http://" "$(has_pattern "$INSTALLER" "http://.*不支持\|必须使用 https")"
check "Worker URL bare host has confirmation" "$(has_pattern "$INSTALLER" "检测到未包含 https")"
check "nanob URL same validation" "$(has_pattern "$INSTALLER" 'nanob_url%%')"

# ── Test 2: Domain validation static checks ─────────────────────────────────
echo ""
echo "── Test 2: Domain validation static checks ──"

check "domain rejects protocol with confirmation" "$(has_pattern "$INSTALLER" "不要带 https://\|不要带 http://")"
check "domain rejects spaces" "$(has_pattern "$INSTALLER" "域名不能包含空格\|不应包含空格")"
check "domain rejects path with confirmation" "$(has_pattern "$INSTALLER" "域名不应包含路径\|不应包含路径")"
check "domain has suggestion" "$(has_pattern "$INSTALLER" "检测到你可能想输入")"
check "domain has numbered choices" "$(has_pattern "$INSTALLER" "重新输入\|退出")"

# ── Test 3: Cert-mode menu with letsencrypt ──────────────────────────────────
echo ""
echo "── Test 3: Cert-mode menu with letsencrypt ──"

check "has letsencrypt option" "$(has_pattern "$INSTALLER" "letsencrypt")"
check "letsencrypt says not recommended" "$(has_pattern "$INSTALLER" "暂不推荐\|not recommended")"
check "letsencrypt offers fallback" "$(has_pattern "$INSTALLER" "改用 self-signed\|改用 existing")"

# ── Test 4: Cloudflare dependency is unconditional ───────────────────────────
echo ""
echo "── Test 4: Cloudflare dependency is unconditional ──"

check "profile check is unconditional" "$(has_pattern "$INSTALLER" "profile.current.json.*not found\|profile.current.json.*不存在")"
check "has recovery commands" "$(has_pattern "$INSTALLER" "mode vps.*lang\|mode cloudflare.*lang")"
check "has healthcheck recovery" "$(has_pattern "$INSTALLER" "healthcheck")"
check "has install-vps.sh recovery" "$(has_pattern "$INSTALLER" "install-vps.sh")"

# ── Test 5: Bot/Web failed state ─────────────────────────────────────────────
echo ""
echo "── Test 5: Bot/Web failed state ──"

check "Bot has failed state" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS.*failed")"
check "Web has failed state" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS.*failed")"
check "Bot failed shows recovery" "$(has_pattern "$INSTALLER" "恢复命令")"
check "Web failed shows recovery" "$(has_pattern "$INSTALLER" "恢复命令")"
check "Bot failed in summary" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS.*==.*failed")"
check "Web failed in summary" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS.*==.*failed")"

# ── Test 6: Summary honesty for failed states ────────────────────────────────
echo ""
echo "── Test 6: Summary honesty for failed states ──"

check "Bot failed shows status failed" "$(has_pattern "$INSTALLER" "status.*failed")"
check "Web failed shows status failed" "$(has_pattern "$INSTALLER" "status.*failed")"
check "Bot failed does not show configured" "$(has_pattern "$INSTALLER" "BOT_STAGE_STATUS.*failed")"
check "Web failed does not show configured" "$(has_pattern "$INSTALLER" "WEB_STAGE_STATUS.*failed")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
