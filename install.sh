#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"

readonly PANASONIC_PRINTER_URL="https://www.psn-web.net/cs/support/fax/common/file/Linux_PrnDriver/Driver_Install_files/mccgdi-2.0.10-x86_64.tar.gz"
readonly PANASONIC_SCANNER_URL="https://www.psn-web.net/cs/support/fax/common/file/Linux_ScanDriver/panamfs-scan-1.3.1-x86_64.tar.gz"

readonly PRINTER_ARCHIVE_NAME="mccgdi-2.0.10-x86_64.tar.gz"
readonly SCANNER_ARCHIVE_NAME="panamfs-scan-1.3.1-x86_64.tar.gz"

DRIVER_CACHE="${STATE_DIR}/drivers"

PRINTER=""
SCANNER=""
QUEUE="Panasonic_KX_MB1500"
DO_AIRPRINT=1
DO_AIRSANE=1
AIRSANE_REF="master"

# prompt | auto | local
DRIVER_SOURCE="prompt"

usage() {
  cat <<'EOF'
Usage:
  sudo ./install.sh [OPTIONS]

Driver source:
  --download-drivers
      Download the official Panasonic x86_64 Linux printer and scanner drivers.

  --printer-driver PATH
      Use a local Panasonic printer-driver archive.

  --scanner-driver PATH
      Use a local Panasonic scanner-driver archive.

If no driver source is supplied, the installer asks interactively whether
to download the official drivers or use local archives.

Other options:
  --queue-name NAME       CUPS queue name (default: Panasonic_KX_MB1500)
  --no-airprint           Skip CUPS network/AirPrint sharing
  --no-airsane            Skip AirSane/eSCL installation
  --airsane-ref REF       AirSane Git ref/tag/commit (default: master)
  -h, --help              Show this help

Examples:
  sudo ./install.sh --download-drivers

  sudo ./install.sh \
    --printer-driver ~/drivers/mccgdi-2.0.10-x86_64.tar.gz \
    --scanner-driver ~/drivers/panamfs-scan-1.3.1-x86_64.tar.gz

IMPORTANT:
  A full system reboot is required after installation before final
  AirPrint testing from macOS/Windows.
EOF
}

need_value() {
  [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] ||
    die "Option $1 requires a value."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --download-drivers)
      DRIVER_SOURCE="auto"
      shift
      ;;
    --printer-driver)
      need_value "$@"
      PRINTER="$2"
      shift 2
      ;;
    --scanner-driver)
      need_value "$@"
      SCANNER="$2"
      shift 2
      ;;
    --queue-name)
      need_value "$@"
      QUEUE="$2"
      shift 2
      ;;
    --no-airprint)
      DO_AIRPRINT=0
      shift
      ;;
    --no-airsane)
      DO_AIRSANE=0
      shift
      ;;
    --airsane-ref)
      need_value "$@"
      AIRSANE_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_root

[[ "$(uname -m)" == "x86_64" ]] ||
  die "Only x86_64 is currently supported by this installer."

[[ -r /etc/os-release ]] ||
  die "Cannot identify the operating system."

# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] ||
  die "This installer currently supports Ubuntu only."

if [[ "${VERSION_ID:-}" != "24.04" ]]; then
  warn "Validated on Ubuntu 24.04; detected ${VERSION_ID:-unknown}."
fi

[[ "$QUEUE" =~ ^[A-Za-z0-9._-]+$ ]] ||
  die "Invalid CUPS queue name: $QUEUE"

if [[ "$DRIVER_SOURCE" == "auto" &&
      ( -n "$PRINTER" || -n "$SCANNER" ) ]]; then
  die "--download-drivers cannot be combined with --printer-driver/--scanner-driver."
fi

if [[ "$DRIVER_SOURCE" != "auto" ]]; then
  if [[ -n "$PRINTER" && -z "$SCANNER" ]] ||
     [[ -z "$PRINTER" && -n "$SCANNER" ]]; then
    die "Specify both --printer-driver and --scanner-driver, or neither."
  fi
fi

ensure_dirs
install -d -m 0755 "$DRIVER_CACHE"

export BACKUP_SET
BACKUP_SET="$(date '+%Y%m%d-%H%M%S')"

trap 'rc=$?; if (( rc )); then error "Installation failed at line $LINENO (exit $rc). See $LOG_FILE"; fi' EXIT

invoking_user_home() {
  local user="${SUDO_USER:-root}"
  getent passwd "$user" | awk -F: '{print $6}'
}

normalize_user_path() {
  local value="${1:?path required}"
  local home

  if [[ "$value" == "~/"* ]]; then
    home="$(invoking_user_home)"
    value="${home}/${value#~/}"
  fi

  readlink -f -- "$value"
}

validate_driver_archive() {
  local archive="${1:?archive required}"
  local kind="${2:?kind required}"

  [[ -f "$archive" ]] ||
    die "$kind driver archive not found: $archive"

  [[ -s "$archive" ]] ||
    die "$kind driver archive is empty: $archive"

  tar -tf "$archive" >/dev/null 2>&1 ||
    die "$kind driver archive is not a valid tar archive: $archive"

  local members
  members="$(tar -tf "$archive" 2>/dev/null || true)"

  if ! grep -Eq '(^|/)install-driver$' <<<"$members"; then
    die "$kind archive does not look like the expected Panasonic Linux package."
  fi
}

