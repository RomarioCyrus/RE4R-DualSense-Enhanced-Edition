# DualSense Enhanced v1.0 Release Handoff - 2026-07-07

This handoff is for the next agent that will finish the first public
NexusMods/GitHub release.

> **2026-07-14 update:** the repository has moved beyond this handoff's
> numerical baseline. The current extractor configuration is 709 sounds across
> 26 banks. The old 688/25 results below are historical; fresh zero-error tests
> passed on 2026-07-14 in both layouts: `676/676` with the optional Sentinel
> Nine DLC absent and `709/709` with it present. Use
> `release/v1.0/RELEASE_MANIFEST.md` for current package policy. Enhanced
> Haptics and per-item healing audio/haptics now ship in v1.0; the older feature
> scope in this dated handoff is historical.

## Repositories

Canonical dev checkout, source of truth:

```text
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project
```

Release checkout, staging/package target only:

```text
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project - Release v1.0
```

Do not continue runtime, C#, extractor, or weapon-audio feature work in the
release checkout. Make source changes in canonical dev, commit there, then sync
to the release checkout.

## Current Baseline

Latest important commits in canonical dev:

```text
656669e fix(extractor): read Sentinel Nine sounds from DLC pak
6ae10da fix(extractor): sync required bank list with sound manifest
7f17847 fix(audio): add inventory UI sounds to extraction manifest
6624aa9 chore(repo): ignore local wav scratch files
3fdf269 fix(release): use verified transport publish-fixed artifact
66c4d50 fix(tools): mirror-delete orphaned files in deploy.ps1, flag them in verify
84b9caf audio: add knife action speaker sounds (hit/surface/stealth/finisher/swing/draw)
```

Known verified state:

- Dev tracked worktree was clean after `656669e`.
- `tools/verify_deploy.ps1` passed after the transport artifact path was aligned
  to `publish-fixed`: 619 deployed files matched source.
- `RELEASE_BUILD = true` UI smoke test passed manually on 2026-07-07; the UI
  looked good and debug/experimental panels were hidden.
- Superseding note (2026-07-14): a later professional consistency pass changed
  section order, quick controls, units, mode markers, Enhanced Haptics rows,
  and test feedback. The older smoke result still proves release gating, but
  does not visually validate the new layout; repeat it before public release.
- `setup_sounds.ps1` full temporary-folder extractor test passed on 2026-07-07:
  688 extracted, 0 errors, 688 required WAV files present.
- The successful extractor test included:
  - `qte.wav`
  - `ui_inventory_open.wav`
  - `ui_inventory_close.wav`
  - `wp6000_aim_in1.wav`
  - `wp6000_last_shot14.wav`
- Sentinel Nine (`wp6000`) is extracted from
  `dlc\re_dlc_stm_2109308.pak`; base-game sounds are extracted from
  `re_chunk_000.pak`.

Local ignored scratch folders may exist and must not be packaged:

```text
tmp_wav/
tmp_extractor_test/
tmp_dlc_bank_probe/
```

## Release Policy

Use `release/v1.0/RELEASE_MANIFEST.md` as the package surface. The short version:

- Nexus ZIP must not include Capcom WAV files.
- Nexus ZIP must not include `docs/`, `speaker/` source, build caches, PDBs,
  logs, debug/probe folders, or extracted WAVs.
- User-facing release copy should not claim DSX compatibility for v1.0.
- `DualSenseEnhanced.lua` must be staged with `RELEASE_BUILD = true`.
- Dev source must keep `RELEASE_BUILD = false`.
- Debug/experimental UI and modules stay in source, but must not be packaged or
  drawn in release mode.

## Remaining Release Steps

1. Confirm canonical dev is clean.

```powershell
git status --short
git log --oneline -n 12
```

Only ignored scratch folders should exist locally. Do not commit generated WAVs.

2. Dry-run release sync.

```powershell
powershell -ExecutionPolicy Bypass -File tools\sync_to_release.ps1 -WhatIf
```

Check warnings. Build outputs that must exist before final sync:

- `speaker/DualsenseAudioBridge/launcher-nativeaot/publish/DualsenseAudioBridgeLauncher.dll`
- `speaker/DualsenseAudioBridge/dist/native-autostart/DualsenseAudioBridge.exe`
- `speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/publish-fixed/DualSenseEnhancedTransport.exe`
- `speaker/DualSenseEnhancedTransport/third_party/build_out/duaLib.dll`
- `speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/hidapi.dll`

3. Run release sync.

```powershell
powershell -ExecutionPolicy Bypass -File tools\sync_to_release.ps1
```

Then inspect the release checkout, not dev:

```powershell
git status --short
git diff --stat
git diff --name-status
```

4. Audit release checkout package surface.

Required top-level/package files:

- `setup_sounds.bat`
- `THIRD_PARTY_LICENSES.txt`
- `modinfo.ini`
- `README.txt`
- `VERSION.txt`

Important: canonical dev currently has `setup_sounds.bat` and
`THIRD_PARTY_LICENSES.txt`, but `modinfo.ini`, `README.txt`, and `VERSION.txt`
were not visible in dev root at handoff time. Verify whether they already exist
in release checkout or need to be created from the release description/docs.

Required runtime/extractor files are listed in
`release/v1.0/RELEASE_MANIFEST.md`.

Must not be present in release package:

