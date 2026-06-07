#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare DNS Readiness Test
#
# Tests nanobk cf dns readiness [--api-env PATH] [--profile PATH] [--json].
# All API calls use fake transport (NANOBK_CF_ZONES_FAKE_RESPONSE).
# No real Cloudflare API is called. No DNS mutation.
#
# Usage:
#   bash tests/cf-dns-readiness.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"
FIXTURES="$ROOT/tests/fixtures"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

# ── Temp file cleanup ───────────────────────────────────────────────────────

TMP_FILES=()
cleanup() {
  for f in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do
    rm -f "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT

make_env() {
  local mode="$1"
  shift
  local tmpfile
  tmpfile=$(mktemp)
  chmod "$mode" "$tmpfile"
  for line in "$@"; do
    echo "$line" >> "$tmpfile"
  done
  TMP_FILES+=("$tmpfile")
  echo "$tmpfile"
}

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

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# ── Helper: run readiness ───────────────────────────────────────────────────

run_readiness() {
  local extra_env=""
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns readiness)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fake-response)
        extra_env="NANOBK_CF_ZONES_FAKE_RESPONSE=$2"; shift 2 ;;
      *)
        args+=("$1"); shift ;;
    esac
  done
  if [[ -n "$extra_env" ]]; then
    env "$extra_env" bash "${args[@]}" 2>&1
  else
    bash "${args[@]}" 2>&1
  fi
}

echo ""
echo "=== Cloudflare DNS Readiness Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns readiness --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "readiness" "help mentions readiness"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Missing api-env and missing profile ──────────────────────────────────

echo "--- B. Missing inputs ---"
echo ""

MISSING_OUT=$(run_readiness)
assert_contains "$MISSING_OUT" "manual_pending" "missing inputs report manual_pending"
assert_contains "$MISSING_OUT" "No DNS records were created" "missing inputs shows no-mutation"
assert_not_contains "$MISSING_OUT" "Traceback" "missing inputs has no traceback"

echo ""

# ── C. Insecure api-env ─────────────────────────────────────────────────────

echo "--- C. Insecure api-env ---"
echo ""

PERM_ENV=$(make_env 644 "CF_API_TOKEN=test_token_insecure")
PERM_OUT=$(run_readiness --api-env "$PERM_ENV" --fake-response "$FIXTURES/cf-zones-success.json" || true)
assert_contains "$PERM_OUT" "Insecure" "insecure api-env reports error"
assert_not_contains "$PERM_OUT" "test_token_insecure" "no token in insecure error output"

echo ""

# ── D. Unsupported env key ──────────────────────────────────────────────────

echo "--- D. Unsupported env key ---"
echo ""

BADKEY_ENV=$(make_env 600 "CF_API_TOKEN=test_token_badkey" "CF_BAD_KEY=badvalue")
BADKEY_OUT=$(run_readiness --api-env "$BADKEY_ENV" --fake-response "$FIXTURES/cf-zones-success.json" || true)
assert_contains "$BADKEY_OUT" "Unsupported key" "unsupported key reports error"
assert_not_contains "$BADKEY_OUT" "test_token_badkey" "no token in unsupported key error"
assert_not_contains "$BADKEY_OUT" "badvalue" "no value in unsupported key error"

echo ""

# ── E. Token-only env ───────────────────────────────────────────────────────

echo "--- E. Token-only env ---"
echo ""

TOKEN_ENV=$(make_env 600 "CF_API_TOKEN=test_token_only")
TOKEN_OUT=$(run_readiness --api-env "$TOKEN_ENV" --fake-response "$FIXTURES/cf-zones-success.json")
assert_contains "$TOKEN_OUT" "ok" "token-only env shows ok status"
assert_contains "$TOKEN_OUT" "2 zones found" "token-only shows zone count"
assert_contains "$TOKEN_OUT" "manual_pending" "token-only dns_check_available is manual_pending"
assert_not_contains "$TOKEN_OUT" "test_token_only" "no token in output"

echo ""

# ── F. Token+zone env ───────────────────────────────────────────────────────

echo "--- F. Token+zone env ---"
echo ""

FULL_ENV=$(make_env 600 "CF_API_TOKEN=test_token_full" "CF_ZONE_ID=zone_id_123" "CF_ZONE_NAME=example.com")
FULL_OUT=$(run_readiness --api-env "$FULL_ENV" --fake-response "$FIXTURES/cf-zones-success.json")
assert_contains "$FULL_OUT" "ok" "full env shows ok status"
assert_not_contains "$FULL_OUT" "test_token_full" "no token in output"
assert_not_contains "$FULL_OUT" "zone_id_123" "no raw zone id in output"

echo ""

# ── G. Fake zones cases ─────────────────────────────────────────────────────

echo "--- G. Fake zones cases ---"
echo ""

