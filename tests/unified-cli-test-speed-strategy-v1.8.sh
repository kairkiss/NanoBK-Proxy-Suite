#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.37 Test Speed Strategy Coverage Test
#
# Verifies docs/validation-v1.8-test-speed-strategy.md exists and
# contains required sections.
#
# Usage:
#   bash tests/unified-cli-test-speed-strategy-v1.8.sh

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
echo "=== Test Suite: v1.8.37 Test Speed Strategy Coverage ==="

DOC="${REPO_DIR}/docs/validation-v1.8-test-speed-strategy.md"

if [[ ! -f "$DOC" ]]; then
  fail "Document not found: $DOC"
  echo ""
  echo "=== Results ==="
  echo "  Passed: ${PASS}"
  echo "  Failed: ${FAIL}"
  echo ""
  echo "FAILED"
  exit 1
fi

doc_content=$(cat "$DOC")

# ── 1: Required sections ───────────────────────────────────────────────

echo ""
echo "--- 1: Required sections ---"

assert_contains "$doc_content" "## 1. Purpose" "1a: has Purpose section"
assert_contains "$doc_content" "## 2. Why v1.8.31 was slow" "1b: has Why slow section"
assert_contains "$doc_content" "## 3. Fast test strategy" "1c: has Fast test strategy"
assert_contains "$doc_content" "## 4. Test tiers" "1d: has Test tiers"
assert_contains "$doc_content" "## 5. When to run full regression" "1e: has When full regression"
assert_contains "$doc_content" "## 6. When real VPS/CF tests are needed" "1f: has When real VPS/CF"
assert_contains "$doc_content" "## 7. Policy for future agents" "1g: has Policy for agents"

# ── 2: Tier definitions ────────────────────────────────────────────────

echo ""
echo "--- 2: Tier definitions ---"

assert_contains "$doc_content" "Tier 0" "2a: has Tier 0"
assert_contains "$doc_content" "Tier 1" "2b: has Tier 1"
assert_contains "$doc_content" "Tier 2" "2c: has Tier 2"
assert_contains "$doc_content" "Tier 3" "2d: has Tier 3"

# ── 3: Key technical content ───────────────────────────────────────────

echo ""
echo "--- 3: Key technical content ---"

assert_contains "$doc_content" "NANOBK_TEST_OVERRIDE_SCRIPT" "3a: mentions override script"
assert_contains "$doc_content" "All safe tests" "3b: mentions All safe tests"
assert_contains "$doc_content" "run_operation_log_real_command_pilot" "3c: mentions real command pilot"
assert_contains "$doc_content" "run_operation_log_help_command_pilot" "3d: mentions help command pilot"
assert_contains "$doc_content" "FAST PASS" "3e: mentions FAST PASS"
assert_contains "$doc_content" "operation-log can hide output, but must never hide failure" "3f: has safety rule"

# ── 3b: v1.8.33 no-trigger polish ──────────────────────────────────────

echo ""
echo "--- 3b: v1.8.33 no-trigger polish ---"

assert_contains "$doc_content" "v1.8.33" "3g: mentions v1.8.33"
assert_contains "$doc_content" "no-trigger" "3h: mentions no-trigger"
assert_contains "$doc_content" "avoid All safe tests" "3i: mentions avoid All safe tests"
assert_contains "$doc_content" "Full regression remains available" "3j: full regression remains available"
assert_contains "$doc_content" "full regression is not run by default" "3k: full regression not run by default"

# ── 4: Safety rules ────────────────────────────────────────────────────

echo ""
echo "--- 4: Safety rules ---"

assert_contains "$doc_content" "Do not run full regression by default" "4a: don't run full by default"
assert_contains "$doc_content" "first run focused tests" "4b: first run focused"
assert_contains "$doc_content" "if full regression is skipped, say so honestly" "4c: honest skip reporting"

# ── 5: VPS/CF test guidance ────────────────────────────────────────────

echo ""
echo "--- 5: VPS/CF guidance ---"

assert_contains "$doc_content" "Not needed for" "5a: has Not needed list"
assert_contains "$doc_content" "Clean VPS needed for" "5b: has Clean VPS list"
assert_contains "$doc_content" "Cloudflare real test needed for" "5c: has CF real test list"

# ── Summary ─────────────────────────────────────────────────────────────

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
