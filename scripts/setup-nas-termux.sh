#!/usr/bin/env bash
set -euo pipefail

TERMUX_BOOT_SCRIPT="${HOME}/.termux/boot/start-android-nas"
NAS_ROOT="${HOME}/storage/shared/nas"
SSH_PORT="8022"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ANDROID_CONFIG_DIR="${HOME}/.config/android-nas"
ANDROID_CONFIG_FILE="${ANDROID_CONFIG_DIR}/android.env"

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

require_termux() {
  [[ "${PREFIX:-}" == *"/com.termux/"* ]] || die "This script must run inside Termux."
}

setup_packages() {
  info "Updating Termux packages"
  pkg update -y
  pkg upgrade -y

  info "Installing required packages"
  pkg install -y openssh rsync termux-services rclone termux-api
}

setup_storage() {
  if [[ ! -d "${HOME}/storage/shared" ]]; then
    info "Initializing shared storage access"
    termux-setup-storage
  else
    info "Shared storage access already initialized"
  fi
}

create_nas_tree() {
  info "Creating NAS directories under ${NAS_ROOT}"
  mkdir -p "${NAS_ROOT}"/{projects,experiments,claude,backups,shared}
}

start_sshd() {
  if pgrep -x sshd >/dev/null 2>&1; then
    info "sshd is already running"
  else
    info "Starting sshd"
    sshd
  fi
}

install_commands() {
  info "Installing Android NAS helper commands"
  install -m 700 "${SCRIPT_DIR}/nas-android-usb-sync" "${PREFIX}/bin/nas-android-usb-sync"
  install -m 700 "${SCRIPT_DIR}/nas-android-usb-watch" "${PREFIX}/bin/nas-android-usb-watch"
  install -m 700 "${SCRIPT_DIR}/nas-android-doctor" "${PREFIX}/bin/nas-android-doctor"
}

write_android_config() {
  info "Writing Android NAS config template"
  mkdir -p "$ANDROID_CONFIG_DIR"

  if [[ -f "$ANDROID_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ANDROID_CONFIG_FILE"
  fi

  cat >"$ANDROID_CONFIG_FILE" <<EOF
NAS_ROOT=$(printf '%q' "${NAS_ROOT:-/storage/emulated/0/nas}")
USB_ROOT=$(printf '%q' "${USB_ROOT:-}")
USB_SUBDIR=$(printf '%q' "${USB_SUBDIR:-android-nas}")
ANDROID_NOTIFY_INFO=$(printf '%q' "${ANDROID_NOTIFY_INFO:-1}")
ANDROID_NOTIFY_WARN=$(printf '%q' "${ANDROID_NOTIFY_WARN:-1}")
EOF
}

install_boot_script() {
  info "Installing Termux:Boot startup script"
  mkdir -p "$(dirname "$TERMUX_BOOT_SCRIPT")"

  cat >"$TERMUX_BOOT_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

termux-wake-lock || true
mkdir -p "${HOME}/.local/state/android-nas"
pgrep -x sshd >/dev/null 2>&1 || sshd
pgrep -f "nas-android-usb-watch" >/dev/null 2>&1 || nohup nas-android-usb-watch >"${HOME}/.local/state/android-nas/usb-watch.log" 2>&1 &
EOF

  chmod 700 "$TERMUX_BOOT_SCRIPT"
}

start_usb_watcher() {
  mkdir -p "${HOME}/.local/state/android-nas"

  if pgrep -f "nas-android-usb-watch" >/dev/null 2>&1; then
    info "Android USB watcher is already running"
    return 0
  fi

  info "Starting Android USB watcher"
  nohup nas-android-usb-watch >"${HOME}/.local/state/android-nas/usb-watch.log" 2>&1 &
}

print_summary() {
  local ip_output username
  username="$(whoami)"
  ip_output="$(ip -o -4 addr show wlan0 2>/dev/null || ip -o -4 addr show 2>/dev/null || true)"

  cat <<EOF

Android NAS setup complete.

SSH server
  Status : $(pgrep -x sshd >/dev/null 2>&1 && printf 'running' || printf 'stopped')
  Port   : ${SSH_PORT}
  User   : ${username}

Storage
  NAS root: /storage/emulated/0/nas

Boot
  Script : ${TERMUX_BOOT_SCRIPT}
  Note   : Install Termux:Boot and open it once after install.

USB automation
  Watcher: $(pgrep -f "nas-android-usb-watch" >/dev/null 2>&1 && printf 'running' || printf 'stopped')
  Manual : nas-android-usb-sync push

Suggested next steps
  1. Run 'passwd' if you need password-based SSH login.
  2. Prefer SSH keys for regular access.
  3. Check setup: nas-android-doctor
  4. Disable battery optimization for Termux and Termux:Boot.
  5. Install/open Termux:API app if notification popups are wanted.
  6. Keep Wi-Fi stable and keep the phone on power for long mounts.

Client examples
  ssh -p ${SSH_PORT} ${username}@<PHONE_IP>
  sftp -P ${SSH_PORT} ${username}@<PHONE_IP>

Detected IP addresses
${ip_output:-  Unable to detect a LAN IP automatically. Run: ip a}
EOF
}

main() {
  require_termux
  setup_packages
  setup_storage
  create_nas_tree
  start_sshd
  install_commands
  write_android_config
  install_boot_script
  start_usb_watcher
  print_summary
}

main "$@"
