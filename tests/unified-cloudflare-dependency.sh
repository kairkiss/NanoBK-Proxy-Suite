#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Dependency Test
#
# Verifies that cloudflare-only mode stops early when profile is missing.
#
# Usage:
#   bash tests/unified-cloudflare-dependency.sh

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

not_contains() {
  local text="$1"
  local pattern="$2"
  if grep -qi -- "$pattern" <<< "$text"; then
    echo "0"
  else
    echo "1"
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

echo "=== Cloudflare Dependency Test ==="
echo ""

# ── Test 1: Static checks ──────────────────────────────────────────────────
echo "── Test 1: Static checks ──"

check "has require_default_profile_for_cloudflare" "$(has_pattern "$INSTALLER" "require_default_profile_for_cloudflare")"
check "has profile not found message" "$(has_pattern "$INSTALLER" "profile.current.json\|profile.*不存在")"
check "has --mode vps recovery" "$(has_pattern "$INSTALLER" "mode vps")"
check "has --mode cloudflare recovery" "$(has_pattern "$INSTALLER" "mode cloudflare")"
check "has install-vps.sh recovery" "$(has_pattern "$INSTALLER" "install-vps.sh")"
check "has skipped_dependency state" "$(has_pattern "$INSTALLER" "skipped_dependency")"

# ── Test 2: Dynamic test with missing profile ──────────────────────────────
echo ""
echo "── Test 2: Dynamic test with missing profile ──"

# Use a non-existent profile path
TMP_PROFILE="/tmp/nanobk-test-no-profile-$$"
OUTPUT=$(NANOBK_DEFAULT_PROFILE_PATH="$TMP_PROFILE" bash "$INSTALLER" --mode cloudflare --dry-run --defaults --lang zh 2>&1) || true

check "contains profile dependency message" "$(contains "$OUTPUT" "需要.*profile\|profile.*需要\|部署需要")"
check "contains --mode vps" "$(contains "$OUTPUT" "mode vps")"
check "contains --mode cloudflare" "$(contains "$OUTPUT" "mode cloudflare")"
check "contains skipped / dependency missing" "$(contains "$OUTPUT" "skipped.*dependency\|dependency.*missing\|skipped_dependency")"
check "does NOT show install-cloudflare preflight" "$(not_contains "$OUTPUT" "install-cloudflare.sh --preflight")"
check "does NOT show validate-profile-only" "$(not_contains "$OUTPUT" "validate-profile-only")"
check "does NOT show deploy-nanob" "$(not_contains "$OUTPUT" "deploy-nanob")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