select_driver_source() {
  local answer

  [[ -t 0 ]] ||
    die "No driver source specified in non-interactive mode. Use --download-drivers or provide both local driver archives."

  printf '\n'
  printf 'Panasonic Linux printer and scanner drivers are required.\n'
  printf '\n'
  printf '  1) Download the official x86_64 drivers from Panasonic\n'
  printf '  2) Use Panasonic driver archives already downloaded locally\n'
  printf '\n'

  while true; do
    read -r -p "Choose driver source [1/2]: " answer

    case "$answer" in
      1)
        DRIVER_SOURCE="auto"
        return 0
        ;;
      2)
        DRIVER_SOURCE="local"
        return 0
        ;;
      *)
        printf 'Please enter 1 or 2.\n'
        ;;
    esac
  done
}

select_local_drivers() {
  local printer_path
  local scanner_path

  [[ -t 0 ]] ||
    die "Local-driver selection requires an interactive terminal."

  printf '\n'
  printf 'Enter paths to the original Panasonic Linux driver archives.\n'
  printf 'Absolute paths are recommended; ~/... is also accepted.\n'
  printf '\n'

  read -r -e -p "Printer driver archive: " printer_path
  read -r -e -p "Scanner driver archive: " scanner_path

  PRINTER="$(normalize_user_path "$printer_path")"
  SCANNER="$(normalize_user_path "$scanner_path")"

  validate_driver_archive "$PRINTER" "Printer"
  validate_driver_archive "$SCANNER" "Scanner"

  success "Local Panasonic driver archives accepted."
}

download_one_driver() {
  local url="${1:?url required}"
  local output="${2:?output required}"
  local description="${3:?description required}"
  local part="${output}.part"
  local total=""
  local chunk_size=16384
  local start end expected got

  if [[ -s "$output" ]]; then
    local cached_members
    cached_members="$(tar -tf "$output" 2>/dev/null || true)"
    if grep -Eq '(^|/)install-driver$' <<<"$cached_members"; then
      success "$description already cached: $output"
      return 0
    fi
  fi

  rm -f -- "$part" "${part}.chunk"
  log "Downloading $description from Panasonic..."

  # First try an ordinary transfer. Some networks/CDN paths stall after the
  # first ~16 KiB; keep it time-bounded so we can fall back automatically.
  if curl -4 --http1.1 \
      --fail --location --show-error --progress-bar \
      --connect-timeout 20 --speed-time 20 --speed-limit 1024 \
      --retry 2 --retry-delay 2 \
      --output "$part" "$url"; then
    if tar -tf "$part" >/dev/null 2>&1; then
      mv -f -- "$part" "$output"
      validate_driver_archive "$output" "$description"
      success "Downloaded $description."
      return 0
    fi
  fi

  warn "Normal download stalled or was incomplete; trying HTTP Range fallback (16 KiB chunks)."
  rm -f -- "$part"

  total="$(curl -4 --http1.1 --fail --location --silent --show-error --head "$url" \
    | tr -d '\r' | awk 'tolower($1)=="content-length:" {n=$2} END {print n}')"
  [[ "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]] ||
    die "Could not determine $description size for HTTP Range fallback."

  : > "$part"
  start=0
  while (( start < total )); do
    end=$((start + chunk_size - 1))
    (( end >= total )) && end=$((total - 1))
    expected=$((end - start + 1))

    rm -f -- "${part}.chunk"
    curl -4 --http1.1 \
      --fail --location --silent --show-error \
      --connect-timeout 20 --max-time 60 \
      --retry 4 --retry-delay 1 \
      --range "${start}-${end}" \
      --output "${part}.chunk" "$url" ||
        die "HTTP Range download failed for bytes ${start}-${end} of $description."

    got="$(stat -c '%s' "${part}.chunk")"
    [[ "$got" -eq "$expected" ]] ||
      die "HTTP Range returned $got bytes; expected $expected for bytes ${start}-${end}."

    cat "${part}.chunk" >> "$part"
    printf '\r  %s: %d/%d bytes (%d%%)' "$description" "$((end + 1))" "$total" "$(((end + 1) * 100 / total))" >&2
    start=$((end + 1))
  done
  printf '\n' >&2
  rm -f -- "${part}.chunk"

  [[ "$(stat -c '%s' "$part")" -eq "$total" ]] ||
    die "HTTP Range fallback produced an unexpected file size for $description."

  mv -f -- "$part" "$output"
  validate_driver_archive "$output" "$description"
  success "$description downloaded successfully using HTTP Range fallback."
}

download_panasonic_drivers() {
  PRINTER="${DRIVER_CACHE}/${PRINTER_ARCHIVE_NAME}"
  SCANNER="${DRIVER_CACHE}/${SCANNER_ARCHIVE_NAME}"

  download_one_driver \
    "$PANASONIC_PRINTER_URL" \
    "$PRINTER" \
    "Panasonic printer driver"

  download_one_driver \
    "$PANASONIC_SCANNER_URL" \
    "$SCANNER" \
    "Panasonic scanner driver"

  success "Official Panasonic driver archives are ready."
}

resolve_driver_source() {
  if [[ -n "$PRINTER" && -n "$SCANNER" ]]; then
    DRIVER_SOURCE="local"

    PRINTER="$(normalize_user_path "$PRINTER")"
    SCANNER="$(normalize_user_path "$SCANNER")"

    validate_driver_archive "$PRINTER" "Printer"
    validate_driver_archive "$SCANNER" "Scanner"

    log "Using Panasonic driver archives supplied on the command line."
    return 0
  fi

  if [[ "$DRIVER_SOURCE" == "prompt" ]]; then
    select_driver_source
  fi

  case "$DRIVER_SOURCE" in
    auto)
      ;;
    local)
      select_local_drivers
      ;;
    *)
      die "Internal error: unknown driver source '$DRIVER_SOURCE'"
      ;;
  esac
}

