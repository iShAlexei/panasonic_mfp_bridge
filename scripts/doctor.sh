#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

QUEUE="${1:-$(cat "$STATE_DIR/queue-name" 2>/dev/null || printf '%s' Panasonic_KX_MB1500)}"
FAIL=0
WARN=0

ok(){ success "$*"; }
bad(){ error "$*"; FAIL=$((FAIL+1)); }
meh(){ warn "$*"; WARN=$((WARN+1)); }

printf 'Panasonic MFP Bridge diagnostics\n================================\n'

usb_present && ok "USB device 04da:0f0b is visible" || bad "USB device 04da:0f0b not found"
systemctl is-active --quiet cups && ok "CUPS active" || bad "CUPS inactive"
systemctl is-active --quiet avahi-daemon && ok "Avahi active" || bad "Avahi inactive"

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  ok "CUPS queue exists: $QUEUE"
else
  bad "CUPS queue missing: $QUEUE"
fi

lpstat -a "$QUEUE" 2>/dev/null | grep -q 'accepting requests' &&
  ok "Queue accepts jobs" || bad "Queue does not accept jobs"

lpinfo -v 2>/dev/null | grep -Fq 'usb://Panasonic/KX-MB1500' &&
  ok "CUPS USB backend sees Panasonic" || bad "CUPS USB backend does not see Panasonic"

[[ -x /usr/lib/cups/filter/L_H0JDGCZAZ ]] &&
  ok "Panasonic GDI filter installed" || bad "Panasonic GDI filter missing"

[[ -e /usr/local/lib/libgs.so ]] &&
  ok "Legacy Ghostscript compatibility link exists" || bad "libgs compatibility link missing"

if lpoptions -p "$QUEUE" 2>/dev/null | grep -Eq 'PageSize=A4|media=A4|media-default=A4'; then
  ok "A4 is configured"
else
  meh "A4 default was not visible in lpoptions output"
fi

if avahi-browse -rt _ipp._tcp 2>/dev/null | grep -Fq "$QUEUE" ||
   avahi-browse -rt _ipps._tcp 2>/dev/null | grep -Fq "$QUEUE"; then
  ok "CUPS publishes printer via DNS-SD"
else
  bad "Printer DNS-SD publication not found"
fi

if sudo -u saned scanimage -L 2>/dev/null | grep -Fq 'Panasonic KX-MB1500'; then
  ok "saned can access Panasonic scanner"
else
  bad "saned cannot access Panasonic scanner"
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^airsaned\.service'; then
  systemctl is-active --quiet airsaned && ok "AirSane active" || bad "AirSane installed but inactive"
  if avahi-browse -rt _uscan._tcp 2>/dev/null | grep -qi Panasonic; then
    ok "AirSane publishes _uscan._tcp"
  else
    meh "No Panasonic _uscan._tcp record found"
  fi
else
  meh "AirSane is not installed"
fi

printf '\nFailures: %d\nWarnings: %d\n' "$FAIL" "$WARN"
(( FAIL == 0 )) || exit 1
(( WARN == 0 )) || exit 2
success "All diagnostics passed."
