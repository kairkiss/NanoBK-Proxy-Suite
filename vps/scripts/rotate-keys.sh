#!/usr/bin/env bash
# NanoBK Proxy Suite — Key Rotation v0.9
#
# Rotates credentials for proxy services on the VPS
# and syncs the new profile to Cloudflare Workers via admin API.
#
# Supports single-protocol rotation:
#   --protocol all|hy2|tuic|reality|trojan
#
# Reads configuration from:
#   /etc/nanobk/config.env          (VPS paths and settings)
#   /etc/nanobk/secrets.private.env (current credentials)
#   /root/.nanok-cf-admin.env       (Cloudflare admin tokens)
#
# Usage:
#   sudo bash vps/scripts/rotate-keys.sh
#   sudo bash vps/scripts/rotate-keys.sh --protocol hy2
#   sudo bash vps/scripts/rotate-keys.sh --protocol reality --skip-cloudflare

set -Eeuo pipefail

# ── Resolve script directory ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Source libraries ────────────────────────────────────────────────────────

source "${REPO_DIR}/vps/lib/common.sh"
source "${REPO_DIR}/vps/lib/profile.sh"

# ── Cross-platform UUID ────────────────────────────────────────────────────

generate_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen
  else
    python3 -c "import uuid; print(uuid.uuid4())"
  fi
}

# ── Default configuration ──────────────────────────────────────────────────

NANOBK_DRY_RUN=0
NANOBK_YES=0
FORCE=0
SKIP_CLOUDFLARE=0
SKIP_SERVICES=0
ALLOW_PLACEHOLDER_REALITY=0
INSTALL_DIR_EXPLICIT=0
ROTATE_PROTOCOL="all"

NANOBK_CONFIG_DIR="/etc/nanobk"
NANOBK_INSTALL_DIR="/opt/nanobk"
CF_ADMIN_ENV="/root/.nanok-cf-admin.env"

# Staged new credentials
NEW_HY2_PASSWORD=""
NEW_TUIC_UUID=""
NEW_TUIC_PASSWORD=""
NEW_REALITY_UUID=""
NEW_REALITY_PRIVATE_KEY=""
NEW_REALITY_PUBLIC_KEY=""
NEW_REALITY_SHORT_ID=""
NEW_TROJAN_PASSWORD=""

# Backup dir (set in make_backup)
BACKUP_DIR=""

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — Key Rotation v0.9

Usage:
  sudo bash vps/scripts/rotate-keys.sh [OPTIONS]

Options:
  --protocol PROTO             Protocol to rotate: all|hy2|tuic|reality|trojan (default: all)
  --dry-run                    Print actions without modifying anything
  --yes                        Non-interactive mode
  --config-dir PATH            Config directory (default: /etc/nanobk)
  --install-dir PATH           Install directory (default: from config.env or /opt/nanobk)
  --cf-admin-env PATH          Cloudflare admin env file (default: /root/.nanok-cf-admin.env)
  --skip-cloudflare            Do not sync to Cloudflare (local only)
  --skip-services              Do not restart services or check ports
  --allow-placeholder-reality  Allow placeholder Reality key when xray is missing (TEST ONLY)
  --force                      Skip confirmation prompts
  --help                       Show this help

Examples:
  # Rotate all protocols
  sudo bash vps/scripts/rotate-keys.sh

  # Rotate only HY2 password
  sudo bash vps/scripts/rotate-keys.sh --protocol hy2

  # Rotate only Reality keys
  sudo bash vps/scripts/rotate-keys.sh --protocol reality --skip-cloudflare

  # Dry-run single protocol
  bash vps/scripts/rotate-keys.sh --protocol tuic --dry-run --skip-services --skip-cloudflare
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --protocol)                     ROTATE_PROTOCOL="$2"; shift ;;
      --dry-run)                      NANOBK_DRY_RUN=1 ;;
      --yes)                          NANOBK_YES=1 ;;
      --force)                        FORCE=1 ;;
      --config-dir)                   NANOBK_CONFIG_DIR="$2"; shift ;;
      --install-dir)                  NANOBK_INSTALL_DIR="$2"; INSTALL_DIR_EXPLICIT=1; shift ;;
      --cf-admin-env)                 CF_ADMIN_ENV="$2"; shift ;;
      --skip-cloudflare)              SKIP_CLOUDFLARE=1 ;;
      --skip-services)                SKIP_SERVICES=1 ;;
      --allow-placeholder-reality)    ALLOW_PLACEHOLDER_REALITY=1 ;;
      --help|-h)                      show_help; exit 0 ;;
      *)                              die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done

  # Validate protocol
  case "$ROTATE_PROTOCOL" in
    all|hy2|tuic|reality|trojan) ;;
    *) die "Invalid protocol: ${ROTATE_PROTOCOL}. Use all|hy2|tuic|reality|trojan." ;;
  esac
}

