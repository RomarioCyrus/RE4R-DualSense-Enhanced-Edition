<#
.SYNOPSIS
    First-run setup: extracts RE4R weapon sounds from the user's own game files.

.DESCRIPTION
    DualSense Enhanced Edition needs WAV files extracted from Resident Evil 4
    Remake's audio banks. This script recreates those files on the player's own
    machine using their legally-purchased copy of the game, so no Capcom audio
    assets are distributed with the mod.

    Requirements:
      - RE4R installed via Steam (or path provided via -GamePath)
      - ree-pak-cli.exe  -- extracts .pak archives (MIT, bundled)
      - DSE_Required_Banks.list -- minimal filename list for the required banks
      - vgmstream-cli.exe -- converts Wwise .wem to .wav (LGPL, bundled)

    RE4R stores all game data in re_chunk_000.pak in the game root.
    Weapon Wwise banks are at:
        natives/stm/_chainsaw/sound/wwise/ch_wpNNNN_media.sbnk.1.x64

    The script:
      1. Reads sounds_manifest.json for the list of sounds to extract.
      2. Builds a regex filter from the needed bank filenames.
      3. Runs ree-pak-cli once to extract only those banks (~30 MB, not the full 55 GB pak).
      4. For each bank, parses the Wwise DIDX section to carve out raw WEM bytes by WEM ID.
      5. Feeds each .wem to vgmstream-cli to produce a .wav file.
      6. Places output WAVs in the mod's sounds folder (ready to use).

.PARAMETER GamePath
    Root folder of the RE4R installation.
    Default: auto-detected from Steam registry.

.PARAMETER ReePakPath
    Path to ree-pak-cli.exe.
    Default: ree-pak-cli.exe in the same folder as this script.

.PARAMETER HashListPath
    Path to the minimal RE4R filename list used by ree-pak-cli.
    Default: DSE_Required_Banks.list in the same folder as this script.

.PARAMETER VGMStreamPath
    Path to vgmstream-cli.exe.
    Default: vgmstream\vgmstream-cli.exe relative to this script.

.PARAMETER ManifestPath
    Path to sounds_manifest.json.
    Default: same directory as this script.

.PARAMETER OutputSoundsPath
    Where to write the extracted .wav files.
    Default: installed reframework\data\DualSenseEnhanced\sounds when packaged,
    otherwise src\reframework\data\DualSenseEnhanced\sounds in the dev tree.

.PARAMETER TempDir
    Working directory for intermediate files.
    Default: %TEMP%\re4r_dsx_sounds

.PARAMETER ChunkPakPath
    Explicit path to re_chunk_000.pak.
    Default: auto-detected from GamePath.
    Use this if the game pak is modified by Fluffy Mod Manager.

.PARAMETER Force
    Re-extract even if the target .wav already exists.

.EXAMPLE
    # Minimal — all tools bundled, game auto-detected:
    .\setup_sounds.ps1

    # With explicit pak (Fluffy Mod Manager users):
    .\setup_sounds.ps1 -ChunkPakPath "<path-to-re_chunk_000.pak>"
#>

[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$ReePakPath       = "",
    [string]$HashListPath     = "",
    [string]$VGMStreamPath    = "",
    [string]$ManifestPath     = "",
    [string]$OutputSoundsPath = "",
    [string]$TempDir          = "",
    [string]$ChunkPakPath     = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $ReePakPath)       { $ReePakPath       = Join-Path $scriptDir "ree-pak-cli.exe" }
if (-not $HashListPath)     { $HashListPath      = Join-Path $scriptDir "DSE_Required_Banks.list" }
if (-not $VGMStreamPath)    { $VGMStreamPath     = Join-Path $scriptDir "vgmstream\vgmstream-cli.exe" }
if (-not $ManifestPath)     { $ManifestPath      = Join-Path $scriptDir "sounds_manifest.json" }
if (-not $TempDir)          { $TempDir           = Join-Path $env:TEMP "re4r_dsx_sounds" }

