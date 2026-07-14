# TASKS_FOR_CODEX.md

Read `AGENTS.md`, `MEMORY.md`, `BUGS.md`, `AUDIO_MEMORY.md`, and
`docs/game_events.md` before starting a task.

For audio-hook mapping work, start with `docs/AUDIO_HOOK_MAPPING_TASK.md`.

Inspect relevant source files before editing. Explain the root cause before
patching.

## Current Release Priorities (2026-07-14)

1. Sync canonical dev into the separate `Release v1.0` checkout, keep
   `RELEASE_BUILD=true` only there, and audit the package surface against
   `release/v1.0/RELEASE_MANIFEST.md`.
2. Keep `DualsenseAudioBridge.exe` aligned with the selected
   `dist/native-autostart` release artifact; `tools/verify_deploy.ps1` now
   checks that same path instead of the stale `publish-fixed` output.
3. Visually smoke-test the 2026-07-14 professional UI pass in release mode:
   section order, Quick Controls mirroring, selected-mode markers, percentage
   controls, Soft/Normal/Strong haptic rows, haptic test status, and narrow
   REFramework window layout. Then run `Test Speaker`, Enhanced Haptics,
   adaptive-trigger, gyro, lightbar, Mic LED, and shutdown tests on hardware.
4. Keep remaining weapon-audio tuning, gyro drift research, release artifacts,
   and documentation sync in separate commits.

## Completed - Redistributable Custom Healing Assets

The mod author confirmed that the custom healing WAVs were AI-generated and
may be redistributed. Release sync/staging now uses an explicit 29-file
creator-owned allowlist: 11 healing cues, their 11 haptic companions, three
footstep reference tones, parry, two knife-impact pulses, and pickup. Extracted
Capcom WAVs, `heal_spray.wav`, and all `haptic_*_real.wav` derivatives remain
excluded and are created locally from each user's game installation.

## Completed - Optional Sentinel Nine DLC Extraction

Confirmed 2026-07-14 against real game archives in isolated scratch output:

- base-only: `676 extracted / 0 errors / 33 optional skipped / 676 present`;
- Sentinel Nine DLC installed: `709 extracted / 0 errors / 709 present`.

## Completed - Gameplay State Recovery

Confirmed working:

- clean main menu on first launch;
- gameplay HP/ammo/Mic LED enable;
- return-to-menu cleanup;
- repeated death and Continue recovery;
- grab, parry, damage, Fatal Kick, and Hookshot effects.
- 2026-07-04: normal menu-to-gameplay lightbar entry remains correct after the
  recent blackout/ownership changes. Death blackout is confirmed, although the
  three visible light sources still turn off slightly sequentially; a future
  polish pass can collapse that into one forced blackout command.
- 2026-07-04: L2 spam no longer causes gyro drift or stuck trigger haptics in
  live testing. Keep this as a watchlist item because gyro and adaptive
  triggers share the delayed duaLib transport.

Keep the current polling and generation-guard solution unless a replacement is
independently verified in game.

## Completed - Native-First Bridge Architecture

The stable split architecture is implemented, installed, and confirmed
working.

It handles:

- `DualsenseAudioBridge.exe`: DualSense speaker audio and actuator channels
  3/4 through NAudio/WASAPI, plus early native speaker-route initialization;
- `DualSenseEnhancedTransport.exe`: adaptive triggers, gyro, player
  indicators, lightbar, Mic LED, and haptics mode through duaLib;
- automatic hidden launch through a native REFramework plugin;
- portable path resolution and config migration;
- automatic shutdown with `re4.exe`.

The v1.0 supported path requires DSX closed and Steam Input disabled. The old
DSX payload/client implementation remains legacy compatibility source only and
is not packaged or claimed as supported.

Do not reintroduce:

- the PowerShell audio prototype;
- Lua `os.execute`;
- hard-coded Steam installation paths;
- UDP/payload handling inside the audio bridge;
- the removed custom `DualsenseDsxBridge`, which caused repeatable stutters.

