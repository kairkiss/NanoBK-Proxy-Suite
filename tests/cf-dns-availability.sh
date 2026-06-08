#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Availability Check Test
#
# Tests nanobk cf dns availability check --zone DOMAIN --node NODE --api-env PATH [--json].
# Uses fake transport (NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE).
# No real Cloudflare API is called. No DNS mutation.
#
# Usage:
#   bash tests/cf-dns-availability.sh

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

# ── Helper: run availability check ──────────────────────────────────────────

run_check() {
  local fake=""
  local env_file=""
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns availability check --zone example.com --node proxy)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fake) fake="$2"; shift 2 ;;
      --env) env_file="$2"; shift 2 ;;
      --no-env) env_file=""; shift ;;
      --zone) args=("${args[@]/--zone example.com/--zone $2}"); shift 2 ;;
      --node) args=("${args[@]/--node proxy/--node $2}"); shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [[ -z "$env_file" ]]; then
    env_file=$(make_env 600 "CF_API_TOKEN=test_token" "CF_ZONE_ID=zone123" "CF_ZONE_NAME=example.com")
  fi
  args+=(--api-env "$env_file")
  if [[ -n "$fake" ]]; then
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE="$fake" bash "${args[@]}" 2>&1
  else
    bash "${args[@]}" 2>&1
  fi
}

echo ""
echo "=== DNS Availability Check Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns availability check --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "read-only" "help mentions read-only"
assert_contains "$HELP_OUTPUT" "GET-only" "help mentions GET-only"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

# Top-level availability error
AVAIL_ERROR=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns availability 2>&1 || true)
assert_contains "$AVAIL_ERROR" "check" "availability usage mentions check"

echo ""

# ── B. Env parser ───────────────────────────────────────────────────────────

echo "--- B. Env parser ---"
echo ""

# Full env accepted
FULL_ENV=$(make_env 600 "CF_API_TOKEN=test_token" "CF_ZONE_ID=zone123" "CF_ZONE_NAME=example.com")
FULL_OUT=$(run_check --env "$FULL_ENV" --fake "$FIXTURES/cf-dns-availability-empty.json")
assert_contains "$FULL_OUT" "available" "full env shows available"
assert_not_contains "$FULL_OUT" "test_token" "full env has no token"

# Token-only env fails
TOKEN_ENV=$(make_env 600 "CF_API_TOKEN=test_token2")
TOKEN_OUT=$(run_check --env "$TOKEN_ENV" --fake "$FIXTURES/cf-dns-availability-empty.json" 2>&1 || true)
assert_contains "$TOKEN_OUT" "CF_ZONE_ID" "token-only env requires CF_ZONE_ID"
assert_not_contains "$TOKEN_OUT" "test_token2" "token-only env has no token"

# Insecure permissions
PERM_ENV=$(make_env 644 "CF_API_TOKEN=test_token3" "CF_ZONE_ID=z" "CF_ZONE_NAME=example.com")
PERM_OUT=$(run_check --env "$PERM_ENV" --fake "$FIXTURES/cf-dns-availability-empty.json" 2>&1 || true)
assert_contains "$PERM_OUT" "Insecure" "insecure permissions rejected"
assert_not_contains "$PERM_OUT" "test_token3" "insecure env has no token"

# Unsupported key
BADKEY_ENV=$(make_env 600 "CF_API_TOKEN=test_token4" "CF_ZONE_ID=z" "CF_ZONE_NAME=example.com" "CF_BAD_KEY=bad")
BADKEY_OUT=$(run_check --env "$BADKEY_ENV" --fake "$FIXTURES/cf-dns-availability-empty.json" 2>&1 || true)
assert_contains "$BADKEY_OUT" "Unsupported key" "unsupported key rejected"
assert_not_contains "$BADKEY_OUT" "test_token4" "unsupported key has no token"
assert_not_contains "$BADKEY_OUT" "bad" "unsupported key has no value"

echo ""

# ── C. Zone mismatch ───────────────────────────────────────────────────────