# ── Load configuration ──────────────────────────────────────────────────────

load_nanobk_config() {
  local config_file="${NANOBK_CONFIG_DIR}/config.env"
  if [[ ! -f "$config_file" ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      warn "config.env not found: ${config_file} (OK in dry-run)"
      NANOBK_DOMAIN="${NANOBK_DOMAIN:-proxy.example.com}"
      NANOBK_VPS_IP="${NANOBK_VPS_IP:-198.51.100.10}"
      NANOBK_GEO_LABEL="${NANOBK_GEO_LABEL:-UN}"
      NANOBK_CERT_MODE="${NANOBK_CERT_MODE:-self-signed}"
      NANOBK_CERT_FILE="${NANOBK_CERT_FILE:-/dev/null}"
      NANOBK_KEY_FILE="${NANOBK_KEY_FILE:-/dev/null}"
      NANOBK_SYSTEMD_DIR="${NANOBK_SYSTEMD_DIR:-/tmp/fake-systemd}"
      REALITY_SERVERNAME="${REALITY_SERVERNAME:-www.microsoft.com}"
      HY2_CONFIG="${HY2_CONFIG:-/tmp/fake-hy2.yaml}"
      TUIC_CONFIG="${TUIC_CONFIG:-/tmp/fake-tuic.json}"
      REALITY_CONFIG="${REALITY_CONFIG:-/tmp/fake-reality.json}"
      TROJAN_CONFIG="${TROJAN_CONFIG:-/tmp/fake-trojan.json}"
      HY2_SERVICE="hysteria-server.service"
      TUIC_SERVICE="tuic-v5-9443.service"
      REALITY_SERVICE="xray-reality-8443.service"
      TROJAN_SERVICE="xray-trojan-2443.service"
      return 0
    fi
    die "config.env not found: ${config_file}
Run the VPS installer first: bash installer/install-vps.sh"
  fi

  log "Loading config: ${config_file}"

  local cli_install_dir="$NANOBK_INSTALL_DIR"
  # shellcheck source=/dev/null
  source "$config_file"
  if [[ "$INSTALL_DIR_EXPLICIT" == "1" ]]; then
    NANOBK_INSTALL_DIR="$cli_install_dir"
  fi

  [[ -n "${NANOBK_DOMAIN:-}" ]] || die "NANOBK_DOMAIN not set in config.env"
  [[ -n "${NANOBK_VPS_IP:-}" ]] || die "NANOBK_VPS_IP not set in config.env"

  ok "Config loaded: domain=${NANOBK_DOMAIN}, ip=${NANOBK_VPS_IP}"
}

load_secrets() {
  local secrets_file="${NANOBK_CONFIG_DIR}/secrets.private.env"
  if [[ ! -f "$secrets_file" ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      warn "secrets.private.env not found: ${secrets_file} (OK in dry-run)"
      return 0
    fi
    die "secrets.private.env not found: ${secrets_file}"
  fi

  log "Loading secrets: ${secrets_file}"
  # shellcheck source=/dev/null
  source "$secrets_file"

  local required_secrets=(
    HY2_PASSWORD TUIC_UUID TUIC_PASSWORD
    REALITY_UUID REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
    TROJAN_PASSWORD
  )
  for var in "${required_secrets[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      die "Missing required secret in secrets.private.env: ${var}"
    fi
  done

  ok "Secrets loaded"
}

load_cf_admin_env() {
  if [[ "$SKIP_CLOUDFLARE" == "1" ]]; then
    log "Skipping Cloudflare (--skip-cloudflare)"
    return 0
  fi

  if [[ ! -f "$CF_ADMIN_ENV" ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      warn "CF admin env not found: ${CF_ADMIN_ENV} (OK in dry-run)"
      ADMIN_TOKEN="DRY_RUN_ADMIN_TOKEN"
      ADMIN_UPDATE_URL="https://nanok.example.workers.dev/admin/update"
      ADMIN_CURRENT_URL="https://nanok.example.workers.dev/admin/current"
      return 0
    fi
    die "Cloudflare admin env not found: ${CF_ADMIN_ENV}"
  fi

  log "Loading CF admin env: ${CF_ADMIN_ENV}"
  # shellcheck source=/dev/null
  source "$CF_ADMIN_ENV"

  if [[ -z "${ADMIN_CURRENT_URL:-}" ]] && [[ -n "${NANOK_ROUTE_URL:-}" ]]; then
    ADMIN_CURRENT_URL="${NANOK_ROUTE_URL}${ADMIN_CURRENT_PATH:-/admin/current}"
    ADMIN_UPDATE_URL="${NANOK_ROUTE_URL}${ADMIN_PATH:-/admin/update}"
  fi

  [[ -n "${ADMIN_TOKEN:-}" ]] || die "ADMIN_TOKEN not in CF admin env"
  [[ -n "${ADMIN_UPDATE_URL:-}" ]] || die "ADMIN_UPDATE_URL not in CF admin env"
  [[ -n "${ADMIN_CURRENT_URL:-}" ]] || die "ADMIN_CURRENT_URL not in CF admin env"

  ok "CF admin env loaded (token fingerprint: $(fingerprint "$ADMIN_TOKEN"))"
}

# ── Generate staged credentials ─────────────────────────────────────────────

generate_reality_keypair() {
  if command -v xray &>/dev/null; then
    local keypair
    keypair=$(xray x25519) || die "Failed to generate Reality keypair"
    NEW_REALITY_PRIVATE_KEY=$(echo "$keypair" | awk -F': ' '/Private key/ {print $2}' | tr -d '\r\n')
    NEW_REALITY_PUBLIC_KEY=$(echo "$keypair" | awk -F': ' '/Public key/ {print $2}' | tr -d '\r\n')
  elif [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    warn "xray not available (using placeholder for dry-run)"
    NEW_REALITY_PRIVATE_KEY="DRY_RUN_PLACEHOLDER_PRIVATE_KEY"
    NEW_REALITY_PUBLIC_KEY="DRY_RUN_PLACEHOLDER_PUBLIC_KEY"
  elif [[ "$ALLOW_PLACEHOLDER_REALITY" == "1" ]]; then
    warn "xray not available (using placeholder — NOT for production)"
    NEW_REALITY_PRIVATE_KEY="PLACEHOLDER_PRIVATE_KEY_NOT_FOR_PRODUCTION"
    NEW_REALITY_PUBLIC_KEY="PLACEHOLDER_PUBLIC_KEY_NOT_FOR_PRODUCTION"
  else
    die "xray is required for Reality keypair generation.
For offline tests only, add --allow-placeholder-reality."
  fi
}

generate_new_credentials() {
  log "Generating new credentials for protocol: ${ROTATE_PROTOCOL}"

  # Start with current values (unchanged protocols keep old values)
  NEW_HY2_PASSWORD="$HY2_PASSWORD"
  NEW_TUIC_UUID="$TUIC_UUID"
  NEW_TUIC_PASSWORD="$TUIC_PASSWORD"
  NEW_REALITY_UUID="$REALITY_UUID"
  NEW_REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY"
  NEW_REALITY_PUBLIC_KEY="$REALITY_PUBLIC_KEY"
  NEW_REALITY_SHORT_ID="$REALITY_SHORT_ID"
  NEW_TROJAN_PASSWORD="$TROJAN_PASSWORD"

  case "$ROTATE_PROTOCOL" in
    all)
      NEW_HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
      NEW_TUIC_UUID=$(generate_uuid)
      NEW_TUIC_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')
      NEW_REALITY_UUID=$(generate_uuid)
      NEW_REALITY_SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
      generate_reality_keypair
      NEW_TROJAN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
      ;;
    hy2)
      NEW_HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
      ;;
    tuic)
      NEW_TUIC_UUID=$(generate_uuid)
      NEW_TUIC_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')
      ;;
    reality)
      NEW_REALITY_UUID=$(generate_uuid)
      NEW_REALITY_SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
      generate_reality_keypair
      ;;
    trojan)
      NEW_TROJAN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
      ;;
  esac

  [[ -n "$NEW_REALITY_PRIVATE_KEY" ]] || die "Reality private key is empty"
  [[ -n "$NEW_REALITY_PUBLIC_KEY" ]] || die "Reality public key is empty"

  # Log fingerprints for rotated protocols only
  ok "New credential fingerprints (protocol=${ROTATE_PROTOCOL}):"
  case "$ROTATE_PROTOCOL" in
    all|hy2)     echo "    HY2 password:     $(fingerprint "$NEW_HY2_PASSWORD")" ;;
  esac
  case "$ROTATE_PROTOCOL" in
    all|tuic)
      echo "    TUIC UUID:        $(fingerprint "$NEW_TUIC_UUID")"
      echo "    TUIC password:    $(fingerprint "$NEW_TUIC_PASSWORD")"
      ;;
  esac
  case "$ROTATE_PROTOCOL" in
    all|reality)
      echo "    Reality UUID:     $(fingerprint "$NEW_REALITY_UUID")"
      echo "    Reality public:   $(fingerprint "$NEW_REALITY_PUBLIC_KEY")"
      echo "    Reality shortId:  $(fingerprint "$NEW_REALITY_SHORT_ID")"
      ;;
  esac
  case "$ROTATE_PROTOCOL" in
    all|trojan)  echo "    Trojan password:  $(fingerprint "$NEW_TROJAN_PASSWORD")" ;;
  esac
}

