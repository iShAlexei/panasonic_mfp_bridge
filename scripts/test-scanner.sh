#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

OUT="${1:-/tmp/panasonic-scan-test.png}"
require_root

DEVICE="$(sudo -u saned scanimage -L 2>/dev/null |
  sed -n "s/^device \`\\([^']*\\)'.*/\\1/p" |
  grep '^panamfs:' | head -n1)"

[[ -n "$DEVICE" ]] || die "No panamfs scanner visible to saned."

log "Scanning A4 150 dpi color test to $OUT..."
sudo -u saned scanimage \
  --device-name "$DEVICE" \
  --mode Color \
  --resolution 150 \
  --paper-size A4 \
  --format=png >"$OUT"

file "$OUT"
ls -lh "$OUT"
success "Scanner test completed."
