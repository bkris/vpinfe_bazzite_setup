#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/vpinball"
source "$ROOT/vpinfe_fixes.sh"

stop_stale_vpinfe
install_chrome_wrapper

cd "$VPINFE_DIR"

# Let VPinFE manage Chromium itself: it starts the WebSocket bridge before
# opening windows, applies the [Displays]/chromeoptions settings from
# vpinfe.ini, and can close its own windows on Exit. The Chromium wrapper
# (vpinfe_fixes.sh) is what makes VPinFE-launched Chromium work on Bazzite.
exec "$VPINFE_BIN"
