#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.15 CLI Compact Mode Test
#
# Tests NANOBK_COMPACT=1 display mode without real deployment.
#
# Usage:
#   bash tests/unified-cli-compact-mode-v1.8.sh

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

source_ui_and_run() {
  local env_flags="$1"
  local code="$2"
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/ui.sh'
    ${code}
  " 2>&1
}

echo ""
echo "=== Test Suite: v1.8.15 CLI Compact Mode ==="

# ── 1: Compact banner ────────────────────────────────────────────────────

echo ""
echo "--- 1: Compact banner ---"

compact_banner=$(source_ui_and_run "NANOBK_COMPACT=1" "
  ui_banner 'v1.8.15' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$compact_banner" "NanoBK" "Compact banner: product name"
assert_contains "$compact_banner" "v1.8.15" "Compact banner: version"
assert_contains "$compact_banner" "Full Recommended" "Compact banner: subtitle"

# Compact banner should not have box drawing
assert_not_contains "$compact_banner" "╭" "Compact banner: no box top-left"
assert_not_contains "$compact_banner" "╯" "Compact banner: no box bottom-right"
assert_not_contains "$compact_banner" "│" "Compact banner: no box vertical"

# Compact banner should be shorter than default
default_banner=$(source_ui_and_run "" "
  ui_banner 'v1.8.15' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")
compact_lines=$(count_lines "$compact_banner")
default_lines=$(count_lines "$default_banner")
if [[ "$compact_lines" -lt "$default_lines" ]]; then
  pass "Compact banner: fewer lines ($compact_lines < $default_lines)"
else
  fail "Compact banner: expected fewer lines ($compact_lines >= $default_lines)"
fi

# Width guard
compact_max=$(echo "$compact_banner" | while IFS= read -r line; do printf '%s\n' "${#line}"; done | sort -rn | head -1)
if [[ "$compact_max" -le 90 ]]; then
  pass "Compact banner: width $compact_max <= 90"
else
  fail "Compact banner: width $compact_max > 90"
fi

# ── 2: Compact stage cards ───────────────────────────────────────────────

echo ""
echo "--- 2: Compact stage cards ---"

compact_cards=$(source_ui_and_run "NANOBK_COMPACT=1" "
  ui_stage_card_vps
  ui_stage_card_cloudflare
  ui_stage_card_bot
  ui_stage_card_web
  ui_stage_card_summary
")

assert_contains "$compact_cards" "VPS" "Compact cards: VPS"
assert_contains "$compact_cards" "HY2" "Compact cards: HY2"
assert_contains "$compact_cards" "TUIC" "Compact cards: TUIC"
assert_contains "$compact_cards" "Reality" "Compact cards: Reality"
assert_contains "$compact_cards" "Trojan" "Compact cards: Trojan"
assert_contains "$compact_cards" "Cloudflare" "Compact cards: Cloudflare"
assert_contains "$compact_cards" "nanok" "Compact cards: nanok"
assert_contains "$compact_cards" "nanob" "Compact cards: nanob"
assert_contains "$compact_cards" "Bot" "Compact cards: Bot"
assert_contains "$compact_cards" "控制端" "Compact cards: control plane"
assert_contains "$compact_cards" "Web" "Compact cards: Web"
assert_contains "$compact_cards" "Summary" "Compact cards: Summary"
assert_contains "$compact_cards" "planned / dry-run" "Compact cards: planned / dry-run"

# Compact cards should not have emoji or box drawing
if has_ansi "$compact_cards"; then
  fail "Compact cards: no ANSI"
else
  pass "Compact cards: no ANSI"
fi
assert_not_contains "$compact_cards" "✓" "Compact cards: no emoji"
assert_not_contains "$compact_cards" "╭" "Compact cards: no box drawing"

# Compact cards should be shorter than default
default_cards=$(source_ui_and_run "" "
  ui_stage_card_vps
  ui_stage_card_cloudflare
  ui_stage_card_bot
  ui_stage_card_web
  ui_stage_card_summary
")
compact_card_lines=$(count_lines "$compact_cards")
default_card_lines=$(count_lines "$default_cards")
if [[ "$compact_card_lines" -lt "$default_card_lines" ]]; then
  pass "Compact cards: fewer lines ($compact_card_lines < $default_card_lines)"
else
  fail "Compact cards: expected fewer lines ($compact_card_lines >= $default_card_lines)"
fi

# ── 3: Compact token reminder ────────────────────────────────────────────

echo ""
echo "--- 3: Compact token reminder ---"

compact_token=$(source_ui_and_run "NANOBK_COMPACT=1" "
  ui_token_reminder
")

assert_contains "$compact_token" "token" "Compact token: contains token"
assert_contains "$compact_token" "不要截图" "Compact token: contains do-not-screenshot"
assert_contains "$compact_token" "聊天" "Compact token: contains chat"
assert_contains "$compact_token" "当作密码保管" "Compact token: contains treat-as-password"
assert_contains "$compact_token" "revoke" "Compact token: contains revoke"
assert_contains "$compact_token" "regenerate" "Compact token: contains regenerate"
assert_not_contains "$compact_token" "不会出现在屏幕或日志中" "Compact token: no absolute promise"

if has_ansi "$compact_token"; then
  fail "Compact token: no ANSI"
else
  pass "Compact token: no ANSI"
fi

# ── 4: Compact recovery block ────────────────────────────────────────────

echo ""
echo "--- 4: Compact recovery block ---"

compact_recovery=$(source_ui_and_run "NANOBK_COMPACT=1" "
  ui_recovery_block 'bash installer/install.sh --mode vps --lang zh' 'bash bin/nanobk status'
")

assert_contains "$compact_recovery" "恢复" "Compact recovery: contains recovery label"
assert_contains "$compact_recovery" "installer/install.sh" "Compact recovery: contains installer command"
assert_contains "$compact_recovery" "nanobk status" "Compact recovery: contains nanobk command"
assert_not_contains "$compact_recovery" "TOKEN=" "Compact recovery: no TOKEN="
assert_not_contains "$compact_recovery" "SECRET=" "Compact recovery: no SECRET="

if has_ansi "$compact_recovery"; then
  fail "Compact recovery: no ANSI"
else
  pass "Compact recovery: no ANSI"
fi

# ── 5: Compact dry-run notice ────────────────────────────────────────────

echo ""
echo "--- 5: Compact dry-run notice ---"

compact_notice=$(source_ui_and_run "NANOBK_COMPACT=1" "
  ui_dry_run_notice
")

assert_contains "$compact_notice" "dry-run" "Compact notice: contains dry-run"
assert_contains "$compact_notice" "没有执行真实部署" "Compact notice: contains no-real-deploy"
assert_contains "$compact_notice" "No real deployment was performed" "Compact notice: contains EN notice"
assert_not_contains "$compact_notice" "success" "Compact notice: no success"

# ── 6: Full Wizard compact dry-run ───────────────────────────────────────

echo ""
echo "--- 6: Full Wizard compact dry-run ---"

wizard_compact=$(env NANOBK_COMPACT=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

assert_contains "$wizard_compact" "NanoBK" "Wizard compact: product name"
assert_contains "$wizard_compact" "planned / dry-run" "Wizard compact: planned / dry-run"
assert_contains "$wizard_compact" "没有执行真实部署" "Wizard compact: no-real-deploy"
assert_contains "$wizard_compact" "控制端" "Wizard compact: control plane"
assert_not_contains "$wizard_compact" "status:  success" "Wizard compact: no fake success"
assert_not_contains "$wizard_compact" "TOKEN=" "Wizard compact: no TOKEN="
assert_not_contains "$wizard_compact" "SECRET=" "Wizard compact: no SECRET="
assert_not_contains "$wizard_compact" "ADMIN_TOKEN=" "Wizard compact: no ADMIN_TOKEN="

# ── 7: Compact vs default line count ─────────────────────────────────────

echo ""
echo "--- 7: Compact vs default line count ---"

wizard_default=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

compact_wc=$(count_lines "$wizard_compact")
default_wc=$(count_lines "$wizard_default")
if [[ "$compact_wc" -le "$default_wc" ]]; then
  pass "Wizard compact: not more lines ($compact_wc <= $default_wc)"
else
  fail "Wizard compact: more lines than default ($compact_wc > $default_wc)"
fi

# ── 8: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-compact-mode-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-compact-mode-v1.8.sh"; then
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
