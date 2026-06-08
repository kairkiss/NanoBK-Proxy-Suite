#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Profile Preview Test
#
# Tests nanobk cf dns profile preview --zone DOMAIN --node NODE --ipv4 VALUE [--ipv6 VALUE] [--json] [--allow-documentation-ips].
# Preview-only: no file writes, no Cloudflare calls, no DNS apply/check.
#
# Usage:
#   bash tests/cf-dns-profile-preview.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"

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

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# ── Helper: run profile preview ─────────────────────────────────────────────

run_preview() {
  local allow_docs=1
  local zone="example.com"
  local node="proxy"
  local ipv4="203.0.113.10"
  local ipv6=""
  local extra_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-allow) allow_docs=0; shift ;;
      --ipv6) ipv6="$2"; shift 2 ;;
      --zone) zone="$2"; shift 2 ;;
      --node) node="$2"; shift 2 ;;
      --ipv4) ipv4="$2"; shift 2 ;;
      *) extra_args+=("$1"); shift ;;
    esac
  done
  local args=("$NANOBK" --repo-dir "$ROOT" cf dns profile preview --zone "$zone" --node "$node" --ipv4 "$ipv4")
  [[ -n "$ipv6" ]] && args+=("--ipv6" "$ipv6")
  [[ "$allow_docs" == "1" ]] && args+=("--allow-documentation-ips")
  args+=("${extra_args[@]+"${extra_args[@]}"}")
  bash "${args[@]}" 2>&1
}

echo ""
echo "=== DNS Profile Preview Test ==="
echo ""

# ── A. Help ─────────────────────────────────────────────────────────────────

echo "--- A. Help ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile preview --help 2>&1 || true)
assert_contains "$HELP_OUTPUT" "preview" "help mentions preview"
assert_contains "$HELP_OUTPUT" "no file write" "help mentions no file write"
assert_not_contains "$HELP_OUTPUT" "apply --yes" "help has no apply --yes"

echo ""

# ── B. Missing args ─────────────────────────────────────────────────────────

echo "--- B. Missing args ---"
echo ""

# Missing zone
MISS_ZONE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile preview --node proxy --ipv4 203.0.113.10 --json 2>&1 || true)
if echo "$MISS_ZONE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "missing zone JSON is valid"
else
  fail "missing zone JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$MISS_ZONE" '"ok": false' "missing zone has ok: false"
assert_contains "$MISS_ZONE" '"profile_written": false' "missing zone has profile_written: false"
assert_contains "$MISS_ZONE" '"dns_mutation": false' "missing zone has dns_mutation: false"
assert_not_contains "$MISS_ZONE" "Traceback" "missing zone has no Traceback"
assert_not_contains "$MISS_ZONE" "example.com" "missing zone has no raw zone"

# Missing node
MISS_NODE=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile preview --zone example.com --ipv4 203.0.113.10 --json 2>&1 || true)
assert_contains "$MISS_NODE" '"ok": false' "missing node has ok: false"
assert_not_contains "$MISS_NODE" "Traceback" "missing node has no Traceback"

# Missing ipv4
MISS_IPV4=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile preview --zone example.com --node proxy --json 2>&1 || true)
assert_contains "$MISS_IPV4" '"ok": false' "missing ipv4 has ok: false"
assert_not_contains "$MISS_IPV4" "Traceback" "missing ipv4 has no Traceback"

echo ""

# ── C. Valid IPv4-only with documentation IP ────────────────────────────────

echo "--- C. Valid IPv4-only ---"
echo ""

IPV4_OUT=$(run_preview)
assert_contains "$IPV4_OUT" "profile_valid: true" "ipv4-only valid"
assert_contains "$IPV4_OUT" "validation_status: passed" "ipv4-only passed"
assert_contains "$IPV4_OUT" "profile_written: false" "ipv4-only no write"
assert_contains "$IPV4_OUT" "profile_write_mode: preview" "ipv4-only preview mode"
assert_contains "$IPV4_OUT" "dns_mutation: false" "ipv4-only no dns mutation"
assert_contains "$IPV4_OUT" "cloudflare_mutation: false" "ipv4-only no cf mutation"
assert_contains "$IPV4_OUT" "dns_apply: false" "ipv4-only no dns apply"
assert_contains "$IPV4_OUT" "test_mode: true" "ipv4-only test mode"
assert_contains "$IPV4_OUT" "203.0.113.xxx" "ipv4-only shows masked IP"
assert_not_contains "$IPV4_OUT" "203.0.113.10" "ipv4-only has no full IP"
assert_not_contains "$IPV4_OUT" "example.com" "ipv4-only has no raw zone"
assert_not_contains "$IPV4_OUT" "proxy.example.com" "ipv4-only has no raw hostname"

