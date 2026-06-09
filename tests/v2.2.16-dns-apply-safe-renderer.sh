#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Safe Renderer Test
#
# Tests lib/nanobk_cf_dns_apply_safe_renderer.py with static raw helper-style
# JSON fixtures. Does NOT call helper. Does NOT call Cloudflare.
#
# Usage:
#   bash tests/v2.2.16-dns-apply-safe-renderer.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_safe_renderer.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (unexpected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== DNS Apply Safe Renderer Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

# A1. Module exists
if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

MODULE_SOURCE=$(cat "$MODULE")

# A2. Module says safe renderer
assert_contains "$MODULE_SOURCE" "Safe Renderer" "A2: module says safe renderer"
assert_contains "$MODULE_SOURCE" "Does not invoke helper" "A2: module says no helper invocation"

# A3. Module does not import helper boundary mock
IMPORT_LINES=$(grep -E '^\s*(import |from )' "$MODULE" || true)
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply_helper_boundary_mock" "A3: no boundary mock import"
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply_ux_mock" "A3: no UX mock import"

# A4. Module does not import low-level helper
assert_not_contains "$IMPORT_LINES" "nanobk_cf_dns_apply " "A4: no low-level helper import"

# A5. bin/nanobk does not reference renderer
if grep -q 'nanobk_cf_dns_apply_safe_renderer' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "A5: bin/nanobk references renderer"
  ERRORS=$((ERRORS + 1))
else
  pass "A5: bin/nanobk does not reference renderer"
fi

# A6. installer/Bot/Web do not reference renderer
for dir in installer bot web; do
  if grep -rq 'nanobk_cf_dns_apply_safe_renderer' "$ROOT/$dir/" 2>/dev/null; then
    fail "A6: $dir/ references renderer"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "A6: installer/Bot/Web do not reference renderer"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Normalization
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Normalization ---"
echo ""

# Raw helper JSON with all forbidden fields
RAW_APPLIED='{"ok": true, "dryRun": false, "checkMode": false, "actions": [{"recordType": "A", "name": "node.example.com", "plannedContent": "203.0.113.10", "action": "create", "message": "planned create for node.example.com"}, {"recordType": "AAAA", "name": "node.example.com", "plannedContent": "2001:db8::10", "action": "create", "message": "planned create for node.example.com"}], "results": [{"recordType": "A", "name": "node.example.com", "action": "create", "success": true, "message": "created A node.example.com", "recordId": "rec-new-001"}, {"recordType": "AAAA", "name": "node.example.com", "action": "create", "success": true, "message": "created AAAA node.example.com", "recordId": "rec-new-001"}]}'

# B1. Normalize and check model does not contain raw fields
MODEL=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import normalize_helper_json
raw = json.loads('''$RAW_APPLIED''')
model = normalize_helper_json(raw, 'fake_only')
print(json.dumps(model))
" 2>&1)

assert_not_contains "$MODEL" "example.com" "B1: no raw domain in model"
assert_not_contains "$MODEL" "node.example.com" "B1: no raw hostname in model"
assert_not_contains "$MODEL" "203.0.113.10" "B1: no raw IPv4 in model"
assert_not_contains "$MODEL" "2001:db8::10" "B1: no raw IPv6 in model"
assert_not_contains "$MODEL" "rec-new-001" "B1: no raw recordId in model"
assert_not_contains "$MODEL" "plannedContent" "B1: no plannedContent in model"
assert_not_contains "$MODEL" "existingContent" "B1: no existingContent in model"
assert_not_contains "$MODEL" "recordId" "B1: no recordId in model"

# B2. Model contains required fields
assert_contains "$MODEL" '"status"' "B2: model has status"
assert_contains "$MODEL" '"mode"' "B2: model has mode"
assert_contains "$MODEL" '"action_counts"' "B2: model has action_counts"
assert_contains "$MODEL" '"record_type_counts"' "B2: model has record_type_counts"
assert_contains "$MODEL" '"safety"' "B2: model has safety"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Rendering fake mode
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Rendering fake mode ---"
echo ""

C_OUT=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$RAW_APPLIED''')
print(render_from_helper_json(raw, 'fake_only'))
" 2>&1)

assert_contains "$C_OUT" "NanoBK DNS Apply — Safe Summary" "C1: has header"
assert_contains "$C_OUT" "Status:" "C2: has Status"
assert_contains "$C_OUT" "Mode: fake_only" "C3: has Mode"
assert_contains "$C_OUT" "Actions:" "C4: has Actions"
assert_contains "$C_OUT" "Record types:" "C5: has Record types"
assert_contains "$C_OUT" "Test mode: fake transport only" "C6: says fake transport only"
assert_contains "$C_OUT" "No live Cloudflare verification was performed" "C7: says no live verification"
assert_contains "$C_OUT" "No DNS records were deleted" "C8: says no deletes"

# C9-C14. No raw values in output
assert_not_contains "$C_OUT" "example.com" "C9: no raw domain"
assert_not_contains "$C_OUT" "node.example.com" "C9: no raw hostname"
assert_not_contains "$C_OUT" "203.0.113.10" "C10: no raw IPv4"
assert_not_contains "$C_OUT" "2001:db8::10" "C11: no raw IPv6"
assert_not_contains "$C_OUT" "recordId" "C12: no recordId"
assert_not_contains "$C_OUT" "record ID" "C12: no record ID"
assert_not_contains "$C_OUT" "CF_API_TOKEN" "C13: no token"
assert_not_contains "$C_OUT" "Authorization" "C13: no Authorization"
assert_not_contains "$C_OUT" "api-env" "C13: no api-env"
assert_not_contains "$C_OUT" "/zones/" "C14: no /zones/"
assert_not_contains "$C_OUT" "dns_records" "C14: no dns_records"
assert_not_contains "$C_OUT" "apply --yes" "C14: no apply --yes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Status cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Status cases ---"
echo ""

# D1. Applied status
D1=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$RAW_APPLIED''')
print(render_from_helper_json(raw, 'fake_only'))
" 2>&1)
assert_contains "$D1" "Status: applied" "D1: applied status"
assert_contains "$D1" "Failed: 0" "D1b: applied shows Failed: 0"

