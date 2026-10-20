#!/usr/bin/env bash
# Downloads the GodotSteam GDExtension into addons/godotsteam/ (gitignored).
# The game runs without it (SteamBridge becomes a no-op); exports for Steam
# need it present at export time. Usage:
#   GODOTSTEAM_URL=https://github.com/GodotSteam/GodotSteam/releases/download/<tag>/<gdextension zip> tools/get_godotsteam.sh
# Find the asset for the pinned Godot version on
# https://github.com/GodotSteam/GodotSteam/releases (GDExtension zip, "g4.x"
# must match the engine minor version in CLAUDE.md). License: MIT (LICENSES.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# Asset names change per release (they encode the Godot and Steamworks SDK
# versions), so the URL is not guessed: pass it explicitly.
URL="${GODOTSTEAM_URL:-}"
if [[ -z "$URL" ]]; then
  cat >&2 <<MSG
[godotsteam] GODOTSTEAM_URL is not set.
  1. Open https://github.com/GodotSteam/GodotSteam/releases (latest 4.x tag, e.g. v4.23.2)
  2. Copy the link of the GDExtension zip whose name matches Godot 4.7 (the "g4.7" part)
  3. GODOTSTEAM_URL=<that link> tools/get_godotsteam.sh
MSG
  exit 1
fi
DEST="addons/godotsteam"
if [[ -f "$DEST/godotsteam.gdextension" ]]; then
  echo "[godotsteam] already present in $DEST"
  exit 0
fi
TMP="$(mktemp -d)"
echo "[godotsteam] downloading $URL"
if ! curl -fsSL -o "$TMP/gs.zip" "$URL"; then
  echo "[godotsteam] download failed. Open https://github.com/GodotSteam/GodotSteam/releases, copy the GDExtension zip URL for Godot 4.7 and rerun with GODOTSTEAM_URL=<url>." >&2
  exit 1
fi
mkdir -p "$DEST"
unzip -q -o "$TMP/gs.zip" -d "$TMP/x"
# The zip holds addons/godotsteam/...; copy whatever layout it has into place.
if [[ -d "$TMP/x/addons/godotsteam" ]]; then
  cp -R "$TMP/x/addons/godotsteam/." "$DEST/"
else
  cp -R "$TMP/x/." "$DEST/"
fi
rm -rf "$TMP"
echo "[godotsteam] installed into $DEST. Put steam_appid.txt (your app id) next to the executable for local testing; see docs/RELEASE.md."
