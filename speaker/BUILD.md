# Building the DualSense Audio Bridge

## Architecture

```text
audio_events.json -> DualsenseAudioBridge.exe -> NAudio/WASAPI
payload.json      -> external DSX_UDPClient.exe -> DSX
```

The C# project is audio-only. The external UDP client is kept separate because
the rejected custom replacement caused repeatable in-game stutters.

## Requirements

- Windows x64
- .NET 8 SDK (builds this `net6.0-windows` project)
- DSX v3.1+
- DualSense connected by USB for speaker audio
- This project's compatible `DSX_UDPClient.exe` build in the RE4R game directory

For native-mode testing, DSX and `DSX_UDPClient.exe` are not required. The
custom native lightbar and delayed duaLib trigger transport remain available
with Steam Input disabled.

## Portable Build

```powershell
cd speaker\DualsenseAudioBridge

dotnet publish .\DualsenseAudioBridge.csproj `
  -c Release -o .\dist\audio-portable
```

The self-contained executable is about 66 MB and does not require an installed
.NET runtime.

For the current locally restored dependency state, the deployed single-file
build can also be refreshed without reading the user NuGet configuration:

```powershell
dotnet publish .\DualsenseAudioBridge.csproj `
  -c Release -r win-x64 --self-contained true --no-restore `
  -o .\bin\Release\net6.0-windows\win-x64\publish-fixed
```

## Compact Build

```powershell
dotnet publish .\DualsenseAudioBridge.csproj `
  -c Release -o .\dist\audio-compact `
  --self-contained false -p:PublishSingleFile=true `
  -p:EnableCompressionInSingleFile=false
```

The compact executable is under 1 MB and requires the .NET 6 Desktop Runtime.

## Deployment

```text
<RE4R>\
+-- DSX_UDPClient.exe
+-- reframework\
    +-- plugins\
    |   +-- DualsenseAudioBridgeLauncher.dll
    +-- data\
        +-- audio_events.json
        +-- DualSenseEnhanced\
            +-- DualsenseAudioBridge.exe
            +-- DualsenseAudioBridge.json
            +-- DualsenseAudioBridge.log
            +-- DualSenseEnhancedTransport.exe
            +-- duaLib.dll
            +-- hidapi.dll
            +-- payload.json
            +-- sounds\
```

The native launcher starts the audio bridge and external UDP client silently.
The audio bridge watches `re4.exe`; the launcher places the UDP client in a
Windows Job Object so it exits when REFramework unloads.

For native-mode deployments, copy the confirmed RGB-lightbar-capable
`speaker\DualSenseEnhancedTransport\third_party\build_out\duaLib.dll`
to `speaker\DualSenseEnhancedTransport\bin\Release\net6.0-windows\win-x64\duaLib.dll`
before copying it to the game folder. The older 2026-06-26 trigger-only DLL can
make watcher logs show `Led=(...)` while physical lightbar output remains
suppressed. The confirmed build hash is
`B16261C95AB1849D1EAD669CA215D03054EEF05E272E1F2EC822A4CB418E02FE`
(2026-07-11, same day, second fix: adds `scePadSetMotorPowerReduction`
+ a `motorPowerEnabled` opt-in flag, same pattern as `audioControlEnabled`
below — the same trigger-only suppression guard was also unconditionally
forcing `AllowMotorPowerLevel` off, so this fork could never clear a stuck
nonzero `Trigger`/`RumbleMotorPowerReduction`. Hardware A/B-confirmed as the
real root cause of channels-3/4 footstep-haptics content not being felt
during real RE4R gameplay (previously misdiagnosed as an external RE4R
write race); see `docs/HAPTICS_FOOTSTEPS_TASK.md`. Supersedes
`63B4B3A8ED04A1C55C054DDF99FBAB8D1A3C263E27B18975CF96173DDEB61066`, which
adds an `audioControlEnabled` opt-in flag so
`scePadSetAudioOutPath`/`scePadSetVolumeGain` actually reach the wire — the
trigger-only output-suppression guard in `readDualsense.cpp` was previously
force-clearing `AllowSpeakerVolume`/`AllowAudioControl` on every write
regardless of caller intent, which is why the native DualSense speaker never
worked without DSX/DualSenseY. Supersedes `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`,
2026-07-06's vibration-mode fields fix, which is preserved on top of this
build; see `docs/DUALSENSE_SPEAKER_NATIVE_INIT.md`).
`hidapi.dll` must be deployed alongside it — the rebuild links `hidapi.dll.a`
dynamically, so `duaLib.dll` fails to load with `DllNotFoundException` if
`hidapi.dll` is missing from the same folder.

`DSX_UDPClient.exe` is built from this repository's
`speaker/DualsenseAudioBridge/experimental-dsx-client/DSX_UDPClient_Test.c`.
Keep its DSX-compatible transport role separate from the audio bridge.

## Audio Configuration

```json
{
  "device": "",
  "volume": 0.85,
  "sounds_dir": "data\\DualSenseEnhanced\\sounds",
  "events_file": "data\\audio_events.json"
}
```

## Verification

1. Start DSX and connect the controller by USB.
2. Start RE4R.
3. Confirm one `DualsenseAudioBridge.exe` and one `DSX_UDPClient.exe`.
4. Confirm the audio log contains `Listening for events`.
5. Verify LEDs and adaptive triggers.
6. Verify speaker audio separately.
7. Exit the game and confirm both helper processes stop.

Native-mode verification:

1. Close DSX and disable Steam Input for RE4R.
2. Connect the controller by USB and confirm RE4R sees the native DualSense.
3. Start RE4R and load a save. The trigger transport starts automatically only
   after the Lua in-game ready marker; do not start a manual watcher.
4. Verify mapped controller-speaker WAV playback and native weapon triggers.
5. Verify custom native lightbar and Capcom haptics remain active.

Weapon-audio deployment must additionally verify:

1. `SoundMap.cs` contains each new event name.
2. Lua weapon IDs emit only mapped events.
3. Source/game EXE, Lua, and WAV hashes match.
4. A successful bridge smoke test is recorded separately from in-game sound
   confirmation.
5. Prototype weapon profiles remain marked unconfirmed until physically
   tested.

## BSOD Diagnostic

The June 19, 2026 crash dump was analyzed with Microsoft WinDbg:

```text
Bugcheck: DRIVER_IRQL_NOT_LESS_OR_EQUAL (0xD1)
Module:   nssvpd.sys
Bucket:   AV_nssvpd!unknown_function
Driver:   Nefarius Virtual Gamepad Emulation Bus G2 2.62.0.0
```

This is a kernel-driver crash, not a managed exception. Process isolation
cannot correct a kernel driver bug. Update DSX/Nefarius drivers when a newer
compatible version is available.
