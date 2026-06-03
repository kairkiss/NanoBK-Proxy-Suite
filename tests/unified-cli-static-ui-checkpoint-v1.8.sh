#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.25 CLI Static UI Checkpoint Coverage Test
#
# Checks that docs/validation-v1.8-cli-static-ui-checkpoint.md contains
# required acceptance records, fix history, and decision matrix.
#
# Usage:
#   bash tests/unified-cli-static-ui-checkpoint-v1.8.sh

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

echo ""
echo "=== Test Suite: v1.8.25 CLI Static UI Checkpoint Coverage ==="

# ── Read the checkpoint ───────────────────────────────────────────────────

doc=$(cat "${REPO_DIR}/docs/validation-v1.8-cli-static-ui-checkpoint.md")

# ── 1: Title and purpose ─────────────────────────────────────────────────

echo ""
echo "--- 1: Title and purpose ---"

assert_contains "$doc" "CLI Static UI Acceptance Checkpoint" "Doc: contains title"
assert_contains "$doc" "not a real deployment" "Doc: clarifies not real deployment"

# ── 2: Fix history ───────────────────────────────────────────────────────

echo ""
echo "--- 2: Fix history ---"

assert_contains "$doc" "v1.8.14" "Doc: contains v1.8.14"
assert_contains "$doc" "BLOCKED" "Doc: contains BLOCKED"
assert_contains "$doc" "Plain mode not plain" "Doc: records Plain mode issue"
assert_contains "$doc" "v1.8.15" "Doc: contains v1.8.15"
assert_contains "$doc" "v1.8.16" "Doc: contains v1.8.16"
assert_contains "$doc" "v1.8.17" "Doc: contains v1.8.17"
assert_contains "$doc" "v1.8.18" "Doc: contains v1.8.18"

# ── 3: Final four-mode status ────────────────────────────────────────────

echo ""
echo "--- 3: Final four-mode status ---"

assert_contains "$doc" "Default" "Doc: contains Default"
assert_contains "$doc" "Compact" "Doc: contains Compact"
assert_contains "$doc" "Plain" "Doc: contains Plain"
assert_contains "$doc" "UI=0" "Doc: contains UI=0"
assert_contains "$doc" "PASS" "Doc: contains PASS"

# ── 4: Next decision ─────────────────────────────────────────────────────

echo ""
echo "--- 4: Next decision ---"

assert_contains "$doc" "operation-log" "Doc: mentions operation-log"
assert_contains "$doc" "Dynamic Progress" "Doc: mentions Dynamic Progress"
assert_contains "$doc" "Mascot" "Doc: mentions Mascot"
assert_contains "$doc" "Telegram Bot" "Doc: mentions Telegram Bot"
assert_contains "$doc" "Web Panel" "Doc: mentions Web Panel"

# ── 5: Safety ────────────────────────────────────────────────────────────

echo ""
echo "--- 5: Safety ---"

assert_contains "$doc" "TOKEN=" "Doc: mentions TOKEN="
assert_contains "$doc" "status: success" "Doc: mentions status: success"
assert_contains "$doc" "dry-run" "Doc: mentions dry-run"
assert_contains "$doc" "planned / dry-run" "Doc: contains planned / dry-run"
assert_contains "$doc" "real deployment" "Doc: mentions real deployment"
assert_contains "$doc" "control plane" "Doc: mentions control plane"

# ── 6: Baseline ──────────────────────────────────────────────────────────

echo ""
echo "--- 6: Baseline ---"

assert_contains "$doc" "v1.7.27" "Doc: references v1.7.27 baseline"
assert_contains "$doc" "not intentionally changed" "Doc: logic not intentionally changed"

# ── 7: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 7: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-static-ui-checkpoint-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-static-ui-checkpoint-v1.8.sh"; then
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
