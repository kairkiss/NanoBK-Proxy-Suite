#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.5 CLI Dry-run Layout Test
#
# Checks Full Wizard dry-run page layout without real deployment.
# Uses safe mock / dry-run / defaults only.
#
# Usage:
#   bash tests/unified-cli-dry-run-layout-v1.8.sh

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
  if grep -qF "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

# Check that marker A appears before marker B in the text
assert_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local label="$4"
  # Get line numbers of first occurrence of each marker
  local line_first line_second
  line_first=$(grep -nF "$first" <<< "$haystack" | head -1)
  line_second=$(grep -nF "$second" <<< "$haystack" | head -1)
  local num_first num_second
  num_first=$(echo "$line_first" | cut -d: -f1)
  num_second=$(echo "$line_second" | cut -d: -f1)
  if [[ -z "$num_first" ]] || [[ -z "$num_second" ]]; then
    fail "$label — markers not found (first='$first', second='$second')"
    return
  fi
  # If same line, check column position within the line
  if [[ "$num_first" -eq "$num_second" ]]; then
    local col_first col_second
    col_first=$(echo "$line_first" | awk -v s="$first" '{print index($0, s)}')
    col_second=$(echo "$line_second" | awk -v s="$second" '{print index($0, s)}')
    if [[ "$col_first" -lt "$col_second" ]]; then
      pass "$label"
    else
      fail "$label — expected '$first' (col $col_first) before '$second' (col $col_second)"
    fi
  elif [[ "$num_first" -lt "$num_second" ]]; then
    pass "$label"
  else
    fail "$label — expected '$first' (line $num_first) before '$second' (line $num_second)"
  fi
}

source_ui_and_run() {
  local env_flags="$1"
  local code="$2"
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/ui.sh'
    ${code}
  " 2>&1
}

echo ""
echo "=== Test Suite: v1.8.5 CLI Dry-run Layout ==="

# ── Run Full Wizard dry-run ───────────────────────────────────────────────

echo ""
echo "--- Capturing Full Wizard dry-run output ---"

wizard_output=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# ── Layout 1: Entry page ──────────────────────────────────────────────────

echo ""
echo "--- Layout 1: Entry page ---"

assert_contains "$wizard_output" "NanoBK" "Entry: contains NanoBK"
assert_contains "$wizard_output" "Full Recommended" "Entry: contains Full Recommended"

# ── Layout 2: Stage structure ─────────────────────────────────────────────

echo ""
echo "--- Layout 2: Stage structure ---"

assert_contains "$wizard_output" "VPS" "Stage: contains VPS"
assert_contains "$wizard_output" "Cloudflare" "Stage: contains Cloudflare"
assert_contains "$wizard_output" "Telegram Bot" "Stage: contains Telegram Bot"
assert_contains "$wizard_output" "Web Panel" "Stage: contains Web Panel"

# ── Layout 3: Stage ordering ──────────────────────────────────────────────

echo ""
echo "--- Layout 3: Stage ordering ---"

# Use stage header markers from install.sh (阶段 1, 阶段 2, etc.)
# These only appear in the stage sections, not in the banner subtitle
assert_order "$wizard_output" "阶段 1" "阶段 2" "Order: Stage 1 before Stage 2"
assert_order "$wizard_output" "阶段 2" "阶段 3" "Order: Stage 2 before Stage 3"
assert_order "$wizard_output" "阶段 3" "阶段 4" "Order: Stage 3 before Stage 4"

# ── Layout 4: Dry-run honesty ─────────────────────────────────────────────

echo ""
echo "--- Layout 4: Dry-run honesty ---"

assert_contains "$wizard_output" "planned / dry-run" "Honesty: contains planned / dry-run"
assert_not_contains "$wizard_output" "status:  success" "Honesty: no fake success"
assert_not_contains "$wizard_output" "status: success" "Honesty: no fake success (no double space)"

# Summary section should exist
assert_contains "$wizard_output" "Summary" "Honesty: contains Summary"

# ── Layout 4b: VPS Summary dry-run wording (default dry-run) ─────────────

echo ""
echo "--- Layout 4b: VPS Summary dry-run wording (default) ---"

# Extract VPS block from Summary (from "VPS:" to "Cloudflare:")
vps_block=$(awk '/^  VPS:/{found=1} found{print} /^  Cloudflare:/{if(found) exit}' <<< "$wizard_output" | grep -v 'Cloudflare:')

# In default dry-run, VPS block should show "planned / dry-run"
assert_contains "$vps_block" "planned / dry-run" "VPS block default: contains planned / dry-run"
assert_not_contains "$vps_block" "skipped (dry-run)" "VPS block default: no skipped (dry-run)"
assert_not_contains "$vps_block" "status:  installed" "VPS block default: no installed"
assert_not_contains "$vps_block" "status:  success" "VPS block default: no success"

# ── Layout 4d: User-skip VPS dry-run Summary ─────────────────────────────

echo ""
echo "--- Layout 4d: User-skip VPS dry-run Summary ---"

# Run with user explicitly skipping VPS (input: 2=skip VPS, then skip CF/Bot/Web, 6=exit resume if shown)
skip_output=$(printf '2\nn\nn\nn\n' | env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --lang zh 2>&1 || true)

# Extract VPS block from skip output
skip_vps_block=$(awk '/^  VPS:/{found=1} found{print} /^  Cloudflare:/{if(found) exit}' <<< "$skip_output" | grep -v 'Cloudflare:')

