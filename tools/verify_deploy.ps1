<#
.SYNOPSIS
  Compares every deployed src/reframework Lua file, every sound WAV, and the audio
  bridge exe against their deployed copies in the RE4R game folder and
  reports drift. Run this before declaring any change "ready to test" --
  it is the cheapest way to catch a forgotten `cp`/deploy step across a
  multi-turn or multi-agent editing session.

.PARAMETER GamePath
  Root of the RE4R install (the folder containing reframework\).
  Defaults to the Steam path used on this machine.

.EXAMPLE
  .\tools\verify_deploy.ps1
#>
param(
    [string]$GamePath = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4"
)

$repoRoot = Split-Path -Parent $PSScriptRoot

$mismatches = @()
$missing = @()
$ok = 0

function Compare-Tree {
    param(
        [string]$SrcRoot,
        [string]$DstRoot,
        [string]$Filter
    )

    if (-not (Test-Path $SrcRoot)) {
        Write-Error "Source root not found: $SrcRoot"
        exit 1
    }
    if (-not (Test-Path $DstRoot)) {
        Write-Error "Deployed root not found: $DstRoot"
        exit 1
    }

    Get-ChildItem -Path $SrcRoot -Filter $Filter -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($SrcRoot.Length).TrimStart('\')
        $dstFile = Join-Path $DstRoot $relative

        if (-not (Test-Path $dstFile)) {
            $script:missing += $relative
            return
        }

        $srcHash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -Path $dstFile -Algorithm SHA256).Hash

        if ($srcHash -ne $dstHash) {
            $script:mismatches += $relative
        } else {
            $script:ok++
        }
    }
}

# Lua autorun scripts.
Compare-Tree `
    -SrcRoot (Join-Path $repoRoot "src\reframework\autorun") `
    -DstRoot (Join-Path $GamePath "reframework\autorun") `
    -Filter "*.lua"

# Lua data files, including RE4R_WeaponData.lua and DualSenseEnhanced\weapon_trigger_profiles.lua.
Compare-Tree `
    -SrcRoot (Join-Path $repoRoot "src\reframework\data") `
    -DstRoot (Join-Path $GamePath "reframework\data") `
    -Filter "*.lua"

# Sound WAVs (catches the most common silent-drift case: a WAV extracted
# and dropped in src/ during a capture session but never copied in-game).
Compare-Tree `
    -SrcRoot (Join-Path $repoRoot "src\reframework\data\DualSenseEnhanced\sounds") `
    -DstRoot (Join-Path $GamePath "reframework\data\DualSenseEnhanced\sounds") `
    -Filter "*.wav"

# Audio bridge exe: compare the latest Release publish output against the
# deployed copy. If SoundMap.cs was edited and rebuilt, this is the one
# artifact that actually matters (the .cs source itself isn't deployed).
function Compare-OneFile {
    param(
        [string]$Src,
        [string]$Dst,
        [string]$Label,
        [string]$MissingMessage
    )

    if (Test-Path $Src) {
        if (-not (Test-Path $Dst)) {
            $script:missing += $Label
        } else {
            $srcHash = (Get-FileHash -Path $Src -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash -Path $Dst -Algorithm SHA256).Hash
            if ($srcHash -ne $dstHash) {
                $script:mismatches += $Label
            } else {
                $script:ok++
            }
        }
    } else {
        Write-Host $MissingMessage -ForegroundColor DarkGray
    }
}

Compare-OneFile `
    -Src (Join-Path $repoRoot "speaker\DualsenseAudioBridge\dist\native-autostart\DualsenseAudioBridge.exe") `
    -Dst (Join-Path $GamePath "reframework\data\DualSenseEnhanced\DualsenseAudioBridge.exe") `
    -Label "DualsenseAudioBridge.exe (selected native-autostart release build)" `
    -MissingMessage "Skipping DualsenseAudioBridge.exe check: no dist/native-autostart release build found."

Compare-OneFile `
    -Src (Join-Path $repoRoot "speaker\DualsenseAudioBridge\launcher-nativeaot\publish\DualsenseAudioBridgeLauncher.dll") `
    -Dst (Join-Path $GamePath "reframework\plugins\DualsenseAudioBridgeLauncher.dll") `
    -Label "DualsenseAudioBridgeLauncher.dll (launcher-nativeaot build newer than deployed copy)" `
    -MissingMessage "Skipping DualsenseAudioBridgeLauncher.dll check: no launcher-nativeaot build found."

Compare-OneFile `
    -Src (Join-Path $repoRoot "speaker\DualSenseEnhancedTransport\bin\Release\net6.0-windows\win-x64\publish-fixed\DualSenseEnhancedTransport.exe") `
    -Dst (Join-Path $GamePath "reframework\data\DualSenseEnhanced\DualSenseEnhancedTransport.exe") `
    -Label "DualSenseEnhancedTransport.exe (publish-fixed build newer than deployed copy)" `
    -MissingMessage "Skipping DualSenseEnhancedTransport.exe check: no publish-fixed build found."

Compare-OneFile `
    -Src (Join-Path $repoRoot "speaker\DualSenseEnhancedTransport\bin\Release\net6.0-windows\win-x64\duaLib.dll") `
    -Dst (Join-Path $GamePath "reframework\data\DualSenseEnhanced\duaLib.dll") `
    -Label "duaLib.dll" `
    -MissingMessage "Skipping duaLib.dll check: no Release build found."

Compare-OneFile `
    -Src (Join-Path $repoRoot "speaker\DualSenseEnhancedTransport\bin\Release\net6.0-windows\win-x64\hidapi.dll") `
    -Dst (Join-Path $GamePath "reframework\data\DualSenseEnhanced\hidapi.dll") `
    -Label "hidapi.dll" `
    -MissingMessage "Skipping hidapi.dll check: no Release build found."

# Orphans: files present in the game folder but no longer in src, inside the
# subtrees this mod fully owns (same list deploy.ps1 mirror-deletes). These
# are live drift -- the bridge auto-discovers WAV variants by scanning
# sounds\, so a WAV deleted from src keeps playing until removed in-game.
$orphans = @()
foreach ($sub in @("autorun\DualSenseEnhanced", "data\DualSenseEnhanced\sounds")) {
    $srcDir = Join-Path $repoRoot "src\reframework\$sub"
    $dstDir = Join-Path $GamePath "reframework\$sub"
    if (-not (Test-Path $srcDir) -or -not (Test-Path $dstDir)) { continue }
    Get-ChildItem -Path $dstDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($dstDir.Length).TrimStart('\')
        if (-not (Test-Path (Join-Path $srcDir $rel))) { $orphans += "$sub\$rel" }
    }
}

Write-Host "Checked $($ok + $mismatches.Count) deployed files ($ok match)."

if ($orphans.Count -gt 0) {
    Write-Host ""
    Write-Host "ORPHAN in game folder (deleted from src but still deployed -- run deploy.ps1 to clean):" -ForegroundColor Red
    $orphans | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "MISSING in game folder (never deployed):" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

if ($mismatches.Count -gt 0) {
    Write-Host ""
    Write-Host "MISMATCH (source edited since last deploy):" -ForegroundColor Red
    $mismatches | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

if ($orphans.Count -gt 0) { exit 1 }

if ($missing.Count -eq 0 -and $mismatches.Count -eq 0) {
    Write-Host "All deployed files match source." -ForegroundColor Green
}
