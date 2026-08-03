#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
QUEUE="${1:-$(cat "$STATE_DIR/queue-name" 2>/dev/null || echo Panasonic_KX_MB1500)}"
FAIL=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'OK   %s\n' "$label"; else printf 'FAIL %s\n' "$label"; FAIL=1; fi
}

check "USB device 04da:0f0b detected" bash -c "lsusb | grep -q '04da:0f0b'"
check "CUPS service active" systemctl is-active --quiet cups
check "Avahi service active" systemctl is-active --quiet avahi-daemon
check "Printer queue exists" lpstat -p "$QUEUE"
check "Panasonic CUPS filter installed" test -x /usr/lib/cups/filter/L_H0JDGCZAZ
check "Ghostscript compatibility link exists" test -e /usr/local/lib/libgs.so
check "Scanner backend installed" test -e /usr/lib/x86_64-linux-gnu/sane/libsane-panamfs.so
check "Scanner visible to saned" bash -c "sudo -u saned scanimage -L 2>/dev/null | grep -q 'Panasonic KX-MB1500'"
check "AirSane service active" systemctl is-active --quiet airsaned
check "AirSane HTTP port listening" bash -c "ss -lnt | grep -q ':8090'"
check "AirSane HTTP page responds" curl -fsS http://127.0.0.1:8090/
check "AirScan mDNS service published" bash -c "timeout 4 avahi-browse -rt _uscan._tcp 2>/dev/null | grep -qi Panasonic"
exit "$FAIL"
