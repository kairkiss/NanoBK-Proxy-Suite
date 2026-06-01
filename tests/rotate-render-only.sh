#!/usr/bin/env bash
# NanoBK Proxy Suite — Key Rotation Render Test
#
# Tests:
#   A. Normal rotation succeeds (credentials change, profile valid, no key leak)
#   B. Rollback restores correct per-protocol files on failure
#
# Requirements: jq
#
# Usage:
#   bash tests/rotate-render-only.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nanobk-rotate-test-XXXXXX")
TMP_FAIL=$(mktemp -d "${TMPDIR:-/tmp}/nanobk-rotate-fail-XXXXXX")

# Cleanup on exit
cleanup() {
  rm -rf "$TMP" "$TMP_FAIL" 2>/dev/null || true
}
trap cleanup EXIT

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

# Assert a JSON field path is non-empty in a file
assert_json_field_nonempty() {
  local file="$1"
  local expr="$2"
  local label="$3"
  python3 - "$file" "$expr" "$label" <<'PY'
import json, sys
path, expr, label = sys.argv[1:]
d=json.load(open(path))
cur=d
for part in expr.split("."):
    if part.endswith("]"):
        name, idx = part[:-1].split("[")
        cur = cur[name][int(idx)]
    else:
        cur = cur[part]
if cur is None or cur == "" or cur == []:
    print(f"missing/empty: {label}", file=sys.stderr)
    sys.exit(1)
PY
}

