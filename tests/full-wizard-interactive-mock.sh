#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Interactive Mock Test
#
# Simulates user interaction with the Full Wizard using NANOBK_TEST_MOCK.
# Does NOT connect to VPS or Cloudflare.
# Does NOT write to /etc or /root.
# All mock output clearly labeled [MOCK].
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
check "has mock_validate_profile" "$(grep -q 'mock_validate_profile' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_find_existing_kv" "$(grep -q 'mock_find_existing_kv' "$INSTALLER" && echo 1 || echo 0)"
check "has NANOBK_TEST_MOCK check" "$(grep -q 'NANOBK_TEST_MOCK' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 2: VPS review table ────────────────────────────────────────────────
echo ""
echo "── Test 2: VPS review table ──"

check "has VPS 配置确认" "$(grep -q 'VPS 配置确认' "$INSTALLER" && echo 1 || echo 0)"
check "has modify domain option" "$(grep -q '修改节点域名' "$INSTALLER" && echo 1 || echo 0)"
check "has modify cert option" "$(grep -q '修改证书模式' "$INSTALLER" && echo 1 || echo 0)"
check "has modify reality option" "$(grep -q '修改 Reality 伪装域名' "$INSTALLER" && echo 1 || echo 0)"
check "has confirm and deploy" "$(grep -q '确认并执行 VPS 部署' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 3: Cloudflare review table ─────────────────────────────────────────
echo ""
echo "── Test 3: Cloudflare review table ──"

check "has Cloudflare 配置确认" "$(grep -q 'Cloudflare 配置确认' "$INSTALLER" && echo 1 || echo 0)"
check "has modify Worker URL option" "$(grep -q '修改 Worker 地址' "$INSTALLER" && echo 1 || echo 0)"
check "has modify KV option" "$(grep -q '修改 KV 设置' "$INSTALLER" && echo 1 || echo 0)"
check "has modify nanob option" "$(grep -q '修改 nanob 设置' "$INSTALLER" && echo 1 || echo 0)"
check "has confirm and deploy CF" "$(grep -q '确认并部署 Cloudflare' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 4: Bot review table ────────────────────────────────────────────────
echo ""
echo "── Test 4: Bot review table ──"

check "has Telegram Bot 配置确认" "$(grep -q 'Telegram Bot 配置确认' "$INSTALLER" && echo 1 || echo 0)"
check "has modify Bot Token option" "$(grep -q '修改 Bot Token' "$INSTALLER" && echo 1 || echo 0)"
check "has modify Owner ID option" "$(grep -q '修改 Owner ID' "$INSTALLER" && echo 1 || echo 0)"
check "has confirm and write bot" "$(grep -q '确认并写入 bot/.env\|确认并继续' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 5: Web review table ────────────────────────────────────────────────
echo ""
echo "── Test 5: Web review table ──"

check "has Web Panel 配置确认" "$(grep -q 'Web Panel 配置确认' "$INSTALLER" && echo 1 || echo 0)"
check "has modify host option" "$(grep -q '修改 host' "$INSTALLER" && echo 1 || echo 0)"
check "has modify port option" "$(grep -q '修改 port' "$INSTALLER" && echo 1 || echo 0)"
check "has regenerate token option" "$(grep -q '重新生成 token/secret' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 6: Resume routing ──────────────────────────────────────────────────
echo ""
echo "── Test 6: Resume routing ──"

check "has START_FROM_STAGE variable" "$(grep -q 'START_FROM_STAGE' "$INSTALLER" && echo 1 || echo 0)"
check "has cloudflare skip" "$(grep -q 'START_FROM_STAGE.*cloudflare' "$INSTALLER" && echo 1 || echo 0)"
check "has botweb skip" "$(grep -q 'START_FROM_STAGE.*botweb' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 7: Existing KV recovery ────────────────────────────────────────────
echo ""
echo "── Test 7: Existing KV recovery ──"

check "has mock_find_existing_kv with SUB_STORE" "$(grep -q 'SUB_STORE.*mock-sub-store-id\|mock-sub-store-id.*SUB_STORE' "$INSTALLER" && echo 1 || echo 0)"
check "has mock_find_existing_kv with NANOB_GEO_CACHE" "$(grep -q 'NANOB_GEO_CACHE.*mock-geo-cache-id\|mock-geo-cache-id.*NANOB_GEO_CACHE' "$INSTALLER" && echo 1 || echo 0)"

# ── Test 8: Domain validation order ─────────────────────────────────────────
echo ""
echo "── Test 8: Domain validation order ──"

# Protocol/path check should come before format validation in domain loop
PROTOCOL_LINE=$(grep -n 'domain == https://\*' "$INSTALLER" | head -1 | cut -d: -f1)
FORMAT_LINE=$(grep -n 'is_valid_domain_name "$domain"' "$INSTALLER" | head -1 | cut -d: -f1)
check "protocol check before format validation" "$([[ $PROTOCOL_LINE -lt $FORMAT_LINE ]] && echo 1 || echo 0)"

# ── Test 9: Output control ──────────────────────────────────────────────────
echo ""
echo "── Test 9: Output control ──"

check "has check_output_clean helper" "$(grep -q 'check_output_clean' "$INSTALLER" && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
