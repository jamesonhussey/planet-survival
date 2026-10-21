#!/usr/bin/env bash
# Runs the pinned Godot version, downloading it on first use.
# Usage: tools/godot.sh [godot args...]
# Override the binary with GODOT_BIN=/path/to/godot if you already have 4.7.2.
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/.godot-bin"

if [[ -n "${GODOT_BIN:-}" ]]; then
  exec "$GODOT_BIN" "$@"
fi

case "$(uname -s)" in
  Linux*)  FILE="Godot_v${GODOT_VERSION}_linux.x86_64"; EXE="$BIN_DIR/$FILE" ;;
  Darwin*) FILE="Godot_v${GODOT_VERSION}_macos.universal"; EXE="$BIN_DIR/Godot.app/Contents/MacOS/Godot" ;;
  MINGW*|MSYS*|CYGWIN*) FILE="Godot_v${GODOT_VERSION}_win64.exe"; EXE="$BIN_DIR/Godot_v${GODOT_VERSION}_win64_console.exe" ;;
  *) echo "Unsupported OS: $(uname -s). Set GODOT_BIN." >&2; exit 1 ;;
esac

if [[ ! -x "$EXE" ]]; then
  URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${FILE}.zip"
  echo "Downloading Godot ${GODOT_VERSION} from ${URL}" >&2
  mkdir -p "$BIN_DIR"
  curl -fsSL -o "$BIN_DIR/godot.zip" "$URL"
  (cd "$BIN_DIR" && unzip -oq godot.zip && rm -f godot.zip)
  chmod +x "$EXE" 2>/dev/null || true
fi

# Fresh clone or changed scripts: refresh .godot/ first so class_name resolves
# (same rule as tools/ensure_import.sh, inlined to avoid recursion).
project_run=0
case " $* " in
  *" --path "*) project_run=1 ;;
esac
case " $* " in
  *" --import "*|*" --doctool "*|*" -e "*) project_run=0 ;;
esac
if [[ $project_run -eq 1 && "${GODOT_NO_IMPORT:-0}" != "1" ]]; then
  CACHE="$ROOT/.godot/global_script_class_cache.cfg"
  needs=0
  if [[ ! -f "$CACHE" || "${FORCE_IMPORT:-0}" == "1" ]]; then
    needs=1
  elif [[ -n "$(find "$ROOT/src" "$ROOT/tests" -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]]; then
    needs=1
  fi
  if [[ $needs -eq 1 ]]; then
    echo "[import] refreshing project import/class cache (first run or scripts changed)" >&2
    GODOT_NO_IMPORT=1 "$EXE" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
  fi
fi

exec "$EXE" "$@"
