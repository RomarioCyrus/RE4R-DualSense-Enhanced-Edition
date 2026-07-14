<#
.SYNOPSIS
    Regenerates Wwise txtp analysis files from the unmodded RE4R game banks.

.DESCRIPTION
    Extracts all weapon Wwise banks from re_chunk_000.pak, converts them to
    .bnk (wwiser's expected extension), runs wwiser.pyz to generate txtp event
    files, and writes them to tools/txtp/ in the project.

    Run this after removing mods, after a game update, or when you need fresh
    txtp to investigate a new weapon's event IDs.

    Requirements:
      - RE4R installed via Steam (or -GamePath)
      - ree-pak-cli.exe  (bundled in tools/extract_sounds/)
      - wwiser.pyz       (default: <downloads-root>\wwiser.pyz)
      - Python / py.exe  (for wwiser)

.PARAMETER GamePath
    Root folder of the RE4R installation. Default: auto-detect from Steam.

.PARAMETER WwiserPath
    Path to wwiser.pyz. Default: <downloads-root>\wwiser.pyz

.PARAMETER ReePakPath
    Path to ree-pak-cli.exe. Default: extract_sounds\ree-pak-cli.exe

.PARAMETER BankListPath
    REtool-style filename list for weapon banks.
    Default: <REtool-root>\RE4R_weapon_wwise_banks.list

.PARAMETER TxTPOutDir
    Where to write the generated txtp files.
    Default: tools\txtp\ relative to this script.

.PARAMETER FusionToolsDir
    If set, also copies txtp to this directory (e.g. FusionTools RE4R folder)
    so FusionTools can open them immediately.

.PARAMETER TempDir
    Working directory for intermediate files. Default: %TEMP%\re4r_txtp_regen

.PARAMETER BankFilter
    Regex applied to bank filenames to select which banks to process.
    Default: ch_wp (all weapon banks). Use e.g. "ch_wp6001" for one weapon.

.PARAMETER ChunkPakPath
    Explicit path to re_chunk_000.pak. Default: auto from GamePath.

.EXAMPLE
    # Full regeneration, no mods:
    .\regen_txtp.ps1

    # Single weapon only:
    .\regen_txtp.ps1 -BankFilter "ch_wp6001"

    # Also copy to FusionTools:
    .\regen_txtp.ps1 -FusionToolsDir "<FusionTools-RE4R-root>"
#>

[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$WwiserPath    = "<downloads-root>\wwiser.pyz",
    [string]$ReePakPath    = "",
    [string]$BankListPath  = "<REtool-root>\RE4R_weapon_wwise_banks.list",
    [string]$TxTPOutDir    = "",
    [string]$FusionToolsDir = "",
    [string]$TempDir       = "",
    [string]$BankFilter    = "ch_wp",
    [string]$ChunkPakPath  = ""
)

Set-StrictMode -Version Latest
# 'Continue' required: native exes (ree-pak-cli, wwiser) write progress to
# stderr; PS 5.1 wraps this as NativeCommandError and 'Stop' would abort.
$ErrorActionPreference = 'Continue'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $ReePakPath)  { $ReePakPath  = Join-Path $scriptDir "extract_sounds\ree-pak-cli.exe" }
if (-not $TxTPOutDir)  { $TxTPOutDir  = Join-Path $scriptDir "txtp" }
if (-not $TempDir)     { $TempDir     = Join-Path $env:TEMP "re4r_txtp_regen" }

# ---------------------------------------------------------------------------
# Validate tools
# ---------------------------------------------------------------------------

$pyCmdPy = Get-Command py -ErrorAction SilentlyContinue
$pyCmdPy3 = Get-Command python3 -ErrorAction SilentlyContinue
$pyExe = if ($pyCmdPy) { $pyCmdPy.Source } elseif ($pyCmdPy3) { $pyCmdPy3.Source } else { $null }
if (-not $pyExe) { Write-Error "Python (py.exe or python3) not found in PATH."; exit 1 }

foreach ($f in @($WwiserPath, $ReePakPath, $BankListPath)) {
    if (-not (Test-Path $f)) { Write-Error "Required file not found: $f"; exit 1 }
}

# ---------------------------------------------------------------------------
# Auto-detect game path
# ---------------------------------------------------------------------------

