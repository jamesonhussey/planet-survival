#!/usr/bin/env bash
# Dumps the official class reference of the *pinned* Godot version to
# docs/godot-classes/ (gitignored). Grep it instead of guessing APIs:
#   grep -o '<method name="[a-z_]*"' docs/godot-classes/doc/classes/SubViewport.xml
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p docs/godot-classes
tools/godot.sh --headless --doctool docs/godot-classes --no-docbase >/dev/null 2>&1 || true
echo "Class reference written to docs/godot-classes/doc/classes ($(ls docs/godot-classes/doc/classes | wc -l) files)"
