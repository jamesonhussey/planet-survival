#!/usr/bin/env bash
# Runs the unit tests headless. Usage: tools/test.sh [--filter=substring]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# First run (or CI) must import the project so class_name lookups resolve headless.
if [[ ! -f .godot/global_script_class_cache.cfg || "${FORCE_IMPORT:-0}" == "1" ]]; then
  tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
fi
exec tools/godot.sh --headless --path . -s res://tests/run_tests.gd -- "$@"
