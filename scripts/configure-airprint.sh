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

retry_lpadmin() {
  local attempt
  local max_attempts=10
  local delay=2

  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    if lpadmin "$@"; then
      return 0
    fi

    if (( attempt == max_attempts )); then
      return 1
    fi

    warn "CUPS temporarily unavailable; lpadmin retry $attempt/$max_attempts in ${delay}s..."
    sleep "$delay"
  done

  return 1
}

retry_lpadmin \
  -p "$QUEUE" \
  -o printer-is-shared=true ||
    die "Failed to enable CUPS printer sharing after multiple attempts."

systemctl restart cups
systemctl restart avahi-daemon
wait_for_cups || die "CUPS is not ready after AirPrint configuration."

sleep 3

log "Reading DNS-SD records published by CUPS..."

IPP_RECORDS="$(avahi-browse -rt _ipp._tcp 2>/dev/null || true)"
IPPS_RECORDS="$(avahi-browse -rt _ipps._tcp 2>/dev/null || true)"

printf '%s\n' "$IPP_RECORDS"
printf '%s\n' "$IPPS_RECORDS"

IPP_FOUND=0
IPPS_FOUND=0

if grep -Fq "rp=printers/${QUEUE}" <<<"$IPP_RECORDS"; then
    IPP_FOUND=1
fi

if grep -Fq "rp=printers/${QUEUE}" <<<"$IPPS_RECORDS"; then
    IPPS_FOUND=1
fi

if (( IPP_FOUND || IPPS_FOUND )); then
    success "CUPS is publishing $QUEUE through DNS-SD/Bonjour."

    if (( IPP_FOUND )); then
        success "_ipp._tcp advertisement found"
    fi

    if (( IPPS_FOUND )); then
        success "_ipps._tcp advertisement found"
    fi
else
    die "No CUPS DNS-SD record found for $QUEUE."
fi