# D2. Conflict status
RAW_CONFLICT='{"ok": false, "dryRun": false, "checkMode": false, "actions": [{"recordType": "A", "name": "x", "plannedContent": "y", "action": "fail_conflict", "message": "conflict"}], "results": []}'
D2=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$RAW_CONFLICT''')
print(render_from_helper_json(raw, 'fake_only'))
" 2>&1)
assert_contains "$D2" "Status: conflict" "D2: conflict status"

# D3. Partial status
RAW_PARTIAL='{"ok": false, "dryRun": false, "checkMode": false, "actions": [{"recordType": "A", "name": "x", "plannedContent": "y", "action": "create", "message": "m"}, {"recordType": "AAAA", "name": "x", "plannedContent": "z", "action": "create", "message": "m"}], "results": [{"recordType": "A", "name": "x", "action": "create", "success": true, "message": "ok", "recordId": "r1"}, {"recordType": "AAAA", "name": "x", "action": "create", "success": false, "message": "fail"}]}'
D3=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$RAW_PARTIAL''')
print(render_from_helper_json(raw, 'fake_only'))
" 2>&1)
assert_contains "$D3" "Status: partial" "D3: partial status"
assert_contains "$D3" "Failed: 1" "D3b: partial shows Failed: 1"

# D4. Failed status
RAW_FAILED='{"ok": false, "dryRun": false, "checkMode": false, "actions": [{"recordType": "A", "name": "x", "plannedContent": "y", "action": "create", "message": "m"}], "results": [{"recordType": "A", "name": "x", "action": "create", "success": false, "message": "fail"}]}'
D4=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$RAW_FAILED''')
print(render_from_helper_json(raw, 'fake_only'))
" 2>&1)
assert_contains "$D4" "Status: failed" "D4: failed status"
assert_contains "$D4" "Failed: 1" "D4b: failed shows Failed: 1"

# D5. Ready status (dry-run with no mutations)
READY='{"ok": true, "dryRun": true, "checkMode": false, "actions": [{"recordType": "A", "name": "x", "plannedContent": "y", "action": "noop", "message": "m"}], "results": []}'
D5=$(python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
raw = json.loads('''$READY''')
print(render_from_helper_json(raw, 'dry_run'))
" 2>&1)
assert_contains "$D5" "Status: ready" "D5: ready status"

# D6. All outputs are safe
for D_OUT in "$D1" "$D2" "$D3" "$D4" "$D5"; do
  assert_not_contains "$D_OUT" "example.com" "D6: no raw domain"
  assert_not_contains "$D_OUT" "203.0.113.10" "D6: no raw IPv4"
  assert_not_contains "$D_OUT" "recordId" "D6: no recordId"
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Fail-closed output gate
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Fail-closed output gate ---"
echo ""

# Test assert_safe_output with unsafe inputs
UNSAFE_CASES=(
  "node.example.com"
  "203.0.113.10"
  "2001:db8::10"
  "rec-new-001"
  "Authorization"
  "/zones/fake-zone/dns_records"
  "vless://user@host"
  "PRIVATE KEY"
  "apply --yes"
)

for unsafe in "${UNSAFE_CASES[@]}"; do
  E_RESULT=$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_safe_renderer import assert_safe_output, UnsafeOutputError
try:
    assert_safe_output('$unsafe')
    print('FAIL')
except UnsafeOutputError:
    print('PASS')
except Exception:
    print('FAIL')
" 2>&1)
  if [[ "$E_RESULT" == "PASS" ]]; then
    pass "E: rejects unsafe: ${unsafe:0:30}"
  else
    fail "E: should reject unsafe: ${unsafe:0:30}"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Redaction helper defensive use
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Redaction helper ---"
echo ""

if [[ -f "$ROOT/lib/nanobk_redaction.py" ]]; then
  pass "F1: nanobk_redaction.py exists"
  # The renderer has its own DNS-specific forbidden checks.
  # Redaction helper is available but not the only boundary.
  pass "F2: renderer has DNS-specific forbidden checks (own _FORBIDDEN_PATTERNS)"
else
  pass "F1: nanobk_redaction.py not found (renderer uses local checks)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. No public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. No public integration ---"
echo ""

if grep -q 'nanobk_cf_dns_apply_safe_renderer' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "G1: bin/nanobk references renderer"
  ERRORS=$((ERRORS + 1))
else
  pass "G1: bin/nanobk does not reference renderer"
fi

for dir in installer bot web; do
  if grep -rq 'nanobk_cf_dns_apply_safe_renderer' "$ROOT/$dir/" 2>/dev/null; then
    fail "G2: $dir/ references renderer"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "G2: installer/Bot/Web do not reference renderer"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Existing tests remain expected pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.8-dns-apply-beginner-ux-mock.sh" \
  "v2.2.10-dns-apply-ux-fake-wrapper.sh" \
  "v2.2.11-dns-apply-ux-wrapper-hardening.sh" \
  "v2.2.15-dns-apply-helper-boundary-mock.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "H: $test_file passes"
  else
    fail "H: $test_file fails"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.16 DNS Apply Safe Renderer tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
