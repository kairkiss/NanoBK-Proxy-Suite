#!/usr/bin/env bash
# NanoBK Proxy Suite — Render Integration Test
#
# Tests the VPS installer in render-only mode, verifying:
#   - All expected files are generated
#   - JSON configs are valid
#   - No placeholder residues remain
#   - Reality private key is NOT in profile JSON
#   - Healthcheck passes in offline mode
#   - config.env paths are consistent
#
# Requirements:
#   - jq (mandatory for JSON validation)
#
# Usage:
#   bash tests/render-install-vps.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-render-test"

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
echo "=== NanoBK Render Integration Test ==="
echo ""

if ! command -v jq &>/dev/null; then
  fail "jq is required for render integration test"
  echo "  Install jq first:"
  echo "    macOS:          brew install jq"
  echo "    Debian/Ubuntu:  sudo apt-get install -y jq"
  echo "    RHEL/Rocky:     sudo dnf install -y jq"
  exit 1
fi
pass "jq found: $(command -v jq)"

echo "  Temp dir: ${TMP}"
echo ""

rm -rf "$TMP"

# ── Run installer in render-only mode ───────────────────────────────────────

echo "--- Running install-vps.sh --render-only ---"
echo ""

bash "$ROOT/installer/install-vps.sh" --render-only --yes \
  --install-dir "$TMP/opt/nanobk" \
  --config-dir "$TMP/etc/nanobk" \
  --domain proxy.example.com \
  --vps-ip 198.51.100.10 \
  --cert-mode self-signed

echo ""

# ── Check expected files exist ──────────────────────────────────────────────

echo "--- Checking expected files ---"
echo ""

check "config.env exists"               test -f "$TMP/etc/nanobk/config.env"
check "secrets.private.env exists"       test -f "$TMP/etc/nanobk/secrets.private.env"
check "profile.initial.json exists"      test -f "$TMP/etc/nanobk/profile.initial.json"
check "profile.current.json exists"      test -f "$TMP/etc/nanobk/profile.current.json"
check "selfsigned.fullchain.pem exists"  test -f "$TMP/etc/nanobk/certs/selfsigned.fullchain.pem"
check "selfsigned.privkey.pem exists"    test -f "$TMP/etc/nanobk/certs/selfsigned.privkey.pem"

check "HY2 config exists"               test -f "$TMP/etc/nanobk/generated/hysteria/config.yaml"
check "TUIC config exists"              test -f "$TMP/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json"
check "Reality config exists"           test -f "$TMP/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json"
check "Trojan config exists"            test -f "$TMP/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json"

check "hysteria-server.service exists"  test -f "$TMP/etc/nanobk/systemd/hysteria-server.service"
check "tuic-v5-9443.service exists"     test -f "$TMP/etc/nanobk/systemd/tuic-v5-9443.service"
check "xray-reality-8443.service exists" test -f "$TMP/etc/nanobk/systemd/xray-reality-8443.service"
check "xray-trojan-2443.service exists" test -f "$TMP/etc/nanobk/systemd/xray-trojan-2443.service"

echo ""

# ── Check secrets permissions ───────────────────────────────────────────────

echo "--- Checking secrets permissions ---"
echo ""

SECRETS_PERMS=$(stat -c '%a' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || stat -f '%Lp' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null || echo "unknown")
if [[ "$SECRETS_PERMS" == "600" ]]; then
  pass "secrets.private.env permissions: 600"
else
  fail "secrets.private.env permissions: ${SECRETS_PERMS} (expected 600)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Validate JSON configs ───────────────────────────────────────────────────

echo "--- Validating JSON configs ---"
echo ""

check "TUIC config is valid JSON"      jq . "$TMP/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json"
check "Reality config is valid JSON"   jq . "$TMP/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json"
check "Trojan config is valid JSON"    jq . "$TMP/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json"
check "profile.current.json is valid"  jq . "$TMP/etc/nanobk/profile.current.json"

echo ""

# ── Validate profile structure ──────────────────────────────────────────────

echo "--- Validating profile JSON structure ---"
echo ""

check "profile has hy2 section"        jq -e '.hy2' "$TMP/etc/nanobk/profile.current.json"
check "profile has tuic section"       jq -e '.tuic' "$TMP/etc/nanobk/profile.current.json"
check "profile has reality section"    jq -e '.reality' "$TMP/etc/nanobk/profile.current.json"
check "profile has trojan section"     jq -e '.trojan' "$TMP/etc/nanobk/profile.current.json"
check "profile has extraNodes"         jq -e '.extraNodes' "$TMP/etc/nanobk/profile.current.json"

check "reality has publicKey"          jq -e '.reality.publicKey' "$TMP/etc/nanobk/profile.current.json"
check "reality has shortId"            jq -e '.reality.shortId' "$TMP/etc/nanobk/profile.current.json"

