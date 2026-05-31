#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Preflight Static Test
#
# Static analysis of install.sh for preflight-related content.
# Verifies that the installer contains port detection, Node.js checks,
# wrangler login guidance, python3-venv guidance, and security warnings.
#
# Usage:
#   bash tests/unified-preflight-static.sh

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

echo "=== Unified Preflight Static Test ==="
echo ""

# ── Port detection ──────────────────────────────────────────────────────────
echo "── Port detection ──"

check "has port 443 check" "$(has_pattern "$INSTALLER" "443")"
check "has port 9443 check" "$(has_pattern "$INSTALLER" "9443")"
check "has port 8443 check" "$(has_pattern "$INSTALLER" "8443")"
check "has port 2443 check" "$(has_pattern "$INSTALLER" "2443")"
check "has port 8080 check" "$(has_pattern "$INSTALLER" "8080")"
check "has port detection function" "$(has_pattern "$INSTALLER" "check_port_available\|端口")"
check "has port conflict handler" "$(has_pattern "$INSTALLER" "handle_core_port_conflict\|端口冲突\|occupied")"
check "has re-check option" "$(has_pattern "$INSTALLER" "重新检测\|re-check")"
check "has show process details option" "$(has_pattern "$INSTALLER" "显示占用进程详情\|显示.*占用")"
check "no fake skip HY2" "$(no_pattern "$INSTALLER" "跳过 HY2\|跳过.*HY2\|skip HY2")"
check "no fake skip TUIC" "$(no_pattern "$INSTALLER" "跳过 TUIC\|跳过.*TUIC\|skip TUIC")"
check "no fake skip Reality" "$(no_pattern "$INSTALLER" "跳过 Reality\|跳过.*Reality\|skip Reality")"
check "no fake skip Trojan" "$(no_pattern "$INSTALLER" "跳过 Trojan\|跳过.*Trojan\|skip Trojan")"
check "no skip protocol text" "$(no_pattern "$INSTALLER" "跳过.*继续部署其他\|skip.*continue.*other")"
check "has assumed free (dry-run)" "$(has_pattern "$INSTALLER" "assumed free.*dry-run\|assumed free")"
check "has ss unavailability handling" "$(has_pattern "$INSTALLER" "ss.*不可用\|ss.*not available\|ss not found")"

# ── Node.js and Wrangler ───────────────────────────────────────────────────
echo ""
echo "── Node.js and Wrangler ──"

check "has Node >=22 check" "$(has_pattern "$INSTALLER" "node.*22\|>=22\|nmajor")"
check "has wrangler login guidance" "$(has_pattern "$INSTALLER" "wrangler login")"
check "has SSH tunnel for wrangler" "$(has_pattern "$INSTALLER" "ssh -L 8976\|8976")"
check "has nodesource install hint" "$(has_pattern "$INSTALLER" "nodesource")"

# ── Python and venv ────────────────────────────────────────────────────────
echo ""
echo "── Python and venv ──"

check "has python3-venv check" "$(has_pattern "$INSTALLER" "python3-venv\|python3.*venv\|import venv")"
check "has venv install guidance" "$(has_pattern "$INSTALLER" "apt.*python3-venv\|python3.12-venv")"

# ── Security warnings ──────────────────────────────────────────────────────
echo ""
echo "── Security warnings ──"

check "has 0.0.0.0 warning" "$(has_pattern "$INSTALLER" "0.0.0.0.*暴露\|0.0.0.0.*公网\|0.0.0.0.*warning")"
check "has SSH tunnel hint" "$(has_pattern "$INSTALLER" "ssh -L.*127.0.0.1\|SSH tunnel")"
check "has chmod 600 for bot/.env" "$(has_pattern "$INSTALLER" "chmod 600.*bot/.env\|bot/.env.*600")"
check "has chmod 600 for web/.env" "$(has_pattern "$INSTALLER" "chmod 600.*web/.env\|web/.env.*600")"

# ── No real secrets ─────────────────────────────────────────────────────────
echo ""
echo "── No real secrets ──"

check "no real Telegram bot token" "$(no_pattern "$INSTALLER" "TELEGRAM_BOT_TOKEN=[0-9].*:")"
check "no real SUB_TOKEN" "$(no_pattern "$INSTALLER" "SUB_TOKEN=[A-Za-z0-9]{20}")"
check "no real ADMIN_TOKEN" "$(no_pattern "$INSTALLER" "ADMIN_TOKEN=[A-Za-z0-9]{20}")"
check "no real VPS IP" "$(no_pattern "$INSTALLER" "62.60.250.69")"
check "no source INSTALLER_CONFIG" "$(no_pattern "$INSTALLER" "source.*INSTALLER_CONFIG\|source.*installer.env")"
check "no eval in install.sh" "$(no_pattern "$INSTALLER" "eval ")"

# ── New modes in help ──────────────────────────────────────────────────────
echo ""
echo "── New modes ──"

check "has cli-only mode" "$(has_pattern "$INSTALLER" "cli-only")"
check "has cli-bot mode" "$(has_pattern "$INSTALLER" "cli-bot")"
check "has cli-web mode" "$(has_pattern "$INSTALLER" "cli-web")"
check "has cli-bot-web mode" "$(has_pattern "$INSTALLER" "cli-bot-web")"
check "has Full Recommended" "$(has_pattern "$INSTALLER" "Full Recommended\|full.*推荐")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
