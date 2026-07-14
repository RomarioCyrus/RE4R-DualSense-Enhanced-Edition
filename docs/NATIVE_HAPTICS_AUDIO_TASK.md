# Native DualSense LED, Audio, And Haptics Research Task

## Purpose

Find whether RE4R can drive custom DualSense LED, controller-speaker audio,
and haptics natively, without DSX, the WASAPI audio bridge, or expanding the
confirmed duaLib trigger/gyro transport into a broad HID output owner.

This task is intentionally not about adaptive triggers or gyro. Those are
already implemented through the isolated duaLib watcher.

## Operating Mode

Use this baseline for every test:

- USB DualSense or DualSense Edge.
- Steam Input disabled.
- DSX closed.
- RE4R running in native DualSense mode, detected as
  `via.hid.VendorNativeDualSenseDevice`.
- Preserve Capcom native shot, reload, damage, knife, and low-HP haptics.
- Preserve the confirmed custom native lightbar path.
- Preserve the existing stable DSX/WASAPI bridge architecture unless a fully
  isolated experiment proves a replacement path.

Do not test native output while DSX is running. Previous tests show DSX
suppresses native haptics and competes for lightbar ownership.

## Confirmed So Far

### Native lightbar

Confirmed working:

- `native_feedback.lua` captures `share.hid.Device` and the native
  DualSense device.
- Custom lightbar output works through `set_LightBarColor` /
  `resetLightBarColor`.
- Capcom lightbar writes can be temporarily suppressed while a mod LED source
  owns the lightbar.
- A post-`share.hid.Device.update` enforcement write prevents Capcom's cached
  lightbar state from winning between mod updates.
- Normal HP, heal, damage, parry, event lightbar effects, and the red/orange
  low-HP pulse work in native gameplay while Capcom haptics remain active.

Known limitations:

- Player indicator LEDs and Mic LED have no confirmed RE4R managed setter.
- Menu lightbar override is deferred and non-critical.

### Native haptics

Confirmed baseline:

- Capcom native haptics work for shots, reloads, damage, knife impacts, and
  low-HP heartbeat.
- These continue to work while the custom native lightbar and confirmed
  duaLib trigger transport are active.

Not yet solved:

- No confirmed custom haptic impulse API exists in REFramework Lua.
- `chainsaw.PlayerManager` adaptive-trigger probes did not reveal a useful
  custom haptic path.
- Do not confuse adaptive triggers with actuator haptics. Adaptive triggers
  are solved through duaLib; this task is about native vibration/audio-haptic
  output.

### Controller-speaker audio

Confirmed stable workaround:

- The current event-based speaker path is still
  `audio_feedback.lua` / `wwise_audio_router.lua` -> `audio_events.json` ->
  `DualsenseAudioBridge.exe` -> Windows WASAPI DualSense speaker endpoint.
- This bridge works in native DualSense mode because it does not write HID
  output reports.

Not yet solved:

- No confirmed REFramework/native game API plays arbitrary custom WAV/PCM data
  through the controller speaker.
- duaLib exposes audio route, volume, and mute controls, but no WAV/PCM
  playback API. Do not treat duaLib as a replacement speaker bridge unless new
  evidence proves otherwise.

### Native Wwise "Controller Speaker" sink (found, not pursued) -- 2025-06-29

The game's own `init.bnk` (Wwise init bank) contains a genuine
`CAkAudioDevice` (Sink) HIRC object named `controller_speaker`
(`ulID=1334442663`), using the Audiokinetic-provided plugin
`fxID=0x00B30007 [Controller Speaker]` (`type=Sink, company=Audiokinetic`).
Confirmed via wwiser's full bank dump (`View banks` -> `banks.xml` in
FusionTools' bundled wwiser GUI) on `init.bnk`, not just the per-event txtp
generator. Several sibling `CAkAudioDevice` objects exist alongside it in
the same bank: `Ch_HomeCinema`, `system_No3dAudio`, `No_Output`,
`System_PS4`, `Microsoft_Spatial_Sound_Platform_Output` -- these are
separate Sink definitions, not values of one switchable State Group (an
earlier hypothesis in this research, based on `wwnames.txt` grouping them
together, was wrong: they're a flat list of HIRC objects sharing a bank
section, not one enum).

