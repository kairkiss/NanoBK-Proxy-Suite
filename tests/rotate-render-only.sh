#!/usr/bin/env bash
# NanoBK Proxy Suite — Key Rotation Render Test
#
# Tests the key rotation script in offline mode:
#   1. Generates initial configs via render-install-vps.sh
#   2. Runs rotate-keys.sh with --skip-services --skip-cloudflare
#   3. Verifies profile changed, secrets updated, no key leaks
#
# Requirements: jq
#
# Usage:
#   bash tests/rotate-render-only.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-rotate-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── Prerequisites ───────────────────────────────────────────────────────────

echo ""
echo "=== NanoBK Key Rotation Render Test ==="
echo ""

if ! command -v jq &>/dev/null; then
  fail "jq is required for rotation test"
  echo "  Install: brew install jq  OR  sudo apt-get install -y jq"
  exit 1
fi
pass "jq found"

echo "  Temp dir: ${TMP}"
echo ""

# ── Phase 1: Generate initial configs ───────────────────────────────────────

echo "--- Phase 1: Generating initial configs ---"
echo ""

rm -rf "$TMP"

bash "$ROOT/installer/install-vps.sh" --render-only --yes \
  --install-dir "$TMP/opt/nanobk" \
  --config-dir "$TMP/etc/nanobk" \
  --domain proxy.example.com \
  --vps-ip 198.51.100.10 \
  --cert-mode self-signed

echo ""

# Save old credentials for comparison
OLD_TUIC_UUID=$(jq -r '.tuic.uuid' "$TMP/etc/nanobk/profile.current.json")
OLD_HY2_PW=$(jq -r '.hy2.password' "$TMP/etc/nanobk/profile.current.json")
OLD_REALITY_UUID=$(jq -r '.reality.uuid' "$TMP/etc/nanobk/profile.current.json")
pass "Saved old credentials for comparison"

# Create fake service configs (rotate expects them to exist)
mkdir -p "$TMP/etc/nanobk/generated/hysteria"
mkdir -p "$TMP/etc/nanobk/generated/proxy-stack/tuic-v5-9443"
mkdir -p "$TMP/etc/nanobk/generated/proxy-stack/xray-reality-8443"
mkdir -p "$TMP/etc/nanobk/generated/proxy-stack/xray-trojan-2443"

# Copy the rendered configs to where rotate expects them
# (rotate reads HY2_CONFIG etc from config.env)
cp "$TMP/etc/nanobk/generated/hysteria/config.yaml" "$TMP/etc/nanobk/generated/hysteria/config.yaml" 2>/dev/null || true

# Create minimal valid configs for rotation
# HY2 config
cat > "$TMP/etc/nanobk/generated/hysteria/config.yaml" <<YAML
listen: :443
tls:
  cert: /dev/null
  key: /dev/null
auth:
  type: password
  password: "old-password"
YAML

# TUIC config
cat > "$TMP/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json" <<JSON
{
  "server": "[::]:9443",
  "users": {"old-uuid": "old-password"}
}
JSON

# Reality config
cat > "$TMP/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json" <<JSON
{
  "inbounds": [{
    "protocol": "vless",
    "settings": {"clients": [{"id": "old-uuid"}]},
    "streamSettings": {
      "realitySettings": {
        "privateKey": "old-private-key",
        "shortIds": ["old-short-id"]
      }
    }
  }]
}
JSON

# Trojan config
cat > "$TMP/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json" <<JSON
{
  "inbounds": [{
    "protocol": "trojan",
    "settings": {"clients": [{"password": "old-password"}]}
  }]
}
JSON

pass "Created minimal service configs"

echo ""

# ── Phase 2: Run rotation ───────────────────────────────────────────────────

echo "--- Phase 2: Running key rotation ---"
echo ""

bash "$ROOT/vps/scripts/rotate-keys.sh" --yes \
  --config-dir "$TMP/etc/nanobk" \
  --install-dir "$TMP/opt/nanobk" \
  --skip-services \
  --skip-cloudflare

echo ""

# ── Phase 3: Verify results ─────────────────────────────────────────────────