# ── Backup ──────────────────────────────────────────────────────────────────

backup_service_config() {
  local src="$1"
  local dest_name="$2"
  if [[ -f "$src" ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} Would backup ${src} → ${BACKUP_DIR}/${dest_name}"
    else
      cp -a "$src" "${BACKUP_DIR}/${dest_name}"
    fi
  fi
}

restore_service_config() {
  local dest="$1"
  local src_name="$2"
  local bak="${BACKUP_DIR}/${src_name}"
  if [[ -f "$bak" ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} Would restore ${bak} → ${dest}"
    else
      cp -a "$bak" "$dest"
      warn "Restored: ${dest}"
    fi
  fi
}

make_backup() {
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="${NANOBK_INSTALL_DIR}/backups/rotate-${stamp}"

  log "Creating backup: ${BACKUP_DIR}"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would create ${BACKUP_DIR}"
    BACKUP_DIR="/tmp/nanobk-dry-run-backup-${stamp}"
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  for f in \
    "${NANOBK_CONFIG_DIR}/config.env" \
    "${NANOBK_CONFIG_DIR}/secrets.private.env" \
    "${NANOBK_CONFIG_DIR}/profile.current.json"; do
    [[ -f "$f" ]] && cp -a "$f" "$BACKUP_DIR/" || true
  done

  # Always backup all configs (simplifies rollback)
  backup_service_config "$HY2_CONFIG"     "hy2.config.yaml.bak"
  backup_service_config "$TUIC_CONFIG"    "tuic.config.json.bak"
  backup_service_config "$REALITY_CONFIG" "reality.config.json.bak"
  backup_service_config "$TROJAN_CONFIG"  "trojan.config.json.bak"

  ok "Backup created: ${BACKUP_DIR}"
}

# ── Patch configs ───────────────────────────────────────────────────────────

patch_hy2_config() {
  log "Patching HY2 config..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would patch password in ${HY2_CONFIG}"
    return 0
  fi

  python3 - "$HY2_CONFIG" "$NEW_HY2_PASSWORD" <<'PY'
import sys
path, password = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read().splitlines()
out = []
changed = False
for line in text:
    stripped = line.lstrip()
    indent = line[:len(line)-len(stripped)]
    if stripped.startswith('password:'):
        out.append(f'{indent}password: "{password}"')
        changed = True
    else:
        out.append(line)
if not changed:
    raise SystemExit('HY2 password field was not found')
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
  ok "HY2 config patched"
}

patch_tuic_config() {
  log "Patching TUIC config..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would patch UUID/password in ${TUIC_CONFIG}"
    return 0
  fi

  python3 - "$TUIC_CONFIG" "$NEW_TUIC_UUID" "$NEW_TUIC_PASSWORD" <<'PY'
import json, sys
path, uuid, password = sys.argv[1:4]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
if isinstance(data.get('users'), dict):
    data['users'] = {uuid: password}
elif isinstance(data.get('users'), list):
    data['users'] = [{'uuid': uuid, 'password': password}]
else:
    raise SystemExit('unsupported TUIC users structure')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  ok "TUIC config patched"
}

patch_reality_config() {
  log "Patching Reality config..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would patch uuid/privateKey/shortIds in ${REALITY_CONFIG}"
    return 0
  fi

  python3 - "$REALITY_CONFIG" "$NEW_REALITY_UUID" "$NEW_REALITY_PRIVATE_KEY" "$NEW_REALITY_SHORT_ID" <<'PY'
import json, sys
path, uuid, private_key, short_id = sys.argv[1:5]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
changed_client = changed_private = changed_short = False
for inbound in data.get('inbounds', []):
    if inbound.get('protocol') != 'vless':
        continue
    settings = inbound.get('settings', {})
    clients = settings.get('clients', [])
    if clients:
        clients[0]['id'] = uuid
        changed_client = True
    reality = inbound.get('streamSettings', {}).get('realitySettings', {})
    if 'privateKey' in reality:
        reality['privateKey'] = private_key
        changed_private = True
    if 'shortIds' in reality and isinstance(reality['shortIds'], list):
        reality['shortIds'] = [short_id]
        changed_short = True
if not (changed_client and changed_private and changed_short):
    raise SystemExit('failed to patch expected Reality fields')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  ok "Reality config patched"
}

patch_trojan_config() {
  log "Patching Trojan config..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would patch password in ${TROJAN_CONFIG}"
    return 0
  fi

  python3 - "$TROJAN_CONFIG" "$NEW_TROJAN_PASSWORD" <<'PY'
import json, sys
path, password = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
changed = False
for inbound in data.get('inbounds', []):
    if inbound.get('protocol') != 'trojan':
        continue
    clients = inbound.get('settings', {}).get('clients', [])
    if clients:
        clients[0]['password'] = password
        changed = True
if not changed:
    raise SystemExit('failed to patch expected Trojan password field')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  ok "Trojan config patched"
}

patch_selected_configs() {
  case "$ROTATE_PROTOCOL" in
    all)
      patch_hy2_config
      patch_tuic_config
      patch_reality_config
      patch_trojan_config
      ;;
    hy2)     patch_hy2_config ;;
    tuic)    patch_tuic_config ;;
    reality) patch_reality_config ;;
    trojan)  patch_trojan_config ;;
  esac

  if [[ "${NANOBK_TEST_FAIL_AFTER_PATCH:-}" == "1" ]]; then
    die "Test-only failure after patch (NANOBK_TEST_FAIL_AFTER_PATCH=1)"
  fi
}

