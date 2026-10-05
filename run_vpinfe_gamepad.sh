#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/vpinball"
source "$ROOT/vpinfe_fixes.sh"

stop_stale_vpinfe
install_chrome_wrapper
patch_gamepad_page

cd "$VPINFE_DIR"

# --gamepadtest registers the 'gamepad' window API and launches its own
# Chromium on the gamepad page. Opening that page manually against a
# --headless instance doesn't work: only the 'table' API is registered, so
# the page's WebSocket calls never get answered and the UI stays frozen.
exec "$VPINFE_BIN" --gamepadtest
