#!/usr/bin/env bash
# NanoBK Proxy Suite — Combined DNS Preparation Report Test
#
# Tests nanobk cf dns report --zone DOMAIN --api-env PATH --ip-fixture PATH [--nodes proxy,web] [--json].
# Uses IP fixtures and availability fake map. No real Cloudflare API.
#
# Usage:
#   bash tests/cf-dns-report.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"
FIXTURES="$ROOT/tests/fixtures"
IP_FIXTURES="$FIXTURES/ip-detect"

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

# ── Helper: run report ──────────────────────────────────────────────────────

run_report() {
  local fake_map=""
  local env_file=""
  local ip_fixture="$IP_FIXTURES/dual-stack.json"
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns report --zone example.com --nodes proxy,web)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fake-map) fake_map="$2"; shift 2 ;;
      --env) env_file="$2"; shift 2 ;;
      --ip-fixture) ip_fixture="$2"; shift 2 ;;
      --no-env) env_file=""; shift ;;
      --zone) args=("${args[@]/--zone example.com/--zone $2}"); shift 2 ;;
      --nodes) args=("${args[@]/--nodes proxy,web/--nodes $2}"); shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  if [[ -z "$env_file" ]]; then
    env_file=$(make_env 600 "CF_API_TOKEN=test_token" "CF_ZONE_ID=zone123" "CF_ZONE_NAME=example.com")
  fi
  args+=(--api-env "$env_file" --ip-fixture "$ip_fixture")
  if [[ -n "$fake_map" ]]; then
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$fake_map" bash "${args[@]}" 2>&1
  else
    bash "${args[@]}" 2>&1
  fi
}

echo ""
echo "=== DNS Preparation Report Test ==="
echo ""

# ── A. Help and dispatch ────────────────────────────────────────────────────

echo "--- A. Help and dispatch ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "report" "help mentions report"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Missing inputs ───────────────────────────────────────────────────────

echo "--- B. Missing inputs ---"
echo ""

# Missing zone
MISSING_ZONE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --api-env /tmp/f --ip-fixture /tmp/f 2>&1 || true)
assert_contains "$MISSING_ZONE" "zone is required" "missing zone reports error"
assert_not_contains "$MISSING_ZONE" "Traceback" "missing zone has no traceback"

# Missing zone JSON
MISSING_ZONE_JSON=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --api-env /tmp/f --ip-fixture /tmp/f --json 2>&1 || true)
if echo "$MISSING_ZONE_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "missing zone JSON is valid"
else
  fail "missing zone JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MISSING_ZONE_JSON" '"ok": false' "missing zone JSON has ok: false"

# Missing api-env
MISSING_ENV=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --zone example.com --ip-fixture /tmp/f 2>&1 || true)
assert_contains "$MISSING_ENV" "api-env is required" "missing api-env reports error"

# Missing ip-fixture
MISSING_FIX=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --zone example.com --api-env /tmp/f 2>&1 || true)
assert_contains "$MISSING_FIX" "ip-fixture is required" "missing ip-fixture reports error"

echo ""

# ── C. Happy path dual-stack ───────────────────────────────────────────────

echo "--- C. Happy path dual-stack ---"
echo ""