- `docs/`
- `speaker/`
- `.git/`, `.github/`, `.codex/`, `.agents/`, `.claude/`
- `deployment_backups/`
- `tmp_*`
- `*.pdb`
- `*.log`, `*_debug.txt`
- `src/reframework/data/DualSenseEnhanced/sounds/*.wav`
- `reframework/data/DualSenseEnhanced/sounds/*.wav` in the shipped ZIP
- debug-only runtime modules:
  - `monitor.lua`
  - `capcom_haptics_diag.lua`
  - `sound_event_diag.lua`
  - `radio_dialogue.lua`
  - `debug_led.lua`
  - `weapon_equip_ui.lua`

5. Verify release-mode loader in the release checkout.

The release copy of:

```text
src/reframework/autorun/DualSenseEnhanced.lua
```

must contain:

```lua
local RELEASE_BUILD = true
```

The canonical dev source must remain:

```lua
local RELEASE_BUILD = false
```

6. Test the packaged extractor from release layout.

Do not test only the dev script. Test the user-facing layout:

- `setup_sounds.bat` at package/game-root level
- extractor tools under `DualSenseEnhanced/tools/extract_sounds/`
- output under `reframework/data/DualSenseEnhanced/sounds/`

Expected result:

```text
Extracted : 688
Errors    : 0
Verified  : 688 required WAV files present
```

Also spot-check:

```text
qte.wav
ui_inventory_open.wav
ui_inventory_close.wav
wp6000_aim_in1.wav
wp6000_last_shot14.wav
```

7. Runtime smoke tests.

Already passed informally:

- latest runtime works normally in dev mode;
- release-mode UI looked good after `Reset Scripts`.

Still required before public release:

- visually test the 2026-07-14 UI consistency pass after `Reset Scripts`,
  including a narrow REFramework window and `RELEASE_BUILD = true`;
- `Reset Defaults` in REFramework, confirm defaults apply and are not overridden
  unexpectedly by existing `RE4R_DualSense_settings.lua`;
- main menu;
- load save;
- new game if time permits;
- game restart;
- controller reconnect/disconnect;
- crash recovery if practical.

8. Hardware test matrix.

Mark claims only after physical testing:

- DualSense USB
- DualSense Edge USB
- two controllers connected simultaneously
- native Bluetooth
- Bluetooth + DSX + DSX DLC
- DS5Dongle
- controller reconnect/disconnect
- DLC / Separate Ways only if actually tested

9. Final docs/copy.

Prepare or verify:

- Nexus description
- Nexus requirements
- Nexus installation steps
- Known issues
- FAQ
- Changelog
- GitHub README
- Credits and license notices

Credits must include lunatiii:

```text
lunatiii - weapon adaptive trigger reference values
https://www.nexusmods.com/profile/lunatiii
```

Tool/license notices must include ree-pak-rs / ree-pak-cli:

```text
MIT License, Copyright (c) 2024 Eigeen
```

## Suggested Commit Boundaries

Keep commits narrow:

- `chore(release): sync v1.0 package staging from dev`
- `docs(release): add Nexus and GitHub release copy`
- `fix(release): correct package surface audit findings`
- `test(release): document v1.0 hardware smoke results`

Do not mix runtime fixes, package sync, generated WAVs, hardware-result docs,
and release copy in one commit.

## Ready-To-Paste Prompt For The Next Agent

```text
You are taking over the Resident Evil 4 DualSense Enhanced Edition v1.0 release.

Read first:
- docs/AGENTS.md
- docs/MEMORY.md
- release/v1.0/RELEASE_MANIFEST.md
- docs/RELEASE_HANDOFF_2026-07-07.md

Canonical dev checkout:
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project

Release checkout/staging target:
$env:USERPROFILE\Documents\Dualsense_DSX_RE4R_Project\Dualsense DSX RE4R Project - Release v1.0

Rules:
- Work from canonical dev as source of truth.
- Do not do feature/runtime commits in the release checkout.
- Do not use git add .
- Do not package Capcom WAVs or generated sounds.
- Preserve RELEASE_BUILD=false in dev; release copy must use RELEASE_BUILD=true.
- Keep commits narrow and report staged files before committing.

Current verified state:
- Release-mode UI smoke test passed manually on 2026-07-07.
- tools/verify_deploy.ps1 passed after transport publish-fixed alignment.
- Full temporary extractor test passed on 2026-07-07:
  Extracted 688, Errors 0, Verified 688 WAV files present.
- Sentinel Nine wp6000 extraction uses dlc\re_dlc_stm_2109308.pak.

Task:
Finish v1.0 release staging.

Steps:
1. Confirm dev git status/log.
2. Run tools/sync_to_release.ps1 -WhatIf and resolve missing build outputs.
3. Run tools/sync_to_release.ps1.
4. Audit release checkout against release/v1.0/RELEASE_MANIFEST.md.
5. Ensure no docs/source/PDB/logs/tmp/generated WAVs/debug-only modules are in the package.
6. Ensure release DualSenseEnhanced.lua has RELEASE_BUILD=true.
7. Completed 2026-07-14: current extractor logic passed scratch validation in
   both modes. Without Sentinel Nine DLC: `676 present`, `33 optional skipped`,
   `0 errors`. With the DLC: `709 present`, `0 errors`.
8. Prepare or update README.txt, VERSION.txt, modinfo.ini, Nexus copy, GitHub README, FAQ, Known Issues, Credits, and Changelog.
9. Leave hardware matrix as unclaimed until physically tested by the project owner.

Do not create the final public ZIP until package surface audit and extractor test pass from the release layout.
```
