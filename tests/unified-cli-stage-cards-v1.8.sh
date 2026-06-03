#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.21 CLI Stage Cards Test
#
# Tests ui_stage_card and stage-specific helpers without real deployment.
#
# Usage:
#   bash tests/unified-cli-stage-cards-v1.8.sh

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

source_ui_and_run() {
  local env_flags="$1"
  local code="$2"
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/ui.sh'
    ${code}
  " 2>&1
}

echo ""
echo "=== Test Suite: v1.8.21 CLI Stage Cards ==="

# ── 1: Stage card default snapshot ────────────────────────────────────────

echo ""
echo "--- 1: Stage card default snapshot ---"

output=$(source_ui_and_run "" "
  ui_stage_card_vps
  ui_stage_card_cloudflare
  ui_stage_card_bot
  ui_stage_card_web
  ui_stage_card_summary
")

assert_contains "$output" "VPS" "Default: contains VPS"
assert_contains "$output" "HY2" "Default: contains HY2"
assert_contains "$output" "TUIC" "Default: contains TUIC"
assert_contains "$output" "Reality" "Default: contains Reality"
assert_contains "$output" "Trojan" "Default: contains Trojan"
assert_contains "$output" "nanok" "Default: contains nanok"
assert_contains "$output" "nanob" "Default: contains nanob"
assert_contains "$output" "Bot" "Default: contains Bot"
assert_contains "$output" "Web" "Default: contains Web"
assert_contains "$output" "控制端" "Default: contains control plane"
assert_contains "$output" "dry-run" "Default: contains dry-run"
assert_contains "$output" "planned / dry-run" "Default: contains planned / dry-run"

# ── 2: PLAIN mode ────────────────────────────────────────────────────────

echo ""
echo "--- 2: PLAIN mode ---"

plain_output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_stage_card_vps
  ui_stage_card_cloudflare
  ui_stage_card_bot
  ui_stage_card_web
  ui_stage_card_summary
")

assert_contains "$plain_output" "VPS" "PLAIN: contains VPS"
assert_contains "$plain_output" "HY2" "PLAIN: contains HY2"
assert_contains "$plain_output" "nanok" "PLAIN: contains nanok"
assert_contains "$plain_output" "控制端" "PLAIN: contains control plane"
assert_contains "$plain_output" "planned / dry-run" "PLAIN: contains planned / dry-run"

if has_ansi "$plain_output"; then
  fail "PLAIN: no ANSI escape"
else
  pass "PLAIN: no ANSI escape"
fi
assert_not_contains "$plain_output" "✓" "PLAIN: no emoji checkmark"
assert_not_contains "$plain_output" "╭" "PLAIN: no box drawing"
assert_not_contains "$plain_output" "■" "PLAIN: no progress bar"

# ── 3: NO_EMOJI mode ─────────────────────────────────────────────────────

echo ""
echo "--- 3: NO_EMOJI mode ---"

noemoji_output=$(source_ui_and_run "NANOBK_NO_EMOJI=1" "
  ui_stage_card_vps
")

assert_contains "$noemoji_output" "VPS" "NO_EMOJI: contains VPS"
assert_contains "$noemoji_output" "HY2" "NO_EMOJI: contains HY2"
assert_not_contains "$noemoji_output" "✓" "NO_EMOJI: no emoji"

# ── 4: UI=0 mode ─────────────────────────────────────────────────────────

echo ""
echo "--- 4: UI=0 mode ---"

ui0_output=$(source_ui_and_run "NANOBK_UI=0" "
  ui_stage_card_vps
  ui_stage_card_bot
")

assert_contains "$ui0_output" "VPS" "UI=0: contains VPS"
assert_contains "$ui0_output" "Bot" "UI=0: contains Bot"
assert_not_contains "$ui0_output" "╭" "UI=0: no box drawing"
assert_not_contains "$ui0_output" "│" "UI=0: no box vertical"
assert_not_contains "$ui0_output" "✓" "UI=0: no emoji"

# ── 5: Full Wizard dry-run output ────────────────────────────────────────

echo ""
echo "--- 5: Full Wizard dry-run output ---"

wizard_output=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

assert_contains "$wizard_output" "HY2" "Wizard: contains HY2"
assert_contains "$wizard_output" "TUIC" "Wizard: contains TUIC"
assert_contains "$wizard_output" "Reality" "Wizard: contains Reality"
assert_contains "$wizard_output" "Trojan" "Wizard: contains Trojan"
assert_contains "$wizard_output" "nanok" "Wizard: contains nanok"
assert_contains "$wizard_output" "nanob" "Wizard: contains nanob"
assert_contains "$wizard_output" "控制端" "Wizard: contains control plane"
assert_contains "$wizard_output" "planned / dry-run" "Wizard: contains planned / dry-run"
assert_contains "$wizard_output" "没有执行真实部署" "Wizard: contains no-real-deploy"

# ── 6: Secret safety ─────────────────────────────────────────────────────

echo ""
echo "--- 6: Secret safety ---"

all_outputs="${output}${plain_output}${noemoji_output}${ui0_output}${wizard_output}"

assert_not_contains "$all_outputs" "TOKEN=" "Secret: no TOKEN="
assert_not_contains "$all_outputs" "SECRET=" "Secret: no SECRET="
assert_not_contains "$all_outputs" "ADMIN_TOKEN=" "Secret: no ADMIN_TOKEN="
assert_not_contains "$all_outputs" "SUB_TOKEN=" "Secret: no SUB_TOKEN="
assert_not_contains "$all_outputs" "NANOB_TOKEN=" "Secret: no NANOB_TOKEN="
# workers.dev may appear in mock example URLs (e.g., nanok.example.workers.dev) — that's OK
# Just verify no real-looking worker URLs with tokens
assert_not_contains "$all_outputs" "?token=" "Secret: no URL token query"
assert_not_contains "$all_outputs" "nanok-cf-admin.env" "Secret: no admin env path"

# ── 7: Fake success guard ────────────────────────────────────────────────

echo ""
echo "--- 7: Fake success guard ---"

assert_not_contains "$wizard_output" "status:  success" "Honesty: no fake success"
assert_not_contains "$wizard_output" "status: success" "Honesty: no fake success (no double space)"

# ── 8: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-stage-cards-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-stage-cards-v1.8.sh"; then
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
