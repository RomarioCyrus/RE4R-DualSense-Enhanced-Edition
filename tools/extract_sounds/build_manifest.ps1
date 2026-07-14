<#
.SYNOPSIS
    Generates sounds_manifest.json from MANIFEST.csv.
    Maps each runtime WAV event name to its source WEM ID and bank PAK path.

.DESCRIPTION
    Reads the weapon sound catalog (MANIFEST.csv) and produces a JSON manifest
    that the setup_sounds.ps1 script uses at first-run to recreate all sounds
    from the user's own RE4R installation — no Capcom audio assets shipped in
    the mod itself.

    Each manifest entry is one output WAV file:
      event_name -> { bank_pak, bank_file, wem_id }

    bank_pak uses the source weapon's bank (may differ from the runtime event's
    weapon when a weapon borrows another's audio assets, e.g. CQBR uses
    Stingray's bank for some sounds).

.NOTES
    Run from the project root:
        .\tools\extract_sounds\build_manifest.ps1
#>

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$OutputPath  = (Join-Path $PSScriptRoot "sounds_manifest.json")
)

$csvPath = Join-Path $ProjectRoot "speaker\weapon_sound_catalog_v2\MANIFEST.csv"

if (-not (Test-Path $csvPath)) {
    Write-Error "MANIFEST.csv not found at: $csvPath"
    exit 1
}

# Statuses we generate sounds for.
$includedStatuses = @('confirmed', 'implemented_unverified', 'user_confirmed', 'global')

$rows = Import-Csv $csvPath

$manifest = [ordered]@{}
$skipped  = 0

foreach ($row in $rows) {
    # Must have a runtime sound file.
    if ([string]::IsNullOrWhiteSpace($row.runtime_file)) { $skipped++; continue }
    # Must have a source file with a WEM ID.
    if ([string]::IsNullOrWhiteSpace($row.source_file))  { $skipped++; continue }
    # Only include confirmed/implemented sounds.
    if ($row.status -notin $includedStatuses)             { $skipped++; continue }

    # Event name = stem of the runtime WAV path.
    $eventName = [IO.Path]::GetFileNameWithoutExtension($row.runtime_file)

    # WEM ID = last numeric segment in the source filename.
    # "01_949138148"           -> 949138148
    # "event_0234_01_295611387" -> 295611387
    # "739405"                  -> 739405
    $srcStem = [IO.Path]::GetFileNameWithoutExtension($row.source_file)
    if ($srcStem -notmatch '(\d+)$') {
        Write-Warning "Cannot parse WEM ID from source_file '$($row.source_file)' -- skipping $eventName"
        $skipped++
        continue
    }
    $wemId = [long]$Matches[1]

    # Bank path: prefer the wpNNNN from source_file, but source_file paths under
    # review packages may start with a multi-weapon folder name like
    # "handguns_wp4000_wp4004_deduplicated_v1\wp4001_Punisher\..." which causes
    # the first regex match to be the wrong weapon.
    # Strategy: collect ALL wpNNNN matches in source_file; if exactly one unique
    # value → use it. If multiple → fall back to the weapon derived from runtime_file,
    # which is always authoritative for which bank to open.
    $srcMatches = [regex]::Matches($row.source_file, 'wp(\d{4})')
    $uniqueWpNums = @($srcMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($uniqueWpNums.Count -eq 1) {
        $wpNum = $uniqueWpNums[0]
    } elseif ($uniqueWpNums.Count -gt 1) {
        # Ambiguous source path — derive from runtime_file (e.g. "sounds/wp4001_reload_start.wav")
        if ($row.runtime_file -match 'wp(\d{4})') {
            $wpNum = $Matches[1]
        } else {
            Write-Warning "Cannot determine bank for '$eventName' (ambiguous source path, no wp in runtime) — skipping"
            $skipped++
            continue
        }
    } else {
        Write-Warning "No wpNNNN pattern in source_file '$($row.source_file)' — skipping $eventName"
        $skipped++
        continue
    }
    $wpNum    = $wpNum  # already set above
    $bankFile = "ch_wp${wpNum}_media.sbnk.1.x64"
    $bankPak  = "natives/stm/_chainsaw/sound/wwise/ch_wp${wpNum}_media.sbnk.1.x64"

    if ($manifest.Contains($eventName)) {
        Write-Warning "Duplicate event_name '$eventName' — keeping first entry."
        continue
    }

    $manifest[$eventName] = [ordered]@{
        bank_pak  = $bankPak
        bank_file = $bankFile
        wem_id    = $wemId
    }
}

$manifest | ConvertTo-Json -Depth 3 | Set-Content $OutputPath -Encoding UTF8

Write-Host "sounds_manifest.json written to: $OutputPath"
Write-Host "  Events mapped : $($manifest.Count)"
Write-Host "  Rows skipped  : $skipped"



