# AUDIO_CODEX_PROMPTS.md - Ready-to-Use Prompts

## Initial Context

```text
Read AUDIO_AGENTS.md, AUDIO_MEMORY.md, AUDIO_TASKS.md, and BUILD.md.
Then inspect speaker/DualsenseAudioBridge and the main audio_feedback.lua /
feedback_writer.lua modules.

Do not edit yet. Confirm this architecture:
- Lua writes audio_events.json for controller-speaker events.
- Lua writes DualSenseEnhanced/payload.json for triggers and LEDs.
- DualsenseAudioBridge.exe watches only audio_events.json.
- Audio uses NAudio/WASAPI.
- External DSX_UDPClient.exe forwards payload.json to DSX.
- DSX must run for custom LED/adaptive-trigger tests. For native DualSense
  audio-only tests, close DSX and disable Steam Input.
- A native REFramework plugin starts both helpers; Lua os.execute is
  unavailable.
```

## Verify the Split Bridge Architecture

```text
Read AUDIO_AGENTS.md and AUDIO_MEMORY.md.

Task: verify the current split bridge architecture without changing it.

Portable build:
speaker/DualsenseAudioBridge/dist/audio-portable/DualsenseAudioBridge.exe

Verification:
1. Confirm DSX is running.
2. Confirm exactly one DualsenseAudioBridge.exe and one DSX_UDPClient.exe.
3. Start the bridge hidden with the correct --reframework path if testing it
   outside the launcher.
4. Verify the audio log reports the sounds/events paths and listening state.
5. Emit a mapped audio event and verify physical controller-speaker playback.
6. Verify lightbar, adaptive triggers, Player LED, and Mic LED through the
   external UDP client.
7. Verify both launcher-owned helpers exit with the game.

Do not report success for an untested weapon profile merely because the bridge
starts or its files are deployed.
```

## Add an Audio Event

```text
Read AUDIO_MEMORY.md, AUDIO_TASKS.md, and docs/game_events.md.

Task: add one confirmed in-game audio event to the existing JSON emitter.

Requirements:
- Reuse an existing confirmed game hook when possible.
- Do not install a duplicate hook merely for audio.
- Preserve the event format: event, unique ts, device, volume.
- Add a SoundMap entry and document the expected filename.
- Missing sound files must log and skip without crashing.
- Test through the physical DualSense speaker.
- Update AUDIO_MEMORY.md and CHANGELOG.
```

## Modify DSX UDP Forwarding

```text
Read AUDIO_AGENTS.md and inspect the native launcher integration.

Task: change how the external DSX_UDPClient.exe is launched or managed.

Constraints:
- Do not add UDP or payload.json handling to DualsenseAudioBridge.exe.
- Preserve duplicate-process protection.
- Preserve the launcher-owned Windows Job Object.
- Do not terminate a UDP client that existed before the launcher.
- Run a reproducible frametime test before replacing the external client.
```

## Build Release Artifacts

```text
Read speaker/BUILD.md.

Task: build and verify both bridge variants.

Outputs:
- dist/audio-portable: self-contained compressed release.
- dist/audio-compact: framework-dependent single-file release.

After building:
1. Report exact sizes and SHA-256 hashes.
2. Run a startup/log/path smoke test.
3. Verify mapped audio-event resolution.
4. Do not include PDB, bin, obj, .dotnet, logs, user config, or
   DSX_UDPClient.exe in the release package.
```

## Validate Weapon Audio

```text
Read AUDIO_MEMORY.md, AUDIO_TASKS.md, docs/game_events.md, and
docs/weapon_audio_catalog/README.md.

Task: validate one implemented weapon-audio profile.

Requirements:
- Test full, partial, and one-round/one-shell reload forms where applicable.
- Record early, late, extra, and missing phases.
- Keep unresolved, surface, selector/safety, and post-shot candidates disabled
  unless the test specifically validates them.
- Update the individual weapon profile, README status table, AUDIO_MEMORY.md,
  AUDIO_TASKS.md, and CHANGELOG.md.
- Distinguish deployed, bridge-smoke-tested, and physically confirmed states.
```
