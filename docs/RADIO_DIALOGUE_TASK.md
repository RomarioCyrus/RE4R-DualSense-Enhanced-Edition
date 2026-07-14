# Task: Investigate PS5-style Radio Dialogue Routing

Source task brief: `<downloads-root>\radio_dialogue_routing_codex_task.md`
(copied here for project reference).

## Project Context

Current architecture:
- Works with native DualSense support.
- Does not require DualSenseEnhancedFeedback.
- Does not require Steam Input.
- Preserves native RE4R haptics.
- Adds custom LED/lightbar logic.
- Adds enhanced adaptive triggers.
- Adds controller speaker audio for selected events.
- Adds/experiments with native gyro-to-mouse aiming.
- Audio Bridge can play WAV files to selected output devices.

## Goal

Implement PS5-style radio dialogue behavior for RE4R PC:

- Radio replies/dialogues should play through the DualSense speaker.
- Ideally, radio dialogue should not play through the main game audio mix.
- Radio should not drive haptics by default.
- This should work without DSX or Steam Input.

## Observed PS5 Behavior

On PS5:
- Radio/communication dialogue is routed to the DualSense speaker.
- Radio dialogue appears to be absent or strongly reduced in the main game audio mix.
- Music does not affect haptics.
- Dialogue does not affect haptics.
- Effects/SFX appear to drive haptics.
- Radio behaves like a special speaker-only route.

## Status

- Hooks for radio/dialogue events: not yet found. Must be discovered via
  live diagnostic capture (same `Sound Event Diagnostics` workflow used
  for weapon audio), not assumed from prior research.
- Radio dialogue WAV assets: not yet extracted. Must be located in the
  game's Wwise voice banks and extracted via FusionTools, same as weapon
  audio assets.
- Phase 1 (Speaker Duplicate MVP) scaffolding implemented:
  `src/reframework/autorun/DualSenseEnhanced/radio_dialogue.lua`, wired into the
  loader, settings persistence, and a "Radio Dialogue (Experimental)" UI
  section in `DualSenseEnhanced.lua`. A placeholder test event (`radio_test`,
  reusing `heal_herb.wav`) lets the speaker path be verified before any
  real hook is found.
- Phase 2 (mapping table): skeleton started at
  `docs/radio_dialogue_mapping.csv`, empty until the first real event is
  captured.
- Phase 3 (Runtime Mute) and Phase 4 (Repacked Silence): not started.

## Next Step

Capture a live radio call (e.g. calling Hunnigan, or an incoming call) with
`Sound Event Diagnostics` open, the same way weapon reload events were
identified. Look for new candidate event IDs that are not part of any
already-catalogued weapon bank and that occur only during the call.

---

# Implementation Options

## Mode A: Speaker Duplicate

Hook known radio/dialogue events and play matching WAV files through the DualSense speaker.

Original game audio remains unchanged.

### Pros
- Safest approach.
- Easy to test.
- No game file modifications.
- No repacking.
- Works as an MVP.

### Cons
- Dialogue is duplicated in the main game audio and DualSense speaker.
- Less PS5-like.

### Use Case
Good first implementation and debugging mode.

---

## Mode B: Speaker Only via Repacked Silence

Replace original game radio dialogue files with silent dummy audio files.

The mod plays the matching WAV through the DualSense speaker.

### Pros
- Predictable.
- Closest to PS5 behavior if runtime mute is impossible.
- Does not require Wwise event blocking.

### Cons
- Requires repacked audio files.
- Larger mod size.
- Language-specific.
- Patch fragile.
- Potentially conflicts with other audio mods.
- Less user-friendly.

### Use Case
Fallback / legacy method only.

Do not make this the primary implementation unless runtime mute is impossible.

---

## Mode C: Speaker Only via Runtime Mute / Wwise Interception

Hook relevant Wwise/dialogue events at runtime.

When a radio dialogue event is detected:
1. Prevent or mute original playback in main mix.
2. Play the corresponding WAV through the DualSense speaker.

### Pros
- Best user experience.
- No repacking.
- Smaller mod size.
- Toggleable in UI.
- Cleaner distribution.
- Most user-friendly.
- Closest to native PS5 behavior.

### Cons
- Hardest approach.
- Requires finding a hook before audio reaches the main mix.
- May require event-level mute, bus routing, object-specific mute, or volume override.
- Localization may complicate mapping.
- Must preserve subtitles and timing.

### Use Case
Preferred final implementation.

---

