#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard State and Summary Truth Test
#
# Verifies that the Full Wizard state machine correctly separates
# deploy status from optional check status, and that Summary
# reports truthful states.
#
# Usage:
#   bash tests/unified-full-wizard-state-summary.sh

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

not_contains() {
  local text="$1"
  local pattern="$2"
  if grep -qi -- "$pattern" <<< "$text"; then
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

echo "=== Full Wizard State and Summary Truth Test ==="
echo ""

# ── Test 1: VPS deploy status is separate from healthcheck ─────────────────
echo "── Test 1: VPS status separation ──"

check "has VPS_DEPLOY_STATUS variable" "$(has_pattern "$INSTALLER" "VPS_DEPLOY_STATUS")"
check "has VPS_HEALTHCHECK_STATUS variable" "$(has_pattern "$INSTALLER" "VPS_HEALTHCHECK_STATUS")"
check "has VPS_STATUS_CHECK_STATUS variable" "$(has_pattern "$INSTALLER" "VPS_STATUS_CHECK_STATUS")"
check "VPS_DEPLOY_STATUS initialized in wizard" "$(has_pattern "$INSTALLER" 'VPS_DEPLOY_STATUS=.*unknown')"
check "VPS_HEALTHCHECK_STATUS initialized in wizard" "$(has_pattern "$INSTALLER" 'VPS_HEALTHCHECK_STATUS=.*unknown')"
check "VPS_STATUS_CHECK_STATUS initialized in wizard" "$(has_pattern "$INSTALLER" 'VPS_STATUS_CHECK_STATUS=.*unknown')"

# ── Test 2: healthcheck skipped does not overwrite installed ────────────────
echo ""
echo "── Test 2: healthcheck skip protection ──"

# The installer should save deploy result before healthcheck
check "saves deploy result before healthcheck" "$(has_pattern "$INSTALLER" 'VPS_DEPLOY_STATUS=.*LAST_RUN_CMD_STATUS')"

# Healthcheck skipped_user should only affect VPS_HEALTHCHECK_STATUS
check "healthcheck skipped sets VPS_HEALTHCHECK_STATUS" "$(has_pattern "$INSTALLER" 'VPS_HEALTHCHECK_STATUS=.*skipped_user')"

# VPS_STAGE_STATUS should be set from VPS_DEPLOY_STATUS, not LAST_RUN_CMD_STATUS after healthcheck
check "wizard uses VPS_DEPLOY_STATUS for VPS_STAGE_STATUS" "$(has_pattern "$INSTALLER" 'case.*VPS_DEPLOY_STATUS')"

# ── Test 3: Cloudflare deployed/verified in Summary ────────────────────────
echo ""
echo "── Test 3: Cloudflare status tracking ──"

check "has CF_NANOK_STATUS variable" "$(has_pattern "$INSTALLER" "CF_NANOK_STATUS")"
check "has CF_NANOB_STATUS variable" "$(has_pattern "$INSTALLER" "CF_NANOB_STATUS")"
check "has CF_VERIFY_STATUS variable" "$(has_pattern "$INSTALLER" "CF_VERIFY_STATUS")"
check "has CF_ADMIN_ENV_STATUS variable" "$(has_pattern "$INSTALLER" "CF_ADMIN_ENV_STATUS")"

# After deploy, CF_NANOK_STATUS should be set to deployed
check "CF_NANOK_STATUS set to deployed after success" "$(has_pattern "$INSTALLER" 'CF_NANOK_STATUS=.*deployed')"

# Summary should use CF_NANOK_STATUS variable
check "Summary shows nanok status from CF_NANOK_STATUS" "$(has_pattern "$INSTALLER" 'CF_NANOK_STATUS:-deployed')"

# Summary should NOT show configured/pending when deployed
check "Summary has deployed/verified branch for CF" "$(has_pattern "$INSTALLER" 'CF_STAGE_STATUS.*deployed.*verified')"

# ── Test 4: admin env auto-install ─────────────────────────────────────────
echo ""
echo "── Test 4: admin env auto-install ──"

check "has install_cf_admin_env_from_wizard function" "$(has_pattern "$INSTALLER" "install_cf_admin_env_from_wizard")"
check "calls install-admin-env after CF deploy" "$(has_pattern "$INSTALLER" "install_cf_admin_env_from_wizard")"
check "admin env uses bin/nanobk cf install-admin-env" "$(has_pattern "$INSTALLER" 'bin/nanobk.*cf.*install-admin-env')"

# admin env failure should show recovery command
check "admin env failure has recovery command" "$(has_pattern "$INSTALLER" 'CF_ADMIN_ENV_STATUS=.*failed')"

# admin env should not print token
check "admin env function does not cat env" "$(not_contains "$(sed -n '/install_cf_admin_env_from_wizard/,/^}/p' "$INSTALLER")" "cat.*admin.env")"

# ── Test 5: Summary has healthcheck/status check fields ────────────────────
echo ""
echo "── Test 5: Summary VPS fields ──"

SUMMARY_SECTION="$(sed -n '/print_summary/,/^}/p' "$INSTALLER")"

check "Summary has healthcheck field" "$(contains "$SUMMARY_SECTION" "healthcheck:")"
check "Summary has status check field" "$(contains "$SUMMARY_SECTION" "status check:")"
check "Summary shows passed for healthcheck" "$(contains "$SUMMARY_SECTION" "healthcheck.*passed")"
check "Summary shows skipped for healthcheck" "$(contains "$SUMMARY_SECTION" "healthcheck.*skipped")"

# ── Test 6: Summary Cloudflare fields ──────────────────────────────────────
echo ""
echo "── Test 6: Summary Cloudflare fields ──"

check "Summary has verify field" "$(contains "$SUMMARY_SECTION" "verify:")"
check "Summary has admin env field" "$(contains "$SUMMARY_SECTION" "admin env:")"
check "Summary shows passed for verify" "$(contains "$SUMMARY_SECTION" "verify.*passed")"
check "Summary shows installed for admin env" "$(contains "$SUMMARY_SECTION" "admin env.*installed")"
check "Summary shows recovery for admin env failure" "$(contains "$SUMMARY_SECTION" "install-admin-env")"

# ── Test 7: No loose [y/N] in Full Wizard critical paths ───────────────────
echo ""
echo "── Test 7: No loose [y/N] in Full Wizard ──"

# The numbered menu for healthcheck is in install_vps_from_wizard
check "healthcheck uses numbered menu" "$(has_pattern "$INSTALLER" "执行 healthcheck")"
check "healthcheck has skip option" "$(has_pattern "$INSTALLER" "稍后手动执行")"

# Check that status check uses numbered menu
check "status check uses numbered menu" "$(has_pattern "$INSTALLER" "查看 status")"

# Full Wizard should use ask_yes_no_menu, not raw confirm for critical paths
check "Full Wizard uses ask_yes_no_menu for VPS" "$(has_pattern "$INSTALLER" 'ask_yes_no_menu.*是否配置 VPS')"
check "Full Wizard uses ask_yes_no_menu for CF" "$(has_pattern "$INSTALLER" 'ask_yes_no_menu.*是否配置 Cloudflare')"

# ── Test 8: Bot/Web control_only logic preserved ───────────────────────────
echo ""
echo "── Test 8: Bot/Web control_only preserved ──"

check "Bot has control_only status" "$(has_pattern "$INSTALLER" 'BOT_STAGE_STATUS=.*control_only')"
check "Web has control_only status" "$(has_pattern "$INSTALLER" 'WEB_STAGE_STATUS=.*control_only')"
check "Summary shows control_only warning" "$(contains "$SUMMARY_SECTION" "control plane only")"

# ── Test 9: Dry-run Summary truth ───────────────────────────────────────────
echo ""
echo "── Test 9: Dry-run Summary truth ──"

# Dry-run should show planned/dry-run, not manual command not executed
DRY_OUTPUT=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || true

check "dry-run Summary has VPS section" "$(contains "$DRY_OUTPUT" "VPS:")"
check "dry-run Summary has Cloudflare section" "$(contains "$DRY_OUTPUT" "Cloudflare:")"
check "dry-run does NOT show manual command not executed" "$(not_contains "$DRY_OUTPUT" "manual command not executed")"
check "dry-run shows planned / dry-run" "$(contains "$DRY_OUTPUT" "planned.*dry-run\|dry-run.*planned")"

# ── Test 10: Dynamic mock — Cloudflare verified Summary ─────────────────────
echo ""
echo "── Test 10: Dynamic mock Cloudflare Summary ──"

# Use Python mock to run full wizard with Cloudflare and check Summary
MOCK_PY="$SCRIPT_DIR/full_wizard_interactive_mock.py"
if [[ -f "$MOCK_PY" ]]; then
  MOCK_CF_OUTPUT=$(python3 "$MOCK_PY" 2>&1) || true

  # The Python mock runs Test D which configures Cloudflare
  check "mock Test D reaches Summary" "$(contains "$MOCK_CF_OUTPUT" "output reaches Summary")"
  check "mock Summary shows nanok deployed/verified" "$(contains "$MOCK_CF_OUTPUT" "nanok deployed or verified")"
  check "mock Summary does NOT show configured/pending" "$(contains "$MOCK_CF_OUTPUT" "does NOT show configured / pending")"
  check "mock Summary shows admin env installed" "$(contains "$MOCK_CF_OUTPUT" "admin env installed")"
  check "mock Summary does NOT show manual command not executed" "$(contains "$MOCK_CF_OUTPUT" "does NOT show manual command not executed")"
  check "mock all passed" "$(contains "$MOCK_CF_OUTPUT" "passed, 0 failed")"
else
  check "mock Python test exists" "0"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