# Empty zones
EMPTY_ENV=$(make_env 600 "CF_API_TOKEN=test_empty")
EMPTY_OUT=$(run_readiness --api-env "$EMPTY_ENV" --fake-response "$FIXTURES/cf-zones-empty.json")
assert_contains "$EMPTY_OUT" "0 zones found" "empty zones reports 0"
assert_not_contains "$EMPTY_OUT" "test_empty" "no token in empty output"

# Auth error
AUTH_ENV=$(make_env 600 "CF_API_TOKEN=test_auth")
AUTH_OUT=$(run_readiness --api-env "$AUTH_ENV" --fake-response "$FIXTURES/cf-zones-auth-error.json" || true)
assert_contains "$AUTH_OUT" "Authentication error" "auth error shows message"
assert_not_contains "$AUTH_OUT" "test_auth" "no token in auth error"
assert_not_contains "$AUTH_OUT" "Traceback" "no traceback in auth error"

# API error
API_ENV=$(make_env 600 "CF_API_TOKEN=test_api")
API_OUT=$(run_readiness --api-env "$API_ENV" --fake-response "$FIXTURES/cf-zones-api-error.json" || true)
assert_contains "$API_OUT" "Rate limit" "api error shows message"
assert_not_contains "$API_OUT" "Traceback" "no traceback in api error"

# Malformed
MAL_ENV=$(make_env 600 "CF_API_TOKEN=test_malformed")
MAL_OUT=$(run_readiness --api-env "$MAL_ENV" --fake-response "$FIXTURES/cf-zones-malformed.json" || true)
assert_contains "$MAL_OUT" "invalid JSON" "malformed shows invalid JSON"
assert_not_contains "$MAL_OUT" "test_malformed" "no token in malformed error"
assert_not_contains "$MAL_OUT" "Traceback" "no traceback in malformed error"

echo ""

# ── H. Missing profile ──────────────────────────────────────────────────────

echo "--- H. Missing profile ---"
echo ""

MISSING_PROF=$(run_readiness --profile /tmp/nonexistent_profile_$$ || true)
assert_contains "$MISSING_PROF" "manual_pending" "missing profile reports manual_pending"
assert_not_contains "$MISSING_PROF" "Traceback" "missing profile has no traceback"

echo ""

# ── I. Valid profile ────────────────────────────────────────────────────────

echo "--- I. Valid profile ---"
echo ""

VALID_PROF=$(run_readiness --profile "$FIXTURES/cf-dns-profile-valid.json")
assert_contains "$VALID_PROF" "ok" "valid profile shows ok"
assert_contains "$VALID_PROF" "record" "valid profile shows record count"
assert_not_contains "$VALID_PROF" "apply --yes" "no apply --yes"

echo ""

# ── J. Invalid profile ──────────────────────────────────────────────────────

echo "--- J. Invalid profile ---"
echo ""

# Create invalid profile (missing required fields)
INVALID_PROF=$(mktemp)
echo '{"zoneName": "x"}' > "$INVALID_PROF"
TMP_FILES+=("$INVALID_PROF")
INVALID_OUT=$(run_readiness --profile "$INVALID_PROF" || true)
assert_contains "$INVALID_OUT" "failed" "invalid profile reports failed"
assert_not_contains "$INVALID_OUT" "Traceback" "invalid profile has no traceback"

echo ""

# ── K. JSON mode ────────────────────────────────────────────────────────────

echo "--- K. JSON mode ---"
echo ""

# Missing inputs
JSON_MISSING=$(run_readiness --json)
if echo "$JSON_MISSING" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "missing inputs JSON is valid"
else
  fail "missing inputs JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_MISSING" '"mutation": false' "missing inputs JSON has mutation: false"
assert_contains "$JSON_MISSING" '"manual_apply_pending"' "missing inputs JSON has apply status"

# Full success
JSON_ENV=$(make_env 600 "CF_API_TOKEN=test_json")
JSON_FULL=$(run_readiness --api-env "$JSON_ENV" --profile "$FIXTURES/cf-dns-profile-valid.json" --fake-response "$FIXTURES/cf-zones-success.json" --json)
if echo "$JSON_FULL" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "full success JSON is valid"
else
  fail "full success JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_FULL" '"ok": true' "full success JSON has ok: true"
assert_contains "$JSON_FULL" '"mutation": false' "full success JSON has mutation: false"
assert_not_contains "$JSON_FULL" "test_json" "full success JSON has no token"
assert_not_contains "$JSON_FULL" "example.com" "full success JSON has no raw domain"
assert_not_contains "$JSON_FULL" "hysteria2://" "no hysteria2:// in JSON"
assert_not_contains "$JSON_FULL" "workers.dev" "no workers.dev in JSON"

# Malformed zones
JSON_MAL_ENV=$(make_env 600 "CF_API_TOKEN=test_json_mal")
JSON_MAL=$(run_readiness --api-env "$JSON_MAL_ENV" --fake-response "$FIXTURES/cf-zones-malformed.json" --json || true)
if echo "$JSON_MAL" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "malformed zones JSON is valid"
else
  fail "malformed zones JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_not_contains "$JSON_MAL" "test_json_mal" "malformed JSON has no token"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-readiness tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
