#!/usr/bin/env bash
# NanoBK Proxy Suite - v1.8.44 Status JSON Mock Filesystem Feasibility Coverage Test
#
# Verifies docs/validation-v1.8-status-json-mock-filesystem-feasibility.md
# contains the required feasibility gate content.
#
# Does NOT run real bin/nanobk --json status.
#
# Usage:
#   bash tests/unified-cli-status-json-mock-filesystem-feasibility-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.44 Status JSON Mock Filesystem Feasibility ==="

DOC="${REPO_DIR}/docs/validation-v1.8-status-json-mock-filesystem-feasibility.md"

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
echo "--- 1: Required title and route ---"

assert_contains "$doc_content" "Status JSON Mock Filesystem Feasibility Gate" "1a: has feasibility title"
assert_contains "$doc_content" "NANOBK_REPO_DIR=<tmp_root/repo>" "1b: has NANOBK_REPO_DIR route"
assert_contains "$doc_content" "bin/nanobk --json status --config-dir <tmp_root/config>" "1c: has status command route"
assert_contains "$doc_content" "PATH systemctl shim" "1d: has PATH systemctl shim"

echo ""
echo "--- 2: Code path gates ---"

assert_contains "$doc_content" "parse_global_args" "2a: mentions parse_global_args"
assert_contains "$doc_content" "resolve_repo_dir" "2b: mentions resolve_repo_dir"
assert_contains "$doc_content" "--config-dir" "2c: mentions --config-dir"
assert_contains "$doc_content" "/root/.nanok-cf-admin.env" "2d: mentions root admin env"

echo ""
echo "--- 3: Verdict and required design sections ---"

assert_contains "$doc_content" "Route A feasibility verdict" "3a: has verdict section"
assert_contains "$doc_content" "FEASIBLE ONLY AS PLAN, NOT RUNTIME" "3b: has explicit selected verdict"
assert_contains "$doc_content" "Required mock files" "3c: has required mock files"
assert_contains "$doc_content" "Required runtime guards" "3d: has runtime guards"
assert_contains "$doc_content" "How to prove no real path read" "3e: has proof section"
assert_contains "$doc_content" "v1.8.39" "3f: mentions v1.8.39"

echo ""
echo "--- 4: Forbidden content ---"

assert_contains "$doc_content" "Do NOT add NANOBK_OPLOG_STATUS_PILOT yet" "4a: forbids status pilot"
assert_contains "$doc_content" "Do NOT wrap real installed status on dirty VPS" "4b: forbids dirty VPS status"
assert_contains "$doc_content" 'Do NOT read `/etc/nanobk`' "4c: forbids /etc reads"
assert_contains "$doc_content" 'Do NOT read `/root/.nanok-cf-admin.env`' "4d: forbids root admin env reads"
assert_contains "$doc_content" "run_cmd" "4e: mentions run_cmd"
assert_contains "$doc_content" "run_critical_step" "4f: mentions run_critical_step"
assert_contains "$doc_content" "do not expose raw status JSON in chat" "4g: raw status JSON chat ban"

echo ""
echo "--- 5: v1.8.39 Mock Isolation Hook Planning ---"

assert_contains "$doc_content" "v1.8.39" "5a: mentions v1.8.39"
assert_contains "$doc_content" "Mock Isolation Hook Planning" "5b: has hook planning note"
assert_contains "$doc_content" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" "5c: selected hook"
assert_contains "$doc_content" "no hook implemented yet" "5d: no hook implemented"
assert_contains "$doc_content" "no real status run" "5e: no real status run"
assert_contains "$doc_content" "v1.8.40 admin env path test hook" "5f: next step"

echo ""
echo "--- 6: v1.8.40 admin env path hook note ---"

assert_contains "$doc_content" "v1.8.40 implements the minimal admin env path test hook" "6a: has v1.8.40 implementation note"

echo ""
echo "--- 7: v1.8.41 oplog prototype note ---"

assert_contains "$doc_content" "v1.8.41 proves mock filesystem status output" "7a: has v1.8.41 oplog note"
assert_contains "$doc_content" "operation-log" "7b: mentions operation-log"

echo ""
echo "--- 8: v1.8.42 command path polish ---"

assert_contains "$doc_content" "v1.8.42 polishes operation-log command path" "8a: has v1.8.42 polish note"

echo ""
echo "--- 9: v1.8.43 prototype checkpoint ---"

assert_contains "$doc_content" "v1.8.43 records that v1.8.42 resolved command path leakage" "9a: has v1.8.43 checkpoint note"
assert_contains "$doc_content" "Mock status oplog prototype accepted" "9b: prototype accepted"

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
