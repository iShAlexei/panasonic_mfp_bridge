#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

REF="${AIRSANE_REF:-master}"
SRC="/usr/local/src/AirSane"
BUILD="/usr/local/src/AirSane-build"

require_root
require_commands git cmake make scanimage systemctl

sudo -u saned scanimage -L 2>/dev/null | grep -Fq 'Panasonic KX-MB1500' ||
  die "AirSane will run as saned, but saned cannot access the scanner."

install -d -m 0755 /usr/local/src

if [[ -d "$SRC/.git" ]]; then
  log "Refreshing existing AirSane source..."
  git -C "$SRC" fetch --tags --prune
else
  rm -rf "$SRC"
  git clone https://github.com/SimulPiscator/AirSane.git "$SRC"
fi

git -C "$SRC" checkout "$REF"
if [[ "$REF" == "master" || "$REF" == "main" ]]; then
  git -C "$SRC" pull --ff-only || true
fi

rm -rf "$BUILD"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel
cmake --install "$BUILD"

systemctl daemon-reload
systemctl enable --now airsaned
sleep 3
systemctl is-active --quiet airsaned ||
  die "airsaned failed to start. Check: journalctl -u airsaned -n 100"

success "AirSane installed and running."
