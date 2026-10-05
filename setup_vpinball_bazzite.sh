#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Bazzite VPX + VPinFE installer/setup script
# Based on the working setup from this troubleshooting session.
#
# Default expected downloads:
#   ~/Downloads/VPinballX_GL-10.8.0-2052-5a81d4e-Release-linux-x64.zip
#     (this ZIP may itself contain VPinballX_GL-...-linux-x64.tar.gz)
#   ~/Downloads/vpinfe-v2.6.5-linux-x64.zip
#
# Archive layouts are normalized automatically, including packages whose
# files are all contained in one additional top-level directory.
#
# The non-slim VPinFE package is preferred because it bundles Chromium.
# ============================================================

VPINBALL_ROOT="${VPINBALL_ROOT:-$HOME/vpinball}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/Downloads}"

VPX_DIR="$VPINBALL_ROOT/vpx"
VPINFE_DIR="$VPINBALL_ROOT/vpinfe"
TABLES_DIR="$VPINBALL_ROOT/tables"
ROMS_DIR="$VPINBALL_ROOT/roms"
PUPVIDEOS_DIR="$VPINBALL_ROOT/pupvideos"
LOCAL_LIB_DIR="$HOME/.local/lib"

VPX_ARCHIVE="${VPX_ARCHIVE:-${VPX_ZIP:-}}"
VPINFE_ARCHIVE="${VPINFE_ARCHIVE:-${VPINFE_ZIP:-}}"

log() {
    printf '\n\033[1;32m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

die() {
    printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

find_archive() {
    local pattern="$1"
    find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "$pattern" -print 2>/dev/null | sort | tail -n 1
}

extract_archive() {
    local archive="$1"
    local destination="$2"

    mkdir -p "$destination"

    case "$archive" in
        *.zip)
            unzip -o "$archive" -d "$destination" >/dev/null
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$destination"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$destination"
            ;;
        *.tar)
            tar -xf "$archive" -C "$destination"
            ;;
        *)
            die "Unsupported archive type: $archive"
            ;;
    esac
}

# Extract nested archives found inside a staging directory.
# This specifically handles the VPX distribution layout where the downloaded
# ZIP contains VPinballX_...linux-x64.tar.gz, but it is generic enough for
# one or more nested tar/zip archives.
extract_nested_archives() {
    local staging="$1"
    local pass archive nested_dir found

    for pass in 1 2 3; do
        found=0

        while IFS= read -r -d '' archive; do
            # Do not repeatedly extract an archive we already processed.
            if [[ -e "${archive}.extracted" ]]; then
                continue
            fi

            log "Found nested archive: $archive"
            nested_dir="${archive}.contents"
            mkdir -p "$nested_dir"
            extract_archive "$archive" "$nested_dir"
            touch "${archive}.extracted"
            found=1
        done < <(
            find "$staging" -type f \( \
                -name '*.tar.gz' -o \
                -name '*.tgz' -o \
                -name '*.tar.xz' -o \
                -name '*.tar' -o \
                -name '*.zip' \
            \) -print0
        )

        [[ "$found" -eq 0 ]] && break
    done
}

install_payload_from_binary() {
    local staging="$1"
    local binary_name="$2"
    local destination="$3"
    local binary source_root

    binary="$(find "$staging" -type f -name "$binary_name" -print | head -n 1 || true)"
    [[ -n "$binary" ]] || return 1

    # The folder containing the executable is treated as the application root.
    # This automatically strips an optional single "main folder" created by
    # either the ZIP or TAR archive while preserving all sibling resources.
    source_root="$(dirname "$binary")"

    log "Detected application root: $source_root"

    rm -rf "$destination"
    mkdir -p "$destination"
    cp -a "$source_root"/. "$destination"/
}

log "Creating directory structure"
mkdir -p \
    "$VPX_DIR" \
    "$VPINFE_DIR" \
    "$TABLES_DIR" \
    "$ROMS_DIR" \
    "$PUPVIDEOS_DIR" \
    "$LOCAL_LIB_DIR"

command -v unzip >/dev/null 2>&1 || die "'unzip' is required but was not found."
command -v tar >/dev/null 2>&1 || die "'tar' is required but was not found."

# ------------------------------------------------------------
# Locate archives
# ------------------------------------------------------------

if [[ -z "$VPX_ARCHIVE" ]]; then
    # Prefer the ZIP supplied by the user, but direct tar.gz releases also work.
    VPX_ARCHIVE="$(find_archive 'VPinballX_GL-*-linux-x64.zip' || true)"
    if [[ -z "$VPX_ARCHIVE" ]]; then
        VPX_ARCHIVE="$(find_archive 'VPinballX_GL-*-linux-x64.tar.gz' || true)"
    fi
