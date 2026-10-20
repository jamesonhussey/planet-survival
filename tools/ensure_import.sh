#!/usr/bin/env bash
# Re-imports the project when the global class cache is missing or older than
# any script, so `class_name` lookups resolve in headless runs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CACHE=".godot/global_script_class_cache.cfg"
needs=0
if [[ ! -f "$CACHE" || "${FORCE_IMPORT:-0}" == "1" ]]; then
  needs=1
elif [[ -n "$(find src tests -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]]; then
  needs=1
fi
if [[ $needs -eq 1 ]]; then
  echo "[import] refreshing project import/class cache" >&2
  tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
fi
