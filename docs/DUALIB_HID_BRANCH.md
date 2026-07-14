# duaLib / Direct HID Branch Handoff

## Goal

Add custom adaptive triggers in RE4R native DualSense mode without DSX, while
preserving:

- Capcom native haptics;
- the confirmed custom native lightbar;
- controller-speaker WAV playback;
- normal USB DualSense input.

Gyro started as a later milestone, but now has a confirmed opt-in native
gyro-to-mouse path. It remains a separate input feature that shares the same
delayed duaLib watcher instead of creating another controller owner.

## Current Implementation Status

An isolated first duaLib transport now exists under:

`speaker/DualSenseEnhancedTransport/`

Implemented:

- dynamic x64 loading of `duaLib.dll`;
- USB-only DualSense validation;
- `scePadSetTriggerEffect` packet generation using the documented 120-byte
  `ScePadTriggerEffectParam` ABI;
- weak manual L2/R2 feedback tests;
- explicit two-trigger reset on completion and process shutdown;
- single-instance protection;
- a JSON command-file watcher driven by the existing REFramework mappings;
- delayed automatic start after the game reports an active save;
- offline packet/offset self-test.

The project builds and the offline self-test passes. The standalone USB weak
L2 test is hardware-confirmed: it applied resistance for 800 ms and reset both
triggers normally, with DSX closed and Steam Input disabled. The full RE4R
native path is also hardware-confirmed: mapped L2/R2 effects, Capcom haptics,
custom native lightbar, controller-speaker audio, and stable save loading work
together. The solid-blue lightbar seen on RE4R launch is the game's normal
baseline; custom gameplay lightbar effects were subsequently checked and still
override it. Keep duaLib trigger-only: do not expand it into a second owner of
LED, audio, volume, or haptic output fields.

## Confirmed Baseline

- Test with a USB DualSense/Edge, Steam Input disabled, and DSX closed.
- RE4R detects `via.hid.VendorNativeDualSenseDevice`.
- Capcom native haptics work for shots, reloads, damage, knife impacts, and
  low-HP heartbeat.
- `native_feedback.lua` successfully applies the mod's custom gameplay
  lightbar and red/orange low-HP pulse while native haptics remain active.
- Controller-speaker playback through the existing WASAPI audio bridge also
  works in this native mode.
- DSX must not run: it suppresses native haptics and competes for LED state.

## Rejected REFramework Trigger Paths

- Direct `share.hid.Device.setAdaptiveTriggerFeedback` caused a confirmed game
  crash and is hard-disabled.
- Read-only hooks on
  `chainsaw.PlayerManager.setAdaptiveFeedBack` and
  `setAdaptiveTriggerFeedback` captured no normal weapon activity.
- The PC build appears not to use these PlayerManager trigger methods during
  ordinary gameplay.
- A guarded PlayerManager L2 probe could not acquire a usable manager
  instance. Hooking `PlayerManager.onUpdate` also remained idle.
- This probe does not discover a missing gameplay event: the DSX version
  already has working weapon/event mappings. The missing component is a safe
  native output transport.
- Stop extending the PlayerManager probe. Remove or hide its UI when the
  experimental native backend is cleaned up.

## Candidate A: duaLib

