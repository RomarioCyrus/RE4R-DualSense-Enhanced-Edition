<#
.SYNOPSIS
    Deploy the staged v1.0 release package from the release checkout into
    the RE4R game folder.

.DESCRIPTION
    Copies all files from the Nexus/Fluffy staging folder
    (built by tools\build_release_package.ps1) into the game folder,
    mapping the package layout to the game root:

        <staging>\reframework\  →  <game>\reframework\
        <staging>\DualSenseEnhanced\  →  <game>\DualSenseEnhanced\
        <staging>\setup_sounds.bat    →  <game>\setup_sounds.bat
        ... (README.txt, VERSION.txt, THIRD_PARTY_LICENSES.txt)

    modinfo.ini is NOT copied -- it is a Fluffy Mod Manager metadata
    file and does not belong in the game folder.

    sounds\ is handled carefully:
      - If the game folder already has extracted WAV files, they are left
        intact (user does not need to re-run setup_sounds.bat).
      - If sounds\ is empty or missing, the directory is created empty
        (user will need to run setup_sounds.bat once).

    Hard failures (exit 1):
      - re4.exe is running (DLL replacement would fail silently).
      - Staging folder missing or RELEASE_BUILD != true in the staged loader.
      - Any file fails hash verification after copy.

.PARAMETER GamePath
    Root of the RE4R install. Defaults to the Steam path on this machine.

.PARAMETER StagingPath
    Path to the assembled staging folder (the "Resident Evil 4 - DualSense
    Enhanced Edition" folder, not its parent). Defaults to the expected
    sibling "<dev checkout> - Release v1.0\release\v1.0\staging\<name>".
    Run tools\build_release_package.ps1 first if staging does not exist.

.EXAMPLE
    .\tools\deploy_release.ps1
    .\tools\deploy_release.ps1 -GamePath "<game-directory>"
#>
param(
    [string]$GamePath    = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4",
    [string]$StagingPath = ""
)

$ErrorActionPreference = "Stop"

$devRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $StagingPath) {
    $parent      = Split-Path $devRoot -Parent
    $devName     = Split-Path $devRoot -Leaf
    $releasePath = Join-Path $parent "$devName - Release v1.0"
    $pkgName     = "Resident Evil 4 - DualSense Enhanced Edition"
    $StagingPath = Join-Path $releasePath "release\v1.0\staging\$pkgName"
}

Write-Host "Staging : $StagingPath"
Write-Host "Game    : $GamePath"
Write-Host ""

# ── Pre-flight checks ──────────────────────────────────────────────────────────

if (-not (Test-Path $StagingPath)) {
    Write-Error "Staging folder not found: $StagingPath`nRun tools\build_release_package.ps1 first."
}

$stagedLoader = Join-Path $StagingPath "reframework\autorun\DualSenseEnhanced.lua"
if (-not (Test-Path $stagedLoader)) {
    Write-Error "Staged loader not found -- staging folder appears incomplete."
}
$loaderText = [System.IO.File]::ReadAllText($stagedLoader, [System.Text.Encoding]::UTF8)
if ($loaderText -notmatch "local RELEASE_BUILD = true") {
    Write-Error "Staged loader does not have RELEASE_BUILD = true.`nRebuild staging with tools\build_release_package.ps1."
}

if (-not (Test-Path $GamePath)) {
    Write-Error "Game folder not found: $GamePath"
}

$re4 = Get-Process re4 -ErrorAction SilentlyContinue
if ($re4) {
    Write-Error "re4.exe is running -- close the game before deploying (DLL replacement will silently fail while the process holds the files)."
}

# ── Files / dirs to skip in the staging folder ────────────────────────────────

# modinfo.ini: Fluffy MM metadata, not for the game folder.
# reframework\data\DualSenseEnhanced\sounds\: preserve user's extracted WAVs.

$soundsDst = Join-Path $GamePath "reframework\data\DualSenseEnhanced\sounds"
$soundsHasWavs = (Test-Path $soundsDst) -and
                 ((Get-ChildItem $soundsDst -Filter "*.wav" -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null)

if ($soundsHasWavs) {
    Write-Host "sounds\ has extracted WAVs -- will be preserved (no need to re-run setup_sounds.bat)." -ForegroundColor DarkGray
} else {
    Write-Host "sounds\ is empty or missing -- will be created empty. Run setup_sounds.bat once after deploy." -ForegroundColor Yellow
}
Write-Host ""

# ── Copy ──────────────────────────────────────────────────────────────────────

$copied     = 0
$skipped    = 0
$copyErrors = 0
$luaChanged = $false

Get-ChildItem -Path $StagingPath -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($StagingPath.Length).TrimStart('\')

    # Skip modinfo.ini (Fluffy MM metadata, not for game folder)
    if ($rel -eq "modinfo.ini") { $script:skipped++; return }

    # Skip sounds\ content -- preserve user's extracted WAVs
    if ($rel -like "reframework\data\DualSenseEnhanced\sounds\*") {
        $script:skipped++
        return
    }

    $dst = Join-Path $GamePath $rel
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $dstHash = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash } else { "" }

    if ($srcHash -ne $dstHash) {
        try {
            Copy-Item -Path $_.FullName -Destination $dst -Force
            $script:copied++
            if ($_.Extension -eq ".lua") { $script:luaChanged = $true }
        } catch {
            Write-Host "ERROR: $rel -- $_" -ForegroundColor Red
            $script:copyErrors++
        }
    }
}

# Ensure sounds\ directory exists (empty is fine; setup_sounds.bat fills it)
if (-not (Test-Path $soundsDst)) {
    New-Item -ItemType Directory -Force -Path $soundsDst | Out-Null
}

Write-Host "Copied $copied changed file(s), skipped $skipped ($copyErrors errors)."

# ── Verify ────────────────────────────────────────────────────────────────────

$mismatches = @()
Get-ChildItem -Path $StagingPath -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($StagingPath.Length).TrimStart('\')
    if ($rel -eq "modinfo.ini") { return }
    if ($rel -like "reframework\data\DualSenseEnhanced\sounds\*") { return }

    $dst = Join-Path $GamePath $rel
    if (-not (Test-Path $dst)) {
        $script:mismatches += "MISSING: $rel"
    } else {
        $sh = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $dh = (Get-FileHash $dst -Algorithm SHA256).Hash
        if ($sh -ne $dh) { $script:mismatches += "MISMATCH: $rel" }
    }
}

if ($mismatches.Count -gt 0) {
    Write-Host ""
    $mismatches | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "`nDeploy FAILED -- verification error." -ForegroundColor Red
    exit 1
}

$total = (Get-ChildItem $StagingPath -Recurse -File |
    Where-Object { $_.Name -ne "modinfo.ini" -and $_.FullName -notlike "*\sounds\*.wav" } |
    Measure-Object).Count
Write-Host "All $total deployed files verified." -ForegroundColor Green

# ── What to do next ──────────────────────────────────────────────────────────

Write-Host ""
if ($copyErrors -gt 0) {
    Write-Host "WARNING: $copyErrors file(s) failed to copy -- check errors above." -ForegroundColor Red
} elseif ($copied -eq 0) {
    Write-Host "Nothing changed -- game folder already matches the release staging." -ForegroundColor DarkGray
} else {
    Write-Host "Release deployed successfully." -ForegroundColor Green
    if ($luaChanged) {
        Write-Host "Lua files updated -- press Reset Scripts in REFramework, or restart the game." -ForegroundColor Cyan
    }
    if (-not $soundsHasWavs) {
        Write-Host "Run setup_sounds.bat from the game folder to extract controller speaker audio." -ForegroundColor Yellow
    }
}