# Validate Xray Reality/Trojan configs are complete and valid
validate_xray_fixture_configs() {
  local tmp="$1"
  local phase="${2:-fixture}"
  local reality_cfg="$tmp/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json"
  local trojan_cfg="$tmp/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json"
  local fixture_errors=0

  echo "--- Validating ${phase} Xray fixture configs ---"

  # Reality field checks
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].listen" "${phase}: Reality.listen" || { echo "  FAIL: Reality.listen"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].port" "${phase}: Reality.port" || { echo "  FAIL: Reality.port"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].settings.clients[0].id" "${phase}: Reality.client id" || { echo "  FAIL: Reality.client id"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.network" "${phase}: Reality.network" || { echo "  FAIL: Reality.network"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.security" "${phase}: Reality.security" || { echo "  FAIL: Reality.security"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.realitySettings.dest" "${phase}: Reality.dest" || { echo "  FAIL: Reality.dest"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.realitySettings.serverNames" "${phase}: Reality.serverNames" || { echo "  FAIL: Reality.serverNames"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.realitySettings.privateKey" "${phase}: Reality.privateKey" || { echo "  FAIL: Reality.privateKey"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$reality_cfg" "inbounds[0].streamSettings.realitySettings.shortIds" "${phase}: Reality.shortIds" || { echo "  FAIL: Reality.shortIds"; fixture_errors=$((fixture_errors + 1)); }

  # Trojan field checks
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].listen" "${phase}: Trojan.listen" || { echo "  FAIL: Trojan.listen"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].port" "${phase}: Trojan.port" || { echo "  FAIL: Trojan.port"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].settings.clients[0].password" "${phase}: Trojan.password" || { echo "  FAIL: Trojan.password"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].streamSettings.network" "${phase}: Trojan.network" || { echo "  FAIL: Trojan.network"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].streamSettings.security" "${phase}: Trojan.security" || { echo "  FAIL: Trojan.security"; fixture_errors=$((fixture_errors + 1)); }
  assert_json_field_nonempty "$trojan_cfg" "inbounds[0].streamSettings.tlsSettings.certificates" "${phase}: Trojan.certificates" || { echo "  FAIL: Trojan.certificates"; fixture_errors=$((fixture_errors + 1)); }

  # xray validation if available
  if command -v xray >/dev/null 2>&1; then
    if xray -test -config "$reality_cfg" >/dev/null 2>&1; then
      pass "${phase}: Reality config xray -test passed"
    else
      fail "${phase}: Reality config xray -test failed"
      xray -test -config "$reality_cfg" 2>&1 | tail -5
      fixture_errors=$((fixture_errors + 1))
    fi
    if xray -test -config "$trojan_cfg" >/dev/null 2>&1; then
      pass "${phase}: Trojan config xray -test passed"
    else
      fail "${phase}: Trojan config xray -test failed"
      xray -test -config "$trojan_cfg" 2>&1 | tail -5
      fixture_errors=$((fixture_errors + 1))
    fi
  else
    echo "xray not found; JSON field validation used for ${phase}"
  fi

  return $fixture_errors
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

# ── Helper: generate test configs ───────────────────────────────────────────

generate_test_configs() {
  local tmp="$1"

  rm -rf "$tmp"

  bash "$ROOT/installer/install-vps.sh" --render-only --yes \
    --install-dir "$tmp/opt/nanobk" \
    --config-dir "$tmp/etc/nanobk" \
    --domain proxy.example.com \
    --vps-ip 198.51.100.10 \
    --cert-mode self-signed

  # Read real values from secrets generated by render-only
  local secrets_file="$tmp/etc/nanobk/secrets.private.env"
  local reality_uuid reality_priv reality_short trojan_pw
  reality_uuid=$(grep "^REALITY_UUID=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  reality_priv=$(grep "^REALITY_PRIVATE_KEY=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  reality_short=$(grep "^REALITY_SHORT_ID=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  trojan_pw=$(grep "^TROJAN_PASSWORD=" "$secrets_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')

  # Validate required values exist
  if [[ -z "$reality_uuid" ]] || [[ -z "$reality_priv" ]] || [[ -z "$reality_short" ]] || [[ -z "$trojan_pw" ]]; then
    echo "[ERROR] Missing required secrets from render-only output" >&2
    echo "  REALITY_UUID=${reality_uuid:-<empty>}" >&2
    echo "  REALITY_PRIVATE_KEY=${reality_priv:+<present>}${reality_priv:-<empty>}" >&2
    echo "  REALITY_SHORT_ID=${reality_short:-<empty>}" >&2
    echo "  TROJAN_PASSWORD=${trojan_pw:+<present>}${trojan_pw:-<empty>}" >&2
    return 1
  fi

  # Overwrite Reality config with real values from secrets
  cat > "$tmp/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json" <<JSON
{
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 8443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "${reality_uuid}", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "${reality_priv}",
        "shortIds": ["${reality_short}"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JSON

  # Overwrite Trojan config with real values from secrets
  cat > "$tmp/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json" <<JSON
{
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 2443,
    "protocol": "trojan",
    "settings": {
      "clients": [{"password": "${trojan_pw}"}]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "certificates": [{
          "certificateFile": "$tmp/etc/nanobk/certs/selfsigned.fullchain.pem",
          "keyFile": "$tmp/etc/nanobk/certs/selfsigned.privkey.pem"
        }]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JSON
}

# ═══════════════════════════════════════════════════════════════════════════
# Test A: Normal rotation
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Test A: Normal Rotation                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "--- Generating initial configs ---"
echo ""

generate_test_configs "$TMP"

# Validate fixture configs before rotation
validate_xray_fixture_configs "$TMP" "Test A pre-rotate" || {
  fail "Test A: fixture validation failed before rotation"
  ERRORS=$((ERRORS + 1))
}

# Save old credentials
OLD_TUIC_UUID=$(jq -r '.tuic.uuid' "$TMP/etc/nanobk/profile.current.json")
OLD_HY2_PW=$(jq -r '.hy2.password' "$TMP/etc/nanobk/profile.current.json")
OLD_REALITY_UUID=$(jq -r '.reality.uuid' "$TMP/etc/nanobk/profile.current.json")
pass "Saved old credentials for comparison"

echo ""
echo "--- Running key rotation ---"
echo ""

bash "$ROOT/vps/scripts/rotate-keys.sh" --yes \
  --config-dir "$TMP/etc/nanobk" \
  --install-dir "$TMP/opt/nanobk" \
  --skip-services \
  --skip-cloudflare \
  --allow-placeholder-reality

echo ""
echo "--- Verifying rotation results ---"
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

# Validate Reality config completeness after rotation
REALITY_CFG="$TMP/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json"
if [[ -f "$REALITY_CFG" ]]; then
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].listen" "Reality.listen" && pass "Reality config: listen" || { fail "Reality config: listen missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].port" "Reality.port" && pass "Reality config: port" || { fail "Reality config: port missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.network" "Reality.network" && pass "Reality config: network" || { fail "Reality config: network missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.security" "Reality.security" && pass "Reality config: security" || { fail "Reality config: security missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.realitySettings.dest" "Reality.dest" && pass "Reality config: dest" || { fail "Reality config: dest missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.realitySettings.serverNames" "Reality.serverNames" && pass "Reality config: serverNames" || { fail "Reality config: serverNames missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.realitySettings.privateKey" "Reality.privateKey" && pass "Reality config: privateKey" || { fail "Reality config: privateKey missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$REALITY_CFG" "inbounds[0].streamSettings.realitySettings.shortIds" "Reality.shortIds" && pass "Reality config: shortIds" || { fail "Reality config: shortIds missing"; ERRORS=$((ERRORS + 1)); }
fi

# Validate Trojan config completeness after rotation
TROJAN_CFG="$TMP/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json"
if [[ -f "$TROJAN_CFG" ]]; then
  assert_json_field_nonempty "$TROJAN_CFG" "inbounds[0].listen" "Trojan.listen" && pass "Trojan config: listen" || { fail "Trojan config: listen missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$TROJAN_CFG" "inbounds[0].port" "Trojan.port" && pass "Trojan config: port" || { fail "Trojan config: port missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$TROJAN_CFG" "inbounds[0].streamSettings.network" "Trojan.network" && pass "Trojan config: network" || { fail "Trojan config: network missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$TROJAN_CFG" "inbounds[0].streamSettings.security" "Trojan.security" && pass "Trojan config: security" || { fail "Trojan config: security missing"; ERRORS=$((ERRORS + 1)); }
  assert_json_field_nonempty "$TROJAN_CFG" "inbounds[0].streamSettings.tlsSettings.certificates" "Trojan.certificates" && pass "Trojan config: certificates" || { fail "Trojan config: certificates missing"; ERRORS=$((ERRORS + 1)); }
fi

# Secrets permissions
SECRETS_PERMS=$(stat -c '%a' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || stat -f '%Lp' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || echo "unknown")
if [[ "$SECRETS_PERMS" == "600" ]]; then
  pass "secrets.private.env permissions: 600"
else
  fail "secrets.private.env permissions: ${SECRETS_PERMS}"
  ERRORS=$((ERRORS + 1))
fi

# Secrets contain new values
NEW_TUIC_UUID_FROM_PROFILE=$(jq -r '.tuic.uuid' "$TMP/etc/nanobk/profile.current.json")
if grep -q "TUIC_UUID=\"${NEW_TUIC_UUID_FROM_PROFILE}\"" "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null \
   || grep -q "TUIC_UUID=${NEW_TUIC_UUID_FROM_PROFILE}" "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null; then
  pass "secrets.private.env contains new TUIC UUID"
else
  fail "secrets.private.env does not contain new TUIC UUID"
  ERRORS=$((ERRORS + 1))
fi

# Reality UUID changed
NEW_REALITY_UUID_FROM_PROFILE=$(jq -r '.reality.uuid' "$TMP/etc/nanobk/profile.current.json")
if [[ "$NEW_REALITY_UUID_FROM_PROFILE" != "$OLD_REALITY_UUID" ]]; then
  pass "Reality UUID changed"
else
  fail "Reality UUID did not change"
  ERRORS=$((ERRORS + 1))
fi

# Backup exists with unique names
BACKUP_DIR=$(find "$TMP/opt/nanobk/backups" -maxdepth 1 -name 'rotate-*' -type d | head -1)
if [[ -n "$BACKUP_DIR" ]]; then
  pass "Backup directory exists: $(basename "$BACKUP_DIR")"

  # Check all four backup files exist with unique names
  check "hy2.config.yaml.bak exists"     test -f "$BACKUP_DIR/hy2.config.yaml.bak"
  check "tuic.config.json.bak exists"    test -f "$BACKUP_DIR/tuic.config.json.bak"
  check "reality.config.json.bak exists" test -f "$BACKUP_DIR/reality.config.json.bak"
  check "trojan.config.json.bak exists"  test -f "$BACKUP_DIR/trojan.config.json.bak"

  # Verify they are different files (not overwritten by each other)
  hy2_size=$(wc -c < "$BACKUP_DIR/hy2.config.yaml.bak" | tr -d ' ')
  tuic_size=$(wc -c < "$BACKUP_DIR/tuic.config.json.bak" | tr -d ' ')
  reality_size=$(wc -c < "$BACKUP_DIR/reality.config.json.bak" | tr -d ' ')
  trojan_size=$(wc -c < "$BACKUP_DIR/trojan.config.json.bak" | tr -d ' ')

  if [[ "$tuic_size" != "$reality_size" ]] || [[ "$tuic_size" != "$trojan_size" ]]; then
    pass "Backup files have different sizes (no collision)"
  else
    # Content check: JSON files may coincidentally have same size
    if ! diff -q "$BACKUP_DIR/tuic.config.json.bak" "$BACKUP_DIR/reality.config.json.bak" >/dev/null 2>&1; then
      pass "Backup files have different content (no collision)"
    else
      fail "tuic and reality backup files are identical (collision!)"
      ERRORS=$((ERRORS + 1))
    fi
  fi
else
  fail "No backup directory found"
  ERRORS=$((ERRORS + 1))
fi

# profile.previous.json exists
check "profile.previous.json exists" test -f "$TMP/etc/nanobk/profile.previous.json"

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

# ═══════════════════════════════════════════════════════════════════════════
# Test B: Rollback on failure
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Test B: Rollback on Failure                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "--- Generating fresh configs for rollback test ---"
echo ""

generate_test_configs "$TMP_FAIL"

# Inject markers into configs
HY2_MARKER="HY2_MARKER_BEFORE_$(date +%s)"
TUIC_MARKER="TUIC_MARKER_BEFORE_$(date +%s)"
REALITY_MARKER="REALITY_MARKER_BEFORE_$(date +%s)"
TROJAN_MARKER="TROJAN_MARKER_BEFORE_$(date +%s)"

# HY2: add marker comment
echo "# ${HY2_MARKER}" >> "$TMP_FAIL/etc/nanobk/generated/hysteria/config.yaml"

# TUIC: add marker field
python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json') as f:
    data = json.load(f)
data['_test_marker'] = '${TUIC_MARKER}'
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Reality: add marker field
python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json') as f:
    data = json.load(f)
data['_test_marker'] = '${REALITY_MARKER}'
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Trojan: add marker field
python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json') as f:
    data = json.load(f)
data['_test_marker'] = '${TROJAN_MARKER}'
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json', 'w') as f:
    json.dump(data, f, indent=2)
"

pass "Injected markers into configs"

echo ""
echo "--- Running rotation with forced failure ---"
echo ""

# This should fail after patching (NANOBK_TEST_FAIL_AFTER_PATCH=1)
if NANOBK_TEST_FAIL_AFTER_PATCH=1 bash "$ROOT/vps/scripts/rotate-keys.sh" --yes \
  --config-dir "$TMP_FAIL/etc/nanobk" \
  --install-dir "$TMP_FAIL/opt/nanobk" \
  --skip-services \
  --skip-cloudflare \
  --allow-placeholder-reality 2>&1; then
  fail "Rotation should have failed but succeeded"
  ERRORS=$((ERRORS + 1))
else
  pass "Rotation failed as expected (test hook triggered)"
fi

echo ""
echo "--- Verifying rollback restored original files ---"
echo ""

# Check markers are still present (rollback restored originals)
if grep -q "$HY2_MARKER" "$TMP_FAIL/etc/nanobk/generated/hysteria/config.yaml" 2>/dev/null; then
  pass "HY2 config restored (marker present)"
else
  fail "HY2 config NOT restored (marker missing)"
  ERRORS=$((ERRORS + 1))
fi

if python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json') as f:
    data = json.load(f)
assert data.get('_test_marker') == '${TUIC_MARKER}', f'got: {data.get(\"_test_marker\")}'
" 2>/dev/null; then
  pass "TUIC config restored (marker present)"
else
  fail "TUIC config NOT restored (marker missing or wrong)"
  ERRORS=$((ERRORS + 1))
fi

if python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json') as f:
    data = json.load(f)
assert data.get('_test_marker') == '${REALITY_MARKER}', f'got: {data.get(\"_test_marker\")}'
" 2>/dev/null; then
  pass "Reality config restored (marker present)"
else
  fail "Reality config NOT restored (marker missing or wrong)"
  ERRORS=$((ERRORS + 1))
fi

if python3 -c "
import json
with open('$TMP_FAIL/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json') as f:
    data = json.load(f)
assert data.get('_test_marker') == '${TROJAN_MARKER}', f'got: {data.get(\"_test_marker\")}'
" 2>/dev/null; then
  pass "Trojan config restored (marker present)"
else
  fail "Trojan config NOT restored (marker missing or wrong)"
  ERRORS=$((ERRORS + 1))
fi

# Verify backup directory has unique files
FAIL_BACKUP_DIR=$(find "$TMP_FAIL/opt/nanobk/backups" -maxdepth 1 -name 'rotate-*' -type d | head -1)
if [[ -n "$FAIL_BACKUP_DIR" ]]; then
  pass "Rollback backup directory exists: $(basename "$FAIL_BACKUP_DIR")"
  check "rollback backup has hy2.config.yaml.bak"     test -f "$FAIL_BACKUP_DIR/hy2.config.yaml.bak"
  check "rollback backup has tuic.config.json.bak"    test -f "$FAIL_BACKUP_DIR/tuic.config.json.bak"
  check "rollback backup has reality.config.json.bak" test -f "$FAIL_BACKUP_DIR/reality.config.json.bak"
  check "rollback backup has trojan.config.json.bak"  test -f "$FAIL_BACKUP_DIR/trojan.config.json.bak"
else
  fail "No rollback backup directory found"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Test C: Single-protocol rotation matrix
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Test C: Single-Protocol Rotation                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Helper: read a value from secrets file
read_secret() {
  local file="$1" key="$2"
  grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || echo ""
}

# Helper: read a value from profile JSON
read_profile() {
  local file="$1" field="$2"
  if command -v jq &>/dev/null; then
    jq -r "${field} // empty" "$file" 2>/dev/null
  else
    # python3 fallback for common paths
    python3 -c "
import json, sys
d = json.load(open('$file'))
keys = '$field'.lstrip('.').split('.')
for k in keys:
    if isinstance(d, dict):
        d = d.get(k, '')
    else:
        d = ''
        break
print(d if d else '')
" 2>/dev/null || echo ""
  fi
}

run_single_protocol_test() {
  local proto="$1"
  local tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/nanobk-rotate-${proto}-XXXXXX")

  echo "--- Testing protocol: ${proto} ---"
  echo ""

  rm -rf "$tmp_dir"
  generate_test_configs "$tmp_dir"

  # Validate fixture configs before rotation
  validate_xray_fixture_configs "$tmp_dir" "${proto} pre-rotate" || {
    fail "${proto}: fixture validation failed before rotation"
    ERRORS=$((ERRORS + 1))
    rm -rf "$tmp_dir"
    return
  }

  # Save old secrets values
  local old_secrets="$tmp_dir/etc/nanobk/secrets.private.env"
  local old_hy2_pw old_tuic_uuid old_tuic_pw old_reality_uuid old_reality_pub old_reality_short old_trojan_pw
  old_hy2_pw=$(read_secret "$old_secrets" "HY2_PASSWORD")
  old_tuic_uuid=$(read_secret "$old_secrets" "TUIC_UUID")
  old_tuic_pw=$(read_secret "$old_secrets" "TUIC_PASSWORD")
  old_reality_uuid=$(read_secret "$old_secrets" "REALITY_UUID")
  old_reality_pub=$(read_secret "$old_secrets" "REALITY_PUBLIC_KEY")
  old_reality_short=$(read_secret "$old_secrets" "REALITY_SHORT_ID")
  old_trojan_pw=$(read_secret "$old_secrets" "TROJAN_PASSWORD")

  # Save old profile values
  local old_profile="$tmp_dir/etc/nanobk/profile.current.json"
  local old_p_hy2_pw old_p_tuic_uuid old_p_tuic_pw old_p_reality_uuid old_p_reality_pub old_p_reality_short old_p_trojan_pw
  old_p_hy2_pw=$(read_profile "$old_profile" ".hy2.password")
  old_p_tuic_uuid=$(read_profile "$old_profile" ".tuic.uuid")
  old_p_tuic_pw=$(read_profile "$old_profile" ".tuic.password")
  old_p_reality_uuid=$(read_profile "$old_profile" ".reality.uuid")
  old_p_reality_pub=$(read_profile "$old_profile" ".reality.publicKey")
  old_p_reality_short=$(read_profile "$old_profile" ".reality.shortId")
  old_p_trojan_pw=$(read_profile "$old_profile" ".trojan.password")

  # Run rotation
  if bash "$ROOT/vps/scripts/rotate-keys.sh" --yes \
    --config-dir "$tmp_dir/etc/nanobk" \
    --install-dir "$tmp_dir/opt/nanobk" \
    --skip-services --skip-cloudflare \
    --allow-placeholder-reality \
    --protocol "$proto" 2>&1; then
    pass "${proto}: rotation completed"
  else
    fail "${proto}: rotation failed"
    ERRORS=$((ERRORS + 1))
    rm -rf "$tmp_dir"
    return
  fi

  # Read new secrets values
  local new_secrets="$tmp_dir/etc/nanobk/secrets.private.env"
  local new_hy2_pw new_tuic_uuid new_tuic_pw new_reality_uuid new_reality_pub new_reality_short new_trojan_pw
  new_hy2_pw=$(read_secret "$new_secrets" "HY2_PASSWORD")
  new_tuic_uuid=$(read_secret "$new_secrets" "TUIC_UUID")
  new_tuic_pw=$(read_secret "$new_secrets" "TUIC_PASSWORD")
  new_reality_uuid=$(read_secret "$new_secrets" "REALITY_UUID")
  new_reality_pub=$(read_secret "$new_secrets" "REALITY_PUBLIC_KEY")
  new_reality_short=$(read_secret "$new_secrets" "REALITY_SHORT_ID")
  new_trojan_pw=$(read_secret "$new_secrets" "TROJAN_PASSWORD")

  # Read new profile values
  local new_profile="$tmp_dir/etc/nanobk/profile.current.json"
  local new_p_hy2_pw new_p_tuic_uuid new_p_tuic_pw new_p_reality_uuid new_p_reality_pub new_p_reality_short new_p_trojan_pw
  new_p_hy2_pw=$(read_profile "$new_profile" ".hy2.password")
  new_p_tuic_uuid=$(read_profile "$new_profile" ".tuic.uuid")
  new_p_tuic_pw=$(read_profile "$new_profile" ".tuic.password")
  new_p_reality_uuid=$(read_profile "$new_profile" ".reality.uuid")
  new_p_reality_pub=$(read_profile "$new_profile" ".reality.publicKey")
  new_p_reality_short=$(read_profile "$new_profile" ".reality.shortId")
  new_p_trojan_pw=$(read_profile "$new_profile" ".trojan.password")

  # Helper: assert changed
  assert_changed() {
    local label="$1" old="$2" new="$3"
    if [[ "$old" != "$new" ]]; then
      pass "${proto}: ${label} changed"
    else
      fail "${proto}: ${label} unchanged"
      ERRORS=$((ERRORS + 1))
    fi
  }

  # Helper: assert unchanged
  assert_unchanged() {
    local label="$1" old="$2" new="$3"
    if [[ "$old" == "$new" ]]; then
      pass "${proto}: ${label} unchanged"
    else
      fail "${proto}: ${label} changed unexpectedly"
      ERRORS=$((ERRORS + 1))
    fi
  }

  # ── Verify secrets changes ──
  case "$proto" in
    hy2)
      assert_changed "secrets.HY2 password" "$old_hy2_pw" "$new_hy2_pw"
      assert_unchanged "secrets.TUIC UUID" "$old_tuic_uuid" "$new_tuic_uuid"
      assert_unchanged "secrets.Reality UUID" "$old_reality_uuid" "$new_reality_uuid"
      assert_unchanged "secrets.Trojan password" "$old_trojan_pw" "$new_trojan_pw"
      ;;
    tuic)
      assert_changed "secrets.TUIC UUID" "$old_tuic_uuid" "$new_tuic_uuid"
      assert_changed "secrets.TUIC password" "$old_tuic_pw" "$new_tuic_pw"
      assert_unchanged "secrets.HY2 password" "$old_hy2_pw" "$new_hy2_pw"
      assert_unchanged "secrets.Reality UUID" "$old_reality_uuid" "$new_reality_uuid"
      assert_unchanged "secrets.Trojan password" "$old_trojan_pw" "$new_trojan_pw"
      ;;
    reality)
      assert_changed "secrets.Reality UUID" "$old_reality_uuid" "$new_reality_uuid"
      assert_changed "secrets.Reality public key" "$old_reality_pub" "$new_reality_pub"
      assert_changed "secrets.Reality shortId" "$old_reality_short" "$new_reality_short"
      assert_unchanged "secrets.HY2 password" "$old_hy2_pw" "$new_hy2_pw"
      assert_unchanged "secrets.TUIC UUID" "$old_tuic_uuid" "$new_tuic_uuid"
      assert_unchanged "secrets.Trojan password" "$old_trojan_pw" "$new_trojan_pw"
      ;;
    trojan)
      assert_changed "secrets.Trojan password" "$old_trojan_pw" "$new_trojan_pw"
      assert_unchanged "secrets.HY2 password" "$old_hy2_pw" "$new_hy2_pw"
      assert_unchanged "secrets.TUIC UUID" "$old_tuic_uuid" "$new_tuic_uuid"
      assert_unchanged "secrets.Reality UUID" "$old_reality_uuid" "$new_reality_uuid"
      ;;
  esac

  # ── Verify profile changes ──
  case "$proto" in
    hy2)
      assert_changed "profile.hy2.password" "$old_p_hy2_pw" "$new_p_hy2_pw"
      assert_unchanged "profile.tuic.uuid" "$old_p_tuic_uuid" "$new_p_tuic_uuid"
      assert_unchanged "profile.tuic.password" "$old_p_tuic_pw" "$new_p_tuic_pw"
      assert_unchanged "profile.reality.uuid" "$old_p_reality_uuid" "$new_p_reality_uuid"
      assert_unchanged "profile.reality.publicKey" "$old_p_reality_pub" "$new_p_reality_pub"
      assert_unchanged "profile.reality.shortId" "$old_p_reality_short" "$new_p_reality_short"
      assert_unchanged "profile.trojan.password" "$old_p_trojan_pw" "$new_p_trojan_pw"
      ;;
    tuic)
      assert_changed "profile.tuic.uuid" "$old_p_tuic_uuid" "$new_p_tuic_uuid"
      assert_changed "profile.tuic.password" "$old_p_tuic_pw" "$new_p_tuic_pw"
      assert_unchanged "profile.hy2.password" "$old_p_hy2_pw" "$new_p_hy2_pw"
      assert_unchanged "profile.reality.uuid" "$old_p_reality_uuid" "$new_p_reality_uuid"
      assert_unchanged "profile.reality.publicKey" "$old_p_reality_pub" "$new_p_reality_pub"
      assert_unchanged "profile.reality.shortId" "$old_p_reality_short" "$new_p_reality_short"
      assert_unchanged "profile.trojan.password" "$old_p_trojan_pw" "$new_p_trojan_pw"
      ;;
    reality)
      assert_changed "profile.reality.uuid" "$old_p_reality_uuid" "$new_p_reality_uuid"
      assert_changed "profile.reality.publicKey" "$old_p_reality_pub" "$new_p_reality_pub"
      assert_changed "profile.reality.shortId" "$old_p_reality_short" "$new_p_reality_short"
      assert_unchanged "profile.hy2.password" "$old_p_hy2_pw" "$new_p_hy2_pw"
      assert_unchanged "profile.tuic.uuid" "$old_p_tuic_uuid" "$new_p_tuic_uuid"
      assert_unchanged "profile.tuic.password" "$old_p_tuic_pw" "$new_p_tuic_pw"
      assert_unchanged "profile.trojan.password" "$old_p_trojan_pw" "$new_p_trojan_pw"
      ;;
    trojan)
      assert_changed "profile.trojan.password" "$old_p_trojan_pw" "$new_p_trojan_pw"
      assert_unchanged "profile.hy2.password" "$old_p_hy2_pw" "$new_p_hy2_pw"
      assert_unchanged "profile.tuic.uuid" "$old_p_tuic_uuid" "$new_p_tuic_uuid"
      assert_unchanged "profile.tuic.password" "$old_p_tuic_pw" "$new_p_tuic_pw"
      assert_unchanged "profile.reality.uuid" "$old_p_reality_uuid" "$new_p_reality_uuid"
      assert_unchanged "profile.reality.publicKey" "$old_p_reality_pub" "$new_p_reality_pub"
      assert_unchanged "profile.reality.shortId" "$old_p_reality_short" "$new_p_reality_short"
      ;;
  esac

  # ── Verify profile structure ──
  if [[ -f "$new_profile" ]]; then
    pass "${proto}: profile exists"
    if grep -q 'privateKey' "$new_profile" 2>/dev/null; then
      fail "${proto}: Reality private key in profile"
      ERRORS=$((ERRORS + 1))
    else
      pass "${proto}: Reality private key NOT in profile"
    fi
  else
    fail "${proto}: profile missing"
    ERRORS=$((ERRORS + 1))
  fi

  # ── Post-rotate fixture validation ──
  validate_xray_fixture_configs "$tmp_dir" "${proto} post-rotate" || {
    fail "${proto}: fixture validation failed after rotation"
    ERRORS=$((ERRORS + 1))
  }

  rm -rf "$tmp_dir"
  echo ""
}

run_single_protocol_test hy2
run_single_protocol_test tuic
run_single_protocol_test reality
run_single_protocol_test trojan

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All rotation tests passed!${NC}"
  echo "  Output A: ${TMP}"
  echo "  Output B: ${TMP_FAIL}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  echo "  Output A: ${TMP}"
  echo "  Output B: ${TMP_FAIL}"
  exit 1
fi
