# Exports release builds on Windows. Install export templates once from the
# editor (Editor > Manage Export Templates) or let Godot prompt you.
# Usage: .\tools\build.ps1 [windows|linux|all]
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$What = if ($args.Count -gt 0) { $args[0] } else { "all" }
New-Item -ItemType Directory -Force -Path build\windows, build\linux | Out-Null
if ($What -eq "windows" -or $What -eq "all") {
    & "$Root\tools\godot.ps1" --headless --path . --export-release "Windows Desktop" "build/windows/ChooseAPlanet.exe"
}
if ($What -eq "linux" -or $What -eq "all") {
    & "$Root\tools\godot.ps1" --headless --path . --export-release "Linux" "build/linux/ChooseAPlanet.x86_64"
}
Get-ChildItem build -Recurse
