# Sound Extraction Tools

DualSense Enhanced Edition plays controller-speaker sounds sourced from RE4R's
own audio banks. To avoid distributing Capcom's copyright-protected audio, the
mod does not ship extracted `.wav` files. This tool extracts only the required
sounds from the user's own installed copy of the game. It then generates the
audio-derived Enhanced Haptics WAVs locally, so those derivatives are not
redistributed either.

Run this once after installing the mod. After extraction, sounds work
automatically on later game launches.

## Quick Start

1. Install the mod via Fluffy Mod Manager, or manually into the game folder.
2. Double-click `setup_sounds.bat` in the RE4R game folder.
3. Check the final success/error message.

All required extraction tools are bundled with the Nexus package.

## Installed Layout

```text
[RE4R game folder]/
├── re_chunk_000.pak
├── setup_sounds.bat
├── reframework/
└── DualSenseEnhanced/
    └── tools/
        └── extract_sounds/
            ├── setup_sounds.ps1
            ├── generate_haptics.ps1
            ├── sounds_manifest.json
            ├── DSE_Required_Banks.list
            ├── ree-pak-cli.exe
            └── vgmstream/
                ├── vgmstream-cli.exe
                └── *.dll
```

## Bundled Tools

| Tool | License | Purpose |
|---|---|---|
| `ree-pak-cli.exe` | MIT, eigeen | Extracts required banks from `re_chunk_000.pak` and the Sentinel Nine DLC pak when present |
| `DSE_Required_Banks.list` | Mod-generated filename list | Maps only the required RE4R banks for extraction |
| `vgmstream-cli.exe` + DLLs | vgmstream COPYING notice | Converts Wwise `.wem` audio to `.wav` |
| `generate_haptics.ps1` | Mod-authored PowerShell/.NET tool | Generates low-pass-filtered channels-3/4 haptic WAVs from the locally extracted audio |

The extractor uses `sounds_manifest.json` and only targets the banks needed by
the controller-speaker feature. It checks the base game pak first and also
reads `dlc\re_dlc_stm_2109308.pak` when present for Sentinel Nine (`wp6000`)
sounds. Sentinel Nine is optional: without that DLC pak, its 33 outputs are
skipped and the base-game extraction/verification continues normally.

## Audio Mod Notice

If you use audio mods that replace or modify RE4R `re_chunk` files, disable them
before running `setup_sounds.bat`. After extraction finishes successfully, you
can enable those audio mods again.

Audio replacement mods can prevent some banks from being found or converted.

## Troubleshooting

### The script cannot find the game folder

Run `setup_sounds.bat` directly from the RE4R game folder. The script also tries
to auto-detect the default Steam installation path.

### The script reports missing WAV files

Make sure the mod is installed in the game folder, disable audio replacement
mods temporarily, and run `setup_sounds.bat` again.

### Sounds are still not working after successful extraction

Open the REFramework UI and check the DualSense Enhanced controller speaker
settings. The UI should report missing WAV files if extraction did not create
the required audio files.

## Coverage

The current manifest defines 709 WAV files from 26 Wwise banks. It
covers weapon reload/action sounds, knife and pickup cues, inventory/QTE UI,
and per-item healing audio. After extraction, `generate_haptics.ps1` creates
the audio-derived files used by Enhanced Haptics for footsteps, dry fire,
aim/draw, and healing.

- Base game without Sentinel Nine DLC: 676 required WAVs; 33 optional Sentinel
  Nine outputs are skipped.
- Installation with `re_dlc_stm_2109308.pak`: all 709 WAVs are required.

Release validation completed 2026-07-14 against the expanded 709/26
configuration using clean scratch output:

- Without the Sentinel Nine DLC: `676 extracted / 0 errors / 33 optional
  skipped / 676 present`.
- With the DLC: `709 extracted / 0 errors / 709 present`.

Pending future work:

- Additional DLC-specific routes if they are confirmed later
- Future non-weapon speaker features, such as radio routing

## Developer Commands

Regenerate `sounds_manifest.json` after updating the source manifest:

```powershell
powershell -ExecutionPolicy Bypass -File "tools\extract_sounds\build_manifest.ps1"
```

Re-extract after a manifest update:

```powershell
powershell -ExecutionPolicy Bypass -File "tools\extract_sounds\setup_sounds.ps1" -Force
```

Useful parameters:

| Parameter | Default | Description |
|---|---|---|
| `-GamePath` | Auto-detected or BAT folder | RE4R game folder |
| `-ChunkPakPath` | `re_chunk_000.pak` in `GamePath` | Override source pak |
| `-ReePakPath` | `ree-pak-cli.exe` next to script | `ree-pak-cli` binary |
| `-HashListPath` | `DSE_Required_Banks.list` next to script | Minimal RE4R filename list |
| `-VGMStreamPath` | `vgmstream\vgmstream-cli.exe` | vgmstream binary |
| `-OutputSoundsPath` | Installed `reframework\data\DualSenseEnhanced\sounds` | WAV output folder |
| `-TempDir` | `%TEMP%\re4r_dsx_sounds` | Scratch folder |
| `-Force` | off | Re-extract even if WAV already exists |
