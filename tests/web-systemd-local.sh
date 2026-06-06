#!/usr/bin/env bash
# NanoBK Proxy Suite — Web Systemd Local Test
#
# Validates Web Panel run/systemd infrastructure without requiring
# a real systemd environment. Checks safety, hardening, and structure.
#
# Usage:
#   bash tests/web-systemd-local.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Web Systemd Local Test ==="
echo ""

# ── run.sh checks ──────────────────────────────────────────────────────────

echo "--- web/run.sh ---"
echo ""

if [[ -f "$ROOT/web/run.sh" ]]; then
  pass "run.sh exists"
else
  fail "run.sh missing"
  ERRORS=$((ERRORS + 1))
fi

if [[ -x "$ROOT/web/run.sh" ]]; then
  pass "run.sh is executable"
else
  fail "run.sh is not executable"
  ERRORS=$((ERRORS + 1))
fi

if bash -n "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh syntax valid"
else
  fail "run.sh has syntax errors"
  ERRORS=$((ERRORS + 1))
fi

# run.sh must not bind to 0.0.0.0 by default
if grep -q 'NANOBK_WEB_HOST=0\.0\.0\.0' "$ROOT/web/run.sh" 2>/dev/null; then
  fail "run.sh hardcodes 0.0.0.0 binding"
  ERRORS=$((ERRORS + 1))
else
  pass "run.sh does not hardcode 0.0.0.0"
fi

# run.sh must warn about 0.0.0.0
if grep -q '0\.0\.0\.0' "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh warns about 0.0.0.0 binding"
else
  fail "run.sh missing 0.0.0.0 warning"
  ERRORS=$((ERRORS + 1))
fi

# run.sh must check default token
if grep -q 'change-me-long-random-token' "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh validates default token"
else
  fail "run.sh missing default token check"
  ERRORS=$((ERRORS + 1))
fi

# run.sh must check default secret key
if grep -q 'change-me-session-secret' "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh validates default secret key"
else
  fail "run.sh missing default secret key check"
  ERRORS=$((ERRORS + 1))
fi

# run.sh must use set -Eeuo pipefail
if grep -q 'set -Eeuo pipefail' "$ROOT/web/run.sh" 2>/dev/null; then
  pass "run.sh uses strict mode"
else
  fail "run.sh missing strict mode"
  ERRORS=$((ERRORS + 1))
fi

# run.sh must not cat or print .env contents
if grep -qE 'cat \.env|echo.*\$\{.*TOKEN|echo.*\$\{.*SECRET' "$ROOT/web/run.sh" 2>/dev/null; then
  fail "run.sh may expose .env contents"
  ERRORS=$((ERRORS + 1))
else
  pass "run.sh does not expose .env contents"
fi

echo ""

# ── systemd unit checks ───────────────────────────────────────────────────

echo "--- systemd unit ---"
echo ""

UNIT="$ROOT/web/systemd/nanobk-web-panel.service.example"

if [[ -f "$UNIT" ]]; then
  pass "systemd unit example exists"
else
  fail "systemd unit example missing"
  ERRORS=$((ERRORS + 1))
fi

# Must not bind to 0.0.0.0
if grep -q '0\.0\.0\.0' "$UNIT" 2>/dev/null; then
  fail "systemd unit contains 0.0.0.0"
  ERRORS=$((ERRORS + 1))
else
  pass "systemd unit has no 0.0.0.0"
fi

# Must reference run.sh (preferred) or app.py
if grep -q 'run\.sh' "$UNIT" 2>/dev/null; then
  pass "systemd unit references run.sh"
elif grep -q 'app\.py' "$UNIT" 2>/dev/null; then
  pass "systemd unit references app.py"
else
  fail "systemd unit missing ExecStart reference"
  ERRORS=$((ERRORS + 1))
fi

# Must have Restart=on-failure
if grep -q 'Restart=on-failure' "$UNIT" 2>/dev/null; then
  pass "systemd unit has Restart=on-failure"
