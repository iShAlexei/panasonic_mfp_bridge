#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_root
QUEUE="${1:-Panasonic_KX_MB1500}"

systemctl enable --now avahi-daemon cups
backup_file /etc/cups/cupsd.conf
cupsctl WebInterface=yes SharePrinters=yes RemoteAny=yes

CONF=/etc/cups/cupsd.conf
if grep -qE '^Listen[[:space:]]+localhost:631' "$CONF"; then
  sed -i 's/^Listen[[:space:]]\+localhost:631/Port 631/' "$CONF"
elif ! grep -qE '^(Port[[:space:]]+631|Listen[[:space:]]+0\.0\.0\.0:631)' "$CONF"; then
  printf '\nPort 631\n' >> "$CONF"
fi
if grep -qE '^Browsing[[:space:]]+' "$CONF"; then
  sed -i 's/^Browsing[[:space:]].*/Browsing Yes/' "$CONF"
else
  printf 'Browsing Yes\n' >> "$CONF"
fi
if grep -qE '^BrowseLocalProtocols[[:space:]]+' "$CONF"; then
  sed -i 's/^BrowseLocalProtocols[[:space:]].*/BrowseLocalProtocols dnssd/' "$CONF"
else
  printf 'BrowseLocalProtocols dnssd\n' >> "$CONF"
fi

lpadmin -p "$QUEUE" -o printer-is-shared=true
systemctl restart cups avahi-daemon
log "AirPrint/IPP sharing enabled for '$QUEUE'."
