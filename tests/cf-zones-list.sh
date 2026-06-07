#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Zones List Test
#
# Tests nanobk cf zones list --api-env [--json].
# All API calls use fake transport (NANOBK_CF_ZONES_FAKE_RESPONSE).
# No real Cloudflare API is called.
#
# Usage:
#   bash tests/cf-zones-list.sh

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

# ── Helper: create temp env file ────────────────────────────────────────────

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

# ── Helper: run zones list with fake response ───────────────────────────────

run_zones() {
  local fake_fixture="$1"
  local env_file="$2"
  shift 2
  NANOBK_CF_ZONES_FAKE_RESPONSE="$fake_fixture" \
    bash "$NANOBK" --repo-dir "$ROOT" cf zones list --api-env "$env_file" "$@" 2>&1
}

echo ""
echo "=== Cloudflare Zones List Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "api-env" "help mentions --api-env"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

# Top-level cf error mentions zones
CF_ERROR=$(bash "$NANOBK" --repo-dir "$ROOT" cf 2>&1 || true)
assert_contains "$CF_ERROR" "zones" "cf usage mentions zones"

echo ""

# ── B. Env parser success ───────────────────────────────────────────────────

echo "--- B. Env parser success ---"
echo ""

# Token-only env
TOKEN_ENV=$(make_env 600 "CF_API_TOKEN=test_token_123")
TOKEN_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$TOKEN_ENV")
TOKEN_RC=$?

if [[ $TOKEN_RC -eq 0 ]]; then
  pass "token-only env accepted (exit 0)"
else
  fail "token-only env rejected (exit $TOKEN_RC)"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$TOKEN_OUT" "Cloudflare zones discovered" "shows zone count"

# Token+zone env
FULL_ENV=$(make_env 600 "CF_API_TOKEN=test_token_123" "CF_ZONE_ID=zone123" "CF_ZONE_NAME=example.com")
FULL_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$FULL_ENV")
FULL_RC=$?

if [[ $FULL_RC -eq 0 ]]; then
  pass "token+zone env accepted (exit 0)"
else
  fail "token+zone env rejected (exit $FULL_RC)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── C. Env parser failures ──────────────────────────────────────────────────

echo "--- C. Env parser failures ---"
echo ""

# Missing token
NOTOKEN_ENV=$(make_env 600 "CF_ZONE_NAME=example.com")
NOTOKEN_OUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --api-env "$NOTOKEN_ENV" 2>&1 || true)
assert_contains "$NOTOKEN_OUT" "CF_API_TOKEN" "missing token reports error"

# Unsupported key
BADKEY_ENV=$(make_env 600 "CF_API_TOKEN=test_token" "CF_BAD_KEY=bad")
BADKEY_OUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --api-env "$BADKEY_ENV" 2>&1 || true)
assert_contains "$BADKEY_OUT" "Unsupported key" "unsupported key reports error"
assert_not_contains "$BADKEY_OUT" "test_token" "token not leaked in unsupported key error"

# Insecure permissions (644)
PERM_ENV=$(make_env 644 "CF_API_TOKEN=test_token")
PERM_OUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --api-env "$PERM_ENV" 2>&1 || true)
assert_contains "$PERM_OUT" "Insecure" "insecure permissions rejected"
assert_not_contains "$PERM_OUT" "test_token" "token not leaked in permission error"

# Non-existent file
NOFILE_OUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --api-env /tmp/nonexistent_cf_env_$$ 2>&1 || true)
assert_contains "$NOFILE_OUT" "not found" "missing file reports error"

echo ""

# ── D. Shell safety ─────────────────────────────────────────────────────────

echo "--- D. Shell safety ---"
echo ""

# Token with shell injection attempt
SHELL_ENV=$(make_env 600 'CF_API_TOKEN=fake_$(echo INJECTED)_token')
SHELL_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$SHELL_ENV")
assert_not_contains "$SHELL_OUT" "INJECTED" "shell injection not executed"

# Token with semicolon
SEMI_ENV=$(make_env 600 'CF_API_TOKEN=fake;echo INJECTED')
SEMI_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$SEMI_ENV")
assert_not_contains "$SEMI_OUT" "INJECTED" "semicolon injection not executed"

echo ""

# ── E. Fake transport cases ─────────────────────────────────────────────────

echo "--- E. Fake transport cases ---"
echo ""

# Success with zones
SUCCESS_ENV=$(make_env 600 "CF_API_TOKEN=test")
SUCCESS_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$SUCCESS_ENV")
assert_contains "$SUCCESS_OUT" "2" "success shows 2 zones"
assert_contains "$SUCCESS_OUT" "ex***e.com" "success masks domain 1"
assert_contains "$SUCCESS_OUT" "ex***e.net" "success masks domain 2"
assert_contains "$SUCCESS_OUT" "No DNS records were changed" "success shows no-mutation message"
assert_not_contains "$SUCCESS_OUT" "example.com" "no raw domain in output"
assert_not_contains "$SUCCESS_OUT" "example.net" "no raw domain in output"
assert_not_contains "$SUCCESS_OUT" "test" "no token in output"
assert_not_contains "$SUCCESS_OUT" "Authorization" "no Authorization in output"
assert_not_contains "$SUCCESS_OUT" "workers.dev" "no workers.dev in output"

