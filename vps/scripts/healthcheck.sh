#!/usr/bin/env bash
# NanoBK Proxy Suite — Health Check
# Read-only diagnostic of VPS proxy services, ports, configs, and profile.
#
# Usage:
#   bash vps/scripts/healthcheck.sh
#   bash /opt/nanobk/bin/healthcheck.sh

set -Eeuo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }
header() { echo -e "\n${BLUE}── $* ──${NC}"; }

ERRORS=0
WARNINGS=0

# ── Config discovery ────────────────────────────────────────────────────────

NANOBK_CONFIG_DIR="${NANOBK_CONFIG_DIR:-/etc/nanobk}"

# Try to load config.env
if [[ -f "${NANOBK_CONFIG_DIR}/config.env" ]]; then
  # shellcheck source=/dev/null
  source "${NANOBK_CONFIG_DIR}/config.env"
fi

# ── Services check ──────────────────────────────────────────────────────────

check_services() {
  header "Systemd Services"

  local services=(
    "${HY2_SERVICE:-hysteria-server.service}"
    "${TUIC_SERVICE:-tuic-v5-9443.service}"
    "${REALITY_SERVICE:-xray-reality-8443.service}"
    "${TROJAN_SERVICE:-xray-trojan-2443.service}"
  )

  if ! command -v systemctl &>/dev/null; then
    warn "systemctl not available"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  for svc in "${services[@]}"; do
    local status
    status=$(systemctl is-active "$svc" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      pass "${svc}: active"
    else
      fail "${svc}: ${status:-not found}"
      ERRORS=$((ERRORS + 1))
    fi
  done
}

# ── Ports check ─────────────────────────────────────────────────────────────

check_port() {
  local port="$1"
  local proto="$2"
  local name="$3"

  if ! command -v ss &>/dev/null; then
    warn "ss not available, cannot check port ${port}"
    return
  fi

  if [[ "$proto" == "udp" ]]; then
    if ss -ulnp 2>/dev/null | grep -q ":${port} "; then
      pass "${name} :${port} (${proto}): listening"
    else
      fail "${name} :${port} (${proto}): NOT listening"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      pass "${name} :${port} (${proto}): listening"
    else
      fail "${name} :${port} (${proto}): NOT listening"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

check_ports() {
  header "Port Listening"

  check_port "${HY2_PORT:-443}"  "udp" "HY2"
  check_port "${TUIC_PORT:-9443}" "udp" "TUIC"
  check_port "${REALITY_PORT:-8443}" "tcp" "Reality"
  check_port "${TROJAN_PORT:-2443}" "tcp" "Trojan"
}

# ── Config files check ──────────────────────────────────────────────────────

check_config_files() {
  header "Config Files"

  local configs=(
    "${HY2_CONFIG:-/etc/nanobk/hysteria/config.yaml}:HY2"
    "${TUIC_CONFIG:-/etc/nanobk/tuic-v5-9443/config.json}:TUIC"
    "${REALITY_CONFIG:-/etc/nanobk/xray-reality-8443/config.json}:Reality"
    "${TROJAN_CONFIG:-/etc/nanobk/xray-trojan-2443/config.json}:Trojan"
  )

  for entry in "${configs[@]}"; do
    local path="${entry%%:*}"
    local name="${entry##*:}"
    if [[ -f "$path" ]]; then
      pass "${name} config: ${path}"
    else
      fail "${name} config not found: ${path}"
      ERRORS=$((ERRORS + 1))
    fi
  done
}

# ── Profile check ───────────────────────────────────────────────────────────

check_profile() {
  header "Profile JSON"

  local profile_path="${NANOBK_CONFIG_DIR}/profile.current.json"

  if [[ ! -f "$profile_path" ]]; then
    fail "Profile not found: ${profile_path}"
    ERRORS=$((ERRORS + 1))
    return
  fi

  pass "Profile file exists: ${profile_path}"

  if ! command -v jq &>/dev/null; then
    warn "jq not available, cannot validate profile JSON"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  if jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$profile_path" >/dev/null 2>&1; then
    pass "Profile JSON has all four protocol sections"
  else
    fail "Profile JSON missing required sections (hy2/tuic/reality/trojan)"
    ERRORS=$((ERRORS + 1))
  fi

  # Check for control characters
  if python3 -c "
import json, sys
with open('$profile_path') as f:
    data = json.load(f)
def has_bad(s):
    return any((ord(c) < 32 and c not in '\t\n\r') or ord(c) == 127 or 0x80 <= ord(c) <= 0x9f for c in s)
def walk(v):
    if isinstance(v, str): return has_bad(v)
    if isinstance(v, dict): return any(walk(x) for x in v.values())
    if isinstance(v, list): return any(walk(x) for x in v)
    return False
sys.exit(1 if walk(data) else 0)
" 2>/dev/null; then
    pass "No invalid control characters in profile"
  else
    warn "Profile may contain control characters"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ── Secrets file check ──────────────────────────────────────────────────────

check_secrets() {
  header "Secrets File"

  local secrets_path="${NANOBK_CONFIG_DIR}/secrets.private.env"

  if [[ ! -f "$secrets_path" ]]; then
    warn "Secrets file not found: ${secrets_path}"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  pass "Secrets file exists: ${secrets_path}"

  local perms
  perms=$(stat -c '%a' "$secrets_path" 2>/dev/null || stat -f '%Lp' "$secrets_path" 2>/dev/null || echo "unknown")
  if [[ "$perms" == "600" ]]; then
    pass "Secrets file permissions: ${perms} (secure)"
  elif [[ "$perms" == "unknown" ]]; then
    warn "Cannot check secrets file permissions"
  else
    fail "Secrets file permissions: ${perms} (should be 600)"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
  header "Summary"

  echo ""
  if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "  ${GREEN}All checks passed!${NC}"
  elif [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${YELLOW}${WARNINGS} warning(s), no errors.${NC}"
  else
    echo -e "  ${RED}${ERRORS} error(s), ${WARNINGS} warning(s).${NC}"
    echo ""
    echo "  Fix the errors above before proceeding."
  fi
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "NanoBK Proxy Suite — Health Check"
  check_services
  check_ports
  check_config_files
  check_profile
  check_secrets
  print_summary

  if [[ $ERRORS -gt 0 ]]; then
    return 1
  fi
  return 0
}

main "$@"
