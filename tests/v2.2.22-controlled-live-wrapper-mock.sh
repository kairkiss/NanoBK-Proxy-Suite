#!/usr/bin/env bash
# NanoBK Proxy Suite — Controlled Live Wrapper Mock Test
#
# Tests lib/nanobk_cf_dns_apply_controlled_live_wrapper_mock.py with
# safe static fixtures. Does NOT call Cloudflare. Does NOT call helper.
#
# Usage:
#   bash tests/v2.2.22-controlled-live-wrapper-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_controlled_live_wrapper_mock.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.22"

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
echo "=== Controlled Live Wrapper Mock Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

MODULE_SOURCE=$(cat "$MODULE")

if [[ -d "$FIXTURES" ]]; then
  pass "A2: fixture directory exists"
else
  fail "A2: fixture directory does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$MODULE_SOURCE" "Pure mock" "A3: module says pure mock"
assert_contains "$MODULE_SOURCE" "Does not call Cloudflare" "A4: no Cloudflare"
assert_contains "$MODULE_SOURCE" "Does not call helper" "A4: no helper"
assert_contains "$MODULE_SOURCE" "Does not read real env" "A4: no env reading"
assert_contains "$MODULE_SOURCE" "Does not mutate DNS" "A4: no DNS mutation"
assert_not_contains "$MODULE_SOURCE" "public CLI" "A5: no public CLI wording"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_wrapper_mock' "$loc" 2>/dev/null; then
    fail "A6: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "A6: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Fixture safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Fixture safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  content=$(cat "$fixture_file")

  assert_not_contains "$content" "example.com" "B: $fname no example.com"
  assert_not_contains "$content" "203.0.113" "B: $fname no IPv4"
  assert_not_contains "$content" "2001:db8" "B: $fname no IPv6"
  assert_not_contains "$content" "recordId" "B: $fname no recordId"
  assert_not_contains "$content" "Zone ID" "B: $fname no Zone ID"
  assert_not_contains "$content" "Account ID" "B: $fname no Account ID"
  assert_not_contains "$content" "Authorization" "B: $fname no Authorization"
  assert_not_contains "$content" "CF_API_TOKEN" "B: $fname no token"
  assert_not_contains "$content" "workers.dev" "B: $fname no workers.dev"
  assert_not_contains "$content" "vless://" "B: $fname no vless://"
  assert_not_contains "$content" "PRIVATE KEY" "B: $fname no PRIVATE KEY"
  assert_not_contains "$content" "apply --yes" "B: $fname no apply --yes"

  if echo "$content" | grep -qE '[a-f0-9]{64}'; then
    fail "B: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "B: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Wrapper evaluation cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Wrapper evaluation cases ---"
echo ""

evaluate_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_wrapper_mock import run_controlled_live_wrapper_mock
with open('$fixture') as f:
    data = json.load(f)
model = run_controlled_live_wrapper_mock(data)
print(json.dumps(model))
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_wrapper_mock import run_controlled_live_wrapper_mock, render_controlled_live_wrapper_summary
with open('$fixture') as f:
    data = json.load(f)
model = run_controlled_live_wrapper_mock(data)
print(render_controlled_live_wrapper_summary(model))
" 2>&1
}

# C1. mock_verified_placeholder -> mock_verified
C1=$(evaluate_fixture "$FIXTURES/mock_verified_placeholder.json")
C1_STATUS=$(echo "$C1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$C1_STATUS" == "mock_verified" ]]; then
  pass "C1: mock_verified_placeholder -> mock_verified"
else
  fail "C1: expected mock_verified, got '$C1_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

