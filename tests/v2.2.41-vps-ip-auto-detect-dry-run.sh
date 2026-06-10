#!/usr/bin/env bash
# NanoBK Proxy Suite — VPS IP Auto-detect Dry-run Test
#
# Tests the read-only VPS IP auto-detection helper.
# Uses NANOBK_TEST_* env vars for mock. Does NOT call real endpoints.
#
# Usage:
#   bash tests/v2.2.41-vps-ip-auto-detect-dry-run.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_ip_detect.py"

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
echo "=== VPS IP Auto-detect Dry-run Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Module exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Module exists ---"
echo ""

if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Dual-stack: IPv4 + IPv6 detected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Dual-stack: IPv4 + IPv6 detected ---"
echo ""

B_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.10" NANOBK_TEST_DETECTED_IPV6="2001:db8::10" \
  python3 "$MODULE" detect 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: dual-stack exits 0"
else
  fail "B1: dual-stack should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "IPv4: detected" "B2: IPv4 detected"
assert_contains "$B_OUT" "IPv6: detected" "B3: IPv6 detected"
assert_contains "$B_OUT" "203.0.113.10" "B4: IPv4 address shown"
assert_contains "$B_OUT" "2001:db8::10" "B5: IPv6 address shown"
assert_contains "$B_OUT" "A record: ready" "B6: A record ready"
assert_contains "$B_OUT" "AAAA record: ready" "B7: AAAA record ready"
assert_contains "$B_OUT" "Dry-run: true" "B8: dry-run true"
assert_contains "$B_OUT" "System changed: false" "B9: system not changed"
assert_contains "$B_OUT" "Cloudflare touched: false" "B10: cf not touched"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. IPv4 only, IPv6 not detected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. IPv4 only ---"
echo ""

C_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.20" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$MODULE" detect 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: IPv4-only exits 0"
else
  fail "C1: IPv4-only should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "IPv4: detected" "C2: IPv4 detected"
assert_contains "$C_OUT" "IPv6: not_detected" "C3: IPv6 not detected"
assert_contains "$C_OUT" "203.0.113.20" "C4: IPv4 address shown"
assert_contains "$C_OUT" "A record: ready" "C5: A record ready"
assert_contains "$C_OUT" "AAAA record: skipped" "C6: AAAA record skipped"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. IPv6 only, IPv4 fails
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. IPv6 only ---"
echo ""

D_OUT=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECTED_IPV6="2001:db8::20" \
  python3 "$MODULE" detect 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "0" ]]; then
  pass "D1: IPv6-only exits 0"
else
  fail "D1: IPv6-only should exit 0, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "IPv4: not_detected" "D2: IPv4 not detected"
assert_contains "$D_OUT" "IPv6: detected" "D3: IPv6 detected"
assert_contains "$D_OUT" "2001:db8::20" "D4: IPv6 address shown"
assert_contains "$D_OUT" "A record: skipped" "D5: A record skipped"
assert_contains "$D_OUT" "AAAA record: ready" "D6: AAAA record ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Both fail — should exit non-zero, friendly output
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Both fail ---"
echo ""

E_OUT=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$MODULE" detect 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: both fail exits non-zero ($E_RC)"
else
  fail "E1: both fail should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "IPv4: not_detected" "E2: IPv4 not detected"
assert_contains "$E_OUT" "IPv6: not_detected" "E3: IPv6 not detected"
assert_contains "$E_OUT" "A record: skipped" "E4: A record skipped"
assert_contains "$E_OUT" "AAAA record: skipped" "E5: AAAA record skipped"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Private IPv4 rejected — not usable for DNS
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Private IPv4 rejected ---"
echo ""

F_OUT=$(NANOBK_TEST_DETECTED_IPV4="192.168.1.1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$MODULE" detect 2>&1) && F_RC=0 || F_RC=$?

# Private IP → not_detected (not usable for DNS)
if [[ "$F_RC" != "0" ]]; then
  pass "F1: private IPv4 exits non-zero ($F_RC)"
else
  fail "F1: private IPv4 should exit non-zero (not usable)"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "not_detected" "F2: private IPv4 shows not_detected"
assert_not_contains "$F_OUT" "192.168.1.1" "F3: private IPv4 address not shown as detected"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Loopback / link-local / unspecified rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Loopback / link-local / unspecified rejected ---"
echo ""

