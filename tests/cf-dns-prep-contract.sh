#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Preparation Contract Smoke Test
#
# Smoke-tests common contract guarantees across read-only DNS preparation helpers.
# Does not replace focused helper tests; validates cross-cutting JSON/dry-run contracts.
#
# Usage:
#   bash tests/cf-dns-prep-contract.sh

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

valid_json() {
  local desc="$1"
  local data="$2"
  if echo "$data" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== DNS Preparation Contract Smoke Test ==="
echo ""

# ── A. cf zones list --json missing api-env ─────────────────────────────────

echo "--- A. cf zones list --json missing api-env ---"
echo ""

ZONES_MISSING=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --json 2>&1 || true)
valid_json "zones missing api-env JSON is valid" "$ZONES_MISSING"
assert_contains "$ZONES_MISSING" '"ok": false' "zones missing has ok: false"
assert_contains "$ZONES_MISSING" '"mutation": false' "zones missing has mutation: false"
assert_contains "$ZONES_MISSING" "api-env is required" "zones missing has error message"
assert_not_contains "$ZONES_MISSING" "Traceback" "zones missing has no Traceback"
assert_not_contains "$ZONES_MISSING" "usage:" "zones missing has no argparse usage"

echo ""

# ── B. cf dns readiness --json minimal path ─────────────────────────────────

echo "--- B. cf dns readiness --json minimal path ---"
echo ""

READY_JSON=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns readiness --json 2>&1)
valid_json "readiness minimal JSON is valid" "$READY_JSON"
assert_contains "$READY_JSON" '"ok": true' "readiness minimal has ok: true"
assert_contains "$READY_JSON" '"mutation": false' "readiness minimal has mutation: false"
assert_contains "$READY_JSON" '"profile_write": false' "readiness minimal has profile_write: false"
assert_contains "$READY_JSON" '"ready": false' "readiness minimal has ready: false"
assert_not_contains "$READY_JSON" "Traceback" "readiness minimal has no Traceback"

echo ""

# ── C. vps ip detect --json no fixture ──────────────────────────────────────

echo "--- C. vps ip detect --json no fixture ---"
echo ""

IP_JSON=$(bash "$NANOBK" --repo-dir "$ROOT" vps ip detect --json 2>&1)
valid_json "ip detect no fixture JSON is valid" "$IP_JSON"
assert_contains "$IP_JSON" '"mutation": false' "ip detect has mutation: false"
assert_not_contains "$IP_JSON" "Traceback" "ip detect has no Traceback"
assert_not_contains "$IP_JSON" "203.0.113" "ip detect has no full real IP"

echo ""

# ── D. cf dns target preview --json missing inputs ──────────────────────────

echo "--- D. cf dns target preview --json missing inputs ---"
echo ""

TARGET_MISS=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns target preview --json --ip-fixture /tmp/f 2>&1 || true)
valid_json "target preview missing zone JSON is valid" "$TARGET_MISS"
assert_contains "$TARGET_MISS" '"ok": false' "target missing has ok: false"
assert_contains "$TARGET_MISS" '"mutation": false' "target missing has mutation: false"
assert_contains "$TARGET_MISS" '"profile_write": false' "target missing has profile_write: false"
assert_not_contains "$TARGET_MISS" "Traceback" "target missing has no Traceback"

echo ""

# ── E. cf dns availability check --json missing api-env ─────────────────────

echo "--- E. cf dns availability check --json missing api-env ---"
echo ""

AVAIL_MISS=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns availability check --zone example.com --node proxy --json 2>&1 || true)
valid_json "availability missing api-env JSON is valid" "$AVAIL_MISS"
assert_contains "$AVAIL_MISS" '"ok": false' "availability missing has ok: false"
assert_contains "$AVAIL_MISS" '"mutation": false' "availability missing has mutation: false"
assert_contains "$AVAIL_MISS" '"profile_write": false' "availability missing has profile_write: false"
assert_not_contains "$AVAIL_MISS" "Traceback" "availability missing has no Traceback"

