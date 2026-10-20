# Runs the pinned Godot version on Windows, downloading it on first use.
# Usage: .\tools\godot.ps1 [godot args...]
# Uses the *_console.exe build so test output shows in the terminal.
# Override with $env:GODOT_BIN if you already have 4.7.2 installed.
$ErrorActionPreference = "Stop"
$GodotVersion = "4.7.2-stable"
$Root = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $Root ".godot-bin"
$File = "Godot_v${GodotVersion}_win64.exe"
$Exe = Join-Path $BinDir "Godot_v${GodotVersion}_win64_console.exe"

if ($env:GODOT_BIN) {
    & $env:GODOT_BIN @args
    exit $LASTEXITCODE
}

if (-not (Test-Path $Exe)) {
    $Url = "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion/$File.zip"
    Write-Host "Downloading Godot $GodotVersion from $Url"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $Zip = Join-Path $BinDir "godot.zip"
    Invoke-WebRequest -Uri $Url -OutFile $Zip
    Expand-Archive -Path $Zip -DestinationPath $BinDir -Force
    Remove-Item $Zip
}

& $Exe @args
exit $LASTEXITCODE
