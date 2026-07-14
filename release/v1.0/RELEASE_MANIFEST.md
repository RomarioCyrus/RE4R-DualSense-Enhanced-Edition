# Resident Evil 4 - DualSense Enhanced Edition v1.0 Release Manifest

Status: release-candidate package definition. This is the curated Nexus package surface, not the full
GitHub/dev repository. This manifest is maintained from the dev checkout; the
separate release checkout is a packaging/staging target, not a place to edit
source independently (see `docs/AGENTS.md`'s Commit Rules).

Run `tools/sync_to_release.ps1` from the dev checkout to copy the files below
into the release checkout instead of hand-editing them there -- that is the
workflow that caused dev and release to diverge before 2026-07-04.

For the current release handoff and next-agent task list, see
`docs/RELEASE_HANDOFF_2026-07-07.md`.

## Release Policy

- GitHub/dev repo may keep source code, diagnostics, hook discovery tools,
  build scripts, and research docs.
- Nexus ZIP must contain only the installable Fluffy Mod Manager package and
  bundled runtime/extractor dependencies.
- Do not distribute Capcom audio assets, WAV files extracted from RE4R, or
  audio-to-haptics derivatives of extracted RE4R audio.
- The package may include the explicit creator-owned WAV allowlist below:
  custom healing cues generated with AI tools by the mod author, haptic
  derivatives of those cues, and original synthesized haptic tones generated
  by `tools/gen_haptic_wavs.py`. These contain no Capcom audio. Never replace
  the allowlist with a wildcard copy of the development `sounds/` folder.
- Do not include `DualSenseX`/`DualsenseX` naming or paths in v1.0 package.
- DSX compatibility is not a v1.0 release claim. Any remaining DSX references
  should be internal source comments or future/legacy notes, not user-facing
  release copy.
- Keep error logging that helps users report issues. Exclude hook discovery,
  Wwise capture, and noisy temporary logging from the Nexus package.
- Debug/experimental UI (event monitor, native haptics diagnostics, Wwise
  event logger, radio speaker routing, the Knife Hit audio toggle) is not
  deleted from the source -- it is gated behind the `RELEASE_BUILD` local flag
  at the top of `src/reframework/autorun/DualSenseEnhanced.lua`. Set it to
  `true` before staging the Nexus package so those modules do not load and
  their UI does not draw; leave it `false` for normal dev work. This keeps one
  source file instead of a second hand-maintained copy.

## Package Root

```text
Resident Evil 4 - DualSense Enhanced Edition/
```

## Include In Nexus ZIP

Top-level package files:

- `modinfo.ini`
- `README.txt`
- `VERSION.txt`
- `setup_sounds.bat`
- `THIRD_PARTY_LICENSES.txt`

Runtime Lua:

- `reframework/autorun/DualSenseEnhanced.lua` (with `RELEASE_BUILD = true`)
- `reframework/autorun/DualSenseEnhanced/ammo_led.lua`
- `reframework/autorun/DualSenseEnhanced/audio_feedback.lua`
- `reframework/autorun/DualSenseEnhanced/dualib_trigger_ipc.lua`
- `reframework/autorun/DualSenseEnhanced/events_led.lua`
- `reframework/autorun/DualSenseEnhanced/feedback_writer.lua`
- `reframework/autorun/DualSenseEnhanced/hp_led.lua`
- `reframework/autorun/DualSenseEnhanced/item_ids.lua`
- `reframework/autorun/DualSenseEnhanced/mic_led.lua`
- `reframework/autorun/DualSenseEnhanced/native_feedback.lua`
- `reframework/autorun/DualSenseEnhanced/native_gyro.lua`
- `reframework/autorun/DualSenseEnhanced/player_movement.lua`
- `reframework/autorun/DualSenseEnhanced/settings.lua`
- `reframework/autorun/DualSenseEnhanced/trigger_intensity.lua`
- `reframework/autorun/DualSenseEnhanced/weapon_equip_core.lua`
- `reframework/autorun/DualSenseEnhanced/wwise_audio_router.lua`

Do not package (loaded only when `RELEASE_BUILD = false`):

- `reframework/autorun/DualSenseEnhanced/monitor.lua`
- `reframework/autorun/DualSenseEnhanced/capcom_haptics_diag.lua`
- `reframework/autorun/DualSenseEnhanced/sound_event_diag.lua`
- `reframework/autorun/DualSenseEnhanced/radio_dialogue.lua`
- `reframework/autorun/DualSenseEnhanced/movement_diag.lua`

Never loaded by the main loader at all, `RELEASE_BUILD` or not (existing v1.0
UI Direction rule in `docs/AGENTS.md`) -- do not package either:

- `reframework/autorun/DualSenseEnhanced/debug_led.lua`
- `reframework/autorun/DualSenseEnhanced/weapon_equip_ui.lua`

Runtime data:

- `reframework/data/RE4R_WeaponData.lua`
- `reframework/data/DualSenseEnhanced/DualSenseEnhancedConfig.txt`
- `reframework/data/DualSenseEnhanced/transport_mode.txt`
- `reframework/data/DualSenseEnhanced/weapon_trigger_profiles.lua`
- `reframework/data/DualSenseEnhanced/sounds/` as the local extraction output
  directory, pre-populated only with this creator-owned allowlist:

  ```text
  heal_beetle.wav
  heal_egg.wav
  heal_egg_brown.wav
  heal_egg_gold.wav
  heal_fish.wav
  heal_fish_large.wav
  heal_fish_lunker.wav
  heal_herb.wav
  heal_herb_mock.wav
  heal_herb_rare.wav
  heal_viper.wav
  haptic_heal_beetle.wav
  haptic_heal_egg.wav
  haptic_heal_egg_brown.wav
  haptic_heal_egg_gold.wav
  haptic_heal_fish.wav
  haptic_heal_fish_large.wav
  haptic_heal_fish_lunker.wav
  haptic_heal_herb.wav
  haptic_heal_herb_mock.wav
  haptic_heal_herb_rare.wav
  haptic_heal_viper.wav
  haptic_footstep.wav
  haptic_footstep_soft.wav
  haptic_footstep_strong.wav
  haptic_impact_medium.wav
  haptic_impact_strong.wav
  haptic_parry.wav
  haptic_pickup.wav
  ```

  The `heal_*` entries above are AI-generated by the mod author. The
  `haptic_heal_*` entries are derived only from those author-owned cues; the
  remaining `haptic_*` entries are original synthesized tones.
  **`haptic_*_real.wav` files (footstep/dry-fire/aim/draw/heal
  audio-to-haptics companions, see `docs/HAPTICS_FOOTSTEPS_TASK.md`) are
  NEVER packaged** -- they are derivatives of extracted Capcom audio
  (low-pass filtered, not re-synthesized), so the same "do not distribute
  extracted Capcom audio" rule applies to them as to the plain speaker WAVs.
  `setup_sounds.bat` generates them locally on the player's own machine via
  `generate_haptics.ps1` (a PowerShell port of `tools/audio_to_haptic.py`,
  which itself is a dev-only tool and also NOT packaged -- it requires
  Python, which regular users won't have).

Runtime binaries:

- `reframework/plugins/DualsenseAudioBridgeLauncher.dll`
  from `speaker/DualsenseAudioBridge/launcher-nativeaot/publish/`.
- `reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe`
  from `speaker/DualsenseAudioBridge/dist/native-autostart/` or the selected
  v1.0 portable audio build.
- `reframework/data/DualSenseEnhanced/DualSenseEnhancedTransport.exe`
  from `speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/publish-fixed/`.
- `reframework/data/DualSenseEnhanced/duaLib.dll`
  from `speaker/DualSenseEnhancedTransport/third_party/build_out/duaLib.dll`
  unless a newer lightbar-allowled build is explicitly verified.
- `reframework/data/DualSenseEnhanced/hidapi.dll`
  from the verified trigger transport release output.

Audio extractor:

- `DualSenseEnhanced/tools/extract_sounds/setup_sounds.ps1`
- `DualSenseEnhanced/tools/extract_sounds/generate_haptics.ps1` -- runs after
  `setup_sounds.ps1` (see `setup_sounds.bat`), generates the `haptic_*_real.wav`
  audio-to-haptics companions locally from the sounds `setup_sounds.ps1` just
  extracted. Pure PowerShell/.NET, no Python dependency.
- `DualSenseEnhanced/tools/extract_sounds/sounds_manifest.json`
- `DualSenseEnhanced/tools/extract_sounds/ree-pak-cli.exe`
- `DualSenseEnhanced/tools/extract_sounds/DSE_Required_Banks.list`
- `DualSenseEnhanced/tools/extract_sounds/vgmstream/vgmstream-cli.exe`
- `DualSenseEnhanced/tools/extract_sounds/vgmstream/*.dll`

## Exclude From Nexus ZIP

- `.git/`, `.github/`, `.codex/`, `.agents/`, `.claude/`
- `docs/` development handoffs and research notes
- `deployment_backups/`
- `speaker/` source tree, `.dotnet/`, `bin/`, `obj/`, toolchains, build caches
- `tools/verify_deploy.ps1`
- `tools/extract_sounds/build_manifest.ps1`
- `tools/audio_to_haptic.py` and `tools/gen_haptic_wavs.py` -- dev-only,
  require Python; `generate_haptics.ps1` is the packaged equivalent for
  audio-to-haptics, the synthesized-tone script has no release-time role
  at all (its output ships as a static asset, see Release Policy above).
- `src/reframework/data/DualSenseEnhanced/sounds/*.wav` except the exact
  creator-owned allowlist under Runtime data above. In particular,
  `heal_spray.wav`, knife/weapon/UI/gameplay WAVs, and all
  `haptic_*_real.wav` files are excluded.
- PDB files
- Logs: `*.log`, `*_debug.txt`, `sound_event_ids.log`,
  `sound_event_diag.log`, `events_debug.txt`, `native_lightbar_debug.txt`
- DSX UDP tooling:
  - `DSX_UDPClient.exe`
  - `DSX_UDPClient_Test.exe`
  - `speaker/DualsenseAudioBridge/experimental-dsx-client/`
  - `speaker/DualsenseAudioBridge/dist/experimental-dsx-client/`
- Manual native test BAT files:
  - `01_CHECK_DLLS.bat`
  - `02_TEST_L2_WEAK.bat`
  - `03_RESET_TRIGGERS.bat`
  - `04_WATCH_RE4R_NATIVE.bat`
- Experimental HID/audio-haptics folders not used by v1.0 runtime.

## Current Audit Findings

- `src/reframework/data/DualSenseEnhanced/sounds` is a development/deployment
  tree containing extracted and generated WAV files. They must not be copied
  wholesale into the Nexus ZIP. Only the 29 creator-owned files in the Runtime
  data allowlist ship; the extractor recreates required game audio and its
  derivatives locally.
- `tools/extract_sounds/sounds_manifest.json` now has 709 entries across 26
  required Wwise banks, including QTE, inventory UI, per-item healing, and
  weapon sounds. `qte.wav` maps
  to `ch_ui_ingame_media.sbnk.1.x64`, WEM `637613124`, based on
  `speaker/extracted_ui_wavs/PRELIMINARY_CATALOG.md` and `TXTP_EVENT_INDEX.csv`.
- `ree-pak-cli.exe`, `DSE_Required_Banks.list`, and required `vgmstream` binaries
  were copied into `tools/extract_sounds/` after phase 1 inventory.
- `setup_sounds.ps1` now reads the base `re_chunk_000.pak` and, when present,
  `dlc/re_dlc_stm_2109308.pak` for Sentinel Nine (`wp6000`) sounds. When the
  DLC pak is absent, its 33 outputs are optional and the script verifies the
  remaining 676 base-game outputs instead of failing the whole setup.
- Full scratch-directory validation passed on 2026-07-14 against the expanded
  709-entry/26-bank manifest in both supported layouts: base-only produced
  `676 extracted / 0 errors / 33 optional skipped / 676 present`; the
  DLC-present follow-up produced `709 extracted / 0 errors / 709 present`,
  including all `wp6000_*` outputs.
- Staged `THIRD_PARTY_LICENSES.txt` now includes notices for NAudio, duaLib,
  hidapi, ree-pak-cli, DSE_Required_Banks.list, vgmstream, REFramework, Fluffy Mod
  Manager, lunatiii credit, and Capcom/Sony disclaimers. `ree-pak-cli` is
  documented as `ree-pak-rs`, MIT License, Copyright (c) 2024 Eigeen.
- Final package layout places extractor tools under
  `[GameDir]/DualSenseEnhanced/tools/extract_sounds/`, with
  `setup_sounds.bat` and `THIRD_PARTY_LICENSES.txt` at the game-folder root.
- Several source/docs comments still mention DSX. Internal comments about
  DSX-origin trigger mapping may remain, but user-facing package docs and UI
  should avoid DSX compatibility claims for v1.0.

## Required Pre-ZIP Blockers

1. Run in-game REFramework smoke test with `RELEASE_BUILD = true` after
   `Reset Scripts` to confirm the debug/experimental UI is fully hidden and
   nothing else regressed.
2. Runtime smoke-test `Reset Defaults` in REFramework to confirm the static
   defaults are applied in-game and are not overridden by an existing user
   `RE4R_DualSense_settings.lua`.
3. Create GitHub docs separately from Nexus description.
4. Run final deployment/hash checks after any Lua/binary changes
   (`tools/verify_deploy.ps1`).

## Completed

- `setup_sounds.bat` attempts PowerShell-side Steam auto-detection if
  `re_chunk_000.pak` is not beside the BAT.
- `setup_sounds.ps1` defaults output to installed
  `reframework/data/DualSenseEnhanced/sounds` when run from the package layout,
  while preserving the dev-tree fallback.
- `setup_sounds.ps1` prints the audio-mod/re_chunk warning and exits non-zero
  if any required WAV is missing after extraction.
- `setup_sounds.ps1` extracts Sentinel Nine (`wp6000`) sounds from
  `dlc/re_dlc_stm_2109308.pak` when that DLC pak is installed, and skips only
  those 33 optional outputs when it is not installed.
- The current 709-entry/26-bank extractor passed clean scratch validation in
  both layouts on 2026-07-14: `676/676` without Sentinel Nine DLC and `709/709`
  with it, both with zero errors.
- The creator authorized redistribution of the project's AI-generated custom
  healing cues. The 29-file creator-owned WAV allowlist is now enforced by
  both release sync and package staging; `heal_spray.wav`, extracted game WAVs,
  and `haptic_*_real.wav` remain excluded.
- Staging includes `ree-pak-cli.exe`, `DSE_Required_Banks.list`,
  `vgmstream-cli.exe`, and required vgmstream DLLs under
  `DualSenseEnhanced/tools/extract_sounds/`.
- Root `README.txt`/`README.md` explains installation, local audio extraction,
  the audio-mod/re_chunk warning, included v1.0 features, and the v1.0 DSX
  non-claim.
- Root `THIRD_PARTY_LICENSES.txt` is no longer a placeholder.
- The native trigger/gyro transport was renamed from
  `ExperimentalAdaptiveTriggerTransport` to `DualSenseEnhancedTransport`
  (folder, `.csproj`, `AssemblyName`/`RootNamespace`, named mutex, and every
  reference in the audio bridge, native launcher, `tools/verify_deploy.ps1`,
  and docs).
- Debug/experimental UI hiding (event monitor, native haptics diagnostics,
  Wwise event logger, radio speaker routing, Knife Hit toggle) is implemented
  as the `RELEASE_BUILD` flag in `DualSenseEnhanced.lua` rather than a
  physically separate release copy of the file.
- Replaced the full `RE4_STM_Release.list` with the mod-generated
  `DSE_Required_Banks.list`, currently containing only the 26 Wwise bank paths
  required by `sounds_manifest.json`.

## Planned Test Matrix

Mark claims only after physical testing:

- DualSense USB
- DualSense Edge
- two controllers connected simultaneously
- native Bluetooth
- Bluetooth + DSX + DSX DLC
- DS5Dongle
- controller reconnect/disconnect
- game restart
- game crash recovery
- save loading
- new game
- main menu
- DLC / Separate Ways if tested
