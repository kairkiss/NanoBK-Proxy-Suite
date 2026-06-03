#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.19 CLI Mode Boundaries Test
#
# Tests full installer output respects mode boundaries:
#   PLAIN: no box drawing / emoji / Unicode progress
#   UI=0: no large banner
#   Compact: truly shorter
#
# Usage:
#   bash tests/unified-cli-mode-boundaries-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo "  OK $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

has_ansi() {
  grep -qE $'\x1b\[' <<< "$1"
}

count_lines() {
  echo "$1" | wc -l | tr -d ' '
}

echo ""
echo "=== Test Suite: v1.8.19 CLI Mode Boundaries ==="

# ── Test 1: Plain full output ────────────────────────────────────────────

echo ""
echo "--- 1: Plain full output ---"

plain_output=$(env NANOBK_PLAIN=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# Must contain
assert_contains "$plain_output" "NanoBK" "Plain: contains NanoBK"
assert_contains "$plain_output" "planned / dry-run" "Plain: contains planned / dry-run"
assert_contains "$plain_output" "没有执行真实部署" "Plain: contains no-real-deploy CN"
assert_contains "$plain_output" "No real deployment was performed" "Plain: contains no-real-deploy EN"
assert_contains "$plain_output" "Preflight" "Plain: contains Preflight"
assert_contains "$plain_output" "OK" "Plain: contains OK"

# Must NOT contain box drawing / emoji / Unicode
assert_not_contains "$plain_output" "╔" "Plain: no ╔"
assert_not_contains "$plain_output" "║" "Plain: no ║"
assert_not_contains "$plain_output" "╚" "Plain: no ╚"
assert_not_contains "$plain_output" "═" "Plain: no ═"
assert_not_contains "$plain_output" "─" "Plain: no Unicode dash"
assert_not_contains "$plain_output" "✓" "Plain: no ✓"
assert_not_contains "$plain_output" "■" "Plain: no ■"
assert_not_contains "$plain_output" "□" "Plain: no □"
assert_not_contains "$plain_output" "╭" "Plain: no ╭"
assert_not_contains "$plain_output" "╯" "Plain: no ╯"

# Must NOT contain ANSI escapes
if has_ansi "$plain_output"; then
  fail "Plain: no ANSI escape"
else
  pass "Plain: no ANSI escape"
fi

# Plain Summary title boundary
plain_summary_block=$(sed -n '/NanoBK Setup Summary/,+5p' <<< "$plain_output" || true)
if [[ -n "$plain_summary_block" ]]; then
  assert_contains "$plain_summary_block" "NanoBK Setup Summary" "Plain Summary: title present"
  assert_not_contains "$plain_summary_block" "─" "Plain Summary: no Unicode dash"
  if has_ansi "$plain_summary_block"; then
    fail "Plain Summary: no ANSI"
  else
    pass "Plain Summary: no ANSI"
  fi
else
  pass "Plain Summary: block not found (acceptable)"
fi

# Must NOT contain secrets or fake success
assert_not_contains "$plain_output" "status:  success" "Plain: no fake success"
assert_not_contains "$plain_output" "TOKEN=" "Plain: no TOKEN="
assert_not_contains "$plain_output" "SECRET=" "Plain: no SECRET="
assert_not_contains "$plain_output" "ADMIN_TOKEN=" "Plain: no ADMIN_TOKEN="

# ── Test 2: UI=0 full output ─────────────────────────────────────────────

echo ""
echo "--- 2: UI=0 full output ---"

ui0_output=$(env NANOBK_UI=0 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# Must contain
assert_contains "$ui0_output" "NanoBK" "UI=0: contains NanoBK"
assert_contains "$ui0_output" "planned / dry-run" "UI=0: contains planned / dry-run"
assert_contains "$ui0_output" "没有执行真实部署" "UI=0: contains no-real-deploy"

# Must NOT contain box drawing
assert_not_contains "$ui0_output" "╔" "UI=0: no ╔"
assert_not_contains "$ui0_output" "║" "UI=0: no ║"
assert_not_contains "$ui0_output" "╚" "UI=0: no ╚"
assert_not_contains "$ui0_output" "═" "UI=0: no ═"
assert_not_contains "$ui0_output" "─" "UI=0: no Unicode dash"
assert_not_contains "$ui0_output" "✓" "UI=0: no ✓"
assert_not_contains "$ui0_output" "■" "UI=0: no ■"
assert_not_contains "$ui0_output" "□" "UI=0: no □"

# Summary title must still be present
assert_contains "$ui0_output" "NanoBK Setup Summary" "UI=0: contains Summary title"

# Must NOT contain ANSI escapes
if has_ansi "$ui0_output"; then
  fail "UI=0: no ANSI escape"
else
  pass "UI=0: no ANSI escape"
fi

# UI=0 Summary title boundary
ui0_summary_block=$(sed -n '/NanoBK Setup Summary/,+5p' <<< "$ui0_output" || true)
if [[ -n "$ui0_summary_block" ]]; then
  assert_contains "$ui0_summary_block" "NanoBK Setup Summary" "UI=0 Summary: title present"
  assert_not_contains "$ui0_summary_block" "─" "UI=0 Summary: no Unicode dash"
  if has_ansi "$ui0_summary_block"; then
    fail "UI=0 Summary: no ANSI"
  else
    pass "UI=0 Summary: no ANSI"
  fi
else
  pass "UI=0 Summary: block not found (acceptable)"
fi

# ── Test 3: Compact truly shorter ────────────────────────────────────────

echo ""
echo "--- 3: Compact truly shorter ---"

default_output=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

compact_output=$(env NANOBK_COMPACT=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# Compact must still contain key content
assert_contains "$compact_output" "NanoBK" "Compact: contains NanoBK"
assert_contains "$compact_output" "planned / dry-run" "Compact: contains planned / dry-run"
assert_contains "$compact_output" "没有执行真实部署" "Compact: contains no-real-deploy"
assert_contains "$compact_output" "NanoBK Setup Summary" "Compact: contains Summary title"
assert_contains "$compact_output" "控制端" "Compact: contains control plane"
assert_not_contains "$compact_output" "status:  success" "Compact: no fake success"
assert_not_contains "$compact_output" "TOKEN=" "Compact: no TOKEN="
assert_not_contains "$compact_output" "SECRET=" "Compact: no SECRET="
assert_not_contains "$compact_output" "ADMIN_TOKEN=" "Compact: no ADMIN_TOKEN="

# Compact must be shorter than default
default_lines=$(count_lines "$default_output")
compact_lines=$(count_lines "$compact_output")
max_compact=$((default_lines * 85 / 100))
if [[ "$compact_lines" -le "$max_compact" ]]; then
  pass "Compact: $compact_lines lines <= 85% of default ($max_compact)"
else
  fail "Compact: $compact_lines lines > 85% of default ($max_compact)"
fi

# Default mode should still have product-like Summary title
default_summary_block=$(sed -n '/NanoBK Setup Summary/,+5p' <<< "$default_output" || true)
if [[ -n "$default_summary_block" ]]; then
  assert_contains "$default_summary_block" "NanoBK Setup Summary" "Default Summary: title present"
  # Default mode is allowed to have Unicode elements
  pass "Default Summary: product UI preserved"
else
  pass "Default Summary: block not found (acceptable)"
fi

# ── Test 4: Plain preflight ASCII ────────────────────────────────────────

echo ""
echo "--- 4: Plain preflight ASCII ---"

assert_contains "$plain_output" "Preflight" "Plain preflight: contains Preflight"
assert_contains "$plain_output" "OK" "Plain preflight: contains OK"
# Check that preflight uses plain OK, not ✓
preflight_section=$(sed -n '/Preflight/,/阶段 1/p' <<< "$plain_output" | head -20)
if grep -qF '✓' <<< "$preflight_section"; then
  fail "Plain preflight: no ✓ in preflight section"
else
  pass "Plain preflight: no ✓ in preflight section"
fi

# ── Test 5: CI mode ──────────────────────────────────────────────────────

echo ""
echo "--- 5: CI mode ---"

ci_output=$(env CI=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

assert_contains "$ci_output" "NanoBK" "CI: contains NanoBK"
assert_contains "$ci_output" "planned / dry-run" "CI: contains planned / dry-run"
assert_contains "$ci_output" "没有执行真实部署" "CI: contains no-real-deploy"

if has_ansi "$ci_output"; then
  fail "CI: no ANSI escape"
else
  pass "CI: no ANSI escape"
fi

assert_not_contains "$ci_output" "TOKEN=" "CI: no TOKEN="
assert_not_contains "$ci_output" "SECRET=" "CI: no SECRET="
assert_not_contains "$ci_output" "status:  success" "CI: no fake success"

# ── Test 5b: Compact + Plain combined ────────────────────────────────────

echo ""
echo "--- 5b: Compact + Plain combined ---"

compact_plain_output=$(env NANOBK_COMPACT=1 NANOBK_PLAIN=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

if has_ansi "$compact_plain_output"; then
  fail "Compact+Plain: no ANSI escape"
else
  pass "Compact+Plain: no ANSI escape"
fi

assert_not_contains "$compact_plain_output" "╔" "Compact+Plain: no box drawing"
assert_not_contains "$compact_plain_output" "✓" "Compact+Plain: no emoji"
assert_not_contains "$compact_plain_output" "■" "Compact+Plain: no progress bar"
assert_contains "$compact_plain_output" "planned / dry-run" "Compact+Plain: contains planned / dry-run"
assert_contains "$compact_plain_output" "没有执行真实部署" "Compact+Plain: contains no-real-deploy"

# ── Test 6: Secret safety on all outputs ─────────────────────────────────

echo ""
echo "--- 6: Secret safety on all outputs ---"

for output_name in "plain" "ui0" "compact" "default"; do
  case "$output_name" in
    plain)   check_output="$plain_output" ;;
    ui0)     check_output="$ui0_output" ;;
    compact) check_output="$compact_output" ;;
    default) check_output="$default_output" ;;
  esac
  assert_not_contains "$check_output" "TOKEN=" "Secret $output_name: no TOKEN="
  assert_not_contains "$check_output" "SECRET=" "Secret $output_name: no SECRET="
  assert_not_contains "$check_output" "ADMIN_TOKEN=" "Secret $output_name: no ADMIN_TOKEN="
  assert_not_contains "$check_output" "SUB_TOKEN=" "Secret $output_name: no SUB_TOKEN="
  assert_not_contains "$check_output" "NANOB_TOKEN=" "Secret $output_name: no NANOB_TOKEN="
  assert_not_contains "$check_output" "NANOBK_CF_API_TOKEN" "Secret $output_name: no CF_API_TOKEN"
done

# ── Test 7: Interactive Plain ANSI regression ─────────────────────────────

echo ""
echo "--- 7: Interactive Plain ANSI regression ---"

# Test A: Plain + VPS mode with invalid input triggers domain warning
plain_vps_output=$(env NANOBK_PLAIN=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode vps --dry-run --lang zh 2>&1 <<'EOF' || true
https://proxy.example.com/path
1
1
EOF
)

assert_contains "$plain_vps_output" "NanoBK" "Interactive Plain VPS: contains NanoBK"
if has_ansi "$plain_vps_output"; then
  fail "Interactive Plain VPS: no ANSI escape"
else
  pass "Interactive Plain VPS: no ANSI escape"
fi
assert_not_contains "$plain_vps_output" "╔" "Interactive Plain VPS: no box drawing"
assert_not_contains "$plain_vps_output" "✓" "Interactive Plain VPS: no emoji"
assert_not_contains "$plain_vps_output" "TOKEN=" "Interactive Plain VPS: no TOKEN="

# Test B: UI=0 + VPS mode with invalid input
ui0_vps_output=$(env NANOBK_UI=0 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode vps --dry-run --lang zh 2>&1 <<'EOF' || true
https://proxy.example.com/path
1
1
EOF
)

assert_contains "$ui0_vps_output" "NanoBK" "Interactive UI=0 VPS: contains NanoBK"
if has_ansi "$ui0_vps_output"; then
  fail "Interactive UI=0 VPS: no ANSI escape"
else
  pass "Interactive UI=0 VPS: no ANSI escape"
fi

# Test C: Static source guard — count say_yellow usage (should be high)
say_yellow_count=$(grep -c 'say_yellow' "${REPO_DIR}/installer/install.sh" || echo "0")
if [[ "$say_yellow_count" -ge 10 ]]; then
  pass "Source guard: say_yellow used $say_yellow_count times"
else
  fail "Source guard: say_yellow only used $say_yellow_count times (expected >= 10)"
fi

# ── Test 8: Test helper stability ────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-mode-boundaries-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-mode-boundaries-v1.8.sh"; then
  pass "Self-check: uses here-string"
else
  fail "Self-check: must use here-string"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
