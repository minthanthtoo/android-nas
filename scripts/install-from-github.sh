#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${ANDROID_NAS_REPO_SLUG:-minthanthtoo/android-nas}"
REPO_REF="${ANDROID_NAS_REPO_REF:-main}"
INSTALL_BASE="${HOME}/.local/share/android-nas"
INSTALL_ROOT="${INSTALL_BASE}/repo"
TARBALL_URL="https://codeload.github.com/${REPO_SLUG}/tar.gz/${REPO_REF}"

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

detect_platform() {
  if [[ "${PREFIX:-}" == *"/com.termux/"* ]]; then
    printf 'termux\n'
    return 0
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    printf 'macos\n'
    return 0
  fi

  die "Unsupported platform. This bootstrap currently supports macOS and Termux."
}

download_repo() {
  local tmp_dir extract_root

  require_command curl
  require_command tar

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  mkdir -p "$INSTALL_BASE"

  info "Downloading ${REPO_SLUG}@${REPO_REF}"
  curl -fsSL "$TARBALL_URL" -o "${tmp_dir}/repo.tar.gz"

  info "Extracting repository"
  tar -xzf "${tmp_dir}/repo.tar.gz" -C "$tmp_dir"

  extract_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$extract_root" ]] || die "Failed to locate extracted repository contents."

  rm -rf "$INSTALL_ROOT"
  mkdir -p "$(dirname "$INSTALL_ROOT")"
  mv "$extract_root" "$INSTALL_ROOT"
}

run_platform_setup() {
  local platform="$1"
  local script_path

  case "$platform" in
    macos)
      script_path="${INSTALL_ROOT}/scripts/setup-nas-mac.sh"
      ;;
    termux)
      script_path="${INSTALL_ROOT}/scripts/setup-nas-termux.sh"
      ;;
    *)
      die "Unsupported platform dispatch: ${platform}"
      ;;
  esac

  [[ -f "$script_path" ]] || die "Missing setup script: $script_path"

  info "Running ${script_path}"
  bash "$script_path" "${@:2}"
}

print_summary() {
  local platform="$1"

  cat <<EOF

GitHub bootstrap complete.

Installed repo : ${INSTALL_ROOT}
Platform       : ${platform}

Next steps
EOF

  if [[ "$platform" == "macos" ]]; then
    cat <<'EOF'
  1. Open a new shell or run: export PATH="$HOME/.local/bin:$PATH"
  2. Verify setup: nas-doctor
EOF
  else
    cat <<'EOF'
  1. Verify setup: nas-android-doctor
  2. Install/open Termux:Boot and Termux:API if not already present
EOF
  fi
}

main() {
  local platform

  platform="$(detect_platform)"
  download_repo
  run_platform_setup "$platform" "$@"
  print_summary "$platform"
}

main "$@"
