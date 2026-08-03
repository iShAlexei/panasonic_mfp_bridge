#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
QUEUE="$(cat "$STATE_DIR/queue-name" 2>/dev/null || echo Panasonic_KX_MB1500)"

systemctl disable --now airsaned 2>/dev/null || true
lpadmin -x "$QUEUE" 2>/dev/null || true
rm -f /usr/lib/cups/filter/L_H0JDGCZAZ
rm -f /usr/lib/L_H0JDJCZAZ.so /usr/lib/L_H0JDJCZAZ.so.1 /usr/lib/L_H0JDJCZAZ.so.1.0.0
rm -f /usr/lib/L_H0JDJCZAZ_2.so /usr/lib/L_H0JDJCZAZ_2.so.1 /usr/lib/L_H0JDJCZAZ_2.so.1.0.0
rm -f /usr/local/lib/libgs.so
rm -f /usr/share/cups/model/panasonic/L_Panasonic-MB1500-gdi.ppd
rm -rf /usr/local/share/panasonic/printer
rm -f /usr/lib/x86_64-linux-gnu/sane/libsane-panamfs.so*
rm -f /etc/sane.d/panamfs.conf /etc/udev/rules.d/60-panasonic-kx-mb1500-scanner.rules
sed -i '/^panamfs$/d' /etc/sane.d/dll.conf 2>/dev/null || true
rm -rf /usr/local/share/panasonic/scanner
udevadm control --reload-rules || true
ldconfig
systemctl restart cups avahi-daemon 2>/dev/null || true
rm -rf "$STATE_DIR"
log "Panasonic bridge files removed. AirSane source installation was left in place; remove it manually if desired."