fi

if [[ -z "$VPINFE_ARCHIVE" ]]; then
    # Prefer the full package over the slim package.
    VPINFE_ARCHIVE="$(find_archive 'vpinfe-v*-linux-x64.zip' || true)"
    if [[ -z "$VPINFE_ARCHIVE" ]]; then
        VPINFE_ARCHIVE="$(find_archive 'vpinfe-v*-linux-x64-slim.zip' || true)"
    fi
fi

[[ -n "$VPX_ARCHIVE" && -f "$VPX_ARCHIVE" ]] \
    || die "VPX archive not found in $DOWNLOAD_DIR. Set VPX_ARCHIVE=/full/path/to/archive and run again."

[[ -n "$VPINFE_ARCHIVE" && -f "$VPINFE_ARCHIVE" ]] \
    || die "VPinFE archive not found in $DOWNLOAD_DIR. Set VPINFE_ARCHIVE=/full/path/to/archive and run again."

log "Using VPX archive: $VPX_ARCHIVE"
log "Using VPinFE archive: $VPINFE_ARCHIVE"

if [[ "$VPINFE_ARCHIVE" == *-slim.zip ]]; then
    warn "You are using the slim VPinFE build. The full linux-x64 build is recommended because it bundles Chromium."
fi

# ------------------------------------------------------------
# Extract VPX
# ------------------------------------------------------------

log "Extracting Visual Pinball X"

VPX_STAGE="$(mktemp -d)"
trap 'rm -rf "${VPX_STAGE:-}" "${VPINFE_STAGE:-}"' EXIT

extract_archive "$VPX_ARCHIVE" "$VPX_STAGE"

# The VPX ZIP used in this setup contains another archive:
#   VPinballX_GL-...-linux-x64.tar.gz
# Extract it (and tolerate an additional wrapper directory if present).
if ! find "$VPX_STAGE" -type f -name 'VPinballX_GL' -print -quit | grep -q .; then
    extract_nested_archives "$VPX_STAGE"
fi

if ! install_payload_from_binary "$VPX_STAGE" "VPinballX_GL" "$VPX_DIR"; then
    warn "VPX staging tree:"
    find "$VPX_STAGE" -maxdepth 4 -printf '%y %p\n' >&2 || true
    die "Could not find VPinballX_GL after extracting the VPX archive and nested archives."
fi

VPX_BIN="$VPX_DIR/VPinballX_GL"
chmod +x "$VPX_BIN"

log "Normalized VPX install structure:"
find "$VPX_DIR" -maxdepth 2 -printf '  %P\n' | sed '/^  $/d' | head -n 80

# ------------------------------------------------------------
# Bazzite/Fedora libbz2 compatibility workaround
# ------------------------------------------------------------

log "Configuring local libbz2 compatibility"

if [[ -e /usr/lib64/libbz2.so.1 ]]; then
    ln -sfn /usr/lib64/libbz2.so.1 "$LOCAL_LIB_DIR/libbz2.so.1.0"
    log "Created: $LOCAL_LIB_DIR/libbz2.so.1.0 -> /usr/lib64/libbz2.so.1"
elif [[ -e /usr/lib/libbz2.so.1 ]]; then
    ln -sfn /usr/lib/libbz2.so.1 "$LOCAL_LIB_DIR/libbz2.so.1.0"
    log "Created: $LOCAL_LIB_DIR/libbz2.so.1.0 -> /usr/lib/libbz2.so.1"
else
    warn "libbz2.so.1 was not found. VPX may fail with a missing libbz2.so.1.0 error."
fi

# ------------------------------------------------------------
# Extract VPinFE
# ------------------------------------------------------------

log "Extracting VPinFE"

VPINFE_STAGE="$(mktemp -d)"
extract_archive "$VPINFE_ARCHIVE" "$VPINFE_STAGE"

# Usually VPinFE is directly inside the ZIP, but this also handles a ZIP
# containing one top-level application directory.
if ! install_payload_from_binary "$VPINFE_STAGE" "vpinfe" "$VPINFE_DIR"; then
    # Be tolerant of a nested archive layout as well.
    extract_nested_archives "$VPINFE_STAGE"

    if ! install_payload_from_binary "$VPINFE_STAGE" "vpinfe" "$VPINFE_DIR"; then
        warn "VPinFE staging tree:"
        find "$VPINFE_STAGE" -maxdepth 4 -printf '%y %p\n' >&2 || true
        die "Could not find the vpinfe executable after extraction."
    fi
