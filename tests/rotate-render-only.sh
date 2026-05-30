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
TMP="${TMPDIR:-/tmp}/nanobk-rotate-test"
TMP_FAIL="${TMPDIR:-/tmp}/nanobk-rotate-fail-test"

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

  # Create minimal valid service configs for rotation
  cat > "$tmp/etc/nanobk/generated/hysteria/config.yaml" <<YAML
listen: :443
tls:
  cert: /dev/null
  key: /dev/null
auth:
  type: password
  password: "old-password"
YAML

  cat > "$tmp/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json" <<JSON
{
  "server": "[::]:9443",
  "users": {"old-uuid": "old-password"}
}
JSON

  cat > "$tmp/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json" <<JSON
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

  cat > "$tmp/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json" <<JSON
{
  "inbounds": [{
    "protocol": "trojan",
    "settings": {"clients": [{"password": "old-password"}]}
  }]
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
  local file="$1" path="$2"
  if command -v jq &>/dev/null; then
    jq -r "$path // empty" "$file" 2>/dev/null
  else
    python3 -c "import json; d=json.load(open('$file')); print(d$(echo "$path" | sed 's/\.\[/\[/g; s/\.\([a-zA-Z]*\)/[\"\1\"]/g'))" 2>/dev/null || echo ""
  fi
}

run_single_protocol_test() {
  local proto="$1"
  local tmp_dir="${TMPDIR:-/tmp}/nanobk-rotate-${proto}-test"

  echo "--- Testing protocol: ${proto} ---"
  echo ""

  rm -rf "$tmp_dir"
  generate_test_configs "$tmp_dir"

  # Save old values
  local old_secrets="$tmp_dir/etc/nanobk/secrets.private.env"
  local old_hy2_pw old_tuic_uuid old_tuic_pw old_reality_uuid old_reality_pub old_reality_short old_trojan_pw
  old_hy2_pw=$(read_secret "$old_secrets" "HY2_PASSWORD")
  old_tuic_uuid=$(read_secret "$old_secrets" "TUIC_UUID")
  old_tuic_pw=$(read_secret "$old_secrets" "TUIC_PASSWORD")
  old_reality_uuid=$(read_secret "$old_secrets" "REALITY_UUID")
  old_reality_pub=$(read_secret "$old_secrets" "REALITY_PUBLIC_KEY")
  old_reality_short=$(read_secret "$old_secrets" "REALITY_SHORT_ID")
  old_trojan_pw=$(read_secret "$old_secrets" "TROJAN_PASSWORD")

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

  # Read new values
  local new_secrets="$tmp_dir/etc/nanobk/secrets.private.env"
  local new_hy2_pw new_tuic_uuid new_tuic_pw new_reality_uuid new_reality_pub new_reality_short new_trojan_pw
  new_hy2_pw=$(read_secret "$new_secrets" "HY2_PASSWORD")
  new_tuic_uuid=$(read_secret "$new_secrets" "TUIC_UUID")
  new_tuic_pw=$(read_secret "$new_secrets" "TUIC_PASSWORD")
  new_reality_uuid=$(read_secret "$new_secrets" "REALITY_UUID")
  new_reality_pub=$(read_secret "$new_secrets" "REALITY_PUBLIC_KEY")
  new_reality_short=$(read_secret "$new_secrets" "REALITY_SHORT_ID")
  new_trojan_pw=$(read_secret "$new_secrets" "TROJAN_PASSWORD")

  # Verify: rotated protocol changed, others unchanged
  case "$proto" in
    hy2)
      [[ "$new_hy2_pw" != "$old_hy2_pw" ]] && pass "${proto}: HY2 password changed" || { fail "${proto}: HY2 password unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_tuic_uuid" == "$old_tuic_uuid" ]] && pass "${proto}: TUIC UUID unchanged" || { fail "${proto}: TUIC UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_reality_uuid" == "$old_reality_uuid" ]] && pass "${proto}: Reality UUID unchanged" || { fail "${proto}: Reality UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_trojan_pw" == "$old_trojan_pw" ]] && pass "${proto}: Trojan password unchanged" || { fail "${proto}: Trojan password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      ;;
    tuic)
      [[ "$new_tuic_uuid" != "$old_tuic_uuid" ]] && pass "${proto}: TUIC UUID changed" || { fail "${proto}: TUIC UUID unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_tuic_pw" != "$old_tuic_pw" ]] && pass "${proto}: TUIC password changed" || { fail "${proto}: TUIC password unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_hy2_pw" == "$old_hy2_pw" ]] && pass "${proto}: HY2 password unchanged" || { fail "${proto}: HY2 password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_reality_uuid" == "$old_reality_uuid" ]] && pass "${proto}: Reality UUID unchanged" || { fail "${proto}: Reality UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_trojan_pw" == "$old_trojan_pw" ]] && pass "${proto}: Trojan password unchanged" || { fail "${proto}: Trojan password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      ;;
    reality)
      [[ "$new_reality_uuid" != "$old_reality_uuid" ]] && pass "${proto}: Reality UUID changed" || { fail "${proto}: Reality UUID unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_reality_pub" != "$old_reality_pub" ]] && pass "${proto}: Reality public key changed" || { fail "${proto}: Reality public key unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_reality_short" != "$old_reality_short" ]] && pass "${proto}: Reality shortId changed" || { fail "${proto}: Reality shortId unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_hy2_pw" == "$old_hy2_pw" ]] && pass "${proto}: HY2 password unchanged" || { fail "${proto}: HY2 password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_tuic_uuid" == "$old_tuic_uuid" ]] && pass "${proto}: TUIC UUID unchanged" || { fail "${proto}: TUIC UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_trojan_pw" == "$old_trojan_pw" ]] && pass "${proto}: Trojan password unchanged" || { fail "${proto}: Trojan password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      ;;
    trojan)
      [[ "$new_trojan_pw" != "$old_trojan_pw" ]] && pass "${proto}: Trojan password changed" || { fail "${proto}: Trojan password unchanged"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_hy2_pw" == "$old_hy2_pw" ]] && pass "${proto}: HY2 password unchanged" || { fail "${proto}: HY2 password changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_tuic_uuid" == "$old_tuic_uuid" ]] && pass "${proto}: TUIC UUID unchanged" || { fail "${proto}: TUIC UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      [[ "$new_reality_uuid" == "$old_reality_uuid" ]] && pass "${proto}: Reality UUID unchanged" || { fail "${proto}: Reality UUID changed unexpectedly"; ERRORS=$((ERRORS + 1)); }
      ;;
  esac

  # Verify profile has all four protocols
  local profile_file="$tmp_dir/etc/nanobk/profile.current.json"
  if [[ -f "$profile_file" ]]; then
    pass "${proto}: profile exists"
    if grep -q 'privateKey' "$profile_file" 2>/dev/null; then
      fail "${proto}: Reality private key in profile"
      ERRORS=$((ERRORS + 1))
    else
      pass "${proto}: Reality private key NOT in profile"
    fi
  else
    fail "${proto}: profile missing"
    ERRORS=$((ERRORS + 1))
  fi

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
