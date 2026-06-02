#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.6 CLI Visual Guide Coverage Test
#
# Checks that docs/validation-v1.8-cli-visual.md contains required
# safety rules, commands, and acceptance criteria.
#
# Usage:
#   bash tests/unified-cli-visual-guide-v1.8.sh

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
echo "=== Test Suite: v1.8.6 CLI Visual Guide Coverage ==="

# ── Read the guide ────────────────────────────────────────────────────────

guide=$(cat "${REPO_DIR}/docs/validation-v1.8-cli-visual.md")

# ── 1: Safe dry-run commands ──────────────────────────────────────────────

echo ""
echo "--- 1: Safe dry-run commands ---"

assert_contains "$guide" "NANOBK_TEST_MOCK=1" "Guide: contains NANOBK_TEST_MOCK"
assert_contains "$guide" "NANOBK_ASSUME_PORTS_FREE=1" "Guide: contains NANOBK_ASSUME_PORTS_FREE"
assert_contains "$guide" "--dry-run" "Guide: contains --dry-run"
assert_contains "$guide" "--defaults" "Guide: contains --defaults"

# ── 2: PLAIN mode ────────────────────────────────────────────────────────

echo ""
echo "--- 2: PLAIN mode ---"

assert_contains "$guide" "NANOBK_PLAIN=1" "Guide: contains NANOBK_PLAIN=1"

# ── 3: NO_EMOJI mode ─────────────────────────────────────────────────────

echo ""
echo "--- 3: NO_EMOJI mode ---"

assert_contains "$guide" "NANOBK_NO_EMOJI=1" "Guide: contains NANOBK_NO_EMOJI=1"

# ── 4: Safety rules ──────────────────────────────────────────────────────

echo ""
echo "--- 4: Safety rules ---"

assert_contains "$guide" "Do NOT input real tokens" "Guide: do not input real tokens"
assert_contains "$guide" "Do NOT \`cat bot/.env\`" "Guide: do not cat bot/.env"
assert_contains "$guide" "Do NOT \`cat web/.env\`" "Guide: do not cat web/.env"
assert_contains "$guide" "Do NOT \`cat .cloudflare.local.env\`" "Guide: do not cat .cloudflare.local.env"
assert_contains "$guide" "Do NOT \`cat .nanob.local.env\`" "Guide: do not cat .nanob.local.env"
assert_contains "$guide" "Do NOT \`cat /root/.nanok-cf-admin.env\`" "Guide: do not cat admin env"
assert_contains "$guide" "Do NOT paste" "Guide: do not paste"

# ── 5: Core semantics ────────────────────────────────────────────────────

echo ""
echo "--- 5: Core semantics ---"

assert_contains "$guide" "planned / dry-run" "Guide: contains planned / dry-run"
assert_contains "$guide" "control plane only" "Guide: contains control plane only"
assert_contains "$guide" "Bot / Web" "Guide: contains Bot / Web"
assert_contains "$guide" "not mislead" "Guide: contains not-mislead concept"
assert_contains "$guide" "status: success" "Guide: mentions status: success as blocked"

# ── 6: PASS / NEEDS POLISH / BLOCKED ─────────────────────────────────────

echo ""
echo "--- 6: Acceptance criteria ---"

assert_contains "$guide" "PASS" "Guide: contains PASS"
assert_contains "$guide" "NEEDS POLISH" "Guide: contains NEEDS POLISH"
assert_contains "$guide" "BLOCKED" "Guide: contains BLOCKED"

# ── 7: Feedback template ─────────────────────────────────────────────────

echo ""
echo "--- 7: Feedback template ---"

assert_contains "$guide" "Feedback Template" "Guide: contains feedback template"
assert_contains "$guide" "Do NOT include tokens" "Guide: feedback says no tokens in screenshots"

# ── 8: No real secrets in guide ───────────────────────────────────────────

echo ""
echo "--- 8: No real secrets in guide ---"

assert_not_contains "$guide" "1234567890:" "Guide: no bot token pattern"
# workers.dev is mentioned in safety rules as "do NOT share real workers.dev" — that's OK

# ── 9: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 9: Test helper stability ---"

# This test file must not have pipe+grep-q patterns
filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-visual-guide-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-visual-guide-v1.8.sh"; then
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