# ── Generate new profile ────────────────────────────────────────────────────

generate_new_profile() {
  log "Generating new profile..."

  if [[ -f "${NANOBK_CONFIG_DIR}/profile.current.json" ]]; then
    if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
      cp -a "${NANOBK_CONFIG_DIR}/profile.current.json" "${NANOBK_CONFIG_DIR}/profile.previous.json"
    fi
  fi

  # Temporarily swap credentials for generate_profile_json
  local old_hy2="$HY2_PASSWORD" old_tuic_uuid="$TUIC_UUID" old_tuic_pw="$TUIC_PASSWORD"
  local old_reality_uuid="$REALITY_UUID" old_reality_priv="$REALITY_PRIVATE_KEY"
  local old_reality_pub="$REALITY_PUBLIC_KEY" old_reality_short="$REALITY_SHORT_ID"
  local old_trojan="$TROJAN_PASSWORD"

  HY2_PASSWORD="$NEW_HY2_PASSWORD"
  TUIC_UUID="$NEW_TUIC_UUID"
  TUIC_PASSWORD="$NEW_TUIC_PASSWORD"
  REALITY_UUID="$NEW_REALITY_UUID"
  REALITY_PRIVATE_KEY="$NEW_REALITY_PRIVATE_KEY"
  REALITY_PUBLIC_KEY="$NEW_REALITY_PUBLIC_KEY"
  REALITY_SHORT_ID="$NEW_REALITY_SHORT_ID"
  TROJAN_PASSWORD="$NEW_TROJAN_PASSWORD"

  local geo="${NANOBK_GEO_LABEL:-UN}"
  local profile_json
  profile_json=$(generate_profile_json \
    "$NANOBK_DOMAIN" \
    "$NANOBK_VPS_IP" \
    "$geo" \
    "${REALITY_SERVERNAME:-www.microsoft.com}")

  # Restore old credentials
  HY2_PASSWORD="$old_hy2"
  TUIC_UUID="$old_tuic_uuid"
  TUIC_PASSWORD="$old_tuic_pw"
  REALITY_UUID="$old_reality_uuid"
  REALITY_PRIVATE_KEY="$old_reality_priv"
  REALITY_PUBLIC_KEY="$old_reality_pub"
  REALITY_SHORT_ID="$old_reality_short"
  TROJAN_PASSWORD="$old_trojan"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${NANOBK_CONFIG_DIR}/profile.current.json"
    return 0
  fi

  printf '%s\n' "$profile_json" > "${NANOBK_CONFIG_DIR}/profile.current.json"

  if command -v jq &>/dev/null; then
    jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' \
      "${NANOBK_CONFIG_DIR}/profile.current.json" >/dev/null || die "Profile JSON validation failed"
  fi

  if grep -q 'privateKey' "${NANOBK_CONFIG_DIR}/profile.current.json" 2>/dev/null; then
    die "Reality private key leaked into profile JSON"
  fi

  ok "New profile generated: ${NANOBK_CONFIG_DIR}/profile.current.json"
}

