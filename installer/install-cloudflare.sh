#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare nanok Deployment Automation
#
# Deploys the nanok primary subscription Worker to Cloudflare,
# creates or uses a KV namespace, sets secrets, uploads profile,
# and verifies the deployment.
#
# Prerequisites:
#   - Node.js and npm
#   - Wrangler CLI (auto-detected: npx wrangler or global wrangler)
#   - Cloudflare account (wrangler login)
#   - profile.current.json from VPS installer (or examples/profile.example.json)
#
# Usage:
#   bash installer/install-cloudflare.sh --yes \
#     --create-kv \
#     --profile /etc/nanobk/profile.current.json \
#     --route-url https://nanok.yourdomain.com
#
# Status: v0.3.1 — nanok deployment automated. nanob/edgetunnel: future versions.

set -Eeuo pipefail

# ── Resolve script directory ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# ── Default configuration ──────────────────────────────────────────────────

DRY_RUN=0
NANOBK_YES=0
FORCE=0

WORKER_NAME="nanok"
WORKER_DIR="${REPO_DIR}/workers/nanok"
PROFILE_PATH="/etc/nanobk/profile.current.json"

SUB_TOKEN=""
ADMIN_TOKEN=""
SUB_PATH="/jb"
ADMIN_PATH="/admin/update"
ADMIN_CURRENT_PATH="/admin/current"

KV_NAMESPACE_ID=""
CREATE_KV=0
KV_BINDING="SUB_STORE"

ROUTE_URL=""
SKIP_PROFILE_UPLOAD=0
SKIP_VERIFY=0

# Derived
WRANGLER=""
WRANGLER_TOML_PATH=""
LOCAL_ENV_FILE="${REPO_DIR}/.cloudflare.local.env"

# ── Helpers ─────────────────────────────────────────────────────────────────

fingerprint() {
  local s="$1"
  local len=${#s}
  if [[ $len -le 12 ]]; then
    echo "${s:0:3}...${s: -3}"
  else
    echo "${s:0:6}...${s: -6}"
  fi
}

generate_token() {
  openssl rand -base64 32 | tr -d '\n/+=' | head -c 32
}

confirm_or_die() {
  local prompt="${1:-Continue?}"
  if [[ "$NANOBK_YES" == "1" ]]; then
    return 0
  fi
  echo -en "${YELLOW}${prompt} [y/N]${NC} "
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    die "Aborted by user"
  fi
}

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — Cloudflare nanok Deployment v0.3.1

Usage:
  bash installer/install-cloudflare.sh [OPTIONS]

Options:
  --dry-run                  Print actions without modifying Cloudflare
  --yes                      Non-interactive mode
  --force                    Overwrite existing wrangler.toml in worker dir
  --worker-name NAME         Worker name (default: nanok)
  --worker-dir PATH          Worker source dir (default: workers/nanok)
  --profile PATH             Path to profile.current.json
  --sub-token TOKEN          Subscription token (auto-generated if omitted)
  --admin-token TOKEN        Admin token (auto-generated if omitted)
  --sub-path PATH            Subscription path (default: /jb)
  --admin-path PATH          Admin update path (default: /admin/update)
  --admin-current-path PATH  Admin read path (default: /admin/current)
  --kv-namespace-id ID       Use existing KV namespace
  --create-kv                Auto-create KV namespace
  --kv-binding NAME          KV binding name (default: SUB_STORE)
  --route-url URL            Worker URL for profile upload and verification
  --skip-profile-upload      Deploy Worker only, do not upload profile
  --skip-verify              Skip HTTP verification after deploy
  --help                     Show this help

Examples:
  # Dry-run with existing KV and profile
  bash installer/install-cloudflare.sh --dry-run --yes \
    --profile examples/profile.example.json \
    --kv-namespace-id abc123 \
    --route-url https://nanok.example.workers.dev

  # Auto-create KV, generate tokens
  bash installer/install-cloudflare.sh --yes \
    --create-kv \
    --profile /etc/nanobk/profile.current.json \
    --route-url https://nanok.yourdomain.com

  # Deploy only (manual profile upload later)
  bash installer/install-cloudflare.sh --yes \
    --kv-namespace-id abc123 \
    --skip-profile-upload --skip-verify
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)              DRY_RUN=1 ;;
      --yes)                  NANOBK_YES=1 ;;
      --force)                FORCE=1 ;;
      --worker-name)          WORKER_NAME="$2"; shift ;;
      --worker-dir)           WORKER_DIR="$2"; shift ;;
      --profile)              PROFILE_PATH="$2"; shift ;;
      --sub-token)            SUB_TOKEN="$2"; shift ;;
      --admin-token)          ADMIN_TOKEN="$2"; shift ;;
      --sub-path)             SUB_PATH="$2"; shift ;;
      --admin-path)           ADMIN_PATH="$2"; shift ;;
      --admin-current-path)   ADMIN_CURRENT_PATH="$2"; shift ;;
      --kv-namespace-id)      KV_NAMESPACE_ID="$2"; shift ;;
      --create-kv)            CREATE_KV=1 ;;
      --kv-binding)           KV_BINDING="$2"; shift ;;
      --route-url)            ROUTE_URL="$2"; shift ;;
      --skip-profile-upload)  SKIP_PROFILE_UPLOAD=1 ;;
      --skip-verify)          SKIP_VERIFY=1 ;;
      --help|-h)              show_help; exit 0 ;;
      *)                      die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done

  # Validate KV config
  if [[ -z "$KV_NAMESPACE_ID" ]] && [[ "$CREATE_KV" != "1" ]]; then
    if [[ "$NANOBK_YES" == "1" ]]; then
      die "Either --kv-namespace-id or --create-kv is required. Use --create-kv to auto-create."
    else
      echo ""
      echo "  No KV namespace specified."
      echo "  Use --kv-namespace-id ID to use an existing one."
      echo "  Use --create-kv to auto-create a new one."
      echo ""
      confirm_or_die "Create a new KV namespace?" && CREATE_KV=1 || die "Aborted."
    fi
  fi

  # Trim trailing slash from route URL
  ROUTE_URL="${ROUTE_URL%/}"
}

