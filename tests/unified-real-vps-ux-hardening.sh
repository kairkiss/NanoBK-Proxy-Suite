#!/usr/bin/env bash
# NanoBK Proxy Suite — Real VPS UX Hardening Test
#
# Tests for placeholder URL rejection, critical step menus,
# headless Wrangler guidance, admin env auto-write, and redacted output.
#
# Usage:
#   bash tests/unified-real-vps-ux-hardening.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_DIR/installer/install.sh"
CF_INSTALLER="$REPO_DIR/installer/install-cloudflare.sh"

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

not_contains() {
  local text="$1"
  local pattern="$2"
  if echo "$text" | grep -qi "$pattern"; then
    echo "0"
  else
    echo "1"
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

echo "=== Real VPS UX Hardening Test ==="
echo ""

# ── Test 1: Placeholder URL rejection ───────────────────────────────────────
echo "── Test 1: Placeholder URL rejection ──"

check "has is_placeholder_value helper" "$(has_pattern "$INSTALLER" "is_placeholder_value")"
check "has is_placeholder_worker_url helper" "$(has_pattern "$INSTALLER" "is_placeholder_worker_url")"
check "rejects example.workers.dev" "$(has_pattern "$INSTALLER" "example.workers.dev")"
check "rejects proxy.example.com" "$(has_pattern "$INSTALLER" "proxy.example.com")"
check "rejects YOUR_DOMAIN" "$(has_pattern "$INSTALLER" "YOUR_DOMAIN\|your_domain")"
check "rejects placeholder" "$(has_pattern "$INSTALLER" "placeholder")"
check "placeholder allowed in dry-run" "$(has_pattern "$INSTALLER" "DRY_RUN.*1\|dry-run")"

# ── Test 2: Critical step menu ──────────────────────────────────────────────
echo ""
echo "── Test 2: Critical step menu ──"

check "has run_critical_step helper" "$(has_pattern "$INSTALLER" "run_critical_step")"
check "critical step default is execute" "$(has_pattern "$INSTALLER" "现在执行.*推荐\|推荐.*现在执行")"
check "critical step has return option" "$(has_pattern "$INSTALLER" "返回修改参数")"
check "critical step has manual option" "$(has_pattern "$INSTALLER" "稍后手动执行")"
check "critical step has exit option" "$(has_pattern "$INSTALLER" "退出")"
check "VPS deploy uses critical step" "$(has_pattern "$INSTALLER" 'run_critical_step.*部署 VPS')"
check "CF preflight uses critical step" "$(has_pattern "$INSTALLER" 'run_critical_step.*Cloudflare preflight\|run_critical_step.*preflight')"

# ── Test 3: Headless Wrangler OAuth guidance ────────────────────────────────
echo ""
echo "── Test 3: Headless Wrangler OAuth guidance ──"

check "has xdg-open detection" "$(has_pattern "$INSTALLER" "xdg-open")"
check "has DISPLAY check" "$(has_pattern "$INSTALLER" "DISPLAY")"
check "has --browser=false guidance" "$(has_pattern "$INSTALLER" "browser=false")"
check "has SSH tunnel 8976 guidance" "$(has_pattern "$INSTALLER" "8976")"
check "has wrangler whoami guidance" "$(has_pattern "$INSTALLER" "wrangler whoami")"

# ── Test 4: Admin env auto-write ────────────────────────────────────────────
echo ""
echo "── Test 4: Admin env auto-write ──"

check "has nanok-cf-admin.env path" "$(has_pattern "$INSTALLER" "nanok-cf-admin.env")"
check "has chmod 600 for admin env" "$(has_pattern "$INSTALLER" "chmod 600.*admin_env\|admin_env.*600\|chmod 600")"
check "has sudo fallback for admin env" "$(has_pattern "$INSTALLER" "sudo.*admin_env\|sudo bash.*admin\|sudo install")"
check "CF installer has ADMIN_CURRENT_URL" "$(has_pattern "$CF_INSTALLER" "ADMIN_CURRENT_URL")"
check "CF installer has ADMIN_UPDATE_URL" "$(has_pattern "$CF_INSTALLER" "ADMIN_UPDATE_URL")"

# ── Test 5: Redacted output ────────────────────────────────────────────────
echo ""
echo "── Test 5: Redacted output ──"

check "CF installer has token hidden" "$(has_pattern "$CF_INSTALLER" "token=<hidden>\|token=.*hidden\|token=\*\*\*")"
check "CF installer has keep private warning" "$(has_pattern "$CF_INSTALLER" "Do not paste\|不要.*paste\|keep private\|KEEP.*PRIVATE")"
check "CF installer has secret file reference" "$(has_pattern "$CF_INSTALLER" "secret file\|local env\|\.cloudflare\.local\.env")"

# ── Test 6: Real mode dry-run still works ───────────────────────────────────
echo ""
echo "── Test 6: Real mode dry-run still works ──"

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