This confirms RE4R's Wwise project (shared across platforms in the bank
data) defines the exact same first-party Sony Wwise "Controller Speaker"
sink plugin used on PS4/PS5 to route audio (e.g. radio/Hunnigan call
dialogue) to the DualSense's onboard speaker. It is almost certainly inert
on the PC build: Wwise Audio Devices are normally statically assigned to a
Bus at Wwise-project build time, and the "Controller Speaker" plugin's
actual implementation calls Sony's native platform audio APIs
(`sceAudioOut`/`scePad*`), which don't exist outside PlayStation SDKs --
the PC executable's Wwise plugin registry almost certainly has no working
backend for this Sink type, so any Bus statically routed to it on PC
just silently drops that audio.

`soundlib.SoundManager` does expose a managed `setState(stateGroupId,
stateId)` wrapper (confirmed in `reframework_object_explorer_dump.json`,
mirroring `AK::SoundEngine::SetState`), but this is very unlikely to be the
right lever here: State Groups switch *content* variations (e.g. an echo
on/off switch), not a Bus's output device assignment, which is normally
fixed at Wwise-project compile time, not a runtime-switchable property.

To actually make this sink functional on PC would require writing a custom
native Wwise Sink plugin (`IAkSinkPlugin`) that receives the mixed PCM
buffer for whatever bus is statically routed to `controller_speaker` and
forwards it to the DualSense's WASAPI endpoint (functionally similar to
the existing `DualsenseAudioBridge.exe`, but living inside the game
process), then injecting/registering it into the already-running `re4.exe`
via `AK::SoundEngine::RegisterPlugin` -- which normally must happen before
bank loading, deep in untouched native engine init code, requiring
binary-level reverse engineering (Wwise SoundEngine is statically linked,
no exported symbol to hook cleanly) and exact ABI matching to whatever
Wwise SDK version this build uses.

**Decision (2025-06-29): not pursuing this.** The risk/fragility (native
binary patching, breaks on every game update, real crash risk) is
disproportionate to the actual problem this was being evaluated for, which
is purely about *not shipping extracted Capcom WAV/WEM assets in the mod*
-- not about achieving lower latency or removing the bridge. The chosen
solution for that problem is runtime extraction from the user's own
already-installed game files (see `IDEAS.md`/`MEMORY.md` weapon-audio
sections for the active plan: decode `.wem` to PCM on the user's machine at
first run via an open-source decoder such as vgmstream, never bundling any
Capcom-derived asset in the mod itself). duaLib was also considered and
ruled out for this specific problem: it only controls DualSense audio
routing/volume/mute at the HID level and has no Wwise/Sink-plugin
capability -- it cannot inject into or read from the game's internal
Wwise mixer, and is irrelevant to either the native-sink idea or the
runtime-extraction plan.

### Audio-to-haptics probe

`speaker/ExperimentalDualsenseHidBridge` tested the public Windows
4-channel DualSense audio-haptics path.

Confirmed findings:

- The 4-channel endpoint can open.
- Standalone tone/loopback experiments exist.
- In RE4R native mode, plain tone and live-loopback tests are silent while the
  game owns native vibration mode.
- One-shot and five-report/200 ms HID selections for native/audio-haptics mode
  did not produce reliable actuator playback in RE4R native mode.

Current conclusion:

- RE4R native haptics and this WASAPI audio-to-haptics path do not currently
  coexist reliably.
- Do not auto-start or integrate `DualSenseHapticsProbe` into the stable path.

## Closed Or Risky Paths

Do not restart these unless there is new evidence:

- DSX/native hybrid ownership. It suppresses native haptics and causes LED
  ownership conflict.
- `share.hid.Device.setAdaptiveTriggerFeedback`. It caused a confirmed game
  crash and is hard-disabled.
- PlayerManager L2/adaptive-trigger probe. It did not acquire a usable live
  path and does not solve audio or haptic actuator output.
- Direct blind HID writes that do not merge or own the full output report.
  DualSense output is a compound report; a narrow write can reset audio mode,
  lightbar, vibration mode, trigger state, mute, volume, or rumble fields.
- Replacing the stable speaker bridge before a native path is physically
  confirmed on the controller.

## Research Targets For The Next Agent

### Target A: RE4R native API discovery

Search the REFramework object dump and runtime Object Explorer for native
DualSense methods related to:

- speaker output;
- audio route / audio haptics / vibration mode;
- actuator vibration impulses;
- haptic wave index or haptic pattern playback;
- player indicator LEDs;
- Mic LED;
- lightbar state beyond the already confirmed color path.

