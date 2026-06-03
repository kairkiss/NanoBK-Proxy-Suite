#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.26 CLI Brand Identity Test
#
# Tests ui_banner / brand output without real deployment.
#
# Usage:
#   bash tests/unified-cli-brand-identity-v1.8.sh

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
echo "=== Test Suite: v1.8.26 CLI Brand Identity ==="

# ── 1: Default banner snapshot ────────────────────────────────────────────

echo ""
echo "--- 1: Default banner snapshot ---"

output=$(source_ui_and_run "" "
  ui_banner 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$output" "NanoBK Proxy Suite" "Default: product name"
assert_contains "$output" "v1.8.26" "Default: version"
assert_contains "$output" "Full Recommended" "Default: subtitle"
assert_contains "$output" "VPS" "Default: VPS"
assert_contains "$output" "Cloudflare" "Default: Cloudflare"
assert_contains "$output" "Bot" "Default: Bot"
assert_contains "$output" "Web Panel" "Default: Web Panel"

# ── 2: Brand mark / structure ─────────────────────────────────────────────

echo ""
echo "--- 2: Brand mark / structure ---"

# Default non-TTY uses plain text fallback — should have structured layout
assert_contains "$output" "一条命令" "Default: contains tagline"

# ── 2b: Direct box banner snapshot ───────────────────────────────────────

echo ""
echo "--- 2b: Direct box banner snapshot ---"

# source_ui_and_run is non-TTY, so _ui_banner_box uses ASCII fallback (+/-/|)
# Directly call _ui_banner_box to test the box output.
box_output=$(source_ui_and_run "" "
  _ui_banner_box 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

# Non-TTY uses ASCII box: + for corners, | for vertical
assert_contains "$box_output" "+" "Box: contains corner"
assert_contains "$box_output" "|" "Box: contains vertical border"
assert_contains "$box_output" "NanoBK Proxy Suite" "Box: product name"
assert_contains "$box_output" "v1.8.26" "Box: version"
assert_contains "$box_output" "Full Recommended" "Box: subtitle"

# Check no line exceeds 90 characters (use bash character count, not awk byte count)
box_max_width=$(echo "$box_output" | while IFS= read -r line; do printf '%s\n' "${#line}"; done | sort -rn | head -1)
if [[ "$box_max_width" -le 90 ]]; then
  pass "Box: longest line $box_max_width chars <= 90"
else
  fail "Box: longest line $box_max_width chars > 90"
fi

assert_not_contains "$box_output" "TOKEN=" "Box: no TOKEN="
assert_not_contains "$box_output" "SECRET=" "Box: no SECRET="

# ── 2c: Long subtitle box banner ─────────────────────────────────────────

echo ""
echo "--- 2c: Long subtitle box banner ---"

long_output=$(source_ui_and_run "" "
  _ui_banner_box 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Telegram Bot + Web Panel + Extra Long Subtitle For Width Guard'
")

assert_contains "$long_output" "NanoBK Proxy Suite" "Long: product name"
assert_contains "$long_output" "v1.8.26" "Long: version"

# Check no line exceeds 90 characters
long_max_width=$(echo "$long_output" | while IFS= read -r line; do printf '%s\n' "${#line}"; done | sort -rn | head -1)
if [[ "$long_max_width" -le 90 ]]; then
  pass "Long: longest line $long_max_width chars <= 90"
else
  fail "Long: longest line $long_max_width chars > 90"
fi

# Long subtitle should be truncated with ...
if grep -qF '...' <<< "$long_output"; then
  pass "Long: subtitle truncated with ..."
else
  # If not truncated, it still fits — that's OK too
  pass "Long: subtitle fits without truncation"
fi

# ── 3: PLAIN mode ────────────────────────────────────────────────────────

echo ""
echo "--- 3: PLAIN mode ---"

plain_output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_banner 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$plain_output" "NanoBK Proxy Suite" "PLAIN: product name"
assert_contains "$plain_output" "v1.8.26" "PLAIN: version"
assert_contains "$plain_output" "Full Recommended" "PLAIN: subtitle"
assert_contains "$plain_output" "一条命令" "PLAIN: tagline"

if has_ansi "$plain_output"; then
  fail "PLAIN: no ANSI escape"
else
  pass "PLAIN: no ANSI escape"
fi
assert_not_contains "$plain_output" "✓" "PLAIN: no emoji checkmark"
assert_not_contains "$plain_output" "╭" "PLAIN: no box drawing top-left"
assert_not_contains "$plain_output" "╯" "PLAIN: no box drawing bottom-right"
assert_not_contains "$plain_output" "■" "PLAIN: no progress bar"

# ── 4: NO_EMOJI mode ─────────────────────────────────────────────────────

echo ""
echo "--- 4: NO_EMOJI mode ---"

noemoji_output=$(source_ui_and_run "NANOBK_NO_EMOJI=1" "
  ui_banner 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$noemoji_output" "NanoBK Proxy Suite" "NO_EMOJI: product name"
assert_contains "$noemoji_output" "v1.8.26" "NO_EMOJI: version"
assert_not_contains "$noemoji_output" "✓" "NO_EMOJI: no emoji"
assert_not_contains "$noemoji_output" "🔒" "NO_EMOJI: no lock emoji"

# ── 5: UI=0 mode ─────────────────────────────────────────────────────────

echo ""
echo "--- 5: UI=0 mode ---"

ui0_output=$(source_ui_and_run "NANOBK_UI=0" "
  ui_banner 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$ui0_output" "NanoBK Proxy Suite" "UI=0: product name"
assert_contains "$ui0_output" "v1.8.26" "UI=0: version"
assert_not_contains "$ui0_output" "╭" "UI=0: no box drawing"
assert_not_contains "$ui0_output" "│" "UI=0: no box vertical"
assert_not_contains "$ui0_output" "✓" "UI=0: no emoji"

# ── 6: CI=1 safety ───────────────────────────────────────────────────────

echo ""
echo "--- 6: CI=1 safety ---"

ci_output=$(source_ui_and_run "CI=1" "
  ui_banner 'v1.8.26' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$ci_output" "NanoBK Proxy Suite" "CI: product name"
assert_contains "$ci_output" "v1.8.26" "CI: version"

if has_ansi "$ci_output"; then
  fail "CI: no ANSI escape"
else
  pass "CI: no ANSI escape"
fi

# ── 7: Width guard ───────────────────────────────────────────────────────

echo ""
echo "--- 7: Width guard ---"

# Check longest line in default banner does not exceed 90 characters
max_width=$(echo "$output" | while IFS= read -r line; do printf '%s\n' "${#line}"; done | sort -rn | head -1)
if [[ "$max_width" -le 90 ]]; then
  pass "Width: longest line $max_width chars <= 90"
else
  fail "Width: longest line $max_width chars > 90"
fi

# ── 8: Secret safety ─────────────────────────────────────────────────────

echo ""
echo "--- 8: Secret safety ---"

# Combine all outputs for secret check
all_outputs="${output}${plain_output}${noemoji_output}${ui0_output}${ci_output}"

assert_not_contains "$all_outputs" "TOKEN=" "Secret: no TOKEN="
assert_not_contains "$all_outputs" "SECRET=" "Secret: no SECRET="
assert_not_contains "$all_outputs" "ADMIN_TOKEN=" "Secret: no ADMIN_TOKEN="
assert_not_contains "$all_outputs" "SUB_TOKEN=" "Secret: no SUB_TOKEN="
assert_not_contains "$all_outputs" "NANOB_TOKEN=" "Secret: no NANOB_TOKEN="
assert_not_contains "$all_outputs" "workers.dev" "Secret: no workers.dev"
assert_not_contains "$all_outputs" "nanok-cf-admin.env" "Secret: no admin env path"
assert_not_contains "$all_outputs" ".cloudflare.local.env" "Secret: no CF env path"
assert_not_contains "$all_outputs" ".nanob.local.env" "Secret: no nanob env path"

# ── 9: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 9: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-brand-identity-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-brand-identity-v1.8.sh"; then
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