for label_addr in "loopback:127.0.0.1" "link_local:169.254.1.1" "unspecified:0.0.0.0"; do
  label="${label_addr%%:*}"
  addr="${label_addr##*:}"
  G_OUT=$(NANOBK_TEST_DETECTED_IPV4="$addr" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
    python3 "$MODULE" detect 2>&1) && G_RC=0 || G_RC=$?
  if [[ "$G_RC" != "0" ]]; then
    pass "G: $label ($addr) exits non-zero"
  else
    fail "G: $label ($addr) should exit non-zero"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Malformed IP rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Malformed IP rejected ---"
echo ""

H_OUT=$(NANOBK_TEST_DETECTED_IPV4="not-an-ip" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$MODULE" detect 2>&1) && H_RC=0 || H_RC=$?

if [[ "$H_RC" != "0" ]]; then
  pass "H1: malformed IP exits non-zero ($H_RC)"
else
  fail "H1: malformed IP should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. JSON output structure
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. JSON output structure ---"
echo ""

I_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.30" NANOBK_TEST_DETECTED_IPV6="2001:db8::30" \
  python3 "$MODULE" detect --json 2>&1) && I_RC=0 || I_RC=$?

if [[ "$I_RC" == "0" ]]; then
  pass "I1: JSON dual-stack exits 0"
else
  fail "I1: JSON dual-stack should exit 0, got $I_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$I_OUT" '"ok": true' "I2: JSON ok true"
assert_contains "$I_OUT" '"status": "detected"' "I3: JSON status detected"
assert_contains "$I_OUT" '"203.0.113.30"' "I4: JSON IPv4 address"
assert_contains "$I_OUT" '"2001:db8::30"' "I5: JSON IPv6 address"
assert_contains "$I_OUT" '"a_record": "ready"' "I6: JSON A record ready"
assert_contains "$I_OUT" '"aaaa_record": "ready"' "I7: JSON AAAA record ready"
assert_contains "$I_OUT" '"dry_run": true' "I8: JSON dry_run true"
assert_contains "$I_OUT" '"system_changed": false' "I9: JSON system_changed false"
assert_contains "$I_OUT" '"cloudflare_touched": false' "I10: JSON cf touched false"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I2. JSON error output structure
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I2. JSON error output structure ---"
echo ""

I2_OUT=$(NANOBK_TEST_DETECT_IPV4_FAIL="1" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  python3 "$MODULE" detect --json 2>&1) && I2_RC=0 || I2_RC=$?

if [[ "$I2_RC" != "0" ]]; then
  pass "I2-1: JSON both-fail exits non-zero ($I2_RC)"
else
  fail "I2-1: JSON both-fail should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$I2_OUT" '"ok": false' "I2-2: JSON ok false"
assert_contains "$I2_OUT" '"not_detected"' "I2-3: JSON not_detected"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. No raw interface dump in output
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. No raw interface dump ---"
echo ""

ALL_OUTPUTS="$B_OUT $C_OUT $D_OUT $E_OUT $I_OUT"

for forbidden in "ip addr" "inet " "scope global" "default via" "link/ether" "mtu " "qdisc"; do
  if echo "$ALL_OUTPUTS" | grep -q "$forbidden"; then
    fail "J: output contains raw dump fragment: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "J: no '$forbidden' in output"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. No Cloudflare references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. No Cloudflare references ---"
echo ""

for forbidden in "api.cloudflare.com" "Authorization:" "CF_API_TOKEN" "CLOUDFLARE_API_TOKEN"; do
  if echo "$ALL_OUTPUTS" | grep -qi "$forbidden"; then
    fail "K: output contains Cloudflare reference: '$forbidden'"
    ERRORS=$((ERRORS + 1))
  else
    pass "K: no '$forbidden' in output"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. CLI integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. CLI integration ---"
echo ""

L_OUT=$(NANOBK_TEST_DETECTED_IPV4="203.0.113.40" NANOBK_TEST_DETECT_IPV6_FAIL="1" \
  "$ROOT/bin/nanobk" vps ip detect 2>&1) && L_RC=0 || L_RC=$?

if [[ "$L_RC" == "0" ]]; then
  pass "L1: CLI exits 0"
else
  fail "L1: CLI should exit 0, got $L_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$L_OUT" "IPv4: detected" "L2: CLI IPv4 detected"
assert_contains "$L_OUT" "203.0.113.40" "L3: CLI IPv4 address"
assert_contains "$L_OUT" "A record: ready" "L4: CLI A record ready"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.41 VPS IP Auto-detect tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
