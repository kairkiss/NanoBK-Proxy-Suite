#!/usr/bin/env bash
# NanoBK Proxy Suite — Test Failure Propagation Test
#
# Verifies that test mode propagates child test failures.
# Uses real installer-level tests with NANOBK_TEST_OVERRIDE_SCRIPT.
#
# Usage:
#   bash tests/unified-test-failure-propagation.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_DIR/installer/install.sh"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

has_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "1"
  else
    echo "0"
  fi
}

contains() {
  local text="$1"
  local pattern="$2"
  if echo "$text" | grep -qi "$pattern"; then
    echo "1"
  else
    echo "0"
  fi
}

echo "=== Test Failure Propagation Test ==="
echo ""

# ── Test 1: Static checks ──────────────────────────────────────────────────
echo "── Test 1: Static checks ──"

check "has TEST_FAILURES counter" "$(has_pattern "$INSTALLER" "TEST_FAILURES")"
check "has TEST_FAILED_NAMES array" "$(has_pattern "$INSTALLER" "TEST_FAILED_NAMES")"
check "has finalize_test_mode function" "$(has_pattern "$INSTALLER" "finalize_test_mode")"
check "has NANOBK_TEST_OVERRIDE_SCRIPT hook" "$(has_pattern "$INSTALLER" "NANOBK_TEST_OVERRIDE_SCRIPT")"
check "has NANOBK_TEST_OVERRIDE_LABEL hook" "$(has_pattern "$INSTALLER" "NANOBK_TEST_OVERRIDE_LABEL")"
check "run_test_mode resets failure state" "$(has_pattern "$INSTALLER" "TEST_FAILURES=0")"
check "has failure summary output" "$(has_pattern "$INSTALLER" "失败项目")"
check "has return 1 on failure" "$(has_pattern "$INSTALLER" "return 1")"

# ── Test 2: Dynamic failure test (real installer-level) ─────────────────────
echo ""
echo "── Test 2: Dynamic failure test (real installer-level) ──"

TMP_FAIL="$(mktemp)"
cat > "$TMP_FAIL" <<'EOF'
#!/usr/bin/env bash
echo "mock failing child test"
exit 42
EOF
chmod +x "$TMP_FAIL"

set +e
OUTPUT_FAIL=$(NANOBK_TEST_OVERRIDE_SCRIPT="$TMP_FAIL" \
  NANOBK_TEST_OVERRIDE_LABEL="mock failing child test" \
  bash "$INSTALLER" --mode test --defaults 2>&1)
EXIT_CODE_FAIL=$?
set -e

rm -f "$TMP_FAIL"

check "exit code non-zero on failure" "$([[ $EXIT_CODE_FAIL -ne 0 ]] && echo 1 || echo 0)"
check "exit code is not 124 (timeout)" "$([[ $EXIT_CODE_FAIL -ne 124 ]] && echo 1 || echo 0)"
check "output contains failure message" "$(contains "$OUTPUT_FAIL" "本地安全测试失败\|failed")"
check "output contains mock label" "$(contains "$OUTPUT_FAIL" "mock failing child test")"
check "output contains 失败项目" "$(contains "$OUTPUT_FAIL" "失败项目")"

# ── Test 3: Dynamic success test (real installer-level) ─────────────────────
echo ""
echo "── Test 3: Dynamic success test (real installer-level) ──"

TMP_PASS="$(mktemp)"
cat > "$TMP_PASS" <<'EOF'
#!/usr/bin/env bash
echo "mock passing child test"
exit 0
EOF
chmod +x "$TMP_PASS"

OUTPUT_PASS=$(NANOBK_TEST_OVERRIDE_SCRIPT="$TMP_PASS" \
  NANOBK_TEST_OVERRIDE_LABEL="mock passing child test" \
  bash "$INSTALLER" --mode test --defaults 2>&1)
EXIT_CODE_PASS=$?

rm -f "$TMP_PASS"

check "exit code 0 on success" "$([[ $EXIT_CODE_PASS -eq 0 ]] && echo 1 || echo 0)"
check "output contains all passed" "$(contains "$OUTPUT_PASS" "全部通过\|all passed")"

# ── Test 4: Missing script test (real installer-level) ──────────────────────
echo ""
echo "── Test 4: Missing script test (real installer-level) ──"

set +e
OUTPUT_MISSING=$(NANOBK_TEST_OVERRIDE_SCRIPT="/tmp/does-not-exist-nanobk-$$" \
  NANOBK_TEST_OVERRIDE_LABEL="missing child test" \
  bash "$INSTALLER" --mode test --defaults 2>&1)
EXIT_CODE_MISSING=$?
set -e

check "exit code non-zero for missing script" "$([[ $EXIT_CODE_MISSING -ne 0 ]] && echo 1 || echo 0)"
check "output contains missing message" "$(contains "$OUTPUT_MISSING" "不存在\|missing")"
check "output contains missing label" "$(contains "$OUTPUT_MISSING" "missing child test")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
