#!/usr/bin/env bash
# One-line capture of Luz (run, skid, turn) in the Greece level plus close-ups:
#   tools/capture/capture.sh <out_dir> [~/Desktop/Caminar.mov]
# Needs ffmpeg and a python with pillow + numpy (PYTHON=/path/to/venv/bin/python).
# Movie Maker records at the window size, so a temporary override.cfg (removed on
# exit) asks for 1280x720 instead of the 640x360 base viewport.
set -euo pipefail
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
printf '[display]\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\n' > "$ROOT/override.cfg"
trap 'rm -f "$ROOT/override.cfg"' EXIT
LUZ_CAPTURE_OUT="$OUT" "$GODOT" --path "$ROOT" --write-movie "$OUT/run.avi" --fixed-fps 60 res://tools/capture/luz_capture.tscn
"${PYTHON:-python3}" "$ROOT/tools/capture/extract.py" "$OUT" ${2:+"$2"}
