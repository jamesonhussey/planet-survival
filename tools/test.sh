#!/usr/bin/env bash
# Runs the unit tests headless. Usage: tools/test.sh [--filter=substring]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tools/ensure_import.sh
set +e
out="$(tools/godot.sh --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1)"
code=$?
set -e
echo "$out"
if echo "$out" | grep -q "SCRIPT ERROR"; then
  echo "!! script errors during tests"
  exit 1
fi
exit $code