Remaining audio/bridge tasks are tracked in `AUDIO_TASKS.md`.

## In Progress - Weapon Audio Validation

Implemented and controller-tested:

- SG-09 R reload;
- SG-09 R dry fire through Wwise `postRequestInfo` -> `wp4000_dry_fire`;
- Riot Gun reload;
- W-870 per-shell reload and delayed post-shot pump;
- Striker reload;
- Handcannon reload;
- Skull Shaker reload;
- SR M1903 reload and delayed post-shot bolt;
- Broken Butterfly reload.

Active follow-up:

- retest the June 25 correction pass for Broken Butterfly, CQBR, Killer7,
  Skull Shaker, SR M1903, Handcannon, and the W-870 last-shot branch;
- Stingray regressed and needs isolated phase testing before the next mapping
  patch;
- Punisher, Red9, Blacktail, and Matilda initial gameplay validation. Test
  tactical and empty reloads separately before adding any slide/chamber finish
  cue.

Use `docs/weapon_audio_catalog/README.md` as the status index. Update a profile
from prototype to confirmed only after an explicit in-game/controller test.

## Completed - Controller Speaker Endpoint Smoke Test

Confirmed 2026-07-04:

- the bridge-generated endpoint list appears in the REFramework UI;
- selecting a visible endpoint row changes the output endpoint;
- `Test Speaker` plays on the selected endpoint, including non-controller
  Windows output devices;
- the obsolete `Test Parry` button was removed from the UI.

The old `Previous`/`Next` carousel has already been replaced by the direct
endpoint list.

## Completed - Save and Load Settings

Runtime settings are saved under
`reframework/data/RE4R_DualSense_settings.lua`, loaded at startup, and exposed
through Save, Load, and Reset controls.

## Moved To Ideas - Cutscene, Pause, and Loading Suppression

Cutscene/pause/loading suppression is no longer an active mod feature or open
bug. The old manual cutscene-gate UI and Movie/Timeline diagnostics were
removed from the runtime. Keep any future work on this as a separate idea in
`IDEAS.md` unless the user explicitly reopens it.

## Completed Research - Native DualSense And Audio Haptics

- Confirmed RE4R detects `via.hid.VendorNativeDualSenseDevice` over USB when
  Steam Input and DSX are disabled.
- Confirmed native LED behavior, low-HP heartbeat, and partial Capcom haptics.
- Confirmed DSX conflicts with native HID output and should not be used for a
  simultaneous native hybrid.
- Confirmed the PC `IsTargetPlatform` gate must remain false.
- Confirmed the experimental 4-channel audio-haptics probe does not reliably
  coexist with RE4R native vibration mode.

Do not continue gate or HID-mode burst experiments unless new evidence changes
the controller-mode model.

## Confirmed Experimental Backend - Native Game API Lightbar

Hardware-confirmed:

- selectable `Custom DSX`, `Native Game API (EXPERIMENTAL)`, and `Off` modes;
- custom lightbar through `share.hid.Device.setLightBarColor`;
- temporary suppression of Capcom lightbar writes while a custom LED source
  owns the lightbar;
- final custom-color enforcement after `share.hid.Device.update`, preventing
  Capcom's cached lightbar state from winning between mod updates;
- no DSX payload writes while native mode is selected;
- stable DSX mode remains the default.

Native adaptive-trigger calls caused a confirmed game crash and are disabled.
Normal HP, heal, damage, parry, event lightbar effects, and the native
red/orange low-HP pulse work in gameplay. Capcom shot/reload/damage/knife
haptics remain active. Menu lightbar override is deferred.

PlayerManager adaptive-trigger research is closed:

- read-only hooks captured no normal weapon calls;
- the guarded L2 probe could not acquire a live PlayerManager;
- `PlayerManager.onUpdate` did not provide an instance;
- the DSX version already has the required gameplay mappings, so further
  event-hook discovery does not solve the missing native output transport.

Do not continue the PlayerManager probe. Hide/remove its UI during later
experimental cleanup.

