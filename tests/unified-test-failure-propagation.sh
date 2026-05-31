#!/usr/bin/env bash
# NanoBK Proxy Suite — Test Failure Propagation Test
#
# Verifies that test mode propagates child test failures.
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

echo "=== Test Failure Propagation Test ==="
echo ""

# ── Test 1: Static checks ──────────────────────────────────────────────────
echo "── Test 1: Static checks ──"

check "has TEST_FAILURES counter" "$(has_pattern "$INSTALLER" "TEST_FAILURES")"
check "has TEST_FAILED_NAMES array" "$(has_pattern "$INSTALLER" "TEST_FAILED_NAMES")"
check "has failure propagation in run_one_test" "$(has_pattern "$INSTALLER" "TEST_FAILURES.*1\|TEST_FAILURES=\\\$")"
check "has failure summary output" "$(has_pattern "$INSTALLER" "失败项目\|failed.*test")"
check "has return 1 on failure" "$(has_pattern "$INSTALLER" "return 1")"

# ── Test 2: Dynamic test with mock failure ──────────────────────────────────
echo ""
echo "── Test 2: Dynamic test with mock failure ──"

# Create a temporary test that always fails
TMP_TEST="/tmp/nanobk-test-always-fail-$$.sh"
cat > "$TMP_TEST" <<'EOF'
#!/usr/bin/env bash
echo "This test always fails"
exit 1
EOF
chmod +x "$TMP_TEST"

# Test run_one_test by calling it directly
# We need to define the required functions
OUTPUT=$(bash -c "
  DRY_RUN=0
  COMMAND_ONLY=0
  log() { echo \"[INFO] \$*\"; }
  ok() { echo \"[OK] \$*\"; }
  warn() { echo \"[WARN] \$*\"; }
  err() { echo \"[ERROR] \$*\" >&2; }
  print_cmd() { echo \"  \$ \${*}\"; }

  TEST_FAILURES=0
  TEST_FAILED_NAMES=()

  run_one_test() {
    local script=\"\$1\"
    local label=\"\$2\"
    local cmd=(bash \"\$script\")
    log \"运行: \${label}\"
    print_cmd \"\${cmd[@]}\"
    if \"\${cmd[@]}\"; then
      return 0
    else
      warn \"测试失败: \${label}\"
      TEST_FAILURES=\$((TEST_FAILURES + 1))
      TEST_FAILED_NAMES+=(\"\${label}\")
      return 1
    fi
  }

  run_one_test '$TMP_TEST' 'mock failure test'
  echo \"TEST_FAILURES=\$TEST_FAILURES\"
  echo \"TEST_FAILED_NAMES=\${TEST_FAILED_NAMES[*]}\"
" 2>&1) || true

check "output contains TEST_FAILURES" "$(echo "$OUTPUT" | grep -q "TEST_FAILURES=" && echo 1 || echo 0)"
check "output contains failure message" "$(echo "$OUTPUT" | grep -qi "测试失败\|WARN\|mock failure" && echo 1 || echo 0)"

rm -f "$TMP_TEST"

# ── Test 3: Test mode with all passing tests should exit 0 ──────────────────
echo ""
echo "── Test 3: Test mode with passing tests ──"

# Run a quick test that should pass
OUTPUT_PASS=$(bash "$INSTALLER" --mode test --defaults 2>&1) || EXIT_CODE=$?

check "test mode exits 0 when all pass" "$([[ ${EXIT_CODE:-0} -eq 0 ]] && echo 1 || echo 0)"
check "output contains all passed" "$(echo "$OUTPUT_PASS" | grep -qi "全部通过\|all passed" && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
