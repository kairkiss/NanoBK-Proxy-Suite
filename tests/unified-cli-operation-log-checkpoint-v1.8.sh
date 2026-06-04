#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.29 Operation Log Checkpoint Coverage Test
#
# Checks that docs/validation-v1.8-operation-log-checkpoint.md contains
# required acceptance checkpoint content.
#
# Usage:
#   bash tests/unified-cli-operation-log-checkpoint-v1.8.sh

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
echo "=== Test Suite: v1.8.29 Operation Log Checkpoint Coverage ==="

# ── Read the checkpoint doc ─────────────────────────────────────────────

doc=$(cat "${REPO_DIR}/docs/validation-v1.8-operation-log-checkpoint.md")

# ── 1: Document title ──────────────────────────────────────────────────

echo ""
echo "--- 1: Document title ---"

assert_contains "$doc" "Operation Log Pilot Acceptance Checkpoint" "Doc: contains title"

# ── 2: Version timeline ────────────────────────────────────────────────

echo ""
echo "--- 2: Version timeline ---"

assert_contains "$doc" "v1.8.20" "Doc: mentions v1.8.20"
assert_contains "$doc" "v1.8.21" "Doc: mentions v1.8.21"
assert_contains "$doc" "v1.8.22" "Doc: mentions v1.8.22"
assert_contains "$doc" "v1.8.23" "Doc: mentions v1.8.23"
assert_contains "$doc" "v1.8.24" "Doc: mentions v1.8.24"
assert_contains "$doc" "v1.8.25" "Doc: mentions v1.8.25"

# ── 3: Acceptance result ───────────────────────────────────────────────

echo ""
echo "--- 3: Acceptance result ---"

assert_contains "$doc" "PASS FOR TEST-MODE PILOT" "Doc: contains PASS FOR TEST-MODE PILOT"
assert_contains "$doc" "Not approved for full deployment rollout" "Doc: not approved for full rollout"

# ── 4: What was proved ─────────────────────────────────────────────────

echo ""
echo "--- 4: What was proved ---"

assert_contains "$doc" "failure propagation" "Doc: mentions failure propagation"
assert_contains "$doc" "hidden output" "Doc: mentions hidden output"
assert_contains "$doc" "verbose" "Doc: mentions verbose"
assert_contains "$doc" "PLAIN" "Doc: mentions PLAIN"
assert_contains "$doc" "UI=0" "Doc: mentions UI=0"
assert_contains "$doc" "CI" "Doc: mentions CI"
assert_contains "$doc" "chmod 600" "Doc: mentions chmod 600"
assert_contains "$doc" "no raw secrets" "Doc: mentions no raw secrets"
assert_contains "$doc" "full dry-run unaffected" "Doc: mentions full dry-run unaffected"

# ── 5: What was NOT proved ─────────────────────────────────────────────

echo ""
echo "--- 5: What was NOT proved ---"

assert_contains "$doc" "run_cmd" "Doc: mentions run_cmd"
assert_contains "$doc" "run_critical_step" "Doc: mentions run_critical_step"

# ── 6: Next step ───────────────────────────────────────────────────────

echo ""
echo "--- 6: Next step ---"

assert_contains "$doc" "v1.8.29" "Doc: mentions v1.8.29"
assert_contains "$doc" "One Low-risk Real Command Pilot" "Doc: mentions One Low-risk Real Command Pilot"
assert_contains "$doc" "bin/nanobk --version" "Doc: mentions bin/nanobk --version"

# ── 7: Safety rules ────────────────────────────────────────────────────

echo ""
echo "--- 7: Safety rules ---"

assert_contains "$doc" "Do not wrap VPS deploy" "Doc: do not wrap VPS deploy"
assert_contains "$doc" "Do not wrap Cloudflare deploy" "Doc: do not wrap Cloudflare deploy"
assert_contains "$doc" "operation-log can hide output, but must never hide failure" "Doc: never hide failure"

# ── 8: Test helper stability ───────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

# Self-check: no pipe+grep-q pattern (except in self-check and assert helpers)
filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-operation-log-checkpoint-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qP 'grep -q.*<<<' "${SCRIPT_DIR}/unified-cli-operation-log-checkpoint-v1.8.sh" 2>/dev/null; then
  pass "Self-check: uses here-string"
else
  # grep -P may not be available; fall back to checking assert_contains uses <<<
  if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-operation-log-checkpoint-v1.8.sh"; then
    pass "Self-check: uses here-string"
  else
    fail "Self-check: uses here-string"
  fi
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
