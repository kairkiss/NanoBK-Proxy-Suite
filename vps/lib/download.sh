#!/usr/bin/env bash
# NanoBK Proxy Suite — Binary download library
# Downloads xray, hysteria, tuic-server from GitHub releases.
# Source this file; do not execute directly.

# Requires: vps/lib/common.sh

# ── GitHub latest release asset downloader ──────────────────────────────────

# Download the latest release asset matching a pattern from a GitHub repo.
#
# Usage: download_latest_asset OWNER REPO PATTERN OUTPUT_PATH
#   OWNER    — GitHub org/user
#   REPO     — GitHub repo name
#   PATTERN  — grep -iE pattern to match asset filename
#   OUTPUT   — where to save the downloaded file
#
# Respects NANOBK_<REPO_UPPER>_DOWNLOAD_URL override env var.
#
# Returns 0 on success, 1 on failure.

download_latest_asset() {
  local owner="$1"
  local repo="$2"
  local pattern="$3"
  local output="$4"

  # Check for override env var
  local override_var="NANOBK_$(echo "$repo" | tr '[:lower:]-' '[:upper:]_')_DOWNLOAD_URL"
  local override_url="${!override_var:-}"

  if [[ -n "$override_url" ]]; then
    log "Using override URL for ${repo}: ${override_url}"
    if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} curl -fsSL -o ${output} ${override_url}"
      return 0
    fi
    curl -fsSL -o "$output" "$override_url"
    return $?
  fi

  # In dry-run, skip actual API calls
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} download latest ${owner}/${repo} asset matching '${pattern}'"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   would query: https://api.github.com/repos/${owner}/${repo}/releases/latest"
    echo -e "  ${CYAN}[DRY-RUN]${NC}   would save to: ${output}"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    err "jq is required for GitHub API parsing. Install jq or set ${override_var}."
    return 1
  fi

  log "Fetching latest release for ${owner}/${repo}..."

  local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"

  local release_json
  release_json=$(curl -fsSL -H "Accept: application/json" "$api_url" 2>/dev/null) || {
    err "Failed to query GitHub API for ${owner}/${repo}"
    err "Set ${override_var} to download manually."
    return 1
  }

  local asset_url
  asset_url=$(echo "$release_json" | jq -r --arg pat "$pattern" '
    .assets[]?
    | select(.name | test($pat; "i"))
    | .browser_download_url
  ' | head -1)

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    err "No asset matching '${pattern}' found in ${owner}/${repo} latest release."
    err "Available assets:"
    echo "$release_json" | jq -r '.assets[]?.name' | sed 's/^/    /' >&2
    err "Set ${override_var} to download manually."
    return 1
  fi

  log "Downloading: ${asset_url}"
  curl -fsSL -o "$output" "$asset_url"
}

# ── Helper: install a downloaded binary ─────────────────────────────────────

install_binary() {
  local src="$1"
  local dest="$2"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} install ${src} → ${dest}"
    echo -e "  ${CYAN}[DRY-RUN]${NC} chmod +x ${dest}"
    return 0
  fi

  mv "$src" "$dest"
  chmod +x "$dest"
}

# ── Helper: check if file is an archive ─────────────────────────────────────

is_archive() {
  local file="$1"
  local mime
  mime=$(file -b --mime-type "$file" 2>/dev/null || echo "")
  case "$mime" in
    application/zip|application/gzip|application/x-tar|application/x-gzip)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# ── Xray installation ──────────────────────────────────────────────────────

install_xray() {
  local bin="/usr/local/bin/xray"

  if command -v xray &>/dev/null; then
    ok "xray already installed: $(command -v xray)"
    return 0
  fi

  if [[ -f "$bin" ]] && [[ -x "$bin" ]]; then
    ok "xray already installed at ${bin}"
    return 0
  fi

  log "Installing xray-core..."

  local os_name
  if [[ "$ARCH" == "aarch64" ]]; then
    os_name="linux-arm64"
  else
    os_name="linux-64"
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" RETURN

  local zip_file="${tmp_dir}/xray.zip"

  download_latest_asset "XTLS" "Xray-core" "Xray-${os_name}\.zip$" "$zip_file" || {
    err "Failed to download xray."
    err "Set NANOBK_XRAY_CORE_DOWNLOAD_URL to a direct .zip URL."
    return 1
  }

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} unzip xray to ${bin}"
    echo -e "  ${CYAN}[DRY-RUN]${NC} chmod +x ${bin}"
    return 0
  fi

  unzip -o -j "$zip_file" "xray" -d /usr/local/bin/ >/dev/null 2>&1 || {
    unzip -o -j "$zip_file" "xray-linux-*" -d /tmp/xray-extract/ >/dev/null 2>&1
    mv /tmp/xray-extract/xray* "$bin" 2>/dev/null || {
      err "Failed to extract xray binary from zip"
      return 1
    }
  }

  chmod +x "$bin"
  ok "xray installed: ${bin}"
}

