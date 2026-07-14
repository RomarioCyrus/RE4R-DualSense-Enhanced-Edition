<#
.SYNOPSIS
    Assembles the Nexus package staging folder (and optionally the ZIP)
    from the release checkout, following release/v1.0/RELEASE_MANIFEST.md.

.DESCRIPTION
    Run AFTER tools/sync_to_release.ps1 has brought the release checkout
    up to date. Reads only from the release checkout and writes the staged
    package to:

        <release checkout>\release\v1.0\staging\<package name>\

    The staged folder mirrors the game-root layout Fluffy Mod Manager
    installs from: modinfo.ini/README/VERSION/setup_sounds.bat/licenses at
    the root, runtime under reframework\, extractor tools under
    DualSenseEnhanced\tools\extract_sounds\.

    Hard failures (script exits non-zero):
      - a manifest-required file is missing in the release checkout;
      - the staged loader does not contain RELEASE_BUILD = true;
      - a forbidden file type (*.wav, *.pdb, *.log) ends up in staging.

.PARAMETER ReleasePath
    Path to the release checkout. Defaults to the sibling
    "<dev name> - Release v1.0" folder, same convention as sync_to_release.ps1.

.PARAMETER Zip
    Also compress the staged folder into
    <release checkout>\release\v1.0\<package name>-v<version>.zip.
    Do not pass this until the package-surface audit and the extractor test
    from the staged layout have both passed (see RELEASE_HANDOFF_2026-07-07.md).
#>

param(
    [string]$ReleasePath,
    [switch]$Zip
)

$ErrorActionPreference = "Stop"

$devRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ReleasePath) {
    $parent = Split-Path $devRoot -Parent
    $devName = Split-Path $devRoot -Leaf
    $ReleasePath = Join-Path $parent "$devName - Release v1.0"
}
if (-not (Test-Path $ReleasePath)) {
    Write-Error "Release checkout not found: $ReleasePath"
}
$ReleasePath = Resolve-Path $ReleasePath

$pkgName = "Resident Evil 4 - DualSense Enhanced Edition"
$staging = Join-Path $ReleasePath "release\v1.0\staging\$pkgName"

Write-Host "Release checkout: $ReleasePath"
Write-Host "Staging target  : $staging"
Write-Host ""

