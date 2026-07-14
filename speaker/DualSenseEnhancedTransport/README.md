# Experimental Adaptive Trigger Transport

Isolated USB-only adaptive-trigger MVP for RE4R native DualSense mode.

It dynamically loads `duaLib.dll` and calls `scePadSetTriggerEffect`. The
confirmed native integration reuses existing REFramework weapon mappings via
`dualib_trigger_ipc.lua`; it does not use DSX or RE4R's crash-prone managed
adaptive-trigger API.

Adaptive trigger profiles were initially tuned using community references as a
starting point, but are integrated into an independent native DualSense
pipeline that does not require DSX or Steam Input. `trigger_intensity.lua` now
layers Off/Native Only/Light/Enhanced/Strong presets and per-weapon-class
intensity multipliers on top of those profiles. Future releases may include
fully custom-tuned trigger profiles.

## Boundary

This is an experimental but hardware-confirmed in-game backend. The standalone
USB weak-L2 test, long-running weapon effects, delayed autostart, and RE4R
coexistence are confirmed on USB with DSX closed and Steam Input disabled.

Success means the trigger effect works while all of these remain intact:

- RE4R native shot/reload/damage haptics;
- the existing custom native lightbar;
- controller input;
- USB stability.

duaLib and RE4R can both write complete DualSense output reports. This first
MVP does not merge Capcom's report state. Stop immediately if native haptics
disappear, the lightbar flickers, the controller disconnects, or a trigger
sticks.

### Confirmed hardware result

The standalone USB weak-L2 test works and resets the triggers. In RE4R native
mode, mapped weapon effects work while Capcom haptics, custom native lightbar,
controller input, and controller-speaker audio remain active. RE4R's solid-blue
startup lightbar is normal; custom gameplay lightbar effects were subsequently
rechecked and remain functional.

The first in-game run exposed a separate controller-speaker regression: after
the test exited, Windows and the audio bridge could still write to the
DualSense Edge WASAPI endpoint but produced no audible controller-speaker
sound. The first teardown-only patch was rejected because it could leave
trigger resistance stuck. The current local duaLib build fixes both causes:
it preserves the existing audio route instead of forcing duaLib's initial
audio-path reset, and its close/terminate path sends a direct trigger-only
reset without LED, audio, mute, volume, or rumble/haptics fields. This fix is
hardware-confirmed in the later native-mode tests below.

The second test showed that the generic background reader could still emit a
first full report after reconnect. The current build additionally suppresses
every non-trigger output-enable flag in that reader, retaining only L2/R2
updates and the direct trigger-only teardown reset. duaLib controls audio
routing and volume but has no WAV/PCM playback API; it cannot replace the
WASAPI speaker bridge. This revision is hardware-confirmed with RE4R active:
after `02_TEST_L2_WEAK.bat`, controller-speaker audio remains audible through
both Windows and the mod's `Play Test Sound`, while native lightbar and haptics
continue working. This suppression boundary is required for the confirmed
long-running watcher as well.

An extended in-game manual test is also confirmed: five-second L2 and R2
effects remained stable while aiming, firing, and reloading. Native haptics,
custom lightbar output, and controller-speaker audio all continued working
after each reset. The same effects now work through automatic gameplay-event
delivery after a save has loaded.

Post-refactor verification (2026-07-02): the `DualSenseEnhanced` namespace
cleanup is confirmed working with the deployed transport. If watcher logs show
`Led=(...)` but the physical lightbar does not change, check the deployed
`duaLib.dll` first. The working RGB-lightbar build is
`third_party/build_out/duaLib.dll` and must be copied beside
`DualSenseEnhancedTransport.exe`; the older 2026-06-26 trigger-only
DLL suppresses `AllowLedColor` at the HID report layer even though the watcher
logs commands as applied.

## Experimental gameplay IPC

`dualib_trigger_ipc.lua` is a persisted opt-in native-mode bridge from the
existing `weapon_trigger_profiles.lua` mappings to the transport's JSON watcher. It writes
only L2/R2 effects and never calls RE4R's crash-prone native trigger API. The
enabled setting, long-running watcher, and delayed automatic start are
hardware-confirmed.

1. Deploy the updated Lua files to REFramework.
2. With DSX closed and Steam Input disabled, start RE4R in native mode and
   load a save. Do not run `04_WATCH_RE4R_NATIVE.bat` for normal play.