else
  fail "systemd unit missing Restart=on-failure"
  ERRORS=$((ERRORS + 1))
fi

# Must have security hardening
if grep -q 'ProtectSystem=strict' "$UNIT" 2>/dev/null; then
  pass "systemd unit has ProtectSystem=strict"
else
  fail "systemd unit missing ProtectSystem=strict"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'NoNewPrivileges=true' "$UNIT" 2>/dev/null; then
  pass "systemd unit has NoNewPrivileges=true"
else
  fail "systemd unit missing NoNewPrivileges=true"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'PrivateTmp=true' "$UNIT" 2>/dev/null; then
  pass "systemd unit has PrivateTmp=true"
else
  fail "systemd unit missing PrivateTmp=true"
  ERRORS=$((ERRORS + 1))
fi

# Must reference EnvironmentFile
if grep -q 'EnvironmentFile' "$UNIT" 2>/dev/null; then
  pass "systemd unit has EnvironmentFile"
else
  fail "systemd unit missing EnvironmentFile"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Security: no real secrets in web files ──────────────────────────────────

echo "--- Security: no real secrets ---"
echo ""

# Check no real IPs (except 127.0.0.1, 0.0.0.0, and example placeholders)
real_ip_hits=0
while IFS= read -r line; do
  # Skip lines with example/placeholder IPs
  if echo "$line" | grep -qE 'YOUR_VPS_IP|example\.com|127\.0\.0\.1|0\.0\.0\.0|localhost'; then
    continue
  fi
  # Check for real-looking IPs
  if echo "$line" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
    real_ip_hits=$((real_ip_hits + 1))
  fi
done < <(grep -rn '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' "$ROOT/web/run.sh" "$UNIT" 2>/dev/null || true)

if [[ "$real_ip_hits" -eq 0 ]]; then
  pass "No real IPs in run.sh or systemd unit"
else
  fail "Found $real_ip_hits potential real IP references"
  ERRORS=$((ERRORS + 1))
fi

# Check no workers.dev URLs
if grep -q 'workers\.dev' "$ROOT/web/run.sh" "$UNIT" 2>/dev/null; then
  fail "Found workers.dev URL in web files"
  ERRORS=$((ERRORS + 1))
else
  pass "No workers.dev URLs"
fi

# Check no subscription URLs
if grep -q 'subscription' "$ROOT/web/run.sh" "$UNIT" 2>/dev/null; then
  fail "Found subscription reference in web files"
  ERRORS=$((ERRORS + 1))
else
  pass "No subscription references"
fi

# Check no private keys
if grep -q 'private_key\|PRIVATE_KEY' "$ROOT/web/run.sh" "$UNIT" 2>/dev/null; then
  fail "Found private key reference in web files"
  ERRORS=$((ERRORS + 1))
else
  pass "No private key references"
fi

echo ""

# ── Installer env chmod 600 check ──────────────────────────────────────────

echo "--- Installer env handling ---"
echo ""

if grep -q 'chmod 600.*\.env' "$ROOT/installer/install.sh" 2>/dev/null; then
  pass "Installer sets chmod 600 on .env"
else
  fail "Installer missing chmod 600 on .env"
  ERRORS=$((ERRORS + 1))
fi

if grep -q 'ssh -L.*127\.0\.0\.1' "$ROOT/installer/install.sh" 2>/dev/null; then
  pass "Installer provides SSH tunnel recovery command"
else
  fail "Installer missing SSH tunnel recovery command"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Web app self-test ──────────────────────────────────────────────────────

echo "--- Web app self-test ---"
echo ""

if python3 "$ROOT/web/app.py" --self-test 2>&1; then
  pass "web/app.py --self-test passed"
else
  fail "web/app.py --self-test failed"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}=== All web-systemd-local tests passed ===${NC}"
else
  echo -e "${RED}=== $ERRORS test(s) failed ===${NC}"
fi
echo ""

exit "$ERRORS"