echo "--- C. Zone mismatch ---"
echo ""

MISMATCH_ENV=$(make_env 600 "CF_API_TOKEN=test_token5" "CF_ZONE_ID=zone456" "CF_ZONE_NAME=other.example")
MISMATCH_OUT=$(run_check --env "$MISMATCH_ENV" --zone "example.com" --fake "$FIXTURES/cf-dns-availability-empty.json" 2>&1 || true)
assert_contains "$MISMATCH_OUT" "mismatch" "zone mismatch reports error"
assert_not_contains "$MISMATCH_OUT" "test_token5" "zone mismatch has no token"
assert_not_contains "$MISMATCH_OUT" "other.example" "zone mismatch has no raw zone name"

# JSON mode
MISMATCH_JSON=$(run_check --env "$MISMATCH_ENV" --zone "example.com" --fake "$FIXTURES/cf-dns-availability-empty.json" --json 2>&1 || true)
if echo "$MISMATCH_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "zone mismatch JSON is valid"
else
  fail "zone mismatch JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MISMATCH_JSON" '"ok": false' "zone mismatch JSON has ok: false"

echo ""

# ── D. Fake fixtures ────────────────────────────────────────────────────────

echo "--- D. Fake fixtures ---"
echo ""

# Empty / available
EMPTY_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-empty.json")
assert_contains "$EMPTY_OUT" "status: available" "empty shows available"
assert_contains "$EMPTY_OUT" "available: true" "empty available is true"
assert_contains "$EMPTY_OUT" "records_found: 0" "empty has 0 records"
assert_contains "$EMPTY_OUT" "manual_review_required: false" "empty no manual review"

# Unowned A — conflict
UNOWNED_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-unowned-a.json")
assert_contains "$UNOWNED_OUT" "status: conflict" "unowned A shows conflict"
assert_contains "$UNOWNED_OUT" "available: false" "unowned A not available"
assert_contains "$UNOWNED_OUT" "manual_review_required: true" "unowned A requires manual review"
assert_contains "$UNOWNED_OUT" "203.0.113.xxx" "unowned A shows masked IPv4"
assert_not_contains "$UNOWNED_OUT" "203.0.113.10" "unowned A has no full IPv4"
assert_not_contains "$UNOWNED_OUT" "rec-abc123" "unowned A has no raw record ID"

# Owned A — nanobk_owned
OWNED_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-owned-a.json")
assert_contains "$OWNED_OUT" "status: nanobk_owned" "owned A shows nanobk_owned"
assert_contains "$OWNED_OUT" "owned_by_nanobk=true" "owned A shows owned_by_nanobk"
assert_not_contains "$OWNED_OUT" "managed-by=nanobk" "owned A has no raw marker"

# CNAME — conflict
CNAME_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-cname.json")
assert_contains "$CNAME_OUT" "status: conflict" "CNAME shows conflict"
assert_contains "$CNAME_OUT" "CNAME" "CNAME shows record type"
assert_not_contains "$CNAME_OUT" "other-host.example.net" "CNAME has no raw target"

# Proxied A — conflict
PROXIED_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-proxied-a.json")
assert_contains "$PROXIED_OUT" "status: conflict" "proxied A shows conflict"
assert_contains "$PROXIED_OUT" "proxied=true" "proxied A shows proxied=true"
assert_not_contains "$PROXIED_OUT" "203.0.113.20" "proxied A has no full IPv4"

# Multiple — conflict
MULTI_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-multiple.json")
assert_contains "$MULTI_OUT" "status: conflict" "multiple shows conflict"
assert_contains "$MULTI_OUT" "records_found: 2" "multiple has 2 records"

# TXT — manual_review/conflict
TXT_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-txt.json")
assert_contains "$TXT_OUT" "TXT" "TXT shows record type"
assert_not_contains "$TXT_OUT" "v=spf1" "TXT has no raw content"
assert_contains "$TXT_OUT" "[redacted]" "TXT shows redacted content"