# ── Validate configs ────────────────────────────────────────────────────────

validate_configs() {
  log "Validating configs..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would validate JSON configs"
    return 0
  fi

  for f in "$TUIC_CONFIG" "$REALITY_CONFIG" "$TROJAN_CONFIG"; do
    if [[ -f "$f" ]]; then
      python3 -c "import json; json.load(open('$f'))" || die "Invalid JSON: $f"
    fi
  done

  if command -v xray &>/dev/null; then
    xray -test -config "$REALITY_CONFIG" >/dev/null 2>&1 || die "Reality config test failed"
    xray -test -config "$TROJAN_CONFIG" >/dev/null 2>&1 || die "Trojan config test failed"
    ok "Xray config tests passed"
  else
    warn "xray not available, skipping config test"
  fi
}

# ── Services ────────────────────────────────────────────────────────────────

restart_services() {
  if [[ "$SKIP_SERVICES" == "1" ]]; then
    log "Skipping service restart (--skip-services)"
    return 0
  fi

  log "Restarting services..."

  local services=()
  case "$ROTATE_PROTOCOL" in
    all)     services=("$REALITY_SERVICE" "$TROJAN_SERVICE" "$TUIC_SERVICE" "$HY2_SERVICE") ;;
    hy2)     services=("$HY2_SERVICE") ;;
    tuic)    services=("$TUIC_SERVICE") ;;
    reality) services=("$REALITY_SERVICE") ;;
    trojan)  services=("$TROJAN_SERVICE") ;;
  esac

  for svc in "${services[@]}"; do
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} systemctl restart ${svc}"
      continue
    fi

    systemctl restart "$svc"
    sleep 1

    if systemctl is-active --quiet "$svc"; then
      ok "${svc}: restarted"
    else
      err "${svc}: failed to restart"
      return 1
    fi
  done
}