echo ""

# ── F. cf dns availability summary --json with fake map ─────────────────────

echo "--- F. cf dns availability summary --json with fake map ---"
echo ""

SUMMARY_ENV=$(make_env 600 "CF_API_TOKEN=test_contract" "CF_ZONE_ID=z_contract" "CF_ZONE_NAME=example.com")
SUMMARY_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-summary-all-available.json" bash "$NANOBK" --repo-dir "$ROOT" cf dns availability summary --zone example.com --api-env "$SUMMARY_ENV" --json 2>&1)
valid_json "summary JSON is valid" "$SUMMARY_JSON"
assert_contains "$SUMMARY_JSON" '"ok": true' "summary has ok: true"
assert_contains "$SUMMARY_JSON" '"mutation": false' "summary has mutation: false"
assert_contains "$SUMMARY_JSON" '"profile_write": false' "summary has profile_write: false"
assert_not_contains "$SUMMARY_JSON" '"records":' "summary has no records array"
assert_not_contains "$SUMMARY_JSON" "test_contract" "summary has no token"

echo ""

# ── G. cf dns report --json happy path ──────────────────────────────────────

echo "--- G. cf dns report --json happy path ---"
echo ""

REPORT_ENV=$(make_env 600 "CF_API_TOKEN=test_report" "CF_ZONE_ID=z_report" "CF_ZONE_NAME=example.com")
REPORT_JSON=$(NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/cf-dns-availability-summary-all-available.json" bash "$NANOBK" --repo-dir "$ROOT" cf dns report --zone example.com --api-env "$REPORT_ENV" --ip-fixture "$IP_FIXTURES/dual-stack.json" --json 2>&1)
valid_json "report JSON is valid" "$REPORT_JSON"
assert_contains "$REPORT_JSON" '"ok": true' "report has ok: true"
assert_contains "$REPORT_JSON" '"mutation": false' "report has mutation: false"
assert_contains "$REPORT_JSON" '"profile_write": false' "report has profile_write: false"
assert_contains "$REPORT_JSON" '"ready_for_profile_generation": true' "report has ready: true"
assert_not_contains "$REPORT_JSON" "test_report" "report has no token"
assert_not_contains "$REPORT_JSON" "203.0.113.10" "report has no full IP"
assert_not_contains "$REPORT_JSON" "example.com" "report has no raw zone"
assert_not_contains "$REPORT_JSON" '"records":' "report availability_summary has no records array"

echo ""

# ── H. Dry-run smoke ────────────────────────────────────────────────────────

echo "--- H. Dry-run smoke ---"
echo ""

# cf zones list --dry-run
ZONES_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" cf zones list --dry-run --api-env /tmp/f 2>&1)
assert_contains "$ZONES_DRY" "DRY-RUN" "zones command-level dry-run shows DRY-RUN"
assert_not_contains "$ZONES_DRY" "Cloudflare zones discovered" "zones dry-run does NOT execute helper"

# nanobk --dry-run cf zones list
ZONES_GDRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf zones list --api-env /tmp/f 2>&1)
assert_contains "$ZONES_GDRY" "DRY-RUN" "zones global dry-run shows DRY-RUN"
assert_not_contains "$ZONES_GDRY" "Cloudflare zones discovered" "zones global dry-run does NOT execute helper"

# cf dns readiness --dry-run
READY_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns readiness --dry-run --api-env /tmp/f 2>&1)
assert_contains "$READY_DRY" "DRY-RUN" "readiness command-level dry-run shows DRY-RUN"
assert_not_contains "$READY_DRY" "NanoBK DNS readiness" "readiness dry-run does NOT execute helper"

# nanobk --dry-run cf dns readiness
READY_GDRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns readiness --api-env /tmp/f 2>&1)
assert_contains "$READY_GDRY" "DRY-RUN" "readiness global dry-run shows DRY-RUN"
assert_not_contains "$READY_GDRY" "NanoBK DNS readiness" "readiness global dry-run does NOT execute helper"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All DNS preparation contract tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
