#!/usr/bin/env bash
# NanoBK Proxy Suite — Runbook Guardrails Test
#
# Tests that runbook/guard docs contain required guardrail wording.
# Local-only. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.48-runbook-guardrails.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNBOOK="$ROOT/docs/runbooks/v2.2.48-operator-controlled-dns-create-runbook.md"
GUARDDOC="$ROOT/docs/validation/v2.2.48-production-apply-is-still-blocked.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Runbook Guardrails Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Docs exist
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Docs exist ---"
echo ""

if [[ -f "$RUNBOOK" ]]; then
  pass "A1: runbook exists"
else
  fail "A1: runbook missing"
  ERRORS=$((ERRORS + 1))
fi

if [[ -f "$GUARDDOC" ]]; then
  pass "A2: guard doc exists"
else
  fail "A2: guard doc missing"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Runbook contains required guardrails
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Runbook required content ---"
echo ""

for pattern in "nanobk-smoke-" "cleanup" "post-check" "leftover" "record ID" "raw API response" \
  "Bot/Web/installer" "Full Wizard" "scanner"; do
  if grep -qi "$pattern" "$RUNBOOK" 2>/dev/null; then
    pass "B: runbook contains '$pattern'"
  else
    fail "B: runbook missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

if grep -qEi "production proxy/web DNS creation remains blocked|does not enable production" "$RUNBOOK" 2>/dev/null; then
  pass "B: runbook contains 'production blocked / does not enable'"
else
  fail "B: runbook missing 'production blocked / does not enable'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Guard doc contains required guardrails
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Guard doc required content ---"
echo ""

for pattern in "production proxy/web" "remains blocked\|not enabled" "Bot/Web/installer" \
  "Full Wizard" "T20-7" "disposable"; do
  if grep -qi "$pattern" "$GUARDDOC" 2>/dev/null; then
    pass "C: guard doc contains '$pattern'"
  else
    fail "C: guard doc missing '$pattern'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. No dangerous positive language in docs
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. No dangerous positive language ---"
echo ""

DANGEROUS_PHRASES=(
  "production apply is enabled"
  "beginner console live create"
  "Bot live create"
  "Web live create"
  "installer live create"
  "auto-apply DNS"
)

ALL_DOCS="$RUNBOOK $GUARDDOC"

for phrase in "${DANGEROUS_PHRASES[@]}"; do
  if echo "$ALL_DOCS" | cat | grep -qi "$phrase" 2>/dev/null; then
    fail "D: dangerous phrase found: '$phrase'"
    ERRORS=$((ERRORS + 1))
  else
    pass "D: no '$phrase'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Promotion rule documented
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Promotion rule ---"
echo ""

if grep -qEi "T20-7.*does.*not.*authorize|Passing T20-7.*does.*not|does.*not.*authorize production" "$RUNBOOK" 2>/dev/null; then
  pass "E1: promotion rule in runbook"
else
  fail "E1: promotion rule missing from runbook"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Format sanity checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Format sanity checks ---"
echo ""

RUNBOOK_LINES=$(wc -l < "$RUNBOOK")
GUARD_LINES=$(wc -l < "$GUARDDOC")
SELF_LINES=$(wc -l < "$0")

if [[ "$RUNBOOK_LINES" -ge 80 ]]; then
  pass "F1: runbook has $RUNBOOK_LINES lines (>= 80)"
else
  fail "F1: runbook has only $RUNBOOK_LINES lines (expected >= 80)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$GUARD_LINES" -ge 30 ]]; then
  pass "F2: production-blocked doc has $GUARD_LINES lines (>= 30)"
else
  fail "F2: production-blocked doc has only $GUARD_LINES lines (expected >= 30)"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$SELF_LINES" -ge 80 ]]; then
  pass "F3: this test script has $SELF_LINES lines (>= 80)"
else
  fail "F3: this test script has only $SELF_LINES lines (expected >= 80)"
  ERRORS=$((ERRORS + 1))
fi

if head -1 "$0" | grep -q "#!/usr/bin/env bash"; then
  pass "F4: test script has shebang"
else
  fail "F4: test script missing shebang"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "set -Eeuo pipefail" "$0"; then
  pass "F5: test script has set -Eeuo pipefail"
else
  fail "F5: test script missing set -Eeuo pipefail"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.48 Runbook Guardrails tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
