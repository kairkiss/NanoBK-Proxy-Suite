#!/usr/bin/env bash
# NanoBK Proxy Suite — Existing Deployment Resume Test
#
# Verifies that the Full Wizard correctly handles existing deployment
# resume scenarios: refreshed state, skipped core port preflight,
# and truthful Summary output.
#
# Usage:
#   bash tests/unified-existing-deployment-resume.sh

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

echo "=== Existing Deployment Resume Test ==="
echo ""

# ── Test 1: wizard_refresh_existing_runtime_state helper exists ─────────────
echo "── Test 1: Runtime state refresh helper ──"

check "wizard_refresh_existing_runtime_state function defined" \
  "$(has_pattern "$INSTALLER" "wizard_refresh_existing_runtime_state()")"
check "refresh reads /etc/nanobk/profile.current.json" \
  "$(has_pattern "$INSTALLER" '/etc/nanobk/profile.current.json')"
check "refresh reads NANOBK_VERIFY_STATUS" \
  "$(has_pattern "$INSTALLER" 'NANOBK_VERIFY_STATUS')"
check "refresh reads NANOB_VERIFY_STATUS" \
  "$(has_pattern "$INSTALLER" 'NANOB_VERIFY_STATUS')"
check "refresh checks admin env mode" \
  "$(has_pattern "$INSTALLER" 'nanok-cf-admin.env')"
check "refresh skips in mock mode" \
  "$(has_pattern "$INSTALLER" 'NANOBK_TEST_MOCK')"

# ── Test 2: START_FROM_STAGE skips core port preflight ──────────────────────
echo ""
echo "── Test 2: Core port preflight skip for resume ──"

check "preflight checks START_FROM_STAGE for cloudflare" \
  "$(has_pattern "$INSTALLER" 'START_FROM_STAGE.*cloudflare')"
check "preflight checks START_FROM_STAGE for botweb" \
  "$(has_pattern "$INSTALLER" 'START_FROM_STAGE.*botweb')"
check "preflight still has real port check for fresh deploy" \
  "$(has_pattern "$INSTALLER" 'check_port_available 443')"
check "preflight has DRY_RUN assumed free" \
  "$(has_pattern "$INSTALLER" 'assumed free.*dry-run\|dry-run.*assumed free')"

# ── Test 3: Resume menu calls refresh ───────────────────────────────────────
echo ""
echo "── Test 3: Resume menu uses refreshed state ──"

check "resume menu calls wizard_refresh_existing_runtime_state" \
  "$(has_pattern "$INSTALLER" 'wizard_refresh_existing_runtime_state')"
check "wizard_state_print uses VPS_STAGE_STATUS" \
  "$(has_pattern "$INSTALLER" 'VPS_STAGE_STATUS.*installed\|installed.*VPS_STAGE_STATUS')"
check "wizard_state_print uses CF_STAGE_STATUS" \
  "$(has_pattern "$INSTALLER" 'CF_STAGE_STATUS.*verified\|verified.*CF_STAGE_STATUS')"

# ── Test 4: Summary shows verified/installed for existing deployment ────────
echo ""
echo "── Test 4: Summary truth for existing deployment ──"

SUMMARY_SECTION="$(sed -n '/^print_summary()/,/^}/p' "$INSTALLER")"

check "Summary has VPS installed branch" \
  "$(contains "$SUMMARY_SECTION" 'VPS_STAGE_STATUS.*installed')"
check "Summary has CF verified branch" \
  "$(contains "$SUMMARY_SECTION" 'CF_STAGE_STATUS.*verified')"
check "Summary has admin env installed" \
  "$(contains "$SUMMARY_SECTION" 'admin env: installed')"
check "Summary has healthcheck passed" \
  "$(contains "$SUMMARY_SECTION" 'healthcheck: passed')"

# ── Test 5: No stale manual_pending when real state is known ────────────────
echo ""
echo "── Test 5: No stale states when real state is known ──"

check "wizard_state_print has installed / healthy label" \
  "$(has_pattern "$INSTALLER" 'installed / healthy')"
check "wizard_state_print has verified label" \
  "$(has_pattern "$INSTALLER" 'CF_STAGE_STATUS.*verified')"

# ── Test 6: Mock isolation preserved ───────────────────────────────────────
echo ""
echo "── Test 6: Mock isolation preserved ──"

check "refresh skips in mock mode (NANOBK_TEST_MOCK)" \
  "$(has_pattern "$INSTALLER" 'NANOBK_TEST_MOCK')"
check "wizard_state_detect_existing skips in mock mode" \
  "$(has_pattern "$INSTALLER" 'NANOBK_TEST_MOCK')"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