# ── Wrangler detection ──────────────────────────────────────────────────────

check_wrangler() {
  log "Checking Wrangler CLI..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would check: npx wrangler --version"
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would check: wrangler whoami"
    WRANGLER="wrangler"
    return 0
  fi

  # Try npx wrangler first, then global
  if command -v npx &>/dev/null; then
    if npx wrangler --version &>/dev/null; then
      WRANGLER="npx wrangler"
      ok "Wrangler via npx: $(npx wrangler --version 2>/dev/null | head -1)"
    fi
  fi

  if [[ -z "$WRANGLER" ]] && command -v wrangler &>/dev/null; then
    WRANGLER="wrangler"
    ok "Wrangler global: $(wrangler --version 2>/dev/null | head -1)"
  fi

  if [[ -z "$WRANGLER" ]]; then
    die "Wrangler CLI not found. Install with:
  npm install -g wrangler
  wrangler login"
  fi

  # Check login
  log "Checking Wrangler authentication..."
  if ! $WRANGLER whoami &>/dev/null; then
    die "Wrangler is not logged in. Run: wrangler login"
  fi
  ok "Wrangler authenticated"
}

# ── KV namespace ────────────────────────────────────────────────────────────

ensure_kv_namespace() {
  if [[ -n "$KV_NAMESPACE_ID" ]]; then
    ok "Using existing KV namespace: ${KV_NAMESPACE_ID}"
    return 0
  fi

  if [[ "$CREATE_KV" != "1" ]]; then
    die "No KV namespace configured. Use --kv-namespace-id or --create-kv."
  fi

  log "Creating KV namespace '${KV_BINDING}'..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} ${WRANGLER} kv:namespace create ${KV_BINDING}"
    KV_NAMESPACE_ID="DRY_RUN_KV_NAMESPACE_ID"
    return 0
  fi

  local output
  output=$($WRANGLER kv:namespace create "$KV_BINDING" 2>&1) || {
    err "Failed to create KV namespace:"
    echo "$output" >&2
    die "Try manually: wrangler kv:namespace create ${KV_BINDING}"
  }

  echo "$output"

  # Parse KV namespace ID from output
  # Wrangler output formats vary:
  #   id = "xxxxxxxx"
  #   { binding = "SUB_STORE", id = "xxxxxxxx" }
  #   {"id":"xxxxxxxx",...}

  # Try: id = "..." format
  KV_NAMESPACE_ID=$(echo "$output" | grep -oP 'id\s*=\s*"\K[^"]+' | head -1) || true

  # Try: JSON format
  if [[ -z "$KV_NAMESPACE_ID" ]] && command -v jq &>/dev/null; then
    KV_NAMESPACE_ID=$(echo "$output" | jq -r '.id // empty' 2>/dev/null) || true
  fi

  # Try: "id: " format
  if [[ -z "$KV_NAMESPACE_ID" ]]; then
    KV_NAMESPACE_ID=$(echo "$output" | grep -oP 'id:\s*\K[a-f0-9]+' | head -1) || true
  fi

  if [[ -z "$KV_NAMESPACE_ID" ]]; then
    err "Could not parse KV namespace ID from Wrangler output:"
    echo "$output" >&2
    die "Please copy the ID manually and re-run with --kv-namespace-id ID"
  fi

  ok "Created KV namespace: ${KV_NAMESPACE_ID}"
}

