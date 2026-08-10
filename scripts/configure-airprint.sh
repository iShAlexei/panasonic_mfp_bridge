#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

QUEUE="${1:-$(cat "$STATE_DIR/queue-name" 2>/dev/null || printf '%s' Panasonic_KX_MB1500)}"

require_root
require_commands cupsctl lpadmin lpstat avahi-browse

lpstat -p "$QUEUE" >/dev/null 2>&1 || die "CUPS queue not found: $QUEUE"

# IMPORTANT: use CUPS' own DNS-SD publication. Do NOT create a custom
# Avahi printer service. CUPS generates the real UUID and capabilities.
log "Enabling standard CUPS printer sharing on the local subnet..."
cupsctl --share-printers

wait_for_cups || die "CUPS did not recover after enabling sharing."

lpadmin -p "$QUEUE" \
  -o printer-is-shared=true \
  -o printer-op-policy=default \
  -o auth-info-required=none \
  -u allow:all

systemctl restart cups
systemctl restart avahi-daemon
wait_for_cups || die "CUPS is not ready after AirPrint configuration."

sleep 3

log "DNS-SD records published by CUPS:"
avahi-browse -rt _ipp._tcp 2>/dev/null | grep -A3 -B1 -F "$QUEUE" || true
avahi-browse -rt _ipps._tcp 2>/dev/null | grep -A3 -B1 -F "$QUEUE" || true

# Both _ipp._tcp and _ipps._tcp are valid CUPS publications.
# macOS may prefer _ipps._tcp; do not replace it with a hand-written record.
if avahi-browse -rt _ipp._tcp 2>/dev/null | grep -Fq "$QUEUE" ||
   avahi-browse -rt _ipps._tcp 2>/dev/null | grep -Fq "$QUEUE"; then
  success "CUPS is publishing $QUEUE through DNS-SD/Bonjour."
else
  die "No CUPS DNS-SD record found for $QUEUE."
fi
