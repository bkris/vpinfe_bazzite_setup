#!/usr/bin/env bash
set -Eeuo pipefail

VPX_DIR="$HOME/vpinball/vpx"

export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$VPX_DIR"
exec ./VPinballX_GL "$@"