echo "--- Phase 3: Verifying rotation results ---"
echo ""

# Profile changed
NEW_TUIC_UUID=$(jq -r '.tuic.uuid' "$TMP/etc/nanobk/profile.current.json")
NEW_HY2_PW=$(jq -r '.hy2.password' "$TMP/etc/nanobk/profile.current.json")

if [[ "$NEW_TUIC_UUID" != "$OLD_TUIC_UUID" ]]; then
  pass "TUIC UUID changed"
else
  fail "TUIC UUID did not change"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$NEW_HY2_PW" != "$OLD_HY2_PW" ]]; then
  pass "HY2 password changed"
else
  fail "HY2 password did not change"
  ERRORS=$((ERRORS + 1))
fi

# Profile structure
check "profile has hy2"       jq -e '.hy2' "$TMP/etc/nanobk/profile.current.json"
check "profile has tuic"      jq -e '.tuic' "$TMP/etc/nanobk/profile.current.json"
check "profile has reality"   jq -e '.reality' "$TMP/etc/nanobk/profile.current.json"
check "profile has trojan"    jq -e '.trojan' "$TMP/etc/nanobk/profile.current.json"

# Reality private key isolation
if grep -q 'privateKey' "$TMP/etc/nanobk/profile.current.json" 2>/dev/null; then
  fail "Reality private key leaked into profile JSON"
  ERRORS=$((ERRORS + 1))
else
  pass "Reality private key NOT in profile"
fi

# Secrets permissions
SECRETS_PERMS=$(stat -c '%a' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || stat -f '%Lp' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || echo "unknown")
if [[ "$SECRETS_PERMS" == "600" ]]; then
  pass "secrets.private.env permissions: 600"
else
  fail "secrets.private.env permissions: ${SECRETS_PERMS}"
  ERRORS=$((ERRORS + 1))
fi

# Secrets contain new values (use UUID from new profile, not from old variable)
NEW_TUIC_UUID_FROM_PROFILE=$(jq -r '.tuic.uuid' "$TMP/etc/nanobk/profile.current.json")
if grep -q "TUIC_UUID=\"${NEW_TUIC_UUID_FROM_PROFILE}\"" "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null \
   || grep -q "TUIC_UUID=${NEW_TUIC_UUID_FROM_PROFILE}" "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null; then
  pass "secrets.private.env contains new TUIC UUID"
else
  fail "secrets.private.env does not contain new TUIC UUID"
  ERRORS=$((ERRORS + 1))
fi

# Also verify reality UUID changed
NEW_REALITY_UUID_FROM_PROFILE=$(jq -r '.reality.uuid' "$TMP/etc/nanobk/profile.current.json")
if [[ "$NEW_REALITY_UUID_FROM_PROFILE" != "$OLD_REALITY_UUID" ]]; then
  pass "Reality UUID changed"
else
  fail "Reality UUID did not change"
  ERRORS=$((ERRORS + 1))
fi

# Backup exists
BACKUP_DIR=$(find "$TMP/opt/nanobk/backups" -maxdepth 1 -name 'rotate-*' -type d | head -1)
if [[ -n "$BACKUP_DIR" ]]; then
  pass "Backup directory exists: $(basename "$BACKUP_DIR")"
else
  fail "No backup directory found"
  ERRORS=$((ERRORS + 1))
fi

# profile.previous.json exists
if [[ -f "$TMP/etc/nanobk/profile.previous.json" ]]; then
  pass "profile.previous.json exists"
else
  fail "profile.previous.json not found"
  ERRORS=$((ERRORS + 1))
fi

# Offline healthcheck
echo ""
echo "--- Running offline healthcheck ---"
echo ""

if bash "$ROOT/vps/scripts/healthcheck.sh" \
  --config-dir "$TMP/etc/nanobk" \
  --skip-services --skip-ports; then
  pass "offline healthcheck passed"
else
  fail "offline healthcheck failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All rotation tests passed!${NC}"
  echo "  Output: ${TMP}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  echo "  Output: ${TMP}"
  exit 1
fi