echo ""

# ── D. Valid dual-stack ─────────────────────────────────────────────────────

echo "--- D. Valid dual-stack ---"
echo ""

DUAL_OUT=$(run_preview --ipv6 "2001:db8::10")
assert_contains "$DUAL_OUT" "A " "dual-stack shows A record"
assert_contains "$DUAL_OUT" "AAAA" "dual-stack shows AAAA record"
assert_contains "$DUAL_OUT" "203.0.113.xxx" "dual-stack masked IPv4"
assert_contains "$DUAL_OUT" "2001:db8:…" "dual-stack masked IPv6"
assert_not_contains "$DUAL_OUT" "203.0.113.10" "dual-stack no full IPv4"
assert_not_contains "$DUAL_OUT" "2001:0db8" "dual-stack no full IPv6"

echo ""

# ── E. Documentation IP without test mode ───────────────────────────────────

echo "--- E. Documentation IP without test mode ---"
echo ""

NO_TEST=$(run_preview --no-allow 2>&1 || true)
assert_contains "$NO_TEST" "documentation" "no-test rejects documentation IP"
assert_not_contains "$NO_TEST" "203.0.113.10" "no-test has no full IP"
assert_not_contains "$NO_TEST" "Traceback" "no-test has no Traceback"

echo ""

# ── F. Private IP ───────────────────────────────────────────────────────────

echo "--- F. Private IP ---"
echo ""

PRIV=$(run_preview --ipv4 10.0.0.1 --no-allow 2>&1 || true)
assert_contains "$PRIV" "not allowed" "private IP rejected"
assert_not_contains "$PRIV" "10.0.0.1" "private has no full IP"
assert_not_contains "$PRIV" "Traceback" "private has no Traceback"

echo ""

# ── G. Invalid IP syntax ───────────────────────────────────────────────────

echo "--- G. Invalid IP syntax ---"
echo ""

INVALID=$(run_preview --ipv4 "not-an-ip" --no-allow 2>&1 || true)
assert_contains "$INVALID" "invalid" "invalid IP rejected"
assert_not_contains "$INVALID" "not-an-ip" "invalid has no raw value"
assert_not_contains "$INVALID" "Traceback" "invalid has no Traceback"

echo ""

# ── H. Invalid zone/node ────────────────────────────────────────────────────

echo "--- H. Invalid zone/node ---"
echo ""

BAD_ZONE=$(run_preview --zone "http://bad.com/path" 2>&1 || true)
assert_contains "$BAD_ZONE" "Error" "bad zone reports error"
assert_not_contains "$BAD_ZONE" "http://bad.com" "bad zone has no raw value"
assert_not_contains "$BAD_ZONE" "Traceback" "bad zone has no Traceback"

BAD_NODE=$(run_preview --node "../bad" 2>&1 || true)
assert_contains "$BAD_NODE" "Error" "bad node reports error"
assert_not_contains "$BAD_NODE" "../bad" "bad node has no raw value"
assert_not_contains "$BAD_NODE" "Traceback" "bad node has no Traceback"

echo ""

# ── I. JSON safety ──────────────────────────────────────────────────────────

echo "--- I. JSON safety ---"
echo ""

JSON_OUT=$(run_preview --json)
if echo "$JSON_OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "JSON is valid"
else
  fail "JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$JSON_OUT" '"ok": true' "JSON has ok: true"