Start from likely namespaces and types:

- `share.hid.*`
- `via.hid.*`
- `chainsaw.*Haptic*`
- `chainsaw.*GamePad*`
- `chainsaw.*Pad*`
- `soundlib.*`
- `via.input.*`

The first deliverable is a method table, not code:

| Type | Method/field | Parameters | Read/write | Observed calls | Risk | Candidate use |
|---|---|---|---|---|---|---|

### Target B: Read-only runtime diagnostics

If candidate methods exist, add read-only diagnostics first:

- hook/log method calls without modifying output;
- capture parameter values during shots, reloads, damage, knife impacts, low
  HP heartbeat, pause/menu transitions, and radio/dialogue if relevant;
- identify whether calls are Capcom haptic events, lightbar writes, audio
  routing, or generic gamepad state updates.

Do not call setters during the first pass unless the method's effect and
parameters are already understood.

### Target C: Isolated custom haptic impulse MVP

Only after read-only evidence:

1. Build a manual, opt-in, in-game test button or standalone experiment.
2. Send one very weak custom actuator impulse.
3. Confirm Capcom native haptics still work afterward.
4. Confirm custom lightbar still works afterward.
5. Confirm controller-speaker audio through the existing bridge still works.
6. Confirm no stuck vibration, mute, audio-route change, disconnect, or input
   regression.

Success is not "any vibration happened." Success is a custom haptic impulse
that coexists with RE4R native haptics and the confirmed native lightbar.

### Target D: Native controller-speaker audio feasibility

Look for an in-process RE4R or RE Engine route to the controller speaker.
Useful evidence would include:

- a native method that accepts speaker/audio buffers;
- a game-side API that routes a sound/event to the DualSense speaker endpoint;
- a way to reuse RE4R's own native controller audio path if one exists;
- proof that Wwise events can be routed to controller speaker without the
  external WASAPI bridge.

Do not count ordinary Windows WASAPI playback as native. The current bridge
already covers that path.

### Target E: Direct HID only as a last-resort design

If no RE4R API exists, direct HID may be researched only as a single-owner or
report-merging design.

Required before implementation:

- document the full USB output report fields touched by the design;
- preserve current trigger-only duaLib output-field suppression;
- preserve Capcom vibration mode and custom lightbar state;
- define how RE4R's concurrent output writes are observed, merged, or avoided;
- define an emergency reset path.

Do not create a second broad HID writer that blindly sends partial reports.

## Suggested Prompt For Another Agent

```text
Read docs/AGENTS.md, docs/TASKS_FOR_CODEX.md,
docs/NATIVE_HAPTICS_AUDIO_TASK.md, docs/DUALIB_HID_BRANCH.md,
docs/AUDIO_MEMORY.md, docs/BUGS.md, docs/game_events.md,
speaker/ExperimentalDualsenseHidBridge/README.md, and
src/reframework/autorun/DualSenseEnhanced/native_feedback.lua.

Task: research native DualSense LED, controller-speaker audio, and actuator
haptics in RE4R without DSX and without the WASAPI audio bridge. Do not work
on gyro or adaptive triggers; those are already implemented through the
confirmed duaLib watcher.

Start by producing a candidate method/API table from the REFramework dump and
existing runtime diagnostics. Separate confirmed behavior, rejected paths, and
unknown candidates. Do not add setters or output writes until a read-only
diagnostic pass proves what the method does. The target success criteria are:
custom haptics or native speaker audio that coexist with Capcom native
haptics, custom native lightbar, controller input, controller-speaker bridge
playback, and the confirmed duaLib trigger/gyro transport.
```

## Evidence Files

- `docs/TASKS_FOR_CODEX.md`
- `docs/DUALIB_HID_BRANCH.md`
- `docs/AUDIO_MEMORY.md`
- `docs/BUGS.md`
- `docs/CHANGELOG.md`
- `docs/game_events.md`
- `src/reframework/autorun/DualSenseEnhanced/native_feedback.lua`
- `src/reframework/autorun/DualSenseEnhanced/dualib_trigger_ipc.lua`
- `src/reframework/autorun/DualSenseEnhanced/native_gyro.lua`
- `speaker/ExperimentalDualsenseHidBridge/README.md`
- `speaker/DualSenseEnhancedTransport/README.md`
- `reframework_object_explorer_dump.json`
