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
INSTALL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Source libraries (installed layout or source layout) ────────────────────

if [[ -f "$INSTALL_ROOT/lib/common.sh" && -f "$INSTALL_ROOT/lib/profile.sh" ]]; then
  # Installed layout: /opt/nanobk/bin/rotate-keys.sh → /opt/nanobk/lib/
  NANOBK_LIB_DIR="$INSTALL_ROOT/lib"
else
  # Source layout: vps/scripts/rotate-keys.sh → vps/lib/
  REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  NANOBK_LIB_DIR="$REPO_DIR/vps/lib"
fi

if [[ ! -f "$NANOBK_LIB_DIR/common.sh" ]] || [[ ! -f "$NANOBK_LIB_DIR/profile.sh" ]]; then
  echo "[ERROR] NanoBK library files not found." >&2
  echo "Expected installed layout: $INSTALL_ROOT/lib/common.sh" >&2
  echo "Expected source layout:    ${REPO_DIR:-?}/vps/lib/common.sh" >&2
  echo "" >&2
  echo "If using installed layout, re-run: sudo bash installer/install-vps.sh --force" >&2
  exit 1
fi

source "$NANOBK_LIB_DIR/common.sh"
source "$NANOBK_LIB_DIR/profile.sh"

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
    # Use shared parser from profile.sh
    local old_priv="${REALITY_PRIVATE_KEY:-}"
    local old_pub="${REALITY_PUBLIC_KEY:-}"
    parse_xray_x25519_output "$keypair"
    NEW_REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY"
    NEW_REALITY_PUBLIC_KEY="$REALITY_PUBLIC_KEY"
    REALITY_PRIVATE_KEY="$old_priv"
    REALITY_PUBLIC_KEY="$old_pub"
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

CF_VERIFY_ATTEMPTS="${NANOBK_CF_VERIFY_ATTEMPTS:-5}"
CF_VERIFY_SLEEP="${NANOBK_CF_VERIFY_SLEEP:-3}"
CF_PROFILE_UPDATED=0

# Compute a sha256 prefix of a JSON file for comparison.
json_sha16() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" <<'PY' 2>/dev/null || echo "unknown"
import json, sys, hashlib
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    obj = json.load(f)
data = json.dumps(obj, sort_keys=True, separators=(',', ':')).encode()
print(hashlib.sha256(data).hexdigest()[:16])
PY
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$file" 2>/dev/null | awk '{print substr($1,1,16)}'
  else
    shasum -a 256 "$file" 2>/dev/null | awk '{print substr($1,1,16)}'
  fi
}

verify_cf_field() {
  local current="$1"
  local field="$2"
  local expected="$3"
  local label="$4"

  local actual
  actual=$(echo "$current" | jq -r "$field // empty" 2>/dev/null)
  if [[ "$actual" != "$expected" ]]; then
    return 1
  fi
  return 0
}

# Verify Cloudflare profile matches expected values for the rotated protocol.
# Returns 0 on match, 1 on mismatch. Does NOT print errors (caller decides).
check_cf_verify() {
  local current="$1"

  if ! command -v jq &>/dev/null; then
    # Can't verify fields without jq
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
  return 0
}

