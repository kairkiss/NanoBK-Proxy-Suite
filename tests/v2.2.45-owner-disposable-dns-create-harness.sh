#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner Disposable DNS Create Harness Test
#
# Tests the owner-approved disposable DNS create smoke harness.
# Uses NANOBK_OWNER_SMOKE_FAKE_MAP for mock. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.45-owner-disposable-dns-create-harness.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_owner_smoke_create.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.45"

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

CONFIRM="I UNDERSTAND THIS WILL CREATE AND DELETE ONE DISPOSABLE CLOUDFLARE DNS RECORD"

chmod 600 "$FIXTURES/safe_api_env.env"
chmod 644 "$FIXTURES/unsafe_world_readable_api_env.env"

echo ""
echo "=== Owner Disposable DNS Create Harness Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Missing owner approval
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Missing owner approval ---"
echo ""

A_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && A_RC=0 || A_RC=$?

if [[ "$A_RC" != "0" ]]; then
  pass "A1: missing approval exits non-zero ($A_RC)"
else
  fail "A1: missing approval should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$A_JSON" "owner_approval_required" "A2: reason owner_approval_required"
assert_contains "$A_JSON" '"mutation_allowed": false' "A3: mutation false"
assert_not_contains "$A_JSON" "fake-created-record-id" "A4: no record id"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Non-disposable label
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Non-disposable label ---"
echo ""

for bad_label in "proxy" "web" "www" "@" "*" "api" "cdn" "mail" "regular-label"; do
  B_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
    python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
    --label "$bad_label" --type A --content 203.0.113.10 --ttl 60 \
    --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && B_RC=0 || B_RC=$?
  if [[ "$B_RC" != "0" ]]; then
    pass "B: label '$bad_label' rejected"
  else
    fail "B: label '$bad_label' should be rejected"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Existing record found → blocked
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Existing record found ---"
echo ""

C_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_existing_record.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" != "0" ]]; then
  pass "C1: existing record exits non-zero ($C_RC)"
else
  fail "C1: existing record should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_JSON" "record_already_exists" "C2: reason record_already_exists"
assert_contains "$C_JSON" '"mutation_allowed": false' "C3: mutation false"
assert_not_contains "$C_JSON" "fake-created-record-id" "C4: no record id"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Successful create + post-check + cleanup
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Successful smoke ---"
echo ""

D_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: success exits 0"
else
  fail "D1: success should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_JSON" '"status": "created_and_cleaned"' "D2: status created_and_cleaned"
assert_contains "$D_JSON" '"ok": true' "D3: ok true"
assert_contains "$D_JSON" '"success": true' "D4: create success"
assert_contains "$D_JSON" '"persistent_dns_changed": false' "D5: persistent_dns_changed false"
assert_contains "$D_JSON" '"records_created": true' "D6: records_created true"
assert_contains "$D_JSON" '"records_deleted": true' "D7: records_deleted true"
assert_contains "$D_JSON" '"cleanup_verified": true' "D8: cleanup_verified true"
assert_contains "$D_JSON" '"record_id_printed": false' "D9: record_id_printed false"
assert_not_contains "$D_JSON" "fake-created-record-id" "D10: no record id in output"

D_TEXT=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" 2>&1)

assert_contains "$D_TEXT" "Cleanup: succeeded" "D11: text cleanup succeeded"
assert_contains "$D_TEXT" "Persistent DNS changed: false" "D12: text persistent false"
assert_contains "$D_TEXT" "Token printed: false" "D13: text token false"
assert_contains "$D_TEXT" "Record ID printed: false" "D14: text record id false"
assert_not_contains "$D_TEXT" "fake-created-record-id" "D15: no record id in text"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Post-check fails → cleanup attempted
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Post-check fails ---"
echo ""

E_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_post_check_fail.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: post-check fail exits non-zero ($E_RC)"
else
  fail "E1: post-check fail should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_JSON" "post_check_failed" "E2: status post_check_failed"
