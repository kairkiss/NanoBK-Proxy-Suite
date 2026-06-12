#!/usr/bin/env bash
# v2.4.7 Closeout Manifest Test
#
# Validates the v2.4 closeout manifest and CHANGELOG entry.
# Static checks only. No real Cloudflare calls. No DNS mutation.
# No certificate request. No token rotation. No Worker mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# Locate manifest
MANIFEST=""
if [[ -f "$REPO_DIR/docs/v2.4-closeout-manifest.md" ]]; then
  MANIFEST="$REPO_DIR/docs/v2.4-closeout-manifest.md"
elif [[ -f "$REPO_DIR/docs/v2.4.7-closeout-manifest.md" ]]; then
  MANIFEST="$REPO_DIR/docs/v2.4.7-closeout-manifest.md"
fi

CHANGELOG="$REPO_DIR/CHANGELOG.md"

# ── Section A: File existence ──────────────────────────────────────────────

echo "=== Section A: File existence ==="

# 1. manifest exists
if [[ -n "$MANIFEST" ]] && [[ -f "$MANIFEST" ]]; then
  ok "1: closeout manifest exists"
else
  fail "1: closeout manifest missing"
fi

# 2. CHANGELOG has v2.4.7 entry
if grep -q "v2.4.7" "$CHANGELOG" 2>/dev/null; then
  ok "2: CHANGELOG has v2.4.7 entry"
else
  fail "2: CHANGELOG missing v2.4.7 entry"
fi

# ── Section B: Manifest content — stage coverage ───────────────────────────

echo ""
echo "=== Section B: Stage coverage ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section B: manifest not found"
else
  # 3. mentions v2.4.0 through v2.4.6
  for ver in v2.4.0 v2.4.1 v2.4.2 v2.4.3 v2.4.4 v2.4.5 v2.4.6; do
    if grep -q "$ver" "$MANIFEST"; then
      ok "3: manifest mentions $ver"
    else
      fail "3: manifest missing $ver"
    fi
  done
fi

# ── Section C: Manifest content — T22-2 and HEAD ──────────────────────────

echo ""
echo "=== Section C: T22-2 and HEAD ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section C: manifest not found"
else
  # 4. mentions T22-2
  if grep -q "T22-2" "$MANIFEST"; then
    ok "4: manifest mentions T22-2"
  else
    fail "4: manifest missing T22-2"
  fi

  # 5. mentions HEAD 85782c3
  if grep -q "85782c3" "$MANIFEST"; then
    ok "5: manifest mentions HEAD 85782c3"
  else
    fail "5: manifest missing HEAD 85782c3"
  fi

  # 6. mentions all six test RC=0
  for ver in v2.4.0 v2.4.1 v2.4.2 v2.4.3 v2.4.4 v2.4.5; do
    if grep -q "${ver}.*RC=0\|${ver}.*| 0 |" "$MANIFEST"; then
      ok "6: manifest records $ver test RC=0"
    else
      # Also accept if the test name appears with 0 in a table
      if grep -q "${ver}.*|.*0.*|.*PASS" "$MANIFEST"; then
        ok "6: manifest records $ver test RC=0"
      else
        fail "6: manifest missing $ver test RC=0"
      fi
    fi
  done
fi

# ── Section D: Safety invariants ───────────────────────────────────────────

echo ""
echo "=== Section D: Safety invariants ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section D: manifest not found"
else
  # 7. no DNS apply
  if grep -qi "no DNS apply\|no dns apply" "$MANIFEST"; then
    ok "7: manifest states no DNS apply"
  else
    fail "7: manifest missing no DNS apply"
  fi

  # 8. no cert issue
  if grep -qi "no certificate issue\|no cert issue\|No certificate issue" "$MANIFEST"; then
    ok "8: manifest states no cert issue"
  else
    fail "8: manifest missing no cert issue"
  fi

  # 9. no token rotation
  if grep -qi "no token rotation" "$MANIFEST"; then
    ok "9: manifest states no token rotation"
  else
    fail "9: manifest missing no token rotation"
  fi

  # 10. no Worker mutation
  if grep -qi "no Worker mutation" "$MANIFEST"; then
    ok "10: manifest states no Worker mutation"
  else
    fail "10: manifest missing no Worker mutation"
  fi

  # 11. no reload/restart
  if grep -qi "no.*reload.*restart\|no service reload" "$MANIFEST"; then
    ok "11: manifest states no reload/restart"
  else
    fail "11: manifest missing no reload/restart"
  fi

  # 12. no tag/release
  if grep -qi "no.*tag\|no.*release\|No tag\|No release" "$MANIFEST"; then
    ok "12: manifest states no tag/release"
  else
    fail "12: manifest missing no tag/release"
  fi
