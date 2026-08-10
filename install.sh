#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"

usage() {
cat <<'EOF'
Usage:
  sudo ./install.sh \
    --printer-driver /path/to/mccgdi-2.0.10-x86_64.tar.tar \
    --scanner-driver /path/to/panamfs-scan-1.3.1-x86_64.tar.tar

Options:
  --queue-name NAME       CUPS queue name (default: Panasonic_KX_MB1500)
  --no-airprint           Skip CUPS network sharing
  --no-airsane            Skip AirSane installation
  --airsane-ref REF       AirSane git ref (default: master)
  -h, --help              Show help
EOF
}

PRINTER=""
SCANNER=""
QUEUE="Panasonic_KX_MB1500"
DO_AIRPRINT=1
DO_AIRSANE=1
AIRSANE_REF="master"

need_value() {
  [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] ||
    die "Option $1 requires a value."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --printer-driver) need_value "$@"; PRINTER="$2"; shift 2 ;;
    --scanner-driver) need_value "$@"; SCANNER="$2"; shift 2 ;;
    --queue-name) need_value "$@"; QUEUE="$2"; shift 2 ;;
    --no-airprint) DO_AIRPRINT=0; shift ;;
    --no-airsane) DO_AIRSANE=0; shift ;;
    --airsane-ref) need_value "$@"; AIRSANE_REF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root
[[ "$(uname -m)" == x86_64 ]] || die "Only x86_64 is supported by these Panasonic driver archives."
[[ -r /etc/os-release ]] || die "Cannot identify operating system."
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "This installer currently supports Ubuntu only."
[[ "${VERSION_ID:-}" == "24.04" ]] || warn "Validated on Ubuntu 24.04; detected ${VERSION_ID:-unknown}."

[[ -n "$PRINTER" ]] || die "--printer-driver is required."
[[ -n "$SCANNER" ]] || die "--scanner-driver is required."
PRINTER="$(readlink -f "$PRINTER")"
SCANNER="$(readlink -f "$SCANNER")"
[[ -f "$PRINTER" ]] || die "Printer archive not found."
[[ -f "$SCANNER" ]] || die "Scanner archive not found."

[[ "$QUEUE" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid CUPS queue name: $QUEUE"

ensure_dirs
export BACKUP_SET="$(date '+%Y%m%d-%H%M%S')"
trap 'rc=$?; if ((rc)); then error "Installation failed at line $LINENO (exit $rc). See $LOG_FILE"; fi' EXIT

log "Stage 1/6: dependencies"
"$ROOT_DIR/scripts/install-deps.sh"

usb_present || die "USB 04da:0f0b not visible. Configure Proxmox USB passthrough before continuing."

log "Stage 2/6: printer driver and local queue"
"$ROOT_DIR/scripts/install-printer.sh" "$PRINTER" "$QUEUE"

log "Stage 3/6: local print smoke test"
"$ROOT_DIR/scripts/test-printer.sh" "$QUEUE" || {
  die "Local printing test failed. Network sharing was NOT configured."
}

if (( DO_AIRPRINT )); then
  log "Stage 4/6: standard CUPS DNS-SD/AirPrint sharing"
  "$ROOT_DIR/scripts/configure-airprint.sh" "$QUEUE"
else
  warn "Skipping AirPrint/CUPS sharing."
fi

log "Stage 5/6: scanner backend and USB permissions"
"$ROOT_DIR/scripts/install-scanner.sh" "$SCANNER"

if (( DO_AIRSANE )); then
  log "Stage 6/6: AirSane/eSCL"
  AIRSANE_REF="$AIRSANE_REF" "$ROOT_DIR/scripts/install-airsane.sh"
else
  warn "Skipping AirSane."
fi

printf '\n'
"$ROOT_DIR/scripts/doctor.sh" "$QUEUE" || true

success "Installation sequence completed."
printf '\nIMPORTANT:\n'
printf '  - Confirm that the local CUPS test page physically printed correctly.\n'
printf '  - On macOS add the printer discovered by Bonjour/AirPrint.\n'
printf '  - A CUPS-generated _ipps._tcp URI with ?uuid=... is VALID and expected.\n'
printf '  - Do not create a manual Avahi printer .service file.\n'
