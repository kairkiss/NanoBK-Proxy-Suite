#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.29 Operation Log Real Pilot Checkpoint Coverage Test
#
# Checks that docs/validation-v1.8-operation-log-real-pilot-checkpoint.md
# contains required acceptance checkpoint content.
#
# Usage:
#   bash tests/unified-cli-operation-log-real-pilot-checkpoint-v1.8.sh

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
echo "=== Test Suite: v1.8.29 Operation Log Real Pilot Checkpoint Coverage ==="

# ── Read the checkpoint doc ─────────────────────────────────────────────

doc=$(cat "${REPO_DIR}/docs/validation-v1.8-operation-log-real-pilot-checkpoint.md")

# ── 1: Document title ──────────────────────────────────────────────────

echo ""
echo "--- 1: Document title ---"

assert_contains "$doc" "Operation Log Real Command Pilot Checkpoint" "Doc: contains title"

# ── 2: Version references ──────────────────────────────────────────────

echo ""
echo "--- 2: Version references ---"

assert_contains "$doc" "v1.8.27" "Doc: mentions v1.8.27"
assert_contains "$doc" "v1.8.28" "Doc: mentions v1.8.28"

# ── 3: What was proved ─────────────────────────────────────────────────

echo ""
echo "--- 3: What was proved ---"

assert_contains "$doc" "bin/nanobk --version" "Doc: mentions bin/nanobk --version"
assert_contains "$doc" "Hidden output" "Doc: mentions Hidden output"
assert_contains "$doc" "Verbose" "Doc: mentions Verbose"
assert_contains "$doc" "Failure propagation" "Doc: mentions Failure propagation"
assert_contains "$doc" "PLAIN" "Doc: mentions PLAIN"
assert_contains "$doc" "UI=0" "Doc: mentions UI=0"
assert_contains "$doc" "CI" "Doc: mentions CI"
assert_contains "$doc" "Full dry-run unaffected" "Doc: mentions full dry-run unaffected"

# ── 4: Acceptance result ───────────────────────────────────────────────

echo ""
echo "--- 4: Acceptance result ---"

assert_contains "$doc" "PASS FOR ONE HARMLESS REAL COMMAND" "Doc: contains PASS result"
assert_contains "$doc" "Not approved for deployment command wrapping" "Doc: not approved for deployment"
assert_contains "$doc" "Real deployment wrapping" "Doc: mentions real deployment wrapping"
assert_contains "$doc" "NOT STARTED" "Doc: NOT STARTED"

# ── 5: What was NOT proved ─────────────────────────────────────────────

echo ""
echo "--- 5: What was NOT proved ---"

assert_contains "$doc" "run_cmd" "Doc: mentions run_cmd"
assert_contains "$doc" "run_critical_step" "Doc: mentions run_critical_step"

# ── 6: Next step ───────────────────────────────────────────────────────

echo ""
echo "--- 6: Next step ---"

assert_contains "$doc" "status --json" "Doc: mentions status --json"
assert_contains "$doc" "--help" "Doc: mentions --help"
assert_contains "$doc" "Do NOT wrap real installed status" "Doc: do NOT wrap real installed status"

# ── 7: Safety rules ────────────────────────────────────────────────────

echo ""
echo "--- 7: Safety rules ---"

assert_contains "$doc" "Do not cat env files" "Doc: do not cat env files"
assert_contains "$doc" "operation-log can hide output, but must never hide failure" "Doc: never hide failure"

# ── 8: Test helper stability ───────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-operation-log-real-pilot-checkpoint-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-operation-log-real-pilot-checkpoint-v1.8.sh"; then
  pass "Self-check: uses here-string"
else
  fail "Self-check: uses here-string"
fi

# ── Results ─────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "FAILED"
  exit 1
else
  echo ""
  echo "ALL PASSED"
  exit 0
fi
