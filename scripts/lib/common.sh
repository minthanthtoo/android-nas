#!/usr/bin/env bash
set -euo pipefail

APP_NAME="android-nas"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.env"
PID_FILE="${STATE_DIR}/rclone.pid"
LOG_FILE="${STATE_DIR}/rclone.log"

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

die() {
  error "$*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ensure_state_dirs() {
  mkdir -p "$CONFIG_DIR" "$STATE_DIR"
}

load_config() {
  ensure_state_dirs
  [[ -f "$CONFIG_FILE" ]] || die "Missing config: $CONFIG_FILE. Run scripts/setup-nas-mac.sh first."

  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  : "${REMOTE:=}"
  : "${REMOTE_FALLBACK:=android}"
  : "${BASE_PATH:=/storage/emulated/0/nas}"
  : "${WORKSPACE:=projects}"
  : "${MOUNT_ROOT:=$HOME/mnt/android-nas}"
}

shell_quote() {
  printf '%q' "$1"
}

set_config_value() {
  local key="$1"
  local value="$2"
  local quoted tmp

  printf -v quoted '%q' "$value"
  tmp="$(mktemp)"

  awk -v k="$key" -v q="$quoted" '
    BEGIN { updated = 0 }
    index($0, k "=") == 1 { print k "=" q; updated = 1; next }
    { print }
    END { if (updated == 0) print k "=" q }
  ' "$CONFIG_FILE" >"$tmp"

  mv "$tmp" "$CONFIG_FILE"
}

list_rclone_remotes() {
  rclone listremotes 2>/dev/null || true
}

detect_remote() {
  require_command rclone

  if [[ -n "${REMOTE}" ]] && list_rclone_remotes | grep -qx "${REMOTE}:"; then
    printf '%s\n' "$REMOTE"
    return 0
  fi

  if list_rclone_remotes | grep -qx 'NAS:'; then
    printf 'NAS\n'
    return 0
  fi

  if [[ -n "${REMOTE_FALLBACK}" ]] && list_rclone_remotes | grep -qx "${REMOTE_FALLBACK}:"; then
    printf '%s\n' "$REMOTE_FALLBACK"
    return 0
  fi

  die "No rclone remote found. Expected 'NAS' or '${REMOTE_FALLBACK}'. Run: rclone config"
}

remote_base_path() {
  printf '%s:%s\n' "$1" "${BASE_PATH%/}"
}

remote_workspace_path() {
  printf '%s:%s/%s\n' "$1" "${BASE_PATH%/}" "$WORKSPACE"
}

local_mount_path() {
  printf '%s/%s\n' "${MOUNT_ROOT%/}" "$WORKSPACE"
}

pid_is_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

read_pid() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE"
}

clear_pid() {
  rm -f "$PID_FILE"
}

write_pid() {
  printf '%s\n' "$1" >"$PID_FILE"
}

is_mounted() {
  local mount_path="$1"
  mount | grep -F "on ${mount_path} (" >/dev/null 2>&1 || mount | grep -F " ${mount_path} " >/dev/null 2>&1
}

remote_root_reachable() {
  local remote="$1"
  rclone lsf "$(remote_base_path "$remote")" >/dev/null 2>&1
}

ensure_remote_root_reachable() {
  local remote="$1"
  remote_root_reachable "$remote" || die "Remote NAS root is not reachable: $(remote_base_path "$remote")"
}

ensure_remote_workspace_exists() {
  local remote="$1"
  rclone mkdir "$(remote_workspace_path "$remote")" >/dev/null
}

unmount_path() {
  local mount_path="$1"

  if ! is_mounted "$mount_path"; then
    return 0
  fi

  if command -v diskutil >/dev/null 2>&1; then
    diskutil unmount force "$mount_path" >/dev/null 2>&1 || true
  fi

  if is_mounted "$mount_path" && command -v umount >/dev/null 2>&1; then
    umount "$mount_path" >/dev/null 2>&1 || true
  fi

  if is_mounted "$mount_path" && command -v fusermount >/dev/null 2>&1; then
    fusermount -u "$mount_path" >/dev/null 2>&1 || true
  fi
}

print_effective_config() {
  cat <<EOF
App        : ${APP_NAME}
Config     : ${CONFIG_FILE}
State      : ${STATE_DIR}
Remote     : ${REMOTE}
Fallback   : ${REMOTE_FALLBACK}
Base path  : ${BASE_PATH}
Workspace  : ${WORKSPACE}
Mount root : ${MOUNT_ROOT}
Mount path : $(local_mount_path)
Log file   : ${LOG_FILE}
EOF
}
