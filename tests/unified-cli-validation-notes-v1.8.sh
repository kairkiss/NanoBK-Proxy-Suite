#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.13 CLI Validation Notes Coverage Test
#
# Checks that docs/validation-v1.8-cli-visual.md contains required
# Phase 13 acceptance result, follow-up fixes, and decision point content.
#
# Usage:
#   bash tests/unified-cli-validation-notes-v1.8.sh

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
echo "=== Test Suite: v1.8.13 CLI Validation Notes Coverage ==="

# ── Read the validation guide ─────────────────────────────────────────────

guide=$(cat "${REPO_DIR}/docs/validation-v1.8-cli-visual.md")

# ── 1: Phase 13 acceptance result ─────────────────────────────────────────

echo ""
echo "--- 1: Phase 13 acceptance result ---"

assert_contains "$guide" "Phase 13" "Guide: contains Phase 13"
assert_contains "$guide" "PASS WITH POLISH NOTES" "Guide: contains PASS WITH POLISH NOTES"
assert_contains "$guide" "v1.8.6" "Guide: references v1.8.6"
assert_contains "$guide" "797a90b" "Guide: references commit hash"

# ── 2: v1.8.7 fixes documented ───────────────────────────────────────────

echo ""
echo "--- 2: v1.8.7 fixes ---"

assert_contains "$guide" "v1.8.7" "Guide: contains v1.8.7"
assert_contains "$guide" "mock / dry-run 模式" "Guide: contains mock mode explanation"
assert_contains "$guide" "不会读取真实部署状态" "Guide: contains real-state-skip"
assert_contains "$guide" "planned / dry-run" "Guide: contains planned / dry-run"

# ── 3: v1.8.8 fixes documented ───────────────────────────────────────────

echo ""
echo "--- 3: v1.8.8 fixes ---"

assert_contains "$guide" "v1.8.8" "Guide: contains v1.8.8"
assert_contains "$guide" "skipped (dry-run)" "Guide: contains skipped (dry-run)"

# ── 4: Decision point ────────────────────────────────────────────────────

echo ""
echo "--- 4: Decision point ---"

assert_contains "$guide" "Operation log integration" "Guide: mentions operation log"
assert_contains "$guide" "Telegram Bot menu polish" "Guide: mentions Bot polish"
assert_contains "$guide" "Web Panel" "Guide: mentions Web Panel"
assert_contains "$guide" "CLI visual polish" "Guide: mentions CLI visual polish"

# ── 5: No real secrets ───────────────────────────────────────────────────

echo ""
echo "--- 5: No real secrets ---"

assert_not_contains "$guide" "1234567890:" "Guide: no bot token pattern"
# Safety rules say "Do NOT cat bot/.env" — that's correct, not an instruction to cat
# Just verify the safety rules section exists
assert_contains "$guide" "Do NOT" "Guide: contains safety prohibitions"

# ── 6: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 6: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-validation-notes-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-validation-notes-v1.8.sh"; then
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
