# Runs the pinned Godot version on Windows, downloading it on first use.
# Usage: .\tools\godot.ps1 [godot args...]
# Uses the *_console.exe build so test output shows in the terminal.
# Override with $env:GODOT_BIN if you already have 4.7.2 installed.
# Before a project run it refreshes the import/class cache (.godot/) when it is
# missing or older than any script: a fresh clone has none, and without it
# every `class_name` fails to resolve ("Could not find type ...").
$ErrorActionPreference = "Stop"
$GodotVersion = "4.7.2-stable"
$Root = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $Root ".godot-bin"
$File = "Godot_v${GodotVersion}_win64.exe"
$Exe = Join-Path $BinDir "Godot_v${GodotVersion}_win64_console.exe"

if ($env:GODOT_BIN) {
    $Exe = $env:GODOT_BIN
} elseif (-not (Test-Path $Exe)) {
    $Url = "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion/$File.zip"
    Write-Host "Downloading Godot $GodotVersion from $Url"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $Zip = Join-Path $BinDir "godot.zip"
    Invoke-WebRequest -Uri $Url -OutFile $Zip
    Expand-Archive -Path $Zip -DestinationPath $BinDir -Force
    Remove-Item $Zip
}

function Test-NeedsImport {
    $Cache = Join-Path $Root ".godot\global_script_class_cache.cfg"
    if ($env:FORCE_IMPORT -eq "1") { return $true }
    if (-not (Test-Path $Cache)) { return $true }
    $CacheTime = (Get-Item $Cache).LastWriteTimeUtc
    foreach ($Dir in @("src", "tests")) {
        $P = Join-Path $Root $Dir
        if (-not (Test-Path $P)) { continue }
        $Newer = Get-ChildItem -Path $P -Recurse -Filter *.gd | Where-Object { $_.LastWriteTimeUtc -gt $CacheTime } | Select-Object -First 1
        if ($Newer) { return $true }
    }
    return $false
}

$IsProjectRun = ($args -contains "--path") -and -not ($args -contains "--import") -and -not ($args -contains "--doctool") -and -not ($args -contains "-e")
if ($IsProjectRun -and $env:GODOT_NO_IMPORT -ne "1" -and (Test-NeedsImport)) {
    Write-Host "[import] refreshing project import/class cache (first run or scripts changed)"
    # Through cmd so Godot's stderr chatter during import never trips $ErrorActionPreference.
    $env:GODOT_NO_IMPORT = "1"
    cmd /c "`"$Exe`" --headless --path `"$Root`" --import >nul 2>&1"
    $env:GODOT_NO_IMPORT = $null
}

# Windows PowerShell turns redirected stderr (e.g. a caller's 2>&1) into error
# records; under "Stop" Godot's first engine warning would abort the run.
$ErrorActionPreference = "Continue"
& $Exe @args
exit $LASTEXITCODE