fi

# ── Section E: Exact confirmation phrases ──────────────────────────────────

echo ""
echo "=== Section E: Exact confirmation phrases ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section E: manifest not found"
else
  # 13. DNS phrase
  if grep -q "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" "$MANIFEST"; then
    ok "13a: manifest has DNS confirmation phrase"
  else
    fail "13a: manifest missing DNS confirmation phrase"
  fi

  # 13. Cert phrase
  if grep -q "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES" "$MANIFEST"; then
    ok "13b: manifest has cert confirmation phrase"
  else
    fail "13b: manifest missing cert confirmation phrase"
  fi

  # 13. Token phrase
  if grep -q "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" "$MANIFEST"; then
    ok "13c: manifest has token confirmation phrase"
  else
    fail "13c: manifest missing token confirmation phrase"
  fi
fi

# ── Section F: Gate authority and preview-only ─────────────────────────────

echo ""
echo "=== Section F: Gate authority ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section F: manifest not found"
else
  # 14. v2.3 gates remain authoritative
  if grep -qi "v2.3.*authoritative\|v2.3 gate.*authoritative\|v2.3 gates remain authoritative" "$MANIFEST"; then
    ok "14: manifest states v2.3 gates remain authoritative"
  else
    fail "14: manifest missing v2.3 gate authority"
  fi

  # 15. v2.4 wrappers are preview-only
  if grep -qi "preview.only\|preview-only" "$MANIFEST"; then
    ok "15: manifest states v2.4 wrappers are preview-only"
  else
    fail "15: manifest missing preview-only statement"
  fi
fi

# ── Section G: Non-blocking notes ──────────────────────────────────────────

echo ""
echo "=== Section G: Non-blocking notes ==="

if [[ -z "$MANIFEST" ]]; then
  fail "Skipping Section G: manifest not found"
else
  # 16. safety grep false positive note
  if grep -qi "false positive\|self-report\|test self-report" "$MANIFEST"; then
    ok "16: manifest documents safety grep false positive note"
  else
    fail "16: manifest missing safety grep false positive note"
  fi

  # 17. DNS wording polish note
  if grep -qi "DNS.*wording\|wording.*polish\|可能会被覆盖\|不会自动覆盖" "$MANIFEST"; then
    ok "17: manifest documents DNS wording polish note"
  else
    fail "17: manifest missing DNS wording polish note"
  fi

  # 18. NANOBK_RUN_LONG_REGRESSION opt-in
  if grep -q "NANOBK_RUN_LONG_REGRESSION" "$MANIFEST"; then
    ok "18: manifest documents NANOBK_RUN_LONG_REGRESSION opt-in"
  else
    fail "18: manifest missing NANOBK_RUN_LONG_REGRESSION opt-in"
  fi

  # 19. home --legacy-json note
  if grep -q "legacy-json\|--legacy-json" "$MANIFEST"; then
    ok "19: manifest documents home --legacy-json note"
  else
    fail "19: manifest missing home --legacy-json note"
  fi
fi

# ── Section H: Test does not call dangerous commands ───────────────────────

echo ""
echo "=== Section H: Test safety ==="

SELF="$0"
DANGEROUS_CALLS=$(grep -nE "^\s*(curl |wrangler |certbot |acme\.sh |systemctl reload|systemctl restart|cf dns apply|nanobk.*dns.*apply|nanobk.*cert.*issue|nanobk.*token.*rotate)" "$SELF" 2>/dev/null | grep -v '^\s*#' || true)

# 20. no live Cloudflare
if echo "$DANGEROUS_CALLS" | grep -qi "cloudflare\|cf dns\|api.cloudflare" 2>/dev/null; then
  fail "20: test calls live Cloudflare"
else
  ok "20: test does not call live Cloudflare"
fi

# 21. no DNS apply
if echo "$DANGEROUS_CALLS" | grep -qi "dns.*apply\|apply.*dns" 2>/dev/null; then
  fail "21: test calls DNS apply"
else
  ok "21: test does not call DNS apply"
fi

# 22. no cert issue
if echo "$DANGEROUS_CALLS" | grep -qi "cert.*issue\|issue.*cert" 2>/dev/null; then
  fail "22: test calls cert issue"
else
  ok "22: test does not call cert issue"
fi

# 23. no token rotate
if echo "$DANGEROUS_CALLS" | grep -qi "token.*rotate\|rotate.*token" 2>/dev/null; then
  fail "23: test calls token rotate"
else
  ok "23: test does not call token rotate"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=============================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL ${PASS} TESTS PASSED"
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
