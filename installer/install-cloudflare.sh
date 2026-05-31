#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Deployment Automation
#
# Deploys nanok (primary subscription) and optionally nanob (aggregator) Workers.
# nanob can optionally merge edgetunnel backup nodes.
# Without edgetunnel, nanob returns nanok primary subscription only.
#
# Prerequisites:
#   - Node.js and npm
#   - Wrangler CLI (auto-detected: npx wrangler or global wrangler)
#   - Cloudflare account (wrangler login)
#   - profile.current.json from VPS installer (or examples/profile.example.json)
#
# Usage:
#   bash installer/install-cloudflare.sh --yes \
#     --create-kv --create-nanob-geo-kv \
#     --profile /etc/nanobk/profile.current.json \
#     --route-url https://nanok.yourdomain.com \
#     --deploy-nanob --nanob-route-url https://nanob.yourdomain.com

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
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; }

# ── Helpers ─────────────────────────────────────────────────────────────────

node_major_version() {
  node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1
}

# ── Default configuration ──────────────────────────────────────────────────

DRY_RUN=0
NANOBK_YES=0
FORCE=0
PREFLIGHT=0
VALIDATE_PROFILE_ONLY=0

# nanok
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

# nanob
DEPLOY_NANOB=0
NANOB_WORKER_NAME="nanob"
NANOB_WORKER_DIR="${REPO_DIR}/workers/nanob"
NANOB_ROUTE_URL=""
NANOB_TOKEN=""
NANOB_PATH="/jb"
NANOB_GEO_KV_NAMESPACE_ID=""
CREATE_NANOB_GEO_KV=0
NANOB_GEO_KV_BINDING="NANOB_GEO_CACHE"
EDGE_HOST=""
EDGE_SUB_PATH="/sub?target=clash"
EDGETUNNEL_EXPORT_TOKEN=""
SKIP_NANOB_VERIFY=0

# Derived
WRANGLER=""
WRANGLER_TOML_PATH=""
NANOB_WRANGLER_TOML_PATH=""
LOCAL_ENV_FILE="${REPO_DIR}/.cloudflare.local.env"
NANOB_LOCAL_ENV_FILE="${REPO_DIR}/.nanob.local.env"

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

clean_host() {
  local text="$1"
  echo "$text" | sed 's|^https\?://||; s|/$||'
}

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — Cloudflare Deployment v1.3.0

Usage:
  bash installer/install-cloudflare.sh [OPTIONS]

General:
  --dry-run                  Print actions without modifying Cloudflare
  --yes                      Non-interactive mode
  --force                    Overwrite existing wrangler.toml in worker dirs
  --preflight                Run pre-deployment checks only (no Cloudflare changes)
  --validate-profile-only    Validate profile JSON only (no Cloudflare, no wrangler)
  --help                     Show this help

nanok options (primary subscription):
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
  --route-url URL            nanok Worker URL for profile upload and verification
  --skip-profile-upload      Deploy Worker only, do not upload profile
  --skip-verify              Skip nanok HTTP verification

nanob options (optional aggregator):
  --deploy-nanob             Deploy nanob aggregator Worker
  --nanob-worker-name NAME   nanob Worker name (default: nanob)
  --nanob-worker-dir PATH    nanob Worker source dir (default: workers/nanob)
  --nanob-route-url URL      nanob Worker URL for verification
  --nanob-token TOKEN        nanob subscription token (auto-generated if omitted)
  --nanob-path PATH          nanob subscription path (default: /jb)
  --nanob-geo-kv-namespace-id ID  Use existing Geo KV namespace
  --create-nanob-geo-kv      Auto-create Geo KV namespace
  --nanob-geo-kv-binding NAME Geo KV binding (default: NANOB_GEO_CACHE)
  --edge-host HOST           Optional edgetunnel host (enables edgetunnel)
  --edge-sub-path PATH       Edgetunnel sub path (default: /sub?target=clash)
  --edgetunnel-export-token TOKEN  Edgetunnel internal auth token (optional)
  --skip-nanob-verify        Skip nanob HTTP verification