[duaLib](https://github.com/WujekFoliarz/duaLib) is an open-source
implementation of Sony's libScePad interface. Its documented DualSense
support includes USB/Bluetooth input, motion state, lightbar, vibration,
vibration mode, audio path, and adaptive-trigger effects.

Advantages:

- higher-level API for trigger effects and motion input;
- useful libScePad-compatible data structures and semantics;
- proven reference for games/mods that add DualSense support externally.

Risks:

- RE4R does not import `libScePad.dll`, so this is integration work, not a
  drop-in replacement;
- duaLib and RE4R may both write complete HID output reports;
- a trigger-only call may still overwrite Capcom vibration mode, lightbar, or
  other report fields unless state is merged correctly;
- compatibility must be tested separately for standard DualSense and
  DualSense Edge.

### Current duaLib Coexistence Result

The USB `02_TEST_L2_WEAK.bat` test was run with RE4R active, DSX closed, and
Steam Input disabled. L2 resistance worked and the game's native haptics
continued. The observed solid-blue lightbar is RE4R's normal startup baseline;
it is not by itself a regression. The test EXE terminates after the 800 ms
delay; this is not a background process. The next required check is to trigger
one known custom-lightbar gameplay event and confirm that it still overrides
the baseline blue. Do not start the JSON watcher or wire REFramework events to
this transport until that check is complete.

That same test revealed that duaLib could silence the Windows controller-speaker
endpoint: the audio bridge logged successful WASAPI playback to `DualSense Edge
Wireless Controller`, yet neither it nor the Windows test tone was audible
after the test. The first patch, which omitted the final library reset, was
rejected because the trigger could remain resistant. The current isolated local
duaLib build preserves the existing audio route instead of forcing its initial
audio-path reset and sends a direct trigger-only reset at close/terminate. That
report omits LED, audio, mute, volume, and rumble/haptics fields. The patched
x64 DLL passes the transport's export check. Hardware verification must confirm
that L2 resets and that both Windows and bridge speaker audio remain audible.

The second test still silenced speaker audio and left trigger resistance stuck,
showing that the generic background reader was also sending a first full report
after `wasDisconnected`. The current local build suppresses all non-trigger
output-enable flags in that reader, retaining only L2/R2 updates and the direct
trigger-only teardown reset. duaLib exposes audio-path, volume, and mute
controls, but no WAV/PCM playback API; it is not an alternative to the WASAPI
audio bridge. The revised standalone DLL is hardware-confirmed with RE4R
active: after `02_TEST_L2_WEAK.bat`, Windows/controller-speaker audio and the
mod's `Play Test Sound` remain audible, while native haptics and custom
lightbar remain active. This trigger-only output boundary is also used by the
confirmed continuous watcher and gameplay-event integration.

The extended manual RE4R check is now also confirmed: five-second L2 and R2
effects were exercised while aiming, firing, and reloading. All native haptics,
custom lightbar output, and controller-speaker audio remained working after
each trigger reset. The long-running `--watch` path and automatic
gameplay-event delivery are also hardware-confirmed. `dualib_trigger_ipc.lua`
converts existing `weapon_trigger_profiles.lua` trigger instructions to
`trigger_command.json`; the saved opt-in checkbox enables it in native mode.
The watcher waits for a ready marker after `CampaignManager.onStartInGame`, so
it does not open duaLib during save loading. `04_WATCH_RE4R_NATIVE.bat` remains
a diagnostic/manual tool, not the normal launch method.

The native autostart path is now hardware-confirmed. In `native` mode the
transport process can start with RE4R, but it waits for a one-line ready marker
written by `dualib_trigger_ipc.lua` only after
`CampaignManager.onStartInGame`. It does not load duaLib or open the controller
before that marker. Once gameplay is active, it reads the existing command
file, applies the mapped trigger effects, and resets both triggers when RE4R
exits. Stable save loading, native lightbar, Capcom haptics, controller-speaker
audio, and weapon trigger effects were all rechecked with this delayed start.

Post-refactor verification (2026-07-02): after moving the runtime namespace to
`DualSenseEnhanced`, the deployed native path is confirmed working again. If a
future deployment shows watcher logs with `Led=(...)` but no physical lightbar
change, check the deployed `duaLib.dll` first: the working build is
`third_party/build_out/duaLib.dll` (SHA-256
`B16261C95AB1849D1EAD669CA215D03054EEF05E272E1F2EC822A4CB418E02FE` as of
2026-07-11, see `docs/DUALSENSE_SPEAKER_NATIVE_INIT.md` and
`docs/HAPTICS_FOOTSTEPS_TASK.md` for what changed — supersedes the same-day
`63B4B3A8...` build, itself superseding 2026-07-06's `0C355C4B...`), not the
older 2026-06-26 trigger-only DLL. `tools/verify_deploy.ps1` must compare
against that copied release DLL before declaring the native path ready. The
same trigger-only-suppression guard these 2026-07-11 fixes touch is also
what makes the native controller-speaker audio path AND the footstep-haptics
research path work now — see those docs before assuming speaker/haptics
audio needs DSX/DualSenseY or is blocked by an external RE4R write race.

## Confirmed Opt-In Feature: Native Gyro-to-Mouse

Native mode deliberately runs with Steam Input disabled and DSX closed. That
preserves RE4R native haptics, the custom lightbar, controller-speaker audio,
and the duaLib trigger transport, but it also removes the usual external
gyro-to-mouse layer. A native gyro companion now fills that gap for L2 aiming.

`scePadSetMotionSensorState(handle, true)` is necessary for the duaLib motion
path, but it is not gyro aiming by itself. In duaLib it only enables filling
the acceleration and angular-velocity fields returned by
`scePadReadState`. It does not send mouse movement, change RE4R's camera, or
create a virtual input device.

The implemented design extends the existing delayed-start native transport
rather than adding another controller owner:

```text
DualSense IMU -> duaLib scePadReadState -> gyro filter/calibration
             -> optional aim-gated mouse delta -> Windows/RE4R input
```

Current confirmed behavior:

- USB read-only IMU logging is hardware-confirmed.
- In the user's normal hold, pitch maps to `angularVelocity.X`.
- The deliberate left/right aiming gesture maps to `angularVelocity.Z`; yaw is
  inverted in the default mapper to match in-game camera direction.
- Resting Z bias is about 0.012 rad/s and is calibrated at mapper startup.
- `--gyro-mouse` is compiled into the existing delayed watcher and is gated by
  L2, RE4R foreground focus, deadzone, and startup calibration.
- Releasing L2 or losing focus immediately clears accumulated motion.
- Deliberate right-stick camera input suppresses gyro deltas, preventing mouse
  and controller camera movement from fighting each other.
- User hardware testing confirms in-game gyro camera movement; after yaw
  inversion and right-stick arbitration it was reported as working smoothly.

Native gyro now has its own Lua module and UI section instead of living under
the experimental trigger IPC checkbox. `native_gyro.lua` writes
`DualSenseEnhanced/native_gyro.json`; the audio bridge reads that file before it
starts the one shared watcher and passes:

- `--gyro-mouse`;
- yaw and pitch sensitivity;
- deadzone;
- L2 aim threshold;
- calibration time.

Keep this boundary: gyro is an input-injection layer attached to the existing
watcher. It must not become a second HID output writer and must not disturb
the confirmed trigger-only output suppression.

## Candidate B: Direct HID

Direct HID is technically promising because it offers full control over the
DualSense output report and does not depend on DSX or RE4R managed trigger
methods.

It is not automatically safer. DualSense effects share a compound output
report. An independent writer that sends only trigger bytes may reset or race
Capcom's haptics/lightbar state. The useful direct-HID design is therefore a
single report owner or report-merging layer, not a second blind writer.

Potential advantages:

- exact trigger control;
- possible future player-indicator, Mic LED, and gyro support;
- no DSX process or virtual-controller dependency;
- behavior can be tailored around RE4R's native mode.

Main risks:

- output-report ownership conflict with Capcom;
- compatible-rumble/audio-haptics mode changes;
- USB/Bluetooth and DualSense/Edge report differences;
- CRC/sequence requirements on Bluetooth;
- disconnects or stuck trigger state after malformed reports;
- future game/controller firmware changes.

## Recommended First MVP

Build an isolated standalone executable or DLL test. Do not initially modify
the stable REFramework modules.

1. Read controller state only and identify USB DualSense/Edge reliably.
2. Send one weak L2 trigger effect with no lightbar or vibration changes.
3. Reset L2 immediately and on process exit.
4. Test outside RE4R.
5. Test inside RE4R main menu.
6. Test during native gunshot/reload haptics.
7. Verify that Capcom haptics and the custom native lightbar remain unchanged.
8. Only then connect the existing DSX weapon mappings to the new transport.

The first success criterion is not merely "the trigger moves." It is:

> Trigger effect works while Capcom native haptics and custom native lightbar
> continue without flicker, suppression, or mode changes.

## Suggested Architecture

```text
Existing REFramework weapon/event mappings
                    |
                    v
         trigger command file / IPC
                    |
                    v
      Native DualSense output service
          (duaLib or direct HID)
                    |
                    v
        merged controller state/report
```

Keep the current event mappings separate from the transport so duaLib and
direct HID can be compared without rewriting gameplay detection.

## References

- [WujekFoliarz/duaLib](https://github.com/WujekFoliarz/duaLib)
- [MasonLeeBack/libscepad_windows_sdk](https://github.com/MasonLeeBack/libscepad_windows_sdk)
- [WujekFoliarz/Dying-Light-1-DUALSENSE-MOD](https://github.com/WujekFoliarz/Dying-Light-1-DUALSENSE-MOD)
- `docs/RE9_DUALSENSE_RESEARCH.md`
- `speaker/ExperimentalDualsenseHidBridge/README.md`
