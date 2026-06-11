#!/usr/bin/env bash
# v2.3.0 Inventory Contract Test
#
# Lightweight check that the v2.3 automation plan document exists
# and contains required sections. No Cloudflare calls, no mutation.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

DOC="docs/v2.3-cli-cf-automation-plan.md"

# 1. Plan document exists
if [[ -f "$DOC" ]]; then
  ok "Plan document exists: $DOC"
else
  fail "Plan document missing: $DOC"
fi

# 2. Contains v2.3.1 to v2.3.9
for v in v2.3.1 v2.3.2 v2.3.3 v2.3.4 v2.3.5 v2.3.6 v2.3.7 v2.3.8 v2.3.9; do
  if grep -q "$v" "$DOC" 2>/dev/null; then
    ok "Document contains $v"
  else
    fail "Document missing $v"
  fi
done

# 3. Contains "Brand CLI Console Shell"
if grep -q "Brand CLI Console Shell" "$DOC" 2>/dev/null; then
  ok "Document contains 'Brand CLI Console Shell'"
else
  fail "Document missing 'Brand CLI Console Shell'"
fi

# 4. Contains "DNS Apply Engine with Confirmation"
if grep -q "DNS Apply Engine with Confirmation" "$DOC" 2>/dev/null; then
  ok "Document contains 'DNS Apply Engine with Confirmation'"
else
  fail "Document missing 'DNS Apply Engine with Confirmation'"
fi

# 5. Contains "Certificate Automation"
if grep -q "Certificate Automation" "$DOC" 2>/dev/null; then
  ok "Document contains 'Certificate Automation'"
else
  fail "Document missing 'Certificate Automation'"
fi

# 6. Contains "Subscription Token Rotation"
if grep -q "Subscription Token Rotation" "$DOC" 2>/dev/null; then
  ok "Document contains 'Subscription Token Rotation'"
else
  fail "Document missing 'Subscription Token Rotation'"
fi

# 7. Contains "plan -> explain -> confirm -> apply -> verify"
if grep -q "plan.*explain.*confirm.*apply.*verify" "$DOC" 2>/dev/null; then
  ok "Document contains 'plan -> explain -> confirm -> apply -> verify'"
else
  fail "Document missing 'plan -> explain -> confirm -> apply -> verify'"
fi

# 8. States "No DNS mutation in v2.3.0"
if grep -qi "no dns mutation" "$DOC" 2>/dev/null; then
  ok "Document states no DNS mutation"
else
  fail "Document does not state no DNS mutation"
fi

# 9. States "Web/Bot remain read-only"
if grep -qi "web.*bot.*read.only\|read.only.*web.*bot" "$DOC" 2>/dev/null; then
  ok "Document states Web/Bot remain read-only"
else
  fail "Document does not state Web/Bot remain read-only"
fi

# 10. Key source files exist
for f in \
  bin/nanobk \
  installer/bootstrap.sh \
  installer/install-vps.sh \
  installer/install-cloudflare.sh \
  lib/nanobk_cf_zones.py \
  lib/nanobk_cf_dns_create_preflight.py \
  lib/nanobk_cf_dns_owner_smoke_create.py \
; do
  if [[ -f "$f" ]]; then
    ok "Key file exists: $f"
  else
    fail "Key file missing: $f"
  fi
done

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.0 inventory contract checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
