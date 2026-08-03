#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_root
ARCHIVE="${1:?printer archive required}"
QUEUE="${2:-Panasonic_KX_MB1500}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "Extracting Panasonic printer driver..."
extract_archive "$ARCHIVE" "$WORK"
BASE="$(dirname "$(find_one "$WORK" '*/filter/L_H0JDGCZAZ')")"
BASE="$(dirname "$BASE")"
PPD_SRC="$BASE/ppd/L_Panasonic-MB1500-gdi.ppd"
[[ -f "$PPD_SRC" ]] || die "KX-MB1500 PPD not found in archive."

install -d -m 755 /usr/lib/cups/filter /usr/share/cups/model/panasonic \
  /usr/local/share/panasonic/printer/data /usr/local/share/panasonic/printer/conf \
  /var/spool/.panamfs
install -o root -g root -m 755 "$BASE/filter/L_H0JDGCZAZ" /usr/lib/cups/filter/L_H0JDGCZAZ
install -o root -g root -m 755 "$BASE/lib/L_H0JDJCZAZ.so.1.0.0" "$BASE/lib/L_H0JDJCZAZ_2.so.1.0.0" /usr/lib/
ln -sfn L_H0JDJCZAZ.so.1.0.0 /usr/lib/L_H0JDJCZAZ.so.1
ln -sfn L_H0JDJCZAZ.so.1 /usr/lib/L_H0JDJCZAZ.so
ln -sfn L_H0JDJCZAZ_2.so.1.0.0 /usr/lib/L_H0JDJCZAZ_2.so.1
ln -sfn L_H0JDJCZAZ_2.so.1 /usr/lib/L_H0JDJCZAZ_2.so
cp -a "$BASE/data/." /usr/local/share/panasonic/printer/data/
install -o root -g root -m 644 "$PPD_SRC" /usr/share/cups/model/panasonic/L_Panasonic-MB1500-gdi.ppd
chmod 777 /var/spool/.panamfs /usr/local/share/panasonic/printer/conf

PPD=/usr/share/cups/model/panasonic/L_Panasonic-MB1500-gdi.ppd
sed -i 's/\r$//' "$PPD"
sed -i 's/^\*FileVersion:.*/\*FileVersion: "2.0.4"/' "$PPD"

GS_REAL="$(ldconfig -p | awk '/libgs\.so(\.[0-9]+)? / && /x86-64/ {print $NF; exit}')"
[[ -n "$GS_REAL" && -e "$GS_REAL" ]] || die "Ghostscript shared library was not found."
install -d -m 755 /usr/local/lib
ln -sfn "$GS_REAL" /usr/local/lib/libgs.so
ldconfig
systemctl enable --now cups
systemctl restart cups

URI="$(lpinfo -v 2>/dev/null | awk '/direct usb:\/\/Panasonic\/KX-MB1500/ {print $2; exit}')"
[[ -n "$URI" ]] || die "CUPS cannot find Panasonic KX-MB1500 over USB. Check Proxmox USB passthrough."

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  lpadmin -p "$QUEUE" -v "$URI" -m panasonic/L_Panasonic-MB1500-gdi.ppd -E
else
  lpadmin -p "$QUEUE" -E -v "$URI" -m panasonic/L_Panasonic-MB1500-gdi.ppd
fi
cupsenable "$QUEUE"
cupsaccept "$QUEUE"
lpadmin -d "$QUEUE"
lpadmin -p "$QUEUE" \
  -o printer-is-shared=true \
  -o print-scaling-default=auto-fit \
  -o fit-to-page-default=true \
  -o media-default=A4 \
  -o PageSize=A4 \
  -o PageRegion=A4

log "Printer queue '$QUEUE' configured at $URI"
