#!/usr/bin/env bash
# NanoBK Proxy Suite — Validation Plan Test
#
# Verifies that --mode validate-plan outputs a complete validation plan
# without executing any real actions or writing files.
#
# Usage:
#   bash tests/unified-validation-plan.sh

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

contains() {
  local text="$1"
  local pattern="$2"
  if echo "$text" | grep -qi "$pattern"; then
    echo "1"
  else
    echo "0"
  fi
}

not_contains() {
  local text="$1"
  local pattern="$2"
  if echo "$text" | grep -qi "$pattern"; then
    echo "0"
  else
    echo "1"
  fi
}

echo "=== Validation Plan Test ==="
echo ""

# ── Test 1: validate-plan exits successfully ────────────────────────────────
echo "── Test 1: validate-plan mode ──"

EXIT_CODE=0
OUTPUT=$(bash "$INSTALLER" --mode validate-plan 2>&1) || EXIT_CODE=$?

check "exit code 0" "$([[ $EXIT_CODE -eq 0 ]] && echo 1 || echo 0)"

# ── Test 2: output contains required sections ───────────────────────────────
echo ""
echo "── Test 2: required sections ──"

check "contains Clean VPS" "$(contains "$OUTPUT" "Clean VPS")"
check "contains Full Wizard" "$(contains "$OUTPUT" "Full Wizard\|Full Recommended")"
check "contains human tester" "$(contains "$OUTPUT" "人工测试员\|human tester")"
check "contains dry-run disclaimer" "$(contains "$OUTPUT" "dry-run.*不能代表\|dry-run.*cannot claim")"
check "contains Bootstrap" "$(contains "$OUTPUT" "Bootstrap\|bootstrap")"
check "contains Cloudflare" "$(contains "$OUTPUT" "Cloudflare\|cloudflare")"
check "contains nanok" "$(contains "$OUTPUT" "nanok")"
check "contains nanob" "$(contains "$OUTPUT" "nanob")"
check "contains rotate tuic" "$(contains "$OUTPUT" "rotate.*tuic\|tuic.*rotate")"
check "contains healthcheck" "$(contains "$OUTPUT" "healthcheck\|Healthcheck")"
check "contains Phase 0" "$(contains "$OUTPUT" "Phase 0\|Baseline")"
check "contains Phase 10" "$(contains "$OUTPUT" "Phase 10\|Final Status")"
check "contains Pass Criteria" "$(contains "$OUTPUT" "Pass Criteria\|通过标准")"
check "contains Fail Criteria" "$(contains "$OUTPUT" "Fail Criteria\|失败标准")"

# ── Test 3: no real secrets ─────────────────────────────────────────────────
echo ""
echo "── Test 3: no real secrets ──"

check "no real tokens" "$(not_contains "$OUTPUT" "kairkiss314-")"
check "no real VPS IP" "$(not_contains "$OUTPUT" "62.60.250.69")"
check "no real workers.dev URL" "$(not_contains "$OUTPUT" "workers.dev/api/token")"

# ── Test 4: no file writes ──────────────────────────────────────────────────
echo ""
echo "── Test 4: no file writes ──"

rm -f "$REPO_DIR/bot/.env" "$REPO_DIR/web/.env"
bash "$INSTALLER" --mode validate-plan >/dev/null 2>&1 || true
check "does NOT write bot/.env" "$([[ ! -f "$REPO_DIR/bot/.env" ]] && echo 1 || echo 0)"
check "does NOT write web/.env" "$([[ ! -f "$REPO_DIR/web/.env" ]] && echo 1 || echo 0)"

# ── Test 5: no false claims ────────────────────────────────────────────────
echo ""
echo "── Test 5: no false claims ──"

check "no 'validation passed'" "$(not_contains "$OUTPUT" "validation passed")"
check "no 'production passed'" "$(not_contains "$OUTPUT" "production passed")"
check "no 'real VPS passed'" "$(not_contains "$OUTPUT" "real VPS passed")"
# Note: "不能代表真实 VPS 验收通过" is a negative disclaimer, not a false claim
check "has negative disclaimer about dry-run" "$(contains "$OUTPUT" "不能代表.*验收通过\|cannot claim.*validation")"

# ── Test 6: validation docs safety ──────────────────────────────────────────
echo ""
echo "── Test 6: validation docs safety ──"

DOC="$REPO_DIR/docs/validation-v1.6-clean-vps.md"
if [[ -f "$DOC" ]]; then
  # Check that cat .env is not in executable code blocks (only in warnings)
  DOC_CONTENT="$(cat "$DOC")"
  # Count occurrences - warnings say "Do NOT execute" which is safe
  CAT_BOT_COUNT=$(echo "$DOC_CONTENT" | grep -c "cat bot/.env" || true)
  CAT_WEB_COUNT=$(echo "$DOC_CONTENT" | grep -c "cat web/.env" || true)
  # Should only appear in warning lines (Do NOT execute), not in code examples
  check "cat bot/.env only in warnings" "$([[ $CAT_BOT_COUNT -le 1 ]] && echo 1 || echo 0)"
  check "cat web/.env only in warnings" "$([[ $CAT_WEB_COUNT -le 1 ]] && echo 1 || echo 0)"
  check "docs has TELEGRAM_BOT_TOKEN: present" "$(contains "$(cat "$DOC")" "TELEGRAM_BOT_TOKEN.*present")"
  check "docs has NANOBK_WEB_TOKEN: present" "$(contains "$(cat "$DOC")" "NANOBK_WEB_TOKEN.*present")"
  check "docs has NANOBK_WEB_SECRET_KEY: present" "$(contains "$(cat "$DOC")" "NANOBK_WEB_SECRET_KEY.*present")"
  check "docs has do-not-paste reminder" "$(contains "$(cat "$DOC")" "Do NOT paste\|不要.*paste\|不要.*粘贴")"
else
  check "validation doc exists" "0"
fi

# ── Test 7: validation-plan in installer test list ──────────────────────────
echo ""
echo "── Test 7: validation-plan in installer test list ──"

check "validation-plan in installer" "$(grep -q 'unified-validation-plan.sh' "$INSTALLER" 2>/dev/null && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