# ── Hysteria2 installation ─────────────────────────────────────────────────

install_hysteria() {
  local bin="/usr/local/bin/hysteria"

  if command -v hysteria &>/dev/null; then
    ok "hysteria already installed: $(command -v hysteria)"
    return 0
  fi

  if [[ -f "$bin" ]] && [[ -x "$bin" ]]; then
    ok "hysteria already installed at ${bin}"
    return 0
  fi

  log "Installing hysteria2..."

  # Pattern for bare binary: hysteria-linux-amd64 or hysteria-linux-arm64
  # Exclude: hashes.txt, windows, darwin, android, freebsd, .sha256
  local arch_pattern
  if [[ "$ARCH" == "aarch64" ]]; then
    arch_pattern="arm64"
  else
    arch_pattern="amd64"
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" RETURN

  # Try bare binary first (most common in recent releases)
  local downloaded=0
  local asset_pattern="hysteria-linux-${arch_pattern}$"
  local output_file="${tmp_dir}/hysteria"

  if download_latest_asset "apernet" "hysteria" "$asset_pattern" "$output_file" 2>/dev/null; then
    downloaded=1
  fi

  # Fallback: try tar.gz
  if [[ "$downloaded" == "0" ]]; then
    local tar_file="${tmp_dir}/hysteria.tar.gz"
    if download_latest_asset "apernet" "hysteria" "hysteria-linux-${arch_pattern}.*\.tar\.gz$" "$tar_file" 2>/dev/null; then
      if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
        tar -xzf "$tar_file" -C "$tmp_dir" 2>/dev/null
        local found
        found=$(find "$tmp_dir" -name 'hysteria*' -type f -executable 2>/dev/null | head -1)
        if [[ -z "$found" ]]; then
          found=$(find "$tmp_dir" -name 'hysteria*' -type f | head -1)
        fi
        [[ -n "$found" ]] && mv "$found" "$output_file"
      fi
      downloaded=1
    fi
  fi

  if [[ "$downloaded" == "0" ]]; then
    err "Failed to download hysteria2."
    err "Set NANOBK_HYSTERIA_DOWNLOAD_URL to a direct binary URL."
    return 1
  fi

  install_binary "$output_file" "$bin"

  # Best-effort version check
  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    "$bin" version 2>/dev/null || "$bin" --version 2>/dev/null || true
  fi

  ok "hysteria installed: ${bin}"
}

# ── tuic-server installation ───────────────────────────────────────────────

install_tuic() {
  local bin="/usr/local/bin/tuic-server"

  if command -v tuic-server &>/dev/null; then
    ok "tuic-server already installed: $(command -v tuic-server)"
    return 0
  fi

  if [[ -f "$bin" ]] && [[ -x "$bin" ]]; then
    ok "tuic-server already installed at ${bin}"
    return 0
  fi

  log "Installing tuic-server..."

  # Pattern for bare binary: tuic-server-*-x86_64-unknown-linux-gnu
  local arch_pattern
  if [[ "$ARCH" == "aarch64" ]]; then
    arch_pattern="aarch64-unknown-linux-gnu"
  else
    arch_pattern="x86_64-unknown-linux-gnu"
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" RETURN

  # Try bare binary first (most common in recent releases)
  local downloaded=0
  local asset_pattern="tuic-server.*${arch_pattern}$"
  local output_file="${tmp_dir}/tuic-server"

  if download_latest_asset "EAimTY" "tuic" "$asset_pattern" "$output_file" 2>/dev/null; then
    downloaded=1
  fi

  # Fallback: try zip
  if [[ "$downloaded" == "0" ]]; then
    local zip_file="${tmp_dir}/tuic.zip"
    if download_latest_asset "EAimTY" "tuic" "${arch_pattern}\.zip$|tuic-server.*${arch_pattern}.*\.zip$" "$zip_file" 2>/dev/null; then
      if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
        unzip -o "$zip_file" -d "$tmp_dir" >/dev/null 2>&1
        local found
        found=$(find "$tmp_dir" -name 'tuic-server*' -type f | head -1)
        [[ -n "$found" ]] && mv "$found" "$output_file"
      fi
      downloaded=1
    fi
  fi

  if [[ "$downloaded" == "0" ]]; then
    err "Failed to download tuic-server."
    err "Set NANOBK_TUIC_DOWNLOAD_URL to a direct binary URL."
    return 1
  fi

  install_binary "$output_file" "$bin"

  # Best-effort version check
  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    "$bin" --version 2>/dev/null || "$bin" version 2>/dev/null || true
  fi

  ok "tuic-server installed: ${bin}"
}

# ── Install all binaries ───────────────────────────────────────────────────

install_all_binaries() {
  log "Checking and installing proxy binaries..."

  install_xray || die "xray installation failed"
  install_hysteria || die "hysteria installation failed"
  install_tuic || die "tuic-server installation failed"

  ok "All proxy binaries ready"
}
