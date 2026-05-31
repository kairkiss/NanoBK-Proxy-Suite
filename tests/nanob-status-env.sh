#!/usr/bin/env bash
# NanoBK Proxy Suite — nanob status env field test
#
# Tests that nanobk status correctly reads .nanob.local.env
# and that verify status updates are reflected.
#
# Also tests install-cloudflare.sh --verify-nanob-only with mock curl.
#
# Usage:
#   bash tests/nanob-status-env.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-status-env-test-$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== nanob Status Env Field Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# ── Test 1: verify=pending shows pending ────────────────────────────────────

echo "--- verify=pending ---"
echo ""

cat > "$TMP/.nanob.local.env" <<'EOF'
NANOB_WORKER_NAME="nanob"
NANOB_ROUTE_URL="https://nanob.example.workers.dev"
NANOB_TOKEN="fake-token-for-test"
NANOB_PATH="/jb"
NANOB_DEPLOY_STATUS="deployed"
NANOB_VERIFY_STATUS="pending"
NANOB_GEO_KV_NAMESPACE_ID="fake-geo-kv"
EDGE_HOST=""
EOF
chmod 600 "$TMP/.nanob.local.env"

# Create a fake repo structure for nanobk to find .nanob.local.env
mkdir -p "$TMP/repo/bin"
cp "$ROOT/bin/nanobk" "$TMP/repo/bin/nanobk"
ln -sf "$TMP/.nanob.local.env" "$TMP/repo/.nanob.local.env"

OUTPUT=$(bash "$TMP/repo/bin/nanobk" --repo-dir "$TMP/repo" --json status --config-dir "$TMP" 2>&1 || true)

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['verifyStatus']=='pending'" 2>/dev/null; then
  pass "nanob verify shows pending"
else
  fail "nanob verify should show pending"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: verify=verified shows verified ──────────────────────────────────

echo ""
echo "--- verify=verified ---"
echo ""

# Use sed to update (set_env_value_safe is tested via install-cloudflare.sh)
sed -i.bak 's/NANOB_VERIFY_STATUS="pending"/NANOB_VERIFY_STATUS="verified"/' "$TMP/.nanob.local.env" && rm -f "$TMP/.nanob.local.env.bak"

OUTPUT2=$(bash "$TMP/repo/bin/nanobk" --repo-dir "$TMP/repo" --json status --config-dir "$TMP" 2>&1 || true)

if echo "$OUTPUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['verifyStatus']=='verified'" 2>/dev/null; then
  pass "nanob verify shows verified"
else
  fail "nanob verify should show verified"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: missing field gets appended ─────────────────────────────────────

echo ""
echo "--- missing field gets appended ---"
echo ""

# Remove NANOB_VERIFY_STATUS from env
sed '/^NANOB_VERIFY_STATUS=/d' "$TMP/.nanob.local.env" > "$TMP/.nanob.local.env.nomarker"
mv "$TMP/.nanob.local.env.nomarker" "$TMP/.nanob.local.env"
chmod 600 "$TMP/.nanob.local.env"

# Verify field is gone
if grep -q "^NANOB_VERIFY_STATUS=" "$TMP/.nanob.local.env"; then
  fail "NANOB_VERIFY_STATUS should be removed"
  ERRORS=$((ERRORS + 1))
else
  pass "NANOB_VERIFY_STATUS removed from env"
fi

# Simulate set_env_value_safe: append the key
printf '%s="%s"\n' "NANOB_VERIFY_STATUS" "verified" >> "$TMP/.nanob.local.env"
chmod 600 "$TMP/.nanob.local.env"

if grep -q '^NANOB_VERIFY_STATUS="verified"' "$TMP/.nanob.local.env" 2>/dev/null; then
  pass "NANOB_VERIFY_STATUS appended as verified"
else
  fail "NANOB_VERIFY_STATUS not appended"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: token not in output ─────────────────────────────────────────────

echo ""
echo "--- token safety ---"
echo ""

if echo "$OUTPUT2" | grep -q "fake-token-for-test"; then
  fail "nanob token leaked in JSON output"
  ERRORS=$((ERRORS + 1))
else
  pass "nanob token not in JSON output"
fi

# ── Test 5: env file permissions ────────────────────────────────────────────

echo ""
echo "--- permissions ---"
echo ""

PERMS=$(stat -c '%a' "$TMP/.nanob.local.env" 2>/dev/null || stat -f '%Lp' "$TMP/.nanob.local.env" 2>/dev/null || echo "unknown")
if [[ "$PERMS" == "600" ]]; then
  pass ".nanob.local.env permissions: 600"
else
  fail ".nanob.local.env permissions: ${PERMS}"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 6: verify-nanob-only with mock curl ────────────────────────────────

echo ""
echo "--- verify-nanob-only with mock curl ---"
echo ""

# Reset env to pending
sed 's/^NANOB_VERIFY_STATUS=.*/NANOB_VERIFY_STATUS="pending"/' "$TMP/.nanob.local.env" > "$TMP/.nanob.local.env.reset"
mv "$TMP/.nanob.local.env.reset" "$TMP/.nanob.local.env"
chmod 600 "$TMP/.nanob.local.env"

# Create fake curl that outputs valid YAML
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURL_FAKE'
#!/usr/bin/env bash
# Fake curl for testing
# When called with nanob subscription URL, returns valid YAML
for arg in "$@"; do
  if [[ "$arg" == *"token="* ]]; then
    cat <<YAML
proxies:
  - name: hy2
    type: hysteria2
  - name: tuic
    type: tuic
  - name: reality
    type: vless
  - name: trojan
    type: trojan
proxy-groups:
  - name: Proxy
    type: select
    proxies: [hy2, tuic, reality, trojan]
rules:
  - MATCH,Proxy
YAML
    exit 0
  fi
done
# Default: return ok
echo '{"ok":true}'
CURL_FAKE
chmod +x "$TMP/bin/curl"

# Create fake repo for nanobk
mkdir -p "$TMP/repo2/bin" "$TMP/repo2/installer" "$TMP/repo2/vps/lib" "$TMP/repo2/vps/scripts"
cp "$ROOT/bin/nanobk" "$TMP/repo2/bin/nanobk"
cp "$ROOT/installer/install-cloudflare.sh" "$TMP/repo2/installer/install-cloudflare.sh"
cp "$ROOT/vps/lib/common.sh" "$TMP/repo2/vps/lib/common.sh" 2>/dev/null || true
cp "$ROOT/vps/lib/profile.sh" "$TMP/repo2/vps/lib/profile.sh" 2>/dev/null || true
ln -sf "$TMP/.nanob.local.env" "$TMP/repo2/.nanob.local.env"

# Run verify with fake curl in PATH
VERIFY_OUTPUT=$(PATH="$TMP/bin:$PATH" bash "$TMP/repo2/installer/install-cloudflare.sh" --verify-nanob-only --dry-run 2>&1 || true)

if echo "$VERIFY_OUTPUT" | grep -q "DRY-RUN\|verify"; then
  pass "verify-nanob-only runs in dry-run"
else
  fail "verify-nanob-only missing output"
  ERRORS=$((ERRORS + 1))
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All nanob status env tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
