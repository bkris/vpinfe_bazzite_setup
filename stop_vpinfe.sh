#!/usr/bin/env bash

VPINFE="$HOME/vpinball/vpinfe/vpinfe"
CHROME="$HOME/vpinball/vpinfe/_internal/chromium/linux/chrome/chrome"

pkill -f "$VPINFE" 2>/dev/null || true
pkill -f "$CHROME" 2>/dev/null || true

sleep 1

echo "Remaining VPinFE processes:"
pgrep -a vpinfe 2>/dev/null || echo "  none"

echo
echo "VPinFE ports:"
ss -ltnp 2>/dev/null | grep -E ':8000|:8001|:8002' || echo "  all free"