3. Enable and save `duaLib trigger IPC (EXPERIMENTAL)` in the mod UI.
4. The transport waits for the post-`onStartInGame` ready marker, then opens
   duaLib and processes weapon mappings automatically.

The watcher resets both triggers after Ctrl+C. If it stops unexpectedly, run
`03_RESET_TRIGGERS.bat` and reconnect the controller if a trigger remains set.

## Dependencies

Matching x64 copies of `duaLib.dll` and `hidapi.dll` have been built locally
and placed beside `DualSenseEnhancedTransport.exe`.

The currently confirmed `duaLib.dll` source artifact is
`third_party/build_out/duaLib.dll` (SHA-256
`B16261C95AB1849D1EAD669CA215D03054EEF05E272E1F2EC822A4CB418E02FE`). Copy it
to `bin\Release\net6.0-windows\win-x64\duaLib.dll` before deploying, then let
`tools\verify_deploy.ps1` compare that release-output copy against the game
folder. `hidapi.dll` must sit next to it — the build links `hidapi.dll.a`
dynamically, not statically.

2026-07-11 rebuild #2: added `scePadSetMotorPowerReduction(handle,
triggerReduction, rumbleReduction)` (RE4R-fork-only export, not upstream) +
a `motorPowerEnabled` opt-in flag, same pattern as `audioControlEnabled`
below. The same trigger-only output-suppression guard was also
unconditionally forcing `AllowMotorPowerLevel` off, so this fork could never
explicitly clear a stuck nonzero `Trigger`/`RumbleMotorPowerReduction` (this
fork's own `CurOutputState` always defaults that field to 0, but the
"apply this" flag never reached the wire, same failure shape as the audio
fix below). Hardware-confirmed via a controlled A/B in real RE4R gameplay
(fix on: felt vibration via a "Test Haptics" debug button; same button,
fix disabled: no vibration; re-enabled: vibration again) as the real root
cause of channels-3/4 footstep-haptics content going silent during real
gameplay — previously misdiagnosed as an external RE4R HID write race (see
`docs/HAPTICS_FOOTSTEPS_TASK.md`). Supersedes
`63B4B3A8ED04A1C55C054DDF99FBAB8D1A3C263E27B18975CF96173DDEB61066`.

2026-07-11 rebuild #1: added an `audioControlEnabled` opt-in flag (same pattern
as `playerIndicatorsEnabled`/`micLightEnabled`/`lightBarOverrideEnabled`) so
`scePadSetAudioOutPath`/`scePadSetVolumeGain` actually reach the wire.
`readDualsense.cpp`'s trigger-only output-suppression guard was
unconditionally force-clearing `AllowSpeakerVolume`/`AllowAudioControl`/
`AllowHeadphoneVolume`/`AllowMicVolume`/`AllowAudioMute` on every write —
written for an earlier, unrelated feature (protecting a trigger-only caller
from accidentally rerouting the Windows speaker endpoint) — even after the
diff-check a few lines above had correctly computed `Allow*=true` for our own
`--test-speaker-init` calls. This is the actual root cause of the native
DualSense speaker never working without DSX/DualSenseY: the correct volume/
path byte always reached the controller, but the "please apply this" flag
was always stripped before send, so firmware silently ignored it. See
`docs/DUALSENSE_SPEAKER_NATIVE_INIT.md` for the full investigation.
Hardware-confirmed on a genuinely fresh USB replug (not residual state) and
regression-tested against triggers, lightbar, mic light, and player
indicators before this became the new confirmed build.

2026-07-06 rebuild (preserved on top of the above): `dataStructures.h`'s
`SetStateData::operator==` now also compares `UseRumbleNotHaptics`/
`EnableRumbleEmulation`/`EnableImprovedRumbleEmulation`. Without this,
`scePadSetVibrationMode` switching back from audio-haptics to compatible
rumble never differed from the last-written output state (when no other
field changed at the same time), so `readDualsense.cpp`'s write-gate never
fired and the controller stayed stuck in audio-haptics mode indefinitely —
hardware-confirmed via the `docs/HAPTICS_FOOTSTEPS_TASK.md` experiment.

Build inputs:

- duaLib commit `03bad1bea2a36561b520846776f2a07ced6773e0`;
- hidapi commit `8c9cbf6c020974d23e4690497778f3df173d1166`;
- LLVM-MinGW `20260616`, UCRT x86_64.

Downloaded sources, toolchain, build outputs, and licenses are isolated under
`third_party/`. They are not deployed to the RE4R game directory.

## Build

```powershell
dotnet publish `
  .\DualSenseEnhancedTransport.csproj -c Release --no-restore
```

