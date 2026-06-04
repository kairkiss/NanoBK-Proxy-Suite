#!/usr/bin/env bash
# NanoBK Proxy Suite - v1.8.44 Status JSON Mock Isolation Hook Planning Coverage Test
#
# Verifies docs/validation-v1.8-status-json-mock-isolation-hook-planning.md
# contains the required hook planning checkpoint content.
#
# Does NOT run real bin/nanobk --json status.
#
# Usage:
#   bash tests/unified-cli-status-json-mock-isolation-hook-planning-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.44 Status JSON Mock Isolation Hook Planning ==="

DOC="${REPO_DIR}/docs/validation-v1.8-status-json-mock-isolation-hook-planning.md"

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
echo "--- 1: Required title and blocker ---"

assert_contains "$doc_content" "Status JSON Mock Isolation Hook Planning" "1a: has hook planning title"
assert_contains "$doc_content" "/root/.nanok-cf-admin.env" "1b: mentions root admin env"
assert_contains "$doc_content" "Current blocker" "1c: has current blocker section"

echo ""
echo "--- 2: Candidate hooks and recommendation ---"

assert_contains "$doc_content" "Candidate hooks" "2a: has candidate hooks"
assert_contains "$doc_content" "Option A" "2b: has Option A"
assert_contains "$doc_content" "NANOBK_STATUS_MOCK_ROOT" "2c: has broad hook option"
assert_contains "$doc_content" "Option B" "2d: has Option B"
assert_contains "$doc_content" "NANOBK_STATUS_ADMIN_ENV_PATH" "2e: has narrow hook candidate"
assert_contains "$doc_content" "Recommended final variable" "2f: has final recommended variable"
assert_contains "$doc_content" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" "2g: recommends test-scoped hook"

echo ""
echo "--- 3: Sketch and future test plan ---"

assert_contains "$doc_content" "Proposed implementation sketch" "3a: has implementation sketch"
assert_contains "$doc_content" "status_admin_env_path" "3b: has sketch variable"
assert_contains "$doc_content" "Required future tests" "3c: has future tests"
assert_contains "$doc_content" "Relationship to future mock filesystem prototype" "3d: has prototype relationship"
assert_contains "$doc_content" "NANOBK_REPO_DIR=<tmp_root/repo>" "3e: has mock repo env"
assert_contains "$doc_content" "bin/nanobk --json status --config-dir <tmp_root/config>" "3f: has future status command"
assert_contains "$doc_content" "PATH systemctl shim" "3g: has PATH systemctl shim"

echo ""
echo "--- 4: Risk and next version ---"

assert_contains "$doc_content" "Risk assessment" "4a: has risk assessment"
assert_contains "$doc_content" "v1.8.40" "4b: mentions v1.8.40"
assert_contains "$doc_content" "Status JSON Admin Env Path Test Hook" "4c: has next-step title"

echo ""
echo "--- 5: Forbidden content ---"

assert_contains "$doc_content" "Do NOT add NANOBK_OPLOG_STATUS_PILOT yet" "5a: forbids status pilot"
assert_contains "$doc_content" "Do NOT modify resolve_repo_dir" "5b: forbids resolve_repo_dir changes"
assert_contains "$doc_content" "Do NOT change status JSON schema" "5c: forbids schema change"
assert_contains "$doc_content" "run_cmd" "5d: mentions run_cmd"
assert_contains "$doc_content" "run_critical_step" "5e: mentions run_critical_step"
assert_contains "$doc_content" "Do NOT expose raw status JSON in chat" "5f: raw status JSON chat ban"

echo ""
echo "--- 6: v1.8.40 implementation section ---"

assert_contains "$doc_content" "v1.8.40 Admin Env Path Test Hook" "6a: has v1.8.40 section title"
assert_contains "$doc_content" "v1.8.40 implements NANOBK_STATUS_TEST_ADMIN_ENV_PATH" "6b: states hook implemented"
assert_contains "$doc_content" "only affects admin env existence check" "6c: states scope limited"
assert_contains "$doc_content" "no content sourced" "6d: states no content sourced"
assert_contains "$doc_content" "no path printed" "6e: states no path printed"
assert_contains "$doc_content" "no status wrapper" "6f: states no status wrapper"

echo ""
echo "--- 7: v1.8.44 oplog prototype section ---"

assert_contains "$doc_content" "v1.8.41 Mock Filesystem Operation-Log Prototype" "7a: has v1.8.41 section title"
assert_contains "$doc_content" "v1.8.41 uses NANOBK_STATUS_TEST_ADMIN_ENV_PATH" "7b: states uses v1.8.40 hook"
assert_contains "$doc_content" "mock config/repo/admin env path" "7c: states mock paths"
assert_contains "$doc_content" "operation-log" "7d: mentions operation-log"
assert_contains "$doc_content" "systemctl PATH shim" "7e: mentions systemctl shim"
assert_contains "$doc_content" "failure propagation" "7f: mentions failure propagation"
assert_contains "$doc_content" "No dirty VPS status" "7g: no dirty VPS status"
assert_contains "$doc_content" "No NANOBK_OPLOG_STATUS_PILOT" "7h: no status pilot"

echo ""
echo "--- 8: v1.8.42 command path polish ---"

assert_contains "$doc_content" "v1.8.42 Command Path Polish" "8a: has v1.8.42 section"
assert_contains "$doc_content" "bash bin/nanobk" "8b: uses relative path"
assert_contains "$doc_content" "no longer records real repo absolute path" "8c: no absolute path in log"

echo ""
echo "--- 9: v1.8.43 prototype checkpoint ---"

assert_contains "$doc_content" "v1.8.43 Prototype Checkpoint" "9a: has v1.8.43 section"
assert_contains "$doc_content" "mock status oplog prototype acceptance" "9b: records acceptance"
assert_contains "$doc_content" "No status pilot" "9c: no status pilot"
assert_contains "$doc_content" "No dirty VPS" "9d: no dirty VPS"

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
