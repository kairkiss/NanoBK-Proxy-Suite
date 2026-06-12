#!/usr/bin/env bash
# v2.3.10 Closeout Manifest Test
#
# Verifies v2.3 closeout documentation, safety model, and regression coverage.
# No real DNS creation. No real certificate request. No real token rotation.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

MANIFEST="docs/v2.3-closeout-manifest.md"
ACCEPTANCE="docs/v2.3-real-vps-acceptance.md"
PLAN="docs/v2.3-cli-cf-automation-plan.md"

# 1. Manifest document exists
if [[ -f "$MANIFEST" ]]; then
  ok "docs/v2.3-closeout-manifest.md exists"
else
  fail "docs/v2.3-closeout-manifest.md missing"
fi

# 2. Acceptance document exists
if [[ -f "$ACCEPTANCE" ]]; then
  ok "docs/v2.3-real-vps-acceptance.md exists"
else
  fail "docs/v2.3-real-vps-acceptance.md missing"
fi

# 3. CHANGELOG has v2.3.10 entry
if grep -q "v2.3.10" CHANGELOG.md 2>/dev/null; then
  ok "CHANGELOG has v2.3.10 entry"
else
  fail "CHANGELOG missing v2.3.10 entry"
fi

# 4. Manifest contains all v2.3.0-v2.3.10 names
for ver in v2.3.0 v2.3.1 v2.3.2 v2.3.3 v2.3.4 v2.3.5 v2.3.6 v2.3.7 v2.3.8 v2.3.9 v2.3.10; do
  if grep -q "$ver" "$MANIFEST" 2>/dev/null; then
    ok "Manifest contains $ver"
  else
    fail "Manifest missing $ver"
  fi
done

# 5. Manifest contains all three exact confirmation phrases
for phrase in \
  "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" \
  "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES" \
  "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" \
; do
  if grep -qF "$phrase" "$MANIFEST" 2>/dev/null; then
    ok "Manifest contains confirmation phrase: ${phrase:0:30}..."
  else
    fail "Manifest missing confirmation phrase: ${phrase:0:30}..."
  fi
done

# 5b. Manifest contains correct head references
if grep -q "Final implementation head before closeout" "$MANIFEST" 2>/dev/null; then
  ok "Manifest contains 'Final implementation head before closeout'"
else
  fail "Manifest missing 'Final implementation head before closeout'"
fi
if grep -q "2cef31d" "$MANIFEST" 2>/dev/null; then
  ok "Manifest contains implementation head 2cef31d"
else
  fail "Manifest missing implementation head 2cef31d"
fi
if grep -q "Closeout manifest head" "$MANIFEST" 2>/dev/null; then
  ok "Manifest contains 'Closeout manifest head'"
else
  fail "Manifest missing 'Closeout manifest head'"
fi
if grep -q "9dbec7a" "$MANIFEST" 2>/dev/null; then
  ok "Manifest contains closeout head 9dbec7a"
else
  fail "Manifest missing closeout head 9dbec7a"
fi

# 6. Manifest says no release/tag in this commit
if grep -qi "no release/tag\|no tag.*release\|no release.*tag" "$MANIFEST" 2>/dev/null; then
  ok "Manifest states no release/tag"
else
  fail "Manifest does not state no release/tag"
fi

# 7. Manifest says owner approval required
if grep -qi "owner.*approval\|owner.*approves\|pending owner" "$MANIFEST" 2>/dev/null; then
  ok "Manifest states owner approval required"
else
  fail "Manifest does not state owner approval required"
fi

# 8. Manifest says production Worker protected
if grep -qi "production.*worker.*protected\|nanok.*blocked\|nanob.*blocked" "$MANIFEST" 2>/dev/null; then
  ok "Manifest states production Worker protected"
else
  fail "Manifest does not state production Worker protected"
fi

# 9. Manifest says no raw secrets
if grep -qi "no raw.*secret\|no raw.*token\|token.*masked" "$MANIFEST" 2>/dev/null; then
  ok "Manifest states no raw secrets"
else
  fail "Manifest does not state no raw secrets"
fi

# 10. Manifest says no Web/Bot behavior change
if grep -qi "no.*web.*bot.*behavior\|web.*bot.*unchanged\|no web/bot" "$MANIFEST" 2>/dev/null; then
  ok "Manifest states no Web/Bot behavior change"
else
  fail "Manifest does not state no Web/Bot behavior change"
fi

