#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="panasonic-mfp-bridge"
STATE_DIR="/var/lib/${PROJECT_NAME}"
BACKUP_DIR="${STATE_DIR}/backups"
LOG_PREFIX="[panasonic-mfp]"

log() { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARNING: %s\n' "$LOG_PREFIX" "$*" >&2; }
die() { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this command with sudo."
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  mkdir -p "$BACKUP_DIR"
  local name
  name="$(printf '%s' "$path" | sed 's#^/##; s#/#__#g')"
  [[ -e "$BACKUP_DIR/$name" ]] || cp -a "$path" "$BACKUP_DIR/$name"
}

extract_archive() {
  local archive="$1" destination="$2"
  [[ -f "$archive" ]] || die "Archive not found: $archive"
  rm -rf "$destination"
  mkdir -p "$destination"
  tar -xf "$archive" -C "$destination"
}

find_one() {
  local root="$1" pattern="$2"
  local result
  result="$(find "$root" -type f -path "$pattern" -print -quit)"
  [[ -n "$result" ]] || die "Could not find $pattern in $root"
  printf '%s\n' "$result"
}
