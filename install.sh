#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"

usage() {
  cat <<USAGE
Usage:
  sudo ./install.sh --printer-driver /path/to/mccgdi-2.0.10-x86_64.tar.tar \\
                    --scanner-driver /path/to/panamfs-scan-1.3.1-x86_64.tar.tar

Options:
  --printer-driver FILE   Official Panasonic Linux printer driver archive
  --scanner-driver FILE   Official Panasonic Linux scanner driver archive
  --queue-name NAME       CUPS queue name (default: Panasonic_KX_MB1500)
  --no-airsane            Do not build/install AirSane
  --help                  Show this help
USAGE
}

PRINTER_ARCHIVE=""
SCANNER_ARCHIVE=""
QUEUE_NAME="Panasonic_KX_MB1500"
INSTALL_AIRSANE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --printer-driver) PRINTER_ARCHIVE="$2"; shift 2 ;;
    --scanner-driver) SCANNER_ARCHIVE="$2"; shift 2 ;;
    --queue-name) QUEUE_NAME="$2"; shift 2 ;;
    --no-airsane) INSTALL_AIRSANE=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root
[[ $(uname -m) == x86_64 ]] || die "This release supports x86_64 only."
[[ -n "$PRINTER_ARCHIVE" ]] || die "--printer-driver is required."
[[ -n "$SCANNER_ARCHIVE" ]] || die "--scanner-driver is required."
PRINTER_ARCHIVE="$(readlink -f "$PRINTER_ARCHIVE")"
SCANNER_ARCHIVE="$(readlink -f "$SCANNER_ARCHIVE")"

mkdir -p "$STATE_DIR" "$BACKUP_DIR"
printf '%s\n' "$QUEUE_NAME" > "$STATE_DIR/queue-name"

log "Installing system dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  cups cups-client cups-bsd cups-filters ghostscript libgs-dev libcups2-dev \
  avahi-daemon avahi-utils sane-utils libsane-dev libusb-0.1-4 \
  git cmake g++ pkg-config ninja-build libjpeg-dev libpng-dev \
  libavahi-client-dev libusb-1.0-0-dev curl usbutils

"$ROOT_DIR/scripts/install-printer.sh" "$PRINTER_ARCHIVE" "$QUEUE_NAME"
"$ROOT_DIR/scripts/install-scanner.sh" "$SCANNER_ARCHIVE"
"$ROOT_DIR/scripts/configure-airprint.sh" "$QUEUE_NAME"
if [[ $INSTALL_AIRSANE -eq 1 ]]; then
  "$ROOT_DIR/scripts/install-airsane.sh"
fi

log "Installation complete. Running diagnostics..."
"$ROOT_DIR/scripts/doctor.sh" || warn "Some checks failed. Review the output above."
