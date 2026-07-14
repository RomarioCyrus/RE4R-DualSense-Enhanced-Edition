# DualSense Audio Bridge

The v1.0 native-first setup uses two cooperating background processes:

- `DualsenseAudioBridge.exe`: NAudio/WASAPI playback for the controller speaker
  and the DualSense actuator channels 3/4.
- `DualSenseEnhancedTransport.exe`: delayed duaLib transport for adaptive
  triggers, gyro, player indicators, Mic LED, lightbar output, and haptics mode.

`DualsenseAudioBridgeLauncher.dll` is loaded by REFramework and starts the
bridge automatically. The bridge performs a one-shot native speaker-route
initialization as soon as the controller is available, waits for Lua's
post-`onStartInGame` ready marker before launching the shared trigger/gyro
transport, watches `re4.exe`, and exits with the game.

DSX/`DSX_UDPClient.exe` is a legacy compatibility path only. It is not required,
not packaged, and not a supported v1.0 configuration.

## Build Outputs

- `dist/native-autostart/DualsenseAudioBridge.exe`: selected self-contained
  release build.
- `launcher-nativeaot/publish/DualsenseAudioBridgeLauncher.dll`: native
  REFramework launcher.

See [BUILD.md](../BUILD.md) for deployment and testing.

## Current Audio Features

- Runtime output-device and volume selection.
- Exact Windows WASAPI endpoint routing. The bridge writes
  `reframework/data/DualSenseEnhanced/audio_devices.json`, the REFramework UI
  can select `Auto DualSense`, `Manual Endpoint`, or `Legacy Presets`, and
  audio events may specify a `device_id`.
- Playback device resolution order:
  1. exact endpoint ID from `device_id`;
  2. legacy friendly-name fragment from `device`;
  3. automatic DualSense/DualSense Edge detection.
- Numbered random WAV variants with immediate-repeat avoidance.
- Per-item healing cues for herbs, spray, eggs, fish, viper, and rhinoceros
  beetle, plus parry, pickup, QTE, knife-hit, and Fatal Kick events.
- Enhanced Haptics on channels 3/4: sprint-gated footsteps and companion pulses
  for parry, knife, dry-fire, aim, draw, healing, and pickup, with a continuous
  intensity value and per-category toggles supplied by Lua.
- One-shot native speaker-route initialization through the shared duaLib
  backend; no DSX or DualSenseY process is required for audible playback.
- Fatal Kick uses three clean layered composite variants; the unwanted long
  environmental layer is no longer deployed.
- Weapon-specific reload mappings for SG-09 R, W-870, Riot Gun, Striker,
  Skull Shaker, SR M1903, Stingray, CQBR, Broken Butterfly, Killer7, and
  Handcannon.
- SG-09 R dry-fire playback through the confirmed Wwise
  `soundlib.SoundManager.postRequestInfo` event-ID route.
- Controller-speaker playback is confirmed in RE4R native DualSense mode with
  DSX closed and Steam Input disabled, including after the patched duaLib
  trigger transport runs. The native route-init fix is hardware-confirmed on a
  standard DualSense over USB and on a DualSense Edge through ds5dongle.

Only SG-09 R, Riot Gun, and W-870 reload behavior currently have explicit
physical confirmation. See
`docs/weapon_audio_catalog/README.md` for per-weapon status.

## Endpoint Picker Validation Status

The manual endpoint picker is implemented, deployed, and live-tested with a
connected controller. The REFramework UI renders active endpoints as directly
selectable rows, and `Test Speaker` plays through the selected endpoint,
including non-controller Windows output devices.

`Test Speaker` is the single endpoint smoke-test button and emits the confirmed
`parry` event. The redundant `Test Parry` UI button was removed.

Remaining endpoint follow-ups:

1. `Auto DualSense` with one connected controller should choose the controller
   endpoint without manual selection.
2. If two controllers are connected, each endpoint should be selectable and
   routed independently.
