# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is not a source tree and there is nothing to build, lint or test. It is a working Linux virtual-pinball install made of prebuilt binaries plus a few bash launcher scripts:

- `vpx/` holds the **Visual Pinball X 10.8 standalone** binary (`VPinballX_GL`, OpenGL build) and its bundled `.so` libs (PinMAME, dmdutil, serum, zedmd, altsound, SDL2, ffmpeg). It also has `scripts/` (the core VBScript `.vbs` files tables depend on) and `docs/`. CLI flags are in `vpx/docs/CommandLineParameters.txt`.
- `vpinfe/` holds **VPinFE**, a PyInstaller-frozen Python 3.14 frontend (NiceGUI/aiohttp). `vpinfe/vpinfe` is the executable. `vpinfe/_internal/` has its Python deps, its web UI (`web/`, `managerui/`) and a bundled Chromium (`_internal/chromium/linux/chrome/chrome`).
- `tables/` contains one folder per table, named `Title (Manufacturer Year)`. Each folder has the `.vpx` file, a `<folder name>.info` JSON file (IPDB/VPS metadata, ROM name, user stats, and VPX file hash, all written by VPinFE), and `medias/` (`table.mp4/png`, `bg.png`, `dmd.mp4/png`, `wheel.png`, `audio.mp3`, …).
- `roms/` is the PinMAME root (`PinMAMEPath`). PinMAME expects these subfolders: `roms/<rom>.zip`, `ini/<rom>.ini`, and likewise `nvram/`, `altcolor/`, `altsound/`. Only `ini/` exists right now.
- `pupvideos/` holds PinUP Player video packs (currently empty).

Don't edit the binaries or the files in `_internal/`. Changes normally go in the launcher scripts, the config files, or the table folders. There is one exception, the Chromium wrapper. Any Chromium that VPinFE spawns itself inherits PyInstaller's `LD_LIBRARY_PATH=_internal` and loads the bundled Ubuntu libs instead of the system ones. When that happens, input is dead and Chromium aborts in NSS init (exit -6). `run_vpinfe_gamepad.sh` works around this. It renames `_internal/chromium/linux/chrome/chrome` to `chrome.bin` and installs a bash wrapper as `chrome`, which restores `LD_LIBRARY_PATH_ORIG` and adds `--ozone-platform=x11`. The script reinstalls the wrapper automatically after a VPinFE upgrade.

The same script also copies `vpinfe-patches/gamepad.html` over `_internal/web/diag/gamepad.html`, keeping the original as `.orig`. The upstream page only reads `navigator.getGamepads()[0]`. With Steam running, it creates an idle virtual "Microsoft X-Box 360 pad 0" alongside the real Bluetooth "Xbox Wireless Controller", so slot 0 may not be the real pad. The patched page follows whichever pad is being pressed and shows its id. To change the page, edit `vpinfe-patches/gamepad.html`. The frontend itself (`#updateGamepads` in `web/common/vpinfe-core.js`) already reads every pad.

## Scripts

`./setup_vpinball_bazzite.sh` rebuilds the whole install from the archives in `~/Downloads`. It generates every launcher below, the Chromium wrapper and `vpinfe-patches/gamepad.html`, which it derives from the upstream page using an embedded `python3` patcher. Set `VPINBALL_ROOT=<dir>` to test it without touching the live install. **When you change a launcher or a workaround, update the matching heredoc in the setup script too.**

The launchers hardcode `ROOT=$HOME/vpinball`.

- `./run_vpx.sh [args]` puts `~/.local/lib` on `LD_LIBRARY_PATH` (it holds a host-provided `libbz2.so.1.0`), `cd`s into `vpx/` and execs `VPinballX_GL`. Example: `./run_vpx.sh -play "tables/<dir>/<file>.vpx"`. VPinFE launches tables through this script with `-play`.
- `./run_vpinfe.sh` kills stale VPinFE and Chromium processes, starts `vpinfe --headless`, then polls until port 8000 is up. It then launches the bundled Chromium itself in kiosk/app mode at `http://127.0.0.1:8000/app/table` (X11, 1920x1080, with autoplay and throttling disabled). It does this so VPinFE doesn't manage Chromium.
- `./run_vpinfe_gamepad.sh` kills stale processes, installs the Chromium wrapper (see above) and runs `vpinfe --gamepadtest`, which opens its own Chromium on the gamepad mapping page (`/web/diag/gamepad.html?window=gamepad`). Don't open that page manually against a `--headless` instance. Headless mode registers only the `table` window API, so the page's WebSocket calls never get answered and the page freezes.
- `./stop_vpinfe.sh` kills VPinFE and Chromium, then reports any remaining processes and whether ports 8000–8002 are free.

Ports: 8000 serves theme assets and the frontend, and 8001 serves the manager UI (set in `[Network]` in vpinfe.ini).

## Configuration (outside this directory)

- `~/.config/vpinfe/vpinfe.ini` is the VPinFE config. Key settings: `vpxbinpath` (points at `run_vpx.sh`), `tablerootdir` (points at `tables/`), `vpxinipath`, `theme` (themes live in `~/.config/vpinfe/themes/`), the display/orientation settings, and key bindings. Also in that directory: `vpinfe.log`, `collections.ini`, `vpsdb.json`, `roms.json`.
- `~/.vpinball/VPinballX.ini` is the VPX config. `[Standalone] PinMAMEPath` points at `roms/`, `[Player]` holds the display and render settings, and `[TableOverride]` holds per-table overrides. Logs go to `~/.vpinball/vpinball.log` and `altsound.log`. Controller mappings come from `~/.vpinball/gamecontrollerdb.txt`.

## Debugging

Check `~/.config/vpinfe/vpinfe.log` (launch commands are logged by `vpinfe.frontend.launch_service`) and `~/.vpinball/vpinball.log` (table load, script errors, and missing ROMs). A missing ROM usually means `roms/roms/<rom>.zip` doesn't exist. The expected ROM name is in the table's `.info` file under `Info.Rom`.