# UI (implemented, Phase 1)

`DualSenseEnhanced.lua` → "Radio Dialogue (Experimental)" section:

```text
Radio Output Mode:
- Off
- Speaker Duplicate
- Speaker Only - Repacked Silence (not implemented)
- Speaker Only - Runtime Mute (not implemented)

Radio Speaker Volume: 0.0 - 1.0
Radio Latency Offset: -500 ms to +500 ms
Radio Haptics: Off (fixed; not exposed as a toggle yet)
Play Test button
```

Default: `enabled = false`, `mode = "speaker_duplicate"`.

---

# Research Questions

## Event Detection

1. Can radio dialogue events be hooked reliably?
2. Can the mod identify the exact Wwise event ID/name for each radio line?
3. Can the mod map hook events to extracted WAV files?
4. Can radio calls be distinguished from normal dialogue?
5. Can Hunnigan/Ada/other communication calls be separated from regular voice lines?

## Runtime Mute

1. Can the original Wwise event be stopped before it reaches the main output?
2. Can event volume be set to 0 at runtime for selected events?
3. Can a dialogue bus or object-specific emitter be muted temporarily?
4. Can a specific Wwise playing ID be stopped immediately after detection?
5. Is there a pre-play callback/hook available?
6. Is there a post-event hook only? If yes, is that too late to prevent playback?
7. Does muting break subtitles, timing, animation, or cutscene state?

## Localization

1. Can the currently selected voice language be detected?
2. Are Wwise event IDs shared across languages?
3. Are WEM Source IDs language-specific?
4. Should the mod include WAV files for only one language initially?
5. Can the mod fall back gracefully if the required language WAV is missing?

---

# Recommended Development Path

## Phase 1: Speaker Duplicate MVP — implemented (scaffolding)

Implement radio speaker playback using known hooks.

Behavior:
```text
Radio event detected
↓
Play matching WAV on DualSense speaker
↓
Original game dialogue remains unchanged
```

Deliverables:
- [x] UI toggle.
- [x] Radio volume slider.
- [x] Latency offset.
- [x] Play Test button (placeholder WAV).
- [ ] Hook a real radio event (pending live capture).
- [ ] Confirm timing against the real event.

## Phase 2: Radio Event Mapping — started

Mapping table skeleton: `docs/radio_dialogue_mapping.csv`

```csv
dialogue_event,character,line_id,language,wav_file,hook_source,confidence,notes
hunnigan_intro,Hunnigan,line_001,en,event_radio_001.wav,known_hook,high,radio call start
```

## Phase 3: Runtime Mute Research — not started

Investigate:
- Wwise event suppression
- event volume override
- object-specific mute
- dialogue bus mute
- stop event immediately after detection
- pre-play vs post-play hooks

Goal:
```text
Radio event detected
↓
Original game output muted/suppressed
↓
WAV plays only through DualSense speaker
```

## Phase 4: Repacked Silence Fallback — not started

Only if runtime mute is not feasible.

Implement optional silence pack:
- Replace selected original radio dialogue WEM/WAV files with silent files.
- Mod plays the real dialogue through DualSense speaker.
- Keep this as an optional compatibility/fallback route.

---

# Suggested Config (implemented shape, in `radio_dialogue.lua` / settings)

```json
{
  "radio": {
    "enabled": false,
    "mode": "speaker_duplicate",
    "speakerVolume": 1.0,
    "latencyOffsetMs": 0,
    "hapticsEnabled": false,
    "language": "auto",
    "runtimeMuteExperimental": false,
    "fallbackToDuplicate": true
  }
}
```

---

# Acceptance Criteria

## Speaker Duplicate MVP

- Radio hook triggers controller speaker playback.
- Dialogue WAV plays through selected Audio Bridge output.
- Volume slider works.
- Latency offset works.
- No DSX required.
- No Steam Input required.
- Native haptics remain intact.
- No crashes if DualSense audio device is missing.

## Runtime Mute Experimental

- Original radio dialogue can be muted or suppressed.
- DualSense speaker playback still works.
- Subtitles remain intact.
- Timing remains acceptable.
- User can disable the feature if it causes issues.

---

# Important Rules

- Do not break existing audio event playback.
- Do not break native game haptics.
- Do not require DualSenseEnhancedFeedback.
- Do not require Steam Input.
- Do not modify game files unless user explicitly selects Repacked Silence mode.
- Treat Runtime Mute as experimental until proven stable.
- Prefer user-friendly toggle-based behavior.