if (-not $OutputSoundsPath) {
    $installedOutput = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\..\reframework\data\DualSenseEnhanced\sounds"))
    $devOutput       = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\src\reframework\data\DualSenseEnhanced\sounds"))
    $installedRoot   = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\.."))

    if (Test-Path (Join-Path $installedRoot "reframework")) {
        $OutputSoundsPath = $installedOutput
    } elseif (Test-Path $devOutput) {
        $OutputSoundsPath = $devOutput
    } else {
        $OutputSoundsPath = $installedOutput
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Find-RE4RInstall {
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2050650',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2050650'
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $loc = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).InstallLocation
            if ($loc -and (Test-Path $loc)) { return $loc }
        }
    }
    foreach ($def in @(
        'C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4',
        'C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4 BIOHAZARD RE4'
    )) {
        if (Test-Path $def) { return $def }
    }
    return $null
}

function Export-WemFromBnk {
    param(
        [string][Parameter(Mandatory)]$BnkPath,
        [uint32][Parameter(Mandatory)]$WemId,
        [string][Parameter(Mandatory)]$OutputWem
    )

    $raw     = [IO.File]::ReadAllBytes($BnkPath)
    $didxTag = [byte[]]@(0x44, 0x49, 0x44, 0x58)
    $dataTag = [byte[]]@(0x44, 0x41, 0x54, 0x41)

    $didxPos = -1
    for ($i = 0; $i -lt ($raw.Length - 4); $i++) {
        if ($raw[$i] -eq $didxTag[0] -and $raw[$i+1] -eq $didxTag[1] -and
            $raw[$i+2] -eq $didxTag[2] -and $raw[$i+3] -eq $didxTag[3]) {
            $didxPos = $i; break
        }
    }
    if ($didxPos -lt 0) { Write-Verbose "  [bnk] No DIDX in $([IO.Path]::GetFileName($BnkPath))"; return $false }

    $didxSize         = [BitConverter]::ToInt32($raw, $didxPos + 4)
    $numEntries       = [Math]::Floor($didxSize / 12)
    $dataPos          = $didxPos + 8 + $didxSize

    if ($raw[$dataPos] -ne $dataTag[0] -or $raw[$dataPos+1] -ne $dataTag[1] -or
        $raw[$dataPos+2] -ne $dataTag[2] -or $raw[$dataPos+3] -ne $dataTag[3]) {
        Write-Warning "  [bnk] DATA not after DIDX in $([IO.Path]::GetFileName($BnkPath))"
        return $false
    }
    $dataSectionStart = $dataPos + 8

    for ($i = 0; $i -lt $numEntries; $i++) {
        $base      = $didxPos + 8 + $i * 12
        $entryId   = [BitConverter]::ToUInt32($raw, $base)
        $wemOffset = [BitConverter]::ToUInt32($raw, $base + 4)
        $wemSize   = [BitConverter]::ToUInt32($raw, $base + 8)

        if ($entryId -eq $WemId) {
            $wemBytes = $raw[($dataSectionStart + $wemOffset)..($dataSectionStart + $wemOffset + $wemSize - 1)]
            [IO.File]::WriteAllBytes($OutputWem, $wemBytes)
            return $true
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Validate tools
# ---------------------------------------------------------------------------

foreach ($tool in @($ReePakPath, $HashListPath, $VGMStreamPath)) {
    if (-not (Test-Path $tool)) { Write-Error "Required file not found: $tool"; exit 1 }
}
if (-not (Test-Path $ManifestPath)) { Write-Error "Manifest not found: $ManifestPath"; exit 1 }

# ---------------------------------------------------------------------------
# Detect game / chunk pak
# ---------------------------------------------------------------------------

if (-not $GamePath) {
    $GamePath = Find-RE4RInstall
    if (-not $GamePath) { Write-Error "Could not auto-detect RE4R install. Pass -GamePath."; exit 1 }
    Write-Host "Auto-detected game path: $GamePath"
}
if (-not (Test-Path $GamePath)) { Write-Error "Game path not found: $GamePath"; exit 1 }

if (-not $ChunkPakPath) {
    $ChunkPakPath = Join-Path $GamePath "re_chunk_000.pak"
}
if (-not (Test-Path $ChunkPakPath)) {
    Write-Error "re_chunk_000.pak not found: $ChunkPakPath"
    exit 1
}

$pakInputs = [System.Collections.Generic.List[string]]::new()
$pakInputs.Add([IO.Path]::GetFullPath($ChunkPakPath))

$sentinelNineDlcPak = Join-Path $GamePath "dlc\re_dlc_stm_2109308.pak"
$hasSentinelNineDlc = Test-Path $sentinelNineDlcPak
if ($hasSentinelNineDlc) {
    $pakInputs.Add([IO.Path]::GetFullPath($sentinelNineDlcPak))
} else {
    Write-Warning "Sentinel Nine DLC pak not found: $sentinelNineDlcPak"
    Write-Warning "Sentinel Nine controller-speaker sounds will be skipped; base-game audio setup can continue."
}

Write-Host ""
Write-Host "Important: if you use audio mods that replace or modify RE4R re_chunk files,"
Write-Host "disable them before running this setup, then re-enable them after extraction."
Write-Host ""
Write-Host "Source paks:"
$pakInputs | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# ---------------------------------------------------------------------------
# Load manifest
# ---------------------------------------------------------------------------

$manifest = Get-Content $ManifestPath -Encoding UTF8 | ConvertFrom-Json
$allEvents = @($manifest | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)

# Sentinel Nine's bank path is the path stored inside its DLC pak; it is not
# present in the base re_chunk_000.pak. Treat only that exact bank as optional
# when the DLC archive is absent. All other manifest entries remain required.
$sentinelNineBankPak = "natives/stm/_chainsaw/sound/wwise/ch_wp6000_media.sbnk.1.x64"
$skippedOptionalEvents = @()
if ($hasSentinelNineDlc) {
    $events = $allEvents
} else {
    $skippedOptionalEvents = @($allEvents | Where-Object {
        $manifest.$_.bank_pak -eq $sentinelNineBankPak
    })
    $events = @($allEvents | Where-Object {
        $manifest.$_.bank_pak -ne $sentinelNineBankPak
    })
}

Write-Host "Manifest: $($allEvents.Count) sounds configured."
Write-Host "Required for this installation: $($events.Count) sounds."
if ($skippedOptionalEvents.Count -gt 0) {
    Write-Host "Optional Sentinel Nine DLC sounds skipped: $($skippedOptionalEvents.Count)."
}
Write-Host "Output  : $OutputSoundsPath"

New-Item -ItemType Directory -Force -Path $OutputSoundsPath | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir          | Out-Null

# ---------------------------------------------------------------------------
# Phase 1 — extract weapon banks with ree-pak-cli
# ---------------------------------------------------------------------------

$bankExtDir = Join-Path $TempDir "banks"
New-Item -ItemType Directory -Force -Path $bankExtDir | Out-Null

$bs = [char]92

$neededBankPaths = @($events | ForEach-Object { $manifest.$_.bank_pak } | Sort-Object -Unique)

# Check which banks are already cached from a previous run.
$missingBanks = @($neededBankPaths | Where-Object {
    -not (Test-Path (Join-Path $bankExtDir $_.Replace('/', $bs)))
})

if ($missingBanks.Count -eq 0) {
    Write-Host "All banks already cached - skipping extraction."
} else {
    foreach ($pakInput in $pakInputs) {
        $stillNeeded = @($missingBanks | Where-Object {
            -not (Test-Path (Join-Path $bankExtDir $_.Replace('/', $bs)))
        })
        if ($stillNeeded.Count -eq 0) { break }

        # Build a regex filter: match any of the still-missing bank filenames.
        $filterRegex = ($stillNeeded | ForEach-Object { [regex]::Escape([IO.Path]::GetFileName($_)) }) -join "|"
        Write-Verbose "Extracting $($stillNeeded.Count) missing banks from $([IO.Path]::GetFileName($pakInput)) ..."

        & $ReePakPath unpack `
            -p $HashListPath `
            -i $pakInput `
            -o $bankExtDir `
            -f $filterRegex `
            --skip-unknown 2>&1 | Write-Verbose
    }

    # ree-pak-cli places files at: $bankExtDir\natives\stm\...
    # Verify all needed banks were found.
    $stillMissing = @($missingBanks | Where-Object {
        -not (Test-Path (Join-Path $bankExtDir $_.Replace('/', $bs)))
    })
    if ($stillMissing) {
        Write-Warning "The following banks were not found in the pak:"
        $stillMissing | ForEach-Object { Write-Warning "  $_" }
        Write-Warning "If you use Fluffy Mod Manager, re-run with -ChunkPakPath pointing to a clean pak."
    }
}

# ---------------------------------------------------------------------------
# Phase 2 — parse DIDX, extract WEMs, convert to WAV
# ---------------------------------------------------------------------------

$bankGroups = @{}
foreach ($ev in $events) {
    $key = $manifest.$ev.bank_pak
    if (-not $bankGroups.ContainsKey($key)) {
        $bankGroups[$key] = [System.Collections.Generic.List[string]]::new()
    }
    $bankGroups[$key].Add($ev)
}

$totalOk  = 0
$totalErr = 0

foreach ($bankPakPath in $bankGroups.Keys) {
    $bnkPath = Join-Path $bankExtDir $bankPakPath.Replace('/', $bs)

    if (-not (Test-Path $bnkPath)) {
        Write-Warning "`nBank not available, skipping: $([IO.Path]::GetFileName($bankPakPath))"
        $totalErr += $bankGroups[$bankPakPath].Count
        continue
    }

    Write-Host "`n[$([IO.Path]::GetFileName($bankPakPath))]"

    foreach ($ev in $bankGroups[$bankPakPath]) {
        $entry  = $manifest.$ev
        $outWav = Join-Path $OutputSoundsPath "$ev.wav"

        if ((Test-Path $outWav) -and -not $Force) {
            Write-Verbose "  [skip] $ev.wav"
            $totalOk++
            continue
        }

        $tempWem = Join-Path $TempDir "$ev.wem"
        Write-Host -NoNewline "  $ev ... "

        $found = Export-WemFromBnk -BnkPath $bnkPath -WemId ([uint32]$entry.wem_id) -OutputWem $tempWem
        if (-not $found) {
            Write-Host "NOT FOUND in bank (WEM $($entry.wem_id))"
            $totalErr++
            continue
        }

        $result = & $VGMStreamPath -o $outWav $tempWem 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "vgmstream error"
            Write-Verbose "  $result"
            $totalErr++
        } else {
            Write-Host "OK"
            $totalOk++
        }

        Remove-Item $tempWem -ErrorAction SilentlyContinue
    }
}

Write-Host "`n--- Done ---"
Write-Host "  Extracted : $totalOk"
Write-Host "  Errors    : $totalErr"
if ($skippedOptionalEvents.Count -gt 0) {
    Write-Host "  Optional  : $($skippedOptionalEvents.Count) Sentinel Nine DLC sounds skipped"
}

$missingOutputs = @($events | Where-Object {
    -not (Test-Path (Join-Path $OutputSoundsPath "$_.wav"))
})

if ($missingOutputs.Count -gt 0) {
    Write-Warning "Missing required WAV files after extraction:"
    $missingOutputs | ForEach-Object { Write-Warning "  $_.wav" }
}

if ($totalErr -gt 0 -or $missingOutputs.Count -gt 0) {
    Write-Warning "Sound setup did not complete. If audio mods are installed, disable them and run setup_sounds.bat again."
    exit 1
}

Write-Host "  Verified  : $($events.Count) required WAV files present for this installation"
exit 0
