#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

ARCHIVE="${1:?Usage: install-scanner.sh DRIVER_ARCHIVE}"

require_root
require_commands tar scanimage lsusb udevadm

usb_present || die "Panasonic KX-MB1500 (04da:0f0b) is not visible in this VM."

TMP="$(mktemp -d /tmp/panasonic-scanner.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
extract_archive "$ARCHIVE" "$TMP"

INSTALLER="$(find_one "$TMP" '*/install-driver')"
DRIVER_DIR="$(dirname "$INSTALLER")"

log "Installing official Panasonic panamfs SANE backend..."
(
  cd "$DRIVER_DIR"
  chmod +x ./install-driver
  ./install-driver
)

SANE_DIR="/usr/lib/x86_64-linux-gnu/sane"
BACKEND="$SANE_DIR/libsane-panamfs.so.1.3.1"

[[ -e "$BACKEND" ]] || die "panamfs backend not found after installation: $BACKEND"
ldd "$BACKEND" | grep -q 'not found' && {
  ldd "$BACKEND" >&2
  die "panamfs backend has unresolved shared libraries."
}

grep -qxF 'panamfs' /etc/sane.d/dll.conf ||
  printf '%s\n' 'panamfs' >>/etc/sane.d/dll.conf

grep -Eq '^[[:space:]]*usb[[:space:]]+0x04da[[:space:]]+0x0f0b' /etc/sane.d/panamfs.conf ||
  die "panamfs.conf does not contain USB ID 04da:0f0b."

groupadd -f scanner
id saned >/dev/null 2>&1 || die "saned user is missing; sane-utils installation is incomplete."
usermod -aG scanner saned

cat >/etc/udev/rules.d/60-panasonic-kx-mb1500-scanner.rules <<'EOF'
# Panasonic KX-MB1500RU scanner interface
SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="04da", ATTR{idProduct}=="0f0b", MODE="0660", GROUP="scanner", TAG+="uaccess"
EOF

udevadm control --reload-rules
udevadm trigger --subsystem-match=usb
sleep 2

if ! scanimage -L 2>/dev/null | grep -Fq 'Panasonic KX-MB1500'; then
  warn "Root scanimage does not see the scanner yet; USB may need replug/reboot."
fi

if ! sudo -u saned scanimage -L 2>/dev/null | grep -Fq 'Panasonic KX-MB1500'; then
  warn "saned cannot see the scanner yet. A reboot or USB reattach may be needed."
  warn "Check: ls -l /dev/bus/usb/\$(lsusb | awk '/04da:0f0b/{printf \"%03d/%03d\",$2,$4}' | tr -d :)"
else
  success "saned can access Panasonic KX-MB1500."
fi

success "Panasonic scanner backend installed."
