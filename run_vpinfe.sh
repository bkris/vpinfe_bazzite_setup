#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/vpinball"
VPINFE_DIR="$ROOT/vpinfe"
VPINFE_BIN="$VPINFE_DIR/vpinfe"
CHROME_BIN="$VPINFE_DIR/_internal/chromium/linux/chrome/chrome"

cleanup() {
    if [[ -n "${CHROME_PID:-}" ]] && kill -0 "$CHROME_PID" 2>/dev/null; then
        kill "$CHROME_PID" 2>/dev/null || true
        wait "$CHROME_PID" 2>/dev/null || true
    fi

    if [[ -n "${VPINFE_PID:-}" ]] && kill -0 "$VPINFE_PID" 2>/dev/null; then
        kill "$VPINFE_PID" 2>/dev/null || true
        wait "$VPINFE_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# Avoid stale copies occupying ports 8000-8002.
pkill -f "$VPINFE_BIN" 2>/dev/null || true
pkill -f "$CHROME_BIN" 2>/dev/null || true
sleep 1

cd "$VPINFE_DIR"
"$VPINFE_BIN" --headless &
VPINFE_PID=$!

# Wait until VPinFE's asset server is ready.
for _ in {1..50}; do
    if (echo > /dev/tcp/127.0.0.1/8000) >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$VPINFE_PID" 2>/dev/null; then
        echo "VPinFE stopped before port 8000 became ready." >&2
        exit 1
    fi
    sleep 0.2
done

if [[ ! -x "$CHROME_BIN" ]]; then
    echo "Bundled Chromium not found at:" >&2
    echo "  $CHROME_BIN" >&2
    echo "Install the non-slim VPinFE linux-x64 package." >&2
    exit 1
fi

"$CHROME_BIN" \
    --app='http://127.0.0.1:8000/app/table' \
    --window-name=vpinfe-table \
    --class=vpinfe-table \
    --window-position=0,0 \
    --window-size=1920,1080 \
    --user-data-dir=/tmp/vpinfe-manual \
    --kiosk \
    --start-maximized \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-background-networking \
    --disable-component-update \
    --disable-default-apps \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --disable-background-media-suspend \
    --disable-features=CalculateNativeWindowOcclusion,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies \
    --disable-hang-monitor \
    --disable-ipc-flooding-protection \
    --disable-gpu-process-crash-limit \
    --ignore-gpu-blocklist \
    --no-sandbox \
    --disable-gpu-sandbox \
    --autoplay-policy=no-user-gesture-required \
    --test-type \
    --ozone-platform=x11 &

CHROME_PID=$!

wait "$CHROME_PID"
