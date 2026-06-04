#!/usr/bin/env bash
# NanoBK Proxy Suite - v1.8.35 Status JSON Mock/Sanitized Planning Coverage Test
#
# Verifies docs/validation-v1.8-status-json-mock-sanitized-planning.md exists
# and contains the required planning checkpoint content.
#
# Usage:
#   bash tests/unified-cli-status-json-mock-sanitized-planning-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.35 Status JSON Mock/Sanitized Planning ==="

DOC="${REPO_DIR}/docs/validation-v1.8-status-json-mock-sanitized-planning.md"

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

echo ""
echo "--- 1: Required title and commands ---"

assert_contains "$doc_content" "Status JSON Mock/Sanitized Planning" "1a: has planning title"
assert_contains "$doc_content" "bin/nanobk --json status" "1b: has correct command"
assert_contains "$doc_content" "bin/nanobk status --json" "1c: has incorrect command warning"

echo ""
echo "--- 2: Required sections ---"

assert_contains "$doc_content" "Current accepted baseline" "2a: has accepted baseline"
assert_contains "$doc_content" "Code inspection findings" "2b: has code inspection findings"
assert_contains "$doc_content" "Sensitive and semi-sensitive output map" "2c: has sensitive output map"
assert_contains "$doc_content" "Existing mock/sanitized support" "2d: has existing mock support"
assert_contains "$doc_content" "Proposed sanitized status strategy" "2e: has proposed strategy"
assert_contains "$doc_content" "JSON validity gates" "2f: has JSON validity gates"
assert_contains "$doc_content" "Dirty VPS validation policy" "2g: has dirty VPS policy"

echo ""
echo "--- 3: Strategy options ---"

assert_contains "$doc_content" "fixture-based status JSON" "3a: has fixture option"
assert_contains "$doc_content" "mock filesystem root" "3b: has mock filesystem option"
assert_contains "$doc_content" "dirty VPS read-only status" "3c: has dirty VPS option"

echo ""
echo "--- 4: Forbidden and safety content ---"

assert_contains "$doc_content" "Do NOT wrap real installed status on dirty VPS yet" "4a: forbids dirty VPS status wrapping"
assert_contains "$doc_content" "Do NOT wrap VPS deploy" "4b: forbids VPS deploy"
assert_contains "$doc_content" "Do NOT wrap Cloudflare deploy" "4c: forbids Cloudflare deploy"
assert_contains "$doc_content" "run_cmd" "4d: mentions run_cmd"
assert_contains "$doc_content" "run_critical_step" "4e: mentions run_critical_step"
assert_contains "$doc_content" "do not paste raw output" "4f: has raw output rule"
assert_contains "$doc_content" "do not cat env files" "4g: has env file rule"

echo ""
echo "--- 5: Next version ---"

assert_contains "$doc_content" "v1.8.35" "5a: has v1.8.35 recommendation"

echo ""
echo "--- 6: v1.8.35 Sanitized Fixture Prototype ---"

assert_contains "$doc_content" "v1.8.35 Sanitized Fixture Prototype" "6a: has section title"
assert_contains "$doc_content" "static sanitized status JSON fixture" "6b: has fixture description"
assert_contains "$doc_content" "does not run real" "6c: does not run real status"
assert_contains "$doc_content" "default mode hides JSON" "6d: default mode hides JSON"
assert_contains "$doc_content" "verbose mode" "6e: verbose mode shows sanitized JSON"
assert_contains "$doc_content" "mock filesystem root design" "6f: next step is mock filesystem"
assert_contains "$doc_content" "not real dirty VPS status" "6g: not real dirty VPS status"

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