# 11. v2.3.9 acceptance uses explicit test file list, not glob
if grep -q 'REGRESSION_TESTS=(' tests/v2.3.9-real-vps-acceptance.sh 2>/dev/null; then
  ok "v2.3.9 acceptance uses explicit test file list"
else
  fail "v2.3.9 acceptance uses glob instead of explicit list"
fi

# 12. No tag/release automation in manifest/acceptance docs
TAG_AUTOMATION=$(grep -rnE "git tag|gh release|git push.*--tags" docs/v2.3-closeout-manifest.md docs/v2.3-real-vps-acceptance.md 2>/dev/null | grep -v 'must be manual' | grep -v 'no release' | grep -v 'No release/tag' | grep -v 'No tag/release' | grep -v 'tag/release' || true)
if [[ -z "$TAG_AUTOMATION" ]]; then
  ok "No tag/release automation in closeout docs"
else
  fail "Tag/release automation found: $TAG_AUTOMATION"
fi

# 13. Closeout test has no git tag command
if grep -qE "^\s*git tag" tests/v2.3.10-closeout-manifest.sh 2>/dev/null; then
  fail "Closeout test contains git tag command"
else
  ok "Closeout test has no git tag command"
fi

# 14. Closeout test has no gh release command
if grep -qE "^\s*gh release" tests/v2.3.10-closeout-manifest.sh 2>/dev/null; then
  fail "Closeout test contains gh release command"
else
  ok "Closeout test has no gh release command"
fi

# 15. Run v2.3.9 acceptance test
V239_OUT=$(bash tests/v2.3.9-real-vps-acceptance.sh 2>&1 || true)
if echo "$V239_OUT" | grep -q "All v2.3.9 real VPS acceptance checks passed"; then
  ok "v2.3.9 acceptance test passes"
else
  fail "v2.3.9 acceptance test failed"
  echo "$V239_OUT" | tail -5
fi

# 16-24. Run v2.3.8 through v2.3.0 tests
REGRESSION_TESTS=(
  "tests/v2.3.8-full-cli-setup-flow.sh"
  "tests/v2.3.7-token-rotation-gate.sh"
  "tests/v2.3.6-cert-issue-gate.sh"
  "tests/v2.3.5-cert-automation-preflight.sh"
  "tests/v2.3.4-dns-apply-engine.sh"
  "tests/v2.3.3-domain-ip-subdomain-planner.sh"
  "tests/v2.3.2-cloudflare-zone-onboarding.sh"
  "tests/v2.3.1-brand-cli-console-shell.sh"
  "tests/v2.3.0-inventory-contract.sh"
)

for tf in "${REGRESSION_TESTS[@]}"; do
  if [[ ! -f "$tf" ]]; then
    fail "$tf: file not found"
    continue
  fi
  TEST_OUT=$(bash "$tf" 2>&1 || true)
  if echo "$TEST_OUT" | grep -q "passed"; then
    ok "$(basename "$tf") passes"
  else
    fail "$(basename "$tf") failed"
    echo "$TEST_OUT" | tail -3
  fi
done

# 25. Optional v2.2.55/v2.2.56
for tf in tests/v2.2.55-closeout-regression.sh tests/v2.2.56-real-web-bot-bridge-fix.sh; do
  if [[ ! -f "$tf" ]]; then
    fail "$tf: file not found"
    continue
  fi
  TEST_OUT=$(bash "$tf" 2>&1 || true)
  if echo "$TEST_OUT" | grep -q "passed"; then
    ok "$(basename "$tf") passes"
  elif echo "$TEST_OUT" | grep -q "skipped.*Flask"; then
    ok "$(basename "$tf") passes (Flask not available, static checks only)"
  else
    fail "$(basename "$tf") failed"
  fi
done

# 26. No raw token/zone id/record id/api.cloudflare.com in generated outputs
# Check that no test fixture or doc leaks real secrets
LEAK_CHECK=""
for f in "$MANIFEST" "$ACCEPTANCE" docs/v2.3-cli-cf-automation-plan.md; do
  if [[ -f "$f" ]]; then
    LEAK_CHECK+="$(cat "$f" 2>/dev/null || true)"
  fi
done
LEAK_OK=1
for leak in "api.cloudflare.com/client/v4" "CF_API_TOKEN=" "SUB_TOKEN=" "ADMIN_TOKEN="; do
  if echo "$LEAK_CHECK" | grep -qi "$leak"; then
    fail "Documentation leaks: $leak"
    LEAK_OK=0
  fi
done
if [[ "$LEAK_OK" == "1" ]]; then
  ok "No raw secrets in documentation"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.10 closeout manifest checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