Examples:
  # nanok only
  bash installer/install-cloudflare.sh --yes \
    --create-kv --profile /etc/nanobk/profile.current.json \
    --route-url https://nanok.yourdomain.com

  # nanok + nanob (no edgetunnel)
  bash installer/install-cloudflare.sh --yes \
    --create-kv --create-nanob-geo-kv \
    --profile /etc/nanobk/profile.current.json \
    --route-url https://nanok.yourdomain.com \
    --deploy-nanob --nanob-route-url https://nanob.yourdomain.com

  # nanok + nanob + edgetunnel
  bash installer/install-cloudflare.sh --yes \
    --create-kv --create-nanob-geo-kv \
    --profile /etc/nanobk/profile.current.json \
    --route-url https://nanok.yourdomain.com \
    --deploy-nanob --nanob-route-url https://nanob.yourdomain.com \
    --edge-host edge-subscription.example.com \
    --edgetunnel-export-token YOUR_EDGE_TOKEN
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # nanok
      --dry-run)              DRY_RUN=1 ;;
      --yes)                  NANOBK_YES=1 ;;
      --force)                FORCE=1 ;;
      --preflight)            PREFLIGHT=1 ;;
      --validate-profile-only) VALIDATE_PROFILE_ONLY=1 ;;
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
      # nanob
      --deploy-nanob)               DEPLOY_NANOB=1 ;;
      --nanob-worker-name)          NANOB_WORKER_NAME="$2"; shift ;;
      --nanob-worker-dir)           NANOB_WORKER_DIR="$2"; shift ;;
      --nanob-route-url)            NANOB_ROUTE_URL="$2"; shift ;;
      --nanob-token)                NANOB_TOKEN="$2"; shift ;;
      --nanob-path)                 NANOB_PATH="$2"; shift ;;
      --nanob-geo-kv-namespace-id)  NANOB_GEO_KV_NAMESPACE_ID="$2"; shift ;;
      --create-nanob-geo-kv)        CREATE_NANOB_GEO_KV=1 ;;
      --nanob-geo-kv-binding)       NANOB_GEO_KV_BINDING="$2"; shift ;;
      --edge-host)                  EDGE_HOST="$2"; shift ;;
      --edge-sub-path)              EDGE_SUB_PATH="$2"; shift ;;
      --edgetunnel-export-token)    EDGETUNNEL_EXPORT_TOKEN="$2"; shift ;;
      --skip-nanob-verify)          SKIP_NANOB_VERIFY=1 ;;
      # general
      --help|-h)              show_help; exit 0 ;;
      *)                      die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done

  # Skip deployment validation for preflight and validate-profile-only
  if [[ "$PREFLIGHT" != "1" ]] && [[ "$VALIDATE_PROFILE_ONLY" != "1" ]]; then
    # Validate nanok KV config
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

    # Validate nanob config
    if [[ "$DEPLOY_NANOB" == "1" ]]; then
      if [[ -z "$NANOB_ROUTE_URL" ]]; then
        die "--nanob-route-url is required when using --deploy-nanob"
      fi
      # nanob needs nanok origin
      if [[ -z "$ROUTE_URL" ]] && [[ "$DRY_RUN" != "1" ]]; then
        die "--route-url is required when deploying nanob (nanob needs nanok origin)"
      fi
      # Validate nanob Geo KV
      if [[ -z "$NANOB_GEO_KV_NAMESPACE_ID" ]] && [[ "$CREATE_NANOB_GEO_KV" != "1" ]]; then
        if [[ "$NANOBK_YES" == "1" ]]; then
          die "nanob Geo KV: use --nanob-geo-kv-namespace-id or --create-nanob-geo-kv"
        else
          confirm_or_die "Create a new Geo KV namespace for nanob?" && CREATE_NANOB_GEO_KV=1 || die "Aborted."
        fi
      fi
    fi
  fi

  # Trim trailing slashes
  ROUTE_URL="${ROUTE_URL%/}"
  NANOB_ROUTE_URL="${NANOB_ROUTE_URL%/}"
  # Clean edge host
  EDGE_HOST=$(clean_host "$EDGE_HOST")
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

  # Check Node.js version (Wrangler 4.95+ requires Node >=22)
  if command -v node &>/dev/null; then
    local nmajor
    nmajor=$(node_major_version)
    if [[ "$nmajor" -lt 22 ]] 2>/dev/null; then
      die "Node.js $(node --version) detected. Wrangler 4.95+ requires Node.js >=22.
Install Node.js 22+:
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt install -y nodejs
Then verify: node -v"
    fi
  fi

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
  wrangler login
Or use npx: npx wrangler --version"
  fi

  log "Checking Wrangler authentication..."
  if ! $WRANGLER whoami &>/dev/null; then
    die "Wrangler is not logged in.
Run: wrangler login
If you are on a remote VPS, copy the login URL to your browser,
finish authorization, then rerun this installer."
  fi
  ok "Wrangler authenticated"
}

# ── KV namespace (generic) ──────────────────────────────────────────────────