Deploy the single self-contained EXE from
`bin\Release\net6.0-windows\win-x64\publish\`. Do not deploy the smaller
`dotnet build` EXE by itself: it depends on the sibling .NET runtime files.

## Offline self-test

This does not open a controller:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --self-test
```

Verify the locally built DLLs without opening a controller:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --check-library
```

## First hardware test

Before testing:

1. Connect one DualSense or DualSense Edge by USB.
2. Close DSX.
3. Disable Steam Input for RE4R.
4. Test outside RE4R first.

Run a weak 800 ms L2 resistance:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --test-l2 --acknowledge-output-conflict
```

The process explicitly resets both triggers after the delay and again during
normal shutdown.

Convenience launchers:

- `01_CHECK_DLLS.bat` - safe DLL/export check, no controller access;
- `02_TEST_L2_WEAK.bat` - weak 800 ms L2 test;
- `03_RESET_TRIGGERS.bat` - explicit emergency reset.

Then repeat in the RE4R main menu. Only after that, test while firing and
reloading with the game's native haptics active.

## Command-file transport

Watch mode is the active IPC boundary. During normal play it is started by the
launcher and waits for `DualSenseEnhanced/trigger_transport.ready`; that marker is
written only after the save is active, before duaLib is opened:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --watch .\trigger_command.json --acknowledge-output-conflict
```

Start from `trigger_command.example.json`. Increase `sequence` for each
command. Omitted `l2` or `r2` means that trigger is not included in the
duaLib update mask. Supported modes in this first build:

- `off`
- `feedback`
- `weapon`
- `vibration`
- `slope`

The existing REFramework weapon mappings are already connected and
hardware-confirmed. Native gyro input is also supported, but it is attached to
this same watcher only; keep trigger output-field suppression and mouse input
mapping conceptually separate.

## Read-only gyro diagnostic

The first gyro milestone is hardware-confirmed on USB. It uses the same duaLib
session as the trigger watcher, enables the motion-sensor state, and logs
`scePadReadState` angular velocity in radians per second. It does not inject
mouse input and does not modify trigger, lightbar, audio, or haptic output
fields.

For an isolated USB check outside RE4R:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --gyro-log --duration 10000 --gyro-sample-ms 100
```

For a native RE4R session with the already-confirmed trigger watcher, add
`--gyro-log` to the normal watcher command. This deliberately keeps one
duaLib/controller owner:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe `
  --watch .\trigger_command.json --acknowledge-output-conflict `
  --gyro-log --gyro-sample-ms 100
```

The watcher writes the samples to `trigger_watcher.log`. Hardware logging
confirmed stable resting values and the current physical mapping: pitch is
angular-velocity `X`, the player's left/right aiming gesture is
angular-velocity `Z`, and `Y` is not used for aiming.

## Opt-in gyro-to-mouse prototype

USB hardware checks confirm the IMU path and the current physical mapping:
pitch is angular-velocity `X`; the player's left/right aiming gesture is `Z`.
`Y` is not used for aiming. The in-game mouse mapper is hardware-confirmed and
reported by the user as smoother than Steam Input after yaw inversion and
right-stick arbitration.

It is deliberately off by default. In the native mod UI, enable and save
`Enable gyro-to-mouse` under the separate `Native Gyro` section, then fully
restart RE4R. The Lua module writes `DualSenseEnhanced/native_gyro.json`; the audio
bridge reads that config and starts the same trigger watcher with
`--gyro-mouse` plus the saved settings. No second controller process is
created.

For 1.5 seconds after gameplay becomes active, keep the controller still. The
mapper samples the X/Z bias, then sends mouse deltas only while L2 is held and
the RE4R window is focused. Releasing L2 or changing focus clears accumulated
motion immediately. A deliberate right-stick camera input suppresses gyro, so
RE4R never receives mouse and right-stick look deltas together. Defaults are
0.03 rad/s deadzone and 600 mouse counts per radian. The confirmed USB
orientation uses inverted yaw; pass `--gyro-normal-yaw` only if a future
controller orientation requires the opposite direction.

Native gyro now has its own persisted UI section. The Lua module writes
`DualSenseEnhanced/native_gyro.json`, which the audio bridge reads before it starts
the one shared duaLib watcher. Its adjustable values are enable state, yaw and
pitch sensitivity, deadzone, L2 threshold, and calibration time.
