#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    log_error "Need root privileges for this step, but sudo is not available."
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed."
  else
    log_warn "Docker not found. Installing with get.docker.com..."
    curl -fsSL https://get.docker.com | run_as_root bash -s docker
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl enable --now docker >/dev/null 2>&1 || true
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker installation failed."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose plugin is not available."
    exit 1
  fi
}

download_file() {
  local rel_path="$1"
  local dest="$INSTALL_DIR/$rel_path"
  local url="$REPO_RAW_BASE/$rel_path"
  mkdir -p "$(dirname "$dest")"
  log_info "Downloading $rel_path"
  curl -fsSL "$url" -o "$dest"
}

download_file_optional() {
  local rel_path="$1"
  local dest="$INSTALL_DIR/$rel_path"
  local url="$REPO_RAW_BASE/$rel_path"
  mkdir -p "$(dirname "$dest")"
  log_info "Downloading (optional) $rel_path"
  if ! curl -fsSL "$url" -o "$dest"; then
    log_warn "Optional file unavailable: $rel_path"
    return 1
  fi
  return 0
}

DEFAULT_INSTALL_DIR="$HOME/supabase-tiny"
if [ "$(id -u)" -eq 0 ]; then
  DEFAULT_INSTALL_DIR="/root/supabase-tiny"
fi

INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/Gouryella/supabase-tiny/main}"

USER_SELECTED_PROFILE=false
for arg in "$@"; do
  case "$arg" in
    --tiny|--standard)
      USER_SELECTED_PROFILE=true
      ;;
  esac
done

FALLBACK_DEPLOY_ARGS=()

require_cmd bash
require_cmd curl

log_info "Install directory: $INSTALL_DIR"
log_info "Asset source: $REPO_RAW_BASE"

ensure_docker

mkdir -p "$INSTALL_DIR/config"

download_file "deploy.sh"
download_file "docker-compose.yml"
if ! download_file_optional "docker-compose.tiny.yml"; then
  if [ "$USER_SELECTED_PROFILE" = false ]; then
    log_warn "Tiny compose is missing; falling back to standard profile."
    FALLBACK_DEPLOY_ARGS=("--standard")
  fi
fi
download_file "config/kong.yml.template"
download_file "Caddyfile"

chmod +x "$INSTALL_DIR/deploy.sh"

log_info "Bootstrap files are ready."
log_info "Starting deployment..."

cd "$INSTALL_DIR"
exec bash "$INSTALL_DIR/deploy.sh" "${FALLBACK_DEPLOY_ARGS[@]}" "$@"
