#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
QUEUE="${1:-$(cat "$STATE_DIR/queue-name" 2>/dev/null || printf '%s' Panasonic_KX_MB1500)}"

require_root
require_commands lp lpstat

log "Submitting local CUPS test page to $QUEUE..."
JOB="$(lp -d "$QUEUE" -o media=A4 -o fit-to-page /usr/share/cups/data/testprint)"
printf '%s\n' "$JOB"

sleep 8

STATE="$(lpstat -p "$QUEUE" -l 2>&1 || true)"
printf '%s\n' "$STATE"

if printf '%s' "$STATE" | grep -qiE 'disabled|stopped'; then
  error "Printer became stopped/disabled after the test job."
  tail -n 80 /var/log/cups/error_log >&2 || true
  exit 1
fi

if tail -n 120 /var/log/cups/error_log 2>/dev/null |
   grep -qE 'L_H0JDGCZAZ.*(crashed|ERROR)|Job stopped due to filter errors'; then
  warn "Recent CUPS log contains Panasonic filter errors."
  tail -n 120 /var/log/cups/error_log >&2
  exit 2
fi

success "CUPS accepted the local test without stopping the printer."
printf 'Confirm physically that the test page printed correctly.\n'