run_healthcheck() {
  log "Running healthcheck..."

  local hc_script="${NANOBK_INSTALL_DIR}/bin/healthcheck.sh"
  if [[ ! -f "$hc_script" ]]; then
    hc_script="${REPO_DIR}/vps/scripts/healthcheck.sh"
  fi

  if [[ ! -f "$hc_script" ]]; then
    warn "healthcheck.sh not found, skipping"
    return 0
  fi

  local hc_args=("--config-dir" "$NANOBK_CONFIG_DIR")
  if [[ "$SKIP_SERVICES" == "1" ]]; then
    hc_args+=("--skip-services" "--skip-ports")
  fi

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} bash ${hc_script} ${hc_args[*]}"
    return 0
  fi

  if bash "$hc_script" "${hc_args[@]}"; then
    ok "Healthcheck passed"
  else
    err "Healthcheck failed"
    return 1
  fi
}

# ── Cloudflare sync ─────────────────────────────────────────────────────────

verify_cf_field() {
  local current="$1"
  local field="$2"
  local expected="$3"
  local label="$4"

  local actual
  actual=$(echo "$current" | jq -r "$field // empty" 2>/dev/null)
  if [[ "$actual" != "$expected" ]]; then
    err "Cloudflare ${label} mismatch"
    return 1
  fi
}