# ── Generate tokens ─────────────────────────────────────────────────────────

generate_tokens() {
  log "Generating tokens..."

  if [[ -z "$SUB_TOKEN" ]]; then
    SUB_TOKEN=$(generate_token)
    ok "Generated SUB_TOKEN: $(fingerprint "$SUB_TOKEN")"
  else
    ok "SUB_TOKEN provided: $(fingerprint "$SUB_TOKEN")"
  fi

  if [[ -z "$ADMIN_TOKEN" ]]; then
    ADMIN_TOKEN=$(generate_token)
    ok "Generated ADMIN_TOKEN: $(fingerprint "$ADMIN_TOKEN")"
  else
    ok "ADMIN_TOKEN provided: $(fingerprint "$ADMIN_TOKEN")"
  fi
}

# ── Generate wrangler.toml ──────────────────────────────────────────────────

generate_wrangler_toml() {
  WRANGLER_TOML_PATH="${WORKER_DIR}/wrangler.toml"

  log "Generating wrangler.toml at ${WRANGLER_TOML_PATH}..."

  # Validate worker dir
  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -d "$WORKER_DIR" ]] || die "Worker dir not found: ${WORKER_DIR}"
    [[ -f "$WORKER_DIR/src/index.js" ]] || die "Worker entry not found: ${WORKER_DIR}/src/index.js"
  fi

  # Check for existing wrangler.toml
  if [[ -f "$WRANGLER_TOML_PATH" ]]; then
    if grep -q 'Generated by NanoBK install-cloudflare.sh' "$WRANGLER_TOML_PATH" 2>/dev/null; then
      ok "Existing wrangler.toml was generated by NanoBK, will overwrite"
    elif [[ "$FORCE" == "1" ]]; then
      warn "Overwriting existing wrangler.toml (--force)"
    else
      die "Existing wrangler.toml was not generated by NanoBK.
  Path: ${WRANGLER_TOML_PATH}
  Use --force to overwrite, or back it up manually first."
    fi
  fi

  local content="# Generated by NanoBK install-cloudflare.sh. Do not commit.
name = \"${WORKER_NAME}\"
main = \"src/index.js\"
compatibility_date = \"2024-01-01\"

[[kv_namespaces]]
binding = \"${KV_BINDING}\"
id = \"${KV_NAMESPACE_ID}\"

[vars]
SUB_PATH = \"${SUB_PATH}\"
ADMIN_PATH = \"${ADMIN_PATH}\"
ADMIN_CURRENT_PATH = \"${ADMIN_CURRENT_PATH}\"
"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${WRANGLER_TOML_PATH}:"
    echo "$content" | sed 's/^/    /'
    return 0
  fi

  printf '%s\n' "$content" > "$WRANGLER_TOML_PATH"
  ok "Generated: ${WRANGLER_TOML_PATH}"
}

# ── Set Worker secrets ──────────────────────────────────────────────────────