# Auth error
AUTH_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-auth-error.json" 2>&1 || true)
assert_contains "$AUTH_OUT" "Authentication error" "auth error shows message"
assert_not_contains "$AUTH_OUT" "test_token" "auth error has no token"
assert_not_contains "$AUTH_OUT" "Traceback" "auth error has no traceback"

# API error
API_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-api-error.json" 2>&1 || true)
assert_contains "$API_OUT" "Rate limit" "api error shows message"
assert_not_contains "$API_OUT" "Traceback" "api error has no traceback"

# Malformed
MAL_OUT=$(run_check --fake "$FIXTURES/cf-dns-availability-malformed.json" 2>&1 || true)
assert_contains "$MAL_OUT" "invalid JSON" "malformed shows invalid JSON"
assert_not_contains "$MAL_OUT" "Traceback" "malformed has no traceback"

echo ""

# ── E. JSON mode ────────────────────────────────────────────────────────────

echo "--- E. JSON mode ---"
echo ""

# Available JSON
JSON_AVAIL=$(run_check --fake "$FIXTURES/cf-dns-availability-empty.json" --json)
if echo "$JSON_AVAIL" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "available JSON is valid"
else
  fail "available JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_AVAIL" '"ok": true' "available JSON has ok: true"
assert_contains "$JSON_AVAIL" '"mutation": false' "available JSON has mutation: false"
assert_contains "$JSON_AVAIL" '"profile_write": false' "available JSON has profile_write: false"
assert_contains "$JSON_AVAIL" '"available": true' "available JSON has available: true"
assert_contains "$JSON_AVAIL" '"status": "available"' "available JSON has status: available"
assert_not_contains "$JSON_AVAIL" "example.com" "available JSON has no raw zone"
assert_not_contains "$JSON_AVAIL" "proxy.example.com" "available JSON has no raw hostname"
assert_not_contains "$JSON_AVAIL" "test_token" "available JSON has no token"
assert_not_contains "$JSON_AVAIL" "hysteria2://" "available JSON has no protocol URI"
assert_not_contains "$JSON_AVAIL" "workers.dev" "available JSON has no workers.dev"

# Conflict JSON
JSON_CONFLICT=$(run_check --fake "$FIXTURES/cf-dns-availability-unowned-a.json" --json)
if echo "$JSON_CONFLICT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "conflict JSON is valid"
else
  fail "conflict JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_CONFLICT" '"status": "conflict"' "conflict JSON has status: conflict"
assert_contains "$JSON_CONFLICT" '"available": false' "conflict JSON has available: false"
assert_contains "$JSON_CONFLICT" '"manual_review_required": true' "conflict JSON has manual_review: true"
assert_not_contains "$JSON_CONFLICT" "203.0.113.10" "conflict JSON has no full IPv4"
assert_not_contains "$JSON_CONFLICT" "rec-abc123" "conflict JSON has no raw record ID"

echo ""

# ── F. Dry-run ──────────────────────────────────────────────────────────────

echo "--- F. Dry-run ---"
echo ""

DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns availability check --zone example.com --node proxy --api-env /tmp/fake_env 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "NanoBK DNS availability" "global dry-run does NOT execute helper"

DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns availability check --zone example.com --node proxy --api-env /tmp/fake_env --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "NanoBK DNS availability" "command-level dry-run does NOT execute helper"

echo ""

# ── G. Source checks ────────────────────────────────────────────────────────

echo "--- G. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_availability.py")
assert_not_contains "$HELPER_SRC" "requests.post" "no POST"
assert_not_contains "$HELPER_SRC" "requests.patch" "no PATCH"
assert_not_contains "$HELPER_SRC" "requests.delete" "no DELETE"
assert_not_contains "$HELPER_SRC" "requests.put" "no PUT"
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"
assert_not_contains "$HELPER_SRC" "cloudflare-dns-profile.json" "no profile path"
assert_not_contains "$HELPER_SRC" "/etc/nanobk" "no /etc/nanobk"
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-availability tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
