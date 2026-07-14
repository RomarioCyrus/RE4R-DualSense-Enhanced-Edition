# Experimental DualSense HID / Audio-Haptics Bridge

This directory is an isolated experiment for direct DualSense speaker and
haptic output through `Wujek_Dualsense_API`.

## Original Experiment Question

Can this bridge control speaker audio and haptic feedback on the physical
DualSense while DSX and Steam Input continue providing controller input to
Resident Evil 4 Remake?

## Historical Isolation Rules

- Do not modify or replace `speaker/DualsenseAudioBridge`.
- Do not modify the stable native launcher or its auto-start behavior.
- Do not change the current DSX/Steam Input configuration during initial
  implementation.
- Use a separate executable name, mutex, config file, log, and publish
  directory.
- Start the experimental bridge manually until coexistence is verified.
- Do not forward `payload.json` or replace `DSX_UDPClient.exe` in this phase.

## Initial Scope

```text
audio_events.json
        |
        v
ExperimentalDualsenseHidBridge.exe
        |
        v
Wujek_Dualsense_API
        |
        v
Physical DualSense speaker + haptic actuators
```

This was the initial DSX/Steam Input coexistence assumption. Later testing
showed that DSX conflicts with native game DualSense output, so native RE4R
tests now require DSX closed and Steam Input disabled.

## First Milestone

1. Enumerate physical DualSense HID devices.
2. Open one USB-connected controller.
3. Enable `Vibrations.VibrationType.Haptic_Feedback`.
4. Play a validated stereo 48 kHz IEEE-float WAV through `PlayHaptics`.
5. Test speaker, left actuator, and right actuator volumes separately.
6. Verify that RE4R input still works through the existing DSX and Steam Input
   setup.
7. Check for output-report conflicts, stutter, disconnects, or driver
   instability.
8. Only after coexistence is confirmed, connect the existing
   `audio_events.json` watcher.

## Planned Artifacts

```text
ExperimentalDualsenseHidBridge.csproj
Program.cs
DualsenseBridge.cs
BridgeConfig.cs
EventWatcher.cs
SoundMap.cs
ExperimentalDualsenseHidBridge.json
```

No experimental implementation should be deployed into the RE4R directory
until the standalone HID test succeeds.

## Current Test Build: `DualSenseHapticsProbe` v0.3

The first standalone MVP is now source-complete. It does not watch
`audio_events.json` and does not modify the stable bridge.

It tests the public Windows audio-haptics path:

```text
Windows render endpoint loopback
        |
        v
48 kHz stereo processing
        |
        v
4-channel DualSense USB audio endpoint
        |
        +-- channels 1/2: silent
        +-- channel 3: left actuator
        `-- channel 4: right actuator
```

This is an endpoint-mix experiment, not yet an internal RE4R Wwise SFX-bus
capture. For the closest first approximation, temporarily set RE4R Music and
Voice volume to zero while keeping SFX enabled.

### Build

From `speaker/ExperimentalDualsenseHidBridge`:

```powershell
..\DualsenseAudioBridge\.dotnet\dotnet.exe build `
  .\DualSenseHapticsProbe.csproj -c Release --no-restore
```

### Device inspection

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseHapticsProbe.exe --list
```

The physical controller must be connected by USB. The correct endpoint must
report at least four output channels.

The probe uses a 48 kHz, 32-bit, four-channel `WAVEFORMATEXTENSIBLE` stream
with the quadraphonic channel layout expected by the DualSense WASAPI driver.
Its custom float provider preserves that endpoint format instead of passing it
through NAudio's standard converter, which accepts only the non-extensible
IEEE-float format.

The device-independent channel/DSP check is:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseHapticsProbe.exe --self-test
```

### Safe actuator tests

Start at low gain:

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseHapticsProbe.exe `
  --tone left --gain 0.20

.\bin\Release\net6.0-windows\win-x64\DualSenseHapticsProbe.exe `
  --tone right --gain 0.20
```

If left/right are reversed, add `--swap`.

### Live loopback test

```powershell
.\bin\Release\net6.0-windows\win-x64\DualSenseHapticsProbe.exe `
  --loopback --preset ps5
```

Press `Q`, `Escape`, or `Ctrl+C` to stop.

The default source is the Windows default multimedia output. Use
`--source "part of endpoint name"` to capture another render endpoint.

### DSP presets

