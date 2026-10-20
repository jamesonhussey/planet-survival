# Runs the unit tests headless on Windows. Usage: .\tools\test.ps1 [--filter=substring]
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path ".godot\global_script_class_cache.cfg")) {
    & "$Root\tools\godot.ps1" --headless --path . --import | Out-Null
}
& "$Root\tools\godot.ps1" --headless --path . -s res://tests/run_tests.gd -- @args
exit $LASTEXITCODE