if (Test-Path $staging) {
    Remove-Item -Recurse -Force $staging
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null

$missing = @()

function Stage {
    param([string]$RelativeSrc, [string]$RelativeDst)

    $src = Join-Path $script:ReleasePath $RelativeSrc
    $dst = Join-Path $script:staging $RelativeDst
    if (-not (Test-Path $src)) {
        $script:missing += $RelativeSrc
        Write-Warning "MISSING in release checkout: $RelativeSrc"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "staged: $RelativeDst"
}

# --- Top-level package files (RELEASE_MANIFEST.md: Include In Nexus ZIP) --
Stage "modinfo.ini"               "modinfo.ini"
Stage "README.txt"                "README.txt"
Stage "VERSION.txt"               "VERSION.txt"
Stage "setup_sounds.bat"          "setup_sounds.bat"
Stage "THIRD_PARTY_LICENSES.txt"  "THIRD_PARTY_LICENSES.txt"

# --- Runtime Lua (release-safe whitelist only) ----------------------------
Stage "src/reframework/autorun/DualSenseEnhanced.lua" "reframework/autorun/DualSenseEnhanced.lua"
$luaModules = @(
    "ammo_led.lua",
    "audio_feedback.lua",
    "dualib_trigger_ipc.lua",
    "events_led.lua",
    "feedback_writer.lua",
    "hp_led.lua",
    "item_ids.lua",
    "mic_led.lua",
    "native_feedback.lua",
    "native_gyro.lua",
    "player_movement.lua",
    "settings.lua",
    "trigger_intensity.lua",
    "weapon_equip_core.lua",
    "wwise_audio_router.lua"
)
foreach ($m in $luaModules) {
    Stage "src/reframework/autorun/DualSenseEnhanced/$m" "reframework/autorun/DualSenseEnhanced/$m"
}

# --- Runtime data ----------------------------------------------------------
Stage "src/reframework/data/RE4R_WeaponData.lua" "reframework/data/RE4R_WeaponData.lua"
Stage "src/reframework/data/DualSenseEnhanced/DualSenseEnhancedConfig.txt" "reframework/data/DualSenseEnhanced/DualSenseEnhancedConfig.txt"
Stage "src/reframework/data/DualSenseEnhanced/transport_mode.txt" "reframework/data/DualSenseEnhanced/transport_mode.txt"
Stage "src/reframework/data/DualSenseEnhanced/weapon_trigger_profiles.lua" "reframework/data/DualSenseEnhanced/weapon_trigger_profiles.lua"

# Generated-output directory for extracted sounds. No extracted Capcom WAVs
# ship. Only the creator-owned AI-generated healing cues and explicitly
# allowlisted original/derived haptic assets are pre-populated.
New-Item -ItemType Directory -Force -Path (Join-Path $staging "reframework/data/DualSenseEnhanced/sounds") | Out-Null
Write-Host "staged: reframework/data/DualSenseEnhanced/sounds/ (extracted WAVs not shipped)"
$releaseSoundWavs = @(
    "heal_beetle.wav",
    "heal_egg.wav",
    "heal_egg_brown.wav",
    "heal_egg_gold.wav",
    "heal_fish.wav",
    "heal_fish_large.wav",
    "heal_fish_lunker.wav",
    "heal_herb.wav",
    "heal_herb_mock.wav",
    "heal_herb_rare.wav",
    "heal_viper.wav",
    "haptic_heal_beetle.wav",
    "haptic_heal_egg.wav",
    "haptic_heal_egg_brown.wav",
    "haptic_heal_egg_gold.wav",
    "haptic_heal_fish.wav",
    "haptic_heal_fish_large.wav",
    "haptic_heal_fish_lunker.wav",
    "haptic_heal_herb.wav",
    "haptic_heal_herb_mock.wav",
    "haptic_heal_herb_rare.wav",
    "haptic_heal_viper.wav",
    "haptic_footstep.wav",
    "haptic_footstep_soft.wav",
    "haptic_footstep_strong.wav",
    "haptic_impact_medium.wav",
    "haptic_impact_strong.wav",
    "haptic_parry.wav",
    "haptic_pickup.wav"
)
foreach ($w in $releaseSoundWavs) {
    Stage "src/reframework/data/DualSenseEnhanced/sounds/$w" "reframework/data/DualSenseEnhanced/sounds/$w"
}

# --- Runtime binaries (placed in release checkout by sync_to_release.ps1) --
Stage "reframework/plugins/DualsenseAudioBridgeLauncher.dll" "reframework/plugins/DualsenseAudioBridgeLauncher.dll"
Stage "reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe" "reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe"
Stage "reframework/data/DualSenseEnhanced/DualSenseEnhancedTransport.exe" "reframework/data/DualSenseEnhanced/DualSenseEnhancedTransport.exe"
Stage "reframework/data/DualSenseEnhanced/duaLib.dll" "reframework/data/DualSenseEnhanced/duaLib.dll"
Stage "reframework/data/DualSenseEnhanced/hidapi.dll" "reframework/data/DualSenseEnhanced/hidapi.dll"

# --- Audio extractor tooling ----------------------------------------------
Stage "tools/extract_sounds/setup_sounds.ps1" "DualSenseEnhanced/tools/extract_sounds/setup_sounds.ps1"
Stage "tools/extract_sounds/generate_haptics.ps1" "DualSenseEnhanced/tools/extract_sounds/generate_haptics.ps1"
Stage "tools/extract_sounds/sounds_manifest.json" "DualSenseEnhanced/tools/extract_sounds/sounds_manifest.json"
Stage "tools/extract_sounds/ree-pak-cli.exe" "DualSenseEnhanced/tools/extract_sounds/ree-pak-cli.exe"
Stage "tools/extract_sounds/DSE_Required_Banks.list" "DualSenseEnhanced/tools/extract_sounds/DSE_Required_Banks.list"
Stage "tools/extract_sounds/vgmstream/vgmstream-cli.exe" "DualSenseEnhanced/tools/extract_sounds/vgmstream/vgmstream-cli.exe"
$vgmDlls = Get-ChildItem (Join-Path $ReleasePath "tools/extract_sounds/vgmstream") -Filter "*.dll" -ErrorAction SilentlyContinue
foreach ($dll in $vgmDlls) {
    Stage "tools/extract_sounds/vgmstream/$($dll.Name)" "DualSenseEnhanced/tools/extract_sounds/vgmstream/$($dll.Name)"
}

# --- Hard checks -----------------------------------------------------------
$failed = $false

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "FAIL: $($missing.Count) required file(s) missing from the release checkout:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Run tools/sync_to_release.ps1 from dev first." -ForegroundColor Red
    $failed = $true
}

$loader = Join-Path $staging "reframework/autorun/DualSenseEnhanced.lua"
if (Test-Path $loader) {
    $loaderText = Get-Content -Raw -Encoding UTF8 $loader
    if ($loaderText -notmatch "local RELEASE_BUILD = true") {
        Write-Host "FAIL: staged DualSenseEnhanced.lua does not contain 'local RELEASE_BUILD = true'." -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "OK: staged loader has RELEASE_BUILD = true."
    }
}

# Only the explicit creator-owned list above may ship. In particular,
# heal_spray.wav, knife/weapon/UI WAVs, and haptic_*_real.wav must never ship;
# those come from or are derived from locally extracted Capcom audio.
$allowedWavs = $releaseSoundWavs
$forbidden = Get-ChildItem -Recurse -File $staging |
    Where-Object { $_.Extension -in @(".wav", ".pdb", ".log") -and $allowedWavs -notcontains $_.Name }
if ($forbidden) {
    Write-Host "FAIL: forbidden files in staging:" -ForegroundColor Red
    $forbidden | ForEach-Object { Write-Host "  $($_.FullName.Substring($staging.Length + 1))" -ForegroundColor Red }
    $failed = $true
} else {
    Write-Host "OK: no *.pdb / *.log / non-allowlisted *.wav in staging."
}

$debugModules = @("monitor.lua", "capcom_haptics_diag.lua", "sound_event_diag.lua",
                  "radio_dialogue.lua", "debug_led.lua", "weapon_equip_ui.lua")
$leaked = Get-ChildItem -Recurse -File $staging | Where-Object { $debugModules -contains $_.Name }
if ($leaked) {
    Write-Host "FAIL: debug-only module(s) in staging:" -ForegroundColor Red
    $leaked | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Red }
    $failed = $true
} else {
    Write-Host "OK: no debug-only Lua modules in staging."
}

if ($failed) {
    exit 1
}

$fileCount = (Get-ChildItem -Recurse -File $staging | Measure-Object).Count
Write-Host ""
Write-Host "Staged $fileCount files."

# --- Optional ZIP ----------------------------------------------------------
if ($Zip) {
    $version = "0.0.0"
    $versionFile = Join-Path $staging "VERSION.txt"
    if (Test-Path $versionFile) {
        $version = (Get-Content $versionFile -TotalCount 1).Trim()
    }
    $zipPath = Join-Path $ReleasePath "release\v1.0\$pkgName-v$version.zip"
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    # Compress the package folder itself so the ZIP root is the package root.
    Compress-Archive -Path $staging -DestinationPath $zipPath
    Write-Host "ZIP written: $zipPath"
} else {
    Write-Host "No ZIP built (-Zip not passed). Test setup_sounds.bat from the staged layout first."
}
