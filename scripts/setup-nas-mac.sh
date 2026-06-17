#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/android-nas"
STATE_DIR="${HOME}/.local/state/android-nas"
CONFIG_FILE="${CONFIG_DIR}/config.env"
DEFAULT_MOUNT_ROOT="${HOME}/mnt/android-nas"
ENABLE_AGENT="1"

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

  warn "No rclone remote found. Writing config with default remote 'NAS'. Run 'rclone config' before mounting."
  printf 'NAS\n'
}

write_config() {
  local remote="$1"
  local existing_remote existing_remote_fallback existing_base_path existing_workspace existing_mount_root
  local existing_source_policy existing_client_cache_mode existing_usb_subdir existing_usb_root existing_usb_link_path
  local existing_mac_notify_info existing_mac_notify_warn existing_usb_sync_max_age_hours

  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$DEFAULT_MOUNT_ROOT"

  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    existing_remote="${REMOTE:-}"
    existing_remote_fallback="${REMOTE_FALLBACK:-}"
    existing_base_path="${BASE_PATH:-}"
    existing_workspace="${WORKSPACE:-}"
    existing_mount_root="${MOUNT_ROOT:-}"
    existing_source_policy="${SOURCE_POLICY:-}"
    existing_client_cache_mode="${CLIENT_CACHE_MODE:-}"
    existing_usb_subdir="${USB_SUBDIR:-}"
    existing_usb_root="${USB_ROOT:-}"
    existing_usb_link_path="${USB_LINK_PATH:-}"
    existing_mac_notify_info="${MAC_NOTIFY_INFO:-}"
    existing_mac_notify_warn="${MAC_NOTIFY_WARN:-}"
    existing_usb_sync_max_age_hours="${USB_SYNC_MAX_AGE_HOURS:-}"
  fi

  cat >"$CONFIG_FILE" <<EOF
REMOTE=$(printf '%q' "${existing_remote:-$remote}")
REMOTE_FALLBACK=$(printf '%q' "${existing_remote_fallback:-android}")
BASE_PATH=$(printf '%q' "${existing_base_path:-/storage/emulated/0/nas}")
WORKSPACE=$(printf '%q' "${existing_workspace:-projects}")
MOUNT_ROOT=$(printf '%q' "${existing_mount_root:-$DEFAULT_MOUNT_ROOT}")
SOURCE_POLICY=$(printf '%q' "${existing_source_policy:-primary_preferred_secondary_continuity}")
CLIENT_CACHE_MODE=$(printf '%q' "${existing_client_cache_mode:-full}")
USB_SUBDIR=$(printf '%q' "${existing_usb_subdir:-android-nas}")
USB_ROOT=$(printf '%q' "${existing_usb_root:-}")
USB_LINK_PATH=$(printf '%q' "${existing_usb_link_path:-${HOME}/mnt/android-nas-usb}")
MAC_NOTIFY_INFO=$(printf '%q' "${existing_mac_notify_info:-0}")
MAC_NOTIFY_WARN=$(printf '%q' "${existing_mac_notify_warn:-1}")
USB_SYNC_MAX_AGE_HOURS=$(printf '%q' "${existing_usb_sync_max_age_hours:-168}")
EOF
}

