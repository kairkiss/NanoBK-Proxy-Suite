#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.44 v1.8 CLI and Operation Log Checkpoint Coverage Test
#
# Verifies docs/validation-v1.8-cli-operation-log-checkpoint.md
# contains the required checkpoint content.
#
# Does NOT run real status.
# Does NOT run dirty VPS.
#
# Usage:
#   bash tests/unified-cli-v1.8-cli-oplog-checkpoint-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.44 v1.8 CLI and Operation Log Checkpoint ==="

DOC="${REPO_DIR}/docs/validation-v1.8-cli-operation-log-checkpoint.md"

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
echo "--- 1: Title and purpose ---"

assert_contains "$doc_content" "v1.8 CLI and Operation Log Checkpoint" "1a: has checkpoint title"
assert_contains "$doc_content" "v1.7.27" "1b: mentions v1.7.27"
assert_contains "$doc_content" "Full Wizard Productization Final" "1c: mentions Full Wizard baseline"

echo ""
echo "--- 2: Verdicts ---"

assert_contains "$doc_content" "PASS FOR STATIC CLI UI PRODUCTIZATION" "2a: CLI UI verdict"
assert_contains "$doc_content" "PASS FOR LOW-RISK OPERATION-LOG GROUNDWORK" "2b: operation-log verdict"
assert_contains "$doc_content" "PASS FOR FOCUSED TEST SPEED STRATEGY" "2c: test speed verdict"
assert_contains "$doc_content" "PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE" "2d: status verdict"
assert_contains "$doc_content" "PASS FOR CLI UI + OPERATION-LOG GROUNDWORK" "2e: overall verdict"

echo ""
echo "--- 3: CLI UI items ---"

assert_contains "$doc_content" "brand banner" "3a: brand banner"
assert_contains "$doc_content" "stage cards" "3b: stage cards"
assert_contains "$doc_content" "compact mode" "3c: compact mode"
assert_contains "$doc_content" "Plain mode" "3d: Plain mode"
assert_contains "$doc_content" "UI=0 mode" "3e: UI=0 mode"

echo ""
echo "--- 4: Operation-log items ---"

assert_contains "$doc_content" "operation-log library pilot" "4a: library pilot"
assert_contains "$doc_content" "hidden output" "4b: hidden output"
assert_contains "$doc_content" "verbose redacted output" "4c: verbose redacted"
assert_contains "$doc_content" "failure propagation" "4d: failure propagation"
assert_contains "$doc_content" "bin/nanobk --version" "4e: version pilot"
assert_contains "$doc_content" "bin/nanobk --help" "4f: help pilot"

echo ""
echo "--- 5: Test speed items ---"

assert_contains "$doc_content" "Tier 0" "5a: Tier 0"
assert_contains "$doc_content" "Tier 1" "5b: Tier 1"
assert_contains "$doc_content" "Tier 2" "5c: Tier 2"
assert_contains "$doc_content" "Tier 3" "5d: Tier 3"

echo ""
echo "--- 6: Status items ---"

assert_contains "$doc_content" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" "6a: admin env hook"
assert_contains "$doc_content" "NANOBK_OPLOG_STATUS_PILOT remains unadded" "6b: status pilot unadded"
assert_contains "$doc_content" "dirty VPS status remains unapproved" "6c: dirty VPS unapproved"
assert_contains "$doc_content" "production status wrapper remains unapproved" "6d: wrapper unapproved"
assert_contains "$doc_content" "run_cmd" "6e: run_cmd"
assert_contains "$doc_content" "run_critical_step" "6f: run_critical_step"

echo ""
echo "--- 7: Next steps ---"

assert_contains "$doc_content" "v1.8.45" "7a: v1.8.45"
assert_contains "$doc_content" "v1.8 Closeout Decision" "7b: closeout decision"
assert_contains "$doc_content" "v1.9" "7c: v1.9"
assert_contains "$doc_content" "Telegram Bot UX polish" "7d: Bot polish"
assert_contains "$doc_content" "Web Panel UX polish" "7e: Web polish"
assert_contains "$doc_content" "not a release tag recommendation" "7f: not a tag"

echo ""
echo "--- 8: Forbidden items ---"

assert_contains "$doc_content" "Do NOT add NANOBK_OPLOG_STATUS_PILOT" "8a: no status pilot"
assert_contains "$doc_content" "Do NOT wrap dirty VPS status" "8b: no dirty VPS"
assert_contains "$doc_content" "Do NOT full-rollout run_cmd" "8c: no run_cmd rollout"
assert_contains "$doc_content" "Do NOT full-rollout run_critical_step" "8d: no run_critical_step rollout"

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