assert_contains "$JSON_OUT" '"mutation": false' "JSON has mutation: false"
assert_contains "$JSON_OUT" '"profile_written": false' "JSON has profile_written: false"
assert_contains "$JSON_OUT" '"profile_write_mode": "preview"' "JSON has profile_write_mode: preview"
assert_contains "$JSON_OUT" '"dns_mutation": false' "JSON has dns_mutation: false"
assert_contains "$JSON_OUT" '"cloudflare_mutation": false' "JSON has cloudflare_mutation: false"
assert_contains "$JSON_OUT" '"dns_apply": false' "JSON has dns_apply: false"
assert_contains "$JSON_OUT" '"profile_valid": true' "JSON has profile_valid: true"
assert_contains "$JSON_OUT" '"test_mode": true' "JSON has test_mode: true"
assert_not_contains "$JSON_OUT" "203.0.113.10" "JSON has no full IPv4"
assert_not_contains "$JSON_OUT" "example.com" "JSON has no raw zone"
assert_not_contains "$JSON_OUT" "proxy.example.com" "JSON has no raw hostname"
assert_not_contains "$JSON_OUT" "hysteria2://" "JSON has no protocol URI"
assert_not_contains "$JSON_OUT" "workers.dev" "JSON has no workers.dev"
assert_not_contains "$JSON_OUT" "/etc/nanobk" "JSON has no /etc/nanobk"
assert_not_contains "$JSON_OUT" "cloudflare-dns-profile" "JSON has no profile path"

echo ""

# ── J. Dry-run ──────────────────────────────────────────────────────────────

echo "--- J. Dry-run ---"
echo ""

# Command-level dry-run
DRY_LOCAL=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns profile preview --zone example.com --node proxy --ipv4 203.0.113.10 --allow-documentation-ips --dry-run 2>&1)
assert_contains "$DRY_LOCAL" "DRY-RUN" "command-level dry-run shows DRY-RUN"
assert_not_contains "$DRY_LOCAL" "203.0.113.10" "command-level dry-run hides raw IP"
assert_not_contains "$DRY_LOCAL" "example.com" "command-level dry-run hides raw zone"
assert_not_contains "$DRY_LOCAL" "NanoBK DNS profile preview" "command-level dry-run does NOT execute helper"

# Global dry-run
DRY_GLOBAL=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run cf dns profile preview --zone example.com --node proxy --ipv4 203.0.113.10 --allow-documentation-ips 2>&1)
assert_contains "$DRY_GLOBAL" "DRY-RUN" "global dry-run shows DRY-RUN"
assert_not_contains "$DRY_GLOBAL" "203.0.113.10" "global dry-run hides raw IP"
assert_not_contains "$DRY_GLOBAL" "example.com" "global dry-run hides raw zone"
assert_not_contains "$DRY_GLOBAL" "NanoBK DNS profile preview" "global dry-run does NOT execute helper"

echo ""

# ── K. Source checks ────────────────────────────────────────────────────────

echo "--- K. Source checks ---"
echo ""

HELPER_SRC=$(cat "$ROOT/lib/nanobk_cf_dns_profile.py")

# No file write
assert_not_contains "$HELPER_SRC" "open(" "no open()"
assert_not_contains "$HELPER_SRC" "write_text" "no write_text"
assert_not_contains "$HELPER_SRC" "os.rename" "no os.rename"
assert_not_contains "$HELPER_SRC" "shutil.move" "no shutil.move"
assert_not_contains "$HELPER_SRC" "tempfile" "no tempfile"
assert_not_contains "$HELPER_SRC" "os.chmod" "no os.chmod"
assert_not_contains "$HELPER_SRC" "/etc/nanobk" "no /etc/nanobk"
assert_not_contains "$HELPER_SRC" "cloudflare-dns-profile" "no profile path"

# No mutation paths
assert_not_contains "$HELPER_SRC" "cf dns apply" "no cf dns apply"
assert_not_contains "$HELPER_SRC" "apply --check" "no apply --check"
assert_not_contains "$HELPER_SRC" 'method="POST"' "no method=POST"
assert_not_contains "$HELPER_SRC" 'method="DELETE"' "no method=DELETE"

# No external tools
assert_not_contains "$HELPER_SRC" "curl" "no curl"
assert_not_contains "$HELPER_SRC" "wget" "no wget"
assert_not_contains "$HELPER_SRC" "ifconfig.me" "no ifconfig.me"
assert_not_contains "$HELPER_SRC" "ipify" "no ipify"
assert_not_contains "$HELPER_SRC" "/proc/net" "no /proc/net"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All cf-dns-profile-preview tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
