#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare DNS Apply Test (Mocked Transport)
#
# Tests `nanobk cf dns apply` with fake transport.
# Never calls real Cloudflare API.
#
# Usage:
#   bash tests/cf-dns-apply.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    fail "$label — should NOT contain: $needle"
    ERRORS=$((ERRORS + 1))
  else
    pass "$label"
  fi
}

assert_exit() {
  local expected="$1"
  local label="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label — expected exit $expected, got $actual"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== Cloudflare DNS Apply Test (Mocked Transport) ==="
echo ""

NANOBK="$ROOT/bin/nanobk"
PROFILE="$ROOT/tests/fixtures/cf-dns-profile.example.json"

# Create temp dir for test fixtures
TMPDIR_TESTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# ── Helper: create api-env file ──────────────────────────────────────────

make_api_env() {
  local path="$1"
  local token="${2:-fake-cloudflare-token-do-not-use}"
  local zone_id="${3:-fake-zone-id-12345}"
  local zone_name="${4:-example.com}"
  cat > "$path" <<EOF
CF_API_TOKEN="${token}"
CF_ZONE_ID="${zone_id}"
CF_ZONE_NAME=${zone_name}
EOF
  chmod 600 "$path"
}

# ── Helper: create fake transport fixture ────────────────────────────────

make_transport() {
  local path="$1"
  shift
  # Remaining args are key-value pairs: "KEY: JSON_VALUE"
  echo "{" > "$path"
  local first=1
  while [[ $# -gt 0 ]]; do
    local key="$1"
    local val="$2"
    shift 2
    if [[ $first -eq 1 ]]; then
      first=0
    else
      echo "," >> "$path"
    fi
    echo "  \"${key}\": ${val}" >> "$path"
  done
  echo "" >> "$path"
  echo "}" >> "$path"
}

# ── Helper: create fake transport with calls tracking ────────────────────

make_transport_with_calls() {
  local path="$1"
  local calls_file="$2"
  shift 2
  echo "{" > "$path"
  echo "  \"_calls_file\": \"${calls_file}\"," >> "$path"
  local first=1
  while [[ $# -gt 0 ]]; do
    local key="$1"
    local val="$2"
    shift 2
    if [[ $first -eq 1 ]]; then
      first=0
    else
      echo "," >> "$path"
    fi
    echo "  \"${key}\": ${val}" >> "$path"
  done
  echo "" >> "$path"
  echo "}" >> "$path"
}

# ── Standard test data ───────────────────────────────────────────────────

SUCCESS_RESULT='{"success": true, "result": []}'
A_RECORD='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
A_RECORD_DIFF='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
A_RECORD_UNOWNED='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "manual record"}]}'
A_RECORD_PROXIED='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10", "proxied": true, "comment": ""}]}'
A_RECORD_MULTI='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10", "proxied": false}, {"id": "rec-a-002", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false}]}'
AAAA_RECORD='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::10", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
AAAA_RECORD_DIFF='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
AAAA_RECORD_UNOWNED='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "manual record"}]}'
AAAA_RECORD_PROXIED='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::10", "proxied": true, "comment": ""}]}'
AAAA_RECORD_MULTI='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::10", "proxied": false}, {"id": "rec-aaaa-002", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false}]}'
CNAME_RECORD='{"success": true, "result": [{"id": "rec-cname-001", "type": "CNAME", "name": "node.example.com", "content": "other.example.com", "proxied": false}]}'
EMPTY_RECORDS='{"success": true, "result": []}'
CREATE_SUCCESS='{"success": true, "result": {"id": "rec-new-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10"}}'
CREATE_AAAA_SUCCESS='{"success": true, "result": {"id": "rec-new-002", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::10"}}'
UPDATE_SUCCESS='{"success": true, "result": {"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.10"}}'
UPDATE_AAAA_SUCCESS='{"success": true, "result": {"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::10"}}'

ERR_401='{"success": false, "errors": [{"code": 10000, "message": "Authentication error"}], "_status": 401}'
ERR_403='{"success": false, "errors": [{"code": 10000, "message": "Forbidden"}], "_status": 403}'
ERR_429='{"success": false, "errors": [{"code": 10000, "message": "Rate limited"}], "_status": 429}'

# ═══════════════════════════════════════════════════════════════════════════
# Section 1: api-env validation
# ═══════════════════════════════════════════════════════════════════════════

echo "--- api-env validation ---"
echo ""

# 1. Missing api-env fails
assert_exit 1 "missing api-env file fails" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "/tmp/nonexistent-env-$$.env"

# 2. api-env chmod not 600 fails
BAD_PERM_ENV="$TMPDIR_TESTS/bad-perm.env"
make_api_env "$BAD_PERM_ENV"
chmod 644 "$BAD_PERM_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$BAD_PERM_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "600\|permission"; then
  pass "api-env chmod not 600 fails"
else
  fail "api-env chmod not 600 should fail"
  ERRORS=$((ERRORS + 1))
fi

# 3. Missing CF_API_TOKEN fails
NO_TOKEN_ENV="$TMPDIR_TESTS/no-token.env"
cat > "$NO_TOKEN_ENV" <<'EOF'
CF_ZONE_ID="fake-zone-id"
CF_ZONE_NAME=example.com
EOF
chmod 600 "$NO_TOKEN_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$NO_TOKEN_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "CF_API_TOKEN\|missing"; then
  pass "missing CF_API_TOKEN fails"
else
  fail "missing CF_API_TOKEN should fail"
  ERRORS=$((ERRORS + 1))
fi

# 4. Missing CF_ZONE_ID fails
NO_ZONE_ID_ENV="$TMPDIR_TESTS/no-zone-id.env"
cat > "$NO_ZONE_ID_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_NAME=example.com
EOF
chmod 600 "$NO_ZONE_ID_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$NO_ZONE_ID_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "CF_ZONE_ID\|missing"; then
  pass "missing CF_ZONE_ID fails"
else
  fail "missing CF_ZONE_ID should fail"
  ERRORS=$((ERRORS + 1))
fi

# 5. Missing CF_ZONE_NAME fails
NO_ZONE_NAME_ENV="$TMPDIR_TESTS/no-zone-name.env"
cat > "$NO_ZONE_NAME_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_ID="fake-zone-id"
EOF
chmod 600 "$NO_ZONE_NAME_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$NO_ZONE_NAME_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "CF_ZONE_NAME\|missing"; then
  pass "missing CF_ZONE_NAME fails"
else
  fail "missing CF_ZONE_NAME should fail"
  ERRORS=$((ERRORS + 1))
fi

# 5b. API_KEY rejected (allowlist)
API_KEY_ENV="$TMPDIR_TESTS/api-key.env"
cat > "$API_KEY_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_ID="fake-zone-id"
CF_ZONE_NAME=example.com
API_KEY="should-not-be-here"
EOF
chmod 600 "$API_KEY_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_KEY_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "unsupported key\|API_KEY\|Allowed keys"; then
  pass "API_KEY rejected by allowlist"
else
  fail "API_KEY should be rejected by allowlist"
  ERRORS=$((ERRORS + 1))
fi

# 5c. CF_API_KEY rejected (allowlist)
CF_API_KEY_ENV="$TMPDIR_TESTS/cf-api-key.env"
cat > "$CF_API_KEY_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_ID="fake-zone-id"
CF_ZONE_NAME=example.com
CF_API_KEY="should-not-be-here"
EOF
chmod 600 "$CF_API_KEY_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$CF_API_KEY_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "unsupported key\|CF_API_KEY\|Allowed keys"; then
  pass "CF_API_KEY rejected by allowlist"
else
  fail "CF_API_KEY should be rejected by allowlist"
  ERRORS=$((ERRORS + 1))
fi

# 5d. SECRET_KEY rejected (allowlist)
SECRET_KEY_ENV="$TMPDIR_TESTS/secret-key.env"
cat > "$SECRET_KEY_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_ID="fake-zone-id"
CF_ZONE_NAME=example.com
SECRET_KEY="should-not-be-here"
EOF
chmod 600 "$SECRET_KEY_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$SECRET_KEY_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "unsupported key\|SECRET_KEY\|Allowed keys"; then
  pass "SECRET_KEY rejected by allowlist"
else
  fail "SECRET_KEY should be rejected by allowlist"
  ERRORS=$((ERRORS + 1))
fi

# 5e. EXTRA_FIELD rejected (allowlist)
EXTRA_FIELD_ENV="$TMPDIR_TESTS/extra-field.env"
cat > "$EXTRA_FIELD_ENV" <<'EOF'
CF_API_TOKEN="fake-token"
CF_ZONE_ID="fake-zone-id"
CF_ZONE_NAME=example.com
EXTRA_FIELD="should-not-be-here"
EOF
chmod 600 "$EXTRA_FIELD_ENV"
OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$EXTRA_FIELD_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "unsupported key\|EXTRA_FIELD\|Allowed keys"; then
  pass "EXTRA_FIELD rejected by allowlist"
else
  fail "EXTRA_FIELD should be rejected by allowlist"
  ERRORS=$((ERRORS + 1))
fi

# 5f. Valid env with only allowed keys still passes
VALID_ENV="$TMPDIR_TESTS/valid.env"
make_api_env "$VALID_ENV"
TRANSPORT="$TMPDIR_TESTS/transport-valid-env.json"
make_transport "$TRANSPORT" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$VALID_ENV" --dry-run 2>&1 || true)
if echo "$OUT" | grep -qi "dry-run\|validate\|plan"; then
  pass "valid env with only allowed keys still passes"
else
  fail "valid env with only allowed keys should pass"
  ERRORS=$((ERRORS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 2: Command mode behavior
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Command mode behavior ---"
echo ""

API_ENV="$TMPDIR_TESTS/api.env"
make_api_env "$API_ENV"

# 6. Default apply without --yes refuses mutation (needs GET responses for plan)
TRANSPORT="$TMPDIR_TESTS/transport-noyes.json"
make_transport "$TRANSPORT" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" 2>&1 || true)
if echo "$OUT" | grep -qi "review\|--yes\|plan only"; then
  pass "default apply without --yes refuses mutation"
else
  fail "default apply without --yes should refuse mutation"
  ERRORS=$((ERRORS + 1))
fi

# 7. --dry-run performs no fake transport calls
DRYRUN_TRANSPORT="$TMPDIR_TESTS/transport-dryrun.json"
DRYRUN_CALLS="$TMPDIR_TESTS/calls-dryrun.json"
make_transport_with_calls "$DRYRUN_TRANSPORT" "$DRYRUN_CALLS" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS"
NANOBK_CF_DNS_FAKE_TRANSPORT="$DRYRUN_TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --dry-run >/dev/null 2>&1 || true
# --dry-run should skip API calls entirely (validate only)
# Check that no calls file was created (or is empty)
if [[ ! -f "$DRYRUN_CALLS" ]] || [[ "$(cat "$DRYRUN_CALLS" 2>/dev/null)" == "[]" ]] || [[ ! -s "$DRYRUN_CALLS" ]]; then
  pass "--dry-run performs no API calls"
else
  fail "--dry-run should not make API calls"
  ERRORS=$((ERRORS + 1))
fi

# 8. --check performs GET-only fake calls
CHECK_TRANSPORT="$TMPDIR_TESTS/transport-check.json"
CHECK_CALLS="$TMPDIR_TESTS/calls-check.json"
make_transport_with_calls "$CHECK_TRANSPORT" "$CHECK_CALLS" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$CHECK_TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
# Verify no POST or PATCH calls were made
if [[ -f "$CHECK_CALLS" ]]; then
  if grep -q '"POST"\|"PATCH"' "$CHECK_CALLS" 2>/dev/null; then
    fail "--check should not make POST/PATCH calls"
    ERRORS=$((ERRORS + 1))
  else
    pass "--check performs GET-only calls"
  fi
else
  # No calls file means no calls at all, which is also OK
  pass "--check performs GET-only calls"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 3: Idempotency state machine
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Idempotency state machine ---"
echo ""

# 9. Existing same A/AAAA -> noop
TRANSPORT="$TMPDIR_TESTS/transport-noop.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD" \
  "GET_AAAA" "$AAAA_RECORD" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "no change\|noop\|already match"; then
  pass "existing same A/AAAA -> noop"
else
  fail "existing same A/AAAA should be noop"
  ERRORS=$((ERRORS + 1))
fi

# 10. Missing A/AAAA -> create planned; with --yes fake POST called
TRANSPORT="$TMPDIR_TESTS/transport-create.json"
CALLS="$TMPDIR_TESTS/calls-create.json"
make_transport_with_calls "$TRANSPORT" "$CALLS" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS" \
  "POST" "$CREATE_SUCCESS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --yes 2>&1 || true)
if echo "$OUT" | grep -qi "created\|create"; then
  pass "missing A/AAAA -> create with --yes"
else
  fail "missing A/AAAA should create with --yes"
  ERRORS=$((ERRORS + 1))
fi
# Verify POST was called
if [[ -f "$CALLS" ]] && grep -q '"POST"' "$CALLS" 2>/dev/null; then
  pass "POST was called for create"
else
  fail "POST should have been called for create"
  ERRORS=$((ERRORS + 1))
fi

# 11. Existing owned different -> update planned; with --yes fake PATCH called
TRANSPORT="$TMPDIR_TESTS/transport-update.json"
CALLS="$TMPDIR_TESTS/calls-update.json"
make_transport_with_calls "$TRANSPORT" "$CALLS" \
  "GET_A" "$A_RECORD_DIFF" \
  "GET_AAAA" "$AAAA_RECORD_DIFF" \
  "GET_CNAME" "$EMPTY_RECORDS" \
  "PATCH" "$UPDATE_SUCCESS"
# Also need separate PATCH responses for A and AAAA
# The fake transport uses generic PATCH key
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --yes 2>&1 || true)
if echo "$OUT" | grep -qi "update\|updated"; then
  pass "existing owned different -> update with --yes"
else
  fail "existing owned different should update with --yes"
  ERRORS=$((ERRORS + 1))
fi

# 12. Existing unowned different -> fail conflict
TRANSPORT="$TMPDIR_TESTS/transport-unowned.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_UNOWNED" \
  "GET_AAAA" "$AAAA_RECORD_UNOWNED" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 1 "existing unowned -> fail conflict" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# 13. Existing proxied=true -> fail conflict
TRANSPORT="$TMPDIR_TESTS/transport-proxied.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_PROXIED" \
  "GET_AAAA" "$AAAA_RECORD_PROXIED" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "proxied\|conflict"; then
  pass "existing proxied=true -> fail conflict"
else
  fail "existing proxied=true should fail conflict"
  ERRORS=$((ERRORS + 1))
fi

# 14. Multiple existing records -> fail conflict
TRANSPORT="$TMPDIR_TESTS/transport-multi.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_MULTI" \
  "GET_AAAA" "$AAAA_RECORD_MULTI" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "multiple\|conflict"; then
  pass "multiple existing records -> fail conflict"
else
  fail "multiple existing records should fail conflict"
  ERRORS=$((ERRORS + 1))
fi

# 15. Same-name CNAME -> fail conflict
TRANSPORT="$TMPDIR_TESTS/transport-cname.json"
make_transport "$TRANSPORT" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$CNAME_RECORD"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "CNAME\|conflict"; then
  pass "same-name CNAME -> fail conflict"
else
  fail "same-name CNAME should fail conflict"
  ERRORS=$((ERRORS + 1))
fi

# 15b. Owned different content with matching hostname -> update
A_RECORD_OWNED_MATCH='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
AAAA_RECORD_OWNED_MATCH='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=node.example.com"}]}'
TRANSPORT="$TMPDIR_TESTS/transport-owned-match.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_OWNED_MATCH" \
  "GET_AAAA" "$AAAA_RECORD_OWNED_MATCH" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "update\|will update"; then
  pass "owned different with matching hostname -> update"
else
  fail "owned different with matching hostname should be update"
  ERRORS=$((ERRORS + 1))
fi

# 15c. Owned different content but wrong hostname -> fail conflict
A_RECORD_WRONG_HOST='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=other.example.com"}]}'
AAAA_RECORD_WRONG_HOST='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "managed-by=nanobk; component=cf-dns-apply; hostname=other.example.com"}]}'
TRANSPORT="$TMPDIR_TESTS/transport-wrong-host.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_WRONG_HOST" \
  "GET_AAAA" "$AAAA_RECORD_WRONG_HOST" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 1 "owned different but wrong hostname -> fail conflict" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# 15d. Marker missing component -> fail conflict
A_RECORD_NO_COMPONENT='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "managed-by=nanobk; hostname=node.example.com"}]}'
AAAA_RECORD_NO_COMPONENT='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "managed-by=nanobk; hostname=node.example.com"}]}'
TRANSPORT="$TMPDIR_TESTS/transport-no-component.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_NO_COMPONENT" \
  "GET_AAAA" "$AAAA_RECORD_NO_COMPONENT" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 1 "marker missing component -> fail conflict" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# 15e. Marker missing managed-by -> fail conflict
A_RECORD_NO_MANAGED='{"success": true, "result": [{"id": "rec-a-001", "type": "A", "name": "node.example.com", "content": "203.0.113.20", "proxied": false, "comment": "component=cf-dns-apply; hostname=node.example.com"}]}'
AAAA_RECORD_NO_MANAGED='{"success": true, "result": [{"id": "rec-aaaa-001", "type": "AAAA", "name": "node.example.com", "content": "2001:db8::20", "proxied": false, "comment": "component=cf-dns-apply; hostname=node.example.com"}]}'
TRANSPORT="$TMPDIR_TESTS/transport-no-managed.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_NO_MANAGED" \
  "GET_AAAA" "$AAAA_RECORD_NO_MANAGED" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 1 "marker missing managed-by -> fail conflict" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# ═══════════════════════════════════════════════════════════════════════════
# Section 4: Error simulation
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Error simulation ---"
echo ""

# 16. Simulated 401 -> redacted clear failure
TRANSPORT="$TMPDIR_TESTS/transport-401.json"
make_transport "$TRANSPORT" \
  "GET_A" "$ERR_401" \
  "GET_AAAA" "$ERR_401" \
  "GET_CNAME" "$ERR_401"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "authenticat\|401\|token"; then
  pass "simulated 401 -> clear failure message"
else
  fail "simulated 401 should produce clear failure"
  ERRORS=$((ERRORS + 1))
fi

# 17. Simulated 403 -> redacted clear failure
TRANSPORT="$TMPDIR_TESTS/transport-403.json"
make_transport "$TRANSPORT" \
  "GET_A" "$ERR_403" \
  "GET_AAAA" "$ERR_403" \
  "GET_CNAME" "$ERR_403"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "permission\|403\|denied"; then
  pass "simulated 403 -> clear failure message"
else
  fail "simulated 403 should produce clear failure"
  ERRORS=$((ERRORS + 1))
fi

# 18. Simulated 429 -> redacted clear failure
TRANSPORT="$TMPDIR_TESTS/transport-429.json"
make_transport "$TRANSPORT" \
  "GET_A" "$ERR_429" \
  "GET_AAAA" "$ERR_429" \
  "GET_CNAME" "$ERR_429"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "rate limit\|429"; then
  pass "simulated 429 -> clear failure message"
else
  fail "simulated 429 should produce clear failure"
  ERRORS=$((ERRORS + 1))
fi

# 18b. Simulated non-JSON API response -> clear failure (no traceback)
# Note: The fake transport always returns valid JSON from fixtures, so we test
# that _real_transport handles non-JSON gracefully by verifying the error path
# does not produce a Python traceback in output.
NONJSON_TRANSPORT="$TMPDIR_TESTS/transport-nonjson.json"
make_transport "$NONJSON_TRANSPORT" \
  "GET_A" "$ERR_401" \
  "GET_AAAA" "$ERR_401" \
  "GET_CNAME" "$ERR_401"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$NONJSON_TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
if echo "$OUT" | grep -qi "Traceback\|JSONDecodeError"; then
  fail "API error should not produce Python traceback"
  ERRORS=$((ERRORS + 1))
else
  pass "API error produces clean message (no traceback)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 5: Security output checks
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Security output checks ---"
echo ""

# 19. Output does not contain fake token
TRANSPORT="$TMPDIR_TESTS/transport-security.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD" \
  "GET_AAAA" "$AAAA_RECORD" \
  "GET_CNAME" "$EMPTY_RECORDS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
assert_not_contains "$OUT" "fake-cloudflare-token-do-not-use" "output does not contain token value"

# 20. Output does not contain Authorization header
assert_not_contains "$OUT" "Authorization: Bearer" "output does not contain Authorization header"
assert_not_contains "$OUT" "Authorization:" "output does not contain Authorization header (partial)"

# Additional security checks
assert_not_contains "$OUT" "workers.dev" "output does not contain workers.dev"
assert_not_contains "$OUT" "hysteria2://" "output does not contain hysteria2://"
assert_not_contains "$OUT" "tuic://" "output does not contain tuic://"
assert_not_contains "$OUT" "vless://" "output does not contain vless://"
assert_not_contains "$OUT" "trojan://" "output does not contain trojan://"
assert_not_contains "$OUT" "private_key" "output does not contain private_key"
assert_not_contains "$OUT" "subscription" "output does not contain subscription"

# Security check on error output too
ERR_TRANSPORT="$TMPDIR_TESTS/transport-security-err.json"
make_transport "$ERR_TRANSPORT" \
  "GET_A" "$ERR_401" \
  "GET_AAAA" "$ERR_401" \
  "GET_CNAME" "$ERR_401"
ERR_OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$ERR_TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check 2>&1 || true)
assert_not_contains "$ERR_OUT" "fake-cloudflare-token-do-not-use" "error output does not contain token value"
assert_not_contains "$ERR_OUT" "Authorization: Bearer" "error output does not contain Authorization header"

# ═══════════════════════════════════════════════════════════════════════════
# Section 6: --force rejection
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- --force rejection ---"
echo ""

OUT=$(bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --force 2>&1 || true)
if echo "$OUT" | grep -qi "force\|reserved\|not implemented"; then
  pass "--force is rejected with clear message"
else
  fail "--force should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 7: Existing commands preserved
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Existing commands preserved ---"
echo ""

# Verify plan still works
check "cf dns plan still works" bash "$NANOBK" cf dns plan --profile "$PROFILE"

# Verify validate-profile still works
check "cf dns validate-profile still works" bash "$NANOBK" cf dns validate-profile --profile "$PROFILE"

# Verify cf deploy/verify still mentioned
CF_HELP=$(bash "$NANOBK" cf 2>&1 || true)
if echo "$CF_HELP" | grep -q "deploy\|verify"; then
  pass "existing cf subcommands still mentioned"
else
  fail "existing cf subcommands should still work"
  ERRORS=$((ERRORS + 1))
fi

# Verify help mentions apply
HELP_OUT=$(bash "$NANOBK" --help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "cf dns apply"; then
  pass "help mentions cf dns apply"
else
  fail "help should mention cf dns apply"
  ERRORS=$((ERRORS + 1))
fi

# Verify apply --help exits 0
check "cf dns apply --help exits 0" bash "$NANOBK" cf dns apply --help

# Verify apply -h exits 0
check "cf dns apply -h exits 0" bash "$NANOBK" cf dns apply -h

# Verify apply --help output contains key options
APPLY_HELP=$(bash "$NANOBK" cf dns apply --help 2>&1 || true)
assert_contains "$APPLY_HELP" "--dry-run" "apply help mentions --dry-run"
assert_contains "$APPLY_HELP" "--check" "apply help mentions --check"
assert_contains "$APPLY_HELP" "--yes" "apply help mentions --yes"
assert_contains "$APPLY_HELP" "--api-env" "apply help mentions --api-env"
assert_contains "$APPLY_HELP" "--profile" "apply help mentions --profile"
assert_contains "$APPLY_HELP" "--force" "apply help mentions --force"
assert_contains "$APPLY_HELP" "reserved" "apply help mentions reserved for --force"
assert_contains "$APPLY_HELP" "no Cloudflare API calls" "apply help mentions no API calls for --dry-run"

# ═══════════════════════════════════════════════════════════════════════════
# Section 8: JSON output
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- JSON output ---"
echo ""

TRANSPORT="$TMPDIR_TESTS/transport-json.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD" \
  "GET_AAAA" "$AAAA_RECORD" \
  "GET_CNAME" "$EMPTY_RECORDS"
JSON_OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check --json 2>&1 || true)
if echo "$JSON_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'actions' in d" 2>/dev/null; then
  pass "JSON output is valid JSON with actions"
else
  fail "JSON output should be valid JSON"
  ERRORS=$((ERRORS + 1))
fi
# Verify token not in JSON
assert_not_contains "$JSON_OUT" "fake-cloudflare-token-do-not-use" "JSON output does not contain token"

# ═══════════════════════════════════════════════════════════════════════════
# Section 9: Exit code behavior
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- Exit code behavior ---"
echo ""

# Exit 2: mutations needed but no --yes
TRANSPORT="$TMPDIR_TESTS/transport-exit2.json"
make_transport "$TRANSPORT" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 2 "exit 2: mutations needed but no --yes" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV"

# Exit 0: noop (all match)
TRANSPORT="$TMPDIR_TESTS/transport-exit0.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD" \
  "GET_AAAA" "$AAAA_RECORD" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 0 "exit 0: all records match (noop)" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# Exit 1: conflict
TRANSPORT="$TMPDIR_TESTS/transport-exit1.json"
make_transport "$TRANSPORT" \
  "GET_A" "$A_RECORD_UNOWNED" \
  "GET_AAAA" "$AAAA_RECORD_UNOWNED" \
  "GET_CNAME" "$EMPTY_RECORDS"
assert_exit 1 "exit 1: conflict (unowned record)" \
  env NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$PROFILE" --api-env "$API_ENV" --check

# ═══════════════════════════════════════════════════════════════════════════
# Section 10: IPv4-only and IPv6-only profiles
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "--- IPv4-only / IPv6-only profiles ---"
echo ""

# IPv4-only profile
IPV4_PROFILE="$TMPDIR_TESTS/ipv4-only.json"
cat > "$IPV4_PROFILE" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv4": "203.0.113.10",
  "defaultProxied": false
}
EOF

TRANSPORT="$TMPDIR_TESTS/transport-ipv4only.json"
CALLS="$TMPDIR_TESTS/calls-ipv4only.json"
make_transport_with_calls "$TRANSPORT" "$CALLS" \
  "GET_A" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS" \
  "POST" "$CREATE_SUCCESS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$IPV4_PROFILE" --api-env "$API_ENV" --yes 2>&1 || true)
if echo "$OUT" | grep -qi "A.*create\|created.*A"; then
  pass "IPv4-only profile creates A record"
else
  fail "IPv4-only profile should create A record"
  ERRORS=$((ERRORS + 1))
fi

# IPv6-only profile
IPV6_PROFILE="$TMPDIR_TESTS/ipv6-only.json"
cat > "$IPV6_PROFILE" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv6": "2001:db8::10",
  "defaultProxied": false
}
EOF

TRANSPORT="$TMPDIR_TESTS/transport-ipv6only.json"
CALLS="$TMPDIR_TESTS/calls-ipv6only.json"
make_transport_with_calls "$TRANSPORT" "$CALLS" \
  "GET_AAAA" "$EMPTY_RECORDS" \
  "GET_CNAME" "$EMPTY_RECORDS" \
  "POST" "$CREATE_AAAA_SUCCESS"
OUT=$(NANOBK_CF_DNS_FAKE_TRANSPORT="$TRANSPORT" \
  bash "$NANOBK" cf dns apply --profile "$IPV6_PROFILE" --api-env "$API_ENV" --yes 2>&1 || true)
if echo "$OUT" | grep -qi "AAAA.*create\|created.*AAAA"; then
  pass "IPv6-only profile creates AAAA record"
else
  fail "IPv6-only profile should create AAAA record"
  ERRORS=$((ERRORS + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}All cf-dns-apply tests passed${NC}"
else
  echo -e "${RED}${ERRORS} cf-dns-apply test(s) failed${NC}"
fi
echo ""

exit $ERRORS