assert_contains "$E_JSON" '"attempted": true' "E3: cleanup attempted"
assert_not_contains "$E_JSON" "fake-created-record-id" "E4: no record id"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Cleanup fails → manual warning
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Cleanup fails ---"
echo ""

F_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_cleanup_fail.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: cleanup fail exits non-zero ($F_RC)"
else
  fail "F1: cleanup fail should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_JSON" "cleanup_failed" "F2: status cleanup_failed"
assert_contains "$F_JSON" "manual_cleanup_warning" "F3: manual cleanup warning"
assert_not_contains "$F_JSON" "fake-created-record-id" "F4: no record id"
assert_not_contains "$F_JSON" "DUMMY_PLACEHOLDER" "F5: no token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Dangerous flags rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Dangerous flags rejected ---"
echo ""

for flag in "--force" "--overwrite" "--apply" "--yes" "--keep-for-debug"; do
  G_OUT=$(python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
    --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
    --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" "$flag" --json 2>&1) && G_RC=0 || G_RC=$?
  if [[ "$G_RC" != "0" ]]; then
    pass "G: $flag rejected (rc=$G_RC)"
  else
    fail "G: $flag should be rejected"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Unsupported type
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Unsupported type ---"
echo ""

for bad_type in "CNAME" "MX" "NS" "SRV" "CAA"; do
  H_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
    python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
    --label nanobk-smoke-test --type "$bad_type" --content 203.0.113.10 --ttl 60 \
    --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && H_RC=0 || H_RC=$?
  if [[ "$H_RC" != "0" ]]; then
    pass "H: type '$bad_type' rejected"
  else
    fail "H: type '$bad_type' should be rejected"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Unsafe credential permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Unsafe credential ---"
echo ""

I_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/unsafe_world_readable_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && I_RC=0 || I_RC=$?

if [[ "$I_RC" != "0" ]]; then
  pass "I1: unsafe credential exits non-zero ($I_RC)"
else
  fail "I1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$I_JSON" "insecure" "I2: insecure message"
assert_not_contains "$I_JSON" "unsafe_world_readable" "I3: no credential path"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Redaction scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Redaction ---"
echo ""

ALL_OUTPUTS="$D_JSON $D_TEXT $E_JSON $F_JSON $G_OUT $I_JSON"

for forbidden in "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN" \
  "safe_api_env.env" "unsafe_world_readable" "fake-zone-id" "Authorization:" "Bearer " \
  "/dns_records" "/zones/" "api.cloudflare.com" "workers.dev" "vless://" "trojan://" \
  "hysteria2://" "tuic://" "PRIVATE KEY" "subscription" "apply --yes"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "J: output contains forbidden: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "J: no '$forbidden'"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Missing confirmation phrase
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Missing confirmation phrase ---"
echo ""

K_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --cleanup --json 2>&1) && K_RC=0 || K_RC=$?

if [[ "$K_RC" != "0" ]]; then
  pass "K1: missing phrase exits non-zero ($K_RC)"
else
  fail "K1: missing phrase should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$K_JSON" "confirmation_required" "K2: reason confirmation_required"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Missing cleanup flag
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Missing cleanup ---"
echo ""

L_JSON=$(NANOBK_OWNER_SMOKE_FAKE_MAP="$FIXTURES/fake_map_success.json" \
  python3 "$MODULE" smoke --zone example.com --api-env "$FIXTURES/safe_api_env.env" \
  --label nanobk-smoke-test --type A --content 203.0.113.10 --ttl 60 \
  --owner-approve --confirm-disposable-smoke "$CONFIRM" --json 2>&1) && L_RC=0 || L_RC=$?

if [[ "$L_RC" != "0" ]]; then
  pass "L1: missing cleanup exits non-zero ($L_RC)"
else
  fail "L1: missing cleanup should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$L_JSON" "cleanup_required" "L2: reason cleanup_required"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.45 Owner Disposable DNS Create Harness tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
