# Native DualSense Speaker Init (No DSX/DualSenseY Required) — SOLVED 2026-07-11

Status doc for a **solved** investigation, kept as a historical/reference
record. Read this before touching `readDualsense.cpp`'s Allow-flag
suppression guard, `scePadSetAudioOutPath`/`scePadSetVolumeGain`, or the
`DualsenseAudioBridge.exe` startup sequence, and before assuming controller
speaker audio requires DSX or a free alternative.

## Summary

The DualSense's built-in speaker now works over a standard USB connection
with zero third-party software — this was one of the mod's originally
intended "killer features" (no extra software needed), but it turned out
the mod's own code was silently defeating itself. Confirmed on a standard
DualSense and a DualSense Edge over `ds5dongle`.

## The symptom

Windows always shows an active 4-channel WASAPI render endpoint for a wired
USB DualSense (no drivers needed — it's real USB Audio Class hardware). The
mod's `DualsenseAudioBridge.exe`/`SoundPlayer.cs` opened that endpoint fine
in Shared mode and played audio with zero errors, but the physical speaker
stayed completely silent — every time, on every fresh USB connection. The
same channels-3/4 actuator content (via `HapticPlayer.cs`) reached the
motors and produced real felt vibration, ruling out the WASAPI/format side
of the pipeline as the culprit.

## Everything that was tried and ruled out (in order)

1. `scePadSetAudioOutPath`/`scePadSetVolumeGain` alone, with an out-of-range
   volume (100 → hardware byte 0xA4, invalid; PS5 only uses 0x3D-0x64) —
   fixed the range, no change.
2. Channel mapping — confirmed correct against a working reference
   (`ch1` = speaker feed, `ch2`/`ch3` = actuators, matching our own
   confirmed `--test-haptic`).
3. One-shot vs. continuous re-application of the same calls every 200ms — no
   change.
4. `scePadSetVibrationMode` "wake" call before the audio calls — no change.
5. Holding a real WASAPI stream open for 30+ seconds instead of a few
   seconds — no change.
6. Windows-side settings audit (spatial audio, audio enhancements, exclusive
   mode, default device, OS volume/mute) — all clean, none were the cause.
7. 16-bit PCM instead of 32-bit float (derived from measuring a working
   capture's isochronous packet byte count) — worked once, ambiguous, then
   failed on a clean fresh-replug retest.
8. WASAPI Exclusive mode instead of Shared — Windows rejected the requested
   format outright for this device.
9. Jittering the volume value ±1 every 200ms specifically to force duaLib's
   diff-check to re-assert the `AllowSpeakerVolume` bit — the value
   genuinely changed on the wire (confirmed byte-for-byte via capture) but
   the Allow bit never appeared. This was the thread that led to the real
   root cause below.

None of 1–9 could ever have worked. The real bug was elsewhere.

## Root cause

Found via Wireshark + USBPcap, capturing a **known-working DualSenseY-v2**
session side-by-side with our own silent attempts, same session, no
controller replug between them (device address collides across different
USBPcap1/2/3 interfaces — always filter by `frame.interface_id` too, not
`usb.device_address` alone, or you'll silently mix in an unrelated device).

The DualSense's actual gamepad output-report channel on wired USB is
**endpoint 3, OUT, interrupt (`URB_FUNCTION_BULK_OR_INTERRUPT_TRANSFER`),
HID class, Report ID 0x02** — not a control-transfer `SET_REPORT` as first
assumed. Decoding it byte-for-byte against `dataStructures.h`'s documented
struct offsets (wire byte 1 = struct offset 0, containing
`AllowSpeakerVolume` at bit 5; wire byte 6 = struct offset 5 =
`VolumeSpeaker`; wire byte 8 bits 4-5 = `OutputPathSelect`) showed our
`VolumeSpeaker`/`OutputPathSelect` byte values were always correct and
matched DualSenseY's own writes exactly — but bit 5 of byte 1
(`AllowSpeakerVolume`) was never set in any of our writes, while
DualSenseY's showed it set whenever the tracked value was genuinely
changing.

`speaker/DualSenseEnhancedTransport/third_party/src/duaLib-master/src/source/readDualsense.cpp`
has a block (~line 184, comment "RE4R's experimental transport owns
adaptive triggers only") written for the **adaptive-trigger transport**, an
earlier and completely unrelated feature: it unconditionally zeroed
`AllowHeadphoneVolume`/`AllowSpeakerVolume`/`AllowMicVolume`/
`AllowAudioControl`/`AllowAudioMute` on every single output tick, so a
trigger-only caller could never accidentally reroute the Windows speaker
endpoint. This ran immediately *after* the correct diff-check a few lines
above had already computed `AllowSpeakerVolume=true` in response to our
`scePadSetVolumeGain` call — so the new value byte reached the wire
correctly (confirmed via capture), but the "please apply this" flag was
always stripped back to 0 before send, and the firmware silently ignored
the byte. Every symptom chased in steps 1–9 above was a downstream
consequence of this one block.

## The fix

Same pattern as the existing `playerIndicatorsEnabled`/`micLightEnabled`/
`lightBarOverrideEnabled` opt-in flags:

1. `duaLibUtils.hpp`: added `bool audioControlEnabled = false;` to the
   `controller` struct.
2. `duaLib.cpp`: `scePadSetAudioOutPath`/`scePadSetVolumeGain` now set
   `controller.audioControlEnabled = true;` and (matching
   `scePadSetLightBar`/`scePadSetMicLight`) force
   `controller.wasDisconnected = true;` so a real `hid_write` happens even
   if the value coincidentally matches a fresh zero-initialized default.
3. `readDualsense.cpp`: the suppression block now only clears those 5 Allow
   flags `if (!controller.audioControlEnabled)`; when enabled, it leaves
   whatever the diff-check above computed untouched.

Rebuilt with the documented toolchain (`third_party\toolchain\llvm-mingw-
20260616-ucrt-x86_64\bin\x86_64-w64-mingw32-clang++.exe`, same command as
the 2026-07-06 build). New confirmed hash
`63B4B3A8ED04A1C55C054DDF99FBAB8D1A3C263E27B18975CF96173DDEB61066` —
supersedes `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`
(see `speaker/BUILD.md`, `speaker/DualSenseEnhancedTransport/README.md`,
`docs/DUALIB_HID_BRANCH.md`, all updated).

## Startup integration

`DualsenseAudioBridge.exe`'s `Program.cs` now runs a short-lived
`DualSenseEnhancedTransport.exe --test-speaker-init --acknowledge-output-conflict
--duration 3000 --speaker-volume 72` subprocess as soon as it starts
(`RunEarlySpeakerInit`), independent of the game-campaign-ready gate the
trigger/gyro `--watch` session waits for. This is deliberately a one-shot
call, not a persistent second process holding the duaLib handle open: the
route has been hardware-confirmed to survive process exit and even a full
Windows restart (the controller was never actually power-cycled), so a
single successful write early in the bridge's life is enough for the
speaker to work in menus and loading screens, not just once a save is
active. `--watch` also received an opt-in `--init-speaker`/`--speaker-volume`
flag that re-applies the same init once duaLib opens for the trigger/gyro
session, as a defense-in-depth reassertion (e.g. after a mid-session USB
replug) — not required for the primary fix to work.

`speaker-volume` default is 72 (hardware byte 0x88), matching DualSenseY-v2's
own maximum slider position (`0..8 × 9`), not the PS5's own conservative
0x3D-0x64 range — the DualSense's internal speaker element is quiet even at
the PS5's own reported maximum, and 0x88 was directly observed in a working
capture without artifacts.

## UI

`DualSenseEnhanced.lua`'s "Speaker Volume" slider was hard-capped at 100% —
raised to 200% (`audio_feedback.lua`'s `emit()` clamp and
`DualsenseAudioBridge/SoundPlayer.cs`'s gain clamp both raised to match)
since even the loudest native hardware volume is subjectively quiet and
software gain above unity is still useful.

## Tooling notes (kept installed, reusable for future USB-level debugging)

Wireshark + USBPcap + Npcap all installed system-wide. Two non-obvious setup
steps: winget's silent Wireshark install skips both USBPcap and Npcap (both
need separate installers, from their own GitHub/official sites); and
`USBPcapCMD.exe` from `C:\Program Files\USBPcap\` must be manually copied
into `C:\Program Files\Wireshark\extcap\` (admin rights) or Wireshark's GUI
never lists `USBPcap1/2/3` as capture interfaces even with the driver
running. A reboot was also needed once after first install before the
interfaces appeared, even with the file already copied correctly.

Always filter USBPcap captures by `frame.interface_id == N` together with
`usb.device_address == M` — device address values collide across different
USBPcap1/2/3 interfaces (each root hub has independent addressing), and
filtering by device address alone will silently mix in an unrelated
device's traffic.
