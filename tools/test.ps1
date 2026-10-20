# Runs the unit tests headless on Windows. Usage: .\tools\test.ps1 [--filter=substring]
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Cache = ".godot\global_script_class_cache.cfg"
$Needs = -not (Test-Path $Cache)
if (-not $Needs) {
    $CacheTime = (Get-Item $Cache).LastWriteTime
    $Newer = Get-ChildItem -Path src, tests -Recurse -Filter *.gd | Where-Object { $_.LastWriteTime -gt $CacheTime } | Select-Object -First 1
    if ($Newer) { $Needs = $true }
}
if ($Needs) {
    Write-Host "[import] refreshing project import/class cache"
    & "$Root\tools\godot.ps1" --headless --path . --import | Out-Null
}
$Out = & "$Root\tools\godot.ps1" --headless --path . -s res://tests/run_tests.gd -- @args 2>&1 | Out-String
$Code = $LASTEXITCODE
Write-Host $Out
if ($Out -match "SCRIPT ERROR") { Write-Host "!! script errors during tests"; exit 1 }
exit $Code
