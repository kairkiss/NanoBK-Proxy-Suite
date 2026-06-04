#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.45 v1.8 Closeout Decision Coverage Test
#
# Verifies docs/validation-v1.8-closeout-decision.md
# contains the required closeout decision content.
#
# Does NOT run real status.
# Does NOT run dirty VPS.
#
# Usage:
#   bash tests/unified-cli-v1.8-closeout-decision-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.45 v1.8 Closeout Decision ==="

DOC="${REPO_DIR}/docs/validation-v1.8-closeout-decision.md"

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

assert_contains "$doc_content" "v1.8 Closeout Decision" "1a: has title"
assert_contains "$doc_content" "PASS FOR CLI UI + OPERATION-LOG GROUNDWORK" "1b: overall verdict"

echo ""
echo "--- 2: Verdicts ---"

assert_contains "$doc_content" "PASS FOR STATIC CLI UI PRODUCTIZATION" "2a: CLI UI verdict"
assert_contains "$doc_content" "PASS FOR LOW-RISK OPERATION-LOG GROUNDWORK" "2b: oplog verdict"
assert_contains "$doc_content" "PASS FOR FOCUSED TEST SPEED STRATEGY" "2c: speed verdict"
assert_contains "$doc_content" "PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE" "2d: status verdict"

echo ""
echo "--- 3: Closeout decision ---"

assert_contains "$doc_content" "CLOSE v1.8 FEATURE DEVELOPMENT AFTER v1.8.45" "3a: closeout decision"
assert_contains "$doc_content" "Feature development closeout recommendation, not release tag approval" "3b: not tag approval"
assert_contains "$doc_content" "Optional final manual review" "3c: manual review"
assert_contains "$doc_content" "no status: success" "3d: no fake success"
assert_contains "$doc_content" "no TOKEN=" "3e: no TOKEN="
assert_contains "$doc_content" "no SECRET=" "3f: no SECRET="

echo ""
echo "--- 4: Delivered items ---"

assert_contains "$doc_content" "product-like CLI default mode" "4a: default mode"
assert_contains "$doc_content" "compact SSH-friendly mode" "4b: compact mode"
assert_contains "$doc_content" "Plain log/CI mode" "4c: Plain mode"
assert_contains "$doc_content" "UI=0 legacy mode" "4d: UI=0 mode"
assert_contains "$doc_content" "operation-log redaction" "4e: oplog redaction"
assert_contains "$doc_content" "hidden output" "4f: hidden output"
assert_contains "$doc_content" "failure propagation" "4g: failure propagation"

echo ""
echo "--- 5: Not delivered items ---"

assert_contains "$doc_content" "production status wrapper" "5a: no production wrapper"
assert_contains "$doc_content" "dirty VPS status wrapping" "5b: no dirty VPS"
assert_contains "$doc_content" "NANOBK_OPLOG_STATUS_PILOT" "5c: no status pilot"
assert_contains "$doc_content" "full run_cmd rollout" "5d: no run_cmd rollout"
assert_contains "$doc_content" "full run_critical_step rollout" "5e: no run_critical_step rollout"

echo ""
echo "--- 6: v1.9 recommendation ---"

assert_contains "$doc_content" "v1.9" "6a: v1.9"
assert_contains "$doc_content" "Bot/Web Control Plane Productization" "6b: Bot/Web focus"
assert_contains "$doc_content" "Telegram Bot UX polish" "6c: Bot polish"
assert_contains "$doc_content" "Web Panel UX polish" "6d: Web polish"
assert_contains "$doc_content" "Bot/Web must call nanobk CLI" "6e: Bot calls CLI"
assert_contains "$doc_content" "must not directly write configs/systemd/secrets" "6f: no direct writes"

echo ""
echo "--- 7: Closeout result ---"

assert_contains "$doc_content" "READY TO STOP v1.8 FEATURE DEVELOPMENT AFTER v1.8.45" "7a: ready to stop"
assert_contains "$doc_content" "NOT A RELEASE TAG RECOMMENDATION" "7b: not a tag"

echo ""
echo "--- 8: Forbidden items ---"

assert_contains "$doc_content" "Do NOT tag automatically" "8a: no auto tag"
assert_contains "$doc_content" "Do NOT begin v1.9 implementation without explicit approval" "8b: no v1.9 start"

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