install_commands() {
  mkdir -p "$INSTALL_BIN_DIR"

  chmod 700 \
    "${REPO_ROOT}/scripts/nas-mount" \
    "${REPO_ROOT}/scripts/nas-unmount" \
    "${REPO_ROOT}/scripts/nas-switch" \
    "${REPO_ROOT}/scripts/nas-status" \
    "${REPO_ROOT}/scripts/nas-usb-mount" \
    "${REPO_ROOT}/scripts/nas-usb-attach" \
    "${REPO_ROOT}/scripts/nas-mobile-usb-sync" \
    "${REPO_ROOT}/scripts/nas-mac-usb-watch" \
    "${REPO_ROOT}/scripts/nas-mac-install-agent" \
    "${REPO_ROOT}/scripts/nas-doctor"

  ln -sfn "${REPO_ROOT}/scripts/nas-mount" "${INSTALL_BIN_DIR}/nas-mount"
  ln -sfn "${REPO_ROOT}/scripts/nas-unmount" "${INSTALL_BIN_DIR}/nas-unmount"
  ln -sfn "${REPO_ROOT}/scripts/nas-switch" "${INSTALL_BIN_DIR}/nas-switch"
  ln -sfn "${REPO_ROOT}/scripts/nas-status" "${INSTALL_BIN_DIR}/nas-status"
  ln -sfn "${REPO_ROOT}/scripts/nas-usb-mount" "${INSTALL_BIN_DIR}/nas-usb-mount"
  ln -sfn "${REPO_ROOT}/scripts/nas-usb-attach" "${INSTALL_BIN_DIR}/nas-usb-attach"
  ln -sfn "${REPO_ROOT}/scripts/nas-mobile-usb-sync" "${INSTALL_BIN_DIR}/nas-mobile-usb-sync"
  ln -sfn "${REPO_ROOT}/scripts/nas-mac-usb-watch" "${INSTALL_BIN_DIR}/nas-mac-usb-watch"
  ln -sfn "${REPO_ROOT}/scripts/nas-mac-install-agent" "${INSTALL_BIN_DIR}/nas-mac-install-agent"
  ln -sfn "${REPO_ROOT}/scripts/nas-doctor" "${INSTALL_BIN_DIR}/nas-doctor"
}

ensure_shell_path() {
  local shell_rc="${HOME}/.zshrc"
  local marker="# android-nas PATH"

  if [[ ":${PATH}:" == *":${INSTALL_BIN_DIR}:"* ]]; then
    return 0
  fi

  if [[ ! -f "$shell_rc" ]] || ! grep -Fqx "$marker" "$shell_rc"; then
    {
      printf '\n%s\n' "$marker"
      printf 'export PATH="$HOME/.local/bin:$PATH"\n'
    } >>"$shell_rc"
  fi

  warn "${INSTALL_BIN_DIR} was added to ${shell_rc}. Open a new terminal or run: export PATH=\"${INSTALL_BIN_DIR}:\$PATH\""
}

install_agent_if_requested() {
  if [[ "$ENABLE_AGENT" != "1" ]]; then
    return 0
  fi

  "${REPO_ROOT}/scripts/nas-mac-install-agent" || warn "USB watcher LaunchAgent could not be started. Run 'nas-mac-install-agent' later."
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --no-agent)
        ENABLE_AGENT="0"
        ;;
      --help|-h)
        cat <<'EOF'
Usage: setup-nas-mac.sh [--no-agent]

Installs macOS client commands, writes config, adds ~/.local/bin to zsh PATH,
and enables the USB watcher LaunchAgent by default.

Set CLIENT_CACHE_MODE=spaceless in ~/.config/android-nas/config.env after setup
to minimize local mount cache usage on the client.
EOF
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
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
USB watcher : $([[ "$ENABLE_AGENT" == "1" ]] && printf 'enabled' || printf 'not enabled')

Next steps
  1. Configure the rclone SFTP remote if needed: rclone config
  2. Confirm the phone is reachable: ssh -p 8022 <termux-user>@<phone-ip>
  3. Check setup: nas-doctor
  4. Mount mobile workspace: nas-mount
  5. Attach USB secondary manually if needed: nas-usb-attach
EOF
}

main() {
  parse_args "$@"
  require_macos
  require_command bash
  require_command rclone

  local remote
  remote="$(detect_remote)"

  info "Writing client configuration"
  write_config "$remote"

  info "Installing helper commands"
  install_commands

  info "Ensuring shell PATH"
  ensure_shell_path

  info "Configuring USB watcher"
  install_agent_if_requested

  print_summary "$remote"
}

main "$@"