set_worker_secrets() {
  log "Setting Worker secrets..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set secret SUB_TOKEN (fingerprint: $(fingerprint "$SUB_TOKEN"))"
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set secret ADMIN_TOKEN (fingerprint: $(fingerprint "$ADMIN_TOKEN"))"
    return 0
  fi

  # Run from WORKER_DIR so wrangler.toml relative paths work
  (
    cd "$WORKER_DIR"
    log "Setting SUB_TOKEN..."
    if ! printf '%s' "$SUB_TOKEN" | $WRANGLER secret put SUB_TOKEN --config wrangler.toml 2>&1; then
      die "Failed to set SUB_TOKEN secret"
    fi
  )
  ok "SUB_TOKEN set"

  (
    cd "$WORKER_DIR"
    log "Setting ADMIN_TOKEN..."
    if ! printf '%s' "$ADMIN_TOKEN" | $WRANGLER secret put ADMIN_TOKEN --config wrangler.toml 2>&1; then
      die "Failed to set ADMIN_TOKEN secret"
    fi
  )
  ok "ADMIN_TOKEN set"
}

# ── Deploy Worker ───────────────────────────────────────────────────────────

deploy_nanok() {
  log "Deploying nanok Worker..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} (cd ${WORKER_DIR} && ${WRANGLER} deploy --config wrangler.toml)"
    return 0
  fi

  local output
  output=$(
    cd "$WORKER_DIR"
    $WRANGLER deploy --config wrangler.toml 2>&1
  ) || {
    err "Wrangler deploy failed:"
    echo "$output" >&2
    die "Check your wrangler.toml and try again."
  }

  echo "$output"
  ok "nanok Worker deployed"

  if [[ -z "$ROUTE_URL" ]]; then
    warn "No --route-url provided. Profile upload and verification will be skipped."
    warn "Set --route-url to your Worker URL (e.g., https://nanok.yourdomain.com)"
  fi
}

# ── Validate profile file ───────────────────────────────────────────────────

validate_profile_file() {
  if [[ "$SKIP_PROFILE_UPLOAD" == "1" ]]; then
    return 0
  fi

  if [[ -z "$ROUTE_URL" ]]; then
    return 0
  fi

  log "Validating profile file..."

  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ -f "$PROFILE_PATH" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} Would validate ${PROFILE_PATH}"
    else
      warn "Profile not found: ${PROFILE_PATH} (OK in dry-run)"
    fi
    return 0
  fi

  [[ -f "$PROFILE_PATH" ]] || die "Profile file not found: ${PROFILE_PATH}
Run the VPS installer first, or provide --profile PATH."

  # Validate JSON structure
  if command -v jq &>/dev/null; then
    if ! jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$PROFILE_PATH" >/dev/null 2>&1; then
      die "Profile JSON missing required sections (hy2/tuic/reality/trojan): ${PROFILE_PATH}"
    fi
    ok "Profile JSON validated: ${PROFILE_PATH}"
  elif command -v python3 &>/dev/null; then
    if ! python3 -c "
import json, sys
with open('${PROFILE_PATH}') as f:
    data = json.load(f)
for k in ('hy2','tuic','reality','trojan'):
    if k not in data:
        print(f'Missing: {k}', file=sys.stderr)
        sys.exit(1)
" 2>/dev/null; then
      die "Profile JSON validation failed: ${PROFILE_PATH}"
    fi
    ok "Profile JSON validated (via python3): ${PROFILE_PATH}"
  else
    warn "Neither jq nor python3 available, skipping profile JSON validation"
  fi
}

# ── Upload profile ──────────────────────────────────────────────────────────

upload_profile() {
  if [[ "$SKIP_PROFILE_UPLOAD" == "1" ]]; then
    log "Skipping profile upload (--skip-profile-upload)"
    return 0
  fi

  if [[ -z "$ROUTE_URL" ]]; then
    warn "Skipping profile upload: no --route-url provided"
    return 0
  fi

  local upload_url="${ROUTE_URL}${ADMIN_PATH}"

  log "Uploading profile to ${upload_url}..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} curl -X POST ${upload_url}"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   -H 'Authorization: Bearer $(fingerprint "$ADMIN_TOKEN")...'"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   --data-binary @${PROFILE_PATH}"
    return 0
  fi

  local response
  response=$(curl -fsS -X POST "$upload_url" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${PROFILE_PATH}" \
    2>&1) || {
    err "Profile upload failed. HTTP response:"
    echo "$response" >&2
    echo "" >&2
    echo "Troubleshooting:" >&2
    echo "  1. Check --route-url is correct" >&2
    echo "  2. Check ADMIN_TOKEN matches the Worker secret" >&2
    echo "  3. Check ADMIN_PATH matches the Worker config" >&2
    echo "  4. Try: curl -v ${upload_url}" >&2
    return 1
  }

  echo "$response"
  ok "Profile uploaded successfully"
}

