#!/usr/bin/env bash
set -euo pipefail

APP_NAME="android-nas"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.env"
PID_FILE="${STATE_DIR}/rclone.pid"
LOG_FILE="${STATE_DIR}/rclone.log"
USB_LINK_PATH="${HOME}/mnt/android-nas-usb"
AVAILABILITY_STATE_FILE="${STATE_DIR}/availability.env"

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
  : "${SOURCE_POLICY:=primary_preferred_secondary_continuity}"
  : "${CLIENT_CACHE_MODE:=full}"
  : "${USB_ROOT:=}"
  : "${USB_SUBDIR:=android-nas}"
  : "${USB_LINK_PATH:=$HOME/mnt/android-nas-usb}"
  : "${MAC_NOTIFY_INFO:=0}"
  : "${MAC_NOTIFY_WARN:=1}"
  : "${USB_SYNC_MAX_AGE_HOURS:=168}"
  : "${RCLONE_PROBE_CONNECT_TIMEOUT:=5s}"
  : "${RCLONE_PROBE_IO_TIMEOUT:=8s}"
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

remote_all_path() {
  printf '%s:%s\n' "$1" "${BASE_PATH%/}"
}

local_mount_path() {
  printf '%s/%s\n' "${MOUNT_ROOT%/}" "$WORKSPACE"
}

usb_candidates_macos() {
  if [[ -n "${USB_ROOT:-}" ]]; then
    printf '%s\n' "$USB_ROOT"
    return 0
  fi

  find /Volumes -maxdepth 2 -type d -name "$USB_SUBDIR" 2>/dev/null | sort
}

