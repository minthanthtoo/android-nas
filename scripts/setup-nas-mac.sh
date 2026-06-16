#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/android-nas"
STATE_DIR="${HOME}/.local/state/android-nas"
CONFIG_FILE="${CONFIG_DIR}/config.env"
DEFAULT_MOUNT_ROOT="${HOME}/mnt/android-nas"

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

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer currently targets macOS."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

detect_remote() {
  if rclone listremotes | grep -qx 'NAS:'; then
    printf 'NAS\n'
    return 0
  fi

  if rclone listremotes | grep -qx 'android:'; then
    warn "Remote 'NAS' was not found. Falling back to 'android'."
    printf 'android\n'
    return 0
  fi

  die "No rclone remote found. Expected 'NAS' or 'android'. Run: rclone config"
}

write_config() {
  local remote="$1"

  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$DEFAULT_MOUNT_ROOT"

  cat >"$CONFIG_FILE" <<EOF
REMOTE=$(printf '%q' "$remote")
REMOTE_FALLBACK=android
BASE_PATH=/storage/emulated/0/nas
WORKSPACE=projects
MOUNT_ROOT=$(printf '%q' "$DEFAULT_MOUNT_ROOT")
EOF
}

install_commands() {
  mkdir -p "$INSTALL_BIN_DIR"

  ln -sfn "${REPO_ROOT}/scripts/nas-mount" "${INSTALL_BIN_DIR}/nas-mount"
  ln -sfn "${REPO_ROOT}/scripts/nas-unmount" "${INSTALL_BIN_DIR}/nas-unmount"
  ln -sfn "${REPO_ROOT}/scripts/nas-switch" "${INSTALL_BIN_DIR}/nas-switch"
  ln -sfn "${REPO_ROOT}/scripts/nas-status" "${INSTALL_BIN_DIR}/nas-status"
}

print_summary() {
  local remote="$1"

  cat <<EOF

macOS NAS setup complete.

Repository  : ${REPO_ROOT}
Config      : ${CONFIG_FILE}
State       : ${STATE_DIR}
Remote      : ${remote}
Mount root  : ${DEFAULT_MOUNT_ROOT}
Commands    : ${INSTALL_BIN_DIR}/nas-mount

Next steps
  1. Ensure ${INSTALL_BIN_DIR} is on your PATH.
  2. Confirm the phone is reachable with: ssh -p 8022 <termux-user>@<phone-ip>
  3. Mount the default workspace with: nas-mount
  4. Check health with: nas-status
EOF
}

main() {
  require_macos
  require_command bash
  require_command rclone

  local remote
  remote="$(detect_remote)"

  info "Writing client configuration"
  write_config "$remote"

  info "Installing helper commands"
  install_commands

  print_summary "$remote"
}

main "$@"