sync_cloudflare() {
  if [[ "$SKIP_CLOUDFLARE" == "1" ]]; then
    log "Skipping Cloudflare sync (--skip-cloudflare)"
    return 0
  fi

  local profile_path="${NANOBK_CONFIG_DIR}/profile.current.json"

  log "Uploading profile to Cloudflare..."

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} curl -X POST ${ADMIN_UPDATE_URL}"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   --data-binary @${profile_path}"
    return 0
  fi

  local response
  response=$(curl -fsS -X POST "$ADMIN_UPDATE_URL" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${profile_path}" \
    2>&1) || {
    err "Cloudflare profile upload failed:"
    echo "$response" >&2
    return 1
  }

  echo "$response"
  ok "Profile uploaded to Cloudflare"

  # Verify per-protocol
  log "Verifying Cloudflare profile..."
  local current
  current=$(curl -fsS "$ADMIN_CURRENT_URL" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    2>&1) || {
    err "Cloudflare profile verification failed"
    return 1
  }

  if ! command -v jq &>/dev/null; then
    ok "Cloudflare profile uploaded (jq not available for deep verify)"
    return 0
  fi

  local verify_ok=1
  case "$ROTATE_PROTOCOL" in
    all)
      verify_cf_field "$current" '.hy2.password' "$NEW_HY2_PASSWORD" "HY2 password" || verify_ok=0
      verify_cf_field "$current" '.tuic.uuid' "$NEW_TUIC_UUID" "TUIC UUID" || verify_ok=0
      verify_cf_field "$current" '.tuic.password' "$NEW_TUIC_PASSWORD" "TUIC password" || verify_ok=0
      verify_cf_field "$current" '.reality.uuid' "$NEW_REALITY_UUID" "Reality UUID" || verify_ok=0
      verify_cf_field "$current" '.reality.publicKey' "$NEW_REALITY_PUBLIC_KEY" "Reality publicKey" || verify_ok=0
      verify_cf_field "$current" '.reality.shortId' "$NEW_REALITY_SHORT_ID" "Reality shortId" || verify_ok=0
      verify_cf_field "$current" '.trojan.password' "$NEW_TROJAN_PASSWORD" "Trojan password" || verify_ok=0
      ;;
    hy2)
      verify_cf_field "$current" '.hy2.password' "$NEW_HY2_PASSWORD" "HY2 password" || verify_ok=0
      ;;
    tuic)
      verify_cf_field "$current" '.tuic.uuid' "$NEW_TUIC_UUID" "TUIC UUID" || verify_ok=0
      verify_cf_field "$current" '.tuic.password' "$NEW_TUIC_PASSWORD" "TUIC password" || verify_ok=0
      ;;
    reality)
      verify_cf_field "$current" '.reality.uuid' "$NEW_REALITY_UUID" "Reality UUID" || verify_ok=0
      verify_cf_field "$current" '.reality.publicKey' "$NEW_REALITY_PUBLIC_KEY" "Reality publicKey" || verify_ok=0
      verify_cf_field "$current" '.reality.shortId' "$NEW_REALITY_SHORT_ID" "Reality shortId" || verify_ok=0
      ;;
    trojan)
      verify_cf_field "$current" '.trojan.password' "$NEW_TROJAN_PASSWORD" "Trojan password" || verify_ok=0
      ;;
  esac

  if [[ "$verify_ok" == "0" ]]; then
    return 1
  fi
  ok "Cloudflare profile verified (protocol=${ROTATE_PROTOCOL})"
}

# ── Write secrets ───────────────────────────────────────────────────────────

write_new_secrets() {
  log "Writing new secrets..."

  HY2_PASSWORD="$NEW_HY2_PASSWORD"
  TUIC_UUID="$NEW_TUIC_UUID"
  TUIC_PASSWORD="$NEW_TUIC_PASSWORD"
  REALITY_UUID="$NEW_REALITY_UUID"
  REALITY_PRIVATE_KEY="$NEW_REALITY_PRIVATE_KEY"
  REALITY_PUBLIC_KEY="$NEW_REALITY_PUBLIC_KEY"
  REALITY_SHORT_ID="$NEW_REALITY_SHORT_ID"
  TROJAN_PASSWORD="$NEW_TROJAN_PASSWORD"

  local secrets_file="${NANOBK_CONFIG_DIR}/secrets.private.env"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${secrets_file} (mode 600)"
    return 0
  fi

  generate_secrets_env > "$secrets_file"
  chmod 600 "$secrets_file"
  ok "Secrets updated: ${secrets_file}"
}

write_rotation_record() {
  local record_dir="${NANOBK_INSTALL_DIR}/backups"
  local record_file="${record_dir}/rotate-latest.private.md"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${record_file}"
    return 0
  fi

  mkdir -p "$record_dir"

  local cf_status="skipped"
  [[ "$SKIP_CLOUDFLARE" != "1" ]] && cf_status="synced"
  local svc_status="skipped"
  [[ "$SKIP_SERVICES" != "1" ]] && svc_status="restarted"

  cat > "$record_file" <<EOF
# Latest Key Rotation Record

Generated: $(iso_date)
Protocol: ${ROTATE_PROTOCOL}

## Fingerprints

- HY2 password: $(fingerprint "$NEW_HY2_PASSWORD")
- TUIC UUID: $(fingerprint "$NEW_TUIC_UUID")
- TUIC password: $(fingerprint "$NEW_TUIC_PASSWORD")
- Reality UUID: $(fingerprint "$NEW_REALITY_UUID")
- Reality publicKey: $(fingerprint "$NEW_REALITY_PUBLIC_KEY")
- Reality shortId: $(fingerprint "$NEW_REALITY_SHORT_ID")
- Trojan password: $(fingerprint "$NEW_TROJAN_PASSWORD")

## Status

- Cloudflare sync: ${cf_status}
- Service restart: ${svc_status}
- Backup: ${BACKUP_DIR}
- Profile: ${NANOBK_CONFIG_DIR}/profile.current.json

## Security

Keep this file private. Never commit to Git.
Full credentials are in: ${NANOBK_CONFIG_DIR}/secrets.private.env
EOF
  chmod 600 "$record_file"
  ok "Rotation record: ${record_file}"
}