fi

VPINFE_BIN="$VPINFE_DIR/vpinfe"
chmod +x "$VPINFE_BIN"

CHROME_BIN="$VPINFE_DIR/_internal/chromium/linux/chrome/chrome"
if [[ -f "$CHROME_BIN" ]]; then
    chmod +x "$CHROME_BIN"
else
    warn "Bundled Chromium was not found at $CHROME_BIN. This normally means the VPinFE slim build was installed."
fi

# ------------------------------------------------------------
# Chromium wrapper
#
# VPinFE is a PyInstaller bundle: any Chromium it spawns itself inherits
# LD_LIBRARY_PATH=_internal and loads the bundled Ubuntu libs instead of the
# system ones. Input is dead and Chromium aborts in NSS init after ~17 s
# (exit -6; _internal has no libsoftokn3/libfreebl3). Replace the binary with
# a wrapper that restores the original environment. run_vpinfe_gamepad.sh
# re-applies this automatically after a VPinFE upgrade.
# ------------------------------------------------------------

if [[ -f "$CHROME_BIN" && ! -e "$CHROME_BIN.bin" ]]; then
    log "Installing Chromium environment wrapper"
    mv "$CHROME_BIN" "$CHROME_BIN.bin"
    cat > "$CHROME_BIN" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# Installed by run_vpinfe_gamepad.sh: drop PyInstaller's LD_LIBRARY_PATH.
if [[ -n "${LD_LIBRARY_PATH_ORIG:-}" ]]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH_ORIG"
else
    unset LD_LIBRARY_PATH
fi
unset LD_LIBRARY_PATH_ORIG
exec "$(dirname "$(readlink -f "$0")")/chrome.bin" --ozone-platform=x11 "$@"
WRAPPER_EOF
    chmod +x "$CHROME_BIN"
fi

# ------------------------------------------------------------
# Patched gamepad page
#
# Upstream web/diag/gamepad.html only reads navigator.getGamepads()[0]. With
# Steam running, an idle virtual "Microsoft X-Box 360 pad" appears next to
# the real controller and can take slot 0, so presses are ignored. Generate
# a patched copy that follows whichever pad is pressed; run_vpinfe_gamepad.sh
# installs it (keeping the original as gamepad.html.orig).
# ------------------------------------------------------------

GAMEPAD_PAGE="$VPINFE_DIR/_internal/web/diag/gamepad.html"
GAMEPAD_PATCH="$VPINBALL_ROOT/vpinfe-patches/gamepad.html"

if [[ -f "$GAMEPAD_PAGE" ]] && command -v python3 >/dev/null 2>&1; then
    log "Generating patched gamepad page"
    mkdir -p "$(dirname "$GAMEPAD_PATCH")"
    python3 - "$GAMEPAD_PAGE" "$GAMEPAD_PATCH" <<'PY_EOF' || warn "Upstream gamepad.html changed; the stock page will be used."
import sys

src, dst = sys.argv[1], sys.argv[2]
page = open(src, encoding="utf-8").read()

replacements = [
    (
        '  <div class="subtitle">Press ESC to exit</div>',
        '  <div class="subtitle"><span id="padInfo">No gamepad detected yet. Press a controller button.</span> — Press ESC to exit</div>',
    ),
    (
        '    let lastPressedButtons = new Set();\n',
        '    let lastPressedButtons = new Set();\n'
        '    let activePadIndex = null;\n'
        '    const padInfo = document.getElementById("padInfo");\n',
    ),
    (
        '      const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];\n'
        '\n'
        '      const gp = gamepads[0];\n'
        '      if (!gp) {\n'
        '        requestAnimationFrame(updateGamepadStatus);\n'
        '        return;\n'
        '      }\n',
        '      const pads = Array.from(navigator.getGamepads ? navigator.getGamepads() : []).filter(Boolean);\n'
        '\n'
        '      // Slot 0 isn\'t necessarily the physical controller (e.g. Steam Input adds\n'
        '      // an idle virtual pad), so follow whichever pad is being pressed.\n'
        '      const gp = pads.find(p => p.buttons.some(b => b.pressed))\n'
        '        || pads.find(p => p.index === activePadIndex)\n'
        '        || pads[0];\n'
        '      if (!gp) {\n'
        '        requestAnimationFrame(updateGamepadStatus);\n'
        '        return;\n'
        '      }\n'
        '\n'
        '      if (gp.index !== activePadIndex) {\n'
        '        activePadIndex = gp.index;\n'
        '        lastPressedButtons = new Set();\n'
        '        padInfo.textContent = `Gamepad: ${gp.id} (#${gp.index})`;\n'
        '      }\n',
    ),
    (
        '    window.addEventListener("gamepadconnected", () => {\n'
        '      console.log("Gamepad connected");\n'
        '      updateGamepadStatus();\n'
        '    });\n'
        '\n'
        '    window.addEventListener("gamepaddisconnected", () => {\n'
        '      console.log("Gamepad disconnected");\n'
        '    });',
        '    window.addEventListener("gamepadconnected", (e) => {\n'
        '      console.log(`Gamepad connected: ${e.gamepad.id} (#${e.gamepad.index})`);\n'
        '    });\n'
        '\n'
        '    window.addEventListener("gamepaddisconnected", (e) => {\n'
        '      console.log(`Gamepad disconnected: ${e.gamepad.id} (#${e.gamepad.index})`);\n'
        '      if (e.gamepad.index === activePadIndex) activePadIndex = null;\n'
        '    });\n'
        '\n'
        '    requestAnimationFrame(updateGamepadStatus);',
    ),
]

