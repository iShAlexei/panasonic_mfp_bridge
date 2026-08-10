#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/scripts/common.sh"

require_root
QUEUE="$(cat "$STATE_DIR/queue-name" 2>/dev/null || printf '%s' Panasonic_KX_MB1500)"

warn "This removes bridge configuration, but not every file installed by Panasonic vendor uninstallers."

systemctl disable --now airsaned 2>/dev/null || true
lpadmin -x "$QUEUE" 2>/dev/null || true
rm -f /etc/udev/rules.d/60-panasonic-kx-mb1500-scanner.rules
rm -f /usr/local/lib/libgs.so
udevadm control --reload-rules || true

success "Bridge-specific configuration removed."
printf 'Vendor driver files can be removed using the uninstall-driver scripts installed by Panasonic.\n'
