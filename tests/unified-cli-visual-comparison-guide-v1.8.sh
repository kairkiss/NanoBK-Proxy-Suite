#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.21 CLI Visual Comparison Guide Coverage Test
#
# Checks that docs/validation-v1.8-cli-visual-comparison.md contains
# required commands, safety rules, and decision matrix content.
#
# Usage:
#   bash tests/unified-cli-visual-comparison-guide-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo "  OK $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

echo ""
echo "=== Test Suite: v1.8.21 CLI Visual Comparison Guide Coverage ==="

# ── Read the guide ────────────────────────────────────────────────────────

guide=$(cat "${REPO_DIR}/docs/validation-v1.8-cli-visual-comparison.md")

# ── 1: Commands ──────────────────────────────────────────────────────────

echo ""
echo "--- 1: Commands ---"

assert_contains "$guide" "NANOBK_COMPACT=1" "Guide: contains NANOBK_COMPACT=1"
assert_contains "$guide" "NANOBK_PLAIN=1" "Guide: contains NANOBK_PLAIN=1"
assert_contains "$guide" "NANOBK_UI=0" "Guide: contains NANOBK_UI=0"
assert_contains "$guide" "NANOBK_TEST_MOCK=1" "Guide: contains NANOBK_TEST_MOCK=1"
assert_contains "$guide" "NANOBK_ASSUME_PORTS_FREE=1" "Guide: contains NANOBK_ASSUME_PORTS_FREE=1"
assert_contains "$guide" "--dry-run" "Guide: contains --dry-run"
assert_contains "$guide" "--defaults" "Guide: contains --defaults"
assert_contains "$guide" "tee /tmp/nanobk-v1.8-default.txt" "Guide: contains tee default output"

# ── 2: Safety grep ───────────────────────────────────────────────────────

echo ""
echo "--- 2: Safety grep ---"

assert_contains "$guide" "TOKEN=" "Guide: safety grep checks TOKEN="
assert_contains "$guide" "status: success" "Guide: safety grep checks status: success"
assert_contains "$guide" "SECRET=" "Guide: safety grep checks SECRET="
assert_contains "$guide" "ADMIN_TOKEN=" "Guide: safety grep checks ADMIN_TOKEN="
assert_contains "$guide" "SUB_TOKEN=" "Guide: safety grep checks SUB_TOKEN="
assert_contains "$guide" "NANOB_TOKEN=" "Guide: safety grep checks NANOB_TOKEN="
assert_contains "$guide" "NANOBK_CF_API_TOKEN" "Guide: safety grep checks CF_API_TOKEN"

# ── 3: Acceptance criteria ───────────────────────────────────────────────

echo ""
echo "--- 3: Acceptance criteria ---"

assert_contains "$guide" "PASS" "Guide: contains PASS"
assert_contains "$guide" "NEEDS POLISH" "Guide: contains NEEDS POLISH"
assert_contains "$guide" "BLOCKED" "Guide: contains BLOCKED"

# ── 4: Next direction ────────────────────────────────────────────────────

echo ""
echo "--- 4: Next direction ---"

assert_contains "$guide" "dynamic progress" "Guide: mentions dynamic progress"
assert_contains "$guide" "operation-log" "Guide: mentions operation-log"
assert_contains "$guide" "Telegram Bot" "Guide: mentions Telegram Bot"
assert_contains "$guide" "Decision Matrix" "Guide: contains decision matrix"

# ── 5: Safety rules ──────────────────────────────────────────────────────

echo ""
echo "--- 5: Safety rules ---"

assert_contains "$guide" "Do NOT input real tokens" "Guide: do not input real tokens"
assert_contains "$guide" "Do NOT \`cat bot/.env\`" "Guide: do not cat bot/.env"
assert_contains "$guide" "Do NOT \`cat web/.env\`" "Guide: do not cat web/.env"
assert_contains "$guide" "Do NOT \`cat .cloudflare.local.env\`" "Guide: do not cat .cloudflare.local.env"
assert_contains "$guide" "Do NOT \`cat .nanob.local.env\`" "Guide: do not cat .nanob.local.env"
assert_contains "$guide" "Do NOT \`cat /root/.nanok-cf-admin.env\`" "Guide: do not cat admin env"

# ── 6: No real secrets ───────────────────────────────────────────────────

echo ""
echo "--- 6: No real secrets ---"

assert_not_contains "$guide" "1234567890:" "Guide: no bot token pattern"

# ── 7: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 7: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-visual-comparison-guide-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-visual-comparison-guide-v1.8.sh"; then
  pass "Self-check: uses here-string"
else
  fail "Self-check: must use here-string"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