# Args: binding_name create_flag_var namespace_id_var
create_kv_namespace_generic() {
  local binding="$1"
  local create_flag="$2"
  local id_var="$3"

  # Check if already set
  local current_id="${!id_var:-}"
  if [[ -n "$current_id" ]]; then
    ok "Using existing KV namespace: ${current_id}"
    return 0
  fi

  if [[ "${!create_flag}" != "1" ]]; then
    return 1
  fi

  log "Creating KV namespace '${binding}'..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} ${WRANGLER} kv namespace create ${binding}"
    eval "$id_var=\"DRY_RUN_KV_ID\""
    return 0
  fi

  local output
  output=$($WRANGLER kv namespace create "$binding" 2>&1) || {
    err "Failed to create KV namespace '${binding}':"
    echo "$output" >&2
    die "Try manually: wrangler kv namespace create ${binding}"
  }

  echo "$output"

  # Parse ID
  local parsed_id
  parsed_id=$(echo "$output" | grep -oP 'id\s*=\s*"\K[^"]+' | head -1) || true

  if [[ -z "$parsed_id" ]] && command -v jq &>/dev/null; then
    parsed_id=$(echo "$output" | jq -r '.id // empty' 2>/dev/null) || true
  fi

  if [[ -z "$parsed_id" ]]; then
    parsed_id=$(echo "$output" | grep -oP 'id:\s*\K[a-f0-9]+' | head -1) || true
  fi

  if [[ -z "$parsed_id" ]]; then
    err "Could not parse KV namespace ID from Wrangler output:"
    echo "$output" >&2
    die "Copy the ID manually and re-run with the appropriate --*-kv-namespace-id flag"
  fi

  eval "$id_var=\"$parsed_id\""
  ok "Created KV namespace '${binding}': ${parsed_id}"
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

  # Generate nanob token if deploying nanob
  if [[ "$DEPLOY_NANOB" == "1" ]] && [[ -z "$NANOB_TOKEN" ]]; then
    NANOB_TOKEN=$(generate_token)
    ok "Generated NANOB_TOKEN: $(fingerprint "$NANOB_TOKEN")"
  elif [[ "$DEPLOY_NANOB" == "1" ]]; then
    ok "NANOB_TOKEN provided: $(fingerprint "$NANOB_TOKEN")"
  fi
}

# ── Check existing wrangler.toml ────────────────────────────────────────────

check_existing_toml() {
  local toml_path="$1"
  local label="$2"

  if [[ -f "$toml_path" ]]; then
    if grep -q 'Generated by NanoBK install-cloudflare.sh' "$toml_path" 2>/dev/null; then
      ok "${label}: existing wrangler.toml was generated by NanoBK, will overwrite"
    elif [[ "$FORCE" == "1" ]]; then
      warn "${label}: overwriting existing wrangler.toml (--force)"
    else
      die "${label}: existing wrangler.toml was not generated by NanoBK.
  Path: ${toml_path}
  Use --force to overwrite, or back it up manually first."
    fi
  fi
}

# ── Generate nanok wrangler.toml ────────────────────────────────────────────

generate_wrangler_toml() {
  WRANGLER_TOML_PATH="${WORKER_DIR}/wrangler.toml"

  log "Generating nanok wrangler.toml at ${WRANGLER_TOML_PATH}..."

  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -d "$WORKER_DIR" ]] || die "Worker dir not found: ${WORKER_DIR}"
    [[ -f "$WORKER_DIR/src/index.js" ]] || die "Worker entry not found: ${WORKER_DIR}/src/index.js"
  fi

  check_existing_toml "$WRANGLER_TOML_PATH" "nanok"

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

# ── Generate nanob wrangler.toml ────────────────────────────────────────────

generate_nanob_wrangler_toml() {
  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    return 0
  fi

  NANOB_WRANGLER_TOML_PATH="${NANOB_WORKER_DIR}/wrangler.toml"

  log "Generating nanob wrangler.toml at ${NANOB_WRANGLER_TOML_PATH}..."

  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -d "$NANOB_WORKER_DIR" ]] || die "nanob worker dir not found: ${NANOB_WORKER_DIR}"
    [[ -f "$NANOB_WORKER_DIR/src/index.js" ]] || die "nanob entry not found: ${NANOB_WORKER_DIR}/src/index.js"
  fi

  check_existing_toml "$NANOB_WRANGLER_TOML_PATH" "nanob"

  local nanok_origin="${ROUTE_URL}"
  [[ -z "$nanok_origin" ]] && nanok_origin="https://nanok.example.workers.dev"

  local content="# Generated by NanoBK install-cloudflare.sh. Do not commit.
name = \"${NANOB_WORKER_NAME}\"
main = \"src/index.js\"
compatibility_date = \"2024-01-01\"

[[kv_namespaces]]
binding = \"${NANOB_GEO_KV_BINDING}\"
id = \"${NANOB_GEO_KV_NAMESPACE_ID}\"

[[services]]
binding = \"NANOK_SERVICE\"
service = \"${WORKER_NAME}\"

