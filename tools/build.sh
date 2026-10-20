#!/usr/bin/env bash
# Exports release builds with the pinned Godot. Installs the matching export
# templates on first use (large download, ~1 GB).
# Usage: tools/build.sh [windows|linux|all]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_VERSION="4.7.2-stable"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable"
if [[ ! -f "$TEMPLATE_DIR/linux_release.x86_64" || ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ]]; then
  echo "Installing export templates into $TEMPLATE_DIR" >&2
  mkdir -p "$TEMPLATE_DIR" export_templates
  curl -fL -o export_templates/templates.tpz "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
  (cd export_templates && unzip -oq templates.tpz && cp templates/* "$TEMPLATE_DIR/")
fi
tools/ensure_import.sh
what="${1:-all}"
mkdir -p build/windows build/linux
if [[ "$what" == "windows" || "$what" == "all" ]]; then
  tools/godot.sh --headless --path . --export-release "Windows Desktop" "build/windows/ChooseAPlanet.exe"
fi
if [[ "$what" == "linux" || "$what" == "all" ]]; then
  tools/godot.sh --headless --path . --export-release "Linux" "build/linux/ChooseAPlanet.x86_64"
fi
ls -la build/*/
