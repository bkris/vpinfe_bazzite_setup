# Shared VPinFE workarounds, sourced by run_vpinfe.sh and run_vpinfe_gamepad.sh.
# Both are idempotent and re-apply themselves after a VPinFE upgrade.

ROOT="${ROOT:-$HOME/vpinball}"
VPINFE_DIR="$ROOT/vpinfe"
VPINFE_BIN="$VPINFE_DIR/vpinfe"
CHROME_BIN="$VPINFE_DIR/_internal/chromium/linux/chrome/chrome"
GAMEPAD_PAGE="$VPINFE_DIR/_internal/web/diag/gamepad.html"
GAMEPAD_PATCH="$ROOT/vpinfe-patches/gamepad.html"

# VPinFE is a PyInstaller bundle: the Chromium it spawns inherits
# LD_LIBRARY_PATH=_internal and loads the bundled Ubuntu libs instead of the
# system ones. Input is dead and Chromium aborts in NSS init (no
# libsoftokn3/libfreebl3 in _internal). Swap in a wrapper that restores the
# original environment.
install_chrome_wrapper() {
    if [[ -e "$CHROME_BIN.bin" ]]; then
        return
    fi
    if [[ ! -f "$CHROME_BIN" ]]; then
        echo "Bundled Chromium not found at $CHROME_BIN (slim VPinFE build?)." >&2
        return
    fi
    if [[ "$(head -c 4 "$CHROME_BIN" | tr -d '\0')" != $'\x7fELF' ]]; then
        echo "Unexpected Chromium binary at $CHROME_BIN, not wrapping." >&2
        return
    fi
    mv "$CHROME_BIN" "$CHROME_BIN.bin"
    cat > "$CHROME_BIN" <<'EOF'
#!/usr/bin/env bash
# Installed by vpinfe_fixes.sh: drop PyInstaller's LD_LIBRARY_PATH.
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
# original as .orig.
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
stop_stale_vpinfe() {
    pkill -f "$VPINFE_BIN" 2>/dev/null || true
    pkill -f "$CHROME_BIN" 2>/dev/null || true
    sleep 1
}