for old, new in replacements:
    if page.count(old) != 1:
        sys.exit(f"gamepad.html: expected snippet not found: {old.strip().splitlines()[0]}")
    page = page.replace(old, new)

open(dst, "w", encoding="utf-8").write(page)
PY_EOF
else
    warn "gamepad.html or python3 not found; the stock gamepad page will be used."
fi

log "Normalized VPinFE install structure:"
find "$VPINFE_DIR" -maxdepth 2 -printf '  %P\n' | sed '/^  $/d' | head -n 80

# ------------------------------------------------------------
# VPX launcher
# ------------------------------------------------------------

log "Creating VPX launcher"

cat > "$VPINBALL_ROOT/run_vpx.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

VPX_DIR="$HOME/vpinball/vpx"

export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$VPX_DIR"
exec ./VPinballX_GL "$@"
EOF

chmod +x "$VPINBALL_ROOT/run_vpx.sh"

# ------------------------------------------------------------
# VPinFE stable Bazzite launcher
#
# VPinFE runs --headless and Chromium is launched from bash, so it gets a
# clean environment (no PyInstaller LD_LIBRARY_PATH, see the wrapper above)
# and is forced through XWayland.
# ------------------------------------------------------------

log "Creating VPinFE launcher"

cat > "$VPINBALL_ROOT/run_vpinfe.sh" <<'EOF'
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
EOF

chmod +x "$VPINBALL_ROOT/run_vpinfe.sh"

# ------------------------------------------------------------
# Gamepad mapper launcher
# ------------------------------------------------------------

log "Creating VPinFE gamepad mapper launcher"

cat > "$VPINBALL_ROOT/run_vpinfe_gamepad.sh" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/vpinball"
VPINFE_DIR="$ROOT/vpinfe"
VPINFE_BIN="$VPINFE_DIR/vpinfe"
CHROME_BIN="$VPINFE_DIR/_internal/chromium/linux/chrome/chrome"
GAMEPAD_PAGE="$VPINFE_DIR/_internal/web/diag/gamepad.html"
GAMEPAD_PATCH="$ROOT/vpinfe-patches/gamepad.html"

# VPinFE is a PyInstaller bundle: the Chromium it spawns inherits
# LD_LIBRARY_PATH=_internal and loads the bundled Ubuntu libs instead of the
# system ones. Input is dead and Chromium aborts in NSS init (no
# libsoftokn3/libfreebl3 in _internal). Swap in a wrapper that restores the
# original environment. Re-applied automatically after a VPinFE upgrade.
install_chrome_wrapper() {
    if [[ -e "$CHROME_BIN.bin" ]]; then
        return
    fi
    if [[ "$(head -c 4 "$CHROME_BIN" | tr -d '\0')" != $'\x7fELF' ]]; then
        echo "Unexpected Chromium binary at $CHROME_BIN, not wrapping." >&2
        return
    fi
    mv "$CHROME_BIN" "$CHROME_BIN.bin"
    cat > "$CHROME_BIN" <<'EOF'
#!/usr/bin/env bash
# Installed by run_vpinfe_gamepad.sh: drop PyInstaller's LD_LIBRARY_PATH.
if [[ -n "${LD_LIBRARY_PATH_ORIG:-}" ]]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH_ORIG"
else
    unset LD_LIBRARY_PATH
fi
unset LD_LIBRARY_PATH_ORIG
exec "$(dirname "$(readlink -f "$0")")/chrome.bin" --ozone-platform=x11 "$@"
EOF
    chmod +x "$CHROME_BIN"
}

