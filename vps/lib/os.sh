#!/usr/bin/env bash
# NanoBK Proxy Suite — OS detection and dependency management
# Source this file; do not execute directly.

# Requires: vps/lib/common.sh (for log, ok, warn, die, run_cmd, NANOBK_DRY_RUN)

# ── OS Detection ────────────────────────────────────────────────────────────

# Globals set by detect_os():
#   OS_ID        — debian, ubuntu, rocky, alma, centos, fedora, rhel, ...
#   OS_VERSION   — version string (e.g., "12", "22.04", "9")
#   OS_PRETTY    — pretty name from os-release
#   ARCH         — x86_64, aarch64
#   PKG_MANAGER  — apt, dnf, yum
#   IS_DEBIAN_LIKE — 1 if Debian/Ubuntu, 0 otherwise

detect_os() {
  log "Detecting operating system..."

  if [[ ! -f /etc/os-release ]]; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      warn "Cannot detect OS: /etc/os-release not found (OK in dry-run on macOS)"
      OS_ID="debian"
      OS_VERSION="12"
      OS_PRETTY="Dry-run placeholder (Debian 12)"
      ARCH="$(uname -m)"
      [[ "$ARCH" == "arm64" ]] && ARCH="aarch64"
      PKG_MANAGER="apt"
      IS_DEBIAN_LIKE=1
      return 0
    fi
    die "Cannot detect OS: /etc/os-release not found. This installer requires a Linux VPS."
  fi

  # shellcheck source=/dev/null
  source /etc/os-release

  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION}"

  # Architecture
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    arm64)   ARCH="aarch64" ;;
    *)       die "Unsupported architecture: ${machine}. Supported: x86_64, aarch64" ;;
  esac

  # Package manager
  case "$OS_ID" in
    debian|ubuntu|linuxmint|pop)
      PKG_MANAGER="apt"
      IS_DEBIAN_LIKE=1
      ;;
    rocky|almalinux|centos|rhel|fedora|ol|amzn)
      if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
      elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
      else
        die "Neither dnf nor yum found on ${OS_ID}"
      fi
      IS_DEBIAN_LIKE=0
      ;;
    *)
      warn "Unknown OS ID: ${OS_ID}. Will attempt Debian-like behavior."
      PKG_MANAGER="apt"
      IS_DEBIAN_LIKE=1
      ;;
  esac

  ok "OS: ${OS_PRETTY} (${ARCH})"
  ok "Package manager: ${PKG_MANAGER}"
}

# ── Root check ──────────────────────────────────────────────────────────────

ensure_root_or_dry_run() {
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    if [[ $EUID -ne 0 ]]; then
      warn "Not running as root (OK in dry-run mode)"
    fi
    return 0
  fi

  if [[ $EUID -ne 0 ]]; then
    die "This installer must be run as root. Use: sudo bash $0"
  fi
  ok "Running as root"
}

# ── Systemd check ──────────────────────────────────────────────────────────

ensure_systemd() {
  if ! command -v systemctl &>/dev/null; then
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      warn "systemctl not found (OK in dry-run on macOS)"
      return 0
    fi
    die "systemctl not found. This installer requires systemd."
  fi
  ok "systemd detected"
}

# ── Dependency installation ────────────────────────────────────────────────

# Map of required packages per distro family.
# Some packages have different names across distros.

install_dependencies() {
  log "Installing system dependencies..."

  local packages=()

  if [[ "$IS_DEBIAN_LIKE" == "1" ]]; then
    packages=(
      curl
      jq
      python3
      openssl
      tar
      unzip
      gzip
      ca-certificates
      iproute2
      uuid-runtime
    )

    run_cmd "apt-get update" apt-get update -y

    local to_install=()
    for pkg in "${packages[@]}"; do
      if ! dpkg -s "$pkg" &>/dev/null; then
        to_install+=("$pkg")
      fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
      run_cmd "Install: ${to_install[*]}" apt-get install -y "${to_install[@]}"
    else
      ok "All required packages already installed"
    fi

  else
    # RHEL family
    packages=(
      curl
      jq
      python3
      openssl
      tar
      unzip
      gzip
      ca-certificates
      iproute
      util-linux
    )

    local to_install=()
    for pkg in "${packages[@]}"; do
      local rpm_name
      case "$pkg" in
        iproute) rpm_name="iproute" ;;
        util-linux) rpm_name="util-linux" ;;  # provides uuidgen
        *) rpm_name="$pkg" ;;
      esac
      if ! rpm -q "$rpm_name" &>/dev/null 2>&1; then
        to_install+=("$pkg")
      fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
      run_cmd "Install: ${to_install[*]}" "$PKG_MANAGER" install -y "${to_install[@]}"
    else
      ok "All required packages already installed"
    fi
  fi

  # Verify critical commands (skip in dry-run since we didn't actually install)
  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    for cmd in curl jq python3 openssl; do
      if ! command -v "$cmd" &>/dev/null; then
        die "Failed to install ${cmd}"
      fi
    done
  fi

  ok "Dependencies verified"
}

# ── UUID generation (cross-platform) ────────────────────────────────────────

generate_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen
  else
    python3 -c "import uuid; print(uuid.uuid4())"
  fi
}