# C2. blocked_dirty_repo -> blocked + repo gate failed
C2=$(evaluate_fixture "$FIXTURES/blocked_dirty_repo.json")
C2_STATUS=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C2_REASONS=$(echo "$C2" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C2_STATUS" == "blocked" ]] && [[ "$C2_REASONS" == *"repo gate failed"* ]]; then
  pass "C2: blocked_dirty_repo -> blocked + repo gate failed"
else
  fail "C2: expected blocked + repo gate failed, got '$C2_STATUS' '$C2_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C3. blocked_unexpected_head -> blocked + repo gate failed
C3=$(evaluate_fixture "$FIXTURES/blocked_unexpected_head.json")
C3_STATUS=$(echo "$C3" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C3_REASONS=$(echo "$C3" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C3_STATUS" == "blocked" ]] && [[ "$C3_REASONS" == *"repo gate failed"* ]]; then
  pass "C3: blocked_unexpected_head -> blocked + repo gate failed"
else
  fail "C3: expected blocked + repo gate failed, got '$C3_STATUS' '$C3_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C4. blocked_bad_credential_permission -> blocked + credential gate failed
C4=$(evaluate_fixture "$FIXTURES/blocked_bad_credential_permission.json")
C4_STATUS=$(echo "$C4" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C4_REASONS=$(echo "$C4" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C4_STATUS" == "blocked" ]] && [[ "$C4_REASONS" == *"credential gate failed"* ]]; then
  pass "C4: blocked_bad_credential_permission -> blocked + credential gate failed"
else
  fail "C4: expected blocked + credential gate failed, got '$C4_STATUS' '$C4_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C5. blocked_unsafe_identity -> blocked + identity gate failed
C5=$(evaluate_fixture "$FIXTURES/blocked_unsafe_identity.json")
C5_STATUS=$(echo "$C5" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C5_REASONS=$(echo "$C5" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C5_STATUS" == "blocked" ]] && [[ "$C5_REASONS" == *"identity gate failed"* ]]; then
  pass "C5: blocked_unsafe_identity -> blocked + identity gate failed"
else
  fail "C5: expected blocked + identity gate failed, got '$C5_STATUS' '$C5_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C6. blocked_unmanaged_existing_record -> blocked + pre-check gate failed
C6=$(evaluate_fixture "$FIXTURES/blocked_unmanaged_existing_record.json")
C6_STATUS=$(echo "$C6" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C6_REASONS=$(echo "$C6" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C6_STATUS" == "blocked" ]] && [[ "$C6_REASONS" == *"pre-check gate failed"* ]]; then
  pass "C6: blocked_unmanaged_existing_record -> blocked + pre-check gate failed"
else
  fail "C6: expected blocked + pre-check gate failed, got '$C6_STATUS' '$C6_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C7. blocked_cname_conflict -> blocked + pre-check gate failed
C7=$(evaluate_fixture "$FIXTURES/blocked_cname_conflict.json")
C7_STATUS=$(echo "$C7" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C7_REASONS=$(echo "$C7" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C7_STATUS" == "blocked" ]] && [[ "$C7_REASONS" == *"pre-check gate failed"* ]]; then
  pass "C7: blocked_cname_conflict -> blocked + pre-check gate failed"
else
  fail "C7: expected blocked + pre-check gate failed, got '$C7_STATUS' '$C7_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C8. blocked_missing_approval -> blocked + owner approval gate failed
C8=$(evaluate_fixture "$FIXTURES/blocked_missing_approval.json")
C8_STATUS=$(echo "$C8" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C8_REASONS=$(echo "$C8" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C8_STATUS" == "blocked" ]] && [[ "$C8_REASONS" == *"owner approval gate failed"* ]]; then
  pass "C8: blocked_missing_approval -> blocked + owner approval gate failed"
else
  fail "C8: expected blocked + owner approval gate failed, got '$C8_STATUS' '$C8_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C9. blocked_helper_capture_failure -> blocked + helper capture gate failed
C9=$(evaluate_fixture "$FIXTURES/blocked_helper_capture_failure.json")
C9_STATUS=$(echo "$C9" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C9_REASONS=$(echo "$C9" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C9_STATUS" == "blocked" ]] && [[ "$C9_REASONS" == *"helper capture gate failed"* ]]; then
  pass "C9: blocked_helper_capture_failure -> blocked + helper capture gate failed"
else
  fail "C9: expected blocked + helper capture gate failed, got '$C9_STATUS' '$C9_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C10. blocked_helper_schema_failure -> blocked + helper JSON gate failed
C10=$(evaluate_fixture "$FIXTURES/blocked_helper_schema_failure.json")
C10_STATUS=$(echo "$C10" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C10_REASONS=$(echo "$C10" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C10_STATUS" == "blocked" ]] && [[ "$C10_REASONS" == *"helper JSON gate failed"* ]]; then
  pass "C10: blocked_helper_schema_failure -> blocked + helper JSON gate failed"
else
  fail "C10: expected blocked + helper JSON gate failed, got '$C10_STATUS' '$C10_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C11. blocked_postcheck_unavailable -> blocked + post-check gate failed
C11=$(evaluate_fixture "$FIXTURES/blocked_postcheck_unavailable.json")
C11_STATUS=$(echo "$C11" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C11_REASONS=$(echo "$C11" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C11_STATUS" == "blocked" ]] && [[ "$C11_REASONS" == *"post-check gate failed"* ]]; then
  pass "C11: blocked_postcheck_unavailable -> blocked + post-check gate failed"
else
  fail "C11: expected blocked + post-check gate failed, got '$C11_STATUS' '$C11_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C12. blocked_final_redaction_failure -> blocked + final redaction gate failed
C12=$(evaluate_fixture "$FIXTURES/blocked_final_redaction_failure.json")
C12_STATUS=$(echo "$C12" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C12_REASONS=$(echo "$C12" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C12_STATUS" == "blocked" ]] && [[ "$C12_REASONS" == *"final redaction gate failed"* ]]; then
  pass "C12: blocked_final_redaction_failure -> blocked + final redaction gate failed"
else
  fail "C12: expected blocked + final redaction gate failed, got '$C12_STATUS' '$C12_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C13. blocked_public_ux_enabled -> blocked + public UX gate failed
C13=$(evaluate_fixture "$FIXTURES/blocked_public_ux_enabled.json")
C13_STATUS=$(echo "$C13" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C13_REASONS=$(echo "$C13" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C13_STATUS" == "blocked" ]] && [[ "$C13_REASONS" == *"public UX gate failed"* ]]; then
  pass "C13: blocked_public_ux_enabled -> blocked + public UX gate failed"
else
  fail "C13: expected blocked + public UX gate failed, got '$C13_STATUS' '$C13_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C14. uncertain_classifier -> uncertain
C14=$(evaluate_fixture "$FIXTURES/uncertain_classifier.json")
C14_STATUS=$(echo "$C14" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$C14_STATUS" == "uncertain" ]]; then
  pass "C14: uncertain_classifier -> uncertain"
else
  fail "C14: expected uncertain, got '$C14_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

# C15. blocked_multi_gate_first_failure -> blocked + first_failed_gate == repo_gate
C15=$(evaluate_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
C15_STATUS=$(echo "$C15" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C15_FIRST_GATE=$(echo "$C15" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
C15_FIRST_REASON=$(echo "$C15" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_blocked_reason'])")
C15_BLOCKED=$(echo "$C15" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
C15_DIAG=$(echo "$C15" | python3 -c "import sys,json; r=json.load(sys.stdin).get('diagnostic_blocked_reasons',[]); print(len(r))")
if [[ "$C15_STATUS" == "blocked" ]] && [[ "$C15_FIRST_GATE" == "repo_gate" ]] && [[ "$C15_FIRST_REASON" == "repo gate failed" ]]; then
  pass "C15: blocked_multi_gate_first_failure -> blocked + first_failed_gate=repo_gate"
else
  fail "C15: expected blocked + repo_gate, got '$C15_STATUS' '$C15_FIRST_GATE' '$C15_FIRST_REASON'"
  ERRORS=$((ERRORS + 1))
fi

# C16. blocked_reasons contains only first reason (not multiple)
C15_BLOCKED_COUNT=$(echo "$C15" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
if [[ "$C15_BLOCKED_COUNT" == "1" ]]; then
  pass "C16: blocked_reasons contains only first reason (1 item)"
else
  fail "C16: blocked_reasons should contain only 1 reason, got $C15_BLOCKED_COUNT"
  ERRORS=$((ERRORS + 1))
fi

# C17. diagnostic_blocked_reasons may include multiple reasons
if [[ "$C15_DIAG" -gt 1 ]]; then
  pass "C17: diagnostic_blocked_reasons has $C15_DIAG reasons"
else
  fail "C17: diagnostic_blocked_reasons should have multiple reasons, got $C15_DIAG"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Semantic locks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Semantic locks ---"
echo ""

# D1-D8. Mock verified fixture output checks
D1_OUT=$(render_fixture "$FIXTURES/mock_verified_placeholder.json")
assert_contains "$D1_OUT" "Status: mock_verified" "D1: mock verified status"
assert_contains "$D1_OUT" "Mode: placeholder_only" "D2: placeholder_only mode"
assert_contains "$D1_OUT" "Mock verified only" "D3: mock verified only"
assert_contains "$D1_OUT" "Live Cloudflare called: no" "D4: live cloudflare called: no"
assert_contains "$D1_OUT" "Real DNS mutation performed: no" "D5: real dns mutation: no"
assert_contains "$D1_OUT" "Real env read: no" "D6: real env read: no"
assert_contains "$D1_OUT" "Public apply allowed: no" "D7: public apply allowed: no"
assert_contains "$D1_OUT" "Requires owner-approved future live test: yes" "D8: requires future test: yes"

# D9-D10. Blocked fixture output checks
D9_OUT=$(render_fixture "$FIXTURES/blocked_dirty_repo.json")
assert_contains "$D9_OUT" "Status: blocked" "D9: blocked status"
assert_contains "$D9_OUT" "repo gate failed" "D10: safe generic reason"
assert_not_contains "$D9_OUT" "clean" "D11: no raw field name in output"

# D12. Uncertain fixture output
D12_OUT=$(render_fixture "$FIXTURES/uncertain_classifier.json")
assert_contains "$D12_OUT" "Status: uncertain" "D12: uncertain status"
assert_not_contains "$D12_OUT" "mock_verified" "D13: no mock_verified in uncertain output"

# D14-D19. Multi-gate first failure fixture output checks
D14_OUT=$(render_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
assert_contains "$D14_OUT" "Status: blocked" "D14: multi-gate blocked status"
assert_contains "$D14_OUT" "First failed gate: repo_gate" "D15: first failed gate shown"
assert_contains "$D14_OUT" "First blocked reason: repo gate failed" "D16: first blocked reason shown"
assert_not_contains "$D14_OUT" "credential gate failed" "D17: no credential reason in output"
assert_not_contains "$D14_OUT" "owner approval gate failed" "D18: no approval reason in output"
assert_not_contains "$D14_OUT" "helper JSON gate failed" "D19: no helper JSON reason in output"
assert_not_contains "$D14_OUT" "final redaction gate failed" "D20: no redaction reason in output"
assert_not_contains "$D14_OUT" "permission_600" "D21: no raw field name in output"
assert_not_contains "$D14_OUT" "exact_phrase_matched" "D22: no raw field name in output"
assert_not_contains "$D14_OUT" "schema_ok" "D23: no raw field name in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Fail-closed ordering
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Fail-closed ordering ---"
echo ""

# E1. Dirty repo fails at repo gate
E1_MODEL=$(evaluate_fixture "$FIXTURES/blocked_dirty_repo.json")
E1_REPO=$(echo "$E1_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['steps']['repo_gate'])")
E1_HELPER=$(echo "$E1_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['steps']['helper_capture'])")
if [[ "$E1_REPO" == "fail" ]]; then
  pass "E1: dirty repo fails at repo gate"
else
  fail "E1: dirty repo should fail at repo gate"
  ERRORS=$((ERRORS + 1))
fi

# E2. Missing approval fails before helper capture
E2_MODEL=$(evaluate_fixture "$FIXTURES/blocked_missing_approval.json")
E2_APPROVAL=$(echo "$E2_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['steps']['approval_gate'])")
if [[ "$E2_APPROVAL" == "fail" ]]; then
  pass "E2: missing approval fails before helper capture"
else
  fail "E2: missing approval should fail"
  ERRORS=$((ERRORS + 1))
fi

# E3. Helper schema failure blocks postcheck verified
E3_MODEL=$(evaluate_fixture "$FIXTURES/blocked_helper_schema_failure.json")
E3_STATUS=$(echo "$E3_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$E3_STATUS" == "blocked" ]]; then
  pass "E3: helper schema failure blocks output"
else
  fail "E3: helper schema failure should block"
  ERRORS=$((ERRORS + 1))
fi

# E4. Final redaction failure blocks output
E4_MODEL=$(evaluate_fixture "$FIXTURES/blocked_final_redaction_failure.json")
E4_STATUS=$(echo "$E4_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$E4_STATUS" == "blocked" ]]; then
  pass "E4: final redaction failure blocks output"
else
  fail "E4: final redaction failure should block"
  ERRORS=$((ERRORS + 1))
fi

# E5. Multi-gate fixture first failure is repo gate
E5_MODEL=$(evaluate_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
E5_FIRST=$(echo "$E5_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$E5_FIRST" == "repo_gate" ]]; then
  pass "E5: multi-gate first failure is repo_gate"
else
  fail "E5: multi-gate first failure should be repo_gate, got '$E5_FIRST'"
  ERRORS=$((ERRORS + 1))
fi

# E6. Dirty repo first failure is repo gate
E6_MODEL=$(evaluate_fixture "$FIXTURES/blocked_dirty_repo.json")
E6_FIRST=$(echo "$E6_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$E6_FIRST" == "repo_gate" ]]; then
  pass "E6: dirty repo first failure is repo_gate"
else
  fail "E6: dirty repo first failure should be repo_gate, got '$E6_FIRST'"
  ERRORS=$((ERRORS + 1))
fi

# E7. Missing approval first failure is approval gate
E7_MODEL=$(evaluate_fixture "$FIXTURES/blocked_missing_approval.json")
E7_FIRST=$(echo "$E7_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$E7_FIRST" == "approval_gate" ]]; then
  pass "E7: missing approval first failure is approval_gate"
else
  fail "E7: missing approval first failure should be approval_gate, got '$E7_FIRST'"
  ERRORS=$((ERRORS + 1))
fi

# E8. Helper schema first failure is helper_json_gate
E8_MODEL=$(evaluate_fixture "$FIXTURES/blocked_helper_schema_failure.json")
E8_FIRST=$(echo "$E8_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$E8_FIRST" == "helper_json_gate" ]]; then
  pass "E8: helper schema first failure is helper_json_gate"
else
  fail "E8: helper schema first failure should be helper_json_gate, got '$E8_FIRST'"
  ERRORS=$((ERRORS + 1))
fi

# E9. Final redaction first failure is final_redaction_gate
E9_MODEL=$(evaluate_fixture "$FIXTURES/blocked_final_redaction_failure.json")
E9_FIRST=$(echo "$E9_MODEL" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$E9_FIRST" == "final_redaction_gate" ]]; then
  pass "E9: final redaction first failure is final_redaction_gate"
else
  fail "E9: final redaction first failure should be final_redaction_gate, got '$E9_FIRST'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Output safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  out=$(render_fixture "$fixture_file")

  assert_not_contains "$out" "example.com" "F: $fname no example.com"
  assert_not_contains "$out" "203.0.113" "F: $fname no IPv4"
  assert_not_contains "$out" "2001:db8" "F: $fname no IPv6"
  assert_not_contains "$out" "recordId" "F: $fname no recordId"
  assert_not_contains "$out" "Zone ID" "F: $fname no Zone ID"
  assert_not_contains "$out" "Account ID" "F: $fname no Account ID"
  assert_not_contains "$out" "Authorization" "F: $fname no Authorization"
  assert_not_contains "$out" "CF_API_TOKEN" "F: $fname no token"
  assert_not_contains "$out" "workers.dev" "F: $fname no workers.dev"
  assert_not_contains "$out" "vless://" "F: $fname no vless://"
  assert_not_contains "$out" "PRIVATE KEY" "F: $fname no PRIVATE KEY"
  assert_not_contains "$out" "apply --yes" "F: $fname no apply --yes"

  if echo "$out" | grep -qE '[a-f0-9]{64}'; then
    fail "F: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "F: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. No network / no public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. No network / no public integration ---"
echo ""

assert_not_contains "$MODULE_SOURCE" "import requests" "G1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "G1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "G1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "G1: no socket"
assert_not_contains "$MODULE_SOURCE" "import subprocess" "G1: no subprocess"
assert_not_contains "$MODULE_SOURCE" "import os" "G1: no os"
assert_not_contains "$MODULE_SOURCE" "import pathlib" "G1: no pathlib"
assert_not_contains "$MODULE_SOURCE" "import curl" "G1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "G1: no wrangler"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_wrapper_mock' "$loc" 2>/dev/null; then
    fail "G2: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "G2: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh" \
  "v2.2.20-controlled-live-gate-contract.sh" \
  "v2.2.21-controlled-live-gate-placeholder-mock.sh"; do
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
  echo -e "  ${GREEN}All v2.2.22 Controlled Live Wrapper Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