function Find-RE4RInstall {
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2050650',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 2050650'
    )) {
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

if (-not $GamePath) {
    $GamePath = Find-RE4RInstall
    if (-not $GamePath) { Write-Error "Could not auto-detect RE4R. Pass -GamePath."; exit 1 }
    Write-Host "Game path : $GamePath"
}

if (-not $ChunkPakPath) { $ChunkPakPath = Join-Path $GamePath "re_chunk_000.pak" }
if (-not (Test-Path $ChunkPakPath)) { Write-Error "re_chunk_000.pak not found: $ChunkPakPath"; exit 1 }

# ---------------------------------------------------------------------------
# Setup directories
# ---------------------------------------------------------------------------

$bnkDir  = Join-Path $TempDir "bnk"
$txtpTmp = Join-Path $TempDir "txtp"

New-Item -ItemType Directory -Force -Path $bnkDir  | Out-Null
New-Item -ItemType Directory -Force -Path $txtpTmp | Out-Null
New-Item -ItemType Directory -Force -Path $TxTPOutDir | Out-Null

Write-Host "txtp out  : $TxTPOutDir"
Write-Host "temp      : $TempDir"
Write-Host ""
Write-Host "NOTE: run with mods disabled to get clean unmodded txtp."
Write-Host ""

# ---------------------------------------------------------------------------
# Phase 1 — extract weapon banks from all pak files (base + patches)
# ---------------------------------------------------------------------------

Write-Host "Extracting weapon banks from pak..."

# Read the full bank list and filter to weapon banks matching BankFilter.
$allBankPaths = Get-Content $BankListPath | Where-Object {
    $_ -match $BankFilter -and $_ -match '\.sbnk\.1\.x64$'
}

Write-Host "  $($allBankPaths.Count) bank paths match filter '$BankFilter'"

# RE4R stores banks across the base pak and patch paks. Iterate highest-priority
# patch first (highest number = newest); skip banks already found in earlier paks.
$filterRegex = "ch_wp.*\.sbnk\.1\.x64"
$bs = [char]92

$pakDir = Split-Path $ChunkPakPath
$baseName = [IO.Path]::GetFileName($ChunkPakPath)
$patchPaks = @(Get-ChildItem $pakDir -Filter "$baseName.patch_*.pak" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending)  # highest patch number first (highest priority)

$allPaks = @($patchPaks) + @($ChunkPakPath)

foreach ($pak in $allPaks) {
    $pakPath = if ($pak -is [string]) { $pak } else { $pak.FullName }
    $pakLabel = [IO.Path]::GetFileName($pakPath)

    # Only extract banks not yet found in a higher-priority pak.
    $missing = @($allBankPaths | Where-Object { -not (Test-Path (Join-Path $bnkDir $_.Replace('/', $bs))) })
    if ($missing.Count -eq 0) { break }

    # Build a per-pak filter from only the missing filenames so we don't
    # overwrite already-extracted (higher-priority) banks.
    $missingFilter = ($missing | ForEach-Object { [regex]::Escape([IO.Path]::GetFileName($_)) }) -join "|"

    Write-Verbose "  Searching $pakLabel for $($missing.Count) missing banks..."
    & $ReePakPath unpack `
        -p $BankListPath `
        -i $pakPath `
        -o $bnkDir `
        -f $missingFilter `
        --skip-unknown | Write-Verbose
}

$extracted = @($allBankPaths | Where-Object { Test-Path (Join-Path $bnkDir $_.Replace('/', $bs)) })
Write-Host "  Extracted : $($extracted.Count) / $($allBankPaths.Count) banks"

if ($extracted.Count -eq 0) {
    Write-Error "No banks extracted. Check -BankListPath and pak path."
    exit 1
}

# ---------------------------------------------------------------------------
# Phase 2 — rename .sbnk.1.x64 → .bnk (wwiser needs .bnk extension)
# ---------------------------------------------------------------------------

Write-Host "Renaming banks to .bnk ..."

$bnkFiles = [System.Collections.Generic.List[string]]::new()

foreach ($relPath in $extracted) {
    $srcPath = Join-Path $bnkDir $relPath.Replace('/', $bs)
    $bnkName = [IO.Path]::GetFileName($relPath) -replace '\.sbnk\.1\.x64$', '.bnk'
    $dstPath = Join-Path $bnkDir $bnkName

    if (-not (Test-Path $dstPath)) {
        Copy-Item $srcPath $dstPath
    }
    $bnkFiles.Add($dstPath)
}

Write-Host "  $($bnkFiles.Count) .bnk files ready"

# ---------------------------------------------------------------------------
# Phase 3 — run wwiser to generate txtp
# ---------------------------------------------------------------------------

# Only pass structure banks (not media) as input; wwiser finds media banks
# automatically when they're in the same directory.
$structureBnks = @($bnkFiles | Where-Object { $_ -notmatch '_media\.bnk$' })

Write-Host "Running wwiser on $($structureBnks.Count) structure banks ..."
Write-Host "  (media banks are in the same dir and will be resolved automatically)"

$wwiserArgs = @($WwiserPath, '-g', '-go', $txtpTmp) + $structureBnks

# Run wwiser; PS 5.1: don't use 2>&1 on native exe (wraps stderr as ErrorRecord).
# Pipe stdout to Verbose; stderr prints directly to console.
& $pyExe @wwiserArgs | Write-Verbose
$wwiserExit = $LASTEXITCODE
if ($wwiserExit -ne 0) {
    Write-Warning "wwiser exited with code $wwiserExit"
}

$generatedTxtp = @(Get-ChildItem $txtpTmp -Filter "*.txtp" -ErrorAction SilentlyContinue)
Write-Host "  Generated : $($generatedTxtp.Count) txtp files"

if ($generatedTxtp.Count -eq 0) {
    Write-Error "wwiser produced no txtp files. Check wwiser output above."
    exit 1
}

# ---------------------------------------------------------------------------
# Phase 4 — copy txtp to output dir (and optionally FusionTools)
# ---------------------------------------------------------------------------

Write-Host "Copying txtp to $TxTPOutDir ..."
Copy-Item (Join-Path $txtpTmp "*.txtp") $TxTPOutDir -Force
Write-Host "  Done."

if ($FusionToolsDir) {
    if (Test-Path $FusionToolsDir) {
        Write-Host "Copying txtp to FusionTools dir: $FusionToolsDir ..."
        Copy-Item (Join-Path $txtpTmp "*.txtp") $FusionToolsDir -Force
        Write-Host "  Done."
    } else {
        Write-Warning "FusionToolsDir not found, skipping: $FusionToolsDir"
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$weaponCoverage = ($generatedTxtp.Name | ForEach-Object { [regex]::Match($_, 'ch_wp\d+').Value } |
    Sort-Object -Unique | Where-Object { $_ }) -join ', '

Write-Host ""
Write-Host "--- Done ---"
Write-Host "  txtp files : $($generatedTxtp.Count)"
Write-Host "  weapons    : $weaponCoverage"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Check tools\txtp\ for updated event files."
Write-Host "  2. Cross-reference event IDs with wwise_audio_router.lua candidates."
Write-Host "  3. Run setup_sounds.ps1 after updating sounds_manifest.json."
