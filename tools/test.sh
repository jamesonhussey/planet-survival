#!/usr/bin/env bash
# Runs the unit tests headless. Usage: tools/test.sh [--filter=substring]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tools/ensure_import.sh
exec tools/godot.sh --headless --path . -s res://tests/run_tests.gd -- "$@"
