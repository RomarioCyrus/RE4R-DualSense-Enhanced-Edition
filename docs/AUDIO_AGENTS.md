# AUDIO_AGENTS.md - Bridge Rules

## Hard Boundary

| Process | Responsibility |
|---|---|
| `DualsenseAudioBridge.exe` | Audio event file, NAudio, WASAPI |
| external `DSX_UDPClient.exe` | DSX payload forwarding |

Never add UDP or `payload.json` handling back to the audio bridge. Do not
reintroduce the removed custom `DualsenseDsxBridge` without a reproducible
frametime test showing that its stutter problem is solved.

## Launcher Rules

- Start both helpers outside the game thread.
- Prevent duplicate UDP client launches.
- Start the UDP client from the RE4R game directory.
- Keep an auto-started UDP client in a kill-on-close Windows Job Object.
- Do not terminate an instance that was already running before the launcher.

## Audio Rules

- Open WASAPI only for mapped audio events.
- Release all playback objects after completion.
- Keep device enumeration and playback outside the game process.
- USB is required for DualSense speaker output.
- Keep numbered-variant randomization and immediate-repeat avoidance.
- Treat weapon profiles as implemented, gameplay-confirmed, and
  controller-confirmed separately.
- Use `docs/weapon_audio_catalog/README.md` as the status index.
- Do not add unresolved, surface-routed, selector/safety, or post-shot assets
  to runtime mappings without validation.
- Pickup diagnostics must remain opt-in; pickup sound emission must not depend
  on diagnostics being enabled.
- The audio-only bridge can be tested without DSX in native DualSense mode.
- Do not assume DSX and native game DualSense support can coexist. DSX may
  suppress native haptics and compete for LED state.
- Keep live SFX-bus/Wwise capture and actuator loopback experimental; the
  supported baseline is event-triggered playback of extracted WAV files.
- Wwise event-ID routing through `soundlib.SoundManager.postRequestInfo` is
  allowed for extracted-WAV timing. Gate mappings by weapon/ammo/context before
  emitting through `audio_events.json`, keep `onEndOfEvent` as a late
  confirmation logger, and do not confuse this with live SFX-bus capture.
- Add confirmed always-on routes to `wwise_audio_router.lua`. Use
  `sound_event_diag.lua` only for opt-in capture, manual windows, and
  discovery logging.

## Safety Context

A prior test correlated with a `0xD1` kernel crash in `nssvpd.sys`, Nefarius
Virtual Gamepad Emulation Bus G2 2.62.0.0. Preserve process isolation and the
diagnostic files.

## Required Tests

1. Publish portable and compact audio builds.
2. Verify the audio log has no UDP or payload activity.
3. Verify the launcher starts one instance of each helper.
4. Verify auto-started helpers stop with the game.
5. Test DSX effects and audio independently before a combined parry test.
6. For weapon-audio changes, test each weapon and each reload shape separately
   before marking the profile confirmed.
