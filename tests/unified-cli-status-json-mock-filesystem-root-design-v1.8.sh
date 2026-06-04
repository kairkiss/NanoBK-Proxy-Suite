#!/usr/bin/env bash
# NanoBK Proxy Suite - v1.8.44 Status JSON Mock Filesystem Root Design Coverage Test
#
# Verifies docs/validation-v1.8-status-json-mock-filesystem-root-design.md
# contains the required design checkpoint content.
#
# Does NOT run real bin/nanobk --json status.
#
# Usage:
#   bash tests/unified-cli-status-json-mock-filesystem-root-design-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

echo ""
echo "=== Test Suite: v1.8.44 Status JSON Mock Filesystem Root Design ==="

DOC="${REPO_DIR}/docs/validation-v1.8-status-json-mock-filesystem-root-design.md"

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
echo "--- 1: Required title and command boundaries ---"

assert_contains "$doc_content" "Status JSON Mock Filesystem Root Design" "1a: has design title"
assert_contains "$doc_content" "bin/nanobk --json status" "1b: has correct status command"
assert_contains "$doc_content" "bin/nanobk status --json" "1c: has incorrect status command warning"

echo ""
echo "--- 2: Code path inspection coverage ---"

assert_contains "$doc_content" "Current code path inspection" "2a: has code path section"
assert_contains "$doc_content" "--config-dir" "2b: mentions --config-dir"
assert_contains "$doc_content" "resolve_repo_dir" "2c: mentions resolve_repo_dir"
assert_contains "$doc_content" "config.env" "2d: mentions config.env"
assert_contains "$doc_content" "profile.current.json" "2e: mentions profile.current.json"
assert_contains "$doc_content" "secrets.private.env" "2f: mentions secrets.private.env"
assert_contains "$doc_content" ".cloudflare.local.env" "2g: mentions .cloudflare.local.env"
assert_contains "$doc_content" ".nanob.local.env" "2h: mentions .nanob.local.env"
assert_contains "$doc_content" ".nanok-cf-admin.env" "2i: mentions .nanok-cf-admin.env"

echo ""
echo "--- 3: Mock filesystem and isolation ---"

assert_contains "$doc_content" "Proposed mock filesystem layout" "3a: has proposed mock layout"
assert_contains "$doc_content" "Path isolation requirements" "3b: has path isolation requirements"
assert_contains "$doc_content" "systemctl/service status strategy" "3c: has systemctl strategy"
assert_contains "$doc_content" "JSON validity and redaction gates" "3d: has JSON validity gates"

echo ""
echo "--- 4: Next version and prototype policy ---"

assert_contains "$doc_content" "v1.8.38" "4a: mentions v1.8.38"
assert_contains "$doc_content" "Status JSON Mock Filesystem Prototype" "4b: has prototype recommendation"
assert_contains "$doc_content" "Dirty VPS status validation is still not approved" "4c: dirty VPS status still not approved"

echo ""
echo "--- 5: Forbidden next steps ---"

assert_contains "$doc_content" "Do NOT add NANOBK_OPLOG_STATUS_PILOT yet" "5a: forbids status pilot"
assert_contains "$doc_content" "Do NOT modify cmd_status yet" "5b: forbids cmd_status changes"
assert_contains "$doc_content" "Do NOT wrap real installed status on dirty VPS yet" "5c: forbids dirty VPS wrapping"
assert_contains "$doc_content" "run_cmd" "5d: mentions run_cmd"
assert_contains "$doc_content" "run_critical_step" "5e: mentions run_critical_step"
assert_contains "$doc_content" "do not paste raw output" "5f: has raw output rule"
assert_contains "$doc_content" "do not cat env" "5g: has env cat rule"

echo ""
echo "--- 6: v1.8.38 Feasibility Gate ---"

assert_contains "$doc_content" "v1.8.38" "6a: mentions v1.8.38"
assert_contains "$doc_content" "Feasibility Gate" "6b: has Feasibility Gate"
assert_contains "$doc_content" "Route A feasibility" "6c: mentions Route A feasibility"
assert_contains "$doc_content" "no mock runner implemented" "6d: no mock runner implemented"
assert_contains "$doc_content" "no real status runtime proof yet" "6e: no real status runtime proof"
assert_contains "$doc_content" "no status pilot" "6f: no status pilot"
assert_contains "$doc_content" "next step depends on feasibility verdict" "6g: next step depends on verdict"

echo ""
echo "--- 7: v1.8.39 Hook Planning Note ---"

assert_contains "$doc_content" "v1.8.39" "7a: mentions v1.8.39"
assert_contains "$doc_content" "admin env path isolation" "7b: plans admin env path isolation"
assert_contains "$doc_content" "before runtime prototype" "7c: before runtime prototype"

echo ""
echo "--- 8: v1.8.40 admin env hook implemented ---"

assert_contains "$doc_content" "v1.8.40" "8a: mentions v1.8.40"
assert_contains "$doc_content" "admin env path test hook" "8b: has admin env path test hook"

echo ""
echo "--- 9: v1.8.41 oplog prototype ---"

assert_contains "$doc_content" "v1.8.41" "9a: mentions v1.8.41"
assert_contains "$doc_content" "operation-log" "9b: mentions operation-log"

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
