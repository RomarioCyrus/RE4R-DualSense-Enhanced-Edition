# Generates haptic_footstep.wav: a synthesized low-frequency thump for the
# DualSense actuators (channels 3/4 haptics path). 48 kHz, 32-bit IEEE
# float, stereo. Pitch sweeps 110 -> 60 Hz with an exponential amplitude
# decay so it reads as a footstep impact rather than a buzz.
#
# Usage: powershell -File tools\generate_haptic_footstep.ps1 [-OutPath <wav>]
param(
    [string]$OutPath = (Join-Path $PSScriptRoot "..\src\reframework\data\DualSenseEnhanced\sounds\haptic_footstep.wav")
)

$sampleRate = 48000
$durationMs = 100
$attackMs = 2
$decayTauMs = 25
$startHz = 110.0
$endHz = 60.0
$peak = 0.9

$frames = [int]($sampleRate * $durationMs / 1000)
$samples = New-Object 'System.Collections.Generic.List[float]'

$phase = 0.0
for ($i = 0; $i -lt $frames; $i++) {
    $t = $i / $sampleRate
    $tMs = $t * 1000.0
    $freq = $startHz + ($endHz - $startHz) * ($tMs / $durationMs)
    $phase += 2.0 * [math]::PI * $freq / $sampleRate
    $attack = if ($tMs -lt $attackMs) { $tMs / $attackMs } else { 1.0 }
    $decay = [math]::Exp(-$tMs / $decayTauMs)
    $value = [float]([math]::Sin($phase) * $peak * $attack * $decay)
    $samples.Add($value) | Out-Null  # left
    $samples.Add($value) | Out-Null  # right
}

$OutPath = [System.IO.Path]::GetFullPath($OutPath)
$dataBytes = $samples.Count * 4
$stream = [System.IO.File]::Create($OutPath)
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $channels = 2
    $bitsPerSample = 32
    $blockAlign = $channels * ($bitsPerSample / 8)
    $byteRate = $sampleRate * $blockAlign

    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
    $writer.Write([uint32](36 + $dataBytes))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
    $writer.Write([uint32]16)
    $writer.Write([uint16]3)              # WAVE_FORMAT_IEEE_FLOAT
    $writer.Write([uint16]$channels)
    $writer.Write([uint32]$sampleRate)
    $writer.Write([uint32]$byteRate)
    $writer.Write([uint16]$blockAlign)
    $writer.Write([uint16]$bitsPerSample)
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
    $writer.Write([uint32]$dataBytes)
    foreach ($sample in $samples) {
        $writer.Write([float]$sample)
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output ("Wrote {0} ({1} frames, {2} bytes)" -f $OutPath, $frames, (Get-Item $OutPath).Length)
