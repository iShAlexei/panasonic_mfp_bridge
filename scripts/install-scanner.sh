#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_root
ARCHIVE="${1:?scanner archive required}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "Extracting Panasonic scanner backend..."
extract_archive "$ARCHIVE" "$WORK"
BACKEND="$(find_one "$WORK" '*/sane-backend/libsane-panamfs.so.1.3.1')"
BASE="$(dirname "$(dirname "$BACKEND")")"
SANE_LIB_DIR="/usr/lib/x86_64-linux-gnu/sane"

backup_file /etc/sane.d/dll.conf
backup_file /etc/sane.d/panamfs.conf
install -d -m 755 "$SANE_LIB_DIR" /usr/local/share/panasonic/scanner/data
install -o root -g root -m 755 "$BACKEND" "$SANE_LIB_DIR/libsane-panamfs.so.1.3.1"
ln -sfn libsane-panamfs.so.1.3.1 "$SANE_LIB_DIR/libsane-panamfs.so.1"
ln -sfn libsane-panamfs.so.1 "$SANE_LIB_DIR/libsane-panamfs.so"
install -o root -g root -m 644 "$BASE/sane-backend/panamfs.conf" /etc/sane.d/panamfs.conf
if ! grep -qxF panamfs /etc/sane.d/dll.conf; then
  printf '\npanamfs\n' >> /etc/sane.d/dll.conf
fi

for po in "$BASE"/sane-backend/po/sane-panamfs.*.po; do
  [[ -f "$po" ]] || continue
  locale="$(basename "$po" | sed 's/^sane-panamfs\.//; s/\.po$//')"
  install -d -m 755 "/usr/local/share/panasonic/scanner/data/$locale"
  install -o root -g root -m 644 "$po" "/usr/local/share/panasonic/scanner/data/$locale/sane-panamfs.po"
done

getent group scanner >/dev/null || groupadd --system scanner
id saned >/dev/null 2>&1 || die "The saned user is missing; install sane-utils."
usermod -aG scanner saned
cat > /etc/udev/rules.d/60-panasonic-kx-mb1500-scanner.rules <<'RULE'
# Panasonic KX-MB1500RU scanner access for SANE/AirSane
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="04da", ATTR{idProduct}=="0f0b", MODE="0660", GROUP="scanner", TAG+="uaccess"
RULE
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb || true
sleep 2
ldconfig

if ! sudo -u saned scanimage -L 2>/dev/null | grep -q 'Panasonic KX-MB1500'; then
  warn "Scanner is not visible to user 'saned' yet. Replug the USB device or reboot the VM, then run doctor.sh."
else
  log "Panasonic scanner backend is available to user 'saned'."
fi