# ── Verify deployment ───────────────────────────────────────────────────────

verify_nanok() {
  if [[ "$SKIP_VERIFY" == "1" ]]; then
    log "Skipping verification (--skip-verify)"
    return 0
  fi

  if [[ -z "$ROUTE_URL" ]]; then
    warn "Skipping verification: no --route-url provided"
    return 0
  fi

  log "Verifying nanok deployment..."

  # Check admin endpoint
  local admin_url="${ROUTE_URL}${ADMIN_CURRENT_PATH}"
  log "Checking admin endpoint: ${admin_url}"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} curl ${admin_url} -H 'Authorization: Bearer $(fingerprint "$ADMIN_TOKEN")...'"
    echo -e "  ${CYAN}[DRY-RUN]${NC} curl ${ROUTE_URL}${SUB_PATH}?token=$(fingerprint "$SUB_TOKEN")..."
    return 0
  fi

  local admin_response
  admin_response=$(curl -fsS "$admin_url" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    2>&1) || {
    err "Admin endpoint check failed:"
    echo "$admin_response" >&2
    return 1
  }

  # Validate admin response has required fields
  if command -v jq &>/dev/null; then
    if echo "$admin_response" | jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' >/dev/null 2>&1; then
      ok "Admin endpoint: profile has all four protocol sections"
    else
      err "Admin endpoint: profile missing required sections"
      echo "$admin_response" | jq . 2>/dev/null || echo "$admin_response"
      return 1
    fi
  else
    ok "Admin endpoint: responded (jq not available for deep validation)"
  fi

  # Check subscription endpoint
  local sub_url="${ROUTE_URL}${SUB_PATH}?token=${SUB_TOKEN}"
  log "Checking subscription endpoint..."

  local sub_response
  sub_response=$(curl -fsS "$sub_url" 2>&1) || {
    err "Subscription endpoint check failed:"
    echo "$sub_response" >&2
    return 1
  }

  # Check YAML contains required sections
  local yaml_ok=1
  for marker in "proxies:" "type: hysteria2" "type: tuic" "type: vless" "type: trojan" "proxy-groups:" "rules:"; do
    if ! echo "$sub_response" | grep -q "$marker"; then
      err "Subscription YAML missing: ${marker}"
      yaml_ok=0
    fi
  done

  if [[ "$yaml_ok" == "0" ]]; then
    err "Subscription YAML validation failed"
    return 1
  fi
  ok "Subscription YAML: all required sections present"

  # Check for control characters
  if echo "$sub_response" | python3 -c "
import sys
data = sys.stdin.buffer.read()
bad = [b for b in data if (b < 32 and b not in (9, 10, 13)) or b == 127]
sys.exit(1 if bad else 0)
" 2>/dev/null; then
    ok "Subscription YAML: no invalid control characters"
  else
    err "Subscription YAML contains invalid control characters"
    return 1
  fi

  ok "Verification passed"
}

# ── Write local env file ────────────────────────────────────────────────────

# Usage: write_local_env [deploy_status] [upload_status] [verify_status]
write_local_env() {
  local deploy_status="${1:-pending}"
  local upload_status="${2:-pending}"
  local verify_status="${3:-pending}"

  log "Saving local secret file..."

  local content="# Generated by NanoBK install-cloudflare.sh
# KEEP THIS FILE PRIVATE — never commit to Git.

NANOK_WORKER_NAME=\"${WORKER_NAME}\"
NANOK_ROUTE_URL=\"${ROUTE_URL}\"
SUB_TOKEN=\"${SUB_TOKEN}\"
ADMIN_TOKEN=\"${ADMIN_TOKEN}\"
SUB_STORE_KV_NAMESPACE_ID=\"${KV_NAMESPACE_ID}\"
SUB_PATH=\"${SUB_PATH}\"
ADMIN_PATH=\"${ADMIN_PATH}\"
ADMIN_CURRENT_PATH=\"${ADMIN_CURRENT_PATH}\"
NANOBK_PROFILE_PATH=\"${PROFILE_PATH}\"
NANOBK_DEPLOY_STATUS=\"${deploy_status}\"
NANOBK_PROFILE_UPLOAD_STATUS=\"${upload_status}\"
NANOBK_VERIFY_STATUS=\"${verify_status}\"
"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${LOCAL_ENV_FILE} (mode 600)"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   deploy_status=${deploy_status}, upload_status=${upload_status}, verify_status=${verify_status}"
    return 0
  fi

  printf '%s\n' "$content" > "$LOCAL_ENV_FILE"
  chmod 600 "$LOCAL_ENV_FILE"
  ok "Saved ${LOCAL_ENV_FILE} (mode 600) [deploy=${deploy_status}]"
}

