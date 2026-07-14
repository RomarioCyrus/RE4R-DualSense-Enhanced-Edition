<#
.SYNOPSIS
  Deploy all source files from src/reframework/ to the RE4R game folder,
  verify hashes, and report what the user still needs to do in-game.

  Restart matrix (what needs restarting for each change type):
    Lua files only          → Reset Scripts in REFramework (user does this)
    WAV files only          → nothing; FindVariants reads disk on every event
    DualsenseAudioBridge.exe → use -RestartBridge (stop process, copy, restart)
    DualsenseAudioBridgeLauncher.dll → full game restart required
    DualSenseEnhancedTransport.exe   → bridge auto-relaunches it on next trigger

  C# builds are NOT handled here — dotnet publish + bridge restart are a
  separate workflow; use -RestartBridge after you have already built and
  copied the new exe into src/ (or use the manual steps in AGENTS.md).

.PARAMETER GamePath
  Root of the RE4R install. Defaults to the Steam path on this machine.

.PARAMETER RestartBridge
  After deploying, stop DualsenseAudioBridge.exe (if running), copy the
  newly built exe from publish-fixed, and restart the bridge with the same
  args the native launcher uses. Use this when DualsenseAudioBridge.exe
  or SoundMap.cs changed and you have already done the dotnet publish step.

.EXAMPLE
  .\tools\deploy.ps1
  .\tools\deploy.ps1 -RestartBridge
#>
param(
    [string]$GamePath     = "C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4",
    [switch]$RestartBridge
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot  = Join-Path $repoRoot "src\reframework"
$dstRoot  = Join-Path $GamePath "reframework"

if (-not (Test-Path $srcRoot)) { Write-Error "src not found: $srcRoot"; exit 1 }
if (-not (Test-Path $dstRoot)) { Write-Error "game reframework not found: $dstRoot"; exit 1 }

# ── 1. Copy src/reframework/ → game ──────────────────────────────────────────

$copied     = 0
$copyErrors = 0
$luaChanged = $false

Get-ChildItem -Path $srcRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
    $dst = Join-Path $dstRoot $rel
    $dir = Split-Path $dst -Parent

    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $dstHash = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash } else { "" }

    if ($srcHash -ne $dstHash) {
        try {
            Copy-Item -Path $_.FullName -Destination $dst -Force
            $copied++
            if ($_.Extension -eq ".lua") { $luaChanged = $true }
        } catch {
            Write-Host "ERROR copying $rel : $_" -ForegroundColor Red
            $copyErrors++
        }
    }
}

Write-Host "Copied $copied changed files ($copyErrors errors)."

# ── 1.5 Remove orphans ────────────────────────────────────────────────────────
# Files deleted from src/ must also disappear from the game folder, otherwise
# they keep working invisibly: the C# bridge auto-discovers numbered WAV
# variants by scanning sounds\ on every event, so a "removed" sound keeps
# playing (confirmed 2026-07-07: deleted knife_surface water variants kept
# firing). Only subtrees fully owned by this mod are cleaned -- the game's
# reframework\ root and data\DualSenseEnhanced\ root also hold REFramework
# itself, other mods, and runtime files (logs, payload.json, *.ready) that
# must never be mirror-deleted.

$orphanDirs = @(
    "autorun\DualSenseEnhanced",
    "data\DualSenseEnhanced\sounds"
)
$removedOrphans = 0

foreach ($sub in $orphanDirs) {
    $srcDir = Join-Path $srcRoot $sub
    $dstDir = Join-Path $dstRoot $sub
    if (-not (Test-Path $srcDir) -or -not (Test-Path $dstDir)) { continue }

    Get-ChildItem -Path $dstDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($dstDir.Length).TrimStart('\')
        if (-not (Test-Path (Join-Path $srcDir $rel))) {
            try {
                Remove-Item -Path $_.FullName -Force -Confirm:$false
                Write-Host "Removed orphan: $sub\$rel" -ForegroundColor Yellow
                $removedOrphans++
                if ($_.Extension -eq ".lua") { $luaChanged = $true }
            } catch {
                Write-Host "ERROR removing orphan $sub\$rel : $_" -ForegroundColor Red
                $copyErrors++
            }
        }
    }
}

if ($removedOrphans -gt 0) { Write-Host "Removed $removedOrphans orphaned files." }

# ── 2. Verify ─────────────────────────────────────────────────────────────────

$mismatches = @()
Get-ChildItem -Path $srcRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
    $dst = Join-Path $dstRoot $rel
    if (-not (Test-Path $dst)) {
        $mismatches += "MISSING: $rel"
    } else {
        $srcHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dst         -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) { $mismatches += "MISMATCH: $rel" }
    }
}

if ($mismatches.Count -gt 0) {
    Write-Host ""
    $mismatches | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "`nDeploy FAILED." -ForegroundColor Red
    exit 1
}

$total = (Get-ChildItem -Path $srcRoot -Recurse -File | Measure-Object).Count
Write-Host "All $total deployed files match source." -ForegroundColor Green

# ── 3. Bridge restart (optional) ──────────────────────────────────────────────

if ($RestartBridge) {
    $bridgeSrc = "$repoRoot\speaker\DualsenseAudioBridge\bin\Release\net6.0-windows\win-x64\publish-fixed\DualsenseAudioBridge.exe"
    $bridgeDst = "$GamePath\reframework\data\DualSenseEnhanced\DualsenseAudioBridge.exe"

    if (-not (Test-Path $bridgeSrc)) {
        Write-Host "WARN: publish-fixed exe not found -- did you run dotnet publish?" -ForegroundColor Yellow
    } else {
        $running = Get-Process DualsenseAudioBridge -ErrorAction SilentlyContinue
        if ($running) {
            $running | Stop-Process -Force
            Write-Host "Stopped DualsenseAudioBridge.exe."
            Start-Sleep -Milliseconds 500
        }

        Copy-Item $bridgeSrc $bridgeDst -Force
        $h1 = (Get-FileHash $bridgeSrc -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $bridgeDst -Algorithm SHA256).Hash
        if ($h1 -ne $h2) {
            Write-Host "ERROR: bridge exe hash mismatch after copy!" -ForegroundColor Red
            exit 1
        }
        Write-Host "Bridge exe deployed." -ForegroundColor Green

        # Same args as DualsenseAudioBridgeLauncher.dll uses (LauncherExports.cs)
        $rfPath = "$GamePath\reframework"
        $args   = "--reframework `"$rfPath`" --game-process re4"
        Start-Process -FilePath $bridgeDst -ArgumentList $args -WorkingDirectory $GamePath -WindowStyle Hidden
        Write-Host "DualsenseAudioBridge.exe restarted." -ForegroundColor Green
    }
}

# ── 4. Tell the user what to do next ─────────────────────────────────────────

Write-Host ""
if ($copied -eq 0) {
    Write-Host "Nothing changed -- already up to date." -ForegroundColor DarkGray
} elseif ($luaChanged) {
    Write-Host "Lua files changed -- press Reset Scripts in REFramework." -ForegroundColor Cyan
} else {
    Write-Host "WAV-only change -- no Reset Scripts needed; sounds load on next event." -ForegroundColor Cyan
}
