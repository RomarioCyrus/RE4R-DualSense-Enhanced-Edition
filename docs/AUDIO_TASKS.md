# AUDIO_TASKS.md - Bridge Tasks

## Completed

- Restored the audio-only `DualsenseAudioBridge`.
- Removed the stutter-prone custom `DualsenseDsxBridge`.
- Replaced the v1.0 trigger/LED dependency on external DSX with the shared
  native `DualSenseEnhancedTransport.exe` duaLib path.
- Added duplicate-process protection and launcher lifetime management.
- Preserved WinDbg diagnostics for the `nssvpd.sys` kernel crash.
- Published portable and compact audio builds.
- Replaced Fatal Kick's unwanted long layer with three clean randomized
  composite variants.
- Disabled routine pickup ID diagnostics while preserving pickup sounds.
- Added and deployed conservative reload profiles for all currently cataloged
  rifles and magnums.
- Added conservative `start + insert` profiles for Punisher, Red9, Blacktail,
  and Matilda in the project runtime and catalog.
- Confirmed the correction pass for SG-09 R, W-870, Striker, Handcannon,
  Skull Shaker, SR M1903, Broken Butterfly, and the earlier Riot Gun profile.
- Confirmed SG-09 R dry fire through Wwise
  `soundlib.SoundManager.postRequestInfo` event ID `2330373695`, routed to
  `wp4000_dry_fire` with synchronized controller-speaker playback.
- Implemented and deployed the manual WASAPI audio endpoint picker:
  `DualsenseAudioBridge.exe` writes `DualSenseEnhanced/audio_devices.json`,
  `audio_feedback.lua` emits `device_id`, and the REFramework UI exposes
  `Auto DualSense`, `Manual Endpoint`, and `Legacy Presets`.
- Live-tested the endpoint picker with a connected controller: devices appear
  as directly selectable rows in the UI, and `Test Speaker` plays through the
  selected endpoint, including non-controller Windows output devices.
- Fixed `Test Speaker` by changing its smoke-test event from missing
  `heal_herb` audio to confirmed `parry` WAV variants. Removed the redundant
  `Test Parry` UI button.
- Added native speaker-route initialization; controller-speaker playback no
  longer requires DSX or DualSenseY.
- Shipped Enhanced Haptics with sprint-gated footsteps, companion action
  pulses, continuous intensity, and per-category toggles.
- Shipped per-item healing speaker/haptic routing for herbs, spray, eggs,
  fish, viper, and rhinoceros beetle.

## Required In-Game Verification

1. Test `Auto DualSense` with one connected controller. It should choose the
   controller endpoint without manual selection.
2. If two controllers are available, test `Manual Endpoint` selection for each
   endpoint and confirm audio goes to the selected controller. This is the main
   unverified scenario for the new endpoint-ID routing.
3. Confirm that no DualSense endpoint appears in `audio_devices.json` when the
   controller is physically disconnected; this is expected and not a bridge
   failure.
4. Test the corrected profiles in this order: Broken Butterfly, CQBR, Killer7,
   Skull Shaker, SR M1903, Handcannon, then W-870.
5. For W-870, SR M1903, and Handcannon, test both an ordinary shot and the
   final shot. The final shot must not cycle immediately; one deferred cycle
   must occur after the next reload.
6. Tune the provisional one-second post-shot delay for Broken Butterfly and
   Skull Shaker only if gameplay shows it is wrong.
7. Preserve Riot Gun start + insert until a real reload-end candidate is found.
8. Rebuild the Stingray test plan. The current conservative `start + finish`
   mapping regressed and should be tested phase-by-phase before another runtime
   patch.
9. Test Punisher, Red9, Blacktail, and Matilda in this order. For each weapon,
   compare a tactical reload against a reload from empty and report whether a
   separate slide/chamber cue is actually needed.
10. Confirm exactly one audio bridge and one UDP client during the pass.
11. Observe frametime with both helpers active.
12. Exit RE4R and confirm both helper processes stop.

Do not mark the new weapon profiles confirmed merely because the files are
deployed and the bridge smoke test passes.

Stop testing if vibration, stutter, USB disconnect, or driver instability
returns.

## Driver Follow-up

- Check for compatible DSX/Nefarius driver updates newer than 2.62.0.0.
- Preserve the crash dump and `bsod-analysis.txt`.
- Verify the external UDP client's provenance and license before redistribution.

## Deferred Research

- Do not integrate `DualSenseHapticsProbe` into the stable launcher. Native
  RE4R vibration mode and 4-channel audio-haptics did not coexist reliably.
- Do not pursue whole-game/SFX-bus loopback as the next audio milestone.
  Separate Wwise bus capture is not exposed by the PC game, and Dolby Atmos or
  other spatial post-processing complicates post-mix extraction.
- Continue the current event-based extracted-WAV mappings manually when new
  sounds are worth adding. Confirmed Wwise event IDs from `postRequestInfo`
  may be used as low-latency triggers for those extracted WAVs.
- Native gyro without Steam Input is now an opt-in native input module, not an
  audio feature. The audio bridge only reads `DualSenseEnhanced/native_gyro.json` and
  passes the settings when it starts the one shared delayed duaLib watcher. It
  may still switch RE4R to keyboard/mouse prompts while injecting camera deltas,
  so prompt handling remains separate from audio work.