# When user skips VPS in dry-run, VPS block should show "skipped"
if [[ -n "$skip_vps_block" ]]; then
  if grep -qF 'skipped' <<< "$skip_vps_block"; then
    pass "VPS block skip: contains skipped"
  else
    fail "VPS block skip: expected skipped in VPS block"
  fi
  # Should NOT show "planned / dry-run" when user explicitly skipped
  assert_not_contains "$skip_vps_block" "planned / dry-run" "VPS block skip: no planned / dry-run"
else
  # VPS block must exist in Summary — fail if not found
  fail "VPS block skip: VPS block not found in Summary output"
fi

# ── Layout 4c: Mock output product wording ───────────────────────────────

echo ""
echo "--- Layout 4c: Mock output product wording ---"

# Mock output should use product-like wording
assert_contains "$wizard_output" "模拟完成" "Mock: contains simulated-complete wording"

# Old English mock wording should be replaced
assert_not_contains "$wizard_output" "deploy success (simulated)" "Mock: no old deploy success wording"

# ── Layout 4e: Mock/dry-run existing-state explanation ────────────────────

echo ""
echo "--- Layout 4e: Mock/dry-run existing-state explanation ---"

# Create a temporary wizard state file to trigger existing state detection
mock_state_dir=$(mktemp -d)
trap "rm -rf '$mock_state_dir'" EXIT

# Write a mock wizard state file
cat > "${mock_state_dir}/.nanobk-wizard-state.json" <<'MOCKSTATE'
{
  "stage": "vps_done",
  "domain": "mock.example.com",
  "timestamp": "2025-01-01T00:00:00"
}
MOCKSTATE

# Run with mock state file present
existing_output=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 NANOBK_TEST_TMPDIR="$mock_state_dir" \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# When existing state is detected in mock/dry-run mode, explanation must be present
if grep -qF '检测到已有 NanoBK 状态' <<< "$existing_output"; then
  assert_contains "$existing_output" "mock / dry-run 模式" "Existing state: contains mock mode explanation"
  assert_contains "$existing_output" "不会读取真实部署状态" "Existing state: contains real-state-skip explanation"
else
  pass "Existing state: no existing state detected (mock isolation worked)"
fi

# ── Layout 5: Control-plane wording ───────────────────────────────────────

echo ""
echo "--- Layout 5: Control-plane wording ---"

install_content=$(cat "${REPO_DIR}/installer/install.sh")
assert_contains "$install_content" "控制端配置" "Control-plane: wording preserved in source"
assert_contains "$install_content" "不代表 VPS 节点或 Cloudflare 订阅已经可用" "Control-plane: semantic preserved in source"

# Mock/dry-run existing state explanation must be present in source
assert_contains "$install_content" "mock / dry-run 模式" "Source: mock/dry-run explanation present"
assert_contains "$install_content" "不会读取真实部署状态" "Source: real-state-skip explanation present"

# ── Layout 6: Secret safety ───────────────────────────────────────────────

echo ""
echo "--- Layout 6: Secret safety ---"

assert_not_contains "$wizard_output" "SECRET_TEST_BOT_TOKEN" "Secret: no test bot token"
assert_not_contains "$wizard_output" "TOKEN=" "Secret: no TOKEN="
assert_not_contains "$wizard_output" "SECRET=" "Secret: no SECRET="
assert_not_contains "$wizard_output" "ADMIN_TOKEN=" "Secret: no ADMIN_TOKEN="
assert_not_contains "$wizard_output" "NANOBK_CF_API_TOKEN" "Secret: no raw CF token var"
assert_not_contains "$wizard_output" ".cloudflare.local.env" "Secret: no CF env path"
assert_not_contains "$wizard_output" ".nanob.local.env" "Secret: no nanob env path"
assert_not_contains "$wizard_output" "nanok-cf-admin.env" "Secret: no admin env path"

# ── Layout 7: Visual noise ────────────────────────────────────────────────

echo ""
echo "--- Layout 7: Visual noise ---"

# No bash trace / set -x style output
assert_not_contains "$wizard_output" "+ echo" "Noise: no bash trace echo"
assert_not_contains "$wizard_output" "+ set" "Noise: no bash trace set"

# Count how many lines look like raw commands (start with "+ ")
raw_cmd_lines=$(grep -cE '^\+ ' <<< "$wizard_output" || true)
raw_cmd_lines="${raw_cmd_lines:-0}"
# Trim whitespace
raw_cmd_lines="${raw_cmd_lines//[^0-9]/}"
raw_cmd_lines="${raw_cmd_lines:-0}"
if [[ "$raw_cmd_lines" -gt 5 ]]; then
  fail "Noise: too many raw command lines ($raw_cmd_lines)"
else
  pass "Noise: raw command lines within limit ($raw_cmd_lines)"
fi

# ── Layout 8: ui_dry_run_notice function ──────────────────────────────────

echo ""
echo "--- Layout 8: ui_dry_run_notice ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_dry_run_notice
")

assert_contains "$output" "dry-run" "Notice: contains dry-run"
assert_contains "$output" "没有执行真实部署" "Notice: contains no-real-deployment CN"
assert_contains "$output" "No real deployment was performed" "Notice: contains no-real-deployment EN"
assert_not_contains "$output" "success" "Notice: no success"

# ── Layout 9: Test helper stability ───────────────────────────────────────

echo ""
echo "--- Layout 9: Test helper stability ---"

# This test file must not have pipe+grep-q patterns
filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have\|assert_order\|pos_first\|pos_second\|awk.*index' "${SCRIPT_DIR}/unified-cli-dry-run-layout-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-dry-run-layout-v1.8.sh"; then
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