# Build a summary of mismatched fields for logging.
cf_mismatch_summary() {
  local current="$1"
  local mismatches=()

  if ! command -v jq &>/dev/null; then
    echo "(jq not available for field comparison)"
    return
  fi

  case "$ROTATE_PROTOCOL" in
    all)
      verify_cf_field "$current" '.hy2.password' "$NEW_HY2_PASSWORD" "HY2" 2>/dev/null || mismatches+=("hy2.password")
      verify_cf_field "$current" '.tuic.uuid' "$NEW_TUIC_UUID" "TUIC" 2>/dev/null || mismatches+=("tuic.uuid")
      verify_cf_field "$current" '.tuic.password' "$NEW_TUIC_PASSWORD" "TUIC" 2>/dev/null || mismatches+=("tuic.password")
      verify_cf_field "$current" '.reality.uuid' "$NEW_REALITY_UUID" "Reality" 2>/dev/null || mismatches+=("reality.uuid")
      verify_cf_field "$current" '.reality.publicKey' "$NEW_REALITY_PUBLIC_KEY" "Reality" 2>/dev/null || mismatches+=("reality.publicKey")
      verify_cf_field "$current" '.reality.shortId' "$NEW_REALITY_SHORT_ID" "Reality" 2>/dev/null || mismatches+=("reality.shortId")
      verify_cf_field "$current" '.trojan.password' "$NEW_TROJAN_PASSWORD" "Trojan" 2>/dev/null || mismatches+=("trojan.password")
      ;;
    hy2)
      verify_cf_field "$current" '.hy2.password' "$NEW_HY2_PASSWORD" "HY2" 2>/dev/null || mismatches+=("hy2.password")
      ;;
    tuic)
      verify_cf_field "$current" '.tuic.uuid' "$NEW_TUIC_UUID" "TUIC" 2>/dev/null || mismatches+=("tuic.uuid")
      verify_cf_field "$current" '.tuic.password' "$NEW_TUIC_PASSWORD" "TUIC" 2>/dev/null || mismatches+=("tuic.password")
      ;;
    reality)
      verify_cf_field "$current" '.reality.uuid' "$NEW_REALITY_UUID" "Reality" 2>/dev/null || mismatches+=("reality.uuid")
      verify_cf_field "$current" '.reality.publicKey' "$NEW_REALITY_PUBLIC_KEY" "Reality" 2>/dev/null || mismatches+=("reality.publicKey")
      verify_cf_field "$current" '.reality.shortId' "$NEW_REALITY_SHORT_ID" "Reality" 2>/dev/null || mismatches+=("reality.shortId")
      ;;
    trojan)
      verify_cf_field "$current" '.trojan.password' "$NEW_TROJAN_PASSWORD" "Trojan" 2>/dev/null || mismatches+=("trojan.password")
      ;;
  esac

  if [[ ${#mismatches[@]} -eq 0 ]]; then
    echo "(no mismatches)"
  else
    echo "${mismatches[*]}"
  fi
}

# Try to restore old profile to Cloudflare (best-effort).
restore_cloudflare_profile() {
  local old_profile="$1"
  if [[ ! -f "$old_profile" ]]; then
    warn "No old profile to restore to Cloudflare"
    return 1
  fi

  warn "Attempting Cloudflare rollback..."
  local response
  response=$(curl -fsS -X POST "$ADMIN_UPDATE_URL" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${old_profile}" \
    2>&1) || {
    err "Cloudflare rollback POST failed"
    return 1
  }

  # Verify rollback
  local attempt
  for attempt in $(seq 1 "$CF_VERIFY_ATTEMPTS"); do
    local current
    current=$(curl -fsS "$ADMIN_CURRENT_URL" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      2>&1) || {
      sleep "$CF_VERIFY_SLEEP"
      continue
    }

    local old_sha new_sha
    old_sha=$(json_sha16 "$old_profile")
    new_sha=$(echo "$current" | python3 -c "import json,sys,hashlib; d=json.loads(sys.stdin.read()); print(hashlib.sha256(json.dumps(d,sort_keys=True,separators=(',',':')).encode()).hexdigest()[:16])" 2>/dev/null || echo "unknown")

    if [[ "$old_sha" == "$new_sha" ]]; then
      ok "Cloudflare rollback profile verified (attempt ${attempt})"
      return 0
    fi

    if [[ "$attempt" -lt "$CF_VERIFY_ATTEMPTS" ]]; then
      warn "Cloudflare rollback verify attempt ${attempt}/${CF_VERIFY_ATTEMPTS} mismatch; retrying in ${CF_VERIFY_SLEEP}s..."
      sleep "$CF_VERIFY_SLEEP"
    fi
  done

  err "Cloudflare rollback verification failed after ${CF_VERIFY_ATTEMPTS} attempts"
  return 1
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

  # Upload with retry
  local upload_ok=0
  local upload_attempt
  for upload_attempt in $(seq 1 "$CF_VERIFY_ATTEMPTS"); do
    local response
    response=$(curl -fsS -X POST "$ADMIN_UPDATE_URL" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-binary "@${profile_path}" \
      2>&1) && {
      echo "$response"
      upload_ok=1
      break
    }

    if [[ "$upload_attempt" -lt "$CF_VERIFY_ATTEMPTS" ]]; then
      warn "Profile upload attempt ${upload_attempt}/${CF_VERIFY_ATTEMPTS} failed; retrying in ${CF_VERIFY_SLEEP}s..."
      sleep "$CF_VERIFY_SLEEP"
    fi
  done

  if [[ "$upload_ok" != "1" ]]; then
    err "Cloudflare profile upload failed after ${CF_VERIFY_ATTEMPTS} attempts"
    return 1
  fi

  CF_PROFILE_UPDATED=1
  ok "Profile uploaded to Cloudflare"

  # Verify with retry/backoff
  log "Verifying Cloudflare profile (may retry on stale reads)..."

  local local_sha
  local_sha=$(json_sha16 "$profile_path")
  local local_updated
  local_updated=$(jq -r '.updatedAt // "unknown"' "$profile_path" 2>/dev/null || echo "unknown")

  local verify_attempt
  for verify_attempt in $(seq 1 "$CF_VERIFY_ATTEMPTS"); do
    local current
    current=$(curl -fsS "$ADMIN_CURRENT_URL" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      2>&1) || {
      warn "Cloudflare GET /admin/current failed (attempt ${verify_attempt})"
      if [[ "$verify_attempt" -lt "$CF_VERIFY_ATTEMPTS" ]]; then
        sleep "$CF_VERIFY_SLEEP"
      fi
      continue
    }

    # Output sha/atUpdatedAt comparison
    local cloud_sha cloud_updated
    cloud_sha=$(echo "$current" | python3 -c "import json,sys,hashlib; d=json.loads(sys.stdin.read()); print(hashlib.sha256(json.dumps(d,sort_keys=True,separators=(',',':')).encode()).hexdigest()[:16])" 2>/dev/null || echo "unknown")
    cloud_updated=$(echo "$current" | jq -r '.updatedAt // "unknown"' 2>/dev/null || echo "unknown")

    echo "  local updatedAt:  ${local_updated}"
    echo "  cloud updatedAt:  ${cloud_updated}"
    echo "  local sha16:      ${local_sha}"
    echo "  cloud sha16:      ${cloud_sha}"

    if check_cf_verify "$current"; then
      ok "Cloudflare profile verified (attempt ${verify_attempt})"
      return 0
    fi

    local mismatch_summary
    mismatch_summary=$(cf_mismatch_summary "$current")
    warn "Cloudflare verify attempt ${verify_attempt}/${CF_VERIFY_ATTEMPTS} mismatch: ${mismatch_summary}"
    warn "Cloudflare may still be returning stale profile; retrying in ${CF_VERIFY_SLEEP}s..."

    if [[ "$verify_attempt" -lt "$CF_VERIFY_ATTEMPTS" ]]; then
      sleep "$CF_VERIFY_SLEEP"
    fi
  done

  err "Cloudflare profile verification failed after ${CF_VERIFY_ATTEMPTS} attempts"
  return 1
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

    # Best-effort Cloudflare rollback if we uploaded a new profile
    if [[ "$CF_PROFILE_UPDATED" == "1" ]] && [[ -f "${BACKUP_DIR}/profile.current.json" ]]; then
      if restore_cloudflare_profile "${BACKUP_DIR}/profile.current.json"; then
        warn "Cloudflare rollback profile verified"
      else
        warn ""
        warn "Local rollback completed, but Cloudflare rollback failed."
        warn "Local and Cloudflare profiles may be inconsistent."
        warn ""
        warn "To manually resync, run:"
        warn "  curl -fsS -X POST \"\$ADMIN_UPDATE_URL\" \\"
        warn "    -H \"Authorization: Bearer \$ADMIN_TOKEN\" \\"
        warn "    -H \"Content-Type: application/json\" \\"
        warn "    --data-binary @${NANOBK_CONFIG_DIR}/profile.current.json"
        warn ""
        warn "Use ADMIN_TOKEN from your cf-admin-env file."
      fi
    fi

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
