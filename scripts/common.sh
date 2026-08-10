#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="panasonic-mfp-bridge"
readonly STATE_DIR="/var/lib/${PROJECT_NAME}"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly LOG_DIR="/var/log/${PROJECT_NAME}"
readonly LOG_FILE="${LOG_DIR}/install.log"
readonly LOG_PREFIX="[panasonic-mfp]"

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  readonly C_RED=$'\033[31m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_GREEN=$'\033[32m'
  readonly C_BLUE=$'\033[34m'
  readonly C_RESET=$'\033[0m'
else
  readonly C_RED="" C_YELLOW="" C_GREEN="" C_BLUE="" C_RESET=""
fi

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

_emit() {
  local level="${1:?level required}"
  local color="${2:-}"
  shift 2
  local line
  line="$(timestamp) ${LOG_PREFIX} ${level}: $*"
  printf '%s%s%s\n' "$color" "$line" "$C_RESET" >&2
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

log()     { _emit INFO "$C_BLUE" "$*"; }
success() { _emit OK "$C_GREEN" "$*"; }
warn()    { _emit WARNING "$C_YELLOW" "$*"; }
error()   { _emit ERROR "$C_RED" "$*"; }
die()     { error "$*"; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root, e.g. sudo $0"
}

require_cmd() {
  command -v "${1:?command required}" >/dev/null 2>&1 ||
    die "Required command not found: $1"
}

require_commands() {
  local c
  for c in "$@"; do require_cmd "$c"; done
}

ensure_dirs() {
  require_root
  install -d -m 0755 "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR"
  touch "$LOG_FILE"
  chmod 0644 "$LOG_FILE"
}

backup_file() {
  local src="${1:?path required}"
  [[ -e "$src" || -L "$src" ]] || return 0
  ensure_dirs
  local set="${BACKUP_SET:-$(date '+%Y%m%d-%H%M%S')}"
  local dir="${BACKUP_DIR}/${set}"
  install -d -m 0755 "$dir"
  local name
  name="$(printf '%s' "$src" | sed 's#^/##;s#/#__#g;s#[^A-Za-z0-9._-]#_#g')"
  [[ -e "$dir/$name" || -L "$dir/$name" ]] && return 0
  cp -a -- "$src" "$dir/$name"
  printf '%s\t%s\n' "$src" "$dir/$name" >>"$dir/manifest.tsv"
  log "Backed up $src"
}

extract_archive() {
  local archive="${1:?archive required}"
  local dest="${2:?destination required}"
  [[ -f "$archive" ]] || die "Archive not found: $archive"
  tar -tf "$archive" >/dev/null 2>&1 || die "Invalid tar archive: $archive"
  [[ -n "$dest" && "$dest" != "/" ]] || die "Unsafe extraction path: $dest"
  rm -rf -- "$dest"
  mkdir -p -- "$dest"
  tar -xf "$archive" -C "$dest"
}

find_one() {
  local base="${1:?base required}"
  local pattern="${2:?pattern required}"
  local -a found=()
  mapfile -t found < <(find "$base" -type f -path "$pattern" -print | sort | head -n 2)
  case "${#found[@]}" in
    0) die "Could not find '$pattern' under '$base'" ;;
    1) printf '%s\n' "${found[0]}" ;;
    *) die "Multiple files match '$pattern' under '$base'" ;;
  esac
}

wait_for_cups() {
  local i
  for i in {1..30}; do
    if systemctl is-active --quiet cups &&
       lpstat -r 2>/dev/null | grep -q 'scheduler is running'; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

usb_present() {
  lsusb -d 04da:0f0b >/dev/null 2>&1
}
