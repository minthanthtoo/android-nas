#!/usr/bin/env bash
set -euo pipefail

TERMUX_BOOT_SCRIPT="${HOME}/.termux/boot/start-android-nas"
NAS_ROOT="${HOME}/storage/shared/nas"
SSH_PORT="8022"

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
  pkg install -y openssh rsync termux-services
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

install_boot_script() {
  info "Installing Termux:Boot startup script"
  mkdir -p "$(dirname "$TERMUX_BOOT_SCRIPT")"

  cat >"$TERMUX_BOOT_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

termux-wake-lock || true
pgrep -x sshd >/dev/null 2>&1 || sshd
EOF

  chmod 700 "$TERMUX_BOOT_SCRIPT"
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

Suggested next steps
  1. Run 'passwd' if you need password-based SSH login.
  2. Prefer SSH keys for regular access.
  3. Disable battery optimization for Termux and Termux:Boot.
  4. Keep Wi-Fi stable and keep the phone on power for long mounts.

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
  install_boot_script
  print_summary
}

main "$@"