[vars]
NANOK_ORIGIN = \"${nanok_origin}\"
NANOK_SUB_PATH = \"${SUB_PATH}\"
NANOB_PATH = \"${NANOB_PATH}\"
EDGE_HOST = \"${EDGE_HOST}\"
EDGE_SUB_PATH = \"${EDGE_SUB_PATH}\"
"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${NANOB_WRANGLER_TOML_PATH}:"
    echo "$content" | sed 's/^/    /'
    return 0
  fi

  printf '%s\n' "$content" > "$NANOB_WRANGLER_TOML_PATH"
  ok "Generated: ${NANOB_WRANGLER_TOML_PATH}"
}

# ── Set nanok secrets ───────────────────────────────────────────────────────

set_worker_secrets() {
  log "Setting nanok Worker secrets..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set secret SUB_TOKEN (fingerprint: $(fingerprint "$SUB_TOKEN"))"
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set secret ADMIN_TOKEN (fingerprint: $(fingerprint "$ADMIN_TOKEN"))"
    return 0
  fi

  (
    cd "$WORKER_DIR"
    printf '%s' "$SUB_TOKEN" | $WRANGLER secret put SUB_TOKEN --config wrangler.toml 2>&1
  ) || die "Failed to set nanok SUB_TOKEN"
  ok "nanok SUB_TOKEN set"

  (
    cd "$WORKER_DIR"
    printf '%s' "$ADMIN_TOKEN" | $WRANGLER secret put ADMIN_TOKEN --config wrangler.toml 2>&1
  ) || die "Failed to set nanok ADMIN_TOKEN"
  ok "nanok ADMIN_TOKEN set"
}

# ── Set nanob secrets ───────────────────────────────────────────────────────

set_nanob_secrets() {
  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    return 0
  fi

  log "Setting nanob Worker secrets..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set nanob secret NANOB_TOKEN (fingerprint: $(fingerprint "$NANOB_TOKEN"))"
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would set nanob secret NANOK_SUB_TOKEN (fingerprint: $(fingerprint "$SUB_TOKEN"))"
    if [[ -n "$EDGETUNNEL_EXPORT_TOKEN" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} Would set nanob secret EDGETUNNEL_EXPORT_TOKEN (fingerprint: $(fingerprint "$EDGETUNNEL_EXPORT_TOKEN"))"
    else
      echo -e "  ${CYAN}[DRY-RUN]${NC} EDGETUNNEL_EXPORT_TOKEN not provided, edgetunnel will be disabled"
    fi
    return 0
  fi

  (
    cd "$NANOB_WORKER_DIR"
    printf '%s' "$NANOB_TOKEN" | $WRANGLER secret put NANOB_TOKEN --config wrangler.toml 2>&1
  ) || die "Failed to set nanob NANOB_TOKEN"
  ok "nanob NANOB_TOKEN set"

  (
    cd "$NANOB_WORKER_DIR"
    printf '%s' "$SUB_TOKEN" | $WRANGLER secret put NANOK_SUB_TOKEN --config wrangler.toml 2>&1
  ) || die "Failed to set nanob NANOK_SUB_TOKEN"
  ok "nanob NANOK_SUB_TOKEN set"

  # EDGETUNNEL_EXPORT_TOKEN is optional
  if [[ -n "$EDGETUNNEL_EXPORT_TOKEN" ]]; then
    (
      cd "$NANOB_WORKER_DIR"
      printf '%s' "$EDGETUNNEL_EXPORT_TOKEN" | $WRANGLER secret put EDGETUNNEL_EXPORT_TOKEN --config wrangler.toml 2>&1
    ) || die "Failed to set nanob EDGETUNNEL_EXPORT_TOKEN"
    ok "nanob EDGETUNNEL_EXPORT_TOKEN set (edgetunnel enabled)"
  else
    log "No EDGETUNNEL_EXPORT_TOKEN provided — edgetunnel disabled on nanob"
  fi
}

# ── Deploy nanok ────────────────────────────────────────────────────────────

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
    err "nanok deploy failed:"
    echo "$output" >&2
    die "Check your wrangler.toml and try again."
  }

  echo "$output"
  ok "nanok Worker deployed"
}

# ── Deploy nanob ────────────────────────────────────────────────────────────

deploy_nanob() {
  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    return 0
  fi

  log "Deploying nanob Worker..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} (cd ${NANOB_WORKER_DIR} && ${WRANGLER} deploy --config wrangler.toml)"
    return 0
  fi

  local output
  output=$(
    cd "$NANOB_WORKER_DIR"
    $WRANGLER deploy --config wrangler.toml 2>&1
  ) || {
    err "nanob deploy failed:"
    echo "$output" >&2
    die "Check your wrangler.toml and try again."
  }

  echo "$output"
  ok "nanob Worker deployed"
}

# ── Validate profile ────────────────────────────────────────────────────────