# Upstream gamepad.html only reads navigator.getGamepads()[0]. With Steam
# running, slot 0 can be Steam's idle virtual "X-Box 360 pad", so presses on
# the real controller are ignored. Swap in the patched page, keeping the
# original as .orig. Re-applied automatically after a VPinFE upgrade.
patch_gamepad_page() {
    if [[ ! -f "$GAMEPAD_PATCH" ]]; then
        echo "No patched gamepad page at $GAMEPAD_PATCH, using the stock one." >&2
        return
    fi
    if [[ -e "$GAMEPAD_PAGE.orig" ]]; then
        cmp -s "$GAMEPAD_PATCH" "$GAMEPAD_PAGE" || cp "$GAMEPAD_PATCH" "$GAMEPAD_PAGE"
        return
    fi
    if ! grep -q 'const gp = gamepads\[0\];' "$GAMEPAD_PAGE"; then
        echo "Upstream gamepad.html changed, not patching it." >&2
        return
    fi
    cp "$GAMEPAD_PAGE" "$GAMEPAD_PAGE.orig"
    cp "$GAMEPAD_PATCH" "$GAMEPAD_PAGE"
}

# Avoid stale copies occupying ports 8000-8002.
pkill -f "$VPINFE_BIN" 2>/dev/null || true
pkill -f "$CHROME_BIN" 2>/dev/null || true
sleep 1

install_chrome_wrapper
patch_gamepad_page

cd "$VPINFE_DIR"

# --gamepadtest registers the 'gamepad' window API and launches its own
# Chromium on the gamepad page. Opening that page manually against a
# --headless instance doesn't work: only the 'table' API is registered, so
# the page's WebSocket calls never get answered and the UI stays frozen.
exec "$VPINFE_BIN" --gamepadtest
LAUNCHER_EOF

chmod +x "$VPINBALL_ROOT/run_vpinfe_gamepad.sh"

# ------------------------------------------------------------
# Stop helper
# ------------------------------------------------------------

log "Creating stop helper"

cat > "$VPINBALL_ROOT/stop_vpinfe.sh" <<'EOF'
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
EOF

chmod +x "$VPINBALL_ROOT/stop_vpinfe.sh"

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

log "Verifying VPX dependencies"

export LD_LIBRARY_PATH="$LOCAL_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if missing="$(ldd "$VPX_DIR/VPinballX_GL" 2>/dev/null | grep 'not found' || true)" && [[ -n "$missing" ]]; then
    warn "VPX still has missing libraries:"
    printf '%s\n' "$missing"
else
    log "No missing VPX shared libraries detected by ldd."
fi

cat <<EOF

============================================================
Setup complete
============================================================

Directories:
  VPX:       $VPX_DIR
  VPinFE:    $VPINFE_DIR
  Tables:    $TABLES_DIR
  ROMs:      $ROMS_DIR
  PUPVideos: $PUPVIDEOS_DIR

Commands:

  Test VPX:
    $VPINBALL_ROOT/run_vpx.sh -h

  Start VPinFE:
    $VPINBALL_ROOT/run_vpinfe.sh

  Open VPinFE Manager:
    http://localhost:8001

  Configure controller:
    $VPINBALL_ROOT/run_vpinfe_gamepad.sh

  Stop VPinFE:
    $VPINBALL_ROOT/stop_vpinfe.sh

Useful VPinFE paths:
  Config:
    $HOME/.config/vpinfe/vpinfe.ini

  VPX INI:
    $HOME/.vpinball/VPinballX.ini

Recommended VPinFE configuration:
  VPX executable (vpxbinpath):
    $VPINBALL_ROOT/run_vpx.sh

  Table directory:
    $TABLES_DIR

  VPX INI:
    $HOME/.vpinball/VPinballX.ini

NOTES:
  VPX needs the libbz2 compatibility path, so launch it through
  run_vpx.sh rather than calling VPinballX_GL directly.

  The bundled Chromium is wrapped (chrome -> chrome.bin) so it never
  inherits VPinFE's PyInstaller LD_LIBRARY_PATH. Otherwise it has dead
  input and crashes after ~17 s (exit -6).

  With Steam running, a virtual "Microsoft X-Box 360 pad" appears next
  to the real controller. The patched gamepad mapper follows whichever
  pad you press, and its subtitle shows which one is in use.

============================================================
EOF
