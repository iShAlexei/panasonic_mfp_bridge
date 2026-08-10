#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

ARCHIVE="${1:?Usage: install-printer.sh DRIVER_ARCHIVE [QUEUE_NAME]}"
QUEUE="${2:-Panasonic_KX_MB1500}"

require_root
require_commands tar lpinfo lpadmin lpstat ldconfig

usb_present || die "Panasonic KX-MB1500 (04da:0f0b) is not visible in this VM."

TMP="$(mktemp -d /tmp/panasonic-printer.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
extract_archive "$ARCHIVE" "$TMP"

INSTALLER="$(find_one "$TMP" '*/install-driver')"
DRIVER_DIR="$(dirname "$INSTALLER")"

log "Installing official Panasonic GDI driver..."
(
  cd "$DRIVER_DIR"
  chmod +x ./install-driver
  ./install-driver
)

FILTER="/usr/lib/cups/filter/L_H0JDGCZAZ"
PPD="/usr/share/cups/model/panasonic/L_Panasonic-MB1500-gdi.ppd"

[[ -x "$FILTER" ]] || die "Panasonic CUPS filter was not installed: $FILTER"
[[ -f "$PPD" ]] || die "Panasonic PPD was not installed: $PPD"

# The legacy Panasonic filter searches libgs only in old fixed locations.
GS_REAL="$(
  find /usr/lib /lib -type f -o -type l 2>/dev/null |
    grep -E '/libgs\.so$' |
    grep -E 'x86_64-linux-gnu|/usr/lib/libgs\.so$' |
    head -n1 || true
)"
if [[ -z "$GS_REAL" ]]; then
  GS_REAL="$(ldconfig -p | awk '/libgs\.so \(/{print $NF; exit}')"
fi
[[ -n "$GS_REAL" && -e "$GS_REAL" ]] || die "Could not locate libgs.so"

install -d -m 0755 /usr/local/lib
ln -sfn "$GS_REAL" /usr/local/lib/libgs.so
ldconfig
success "Ghostscript compatibility link: /usr/local/lib/libgs.so -> $GS_REAL"

# Verify the legacy filter can at least resolve its normal ELF dependencies.
if ldd "$FILTER" | grep -q 'not found'; then
  ldd "$FILTER" >&2
  die "Panasonic filter has unresolved shared-library dependencies."
fi

DEVICE_URI="$(
  lpinfo -v 2>/dev/null |
    awk '/direct usb:\/\/Panasonic\/KX-MB1500/{sub(/^direct /,""); print; exit}'
)"
[[ -n "$DEVICE_URI" ]] || die "CUPS does not expose the Panasonic USB backend."

log "Creating CUPS queue $QUEUE..."
if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  backup_file "/etc/cups/ppd/${QUEUE}.ppd"
fi

lpadmin -p "$QUEUE" -E \
  -v "$DEVICE_URI" \
  -P "$PPD" \
  -D "Panasonic KX-MB1500" \
  -L "USB via Panasonic MFP Bridge"

lpadmin -d "$QUEUE"
cupsaccept "$QUEUE"
cupsenable "$QUEUE"

# These are the settings that fixed macOS/iOS scaling during the working setup.
lpadmin -p "$QUEUE" \
  -o media-default=A4 \
  -o PageSize=A4 \
  -o PageRegion=A4 \
  -o print-scaling-default=auto-fit \
  -o fit-to-page-default=true

printf '%s\n' "$QUEUE" >"$STATE_DIR/queue-name"
printf '%s\n' "$DEVICE_URI" >"$STATE_DIR/printer-device-uri"

systemctl restart cups
wait_for_cups || die "CUPS failed after printer installation."

lpstat -p "$QUEUE" >/dev/null || die "Printer queue verification failed."
success "Panasonic printer queue installed: $QUEUE"