validate_profile_file() {
  # In validate-profile-only mode, always validate (even without ROUTE_URL)
  if [[ "$VALIDATE_PROFILE_ONLY" != "1" ]]; then
    if [[ "$SKIP_PROFILE_UPLOAD" == "1" ]] || [[ -z "$ROUTE_URL" ]]; then
      return 0
    fi
  fi

  log "Validating profile file..."

  # Check file existence (even in dry-run, we validate if file exists)
  if [[ ! -f "$PROFILE_PATH" ]]; then
    if [[ "$DRY_RUN" == "1" ]] && [[ "$VALIDATE_PROFILE_ONLY" != "1" ]]; then
      warn "Profile not found: ${PROFILE_PATH} (OK in dry-run)"
      return 0
    fi
    die "Profile file not found: ${PROFILE_PATH}"
  fi

  # Check for private key leakage FIRST — this is a security gate
  if grep -qi 'privateKey\|REALITY_PRIVATE_KEY\|private_key' "$PROFILE_PATH" 2>/dev/null; then
    die "SECURITY: Profile contains private key data. This must NEVER be uploaded.
  File: ${PROFILE_PATH}
  Reality private key must only exist in VPS service configs."
  fi

  if command -v jq &>/dev/null; then
    if ! jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$PROFILE_PATH" >/dev/null 2>&1; then
      die "Profile JSON missing required sections: ${PROFILE_PATH}"
    fi
    ok "Profile JSON validated"
  elif command -v python3 &>/dev/null; then
    if ! python3 -c "import json; d=json.load(open('$PROFILE_PATH')); [d[k] for k in ('hy2','tuic','reality','trojan')]" 2>/dev/null; then
      die "Profile JSON validation failed: ${PROFILE_PATH}"
    fi
    ok "Profile JSON validated (python3)"
  else
    warn "Neither jq nor python3 available, skipping profile validation"
  fi
}

# ── Upload profile ──────────────────────────────────────────────────────────

upload_profile() {
  if [[ "$SKIP_PROFILE_UPLOAD" == "1" ]] || [[ -z "$ROUTE_URL" ]]; then
    return 0
  fi

  local upload_url="${ROUTE_URL}${ADMIN_PATH}"
  log "Uploading profile to ${upload_url}..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} curl -X POST ${upload_url} --data-binary @${PROFILE_PATH}"
    return 0
  fi

  local response
  response=$(curl -fsS -X POST "$upload_url" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${PROFILE_PATH}" \
    2>&1) || {
    err "Profile upload failed:"
    echo "$response" >&2
    return 1
  }

  echo "$response"
  ok "Profile uploaded successfully"
}

# ── Verify nanok ────────────────────────────────────────────────────────────

verify_nanok() {
  if [[ "$SKIP_VERIFY" == "1" ]] || [[ -z "$ROUTE_URL" ]]; then
    return 0
  fi

  log "Verifying nanok deployment..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would verify nanok at ${ROUTE_URL}"
    return 0
  fi

  # Admin endpoint
  local admin_url="${ROUTE_URL}${ADMIN_CURRENT_PATH}"
  local admin_response
  admin_response=$(curl -fsS "$admin_url" -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>&1) || {
    err "nanok admin endpoint check failed"
    return 1
  }

  if command -v jq &>/dev/null; then
    if echo "$admin_response" | jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' >/dev/null 2>&1; then
      ok "nanok admin: profile has all four sections"
    else
      err "nanok admin: profile missing sections"
      return 1
    fi
  fi

  # Subscription endpoint
  local sub_url="${ROUTE_URL}${SUB_PATH}?token=${SUB_TOKEN}"
  local sub_response
  sub_response=$(curl -fsS "$sub_url" 2>&1) || {
    err "nanok subscription check failed"
    return 1
  }

  local yaml_ok=1
  for marker in "proxies:" "type: hysteria2" "type: tuic" "type: vless" "type: trojan" "proxy-groups:" "rules:"; do
    if ! echo "$sub_response" | grep -q "$marker"; then
      err "nanok YAML missing: ${marker}"
      yaml_ok=0
    fi
  done

  if [[ "$yaml_ok" == "0" ]]; then
    return 1
  fi
  ok "nanok subscription YAML: all sections present"

  if echo "$sub_response" | python3 -c "import sys; d=sys.stdin.buffer.read(); sys.exit(1 if any((b<32 and b not in (9,10,13)) or b==127 for b in d) else 0)" 2>/dev/null; then
    ok "nanok YAML: no invalid control characters"
  else
    err "nanok YAML contains invalid control characters"
    return 1
  fi

  ok "nanok verification passed"
}

# ── Verify nanob ────────────────────────────────────────────────────────────