Do not pursue the five ammo/player-indicator LEDs through RE4R managed APIs:
no DualSense setter exists in the dump. In native mode, keep using the
confirmed external duaLib watcher path for ammo indicators, RGB lightbar, and
Mic LED; do not re-open a RE4R managed API hunt unless new dump evidence
appears.

## Confirmed Experimental Backend - duaLib Native Trigger Transport

Use `docs/DUALIB_HID_BRANCH.md` as the handoff for a separate chat and branch.
The first milestone is adaptive triggers while preserving Capcom native
haptics and the custom native lightbar. Gyro is now a confirmed opt-in native
input layer that shares the same delayed watcher.

The isolated `speaker/DualSenseEnhancedTransport` duaLib backend
builds successfully, passes its offline packet self-test, and is
hardware-confirmed in RE4R native gameplay. It uses the existing DSX weapon
mappings through `dualib_trigger_ipc.lua`; L2/R2 effects, Capcom haptics,
custom native lightbar, controller-speaker audio, and stable save loading were
all confirmed together. The autostarted process waits for a post-
`CampaignManager.onStartInGame` ready marker before it loads duaLib or opens
the controller.

Post-refactor status (2026-07-02): the renamed `DualSenseEnhanced` runtime is
confirmed working after deploy. The regression where triggers stayed `Off` was
fixed by robust `weapon_trigger_profiles.lua` loading, and the regression where
watcher logs showed `Led=(...)` but the physical lightbar did not change was
fixed by deploying the newer `third_party/build_out/duaLib.dll`
lightbar-allowled build. `tools/verify_deploy.ps1` reported all deployed files
matching source, and the user confirmed the mod now works as expected.

Reference projects:

- `WujekFoliarz/duaLib`
- `MasonLeeBack/libscepad_windows_sdk`
- `WujekFoliarz/Dying-Light-1-DUALSENSE-MOD`

Research goals:

1. Supply locally built x64 `duaLib.dll` and `hidapi.dll`. Completed.
2. Run the weak L2 test outside RE4R and confirm immediate reset. Completed.
3. Trigger a known custom-lightbar gameplay event after the weak-L2 test and
   confirm that it overrides RE4R's normal blue startup baseline. Completed.
4. Run the patched weak-L2 test and verify controller-speaker sound through
   both Windows' test tone and the audio bridge afterward. Completed.
5. Test during native gunshot/reload haptics and custom lightbar effects. Completed:
   five-second L2/R2 tests remained stable while aiming, firing, and reloading.
6. Existing weapon mappings use the opt-in JSON IPC implementation through
   `dualib_trigger_ipc.lua`; long-running watcher and delayed automatic start
   are hardware-confirmed.
7. Compare direct HID only if duaLib overwrites Capcom output state.
8. Native gyro-to-mouse is implemented and hardware-confirmed as opt-in. It
   uses `scePadSetMotionSensorState` + `scePadReadState`, startup calibration,
   L2/focus gating, X pitch, inverted-Z yaw, and right-stick arbitration. It
   remains attached to the same delayed watcher; do not create another
   controller owner. Expect RE4R to show keyboard/mouse prompts while mouse
   deltas are injected; prompt preservation remains an explicit design problem.
9. Keep the stable DSX/audio implementation untouched.

## New Research Task - Native Audio And Haptics Without Bridges

Use `docs/NATIVE_HAPTICS_AUDIO_TASK.md` as the handoff for a separate agent.
This is not a trigger or gyro task. Those are already covered by the confirmed
duaLib watcher.

The goal is to find whether RE4R can drive custom DualSense LED,
controller-speaker audio, and actuator haptics natively, without DSX, without
the WASAPI speaker bridge, and without turning the trigger-only duaLib
transport into a broad HID output owner.

Start with read-only API discovery and diagnostics. Do not re-open the closed
DSX/native hybrid, `share.hid.Device.setAdaptiveTriggerFeedback`,
PlayerManager L2 probe, or `DualSenseHapticsProbe` integration paths unless new
evidence changes the controller-mode model.
