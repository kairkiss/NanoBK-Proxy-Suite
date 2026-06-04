#!/usr/bin/env bash
# NanoBK Proxy Suite -- v1.8.30 Operation Log Second Command Planning Coverage Test
#
# Checks that docs/validation-v1.8-operation-log-second-command-planning.md
# contains required second-command planning checkpoint content.
#
# Usage:
#   bash tests/unified-cli-operation-log-second-command-planning-v1.8.sh

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
    fail "$label -- expected to contain: $needle"
  fi
}

echo ""
echo "=== Test Suite: v1.8.30 Operation Log Second Command Planning Coverage ==="

doc=$(< "${REPO_DIR}/docs/validation-v1.8-operation-log-second-command-planning.md")

echo ""
echo "--- 1: Document identity ---"

assert_contains "$doc" "Operation Log Second Real Command Planning" "Doc: contains planning title"
assert_contains "$doc" "v1.8.29" "Doc: mentions v1.8.29"
assert_contains "$doc" "planning does not approve implementation" "Doc: implementation not approved"

echo ""
echo "--- 2: Candidate coverage ---"

assert_contains "$doc" "bin/nanobk --version" "Doc: mentions bin/nanobk --version"
assert_contains "$doc" "bin/nanobk --help" "Doc: mentions bin/nanobk --help"
assert_contains "$doc" "status --json" "Doc: mentions status --json"
assert_contains "$doc" "Candidate A" "Doc: contains Candidate A"
assert_contains "$doc" "Candidate B" "Doc: contains Candidate B"

echo ""
echo "--- 3: Findings and recommendation ---"

assert_contains "$doc" "Code inspection findings" "Doc: contains code inspection findings"
assert_contains "$doc" "Recommendation for v1.8.31" "Doc: contains v1.8.31 recommendation"
assert_contains "$doc" "Gates before wrapping --help" "Doc: contains help gates"
assert_contains "$doc" "Gates before wrapping status --json" "Doc: contains status gates"

echo ""
echo "--- 4: Forbidden rollout scope ---"

assert_contains "$doc" "Do NOT wrap VPS deploy" "Doc: forbids VPS deploy"
assert_contains "$doc" "Do NOT wrap Cloudflare deploy" "Doc: forbids Cloudflare deploy"
assert_contains "$doc" "Do NOT wrap real installed status on dirty VPS" "Doc: forbids dirty VPS status"
assert_contains "$doc" "run_cmd" "Doc: mentions run_cmd"
assert_contains "$doc" "run_critical_step" "Doc: mentions run_critical_step"

echo ""
echo "--- 5: Safety statements ---"

assert_contains "$doc" "operation-log can hide output, but must never hide failure" "Doc: never hide failure"
assert_contains "$doc" "planning does not approve implementation" "Doc: planning is not implementation approval"

echo ""
echo "--- 6: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-operation-log-second-command-planning-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' <<< "$filtered_self"; then
  pass "Self-check: uses here-string"
else
  fail "Self-check: uses here-string"
fi

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
  echo "PASSED"
fi