verify_nanob() {
  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    return 0
  fi

  if [[ "$SKIP_NANOB_VERIFY" == "1" ]] || [[ -z "$NANOB_ROUTE_URL" ]]; then
    log "Skipping nanob verification"
    return 0
  fi

  log "Verifying nanob deployment..."

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would verify nanob at ${NANOB_ROUTE_URL}"
    return 0
  fi

  local sub_url="${NANOB_ROUTE_URL}${NANOB_PATH}?token=${NANOB_TOKEN}"
  local sub_response
  sub_response=$(curl -fsS "$sub_url" 2>&1) || {
    err "nanob subscription check failed"
    echo ""
    echo "  If this is a Cloudflare Workers deployment, nanob should use"
    echo "  Service Binding to call nanok (direct fetch may fail with error 1042)."
    echo ""
    echo "  Check workers/nanob/wrangler.toml contains:"
    echo '    [[services]]'
    echo '    binding = "NANOK_SERVICE"'
    echo '    service = "'"${WORKER_NAME}"'"'
    echo ""
    return 1
  }

  # Check primary nodes are present
  local yaml_ok=1
  for marker in "proxies:" "type: hysteria2" "type: tuic" "type: vless" "type: trojan" "proxy-groups:" "rules:"; do
    if ! echo "$sub_response" | grep -q "$marker"; then
      err "nanob YAML missing: ${marker}"
      yaml_ok=0
    fi
  done

  if [[ "$yaml_ok" == "0" ]]; then
    return 1
  fi
  ok "nanob subscription YAML: primary nodes present"

  # Note: we do NOT check for edgetunnel nodes here — edgetunnel may fail
  # and nanob correctly falls back to primary-only. That's expected behavior.

  if echo "$sub_response" | python3 -c "import sys; d=sys.stdin.buffer.read(); sys.exit(1 if any((b<32 and b not in (9,10,13)) or b==127 for b in d) else 0)" 2>/dev/null; then
    ok "nanob YAML: no invalid control characters"
  else
    err "nanob YAML contains invalid control characters"
    return 1
  fi

  ok "nanob verification passed"
}

# ── Write local env files ───────────────────────────────────────────────────

write_local_env() {
  local deploy_status="${1:-pending}"
  local upload_status="${2:-pending}"
  local verify_status="${3:-pending}"

  log "Saving nanok local secret file..."

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
    return 0
  fi

  printf '%s\n' "$content" > "$LOCAL_ENV_FILE"
  chmod 600 "$LOCAL_ENV_FILE"
  ok "Saved ${LOCAL_ENV_FILE} (mode 600) [deploy=${deploy_status}]"
}

