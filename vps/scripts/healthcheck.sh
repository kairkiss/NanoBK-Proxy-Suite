#!/usr/bin/env bash
# NanoBK Proxy Suite — Health Check
# Read-only diagnostic of VPS proxy services, ports, configs, and profile.
#
# Usage:
#   bash vps/scripts/healthcheck.sh
#   bash vps/scripts/healthcheck.sh --config-dir /tmp/nanobk-test/etc/nanobk --skip-services --skip-ports
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

# ── Options ─────────────────────────────────────────────────────────────────

NANOBK_CONFIG_DIR="${NANOBK_CONFIG_DIR:-/etc/nanobk}"
SKIP_SERVICES=0
SKIP_PORTS=0

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — Health Check

Usage:
  bash vps/scripts/healthcheck.sh [OPTIONS]

Options:
  --config-dir PATH    Config directory (default: /etc/nanobk or NANOBK_CONFIG_DIR env)
  --skip-services      Skip systemd service checks
  --skip-ports         Skip port listening checks
  --help               Show this help

Examples:
  # Full check on VPS
  bash vps/scripts/healthcheck.sh

  # Check render-only output
  bash vps/scripts/healthcheck.sh --config-dir /tmp/nanobk-test/etc/nanobk --skip-services --skip-ports
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-dir)     NANOBK_CONFIG_DIR="$2"; shift ;;
      --skip-services)  SKIP_SERVICES=1 ;;
      --skip-ports)     SKIP_PORTS=1 ;;
      --help|-h)        show_help; exit 0 ;;
      *)                echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
  done
}

# ── Load config.env ─────────────────────────────────────────────────────────

load_config() {
  if [[ -f "${NANOBK_CONFIG_DIR}/config.env" ]]; then
    # shellcheck source=/dev/null
    source "${NANOBK_CONFIG_DIR}/config.env"
  fi
}

# ── Services check ──────────────────────────────────────────────────────────

check_services() {
  header "Systemd Services"

  if [[ "$SKIP_SERVICES" == "1" ]]; then
    warn "Skipped (--skip-services)"
    return
  fi

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

  if [[ "$SKIP_PORTS" == "1" ]]; then
    warn "Skipped (--skip-ports)"
    return
  fi

  check_port "${HY2_PORT:-443}"  "udp" "HY2"
  check_port "${TUIC_PORT:-9443}" "udp" "TUIC"
  check_port "${REALITY_PORT:-8443}" "tcp" "Reality"
  check_port "${TROJAN_PORT:-2443}" "tcp" "Trojan"
}

# ── Config files check ──────────────────────────────────────────────────────

check_config_files() {
  header "Config Files"

  local configs=(
    "${HY2_CONFIG:-/etc/nanobk/generated/hysteria/config.yaml}:HY2"
    "${TUIC_CONFIG:-/etc/nanobk/generated/proxy-stack/tuic-v5-9443/config.json}:TUIC"
    "${REALITY_CONFIG:-/etc/nanobk/generated/proxy-stack/xray-reality-8443/config.json}:Reality"
    "${TROJAN_CONFIG:-/etc/nanobk/generated/proxy-stack/xray-trojan-2443/config.json}:Trojan"
  )

  for entry in "${configs[@]}"; do
    local path="${entry%%:*}"
    local name="${entry##*:}"
    if [[ -f "$path" ]]; then
      pass "${name} config: ${path}"

      # Validate JSON for TUIC, Reality, Trojan
      if [[ "$path" == *.json ]] && command -v jq &>/dev/null; then
        if jq . "$path" >/dev/null 2>&1; then
          pass "${name} config: valid JSON"
        else
          fail "${name} config: invalid JSON"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    else
      fail "${name} config not found: ${path}"
      ERRORS=$((ERRORS + 1))
    fi
  done
}

# ── Systemd units check ─────────────────────────────────────────────────────

check_systemd_units() {
  header "Systemd Units"

  local systemd_dir="${NANOBK_CONFIG_DIR}/systemd"
  local units=(
    "hysteria-server.service"
    "tuic-v5-9443.service"
    "xray-reality-8443.service"
    "xray-trojan-2443.service"
  )

  local expected_configs=(
    "${HY2_CONFIG:-/etc/hysteria/config.yaml}"
    "${TUIC_CONFIG:-/etc/proxy-stack/tuic-v5-9443/config.json}"
    "${REALITY_CONFIG:-/etc/proxy-stack/xray-reality-8443/config.json}"
    "${TROJAN_CONFIG:-/etc/proxy-stack/xray-trojan-2443/config.json}"
  )

  for i in "${!units[@]}"; do
    local unit="${units[$i]}"
    local expected_cfg="${expected_configs[$i]}"
    local unit_path="${systemd_dir}/${unit}"

    if [[ -f "$unit_path" ]]; then
      pass "${unit}: exists at ${unit_path}"

      # Check ExecStart references the correct config
      if grep -q "ExecStart.*${expected_cfg}" "$unit_path" 2>/dev/null; then
        pass "${unit}: ExecStart references ${expected_cfg}"
      elif grep -q "ExecStart" "$unit_path" 2>/dev/null; then
        local actual_exec
        actual_exec=$(grep 'ExecStart' "$unit_path" | head -1)
        warn "${unit}: ExecStart does not reference expected config"
        warn "  Expected: ${expected_cfg}"
        warn "  Got: ${actual_exec}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      fail "${unit}: not found at ${unit_path}"
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

  # Check Reality private key is NOT in profile
  if grep -q 'privateKey\|REALITY_PRIVATE_KEY' "$profile_path" 2>/dev/null; then
    fail "Reality private key leaked into profile JSON"
    ERRORS=$((ERRORS + 1))
  else
    pass "Reality private key not in profile JSON"
  fi
}

# ── Config env check ────────────────────────────────────────────────────────

check_config_env() {
  header "Config Environment"

  local env_path="${NANOBK_CONFIG_DIR}/config.env"

  if [[ -f "$env_path" ]]; then
    pass "config.env exists: ${env_path}"
  else
    fail "config.env not found: ${env_path}"
    ERRORS=$((ERRORS + 1))
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
  parse_args "$@"
  load_config

  echo ""
  echo "NanoBK Proxy Suite — Health Check"
  echo "  Config dir: ${NANOBK_CONFIG_DIR}"

  check_config_env
  check_secrets
  check_config_files
  check_systemd_units
  check_profile
  check_services
  check_ports
  print_summary

  if [[ $ERRORS -gt 0 ]]; then
    return 1
  fi
  return 0
}

main "$@"
