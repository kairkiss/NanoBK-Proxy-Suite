#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner Smoke Report Scanner Hardening Test
#
# Tests the report scanner rules to distinguish safe status fields from real leaks.
# Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.47-owner-smoke-report-scanner-hardening.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures/v2.2.47"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

# ── Scanner logic ───────────────────────────────────────────────────────────
#
# The scanner checks each line for forbidden patterns.
# A line is SAFE if it also contains a safe indicator:
#   - "printed: no" or "printed: false" or "printed: no"
#   - ": false" (JSON boolean)
#   - "Do not print" (forbidden-list doc)
#   - "must remain absent" (forbidden-list doc)
#   - "No ..." at line start (forbidden-list doc)
#
# A line is a LEAK if it contains a forbidden pattern WITHOUT a safe indicator.

# Forbidden patterns that indicate real leaks when found without safe context
LEAK_PATTERNS=(
  "https://api.cloudflare.com"
  "Authorization: Bearer"
  "CF_API_TOKEN="
  "CLOUDFLARE_API_TOKEN="
  "/client/v4/zones/"
  "PRIVATE KEY"
  "vless://"
  "trojan://"
  "hysteria2://"
  "tuic://"
)

# Patterns that are safe when paired with safe indicators
CONTEXT_PATTERNS=(
  "api.cloudflare.com"
  "/zones/"
  "/dns_records"
  "raw_api_response_printed"
  "Authorization"
  "CF_API_TOKEN"
  "record_id"
  "zone_id"
  "record ID"
  "zone ID"
)

# Safe indicators that negate a match
SAFE_INDICATORS=(
  "printed: no"
  "printed: false"
  ": false"
  ": no"
  "\"raw_api_response_printed\": false"
  "raw_api_response_printed=false"
  "Do not print"
  "must remain absent"
  "not printed"
  "never printed"
)

scan_file() {
  local file="$1"
  local leaked=0

  while IFS= read -r line; do
    # Check each leak pattern — these are always leaks regardless of context
    for pattern in "${LEAK_PATTERNS[@]}"; do
      if echo "$line" | grep -qF "$pattern"; then
        # Check if line has a safe indicator
        local safe=0
        for indicator in "${SAFE_INDICATORS[@]}"; do
          if echo "$line" | grep -qi "$indicator"; then
            safe=1
            break
          fi
        done
        if [[ "$safe" == "0" ]]; then
          echo "LEAK: $line"
          leaked=1
        fi
      fi
    done

    # Check context patterns — these need safe indicators
    for pattern in "${CONTEXT_PATTERNS[@]}"; do
      if echo "$line" | grep -qF "$pattern"; then
        # Check if line has a safe indicator
        local safe=0
        for indicator in "${SAFE_INDICATORS[@]}"; do
          if echo "$line" | grep -qi "$indicator"; then
            safe=1
            break
          fi
        done
        # Also safe if it's a pure negation doc line
        if echo "$line" | grep -qE "^(Do not|No |Never )"; then
          safe=1
        fi
        if [[ "$safe" == "0" ]]; then
          # Check if it's actually a leak pattern (already caught above) or context-only
          local is_leak=0
          for lp in "${LEAK_PATTERNS[@]}"; do
            if echo "$line" | grep -qF "$lp"; then
              is_leak=1
              break
            fi
          done
          if [[ "$is_leak" == "0" ]]; then
            echo "LEAK: $line"
            leaked=1
          fi
        fi
      fi
    done
  done < "$file"

  return $leaked
}

echo ""
echo "=== Owner Smoke Report Scanner Hardening Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Safe status fields accepted
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Safe status fields accepted ---"
echo ""

if scan_file "$FIXTURES/safe_status_fields.txt" > /dev/null 2>&1; then
  pass "A1: safe status fields accepted (no leak)"
else
  fail "A1: safe status fields should be accepted"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Safe JSON status accepted
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Safe JSON status accepted ---"
echo ""

if scan_file "$FIXTURES/safe_json_status.txt" > /dev/null 2>&1; then
  pass "B1: safe JSON status accepted (no leak)"
else
  fail "B1: safe JSON status should be accepted"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Safe forbidden-list docs accepted
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Safe forbidden-list docs accepted ---"
echo ""

if scan_file "$FIXTURES/safe_forbidden_list_doc.txt" > /dev/null 2>&1; then
  pass "C1: safe forbidden-list docs accepted (no leak)"
else
  fail "C1: safe forbidden-list docs should be accepted"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Actual API URL leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Actual API URL leak rejected ---"
echo ""

if scan_file "$FIXTURES/actual_api_url_leak.txt" > /dev/null 2>&1; then
  fail "D1: actual API URL leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "D1: actual API URL leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Authorization leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Authorization leak rejected ---"
echo ""

if scan_file "$FIXTURES/authorization_leak.txt" > /dev/null 2>&1; then
  fail "E1: Authorization leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "E1: Authorization leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Token env leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Token env leak rejected ---"
echo ""

if scan_file "$FIXTURES/token_env_leak.txt" > /dev/null 2>&1; then
  fail "F1: token env leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "F1: token env leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Record ID leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Record ID leak rejected ---"
echo ""

if scan_file "$FIXTURES/record_id_leak.txt" > /dev/null 2>&1; then
  fail "G1: record ID leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "G1: record ID leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Protocol link leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Protocol link leak rejected ---"
echo ""

if scan_file "$FIXTURES/protocol_link_leak.txt" > /dev/null 2>&1; then
  fail "H1: protocol link leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "H1: protocol link leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Private key leak rejected
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Private key leak rejected ---"
echo ""

if scan_file "$FIXTURES/private_key_leak.txt" > /dev/null 2>&1; then
  fail "I1: private key leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "I1: private key leak rejected"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Scanner does not over-relax
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Scanner does not over-relax ---"
echo ""

# Verify that safe status fields do NOT make real leaks pass
MIXED_FILE=$(mktemp)
cat > "$MIXED_FILE" << 'EOF'
raw_api_response_printed=false
https://api.cloudflare.com/client/v4/zones/fake/dns_records
EOF

if scan_file "$MIXED_FILE" > /dev/null 2>&1; then
  fail "J1: mixed file with real leak should be rejected"
  ERRORS=$((ERRORS + 1))
else
  pass "J1: mixed file with real leak rejected despite safe line"
fi

rm -f "$MIXED_FILE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.47 Owner Smoke Report Scanner Hardening tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