HAPPY=$(run_report --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json")
assert_contains "$HAPPY" "ready_for_profile_generation: true" "happy shows ready true"
assert_contains "$HAPPY" "manual_review_required: false" "happy shows no manual review"
assert_contains "$HAPPY" "203.0.113.xxx" "happy shows masked IPv4"
assert_contains "$HAPPY" "2001:db8:…" "happy shows masked IPv6"
assert_contains "$HAPPY" "proxy.ex***e.com" "happy shows masked proxy hostname"
assert_contains "$HAPPY" "web.ex***e.com" "happy shows masked web hostname"
assert_not_contains "$HAPPY" "203.0.113.10" "happy has no full IPv4"
assert_not_contains "$HAPPY" "example.com" "happy has no raw zone"

echo ""

# ── D. IPv4-only target ─────────────────────────────────────────────────────

echo "--- D. IPv4-only target ---"
echo ""

IPV4_ONLY=$(run_report --ip-fixture "$IP_FIXTURES/ipv4-only.json" --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json")
assert_contains "$IPV4_ONLY" "ready_for_profile_generation: true" "ipv4-only shows ready true"
assert_contains "$IPV4_ONLY" "192.0.2.xxx" "ipv4-only shows masked IPv4"
assert_not_contains "$IPV4_ONLY" "AAAA" "ipv4-only has no AAAA"

echo ""

# ── E. Target not ready ─────────────────────────────────────────────────────

echo "--- E. Target not ready ---"
echo ""

# No addresses
NO_ADDR=$(run_report --ip-fixture "$IP_FIXTURES/no-addresses.json" --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json")
assert_contains "$NO_ADDR" "ready_for_profile_generation: false" "no-address shows ready false"
assert_contains "$NO_ADDR" "manual_review_required: true" "no-address shows manual review"

# Private only
PRIV=$(run_report --ip-fixture "$IP_FIXTURES/private-only.json" --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json")
assert_contains "$PRIV" "ready_for_profile_generation: false" "private shows ready false"

# Multiple IPv4
MULTI=$(run_report --ip-fixture "$IP_FIXTURES/multiple-ipv4.json" --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json")
assert_contains "$MULTI" "ready_for_profile_generation: false" "multiple shows ready false"

echo ""

# ── F. Availability conflict ────────────────────────────────────────────────

echo "--- F. Availability conflict ---"
echo ""

CONFLICT=$(run_report --fake-map "$FIXTURES/cf-dns-availability-summary-proxy-available-web-conflict.json")
assert_contains "$CONFLICT" "ready_for_profile_generation: false" "conflict shows ready false"
assert_contains "$CONFLICT" "manual_review_required: true" "conflict shows manual review"
assert_not_contains "$CONFLICT" "198.51.100.10" "conflict has no full IPv4 from availability"

echo ""

# ── G. Availability failed ──────────────────────────────────────────────────

echo "--- G. Availability failed ---"
echo ""

FAILED=$(run_report --fake-map "$FIXTURES/cf-dns-availability-summary-one-failed.json" 2>&1 || true)
assert_contains "$FAILED" "Authentication error" "failed shows error message"
assert_not_contains "$FAILED" "test_token" "failed has no token"
assert_not_contains "$FAILED" "Traceback" "failed has no traceback"

echo ""

# ── H. Partially owned ──────────────────────────────────────────────────────

echo "--- H. Partially owned ---"
echo ""

OWNED=$(run_report --fake-map "$FIXTURES/cf-dns-availability-summary-proxy-owned-web-available.json")
assert_contains "$OWNED" "ready_for_profile_generation: true" "owned shows ready true"
assert_contains "$OWNED" "manual_review_required: false" "owned shows no manual review"
assert_not_contains "$OWNED" "managed-by=nanobk" "owned has no raw marker"

echo ""

# ── I. JSON safety ──────────────────────────────────────────────────────────

echo "--- I. JSON safety ---"
echo ""

JSON_HAPPY=$(run_report --fake-map "$FIXTURES/cf-dns-availability-summary-all-available.json" --json)
if echo "$JSON_HAPPY" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "happy JSON is valid"
else
  fail "happy JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_HAPPY" '"ok": true' "JSON has ok: true"
assert_contains "$JSON_HAPPY" '"mutation": false' "JSON has mutation: false"
assert_contains "$JSON_HAPPY" '"profile_write": false' "JSON has profile_write: false"
assert_contains "$JSON_HAPPY" '"ready_for_profile_generation": true' "JSON has ready: true"
assert_contains "$JSON_HAPPY" '"target_preview"' "JSON has target_preview"
assert_contains "$JSON_HAPPY" '"availability_summary"' "JSON has availability_summary"
assert_not_contains "$JSON_HAPPY" "203.0.113.10" "JSON has no full IPv4"
assert_not_contains "$JSON_HAPPY" "example.com" "JSON has no raw zone"
assert_not_contains "$JSON_HAPPY" "proxy.example.com" "JSON has no raw hostname"
assert_not_contains "$JSON_HAPPY" "test_token" "JSON has no token"
assert_not_contains "$JSON_HAPPY" "hysteria2://" "JSON has no protocol URI"
assert_not_contains "$JSON_HAPPY" "workers.dev" "JSON has no workers.dev"
# availability_summary must not have detailed records array
AVAIL_SECTION=$(echo "$JSON_HAPPY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('availability_summary',{})))")
assert_not_contains "$AVAIL_SECTION" '"records":' "availability_summary has no records array"

echo ""

# ── J. Dry-run ──────────────────────────────────────────────────────────────

echo "--- J. Dry-run ---"
echo ""

DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns report --zone example.com --api-env /tmp/f --ip-fixture /tmp/f 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "NanoBK DNS preparation" "global dry-run does NOT execute"

DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns report --zone example.com --api-env /tmp/f --ip-fixture /tmp/f --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "NanoBK DNS preparation" "command-level dry-run does NOT execute"

echo ""

# ── K. Source checks ────────────────────────────────────────────────────────

echo "--- K. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_report.py")

# Guard against HTTP mutation methods (double-quote variants)
assert_not_contains "$HELPER_SRC" 'method="POST"' "no method=\"POST\""
assert_not_contains "$HELPER_SRC" 'method="PATCH"' "no method=\"PATCH\""
assert_not_contains "$HELPER_SRC" 'method="DELETE"' "no method=\"DELETE\""
assert_not_contains "$HELPER_SRC" 'method="PUT"' "no method=\"PUT\""

# Guard against HTTP mutation methods (single-quote variants)
assert_not_contains "$HELPER_SRC" "method='POST'" "no method='POST'"
assert_not_contains "$HELPER_SRC" "method='PATCH'" "no method='PATCH'"
assert_not_contains "$HELPER_SRC" "method='DELETE'" "no method='DELETE'"
assert_not_contains "$HELPER_SRC" "method='PUT'" "no method='PUT'"

# No mutation/discovery paths
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"
assert_not_contains "$HELPER_SRC" "cloudflare-dns-profile.json" "no profile path"
assert_not_contains "$HELPER_SRC" "/etc/nanobk" "no /etc/nanobk"

# No file writes
assert_not_contains "$HELPER_SRC" "open.*'w'" "no write mode"

# No external tools/services
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "ident.me" "no ident.me"

# No network interface reads
assert_not_contains "$HELPER_SRC" "ip addr" "no ip addr"
assert_not_contains "$HELPER_SRC" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-report tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