check "hy2 server is proxy.example.com" jq -e '.hy2.server == "proxy.example.com"' "$TMP/etc/nanobk/profile.current.json"
check "reality server is 198.51.100.10" jq -e '.reality.server == "198.51.100.10"' "$TMP/etc/nanobk/profile.current.json"

echo ""

# ── Check Reality private key NOT in profile ────────────────────────────────

echo "--- Checking Reality private key isolation ---"
echo ""

if grep -q 'privateKey' "$TMP/etc/nanobk/profile.current.json" 2>/dev/null; then
  fail "Reality private key leaked into profile JSON (found 'privateKey')"
  ERRORS=$((ERRORS + 1))
else
  pass "No 'privateKey' in profile JSON"
fi

if grep -q 'REALITY_PRIVATE_KEY' "$TMP/etc/nanobk/profile.current.json" 2>/dev/null; then
  fail "REALITY_PRIVATE_KEY placeholder leaked into profile JSON"
  ERRORS=$((ERRORS + 1))
else
  pass "No 'REALITY_PRIVATE_KEY' in profile JSON"
fi

if grep -q 'REALITY_PRIVATE_KEY=' "$TMP/etc/nanobk/secrets.private.env" 2>/dev/null; then
  pass "REALITY_PRIVATE_KEY found in secrets.private.env"
else
  fail "REALITY_PRIVATE_KEY missing from secrets.private.env"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Check no placeholder residue ────────────────────────────────────────────

echo "--- Checking for placeholder residues ---"
echo ""

PLACEHOLDER_FOUND=0

for dir in \
  "$TMP/etc/nanobk/generated" \
  "$TMP/etc/nanobk/systemd" \
  "$TMP/etc/nanobk/certs"; do
  if [[ -d "$dir" ]]; then
    if grep -R '__[A-Z0-9_]\+__' "$dir" 2>/dev/null; then
      PLACEHOLDER_FOUND=1
    fi
  fi
done

for f in \
  "$TMP/etc/nanobk/config.env" \
  "$TMP/etc/nanobk/secrets.private.env" \
  "$TMP/etc/nanobk/profile.current.json"; do
  if [[ -f "$f" ]]; then
    if grep -q '__[A-Z0-9_]\+__' "$f" 2>/dev/null; then
      fail "Placeholder residue in: $f"
      PLACEHOLDER_FOUND=1
    fi
  fi
done

if [[ "$PLACEHOLDER_FOUND" == "0" ]]; then
  pass "No unreplaced placeholders found"
else
  fail "Unreplaced placeholders found"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Check config.env paths are consistent ───────────────────────────────────

echo "--- Checking config.env path consistency ---"
echo ""

# shellcheck source=/dev/null
source "$TMP/etc/nanobk/config.env"

if [[ "${NANOBK_SYSTEMD_DIR:-}" == "$TMP/etc/nanobk/systemd" ]]; then
  pass "config.env NANOBK_SYSTEMD_DIR points to render systemd dir"
else
  fail "config.env NANOBK_SYSTEMD_DIR is wrong: ${NANOBK_SYSTEMD_DIR:-<empty>}"
  ERRORS=$((ERRORS + 1))
fi

if [[ "${NANOBK_CONFIG_DIR:-}" == "$TMP/etc/nanobk" ]]; then
  pass "config.env NANOBK_CONFIG_DIR is correct"
else
  fail "config.env NANOBK_CONFIG_DIR is wrong: ${NANOBK_CONFIG_DIR:-<empty>}"
  ERRORS=$((ERRORS + 1))
fi

if [[ "${NANOBK_INSTALL_DIR:-}" == "$TMP/opt/nanobk" ]]; then
  pass "config.env NANOBK_INSTALL_DIR is correct"
else
  fail "config.env NANOBK_INSTALL_DIR is wrong: ${NANOBK_INSTALL_DIR:-<empty>}"
  ERRORS=$((ERRORS + 1))
fi

# Verify all four systemd units exist in NANOBK_SYSTEMD_DIR
for svc in hysteria-server.service tuic-v5-9443.service xray-reality-8443.service xray-trojan-2443.service; do
  if [[ -f "${NANOBK_SYSTEMD_DIR}/${svc}" ]]; then
    pass "systemd unit exists in NANOBK_SYSTEMD_DIR: ${svc}"
  else
    fail "systemd unit missing from NANOBK_SYSTEMD_DIR: ${svc}"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ── Run healthcheck in offline mode ─────────────────────────────────────────

echo "--- Running healthcheck (offline mode) ---"
echo ""

if bash "$ROOT/vps/scripts/healthcheck.sh" \
  --config-dir "$TMP/etc/nanobk" \
  --skip-services \
  --skip-ports; then
  pass "healthcheck offline mode passed"
else
  fail "healthcheck offline mode failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All tests passed!${NC}"
  echo "  Output: ${TMP}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  echo "  Output: ${TMP}"
  exit 1
fi
