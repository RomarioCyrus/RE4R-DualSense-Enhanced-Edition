# Enhanced Haptics (channels 3/4 via audio bridge) — SHIPPED IN v1.0, READY FOR RELEASE (2026-07-13)

Status doc, kept as a historical/reference record. Read this before touching
the audio bridge, the trigger transport, `wwise_audio_router.lua`, or before
interpreting "Capcom native haptics stopped working" as a regression from
something else.

**FINAL STATE 2026-07-13 (supersedes the naming/scope of the 2026-07-11
decision below): feature is complete and confirmed release-ready.** What
ships:
- Consolidated "Enhanced Haptics" UI section (was "Footstep Haptics
  (opt-in)"), always visible (not `RELEASE_BUILD`-gated) — one checkbox
  ("Enable Enhanced Haptics") still gates the whole feature.
- Covers footsteps plus companion pulses for parry, knife hits/finisher,
  dry fire, aim in/out, weapon draw, healing, and item pickup — matched by
  substring against event names via a single dispatch point in
  `audio_feedback.lua` (`COMPANION_HAPTIC_PATTERNS`), not per-entry wiring.
  `fatal_kick`/`reload_*` deliberately excluded — native Capcom haptics
  already cover those well.
- Footsteps and dry-fire/aim/draw/heal use real-audio-to-haptics (extracted
  game SFX, low-pass filtered) instead of synthesized tones — generated
  locally at install time (`generate_haptics.ps1`, copyright reasons, see
  Release Policy in `RELEASE_MANIFEST.md`), not shipped as static files.
  Parry keeps a boosted synthesized tone (native has zero parry vibration).
- **Continuous 0..1 intensity slider**, live-filtered in `HapticPlayer.cs`
  (single-pole low-pass, cutoff scales with intensity) — replaces the old
  3-preset (Softer/Normal/Harder) WAV-swap system entirely.
- **Per-category on/off toggles** (8 checkboxes, one per event category
  above) — `AUDIO.haptic_category_enabled`, persisted via `settings.lua`.
- **Footsteps are sprint-gated and intensity-capped**: only vibrate while
  actually sprinting (`player_movement.lua` polls `get_RequestRun()` on the
  player object; the underlying Wwise event otherwise fires even from idle
  weight-shift while standing still) and use a lower intensity ceiling
  (`AUDIO.FOOTSTEP_INTENSITY_SCALE = 0.35`) than every other category, to
  match how subtle PS5's own native footstep haptics are relative to
  combat/weapon feedback.
- `IPC.haptics_mode_enabled` still defaults `false` — user must check the
  box themselves, same as other optional features.
- `DualsenseAudioBridge.json`'s `HapticsEnabled` config default is `true`
  (`BridgeConfig.cs`) so the Lua checkbox is the *only* toggle a user needs.
  `HapticsEnabled=true` alone is inert (just constructs the `HapticPlayer`
  at bridge startup); real output still requires the Lua flag.

**RELEASE DECISION 2026-07-11 (supersedes every "dev-only, excluded from
v1.0" note below): user decided to ship footstep haptics in v1.0 as an
opt-in feature, default OFF, uniform across all surfaces.** This reverses
the 2026-07-06/07 standing decision referenced throughout the rest of this
doc — those notes are historical context for *why* it was excluded, not
current policy. Concretely:
- `DualSenseEnhanced.lua`: the "Footstep Haptics" UI section was pulled out
  of `draw_debug()` (which is entirely `RELEASE_BUILD`-gated) into its own
  `draw_footstep_haptics(IPC)`, called unconditionally so it's visible and
  usable in a release build. Renamed from "EXPERIMENTAL, not in v1.0" to
  "Footstep Haptics (opt-in)". **Superseded 2026-07-13**: this function was
  renamed again to `draw_enhanced_haptics(IPC)`, see FINAL STATE above.
- Per-surface intensity code (concrete/metal/soft volume buckets, the
  `ROUTER.current_surface` tracking) was removed before this ship — see the
  "Stage 3 v2" section below and `project-haptics-experiment` memory for
  the full research if picking it back up later. What ships is uniform
  volume, same as every other surface.
- `IPC.haptics_mode_enabled` still defaults `false` (`settings.lua`'s
  `reset_runtime_defaults()`) — user must check the box themselves, same as
  other optional features.
- `DualsenseAudioBridge.json`'s `HapticsEnabled` config default was flipped
  `false` → `true` (`BridgeConfig.cs`) so the Lua checkbox is the *only*
  toggle a user needs — previously this was a second, undocumented-to-users
  manual-JSON-edit gate. `HapticsEnabled=true` alone is inert (just
  constructs the `HapticPlayer` at bridge startup); real output still
  requires the Lua flag.

**RESOLVED 2026-07-11: the "RE4R write race" theory below was wrong.** Real
cause: `readDualsense.cpp`'s trigger-only output-suppression guard was also
unconditionally forcing `AllowMotorPowerLevel` off, so this duaLib fork
could never clear a stuck nonzero `Trigger`/`RumbleMotorPowerReduction`.
Fixed with `scePadSetMotorPowerReduction` + a `motorPowerEnabled` opt-in
flag; hardware-confirmed with a controlled A/B in real gameplay (fix
on/off/on via a new "Test Haptics" debug button). Full write-up: see the
"BREAKTHROUGH 2026-07-11" section at the top of the
`project-haptics-experiment` memory, and `docs/CHANGELOG.md`.

The 2026-07-07 stop reasoning and Stage 0-2 history below is preserved as-is
for context; its "blocked" framing for Stage 1's actual physical-vibration
question is superseded by the resolution above.

## Stage 3 v1: uniform footstep haptics wired and live-confirmed (2026-07-11)

`wwise_audio_router.lua`'s `event_map` now routes 33 distinct `postEvent`
event IDs (all sharing a `soundlib.SoundManager.postEvent` `a5` arg of
`326417514505`, captured via `sound_event_diag.lua` across concrete/wood/
grass/house sessions) to `handler = "play_footstep_haptic"`, sharing a new
`cooldown_group = "footstep"` field (added to `emit_mapped()`'s cooldown-key
logic) so whichever ID a given step happens to post, only one haptic pulse
fires per step. **Live-confirmed working** by the user after this change
(prior attempts wired only 2 IDs, which worked by luck on grass but produced
near-silence on wood).

Two dead ends hit along the way, kept here so they aren't retried:
- **Mapping the constant `a5=326417514505` tag directly** (instead of
  enumerating the 33 IDs) seemed like the obviously cleaner fix —
  `scan_args_for_mapped_event()` already checks every arg 1-7 against
  `event_map`, so a match at arg index 5 should work identically to the
  existing index-3 direct-ID matching every other route in this file uses.
  It did not: confirmed via a live `ROUTER.last_event`/`last_status` debug
  readout (added to `DualSenseEnhanced.lua`'s Footstep Haptics debug section)
  that it never matched during real running, across a full session. Root
  cause not found — reverted to per-ID enumeration, which is the same
  mechanism every other working route (knife, parry, etc.) already relies
  on. If revisiting this, instrument `event_id_from_raw`/
  `scan_args_for_mapped_event` directly rather than assuming index-5 behaves
  like index-3.
- **`sound_event_diag.lua` was freezing the game during capture windows.**
  Root cause: `append_line`/`append_event_line` did a synchronous
  open+write+close per *individual* logged event; the widened discovery
  patterns (added earlier the same day) pushed dozens of events/sec, enough
  disk I/O on the hook's calling thread to stutter/freeze. Fixed by
  buffering lines in memory and flushing once per ~15 `UpdateBehavior` ticks
  (plus forced flush on window-close). Also found `"update"` needed adding
  to `dynamic_hook_excluded_prefixes` — `soundlib.SoundManager`'s internal
  per-frame pump methods (`updateEndOfEvent` etc.) matched the `state`/
  `event` discovery patterns and were firing every frame regardless of
  movement, saturating the event-count cap within 1-2 seconds. **Caveat for
  future debugging**: `sdk.hook` installations are NOT removed by Reset
  Scripts / the Lua `_G` wipe — each hook callback's `is_current_generation()`
  check is what makes stale-generation hooks inert, not hook removal. A
  pattern/exclusion-list change only takes effect for hooks installed by the
  *next* `install_hooks()` call, so Reset Scripts (or a full game restart)
  is required after deploying such a change, not just saving the file.

Also fixed in the same investigation: `DualSenseEnhancedTransport.exe`'s
watcher only reissued `scePadSetVibrationMode`/`scePadSetMotorPowerReduction`
when the Lua-side command file's `Sequence` changed. Since
`IPC.haptics_mode_enabled` doesn't change across a native-haptics event, RE4R
flipping the controller back to compatible-rumble mode at the hardware level
(bypassing duaLib) was never caught or corrected — footstep haptics would
work, then go dead the instant native haptics fired, until something else
(e.g. Reset Scripts causing the flag to toggle) forced a `Sequence` bump.
Fixed with a periodic reassert (every 500ms while haptics mode is held,
independent of command-file changes) in the watcher's main loop.

**Not yet done**: per-surface *variation* (different intensity/pattern by
ground type) — current implementation is uniform footstep haptics on all
surfaces. The secondary `a5=326417514497`-tagged event family, earlier
hypothesized as surface-specific "textural debris" content, was also
observed firing on house/wood captures, not just grass — that hypothesis
needs re-verification with clean single-surface captures (metal and water
are still completely untested) before building surface-intensity variation
on top of it.

## Stage 3 scope narrowed: Leon-only, reverted from 33 IDs to 3 (2026-07-11, later same day)

The 33-ID enumeration above fixed wood-floor coverage but broke correctness:
live-tested in Mercenaries, haptics fired from **NPC footsteps** while the
player stood still — the broader ID set is posted by any footstep-capable
actor, not just Leon.

Tried gating on postEvent's `a1` argument as a per-actor sound-object
handle, learned opportunistically from any confirmed-player-only route
(weapon fire/knife/UI, all exclusively player-sourced in this single-player
game). This also failed: a fresh capture showed `a1` is **identical across
every postEvent call in a session**, regardless of actor or event type — not
an object handle at all (likely the shared SoundManager singleton). None of
the 7 postEvent args (a1-a7) reliably identify the emitting actor.

**Reverted to the original narrow 3-ID set** (`1528453721`/`1332518089`/
`2453452847`), confirmed Leon-only with no NPC bleed. User's explicit
decision: correctness beats surface coverage — this set may miss some
surfaces (e.g. wood, per the earlier wood-silence report) but never fires
from another actor. The `ROUTER.player_sound_object_id` gating code was
removed entirely (dead weight, didn't work).

**Stage 3 is DONE at this scope**: uniform, Leon-only footstep haptics. Full
per-surface variation and full-surface coverage remain unimplemented; if
revisited, per-actor filtering needs a source of truth outside Wwise
postEvent args (e.g. the player's own CharacterController velocity/movement
state via REFramework reflection) — enumerating more event IDs will not fix
this, since the actor-ambiguity problem is inherent to the event IDs
themselves, not to which ones are listed.

## Release status: SHIPPING in v1.0 as opt-in (reverses the 2026-07-06/07 decision below)

**Superseded 2026-07-11** — see the top of this doc for the current release
decision. The reasoning below is preserved for history: it documents why the
feature was originally excluded and how the code stayed inert while doing
so, which is exactly the mechanism that was deliberately undone to ship it
(the UI was moved outside the `RELEASE_BUILD` gate, and the bridge's
`HapticsEnabled` config default flipped to `true`).

Original 2026-07-06/07 reasoning, no longer current policy: this feature
must NOT ship in v1.0. Given how `tools/sync_to_release.ps1` actually works:
it copies `dualib_trigger_ipc.lua`, `settings.lua`, `audio_feedback.lua`,
and `wwise_audio_router.lua` by necessity (they carry real v1.0 content
alongside this experiment's additions — the whole files can't be excluded).
Safety instead came from:
- the sync script auto-flips `RELEASE_BUILD` to `true` when copying
  `DualSenseEnhanced.lua`, and the debug-only checkbox that was the only way
  to enable `IPC.haptics_mode_enabled` lived entirely inside
  `if not RELEASE_BUILD` in `draw_debug()` — structurally unreachable in a
  release build (**no longer true as of 2026-07-11** — moved to its own
  `draw_footstep_haptics()`, called unconditionally);
- `IPC.haptics_mode_enabled` and the bridge's `HapticsEnabled` config both
  defaulted `false` (**`HapticsEnabled` now defaults `true` as of
  2026-07-11** — `IPC.haptics_mode_enabled` still defaults `false`, so a
  fresh install is still silent until the user opts in).

The rebuilt `build_out/duaLib.dll` (operator== fix, hash `0C355C4B...`) was
already fine to ship as-is regardless of this decision — the fix only
affects fields nothing in v1.0 ever sets.

## Goal

Play a synthesized footstep thump on the DualSense actuators (channels 3/4
of the 4-channel WASAPI endpoint) on Leon's footsteps, driven by Wwise
event `1528453721` (`ch_cha0-18156-event`, bank `ch_cha0.bnk`) through the
existing `wwise_audio_router.lua -> audio_events.json -> bridge` pipeline.

## Why this can work now (vs. the 2025 DualSenseHapticsProbe "defer")

The probe proved channels 3/4 are physically silent unless something holds
the controller in audio-haptics vibration mode; one-shot HID selections
failed while RE4R owned the report. Since then, the duaLib watcher
(`DualSenseEnhancedTransport.exe`) became a persistent report owner, and
the duaLib fork already exports `scePadSetVibrationMode` (mode 1 = haptics,
mode 2 = compatible rumble). Same discovery class as the lightbar
`AllowLedColor` fix. The initial 2026-07-05 build (`0BF8351F...`) already
exported the function with no rebuild — but a 2026-07-06 physical retest
found the mode never reliably released back to rumble, tracked to a
missing comparison in `SetStateData::operator==` (see Stage 0 below for
the fix). **A duaLib.dll rebuild ended up being required** after all,
current confirmed hash `0C355C4B...`.

## Go/no-go question (Stage 1) — REVISED 2026-07-07: Capcom haptics survive, but so far our OWN actuator output does not

The original working hypothesis was that audio-haptics and compatible-rumble
might be mutually exclusive firmware modes, silencing **Capcom's** native
haptics while held. That half is confirmed true and safe: Capcom's native
haptics, lightbar, adaptive triggers, Mic LED, gyro, and controller-speaker
audio all kept working normally with audio-haptics mode held for a whole
gameplay session (Stage 1 test, 2026-07-07).

**However, Stage 1 never actually re-confirmed that our own WASAPI
channels-3/4 actuator content (the whole point of this experiment) survives
alongside Capcom's haptics** — it only checked that Capcom's side kept
working. Stage 2 live testing (2026-07-07) found it does not: the
already-hardware-confirmed 80 Hz test tone (`--test-haptic both`) produces
**no felt vibration at all** while RE4R is running, in every condition
tested (active combat, "away from keyboard" idle, standing completely
still) — even though `trigger_watcher.log` continuously shows
`Haptics=haptics` applied. The identical test **still works** (vibration
confirmed) when RE4R is fully closed and only the standalone transport
holds the mode — ruling out a hardware/driver/environment regression.

**Working theory**: RE4R likely still sends its own native rumble/haptic
commands to the controller through the standard OS controller-vibration API
(XInput or equivalent) continuously or near-continuously (many engines call
a vibration-set API every frame even with zero values, as a
connection-keepalive side effect) — a write path our duaLib process cannot
see or arbitrate. Every such RE4R-originated write is, by construction,
issued in compatible-rumble mode (that's the only mode the standard OS
vibration API knows about), so it very plausibly forces the physical
firmware mode back to rumble immediately after our own background thread
reasserts audio-haptics, over and over, faster than the WASAPI-routed audio
content can ever be rendered as felt vibration. Our own bookkeeping never
notices because it only diffs against its own last-written state, not
against whatever RE4R itself just wrote. This exact class of risk was
already flagged in `docs/AGENTS.md`/`docs/MEMORY.md` before this project
started emitting haptics at all ("this process may race RE4R's complete HID
output reports"; "DualSense output is a compound report... requires state
merging or one report owner") — it has now materialized concretely, for
vibration-mode selection specifically, not (yet) for any of the other
report sections this project owns (lightbar/indicators/mic/triggers all
continue to work fine because Capcom's engine apparently does not also
independently rewrite those specific sections the way it evidently does for
compatible-rumble/vibration).

**Not yet resolved.** Possible directions if this is pursued further:
addressing race like this would need to either (a) intercept/suppress RE4R's
own native vibration-API calls while our haptics mode is meant to be held
(losing Capcom's native rumble feel while it's active — a real tradeoff, and
technically its own R&D effort), or (b) find some way to make our mode
selection durably "win" (unclear if even possible without (a)), or (c)
accept that this specific coexistence is not achievable and the feature
stops here. This is a decision for the project owner, not something to keep
patching blindly in Lua.

## What changed (all opt-in, default OFF)

| Artifact | Change |
|---|---|
| `speaker/DualSenseEnhancedTransport` | `DuaLibBackend` TryLoads `scePadSetVibrationMode` (`SupportsVibrationMode`/`SetVibrationMode`); command file gained optional `Haptics: {"Mode": 1|2}` field (absent = restore rumble); `--test-haptics-mode --duration <ms>` stand command; `Reset()` restores rumble mode if haptics was selected |
| `speaker/DualsenseAudioBridge` | New `HapticPlayer.cs`: persistent shared-mode 4-channel WASAPI output (WAVEFORMATEXTENSIBLE quad, mixer, channels 1/2 silent, 3 = left actuator, 4 = right, alternating L/R per event); `haptics_enabled` (default **false**) + `haptics_volume` (0.6) in `DualsenseAudioBridge.json`; events prefixed `haptic_` route to actuators (dropped silently when disabled); `--test-haptic [left|right|both]` stand command (runs before the single-instance mutex) |
| `tools/generate_haptic_footstep.ps1` | Generates `haptic_footstep.wav` (48 kHz float stereo, 110→60 Hz sweep, 100 ms, exp decay) into `src/.../sounds/` |
| `src/.../sounds/haptic_footstep.wav` | Deployed to game sounds dir (sha256 `9E7A6159...`, verified) |
| `src/.../dualib_trigger_ipc.lua` | `IPC.haptics_mode_enabled` (renamed 2026-07-07 from the Stage 1 diagnostic `haptics_test_mode_enabled`; default off) emits `haptics: {"mode":1}` in every IPC write when true, omitted (→ rumble restore) otherwise; `IPC.reset()` always forces rumble regardless of the flag. Now the single source of truth read by both this module and `audio_feedback.lua` |
| `src/.../settings.lua` | `IPC.haptics_mode_enabled` wired into `snapshot()`/`apply()`'s `dualib` block (persists across `Reset Scripts`/restart) and explicitly forced `false` in `reset_runtime_defaults()` so the Immersive-preset-style reset never re-enables it |
| `src/DualSenseEnhanced.lua` | New `draw_debug()` section "Footstep Haptics (EXPERIMENTAL, not in v1.0)" — a checkbox toggling `IPC.haptics_mode_enabled`, only reachable when `not RELEASE_BUILD` (same gate as the existing diagnostic tools, so it's structurally impossible to ship in v1.0 regardless of `show_debug_tools`); a `draw_status()` line under the same `RELEASE_BUILD` gate shows current on/off state |
| `src/.../audio_feedback.lua` | `AUDIO.play_footstep_haptic()` — same gated-wrapper pattern as `play_knife_hit`/`play_qte`, reads `_G.DuaLibTriggerIpc.haptics_mode_enabled` (no separate flag) and calls `emit("haptic_footstep")` |
| `src/.../wwise_audio_router.lua` | New `event_map[1528453721]` entry (`handler = "play_footstep_haptic"`, `cooldown = 0.20`) appended after the existing knife entries; purely additive, this ID had no prior entry in the table |

Latency note: `HapticPlayer.cs` already keeps one persistent `WasapiOut` +
`MixingSampleProvider` open (opened once via `EnsureOutputLocked()`); each
`Play()`/`PlayAlternating()` call only adds a mixer input, no per-event
device reopen. The earlier concern about a "one-shot dispatch" redesign for
footstep cadence did not apply once re-checked — no C# changes were needed
for Stage 2.

## Stage plan / current status

- **Stage 0 (stand, no game) — PASSED, hardware-confirmed 2026-07-06.**
  Both exes deployed to the game folder (sha256-verified: transport
  `85908ABB...`, bridge `F0F23478...`). With
  `DualSenseEnhancedTransport.exe --test-haptics-mode
  --acknowledge-output-conflict` holding audio-haptics mode, the bridge's
  `--test-haptic both` 80 Hz tone on channels 3/4 produced **physical
  actuator vibration** on a USB DualSense Edge (DSX closed, game closed).
  This confirms the core hypothesis: the duaLib watcher holding haptics
  mode unblocks the WASAPI channels-3/4 path that the 2025 probe found
  silent. Note: `DualsenseAudioBridge.exe` is WinExe — run stand tests via
  `Start-Process -Wait -RedirectStandardOutput` to see `[Haptic]` log
  lines; a plain console invocation returns immediately with no output.
  Two manual `.bat` helpers exist for this: `speaker/HAPTICS_TEST_A_HOLD_MODE.bat`
  and `speaker/HAPTICS_TEST_B_PLAY_TONE.bat` (deployed copies live directly
  in the game's `DualSenseEnhanced` data folder next to both exes).

  **Root-cause bug found and fixed (2026-07-06)**: the first control-tone
  check came back still vibrating. Root cause was in the duaLib fork, not
  the C#: `dataStructures.h`'s `SetStateData::operator==` did not compare
  `UseRumbleNotHaptics`/`EnableRumbleEmulation`/`EnableImprovedRumbleEmulation`
  — the exact fields `scePadSetVibrationMode` sets. `readDualsense.cpp` only
  `hid_write`s when the current output state differs from the last-written
  one; a vibration-mode-only change with no other field changing at the same
  moment never registered as "different," so the switch back to rumble was
  silently dropped and the controller stayed in audio-haptics mode
  indefinitely (the initial switch INTO haptics mode did land, because it
  rides the forced first-write-after-connect via `wasDisconnected`). Fixed
  by adding those three fields to the comparison and rebuilding
  `build_out/duaLib.dll` (new confirmed hash
  `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`,
  see `speaker/DualSenseEnhancedTransport/README.md`). Build command:
  `x86_64-w64-mingw32-clang++.exe -std=c++20 -shared -static -DDUALIB_EXPORTS
  -I <duaLib include> -I <hidapi include> <6 duaLib .cpp files>
  <full path to>\libhidapi.dll.a -lsetupapi -lwinmm -lole32 -lhid -o duaLib.dll`
  (linking `libhidapi.dll.a` via `-l` failed to resolve; the full path
  worked). `hidapi.dll` must be deployed alongside the rebuilt DLL (dynamic
  dependency, not statically linked in). Regression-tested against
  `--test-l2`/`--test-r2`/`--test-lightbar`/`--test-mic-light`/
  `--test-indicators` (all ran clean) before redeploying, then user
  hardware-confirmed on 2026-07-06: haptics-mode-ON vibrates, and the
  control condition after mode restore is now silent.
- **Stage 1 (native game go/no-go) — PARTIALLY PASSED, revised
  2026-07-07.** Capcom's own native haptics, lightbar, adaptive triggers,
  Mic LED, gyro, and controller-speaker audio all continued working
  normally with audio-haptics mode held for a whole gameplay session. That
  part is a genuine, confirmed GO. What Stage 1 did **not** actually
  re-verify: whether our own channels-3/4 actuator content survives
  alongside Capcom's haptics — see the revised go/no-go section above for
  why that turned out to matter.
- **Stage 2 (full footstep pipeline) — architecture implemented and
  deployed 2026-07-07; live playtest found the actuator content itself
  does not produce felt vibration while RE4R is running.** The Lua/C#
  pipeline is confirmed fully correct end-to-end: `haptic_footstep` events
  are written to `audio_events.json` on a plausible footstep cadence
  (confirmed via direct log inspection, ~0.3-1s apart), the bridge's
  `haptics_enabled: true` config is picked up (confirmed via its startup
  banner), the transport continuously applies `Haptics=haptics`
  (confirmed via `trigger_watcher.log`), and `HapticPlayer` opens the
  4-channel endpoint and dispatches without error (confirmed via bridge
  log). None of that is in question. What fails is the very last, physical
  step: even the already-hardware-confirmed 80 Hz `--test-haptic` tone
  produces **no felt vibration** while RE4R is running (tested during
  active combat, while AFK, and while standing completely still), yet the
  identical tone **does** work the moment RE4R is fully closed and only the
  standalone transport holds the mode. See the revised go/no-go section
  above for the root-cause theory (RE4R's own native vibration-API writes
  likely racing our mode selection).

  Single source-of-truth flag `IPC.haptics_mode_enabled` (renamed from the
  Stage 1 diagnostic) drives both the watcher's mode-hold
  (`dualib_trigger_ipc.lua`) and the Wwise footstep route
  (`wwise_audio_router.lua` → `audio_feedback.lua`'s
  `AUDIO.play_footstep_haptic()`), persisted via `settings.lua`, toggled
  from a debug-only checkbox in `DualSenseEnhanced.lua`'s `draw_debug()`
  (structurally excluded from v1.0 by the existing `RELEASE_BUILD` gate,
  same mechanism as `monitor.lua`/`capcom_haptics_diag.lua`). All 5 changed
  Lua files deployed and sha256-verified; `tools/verify_deploy.ps1` shows no
  drift on any of them (unrelated MISSING/MISMATCH entries belong to a
  concurrent knife-audio session's new WAV files and an already
  hash-confirmed transport exe timestamp).

  Latency was re-checked and is not a concern: `HapticPlayer.cs` already
  holds one persistent `WasapiOut`/`MixingSampleProvider` (opened once via
  `EnsureOutputLocked()`); each event only adds a mixer input, no per-event
  device reopen. No C# changes were needed there — the blocker is not in
  this project's own code.

  **Status: STOPPED 2026-07-07.** Blocked on the RE4R-write-race theory
  above; project owner decided this is not a priority to pursue further
  right now (not a v1.0 concern either way). Do not resume without an
  explicit new instruction — the architecture and findings stay in the
  codebase/docs as reference, but no further testing/tuning is planned.
- **Stage 3 (per-surface WEMs from `ch_cha0.bnk`)** — moot while Stage 2 is
  stopped; would only matter if Stage 2's actuator-content blocker gets
  resolved later. Confirmed during Stage 2 research: no working
  Lua-readable getter for the `ch_ground_attribute` surface switch was
  found (`sound_event_diag.lua`'s `interesting_field_patterns` only
  pattern-matches field *names* for hook exploration, not a real state
  getter) — per-surface variation needs new hook-exploration work first,
  not just wiring.

## Multi-agent rules while this is in flight

- Everything is default-off; deploying these binaries changes no behavior
  until `haptics_enabled` (bridge config) / `IPC.haptics_mode_enabled`
  (Lua, persisted, toggled from the debug-only UI checkbox) are turned on.
- Do not kill/restart the deployed `DualsenseAudioBridge.exe` while
  another capture/test session is live — it is shared and single-instance.
- `duaLib.dll` **was** rebuilt (2026-07-06, operator== fix) — current
  confirmed hash is `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`,
  superseding `0BF8351F...` everywhere it's referenced
  (`docs/AGENTS.md`/`speaker/BUILD.md`/`speaker/DualSenseEnhancedTransport/README.md`/
  `docs/DUALIB_HID_BRANCH.md` are already updated). If you're about to
  rebuild it again for an unrelated reason, diff against the current
  `dataStructures.h` first so you don't silently drop this fix.
- The `audio_events.json` NDJSON format is unchanged; haptic events are
  ordinary events whose name starts with `haptic_`.
- `IPC.haptics_mode_enabled` now persists through `settings.lua`, so
  finding it `true` in a live session is not necessarily a leftover bug
  the way the old Stage 1 literal-flip flag was — check whether the
  debug-only checkbox is intentionally on (via `Status`'s "Footstep
  Haptics (dev)" line, only visible when `not RELEASE_BUILD`) before
  assuming it needs correcting.