# Empty zones
EMPTY_ENV=$(make_env 600 "CF_API_TOKEN=test")
EMPTY_OUT=$(run_zones "$FIXTURES/cf-zones-empty.json" "$EMPTY_ENV")
assert_contains "$EMPTY_OUT" "0" "empty zones shows count 0"
assert_contains "$EMPTY_OUT" "No DNS records were changed" "empty shows no-mutation"

# Auth error
AUTH_ENV=$(make_env 600 "CF_API_TOKEN=test")
AUTH_OUT=$(run_zones "$FIXTURES/cf-zones-auth-error.json" "$AUTH_ENV" || true)
assert_contains "$AUTH_OUT" "Authentication error" "auth error shows message"
assert_not_contains "$AUTH_OUT" "test" "no token in auth error output"

# API error
API_ENV=$(make_env 600 "CF_API_TOKEN=test")
API_OUT=$(run_zones "$FIXTURES/cf-zones-api-error.json" "$API_ENV" || true)
assert_contains "$API_OUT" "Rate limit" "api error shows message"

# No protocol URI schemes
assert_not_contains "$SUCCESS_OUT" "hysteria2://" "no hysteria2:// in output"
assert_not_contains "$SUCCESS_OUT" "tuic://" "no tuic:// in output"
assert_not_contains "$SUCCESS_OUT" "vless://" "no vless:// in output"
assert_not_contains "$SUCCESS_OUT" "trojan://" "no trojan:// in output"

echo ""

# ── F. Malformed fake response ──────────────────────────────────────────────

echo "--- F. Malformed fake response ---"
echo ""

# Text mode: malformed JSON
MAL_ENV=$(make_env 600 "CF_API_TOKEN=test_token_malformed")
MAL_OUT=$(run_zones "$FIXTURES/cf-zones-malformed.json" "$MAL_ENV" || true)
assert_contains "$MAL_OUT" "invalid JSON" "malformed response reports invalid JSON"
assert_not_contains "$MAL_OUT" "Traceback" "malformed response has no traceback"
assert_not_contains "$MAL_OUT" "test_token_malformed" "malformed response has no token"
assert_not_contains "$MAL_OUT" "Authorization" "malformed response has no Authorization"

# JSON mode: malformed JSON
MAL_JSON_ENV=$(make_env 600 "CF_API_TOKEN=test_token_malformed_json")
MAL_JSON_OUT=$(run_zones "$FIXTURES/cf-zones-malformed.json" "$MAL_JSON_ENV" --json || true)

# Should be valid JSON error response
if echo "$MAL_JSON_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "malformed JSON mode returns valid JSON"
else
  fail "malformed JSON mode returns invalid JSON"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MAL_JSON_OUT" '"ok": false' "malformed JSON has ok: false"
assert_contains "$MAL_JSON_OUT" '"mutation": false' "malformed JSON has mutation: false"
assert_not_contains "$MAL_JSON_OUT" "Traceback" "malformed JSON has no traceback"
assert_not_contains "$MAL_JSON_OUT" "test_token_malformed_json" "malformed JSON has no token"

echo ""

# ── G. JSON mode ────────────────────────────────────────────────────────────

echo "--- G. JSON mode ---"
echo ""

JSON_ENV=$(make_env 600 "CF_API_TOKEN=test")
JSON_OUT=$(run_zones "$FIXTURES/cf-zones-success.json" "$JSON_ENV" --json)

# Validate JSON structure
if echo "$JSON_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "JSON output is valid JSON"
else
  fail "JSON output is not valid JSON"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$JSON_OUT" '"ok": true' "JSON has ok: true"
assert_contains "$JSON_OUT" '"count": 2' "JSON has count: 2"
assert_contains "$JSON_OUT" '"mutation": false' "JSON has mutation: false"
assert_not_contains "$JSON_OUT" "test" "JSON has no token"
assert_not_contains "$JSON_OUT" "example.com" "JSON has no raw domain"
assert_not_contains "$JSON_OUT" "abc123def456" "JSON has no raw zone ID"

# JSON error
JSON_ERR_ENV=$(make_env 600 "CF_API_TOKEN=test")
JSON_ERR_OUT=$(run_zones "$FIXTURES/cf-zones-auth-error.json" "$JSON_ERR_ENV" --json || true)
assert_contains "$JSON_ERR_OUT" '"ok": false' "JSON error has ok: false"
assert_not_contains "$JSON_ERR_OUT" "test" "JSON error has no token"

echo ""

# ── H. Dispatch ─────────────────────────────────────────────────────────────

echo "--- H. Dispatch ---"
echo ""

# Invalid subcommand
ZONES_ERR=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones bad 2>&1 || true)
assert_contains "$ZONES_ERR" "Unknown cf zones subcommand" "bad subcommand reports error"

# Missing subcommand
ZONES_EMPTY=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones 2>&1 || true)
assert_contains "$ZONES_EMPTY" "Usage" "missing subcommand shows usage"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-zones-list tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