# ── Rollback ────────────────────────────────────────────────────────────────

rollback_local() {
  if [[ -z "${BACKUP_DIR:-}" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
    warn "No backup directory for rollback"
    return 0
  fi

  warn "ROLLING BACK local configuration from ${BACKUP_DIR}..."

  for f in config.env secrets.private.env profile.current.json; do
    if [[ -f "${BACKUP_DIR}/${f}" ]]; then
      if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
        echo -e "  ${CYAN}[DRY-RUN]${NC} Would restore ${BACKUP_DIR}/${f} → ${NANOBK_CONFIG_DIR}/${f}"
      else
        cp -a "${BACKUP_DIR}/${f}" "${NANOBK_CONFIG_DIR}/${f}"
        warn "Restored: ${f}"
      fi
    fi
  done

  restore_service_config "$HY2_CONFIG"     "hy2.config.yaml.bak"
  restore_service_config "$TUIC_CONFIG"    "tuic.config.json.bak"
  restore_service_config "$REALITY_CONFIG" "reality.config.json.bak"
  restore_service_config "$TROJAN_CONFIG"  "trojan.config.json.bak"

  if [[ "$SKIP_SERVICES" != "1" ]] && [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    for svc in "$HY2_SERVICE" "$TUIC_SERVICE" "$REALITY_SERVICE" "$TROJAN_SERVICE"; do
      systemctl restart "$svc" 2>/dev/null || true
    done
  fi

  warn "Rollback completed. Check services manually."
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  echo ""
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   NanoBK Key Rotation — DRY-RUN                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
  else
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   NanoBK Key Rotation                                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
  fi
  echo ""
  echo "  Protocol: ${ROTATE_PROTOCOL}"
  echo ""

  # Phase 1: Load config
  load_nanobk_config
  load_secrets
  load_cf_admin_env

  # Phase 2: Confirm
  if [[ "$NANOBK_YES" != "1" ]] && [[ "$FORCE" != "1" ]]; then
    echo ""
    echo "  This will rotate credentials for: ${ROTATE_PROTOCOL}"
    echo "  Config dir:    ${NANOBK_CONFIG_DIR}"
    echo "  Cloudflare:    $([ "$SKIP_CLOUDFLARE" == "1" ] && echo "skip" || echo "sync")"
    echo "  Services:      $([ "$SKIP_SERVICES" == "1" ] && echo "skip" || echo "restart")"
    echo ""
    echo -en "${YELLOW}Proceed? [y/N]${NC} "
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by user"
  fi

  # Phase 3: Generate new credentials
  generate_new_credentials

  # Phase 4: Backup
  make_backup

  # Phase 5: Patch configs
  if ! patch_selected_configs; then
    err "Config patching failed"
    rollback_local
    exit 1
  fi

  # Phase 6: Generate new profile
  if ! generate_new_profile; then
    err "Profile generation failed"
    rollback_local
    exit 1
  fi

  # Phase 7: Validate
  if ! validate_configs; then
    err "Config validation failed"
    rollback_local
    exit 1
  fi

  # Phase 8: Services
  if ! restart_services; then
    err "Service restart failed"
    rollback_local
    exit 1
  fi

  if ! run_healthcheck; then
    err "Healthcheck failed"
    rollback_local
    exit 1
  fi

  # Phase 9: Cloudflare
  if ! sync_cloudflare; then
    err "Cloudflare sync failed"
    rollback_local
    exit 1
  fi

  # Phase 10: Commit secrets
  write_new_secrets
  write_rotation_record

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║   Key Rotation Completed                                ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Protocol:  ${ROTATE_PROTOCOL}"
  echo "  Backup:    ${BACKUP_DIR}"
  echo "  Secrets:   ${NANOBK_CONFIG_DIR}/secrets.private.env"
  echo "  Profile:   ${NANOBK_CONFIG_DIR}/profile.current.json"
  echo ""
  echo "  Subscription URL unchanged — clients refresh to get new keys."
  echo ""
}

main "$@"
