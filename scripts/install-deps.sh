#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root

log "Installing Ubuntu dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  cups cups-client cups-bsd cups-filters \
  ghostscript libgs-dev \
  avahi-daemon avahi-utils \
  sane-utils libsane-dev libusb-0.1-4 \
  git cmake g++ make pkg-config ninja-build \
  libjpeg-dev libpng-dev libavahi-client-dev libusb-1.0-0-dev \
  curl usbutils ca-certificates

systemctl enable --now cups avahi-daemon
wait_for_cups || die "CUPS did not become ready."

success "System dependencies installed."