| Launcher | Purpose |
|---|---|
| `04_LIVE_LOOPBACK.bat` | Raw reference matching the confirmed v0.1 behavior |
| `05_LIVE_NATURAL.bat` | Mild band limiting and transient shaping |
| `06_LIVE_PS5_LIKE.bat` | Stronger attacks and reduced reverb/sustained tails |
| `07_LIVE_IMPACT.bat` | Aggressive short impact response |

The v0.2 DSP includes:

- stereo-preserving high-pass and low-pass filters;
- separate fast and slow envelope followers;
- transient emphasis from the envelope difference;
- configurable sustained/reverb-tail level;
- smoothed noise gate attack and release;
- soft limiting.

All parameters can be overridden from the command line:

```powershell
DualSenseHapticsProbe.exe --loopback --preset ps5 `
  --gain 0.58 --gate 0.025 --highpass 50 --lowpass 340 `
  --transient 1.5 --tail 0.35
```

### Important limitations

- Version `0.3` does not yet capture only `re4.exe`; it captures the selected
  Windows endpoint mix.
- It does not install a native Wwise hook.
- The normal v0.2 launchers still send no HID reports.
- The new v0.3 `--audio-haptics` option sends exactly one USB output report
  selecting native/audio haptics instead of compatible rumble. It does not
  write LED or adaptive-trigger state and does not repeat the report.
- RE4R may immediately switch the controller back to compatible rumble.
- `--audio-haptics` is experimental and must not be auto-started.
- Do not deploy or auto-start this executable yet.
- Stop immediately on stutter, USB disconnect, unstable vibration, or driver
  errors.

### Native RE4R coexistence test

When RE4R sees the physical DualSense directly, its native vibration output can
select compatible-rumble mode. In that state the four-channel WASAPI endpoint
still opens, but channels 3/4 may produce no actuator response.

Use the new opt-in launchers:

| Launcher | Purpose |
|---|---|
| `08_NATIVE_MODE_TONE_LEFT.bat` | One-shot audio-haptics selection followed by a left tone |
| `09_NATIVE_MODE_PS5_LIKE.bat` | One-shot selection followed by PS5-like live loopback |

The one-shot report is based on Sony's DualSense USB report layout documented
by the Linux `hid-playstation` driver: report ID `0x02`, with haptics selection
valid and compatible-vibration bits cleared.

Expected interpretations:

- Tone works briefly, then stops after a game vibration: RE4R restores
  compatible-rumble mode.
- Tone works and native RE4R effects disappear: audio haptics and native
  compatible rumble are mutually exclusive.
- Tone still does not work: the one-shot selection is rejected, immediately
  overwritten, or additional controller state is required.

### Final native-mode result

- RE4R native mode detects `via.hid.VendorNativeDualSenseDevice` and provides
  partial Capcom haptics plus native LED/heartbeat behavior.
- Plain tone and live-loopback tests are silent while RE4R owns native
  vibration mode.
- The v0.3 one-shot report is accepted by DualSense Edge and uses the
  descriptor-reported 64-byte output length, but does not produce reliable
  actuator playback.
- The diagnostic `10_NATIVE_MODE_TONE_BURST.bat` starts audio first and sends
  five selections over 200 ms; it also produced no actuator response.
- Conclusion: native RE4R haptics and this WASAPI audio-to-haptics path do not
  currently coexist reliably. Stop here unless a new controller-mode mechanism
  is discovered.
- Keep this directory experimental and do not auto-start it.

### Relationship to future adaptive-trigger HID work

This probe only tested vibration-mode selection and actuator audio. Its failed
native audio-haptics coexistence result does not prove that adaptive triggers
are impossible through HID.

Adaptive triggers remain a separate promising experiment because their report
fields can potentially be changed without selecting audio-haptics mode.
However, RE4R and the experimental tool would still be concurrent writers of a
compound DualSense output report. A trigger-only implementation must prove it
does not reset or race Capcom vibration mode, the custom lightbar, or other
state.

Use `docs/DUALIB_HID_BRANCH.md` for that branch. Do not extend
`DualSenseHapticsProbe` into the stable trigger backend.

### Historical DSX-managed test sequence

1. Connect DualSense by USB.
2. Run `01_LIST_DEVICES.bat` and save the output.
3. Run `02_TEST_LEFT.bat` and `03_TEST_RIGHT.bat`.
4. Confirm `04_LIVE_LOOPBACK.bat` still matches the known-good Raw behavior.
5. Start RE4R with Music and Voice at zero.
6. Compare `05`, `06`, and finally `07` using the same short gameplay route.
7. Test footsteps, knife hits, gunshots, reloads, and object impacts.
8. Confirm DSX LEDs/triggers and game input continue working.
9. Exit the probe before restoring normal audio settings.
