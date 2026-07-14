<#
.SYNOPSIS
    Second-run step: generates real-audio footstep/companion haptic WAVs from
    the player's own freshly-extracted sounds (see setup_sounds.ps1).

.DESCRIPTION
    Audio-to-haptics (docs/HAPTICS_FOOTSTEPS_TASK.md): instead of a
    synthesized fixed-frequency tone, the haptic pulse for footsteps and
    several other events is derived from the real extracted RE4R sound
    effect -- downmixed to mono, single-pole low-pass filtered (DualSense
    actuators respond mainly below ~300Hz; everything above that is felt as
    an undifferentiated buzz, not texture), trimmed, duration-capped, and
    peak-normalized.

    This is a PowerShell port of tools/audio_to_haptic.py's exact algorithm
    (see that file for the reference implementation and rationale) so this
    step doesn't require Python on the player's machine -- setup_sounds.ps1
    already only depends on bundled .exe tools + PowerShell/.NET.

    The source WAVs this reads (wp4000_dry_fire1.wav, footstep_leon_raw1.wav,
    etc.) are themselves extracted from the player's own game files by
    setup_sounds.ps1's Phase 1/2, same as every other sound in this mod --
    this script must run AFTER setup_sounds.ps1, not standalone. The output
    haptic_*_real.wav files are therefore also generated locally and never
    distributed with the mod (see .gitignore / RELEASE_MANIFEST.md).

.PARAMETER SoundsPath
    Folder containing both the source WAVs (already extracted) and where the
    haptic_*_real.wav outputs are written.
    Default: same auto-detection as setup_sounds.ps1 (installed vs dev tree).

.PARAMETER Force
    Regenerate even if the target haptic WAV already exists.
#>