write_nanob_local_env() {
  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    return 0
  fi

  local deploy_status="${1:-pending}"
  local verify_status="${2:-pending}"

  local edge_status="disabled"
  if [[ -n "$EDGE_HOST" ]] && [[ -n "$EDGETUNNEL_EXPORT_TOKEN" ]]; then
    edge_status="enabled"
  elif [[ -n "$EDGE_HOST" ]]; then
    edge_status="host-set-no-token"
  fi

  log "Saving nanob local secret file..."

  local content="# Generated by NanoBK install-cloudflare.sh
# KEEP THIS FILE PRIVATE — never commit to Git.

NANOB_WORKER_NAME=\"${NANOB_WORKER_NAME}\"
NANOB_ROUTE_URL=\"${NANOB_ROUTE_URL}\"
NANOB_TOKEN=\"${NANOB_TOKEN}\"
NANOB_PATH=\"${NANOB_PATH}\"
NANOK_ORIGIN=\"${ROUTE_URL}\"
NANOK_SUB_PATH=\"${SUB_PATH}\"
NANOB_GEO_KV_NAMESPACE_ID=\"${NANOB_GEO_KV_NAMESPACE_ID}\"
EDGE_HOST=\"${EDGE_HOST}\"
EDGE_SUB_PATH=\"${EDGE_SUB_PATH}\"
EDGETUNNEL_STATUS=\"${edge_status}\"
NANOB_DEPLOY_STATUS=\"${deploy_status}\"
NANOB_VERIFY_STATUS=\"${verify_status}\"
"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write ${NANOB_LOCAL_ENV_FILE} (mode 600)"
    return 0
  fi

  printf '%s\n' "$content" > "$NANOB_LOCAL_ENV_FILE"
  chmod 600 "$NANOB_LOCAL_ENV_FILE"
  ok "Saved ${NANOB_LOCAL_ENV_FILE} (mode 600) [deploy=${deploy_status}]"
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

  if [[ "$DEPLOY_NANOB" == "1" ]]; then
    echo ""
    echo "  nanob Worker:"
    echo "    name:  ${NANOB_WORKER_NAME}"
    [[ -n "$NANOB_ROUTE_URL" ]] && echo "    url:   ${NANOB_ROUTE_URL}"
    echo "    edgetunnel: $([ -n "$EDGE_HOST" ] && [ -n "$EDGETUNNEL_EXPORT_TOKEN" ] && echo "enabled (${EDGE_HOST})" || echo "disabled")"
  fi

  echo ""
  if [[ "$DEPLOY_NANOB" == "1" ]] && [[ -n "$NANOB_ROUTE_URL" ]]; then
    echo "  Recommended subscription (nanob aggregator):"
    echo "    ${NANOB_ROUTE_URL}${NANOB_PATH}?token=${NANOB_TOKEN}"
    echo ""
    echo "  Direct subscription (nanok only):"
    [[ -n "$ROUTE_URL" ]] && echo "    ${ROUTE_URL}${SUB_PATH}?token=${SUB_TOKEN}"
  elif [[ -n "$ROUTE_URL" ]]; then
    echo "  Subscription URL (contains SUB_TOKEN — keep private):"
    echo "    ${ROUTE_URL}${SUB_PATH}?token=${SUB_TOKEN}"
  fi

  echo ""
  echo "  Local secret files:"
  echo "    ${LOCAL_ENV_FILE}"
  [[ "$DEPLOY_NANOB" == "1" ]] && echo "    ${NANOB_LOCAL_ENV_FILE}"

  echo ""
  echo "  Next steps:"
  echo "    1. Import subscription URL into Clash/Mihomo."
  echo "    2. On VPS, create admin env for key rotation:"
  echo ""
  echo "       cat > /root/.nanok-cf-admin.env <<'ENVEOF'"
  echo "       ADMIN_TOKEN=\"${ADMIN_TOKEN}\""
  [[ -n "$ROUTE_URL" ]] && echo "       ADMIN_CURRENT_URL=\"${ROUTE_URL}${ADMIN_CURRENT_PATH}\""
  [[ -n "$ROUTE_URL" ]] && echo "       ADMIN_UPDATE_URL=\"${ROUTE_URL}${ADMIN_PATH}\""
  echo "       ENVEOF"
  echo "       chmod 600 /root/.nanok-cf-admin.env"
  echo ""

  if [[ "$DEPLOY_NANOB" != "1" ]]; then
    echo "    3. Optional: deploy nanob aggregator with --deploy-nanob"
  fi

  echo ""
  warn "Keep .cloudflare.local.env and .nanob.local.env private."
  warn "Never commit these files to Git."
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

# ── Preflight check ─────────────────────────────────────────────────────────

preflight_check() {
  log "Running Cloudflare preflight checks..."

  local issues=0

  # Node.js
  if command -v node &>/dev/null; then
    local nver
    nver=$(node --version)
    local nmajor
    nmajor=$(node_major_version)
    if [[ "$nmajor" -ge 22 ]] 2>/dev/null; then
      ok "node: ${nver} (>=22)"
    else
      fail "node: ${nver} (Wrangler 4.95+ requires Node.js >=22)"
      echo "  Install Node.js 22+:"
      echo "    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
      echo "    sudo apt install -y nodejs"
      issues=$((issues + 1))
    fi
  else
    fail "node: not found"
    issues=$((issues + 1))
  fi

  # npm/npx
  if command -v npx &>/dev/null; then
    ok "npx: available"
  elif command -v npm &>/dev/null; then
    ok "npm: available (npx not found)"
  else
    fail "npm/npx: not found"
    issues=$((issues + 1))
  fi

  # Wrangler
  local wrangler_found=0
  if command -v wrangler &>/dev/null; then
    ok "wrangler: $(wrangler --version 2>/dev/null | head -1)"
    wrangler_found=1
  elif command -v npx &>/dev/null; then
    if npx wrangler --version &>/dev/null; then
      ok "wrangler (via npx): $(npx wrangler --version 2>/dev/null | head -1)"
      wrangler_found=1
    fi
  fi
  if [[ "$wrangler_found" == "0" ]]; then
    fail "wrangler: not found"
    issues=$((issues + 1))
  fi

  # Wrangler login (skip in dry-run)
  if [[ "$wrangler_found" == "1" ]] && [[ "$DRY_RUN" != "1" ]]; then
    local wcmd="wrangler"
    command -v wrangler &>/dev/null || wcmd="npx wrangler"
    if $wcmd whoami &>/dev/null; then
      ok "wrangler login: authenticated"
    else
      warn "wrangler login: not authenticated (run: wrangler login)"
      issues=$((issues + 1))
    fi
  fi

  # Worker source files
  if [[ -f "${REPO_DIR}/workers/nanok/src/index.js" ]]; then
    ok "nanok source: ${REPO_DIR}/workers/nanok/src/index.js"
  else
    fail "nanok source: not found"
    issues=$((issues + 1))
  fi

  if [[ -f "${REPO_DIR}/workers/nanob/src/index.js" ]]; then
    ok "nanob source: ${REPO_DIR}/workers/nanob/src/index.js"
  else
    warn "nanob source: not found (nanob deployment will be unavailable)"
  fi

  # Profile file
  if [[ -f "$PROFILE_PATH" ]]; then
    ok "profile: ${PROFILE_PATH}"

    # Validate profile JSON
    if command -v jq &>/dev/null; then
      if jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$PROFILE_PATH" >/dev/null 2>&1; then
        ok "profile JSON: valid (has hy2/tuic/reality/trojan)"
      else
        fail "profile JSON: missing required sections"
        issues=$((issues + 1))
      fi

      # Check for private key leakage
      if jq -e '.reality | has("privateKey")' "$PROFILE_PATH" >/dev/null 2>&1; then
        fail "profile JSON: contains privateKey (SECURITY ISSUE)"
        issues=$((issues + 1))
      else
        ok "profile JSON: no privateKey leakage"
      fi
    fi
  else
    warn "profile: ${PROFILE_PATH} not found (required for upload)"
    issues=$((issues + 1))
  fi

  # Local env files
  if [[ -f "$LOCAL_ENV_FILE" ]]; then
    ok "cloudflare.local.env: exists"
  else
    info "cloudflare.local.env: not yet created (will be generated)"
  fi

  if [[ -f "$NANOB_LOCAL_ENV_FILE" ]]; then
    ok "nanob.local.env: exists"
  else
    info "nanob.local.env: not yet created (will be generated if --deploy-nanob)"
  fi

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    echo -e "  ${GREEN}Cloudflare Preflight: ALL CHECKS PASSED${NC}"
  else
    echo -e "  ${RED}Cloudflare Preflight: ${issues} issue(s) found${NC}"
  fi
  echo ""

  return "$issues"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  # Preflight mode
  if [[ "$PREFLIGHT" == "1" ]]; then
    preflight_check
    return $?
  fi

  # Validate-profile-only mode
  if [[ "$VALIDATE_PROFILE_ONLY" == "1" ]]; then
    validate_profile_file
    return $?
  fi

  echo ""
  local mode_label=""
  [[ "$DRY_RUN" == "1" ]] && mode_label=" — DRY-RUN"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║   NanoBK Cloudflare Installer${mode_label}                "
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  nanok:"
  echo "    name:       ${WORKER_NAME}"
  echo "    route-url:  ${ROUTE_URL:-<not set>}"
  echo "    kv:         ${KV_NAMESPACE_ID:-<will create>}"
  if [[ "$DEPLOY_NANOB" == "1" ]]; then
    echo ""
    echo "  nanob:"
    echo "    name:       ${NANOB_WORKER_NAME}"
    echo "    route-url:  ${NANOB_ROUTE_URL}"
    echo "    geo-kv:     ${NANOB_GEO_KV_NAMESPACE_ID:-<will create>}"
    echo "    edge-host:  ${EDGE_HOST:-<disabled>}"
  fi
  echo ""

  confirm_or_die "Proceed with Cloudflare deployment?"

  # Phase 1: Wrangler
  check_wrangler

  # Phase 2: nanok KV
  create_kv_namespace_generic "$KV_BINDING" CREATE_KV KV_NAMESPACE_ID

  # Phase 3: nanob Geo KV (if deploying nanob)
  if [[ "$DEPLOY_NANOB" == "1" ]]; then
    create_kv_namespace_generic "$NANOB_GEO_KV_BINDING" CREATE_NANOB_GEO_KV NANOB_GEO_KV_NAMESPACE_ID
  fi

  # Phase 4: Tokens
  generate_tokens

  # Phase 5: Save secrets early
  write_local_env "prepared" "pending" "pending"
  write_nanob_local_env "prepared" "pending"

  # Phase 6: Generate wrangler.toml files
  generate_wrangler_toml
  generate_nanob_wrangler_toml

  # Phase 7: Validate profile
  validate_profile_file

  # Phase 8: Set nanok secrets
  set_worker_secrets

  # Phase 9: Deploy nanok
  deploy_nanok
  write_local_env "deployed" "pending" "pending"

  # Phase 10: Upload profile
  upload_profile
  write_local_env "deployed" "uploaded" "pending"

  # Phase 11: Verify nanok
  verify_nanok
  write_local_env "deployed" "uploaded" "verified"

  # Phase 12: Set nanob secrets + deploy
  set_nanob_secrets
  deploy_nanob
  write_nanob_local_env "deployed" "pending"

  # Phase 13: Verify nanob
  verify_nanob
  write_nanob_local_env "deployed" "verified"

  # Phase 14: Next steps
  print_next_steps
}

main "$@"
