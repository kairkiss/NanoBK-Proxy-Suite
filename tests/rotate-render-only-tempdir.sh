#!/usr/bin/env bash
# NanoBK Proxy Suite — Rotate Render-Only Temp Dir Test
#
# Verifies that rotate-render-only.sh uses isolated temp directories
# to avoid concurrent test pollution.
#
# Usage:
#   bash tests/rotate-render-only-tempdir.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_FILE="$REPO_DIR/tests/rotate-render-only.sh"

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

no_pattern() {
  local file="$1"
  local pattern="$2"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "0"
  else
    echo "1"
  fi
}

echo "=== Rotate Render-Only Temp Dir Test ==="
echo ""

# ── Test 1: Uses mktemp ─────────────────────────────────────────────────────
echo "── Test 1: Uses mktemp ──"

check "uses mktemp -d for TMP" "$(has_pattern "$TEST_FILE" "mktemp -d.*nanobk-rotate")"
check "uses mktemp -d for per-protocol" "$(has_pattern "$TEST_FILE" "mktemp -d.*nanobk-rotate-.*-XXXXXX")"

# ── Test 2: No hardcoded fixed dirs ─────────────────────────────────────────
echo ""
echo "── Test 2: No hardcoded fixed dirs ──"

check "no fixed nanobk-rotate-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-test"')"
check "no fixed nanobk-rotate-fail-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-fail-test"')"
check "no fixed nanobk-rotate-hy2-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-hy2-test"')"
check "no fixed nanobk-rotate-tuic-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-tuic-test"')"
check "no fixed nanobk-rotate-reality-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-reality-test"')"
check "no fixed nanobk-rotate-trojan-test" "$(no_pattern "$TEST_FILE" '/tmp/nanobk-rotate-trojan-test"')"

# ── Test 3: Has cleanup trap ────────────────────────────────────────────────
echo ""
echo "── Test 3: Has cleanup trap ──"

check "has trap cleanup" "$(has_pattern "$TEST_FILE" "trap.*cleanup\|trap.*EXIT")"
check "has cleanup function" "$(has_pattern "$TEST_FILE" "cleanup()\|cleanup ()")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
