#!/usr/bin/env bash
# Renders the game for a few seconds under a virtual display (Xvfb + Mesa) and
# saves screenshots to screenshots/. Linux only; used to judge the PS1 look
# without a GPU. Usage: tools/screenshot.sh [planet_id] [frames]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PLANET="${1:-04}"
FRAMES="${2:-120}"
mkdir -p screenshots
if ! command -v xvfb-run >/dev/null; then
  echo "xvfb-run not found; install xvfb or run the game normally with --screenshot." >&2
  exit 1
fi
xvfb-run -a -s "-screen 0 1280x720x24" \
  tools/godot.sh --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 -- --screenshot --planet="$PLANET" --frames="$FRAMES"
ls -la screenshots
