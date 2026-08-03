#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_root

if command -v airsaned >/dev/null 2>&1; then
  log "AirSane is already installed; ensuring service is enabled."
else
  SRC=/usr/local/src/AirSane
  BUILD=/usr/local/src/AirSane-build
  rm -rf "$SRC" "$BUILD"
  git clone --depth 1 https://github.com/SimulPiscator/AirSane.git "$SRC"
  cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD"
  cmake --install "$BUILD"
fi
systemctl daemon-reload
systemctl enable --now airsaned
systemctl restart airsaned
log "AirSane enabled. Web UI default: http://SERVER_IP:8090/"