detect_usb_root_macos() {
  local candidate
  while IFS= read -r candidate; do
    [[ -d "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(usb_candidates_macos)

  return 1
}

usb_path() {
  local root="$1"
  printf '%s/%s\n' "${root%/}" "$WORKSPACE"
}

usb_manifest_dir() {
  local root="$1"
  printf '%s/.android-nas\n' "${root%/}"
}

usb_primary_sync_manifest() {
  local root="$1"
  printf '%s/primary-sync.env\n' "$(usb_manifest_dir "$root")"
}

usb_access_manifest() {
  local root="$1"
  printf '%s/secondary-access.env\n' "$(usb_manifest_dir "$root")"
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_now() {
  date +%s
}

write_usb_primary_sync_manifest() {
  local root="$1"
  local source_name="$2"
  local source_path="$3"
  local scope="$4"
  local manifest_path

  manifest_path="$(usb_primary_sync_manifest "$root")"
  mkdir -p "$(dirname "$manifest_path")"

  cat >"$manifest_path" <<EOF
LAST_PRIMARY_SYNC_STATUS=complete
LAST_PRIMARY_SYNC_EPOCH=$(epoch_now)
LAST_PRIMARY_SYNC_UTC=$(utc_now)
LAST_PRIMARY_SYNC_BY=$(printf '%q' "$(whoami)@$(hostname)")
LAST_PRIMARY_SYNC_SOURCE=$(printf '%q' "$source_name")
LAST_PRIMARY_SYNC_SOURCE_PATH=$(printf '%q' "$source_path")
LAST_PRIMARY_SYNC_SCOPE=$(printf '%q' "$scope")
USB_ROOT=$(printf '%q' "$root")
EOF
}

write_usb_access_manifest() {
  local root="$1"
  local manifest_path

  manifest_path="$(usb_access_manifest "$root")"
  mkdir -p "$(dirname "$manifest_path")"

  cat >"$manifest_path" <<EOF
LAST_SECONDARY_ACCESS_EPOCH=$(epoch_now)
LAST_SECONDARY_ACCESS_UTC=$(utc_now)
LAST_SECONDARY_ACCESS_BY=$(printf '%q' "$(whoami)@$(hostname)")
USB_ROOT=$(printf '%q' "$root")
EOF
}

usb_primary_sync_complete() {
  local root="$1"
  local manifest_path status timestamp

  manifest_path="$(usb_primary_sync_manifest "$root")"
  [[ -f "$manifest_path" ]] || return 1

  status="$(awk -F= '$1 == "LAST_PRIMARY_SYNC_STATUS" { print $2; exit }' "$manifest_path")"
  timestamp="$(awk -F= '$1 == "LAST_PRIMARY_SYNC_EPOCH" { print $2; exit }' "$manifest_path")"

  [[ "$status" == "complete" && "$timestamp" =~ ^[0-9]+$ ]]
}

usb_primary_sync_timestamp() {
  local root="$1"
  local manifest_path

  manifest_path="$(usb_primary_sync_manifest "$root")"
  [[ -f "$manifest_path" ]] || return 1

  awk -F= '$1 == "LAST_PRIMARY_SYNC_UTC" { print $2; exit }' "$manifest_path"
}

usb_primary_sync_epoch() {
  local root="$1"
  local manifest_path

  manifest_path="$(usb_primary_sync_manifest "$root")"
  [[ -f "$manifest_path" ]] || return 1

  awk -F= '$1 == "LAST_PRIMARY_SYNC_EPOCH" { print $2; exit }' "$manifest_path"
}

usb_primary_sync_age_hours() {
  local root="$1" sync_epoch now_epoch

  sync_epoch="$(usb_primary_sync_epoch "$root")" || return 1
  [[ "$sync_epoch" =~ ^[0-9]+$ ]] || return 1

  now_epoch="$(epoch_now)"
  printf '%s\n' $(((now_epoch - sync_epoch) / 3600))
}

usb_primary_sync_is_fresh() {
  local root="$1" age_hours

  age_hours="$(usb_primary_sync_age_hours "$root")" || return 1
  [[ "$age_hours" -le "$USB_SYNC_MAX_AGE_HOURS" ]]
}

macos_popup_warning() {
  local title="$1"
  local message="$2"

  warn "${title}: ${message}"

  if [[ "${MAC_NOTIFY_WARN}" != "1" ]]; then
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  fi
}

macos_popup_info() {
  local title="$1"
  local message="$2"

  info "${title}: ${message}"

  if [[ "${MAC_NOTIFY_INFO}" != "1" ]]; then
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  fi
}

availability_load_value() {
  local key="$1"

  [[ -f "$AVAILABILITY_STATE_FILE" ]] || return 1
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$AVAILABILITY_STATE_FILE"
}

availability_set_value() {
  local key="$1"
  local value="$2"
  local tmp

  ensure_state_dirs
  tmp="$(mktemp)"

  if [[ -f "$AVAILABILITY_STATE_FILE" ]]; then
    awk -F= -v k="$key" -v v="$value" '
      BEGIN { updated = 0 }
      $1 == k { print k "=" v; updated = 1; next }
      { print }
      END { if (updated == 0) print k "=" v }
    ' "$AVAILABILITY_STATE_FILE" >"$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >"$tmp"
  fi

  mv "$tmp" "$AVAILABILITY_STATE_FILE"
}

cache_mode_to_rclone_flag() {
  case "${CLIENT_CACHE_MODE}" in
    full)
      printf 'full\n'
      ;;
    spaceless|minimal|off)
      printf 'off\n'
      ;;
    writes)
      printf 'writes\n'
      ;;
    *)
      warn "Unknown CLIENT_CACHE_MODE=${CLIENT_CACHE_MODE}; falling back to full"
      printf 'full\n'
      ;;
  esac
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

run_rclone_probe() {
  rclone \
    --contimeout "${RCLONE_PROBE_CONNECT_TIMEOUT}" \
    --timeout "${RCLONE_PROBE_IO_TIMEOUT}" \
    --retries 1 \
    --low-level-retries 1 \
    "$@"
}

is_mounted() {
  local mount_path="$1"
  mount | grep -F "on ${mount_path} (" >/dev/null 2>&1 || mount | grep -F " ${mount_path} " >/dev/null 2>&1
}

remote_root_reachable() {
  local remote="$1"
  run_rclone_probe lsf "$(remote_base_path "$remote")" >/dev/null 2>&1
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
Policy     : ${SOURCE_POLICY}
Log file   : ${LOG_FILE}
Cache mode : ${CLIENT_CACHE_MODE}
USB subdir : ${USB_SUBDIR}
Warn popup : ${MAC_NOTIFY_WARN}
Info popup : ${MAC_NOTIFY_INFO}
USB max age: ${USB_SYNC_MAX_AGE_HOURS}h
Probe conn : ${RCLONE_PROBE_CONNECT_TIMEOUT}
Probe I/O  : ${RCLONE_PROBE_IO_TIMEOUT}
EOF
}
