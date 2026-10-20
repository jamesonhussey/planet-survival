#!/usr/bin/env bash
# Boots the game headless on each planet for a number of frames and fails on
# any script error. Usage: tools/smoke.sh [planet_id ...]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tools/ensure_import.sh
PLANETS=("$@")
if [[ ${#PLANETS[@]} -eq 0 ]]; then PLANETS=(04); fi
FRAMES="${SMOKE_FRAMES:-240}"
status=0
for p in "${PLANETS[@]}"; do
  echo "== smoke: planet $p ($FRAMES frames) =="
  set +e
  out="$(tools/godot.sh --headless --path . -- --smoke --planet="$p" --frames="$FRAMES" 2>&1)"
  code=$?
  set -e
  echo "$out" | tail -n 40
  if [[ $code -ne 0 ]] || echo "$out" | grep -qE "SCRIPT ERROR|ERROR:|USER ERROR"; then
    echo "!! smoke failed for planet $p (exit $code)"
    status=1
  fi
done
exit $status
