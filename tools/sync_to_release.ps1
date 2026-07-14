<#
.SYNOPSIS
    Copies the files listed in release/v1.0/RELEASE_MANIFEST.md from this
    (dev) checkout into the separate release checkout, ahead of building the
    Nexus package there.

.DESCRIPTION
    Dev is the single source of truth for source/logic (see docs/AGENTS.md's
    Commit Rules). This script is the only supported way to bring dev's
    current state into the release checkout -- do not hand-edit source files
    directly in the release checkout.

    It does NOT touch git in either checkout and does NOT build the Nexus
    ZIP. After running it:
      1. Review `git status`/`git diff` in the release checkout.
      2. Commit there (e.g. "sync: pull runtime from dev @ <short-hash>").
      3. Run the release checkout's own staging/packaging step.

    Runtime binaries (DualsenseAudioBridge.exe, DualSenseEnhancedTransport.exe,
    duaLib.dll, hidapi.dll, DualsenseAudioBridgeLauncher.dll) are not source
    files and are not built by this script. If their build output isn't
    found next to this checkout, the file is skipped with a warning -- build
    them first (see docs/AGENTS.md's Wwise Event Capture & Deployment
    Workflow and speaker/*/README.md for each project's build command).

.PARAMETER ReleasePath
    Path to the release checkout. Defaults to the sibling folder matching
    this project's existing "<name> - Release v1.0" convention.

.PARAMETER WhatIf
    List what would be copied without touching the release checkout.
#>

param(
    [string]$ReleasePath,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$devRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ReleasePath) {
    $parent = Split-Path $devRoot -Parent
    $devName = Split-Path $devRoot -Leaf
    $ReleasePath = Join-Path $parent "$devName - Release v1.0"
}
if (-not (Test-Path $ReleasePath)) {
    Write-Error "Release checkout not found: $ReleasePath`nPass -ReleasePath explicitly if it lives somewhere else."
}
$ReleasePath = Resolve-Path $ReleasePath

Write-Host "Dev checkout    : $devRoot"
Write-Host "Release checkout: $ReleasePath"
if ($WhatIf) { Write-Host "(-WhatIf: no files will be written)" }
Write-Host ""

function Copy-Tracked {
    param([string]$RelativePath)

    $src = Join-Path $devRoot $RelativePath
    $dst = Join-Path $ReleasePath $RelativePath

    if (-not (Test-Path $src)) {
        Write-Warning "Missing in dev, skipped: $RelativePath"
        return
    }
    if ($WhatIf) {
        Write-Host "would copy: $RelativePath"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "copied: $RelativePath"
}

function Copy-BuildOutput {
    param([string]$RelativeSrc, [string]$RelativeDst)

    $src = Join-Path $devRoot $RelativeSrc
    $dst = Join-Path $ReleasePath $RelativeDst

    if (-not (Test-Path $src)) {
        Write-Warning "Build output not found, skipped (build it first): $RelativeSrc"
        return
    }
    if ($WhatIf) {
        Write-Host "would copy: $RelativeSrc -> $RelativeDst"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "copied: $RelativeSrc -> $RelativeDst"
}

# --- Top-level package files -------------------------------------------
Copy-Tracked "setup_sounds.bat"
Copy-Tracked "THIRD_PARTY_LICENSES.txt"
Copy-Tracked "modinfo.ini"
Copy-Tracked "README.txt"
Copy-Tracked "VERSION.txt"

# --- Runtime Lua (release-safe modules only; see RELEASE_MANIFEST.md) --
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
    Copy-Tracked "src/reframework/autorun/DualSenseEnhanced/$m"
}

# Main loader gets RELEASE_BUILD flipped to true in the copy only.
$loaderSrc = Join-Path $devRoot "src/reframework/autorun/DualSenseEnhanced.lua"
$loaderDst = Join-Path $ReleasePath "src/reframework/autorun/DualSenseEnhanced.lua"
if (Test-Path $loaderSrc) {
    $content = Get-Content -Raw -Encoding UTF8 $loaderSrc
    if ($content -notmatch "local RELEASE_BUILD = false") {
        Write-Warning "DualSenseEnhanced.lua: expected 'local RELEASE_BUILD = false' not found -- check the flag wasn't renamed before trusting the release copy."
    }
    $content = $content -replace "local RELEASE_BUILD = false", "local RELEASE_BUILD = true"
    if ($WhatIf) {
        Write-Host "would copy: src/reframework/autorun/DualSenseEnhanced.lua (RELEASE_BUILD -> true)"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $loaderDst -Parent) | Out-Null
        [System.IO.File]::WriteAllText($loaderDst, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "copied: src/reframework/autorun/DualSenseEnhanced.lua (RELEASE_BUILD -> true)"
    }
} else {
    Write-Warning "Missing in dev, skipped: src/reframework/autorun/DualSenseEnhanced.lua"
}

# --- Runtime data --------------------------------------------------------
Copy-Tracked "src/reframework/data/RE4R_WeaponData.lua"
Copy-Tracked "src/reframework/data/DualSenseEnhanced/DualSenseEnhancedConfig.txt"
Copy-Tracked "src/reframework/data/DualSenseEnhanced/transport_mode.txt"
Copy-Tracked "src/reframework/data/DualSenseEnhanced/weapon_trigger_profiles.lua"

# Creator-owned audio only. The heal_* cues are AI-generated by the mod
# author; the haptic_* entries are original synthesized or author-audio
# derivatives. Never replace this explicit allowlist with a sounds/*.wav copy:
# the same dev folder also contains extracted Capcom audio.
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
    Copy-Tracked "src/reframework/data/DualSenseEnhanced/sounds/$w"
}

# --- Audio extractor tooling ----------------------------------------------
Copy-Tracked "tools/extract_sounds/setup_sounds.ps1"
Copy-Tracked "tools/extract_sounds/generate_haptics.ps1"
Copy-Tracked "tools/extract_sounds/sounds_manifest.json"
Copy-Tracked "tools/extract_sounds/ree-pak-cli.exe"
Copy-Tracked "tools/extract_sounds/DSE_Required_Banks.list"
Copy-Tracked "tools/extract_sounds/vgmstream/vgmstream-cli.exe"
Get-ChildItem (Join-Path $devRoot "tools/extract_sounds/vgmstream") -Filter "*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Tracked "tools/extract_sounds/vgmstream/$($_.Name)" }

# --- Runtime binaries (build output; skipped with a warning if absent) ---
Copy-BuildOutput `
    "speaker/DualsenseAudioBridge/launcher-nativeaot/publish/DualsenseAudioBridgeLauncher.dll" `
    "reframework/plugins/DualsenseAudioBridgeLauncher.dll"
Copy-BuildOutput `
    "speaker/DualsenseAudioBridge/dist/native-autostart/DualsenseAudioBridge.exe" `
    "reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe"
Copy-BuildOutput `
    "speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/publish-fixed/DualSenseEnhancedTransport.exe" `
    "reframework/data/DualSenseEnhanced/DualSenseEnhancedTransport.exe"
Copy-BuildOutput `
    "speaker/DualSenseEnhancedTransport/third_party/build_out/duaLib.dll" `
    "reframework/data/DualSenseEnhanced/duaLib.dll"
Copy-BuildOutput `
    "speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/hidapi.dll" `
    "reframework/data/DualSenseEnhanced/hidapi.dll"

Write-Host ""
Write-Host "Note: DualsenseAudioBridge.exe and hidapi.dll source paths above are" -ForegroundColor Yellow
Write-Host "best-guess build output locations -- verify against the actual verified" -ForegroundColor Yellow
Write-Host "build you intend to ship before trusting a copy that succeeded." -ForegroundColor Yellow

Write-Host ""
Write-Host "Done. This did not touch git in the release checkout or build the"
Write-Host "Nexus ZIP -- review, commit, and stage there next."