# ── Print next steps ────────────────────────────────────────────────────────

print_next_steps() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║     NanoBK Cloudflare Setup Completed                   ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  nanok Worker:"
  echo "    name:  ${WORKER_NAME}"
  [[ -n "$ROUTE_URL" ]] && echo "    url:   ${ROUTE_URL}"
  echo ""
  if [[ -n "$ROUTE_URL" ]]; then
    echo "  Subscription URL (contains SUB_TOKEN — keep private):"
    echo "    ${ROUTE_URL}${SUB_PATH}?token=${SUB_TOKEN}"
    echo ""
    echo "  Admin update URL:"
    echo "    ${ROUTE_URL}${ADMIN_PATH}"
  fi
  echo ""
  echo "  Local secret file:"
  echo "    ${LOCAL_ENV_FILE}"
  echo ""
  echo "  Next steps:"
  echo "    1. Import subscription URL into Clash/Mihomo."
  echo "    2. On VPS, create admin env for key rotation:"
    echo ""
  echo "       cat > /root/.nanok-cf-admin.env <<'ENVEOF'"
  echo "       ADMIN_TOKEN=\"${ADMIN_TOKEN}\""
  if [[ -n "$ROUTE_URL" ]]; then
    echo "       ADMIN_CURRENT_URL=\"${ROUTE_URL}${ADMIN_CURRENT_PATH}\""
    echo "       ADMIN_UPDATE_URL=\"${ROUTE_URL}${ADMIN_PATH}\""
  fi
  echo "       ENVEOF"
  echo "       chmod 600 /root/.nanok-cf-admin.env"
  echo ""
  echo "    3. Optional: deploy nanob aggregator (future version)."
  echo ""
  warn "Keep ${LOCAL_ENV_FILE} and /root/.nanok-cf-admin.env private."
  warn "Never commit these files to Git."
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  echo ""
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   NanoBK Cloudflare Installer — DRY-RUN                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
  else
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   NanoBK Cloudflare Installer                           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
  fi
  echo ""
  echo "  Worker name:    ${WORKER_NAME}"
  echo "  Worker dir:     ${WORKER_DIR}"
  echo "  Profile:        ${PROFILE_PATH}"
  echo "  KV binding:     ${KV_BINDING}"
  echo "  KV namespace:   ${KV_NAMESPACE_ID:-<will create>}"
  echo "  Route URL:      ${ROUTE_URL:-<not set>}"
  echo "  Sub path:       ${SUB_PATH}"
  echo "  Admin path:     ${ADMIN_PATH}"
  echo ""

  confirm_or_die "Proceed with Cloudflare deployment?"

  # Phase 1: Wrangler
  check_wrangler

  # Phase 2: KV
  ensure_kv_namespace

  # Phase 3: Tokens
  generate_tokens

  # Phase 4: Save secrets early (before any Cloudflare operations)
  write_local_env "prepared" "pending" "pending"

  # Phase 5: Generate wrangler.toml
  generate_wrangler_toml

  # Phase 6: Validate profile file
  validate_profile_file

  # Phase 7: Set secrets
  set_worker_secrets

  # Phase 8: Deploy
  deploy_nanok
  write_local_env "deployed" "pending" "pending"

  # Phase 9: Upload profile
  upload_profile
  write_local_env "deployed" "uploaded" "pending"

  # Phase 10: Verify
  verify_nanok
  write_local_env "deployed" "uploaded" "verified"

  # Phase 11: Next steps
  print_next_steps
}

main "$@"