[CmdletBinding()]
param(
    [string]$SoundsPath = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $SoundsPath) {
    $installedOutput = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\..\reframework\data\DualSenseEnhanced\sounds"))
    $devOutput       = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\src\reframework\data\DualSenseEnhanced\sounds"))
    $installedRoot   = [IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\.."))

    if (Test-Path (Join-Path $installedRoot "reframework")) {
        $SoundsPath = $installedOutput
    } elseif (Test-Path $devOutput) {
        $SoundsPath = $devOutput
    } else {
        $SoundsPath = $installedOutput
    }
}

if (-not (Test-Path $SoundsPath)) {
    Write-Error "Sounds folder not found: $SoundsPath -- run setup_sounds.ps1 first."
    exit 1
}

# ---------------------------------------------------------------------------
# Audio-to-haptics conversion (PowerShell port of tools/audio_to_haptic.py)
# ---------------------------------------------------------------------------

function Read-WavMono {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 44 -or
        [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "RIFF" -or
        [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne "WAVE") {
        throw "$Path is not a RIFF/WAVE file"
    }

    $pos = 12
    $fmtFound = $false
    $dataFound = $false
    $channels = 0
    $sampleRate = 0
    $bitsPerSample = 0
    $dataOffset = 0
    $dataSize = 0

    while ($pos -lt $bytes.Length - 8) {
        $chunkId = [Text.Encoding]::ASCII.GetString($bytes, $pos, 4)
        $chunkSize = [BitConverter]::ToUInt32($bytes, $pos + 4)
        $chunkDataStart = $pos + 8

        if ($chunkId -eq "fmt ") {
            $channels = [BitConverter]::ToUInt16($bytes, $chunkDataStart + 2)
            $sampleRate = [BitConverter]::ToUInt32($bytes, $chunkDataStart + 4)
            $bitsPerSample = [BitConverter]::ToUInt16($bytes, $chunkDataStart + 14)
            $fmtFound = $true
        } elseif ($chunkId -eq "data") {
            $dataOffset = $chunkDataStart
            $dataSize = $chunkSize
            $dataFound = $true
        }

        # Chunks are word-aligned; odd-sized chunks have a padding byte.
        $advance = $chunkSize + ($chunkSize % 2)
        $pos = $chunkDataStart + $advance
        if ($fmtFound -and $dataFound) { break }
    }

    if (-not $fmtFound -or -not $dataFound) { throw "$Path missing fmt/data chunk" }
    if ($bitsPerSample -ne 16) { throw "$Path is $bitsPerSample-bit, only 16-bit PCM supported" }

    $sampleCount = [Math]::Floor($dataSize / 2)
    $raw = [Int16[]]::new($sampleCount)
    [System.Buffer]::BlockCopy($bytes, $dataOffset, $raw, 0, $sampleCount * 2)

    if ($channels -eq 1) {
        $mono = [double[]]::new($sampleCount)
        for ($i = 0; $i -lt $sampleCount; $i++) { $mono[$i] = $raw[$i] / 32768.0 }
    } else {
        $frameCount = [Math]::Floor($sampleCount / $channels)
        $mono = [double[]]::new($frameCount)
        for ($f = 0; $f -lt $frameCount; $f++) {
            $sum = 0
            for ($c = 0; $c -lt $channels; $c++) { $sum += $raw[$f * $channels + $c] }
            $mono[$f] = ($sum / $channels) / 32768.0
        }
    }

    return @{ Samples = $mono; SampleRate = $sampleRate }
}

function Apply-LowPass {
    param([double[]]$Samples, [int]$SampleRate, [double]$CutoffHz)
    # Single-pole RC low-pass -- see tools/audio_to_haptic.py's low_pass()
    # for the reference implementation and rationale.
    $dt = 1.0 / $SampleRate
    $rc = 1.0 / (2 * [Math]::PI * $CutoffHz)
    $alpha = $dt / ($rc + $dt)
    $out = [double[]]::new($Samples.Length)
    $prev = 0.0
    for ($i = 0; $i -lt $Samples.Length; $i++) {
        $prev = $prev + $alpha * ($Samples[$i] - $prev)
        $out[$i] = $prev
    }
    return $out
}

function Trim-Silence {
    param([double[]]$Samples, [int]$SampleRate, [double]$Threshold = 0.02, [double]$TailMs = 15)
    $start = 0
    for ($i = 0; $i -lt $Samples.Length; $i++) {
        if ([Math]::Abs($Samples[$i]) -gt $Threshold) { $start = $i; break }
    }
    $end = $Samples.Length
    for ($i = $Samples.Length - 1; $i -ge 0; $i--) {
        if ([Math]::Abs($Samples[$i]) -gt $Threshold) {
            $end = [Math]::Min($Samples.Length, $i + [int]($SampleRate * $TailMs / 1000.0))
            break
        }
    }
    if ($end -le $start) { return @() }
    return $Samples[$start..($end - 1)]
}

function Normalize-Samples {
    param([double[]]$Samples, [double]$TargetPeak = 0.95)
    if ($Samples.Length -eq 0) { return $Samples }
    $peak = ($Samples | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum
    if ($peak -lt 1e-6) { return $Samples }
    $scale = $TargetPeak / $peak
    return $Samples | ForEach-Object { $_ * $scale }
}

function Write-WavMono16 {
    param([string]$Path, [double[]]$Samples, [int]$SampleRate)

    $dataSize = $Samples.Length * 2
    $riffSize = 36 + $dataSize
    $stream = [IO.File]::Create($Path)
    try {
        $writer = New-Object IO.BinaryWriter($stream)
        $writer.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
        $writer.Write([uint32]$riffSize)
        $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
        $writer.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
        $writer.Write([uint32]16)
        $writer.Write([uint16]1)          # PCM
        $writer.Write([uint16]1)          # mono
        $writer.Write([uint32]$SampleRate)
        $writer.Write([uint32]($SampleRate * 2))  # byte rate
        $writer.Write([uint16]2)          # block align
        $writer.Write([uint16]16)         # bits per sample
        $writer.Write([Text.Encoding]::ASCII.GetBytes("data"))
        $writer.Write([uint32]$dataSize)
        foreach ($s in $Samples) {
            $v = [Math]::Max(-1.0, [Math]::Min(1.0, $s))
            $writer.Write([int16]($v * 32767))
        }
        $writer.Flush()
    } finally {
        $stream.Dispose()
    }
}

function Convert-ToHaptic {
    param(
        [string]$InPath,
        [string]$OutPath,
        [double]$CutoffHz = 220.0,
        [double]$Gain = 1.0,
        [double]$MaxDurationMs = 250
    )

    $wav = Read-WavMono -Path $InPath
    $filtered = Apply-LowPass -Samples $wav.Samples -SampleRate $wav.SampleRate -CutoffHz $CutoffHz
    $trimmed = Trim-Silence -Samples $filtered -SampleRate $wav.SampleRate

    $maxSamples = [int]($wav.SampleRate * $MaxDurationMs / 1000.0)
    if ($trimmed.Length -gt $maxSamples) {
        $fadeSamples = [Math]::Min([int]($wav.SampleRate * 0.02), [int]($maxSamples / 4))
        $trimmed = $trimmed[0..($maxSamples - 1)]
        for ($i = 0; $i -lt $fadeSamples; $i++) {
            $factor = 1.0 - ($i / $fadeSamples)
            $trimmed[$maxSamples - $fadeSamples + $i] *= $factor
        }
    }

    $normalized = Normalize-Samples -Samples $trimmed -TargetPeak (0.95 * $Gain)
    Write-WavMono16 -Path $OutPath -Samples $normalized -SampleRate $wav.SampleRate
    $durationMs = 1000.0 * $normalized.Length / $wav.SampleRate
    Write-Host ("  {0} -> {1} ({2:N0}ms, cutoff={3}Hz)" -f (Split-Path -Leaf $InPath), (Split-Path -Leaf $OutPath), $durationMs, $CutoffHz)
}

# ---------------------------------------------------------------------------
# Haptic targets -- source WAV (already extracted by setup_sounds.ps1) ->
# output haptic_*_real.wav, with per-target cutoff/gain/duration tuning.
# ---------------------------------------------------------------------------

$targets = @(
    @{ Source = "footstep_leon_raw1.wav"; Output = "haptic_footstep_real_soft.wav";   Cutoff = 220; Gain = 0.55; MaxMs = 70 }
    @{ Source = "footstep_leon_raw1.wav"; Output = "haptic_footstep_real.wav";        Cutoff = 200; Gain = 0.8;  MaxMs = 90 }
    @{ Source = "footstep_leon_raw1.wav"; Output = "haptic_footstep_real_strong.wav"; Cutoff = 180; Gain = 1.0;  MaxMs = 120 }
    @{ Source = "wp4000_dry_fire1.wav";   Output = "haptic_dry_fire_real.wav";        Cutoff = 250; Gain = 1.0;  MaxMs = 45 }
    @{ Source = "wp4000_aim_in1.wav";     Output = "haptic_aim_in_real.wav";          Cutoff = 220; Gain = 0.8;  MaxMs = 50 }
    @{ Source = "wp4003_aim_out1.wav";    Output = "haptic_aim_out_real.wav";         Cutoff = 220; Gain = 0.7;  MaxMs = 45 }
    @{ Source = "wp4000_draw1.wav";       Output = "haptic_draw_real.wav";            Cutoff = 200; Gain = 0.85; MaxMs = 140 }
    @{ Source = "heal_herb.wav";          Output = "haptic_heal_real.wav";            Cutoff = 180; Gain = 0.6;  MaxMs = 200 }
)

Write-Host "Generating real-audio haptic companions (audio-to-haptics)..."
Write-Host "Output: $SoundsPath"
Write-Host ""

$ok = 0
$skip = 0
$err = 0

foreach ($t in $targets) {
    $srcPath = Join-Path $SoundsPath $t.Source
    $outPath = Join-Path $SoundsPath $t.Output

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Verbose "  [skip] $($t.Output)"
        $skip++
        continue
    }
    if (-not (Test-Path $srcPath)) {
        Write-Warning "  Source not found, skipping: $($t.Source) (run setup_sounds.ps1 first)"
        $err++
        continue
    }

    try {
        Convert-ToHaptic -InPath $srcPath -OutPath $outPath -CutoffHz $t.Cutoff -Gain $t.Gain -MaxDurationMs $t.MaxMs
        $ok++
    } catch {
        Write-Warning "  Failed: $($t.Output) -- $_"
        $err++
    }
}

Write-Host ""
Write-Host "--- Done ---"
Write-Host "  Generated : $ok"
Write-Host "  Skipped   : $skip (already present)"
Write-Host "  Errors    : $err"

if ($err -gt 0) {
    Write-Warning "Some haptic WAVs could not be generated -- footstep/companion haptics will fall back to whichever WAVs are missing being silently skipped by the bridge."
}

exit 0