disable_cups_browsed() {
  if systemctl list-unit-files cups-browsed.service >/dev/null 2>&1; then
    log "Disabling cups-browsed to prevent automatic implicitclass queues..."
    systemctl disable --now cups-browsed.service >/dev/null 2>&1 || true

    if systemctl is-active --quiet cups-browsed.service; then
      warn "cups-browsed is still active."
    else
      success "cups-browsed disabled."
    fi
  fi
}

resolve_driver_source

printf '\n'
log "Installation plan:"
log "  Queue:       $QUEUE"
log "  Driver mode: $DRIVER_SOURCE"
log "  AirPrint:    $([[ "$DO_AIRPRINT" -eq 1 ]] && printf yes || printf no)"
log "  AirSane:     $([[ "$DO_AIRSANE" -eq 1 ]] && printf yes || printf no)"
printf '\n'

log "Stage 1/6: system dependencies"
"$ROOT_DIR/scripts/install-deps.sh"

disable_cups_browsed

if [[ "$DRIVER_SOURCE" == "auto" ]]; then
  download_panasonic_drivers
fi

validate_driver_archive "$PRINTER" "Printer"
validate_driver_archive "$SCANNER" "Scanner"

log "Printer archive: $PRINTER"
log "Scanner archive: $SCANNER"

usb_present ||
  die "Panasonic USB device 04da:0f0b is not visible. Configure Proxmox USB passthrough before continuing."

log "Stage 2/6: Panasonic printer driver and local CUPS queue"
"$ROOT_DIR/scripts/install-printer.sh" "$PRINTER" "$QUEUE"

log "Stage 3/6: local print smoke test"

"$ROOT_DIR/scripts/test-printer.sh" "$QUEUE" || {
  die "Local printing test failed. Network printer sharing was NOT configured."
}

log "Waiting for CUPS to settle after local print test..."

sleep 2

wait_for_cups ||
  die "CUPS did not become ready after local print test."

if (( DO_AIRPRINT )); then
  log "Stage 4/6: standard CUPS DNS-SD/AirPrint sharing"
  "$ROOT_DIR/scripts/configure-airprint.sh" "$QUEUE"
else
  warn "Stage 4/6 skipped: AirPrint/CUPS sharing disabled by user."
fi

log "Stage 5/6: Panasonic scanner backend and USB permissions"
"$ROOT_DIR/scripts/install-scanner.sh" "$SCANNER"

if (( DO_AIRSANE )); then
  log "Stage 6/6: AirSane/eSCL"
  AIRSANE_REF="$AIRSANE_REF" \
    "$ROOT_DIR/scripts/install-airsane.sh"
else
  warn "Stage 6/6 skipped: AirSane disabled by user."
fi

cat /proc/sys/kernel/random/boot_id > "${STATE_DIR}/install-boot-id"

printf '\n'
printf '# Panasonic MFP Bridge diagnostics\n\n'
"$ROOT_DIR/scripts/doctor.sh" "$QUEUE" || true

printf '\n'
success "Installation sequence completed."

printf '\n'
printf '============================================================\n'
printf ' IMPORTANT: A FULL SYSTEM REBOOT IS REQUIRED\n'
printf '============================================================\n'
printf '\n'
printf 'The Panasonic driver, CUPS, USB state and Bonjour/DNS-SD services\n'
printf 'must be started from a clean boot before final client testing.\n'
printf '\n'
printf 'Run now:\n'
printf '\n'
printf '    sudo reboot\n'
printf '\n'
printf 'After the server has rebooted:\n'
printf '\n'
printf '  1. Wait about 20-30 seconds for CUPS, Avahi and AirSane.\n'
printf '  2. Add/test the printer from macOS or Windows through Bonjour/AirPrint.\n'
printf '  3. Test scanning through eSCL/AirScan.\n'
printf '\n'
printf 'Notes:\n'
printf '  - Do NOT create a custom Avahi printer .service file.\n'
printf '  - A CUPS-generated _ipps._tcp URI containing ?uuid=... is valid.\n'
printf '  - cups-browsed is intentionally disabled on this print-server VM.\n'
printf '\n'
