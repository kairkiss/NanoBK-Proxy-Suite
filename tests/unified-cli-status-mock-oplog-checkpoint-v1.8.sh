#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.44 Status Mock Oplog Prototype Checkpoint Coverage Test
#
# Verifies docs/validation-v1.8-status-mock-oplog-prototype-checkpoint.md
# contains the required checkpoint content.
#
# Does NOT run real bin/nanobk --json status.
# Does NOT run dirty VPS status.
#
# Usage:
#   bash tests/unified-cli-status-mock-oplog-checkpoint-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.44 Status Mock Oplog Checkpoint ==="

DOC="${REPO_DIR}/docs/validation-v1.8-status-mock-oplog-prototype-checkpoint.md"

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

assert_contains "$doc_content" "Status Mock Oplog Prototype Checkpoint" "1a: has checkpoint title"
assert_contains "$doc_content" "v1.8.34" "1b: mentions v1.8.34"
assert_contains "$doc_content" "does not approve dirty VPS status" "1c: no dirty VPS approval"
assert_contains "$doc_content" "does not approve production status wrapper" "1d: no production wrapper approval"
assert_contains "$doc_content" "does not add NANOBK_OPLOG_STATUS_PILOT" "1e: no status pilot"

echo ""
echo "--- 2: Proof chain versions ---"

assert_contains "$doc_content" "v1.8.34" "2a: has v1.8.34"
assert_contains "$doc_content" "v1.8.35" "2b: has v1.8.35"
assert_contains "$doc_content" "v1.8.36" "2c: has v1.8.36"
assert_contains "$doc_content" "v1.8.37" "2d: has v1.8.37"
assert_contains "$doc_content" "v1.8.38" "2e: has v1.8.38"
assert_contains "$doc_content" "v1.8.39" "2f: has v1.8.39"
assert_contains "$doc_content" "v1.8.40" "2g: has v1.8.40"
assert_contains "$doc_content" "v1.8.41" "2h: has v1.8.41"
assert_contains "$doc_content" "v1.8.42" "2i: has v1.8.42"

echo ""
echo "--- 3: Accepted status ---"

assert_contains "$doc_content" "PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE" "3a: has pass verdict"
assert_contains "$doc_content" "default output can hide JSON" "3b: default hidden"
assert_contains "$doc_content" "verbose output can show sanitized JSON" "3c: verbose sanitized"
assert_contains "$doc_content" "log JSON" "3d: log JSON"
assert_contains "$doc_content" "PLAIN/UI=0/CI" "3e: PLAIN boundaries"
assert_contains "$doc_content" "systemctl can be shimmed" "3f: systemctl shim"
assert_contains "$doc_content" "failure propagation" "3g: failure propagation"
assert_contains "$doc_content" "dirty VPS status remains unapproved" "3h: dirty VPS unapproved"

echo ""
echo "--- 4: Security proof ---"

assert_contains "$doc_content" "no TOKEN=" "4a: no TOKEN="
assert_contains "$doc_content" "no SECRET=" "4b: no SECRET="
assert_contains "$doc_content" "no ADMIN_TOKEN" "4c: no ADMIN_TOKEN"
assert_contains "$doc_content" "no SUB_TOKEN" "4d: no SUB_TOKEN"
assert_contains "$doc_content" "no NANOB_TOKEN" "4e: no NANOB_TOKEN"
assert_contains "$doc_content" "no REALITY_PRIVATE_KEY" "4f: no REALITY_PRIVATE_KEY"
assert_contains "$doc_content" "no raw IPv4" "4g: no raw IPv4"
assert_contains "$doc_content" "no workers.dev" "4h: no workers.dev"
assert_contains "$doc_content" "no /etc/nanobk" "4i: no /etc/nanobk"
assert_contains "$doc_content" "no /root/" "4j: no /root/"
assert_contains "$doc_content" "no real HOME" "4k: no real HOME"
assert_contains "$doc_content" "no real repo absolute path" "4l: no real repo path"
assert_contains "$doc_content" "log chmod 600" "4m: log chmod 600"
assert_contains "$doc_content" "failure secret redacted" "4n: failure redacted"

echo ""
echo "--- 5: Testing strategy ---"

assert_contains "$doc_content" "full operation-log pilot suite is not required every cycle" "5a: full suite not required"
assert_contains "$doc_content" "Recommended next step" "5b: has recommendation"
assert_contains "$doc_content" "v1.8.44" "5c: mentions v1.8.44"

echo ""
echo "--- 6: Still forbidden ---"

assert_contains "$doc_content" "Do NOT wrap dirty VPS status" "6a: no dirty VPS wrap"
assert_contains "$doc_content" "Do NOT full-rollout run_cmd" "6b: no run_cmd rollout"
assert_contains "$doc_content" "Do NOT full-rollout run_critical_step" "6c: no run_critical_step rollout"
assert_contains "$doc_content" "NANOBK_OPLOG_STATUS_PILOT" "6d: mentions status pilot"

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
