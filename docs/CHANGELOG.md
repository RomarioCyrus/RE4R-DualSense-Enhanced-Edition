# CHANGELOG.md

## Unreleased

### Fix: deploy verifier uses the selected Audio Bridge release artifact (2026-07-14)

- `tools/verify_deploy.ps1` now compares the installed
  `DualsenseAudioBridge.exe` against `dist/native-autostart`, matching
  `tools/sync_to_release.ps1` and the bridge README.
- Removed the false mismatch against the older `publish-fixed` output. The
  installed and selected release binaries already matched at SHA-256
  `3C50985329F7D67907CC0D14A069114FB49EBCE798EE47CB8113176ABDD62D62`.

### Feature: per-category Enhanced Haptics intensity controls (2026-07-14)

- The Enhanced Haptics UI keeps the global intensity slider and adds three
  clear strength levels beside every category: `1 Soft (50%)`,
  `2 Normal (100%)`, and `3 Strong (150%)` for footsteps, parry, knife, dry
  fire, aim, draw, healing, and pickup.
- Effective intensity is `global x category`; the existing footstep balance
  also retains its `0.35` scale. All category multipliers default to `1.0`, so
  existing behavior and older settings files remain unchanged.
- Category enable checkboxes remain the true off switch. This is intentional:
  the bridge's intensity value `0` still uses its minimum filter/gain profile
  and is not guaranteed to be silent.
- Category levels are persisted, normalized to one of the three supported
  values during load, restored to Normal by Reset Defaults, and applied only
  to their matching companion event.
- Polished the panel around simple preset controls: global strength remains
  `0-100%`, categories use levels `1-3`, with Enable All, Disable All, and
  Reset Levels to Normal buttons plus concise guidance about light and Off.
- Fixed the old `Test Haptics` button silently doing nothing while stationary:
  it now plays the packaged parry pulse directly instead of calling the
  sprint-gated footstep route.
- Completed a broader professional UI consistency pass: moved Enhanced
  Haptics before Gyro/Advanced, renamed Core Features to Quick Controls,
  explicitly documented mirrored switches, and added Enhanced Haptics to the
  quick group.
- Replaced raw float presentation with user-facing percentages for lightbar
  brightness, speaker volume, global/per-class trigger strength, and global
  haptic strength. Lightbar and audio output buttons now visibly mark the
  selected mode.
- Removed the clickable no-op Custom preset button, hard-coded Native Haptics
  status, release-facing channel/source-doc jargon, redundant percentage text,
  and developer event/status lines from release audio controls.
- Category rows now show the current Soft/Normal/Strong name, while the haptic
  test only appears when its prerequisites are enabled and reports its result.
  Top-level separators were reduced so collapsible sections form the visual
  hierarchy; Advanced remains last before dev-only Debug Tools.
- Implementation, game deployment, and release staging are complete, but the
  new spacing and narrow-window behavior are not yet visually confirmed in-game.

### Release: creator-owned healing audio and haptics are now packaged (2026-07-14)

- Added a strict 29-file release WAV allowlist containing the mod author's 11
  AI-generated healing cues, their 11 haptic companions, and seven original
  synthesized haptic tones used for footsteps, parry, knife impacts, and
  pickups.
- Added the previously omitted active `haptic_parry.wav` to the distributable
  source exceptions and release pipeline.
- Release sync and staging still reject `heal_spray.wav`, extracted
  knife/weapon/UI WAVs, and every `haptic_*_real.wav` derivative of Capcom
  audio. The development sound folder is never copied by wildcard.
- Shipping `heal_herb.wav` resolves the first-run haptic generator's missing
  input while preserving local extraction for all Capcom-owned game audio.

### Fix: sound setup no longer fails when Sentinel Nine DLC is absent (2026-07-14)

- `setup_sounds.ps1` now treats the exact Sentinel Nine Wwise bank
  (`ch_wp6000_media.sbnk.1.x64`) as optional when
  `dlc/re_dlc_stm_2109308.pak` is not installed.
- Base-game users verify 676 required WAVs and skip 33 Sentinel Nine outputs;
  users with the DLC still verify the full 709-file manifest.
- Missing or broken non-DLC banks remain hard errors. A present DLC pak also
  keeps all Sentinel Nine outputs mandatory, so real DLC extraction failures
  are not hidden.
- Scratch validation passed against real game archives in both modes:
  base-only `676 extracted / 0 errors / 33 optional skipped / 676 present`,
  followed by DLC-present `709 extracted / 0 errors / 709 present`.

### Documentation: public v1.0 feature/readme sync (2026-07-14)

- Updated the package README, GitHub README draft, and Nexus page copy for the
  confirmed native speaker initialization, per-item healing speaker/haptic
  cues, and release-ready Enhanced Haptics behavior (sprint-only footsteps,
  continuous intensity, per-category toggles).
- Updated the release/extractor docs to distinguish the current configured
  `709` sounds / `26` banks from the last fully validated `688/25` scratch run;
  the expanded manifest was then validated in both base-only (`676/676`, 33
  optional skipped) and DLC-present (`709/709`) modes with zero errors.
- Retired stale documentation that still described per-item healing as an
  idea, the endpoint picker as a Previous/Next carousel, or DSX UDP as the
  supported v1.0 output architecture.

### Feature: Enhanced Haptics consolidated -- companion haptics, real-audio conversion, live intensity slider, per-category toggles, sprint-gated footsteps (2026-07-12/13)

Enhanced Haptics now covers footsteps plus parry, knife hits/finisher, dry
fire, aim in/out, weapon draw, healing, and item pickup -- a single
centralized dispatch point in `audio_feedback.lua` pattern-matches Wwise
event names against `COMPANION_HAPTIC_PATTERNS` (each tagged with a
`category`), so no per-entry wiring was needed across the ~150 existing
weapon event mappings. `fatal_kick` and `reload_*` were deliberately left
off this list -- Capcom's own native haptics already cover them well, and a
companion pulse there was redundant/muddying. A priority-suppression system
(`footstep_suppressed_until`) briefly mutes footstep haptics while a more
important companion pulse is landing, so footsteps don't drown out combat
feedback while running.

Footsteps, dry fire, aim in/out, weapon draw, and healing switched from
synthesized gated-sine tones to **real-audio-to-haptics**: the actual game
SFX (extracted via `tools/extract_sounds/`), low-pass filtered/trimmed/
normalized (`tools/audio_to_haptic.py`), live-confirmed clearly better than
synthesis ("реальный звук однозначно лучше"). Parry keeps the boosted
synthesized tone (native haptics have zero vibration on parry, so a felt
pulse there is the actual gap being filled). Since the low-pass-filtered
result is still a derivative of extracted Capcom audio, these `haptic_*_real.wav`
files are **not shipped** -- they're generated locally by
`tools/extract_sounds/generate_haptics.ps1` (pure PowerShell/.NET port of
the Python reference, byte-identical output, no Python dependency), wired
into `setup_sounds.bat`'s existing first-run extraction flow. The 3
synthesized `haptic_footstep*.wav` tones are 100% original and still ship
as static assets.

The old 3-preset (Softer/Normal/Harder) intensity selector was replaced with
a true continuous 0..1 slider. Presets were discrete WAV swaps; the slider
value is now sent to `DualsenseAudioBridge.exe` as a `haptic_intensity`
field on haptic-prefixed events, and `HapticPlayer.cs`'s
`QuadRouteSampleProvider` applies it *live* via a single-pole RC low-pass
filter (cutoff 130-380Hz) plus a gain multiplier -- true continuous control
instead of picking between pre-baked variants, since felt intensity on the
DualSense's voice-coil actuators is driven mainly by frequency, not gain.
Each of the 8 haptic categories also got an individual on/off toggle
(`AUDIO.haptic_category_enabled`), surfaced in a consolidated "Enhanced
Haptics" UI section (was scattered across a "Footstep Haptics" section plus
ad-hoc debug toggles).

Footsteps specifically needed two more passes after the slider landed:
- **Intensity ceiling**: on PS5, native footstep haptics stay noticeably
  weaker than combat/weapon feedback. Our footsteps used the same slider
  range as everything else, so slider=1 hit far harder than the PS5
  reference (slider=0 was the closest match). Footstep events now send
  `AUDIO.haptic_intensity * AUDIO.FOOTSTEP_INTENSITY_SCALE` (0.35) instead of
  the raw slider value, so the slider's top end stays subtle for footsteps
  specifically while parry/impact/etc keep full range.
- **Sprint-only gating**: PS5's footstep haptics only fire while sprinting,
  which is a big part of why they don't read as constant background noise.
  A first attempt widened the footstep `cooldown_group` window (0.20s ->
  0.35s) to thin out walking via cadence alone -- reverted, since it doesn't
  distinguish walk/run and didn't address the real bug: the footstep Wwise
  event was confirmed (via new `movement_diag.lua` dev tool) to also fire
  from idle weight-shift while standing completely still. New
  `player_movement.lua` polls `get_RequestRun()` on the player object once
  every 2 frames (cached after first successful resolution against a list of
  candidate objects) and exposes `PlayerMovement.is_running`;
  `play_footstep_haptic()` now returns early unless it's true. Wwise event
  args carry no reliable per-actor or velocity signal (documented dead ends
  in `wwise_audio_router.lua`), so this required an actual engine-level
  reflection hook rather than anything derivable from the audio event
  stream.

### Feature: footstep haptics ships in v1.0, opt-in, default off, 3 intensity presets (2026-07-11)

Footstep haptics (felt vibration pulse on every step via the DualSense's
actuator channels) now ships in the v1.0 release as an opt-in feature —
reverses the earlier "dev-only, excluded from v1.0" decision. Off by
default; enable via the "Footstep Haptics (opt-in)" section in the mod's
settings ("Hold audio-haptics mode" checkbox). Uniform across all surfaces
— a per-surface variation (different feel for concrete vs. grass vs. metal,
etc.) was prototyped but removed before this release; see
`docs/HAPTICS_FOOTSTEPS_TASK.md` and the `project-haptics-experiment`
memory if picking that back up later.

Also added a 3-way intensity preset (Softer/Normal/Harder). DualSense's
actuators are voice-coil motors, so felt intensity is driven mainly by
waveform *frequency*, not playback volume — an initial volume-multiplier
version was barely perceptible. Each preset instead plays a distinct
synthesized low-frequency gated-sine WAV (90Hz/40Hz/20Hz), live-confirmed
to feel clearly different.

### Research: footstep haptics live-confirmed working (Stage 3 v1), transport reassert fix, sound_event_diag freeze fix (2026-07-11)

`wwise_audio_router.lua` now routes 33 distinct footstep `postEvent` IDs
(sharing a common `a5` Wwise arg, captured via `sound_event_diag.lua`) to the
existing `play_footstep_haptic()` handler, sharing a new `cooldown_group`
field so any of the 33 IDs firing for one physical step only triggers one
haptic pulse. Live-confirmed by the user after this change; earlier attempts
covered only 2-3 IDs and missed most steps on some surfaces (esp. wood).

`DualSenseEnhancedTransport.exe --watch` now periodically reasserts
`scePadSetVibrationMode`/`scePadSetMotorPowerReduction` every 500ms while
audio-haptics mode is held, instead of only on command-file change — RE4R's
own native haptics were silently reverting the controller to compatible-
rumble mode at the hardware level, which the watcher never noticed or
corrected because the Lua-side "hold haptics mode" flag itself never changed.

`sound_event_diag.lua` was doing synchronous per-event file I/O
(open+write+close per logged line), which under widened discovery patterns
was enough disk I/O on the hook thread to freeze the game during capture
windows. Fixed with in-memory buffering + periodic flush. Also excluded
`soundlib.SoundManager`'s internal per-frame `update*` pump methods from the
discovery patterns (they were saturating the event-count cap in ~1-2s).

Full write-up: `docs/HAPTICS_FOOTSTEPS_TASK.md` (Stage 3 v1 section) and the
`project-haptics-experiment` memory. Still opt-in, dev-only, excluded from
v1.0.

### Research: footstep-haptics "RE4R write race" blocker resolved — real cause found (2026-07-11)

Reopens the experiment stopped 2026-07-07 (`docs/HAPTICS_FOOTSTEPS_TASK.md`).
The suspected "RE4R writes competing HID output, racing duaLib" theory was
never actually verified and turned out to be wrong. Found while fixing the
native-speaker-audio bug the same day: the same trigger-only
output-suppression guard in `readDualsense.cpp` was also unconditionally
forcing `AllowMotorPowerLevel` off on every write, so this duaLib fork could
never explicitly clear a stuck nonzero `Trigger`/`RumbleMotorPowerReduction`
register — channels-3/4 content played correctly at the WASAPI/USB level
but could arrive at the motors already turned down, independent of anything
RE4R does in real time.

Added `scePadSetMotorPowerReduction(handle, triggerReduction,
rumbleReduction)` (RE4R-fork-only duaLib export) + a `motorPowerEnabled`
opt-in flag (same pattern as the speaker fix's `audioControlEnabled`).
Wired into `--watch`'s command loop: switching into audio-haptics mode now
also explicitly clears the reduction to 0. New `duaLib.dll` hash
`B16261C95AB1849D1EAD669CA215D03054EEF05E272E1F2EC822A4CB418E02FE`
(supersedes the same day's `63B4B3A8...`).

Hardware-confirmed with a controlled A/B in real RE4R gameplay, not just
correlation: a new "Test Haptics" debug button (`DualSenseEnhanced.lua`)
gives an instant test independent of footstep-walk detection timing. With
the fix active: felt real vibration. Rebuilt with the fix temporarily
disabled, same button, nothing else changed: no vibration. Re-enabled: felt
vibration again.

Still opt-in, dev-only, excluded from v1.0 per the standing 2026-07-06/07
decisions — this unblocks *continuing* the experiment (e.g. Stage 3
per-surface variation), it does not change the release-inclusion decision.

### Feature: native DualSense speaker audio, no DSX/DualSenseY required (2026-07-11)

The controller's built-in speaker now works over a standard USB connection
with no third-party software installed — previously the mod's WAV/haptic
audio pipeline opened the DualSense's WASAPI endpoint fine but produced no
audible speaker output without DSX or a free alternative like DualSenseY-v2
running alongside it.

Root cause, found via side-by-side Wireshark/USBPcap capture of a working
DualSenseY-v2 session against our own silent attempts: `readDualsense.cpp`
has a defensive block (written earlier for an unrelated feature — protecting
the experimental adaptive-trigger transport's trigger-only writes from
accidentally rerouting the Windows speaker endpoint) that unconditionally
force-cleared `AllowSpeakerVolume`/`AllowAudioControl`/`AllowHeadphoneVolume`/
`AllowMicVolume`/`AllowAudioMute` on *every* output-report write. This ran
immediately after the correct diff-check a few lines above had already
computed `Allow*=true` in response to `scePadSetAudioOutPath`/
`scePadSetVolumeGain` — so the new volume/path byte always reached the
controller correctly, but the "please apply this" flag was always stripped
before send, and firmware silently ignored it. Every earlier attempt at this
investigation (volume range, channel mapping, continuous re-apply,
vibration-mode wake, 16-bit PCM, exclusive-mode WASAPI, value jittering) was
chasing symptoms of this one guard.

Fixed with an `audioControlEnabled` opt-in flag (same pattern as the existing
`playerIndicatorsEnabled`/`micLightEnabled`/`lightBarOverrideEnabled`):
`scePadSetAudioOutPath`/`scePadSetVolumeGain` now set it, and the suppression
guard only clears those 5 Allow flags when it's *not* set, otherwise
preserving whatever the diff-check computed. `duaLib.dll` rebuilt, new
confirmed hash `63B4B3A8ED04A1C55C054DDF99FBAB8D1A3C263E27B18975CF96173DDEB61066`
(supersedes `0C355C4B...`; see `speaker/BUILD.md`,
`speaker/DualSenseEnhancedTransport/README.md`, `docs/DUALIB_HID_BRANCH.md`).
`DualsenseAudioBridge.exe` now runs a short-lived speaker-init probe as soon
as it starts (independent of the game-campaign-ready gate the trigger/gyro
transport waits for), so the speaker route is live in menus and loading
screens too, not just once a save is active — the route is a one-shot write
that survives process exit and even a full Windows restart, so this doesn't
need to stay running. The speaker volume UI slider (`DualSenseEnhanced.lua`)
now goes to 200% (previously hard-capped at 100%) since the controller's
internal speaker is quiet even at full native gain.

Hardware-confirmed on a genuinely fresh USB replug (ruling out residual
state from a prior session) on both a standard DualSense and a DualSense
Edge over `ds5dongle`. Regression-tested clean against triggers, lightbar,
mic light, and player indicators. Full investigation write-up:
`docs/DUALSENSE_SPEAKER_NATIVE_INIT.md`.

### Fix: all LED/trigger output dead after Reset Scripts mid-gameplay (2026-07-10)

Confirmed in-game. Previously, after a REFramework **Reset Scripts** while
already in active gameplay, the lightbar, adaptive triggers, ammo indicator,
and Mic LED all stayed off until the player exited to the menu or reloaded a
save (both of which fire `CampaignManager.onStartInGame`).

Root cause, confirmed empirically via `events_debug.txt` (`gen=1`, `prev=nil`
on every reset): this REFramework build **fully resets the Lua state** on Reset
Scripts — `_G` does not persist. The earlier fix attempts relied on preserving
`in_game` / ownership / cached color through `_G` (`_prev`, and the preserved
flags in `native_feedback.lua`); that preservation never actually ran, so the
mod stayed dormant because `onStartInGame` never fires on a Reset Scripts.

Fix in `events_led.lua`: detect an in-progress gameplay session by **live-
polling HP context** instead of trusting `_G`. `poll_game_state` now arms a
one-shot `reset_recovery_pending`; if a valid, non-dead player HP context stays
valid for 2 consecutive poll cycles (~1 s) and no real `onStartInGame` has
fired yet, it calls `begin_pending_gameplay_enable("reset scripts recovery")`
to re-enable outputs itself. At a genuine fresh boot (main menu) HP context is
invalid, so recovery never misfires there, and it disarms as soon as a real
`onStartInGame` runs. The dead `_prev`-based preservation seeding in
`events_led.lua` is retained only as harmless fresh-default fallbacks.

**Follow-up (2026-07-11, confirmed in-game):** the recovery misfired on the
very first cold-start load — the lightbar and triggers lit up during the
initial loading screen. Cause: on a cold start the scripts load at the
title/menu (HP context invalid), but HP context goes valid during the level
load, several seconds before `onStartInGame`, so recovery's "valid for 2
cycles" condition was met mid-load. Fixed with a first-poll discriminator: a
Reset Scripts triggered mid-gameplay has valid HP *immediately* (engine keeps
running, only Lua reloads), so if the **first** poll after load has no valid HP
context, it's a cold start and `reset_recovery_pending` disarms permanently —
the first real enable then belongs to `onStartInGame`. Both paths confirmed:
cold start no longer lights during loading, Reset-Scripts-mid-gameplay still
recovers.

### Fix: knife finisher missing impact layer (2026-07-12)

Added flesh-impact layer for knife finisher (stagger/downed enemy). The existing
`knife_finish` route (`1074911781`, `ch_wp5805.bnk`) covered only the animation
stab sound — the hit-contact layer was silent. Three additional events from
`ch_cha0.bnk` (`2456497329` / `1360748365` / `1344092666`) now route to a shared
`knife_finish_hit` stem (4 WAVs: 1.30s / 1.09s / 0.94s / 0.60s). All three share
`suppress_group = "knife_finish_hit"` so only one impact plays per finisher.
Rejected `2008584986` (generic 1559-WEM blood container) — fires in non-finisher
combat contexts.

### Fix: parry sound missing for some parry types (2026-07-11)

Added `knife_e125` (Wwise event `1651038214`, `ch_wp_knife_cm.bnk` event 0125)
as a third parry variant. Event was previously extracted during the 2026-07-01
Mercenaries session but misclassified as a dead campaign hit and removed. A
silent-parry capture session on 2026-07-11 placed it inside the parry diagnostic
window; both WEMs are parry clash sounds (3.7 s / 3.3 s), user-confirmed.
Routed with `suppress_group = "knife_minor"` alongside e129 / e135.

### Fix: knife hit sound duplicating (2026-07-08)

Removed `chainsaw.Melee.onHitAttack` hook from `events_led.lua`. This hook
was calling `play_knife_hit()` in parallel with the Wwise route for event
`2846967310` in `wwise_audio_router.lua`, causing `knife_hit` to fire twice
per enemy hit. The Wwise route is the authoritative source — it fires only on
actual knife-on-enemy audio with correct game context. Removed the hook, the
`knife_hit_cooldown` state variable, and the `KNIFE_HIT_COOLDOWN_FRAMES`
constant. `AUDIO.knife_hit_enabled` and `AUDIO.play_knife_hit()` remain in
`audio_feedback.lua` as the emit target (called from the Wwise router via
`AUDIO.emit`).

### Item pickup speaker sounds — full category set (2026-07-07)

14 game-accurate WAV files extracted from `ch_ui_ingame_media.sbnk.1.x64`
(Wwise event `play_CH_GUI_INVENTORY_UNIQUE_01`, index 0608) and deployed as
controller-speaker sounds for all item pickup categories:

- `pickup_ammo1/2` — ammo pickups (sm70)
- `pickup_healing1/2` — herb and spray pickups (sm71)
- `pickup_treasure1/2` — treasure/valuables (sm74, spinel range)
- `pickup_metal1/2` — metal, resources, gunpowder, grenades (sm74_538)
- `pickup_pesetas1/2/3` — peseta coin pickups (sm74_554, sm77)
- `pickup_key_item1/2/3` — key items / quest items (sws_quest)

`PICKUP_EVENT_BY_CATEGORY` in `audio_feedback.lua` now includes `key_items`.
Stale explicit aliases in `SoundMap.cs` (`ammo_pickup`, `pesseta`, etc.) that
blocked the identity fallback were removed; bridge rebuilt. See
`docs/TASK_PICKUP_SOUNDS.md` for Wwise architecture and WEM ID table.

### Release handoff for final v1.0 staging (2026-07-07)

Added `docs/RELEASE_HANDOFF_2026-07-07.md` with the current verified baseline,
remaining release blockers, package-surface audit checklist, hardware matrix,
and a ready-to-paste task prompt for the next agent.

### Extractor DLC pak support (2026-07-07)

`setup_sounds.ps1` now checks the base `re_chunk_000.pak` first and then
`dlc/re_dlc_stm_2109308.pak` when present, allowing Sentinel Nine (`wp6000`)
speaker sounds to be extracted from the DLC pak. Full temporary-folder
extractor retest passed: 688 extracted, 0 errors, including QTE, inventory UI,
and `wp6000_*` outputs.

### Extractor manifest bank-list sync (2026-07-07)

Synced `DSE_Required_Banks.list` with the current `sounds_manifest.json`
surface: 688 required WAV outputs across 25 Wwise banks, including QTE and
inventory UI sounds. The release manifest and extractor README now document
the same counts.

### Release tooling - verified transport artifact path (2026-07-07)

Release deploy verification and release-copy sync now treat
`speaker/DualSenseEnhancedTransport/bin/Release/net6.0-windows/win-x64/publish-fixed/DualSenseEnhancedTransport.exe`
as the v1.0 transport artifact. The deployed game-folder executable already
matched this `publish-fixed` build; the older `publish/` output was stale and
caused a false `verify_deploy.ps1` mismatch. `release/v1.0/RELEASE_MANIFEST.md`
now documents the same source path for the Nexus package.

### Knife action speaker sounds — full campaign set (2026-07-07)

Live-captured and routed the knife action set for the controller speaker
(campaign sessions, Combat + Kitchen knives). New always-on Wwise routes in
`wwise_audio_router.lua` (no `weapon_id` gate):

- `knife_hit` (2846967310) — enemy hit, 3 WAV variants.
- `knife_surface` (1953686865) — wall/prop hit; wood (WAV 1-3) + metal (4-7)
  material groups deployed, water group intentionally excluded (the router
  cannot see Wwise's material switch, and water on dry surfaces sounded
  wrong; idea for state-based material detection filed in IDEAS.md).
- `knife_finish` (1074911781, ch_wp5805.bnk) — finisher stab.
- `knife_stealth` (2764633896) / `knife_stealth_cb` (4245295432) — stealth
  kill stabs.
- `knife_swing`/`knife_swing_hit`/`knife_draw` (ch_wp5000.bnk, Combat Knife)
  and `knife_swing_kitchen`/`knife_draw_kitchen` (ch_wp5002.bnk, Kitchen
  Knife).

Removed the 2026-07-01 Mercenaries audition hit set (`knife_e115`–`e139`
except the parry pair) — those events never fire in campaign; superseded by
`knife_hit`. Parry routes `knife_e129`/`knife_e135` unchanged.

New router mechanics: `suppress_group`/`suppressed_by`/`suppress_duration`
give parry priority over the frequent minor knife sounds, and `defer`
(75 ms deferred-emit queue flushed on the UpdateBehavior tick) lets a parry
cancel minor sounds whose Wwise events arrive a few ms before the parry
event. User-tuned: 150 ms defer was audibly late, 75 ms is not.

Also: regenerated `sounds_manifest.json` (knife entries hand-corrected to
match the deployed WAV set — the generator walks nested containers and
would otherwise ship the excluded water WEMs and a 5 s stealth stinger);
added the four knife banks (`ch_wp_knife_cm`, `ch_wp5000`, `ch_wp5002`,
`ch_wp5805`) to `DSE_Required_Banks.list` — `ch_wp_knife_cm` had been
missing since 2026-07-01, so fresh installs could not extract the parry
WAVs. Rejected candidates and bank-layout notes recorded in
`WEAPON_AUDIO_STATUS.md`; grab/QTE finisher stab remains unidentified.

### Haptics experiment — STOPPED, not a v1.0 priority (2026-07-07)

Project owner decision: stop the footstep-haptics experiment at the
RE4R-write-race blocker below rather than pursue further R&D right now.
Not a v1.0 concern either way — verified (see `tools/sync_to_release.ps1`
mechanics) that the added code, while it physically travels with shared
files the sync script must copy, is functionally unreachable in a release
build: the enabling checkbox lives entirely inside the `RELEASE_BUILD`
gate, all flags default off, and no shipped config can turn it on. The
architecture and findings stay in the codebase/docs as reference; no
further testing or tuning is planned without an explicit new instruction.
See `docs/HAPTICS_FOOTSTEPS_TASK.md`'s updated header/exclusion section.

### Haptics experiment — Stage 2 live test: actuator content blocked by suspected RE4R write race (2026-07-07)

Live playtest confirmed the entire Lua/C# pipeline works end-to-end
(`haptic_footstep` events written on a plausible footstep cadence,
`haptics_enabled` config picked up, `Haptics=haptics` continuously applied
by the transport, `HapticPlayer` opens the endpoint and dispatches without
error) — but the already-confirmed 80 Hz test tone produces **no felt
vibration at all** while RE4R is running, in every condition tested
(combat, AFK, standing still). The identical tone works fine the instant
RE4R is fully closed and only the standalone transport holds the mode,
ruling out a hardware/driver/environment regression.

This revises Stage 1's "PASSED" framing: Stage 1 confirmed Capcom's own
native haptics survive audio-haptics mode being held, but never actually
re-confirmed that *our* channels-3/4 actuator content survives alongside
Capcom's — it turns out it doesn't. Working theory: RE4R likely still
issues its own native controller-vibration writes (standard OS vibration
API, probably every frame as a keepalive even at idle) on a path our
duaLib process cannot see or arbitrate, which are inherently
compatible-rumble and very plausibly force the physical mode back before
our WASAPI audio content can render as felt vibration -- a materialization
of the compound-report race risk already flagged in `docs/AGENTS.md`/
`docs/MEMORY.md` before this experiment began.

Not yet resolved; needs a project-owner decision on whether to pursue
further (intercepting RE4R's own vibration writes, or another mitigation)
or stop here. See `docs/HAPTICS_FOOTSTEPS_TASK.md`'s revised go/no-go
section for full detail.

### Haptics experiment — Stage 2 architecture implemented (2026-07-07)

Built the persistent enable path Stage 2 needed instead of reusing Stage
1's throwaway literal-flip flag. `dualib_trigger_ipc.lua`'s diagnostic
`IPC.haptics_test_mode_enabled` is renamed to `IPC.haptics_mode_enabled`
and is now the single source of truth for two independent subsystems: the
watcher's audio-haptics mode hold (unchanged logic, just the renamed
field) and a new `AUDIO.play_footstep_haptic()` wrapper in
`audio_feedback.lua` that emits `haptic_footstep` when the flag is on.
`wwise_audio_router.lua` gained one new additive `event_map` entry for
the confirmed footstep event `1528453721` (`handler =
"play_footstep_haptic"`, `cooldown = 0.20`) — this ID had no prior route.

The flag is persisted via `settings.lua` (`snapshot()`/`apply()`'s
`dualib` block, plus an explicit `false` in `reset_runtime_defaults()` so
resetting to runtime defaults never re-enables it) and toggled from a new
debug-only checkbox in `DualSenseEnhanced.lua`'s `draw_debug()` — gated by
the same `RELEASE_BUILD` check that already hides `monitor.lua`/
`capcom_haptics_diag.lua` from the packaged v1.0 UI, so this cannot leak
into a release build regardless of `show_debug_tools`. A matching
dev-only status line was added to `draw_status()`.

Re-checked `HapticPlayer.cs`'s dispatch model while researching this: it
already holds one persistent `WasapiOut`/`MixingSampleProvider` (opened
once, each event just adds a mixer input), so the footstep cadence
latency concern flagged after Stage 1 did not require any C# changes.

Confirmed during research: no working Lua-readable getter for the
`ch_ground_attribute` surface switch exists yet — Stage 3 (per-surface
WEM variation) needs new hook-exploration work first.

All 5 changed Lua files deployed and sha256-verified;
`tools/verify_deploy.ps1` shows no drift on any of them. Still excluded
from release v1.0. Awaiting a live playtest (requires manually setting
`haptics_enabled: true` in the deployed `DualsenseAudioBridge.json` plus
enabling the new debug checkbox) before tuning the `cooldown` value and
declaring Stage 2 hardware-confirmed. See `docs/HAPTICS_FOOTSTEPS_TASK.md`.

### Haptics experiment — Stage 1 go/no-go PASSED (2026-07-07)

Hardware-confirmed in live gameplay (native mode, USB DualSense Edge, DSX
closed, Steam Input disabled, `Adaptive Triggers` enabled+saved): holding
`scePadSetVibrationMode`'s audio-haptics mode for the whole session does
**not** break Capcom's native haptics (shots/reload/damage/low-HP
heartbeat), the custom lightbar, adaptive triggers, Mic LED, gyro, or
controller-speaker audio. The two modes are not mutually exclusive on this
hardware in practice, resolving Stage 1's open go/no-go question with a GO.

Tested via a temporary literal flip of `dualib_trigger_ipc.lua`'s new
`IPC.haptics_test_mode_enabled` diagnostic flag (adds an optional `haptics`
field to every IPC write when true, omitted otherwise; not wired into
settings.lua or any UI). Reverted to its default-off state and redeployed
immediately after testing (sha256 `b5ea2aef...`).

Stage 2 (routing the confirmed Wwise footstep event `1528453721` through
`wwise_audio_router.lua` into the actuator path) is next; see
`docs/HAPTICS_FOOTSTEPS_TASK.md`. Still fully excluded from release v1.0.

### Tools — sounds_manifest.json now covers all Wwise-routed sounds (2026-07-07)

Added `manifest` subcommand to `tools/extract_sounds/wwise_events.py`. It reads
all `event = ...` entries from `wwise_audio_router.lua`, walks the HIRC chain
for each event ID to resolve WEM IDs, and merges entries into
`tools/extract_sounds/sounds_manifest.json` without touching hook-based reload
entries already in the manifest.

Result: `sounds_manifest.json` now contains **650 entries** (was 100).
Users running `setup_sounds.bat` on a fresh install will now extract draw,
aim, dry_fire, last_shot, postshot, knife, and all other Wwise-routed sounds
in addition to the previously-covered hook-based reloads.

Documented in `docs/AGENTS.md` → "Keeping sounds_manifest.json up to date".
Dev workflow: after routing any new `event = ...` entry, run
`wwise_events.py manifest` and commit the updated `sounds_manifest.json`.

### Audio — base-game weapon profile complete (2026-07-07)

All base-game weapons fully investigated. No open ❌ entries remain in
`docs/WEAPON_AUDIO_STATUS.md` — every role is either confirmed+deployed (✅)
or confirmed absent (➖).

**Striker (4102):**
- aim_in/aim_out `2850476286` shared (2v ~0.27–0.38s, ch_wp4102.bnk) ✅
- finish ➖ (no ch_wp4102 event in reload_finish window)

**CQBR (4402):**
- reload_insert_b `1920728793` (3v ~0.22s, ch_wp4402.bnk) secondary magazine
  click ✅
- reload_start ➖ (no ch_wp4402 event in reload_start window)
- last_shot ➖ (no dedicated event confirmed)

**SR M1903 (4400):**
- last_shot ➖ — `2252083765` fires on every shot incl. last; no dedicated
  last_shot event

**Magnums (confirmed absent):**
- Killer7 (4501) aim_out ➖ — no sound in game
- Broken Butterfly (4500) aim_out ➖ — no sound in game

### Added (weapon audio — full pass session, 2026-07-06)

Full audio routing pass for SMGs, magnums, Bolt Thrower, and Skull Shaker.
All sounds live-confirmed in-game before committing.

**SMGs:**
- TMP (4200): draw 6-stage ✅, dry_fire `2462166917` (4v) ✅, last_shot ➖
- Chicago Sweeper (4201): draw 4-stage ✅, dry_fire `3428451702` (3v) ✅,
  aim_in via draw_b ✅, aim_out ➖, last_shot ➖
- LE 5 (4202): dry_fire `641294031` (3v) ✅, last_shot ➖

**Magnums:**
- Broken Butterfly (4500): aim_in `4007639528` (1v ~0.27s) ✅
- Killer7 (4501): aim_in `3317704895` (3v ~0.21-0.34s) ✅; draw/reload/dry_fire
  live-confirmed
- Handcannon (4502): aim_in `3054041130` (3v ~0.35-0.66s) ✅, aim_out ➖;
  draw/post_shot/dry_fire live-confirmed

**Bolt Thrower (4600) — complete:**
- draw `300966990` (6v, switch container) ✅
- aim_in `922138092` (2v) + `2857008769` (1v click) ✅
- aim_out `3051463304` (2v) ✅
- post_shot `2370660519` (4v ~0.28-0.45s, first-stage without echo) ✅
- dry_fire `1756416417` (1v ~0.07s) ✅
- mine attach/detach `1946457442` (3v ~0.33-0.43s) ✅

**Skull Shaker (6001):**
- draw `960381449` fixed — replaced placeholder with real WAVs (6v ~0.30-0.43s)
- reload_start (tray open) `1840028007` + `2246536536` + `814106828` — 3-layer,
  previously marked as absent (per-shell only) ✅

**Stingray (4401):**
- last_shot `1122442048` (3v ~0.31-0.46s) ✅
- insert `3683820930` confirmed already routed (STATUS correction)

**TMP aim_in/aim_out:** no ch_wp4200.bnk candidates found → ➖

### Changed (audio endpoint list UI, 2026-07-06)

- `DualSenseEnhanced.lua`: replaced the manual controller-speaker endpoint
  Previous/Next carousel with a direct visible endpoint list sourced from
  `audio_devices.json`. Each row marks the current selection plus Auto and
  DualSense-detected endpoints when reported by the bridge.
- Moved legacy name-fragment audio presets out of the main speaker output
  mode row into a collapsed compatibility section. Normal release flow now
  presents `Auto DualSense` and `Manual Endpoint` first.

### Added (footstep haptics experiment Stage 0, 2026-07-05 through 2026-07-06) — STAGE 0 HARDWARE-CONFIRMED, EXCLUDED FROM v1.0

- `DualSenseEnhancedTransport`: opt-in audio-haptics vibration-mode selection
  through `scePadSetVibrationMode`. New optional `Haptics: {"Mode": 1|2}`
  command-file field (absent = restore compatible rumble),
  `--test-haptics-mode --duration <ms>` stand command, and rumble-mode
  restore in the safe `Reset()` path.
- `DualsenseAudioBridge`: new `HapticPlayer` playing `haptic_`-prefixed events
  on channels 3/4 of the DualSense 4-channel WASAPI endpoint (actuators),
  alternating left/right per event; gated by new `haptics_enabled` (default
  false) and `haptics_volume` config keys; `--test-haptic [left|right|both]`
  stand command.
- `tools/generate_haptic_footstep.ps1` + generated
  `sounds/haptic_footstep.wav` (48 kHz float stereo synthesized thump).
- Two manual `.bat` helpers for the physical stand test:
  `speaker/HAPTICS_TEST_A_HOLD_MODE.bat` /
  `speaker/HAPTICS_TEST_B_PLAY_TONE.bat`.
- **duaLib fork fix, hardware-confirmed 2026-07-06**: the first Stage 0
  control-condition check (tone played after the haptics-mode hold ended)
  still vibrated. Root cause: `dataStructures.h`'s `SetStateData::operator==`
  never compared `UseRumbleNotHaptics`/`EnableRumbleEmulation`/
  `EnableImprovedRumbleEmulation` — the fields `scePadSetVibrationMode`
  writes — so `readDualsense.cpp`'s write-gate (`curState != lastState`)
  never fired on a vibration-mode-only change and the switch back to rumble
  was silently dropped; the controller stayed in audio-haptics mode
  indefinitely. Fixed by adding those three fields to the comparison and
  rebuilding `build_out/duaLib.dll` (new confirmed SHA-256
  `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`,
  supersedes the 2026-06-30 lightbar-allowled build `0BF8351F...` in
  `docs/AGENTS.md`/`speaker/BUILD.md`/`speaker/DualSenseEnhancedTransport/README.md`/
  `docs/DUALIB_HID_BRANCH.md`). Regression-tested clean against
  `--test-l2`/`--test-r2`/`--test-lightbar`/`--test-mic-light`/
  `--test-indicators` before redeploy; user then hardware-confirmed both the
  haptics-ON vibration and the now-silent control condition.
- **Excluded from release v1.0** by user decision (2026-07-06): everything
  is opt-in default-off, no v1.0 UI exposure, and these changes must not be
  synced into the `Release v1.0` checkout.
- See `docs/HAPTICS_FOOTSTEPS_TASK.md` for the stage plan, the Stage 1
  go/no-go question (Capcom native haptics vs. held haptics mode), and
  multi-agent rules while the experiment is in flight. Lua routing and the
  UI toggle are intentionally not implemented until Stage 1 physical
  confirmation.

### Fixed/Confirmed (audio endpoint smoke test and runtime feedback, 2026-07-04)

- Live test confirmed that the manual WASAPI endpoint list appears in the
  REFramework UI, `Next` can switch between available devices, and
  `Test Speaker` plays on the selected endpoint, including non-controller
  Windows output devices.
- Fixed the controller-speaker smoke test: `Test Speaker` previously emitted
  `heal_herb`, but the current runtime no longer ships `heal_herb.wav` or
  `healing_spray_original.wav`, so the bridge logged `No sound for event:
  heal_herb`. The test event now uses confirmed `parry` WAV variants.
- Removed the redundant `Test Parry` UI button. `Test Speaker` is now the
  single endpoint smoke-test; gameplay parry audio remains unchanged.
- Live test confirmed normal menu-to-gameplay lightbar entry is correct after
  the recent blackout/ownership fixes.
- Live test confirmed death blackout works: lightbar, player indicators, and
  Mic LED all turn off. Current behavior is slightly sequential because those
  outputs are controlled by separate runtime paths/ticks. Future polish: send
  one forced blackout command that clears lightbar, indicators, Mic LED, and
  triggers in the same frame.
- Loading from an already-active gameplay session can still show Capcom blue
  before the current hook takes ownership. Main-menu-to-gameplay entry is
  confirmed good; gameplay-to-loading needs a more specific start hook.
- L2 spam was retested: gyro no longer drifts and adaptive-trigger haptics no
  longer appear stuck. Keep this on the watchlist because gyro and trigger
  effects share the delayed duaLib transport, and heavy command churn can still
  produce occasional `Command read unstable, skipped` watcher entries. If the
  issue returns, investigate atomic `trigger_command.json` writes and a forced
  reset/off command on L2 release before touching the audio bridge.

### Changed (manual audio endpoint picker, 2026-07-02) — LIVE TESTED 2026-07-04
- `DualsenseAudioBridge.exe` now enumerates active Windows WASAPI render
  endpoints and writes `reframework/data/DualSenseEnhanced/audio_devices.json`
  every few seconds. The file contains endpoint `id`, display `name`, index,
  DualSense-name detection, and the endpoint chosen by auto-detect.
- `audio_feedback.lua` now includes `device_id` in each `audio_events.json`
  event. The bridge resolves playback in this order: exact endpoint ID,
  legacy friendly-name fragment, then automatic DualSense detection.
- `DualSenseEnhanced.lua` now exposes controller-speaker output modes:
  `Auto DualSense`, `Manual Endpoint`, and `Legacy Presets`. Manual mode
  cycles through the endpoints reported by the bridge and persists the
  selected endpoint ID through `settings.lua`.
- Deployed runtime files and verified project/runtime SHA-256 parity for the
  bridge, loader, `audio_feedback.lua`, and `settings.lua`.
- Live validation with a connected controller was completed on 2026-07-04:
  devices appeared in the UI, manual switching worked, and `Test Speaker`
  played on the selected endpoint.

### Fixed (duaLib trigger mapping after namespace cleanup, 2026-07-02)
- Fixed a post-refactor native duaLib regression where the external transport
  started correctly but L2/R2 stayed `Off` because
  `feedback_writer.lua` could silently fail to load
  `DualSenseEnhanced/weapon_trigger_profiles.lua`.
- `feedback_writer.lua` now loads trigger profiles independently of
  `payload.json` availability, records mapping diagnostics
  (`mapping_status`, `mapping_path`, `mapping_count`, `mapping_error`), and
  `dualib_trigger_ipc.lua` retries mapping load before emitting native trigger
  commands if the mapping table is empty.
- Replaced the deployed `duaLib.dll` with the newer
  `third_party/build_out/duaLib.dll` lightbar-allowled build. The previous
  deployed DLL was the older 2026-06-26 trigger-only build, so the watcher
  logged `Led=(...)` commands while the library still suppressed RGB lightbar
  output at the HID report layer.
- After redeploying the Lua fix and the corrected DLL, restarting the bridge
  and watcher, and re-running `tools/verify_deploy.ps1` (`373/373` deployed
  files matched), the user confirmed that UI, audio bridge, duaLib triggers,
  and lightbar feedback all work as expected.

### Changed (DualSense Enhanced namespace cleanup, 2026-07-01)
- Renamed the REFramework runtime namespace from `DualsenseX`/`DualSenseX`
  to `DualSenseEnhanced`, including the main loader, autorun module folder,
  data folder, settings path, trigger-profile data file, and audio bridge
  sound paths.
- Renamed internal globals from `_G.DSX*` to `_G.DualSenseEnhanced*` so the
  mod identity matches **DualSense Enhanced Edition**. The `dsx` output mode
  remains only as a factual DSX-compatible backend/protocol value.
- Updated tooling, docs, manifests, and bridge config references away from
  the old project namespace and removed legacy baseline mod/archive wording
  from current documentation.

### Changed (v1.0 UI polish, 2026-07-01)
- Reworked the REFramework UI into a native-first release panel:
  `Status`, `Global Preset`, `Core Features`, `Lightbar`,
  `Adaptive Triggers`, `Controller Speaker Audio`, `Gyro Aim`, `Advanced`,
  and hidden `Debug Tools`.
- Added `Global Preset` state with `Immersive (Default)` and `Custom`.
  `Immersive` enables native mode, enhanced mod lightbar, native trigger IPC,
  native ammo indicators, Mic LED sync, controller speaker audio, and gyro aim.
- Added `Lightbar` mode state with `Enhanced Mod Lightbar` and
  `Native Game Lightbar`; the native mode releases RGB lightbar ownership back
  to the game and disables both native-feedback and duaLib custom lightbar
  writes.
- Added a global custom lightbar brightness multiplier, persisted through
  settings, while keeping the existing per-effect RGB color editors.
- Moved trigger class sliders, audio event toggles, gyro sensitivity sliders,
  config controls, radio, diagnostics, and console output under collapsed
  advanced/debug sections.
- Stopped loading the old standalone `weapon_equip_ui.lua` and `debug_led.lua`
  UI panels from the main loader so v1.0 no longer exposes payload/UDP/legacy
  DSX wording in normal use.

### Changed (2026-07-01)
- `tools/verify_deploy.ps1` now hashes deployed Lua data files under
  `src/reframework/data/**/*.lua` as well as autorun Lua, sound WAVs, and the
  bridge exe. This closes the blind spot for `weapon_trigger_profiles.lua` and
  `RE4R_WeaponData.lua` deploy drift.
- Removed cutscene/pause/loading suppression from the active mod runtime:
  deleted the temporary `Force cutscene gate` UI, `EventsLed.set_cutscene`,
  `cutscene_active` gating, and Movie/Timeline diagnostic enumeration. The
  topic is now tracked only as a future idea.

### Fixed (all LED/trigger output off on player death, 2026-07-02) — NOT YET TESTED

- **Problem:** on death, lightbar continued showing the last HP color (red),
  ammo indicator showed last ammo state, Mic LED stayed active, and adaptive
  triggers held their last weapon resistance state.
- **Root cause (lightbar):** `EVENTS.in_game` stays `true` during death (by
  design — the player is physically still in-game, just dead). The `in_game`
  hold added for entry-flash prevention kept `owns_lightbar = true` and
  `cached_color` at the last HP color; `device_update_post_hook` enforced
  that color every frame, so the lightbar never cleared.
- **Root cause (triggers):** `IPC.tick()` gated on `EVENTS.in_game == true` —
  which stays true during death — so trigger weapon effects kept being written
  to the JSON transport every frame. L2/R2 continued to resist as if the player
  were aiming.
- **Root cause (ammo/Mic LED):** `AMMO.set_gameplay(false)` already called
  `set_mic_empty(false)` and `clear_indicator()` correctly, but these were
  overridden by the lightbar hold leaving stale `cached_color`. Now that the
  lightbar clears, expected ammo/Mic behavior should follow; will confirm in test.
- **Fix (lightbar):** added `NATIVE.death_blackout` flag in
  `native_feedback.lua`. In `apply_lightbar`, a new check handles
  `loading_blackout OR death_blackout` identically: claim ownership and write
  `0,0,0`, clearing `cached_color` from the previous HP red. `death_blackout` is
  set in the death detection branch of `poll_game_state` (first `is_dead` tick
  only), and cleared in `begin_pending_gameplay_enable` (death recovery path)
  and on menu exit (safety reset).
- **Fix (triggers):** added `EVENTS.player_dead` flag (set alongside
  `death_blackout`, cleared alongside it). `IPC.tick()` now checks
  `not EVENTS.player_dead` in the `gameplay_ready` expression — when dead,
  `gameplay_ready = false` → `set_ready(false)` + `IPC.reset()` fires every
  tick, zeroing L2/R2 effects until recovery.
- **Transition:** on recovery (`begin_pending_gameplay_enable`):
  `death_blackout = false` and `player_dead = false` are cleared before
  `set_gameplay_outputs(true)`. The existing `in_game` hold then covers the
  1-2 frame gap before HP pushes its first color, so there is no flash between
  black and HP color.

### Fixed (Capcom native blue during level loading, 2026-07-02) — NOT YET TESTED

- **Problem:** during the level loading screen (after selecting "Load Game",
  before `onStartInGame` fires), Capcom's native blue lightbar was visible.
- **Fix:** added `NATIVE.loading_blackout` flag in `native_feedback.lua`.
  In `onStartInGameSetup` POST-hook (`events_led.lua`), when `output_mode ==
  "native"`, sets `NATIVE.loading_blackout = true` — this is the earliest
  confirmed hook in the load sequence. In `apply_lightbar`, the combined
  `loading_blackout OR death_blackout` check forces black and claims
  ownership, blocking Capcom's `set_LightBarColor` via `lightbar_pre_hook`
  and re-enforcing `0,0,0` via `device_update_post_hook` every frame.
  Cleared in `onStartInGame` POST-hook (first action, before `reset_all()`)
  so the existing `in_game` hold takes over for the 1-2 frame gap before
  HP color appears.
- **Coverage:** from `onStartInGameSetup` until `onStartInGame`. The loading
  period before `onStartInGameSetup` fires (very first seconds after selecting
  load) may still show Capcom blue — a more specific hook for load-start has
  not yet been found (`CampaignManager.onStartLoading` does not exist).
- **Safety:** menu exit clears `loading_blackout` to prevent stuck-black if a
  load is abandoned mid-sequence.

### Fixed (Capcom native green/blue flash on gameplay entry/exit, 2026-07-02) — NOT YET TESTED

- **Problem:** on gameplay entry (warm and cold start), Capcom's native green
  lightbar flashed briefly (~0.5s) before the custom HP color appeared. Same
  on exit to menu: Capcom's blue briefly flashed during the transition.
- **Root cause:** `apply_lightbar(nil)` is called when the LED bus is empty.
  That happens for 1-2 frames right after `reset_all()` runs inside the
  `onStartInGame` POST-hook, before `hp_led.lua` has had a chance to push its
  first HP color. In that window, `owns_lightbar` was set to `false` → the
  `lightbar_pre_hook` stopped blocking → Capcom's `set_LightBarColor(green)`
  passed through. Same gap on exit: `clear_gameplay_outputs()` empties the LED
  bus while `EVENTS.in_game` is still true for ~1 poll cycle.
- **Fix:** in `apply_lightbar`'s else-branch (no active LED source), check
  `_G.EventsLed.in_game` before releasing `owns_lightbar`. When gameplay is
  active, keep the claim even with an empty LED bus (`cached_color = nil` means
  the post-update hook enforces no color during the hold — lightbar just holds
  whatever was last drawn). Release immediately when `in_game = false`.
- **Result:** transition is [menu blue] → [HP color], with Capcom's green
  never getting through. Exit transition: [HP color] → [Capcom blue] once
  `in_game = false`, same as before.
- **Edge case:** if death detection takes 1 poll cycle to set `in_game = false`,
  the claim is held for that extra cycle (~2-5 frames). HP LED has already
  cleared its sources so `cached_color = nil` and nothing is enforced — the
  lightbar just stays at the last HP color for those extra frames. Acceptable.

### Changed (native device capture via device.update hook, 2026-07-02) — NOT YET TESTED

- **Problem:** on cold start (first RE4R launch), custom lightbar had a 2-3s
  delay after entering gameplay before appearing. On warm re-entry (exit to
  menu + reload same session), no delay — because `NATIVE.available` persisted
  as `true` from the first load.
- **Root cause:** `refresh_device()` goes through
  `AppSingleton<share.hid.DeviceSystem>.get_Instance → getGamePadDevice(0)`.
  This path returns nil for the first 2-3 seconds of a cold session because
  `share.hid.DeviceSystem`'s own native-DualSense enumeration takes that long to
  complete on first run. The per-frame retry (DEVICE_RETRY_INTERVAL=1) was
  already polling at max frequency; the delay was the underlying enumeration
  time, not our polling cadence.
- **Fix:** added early-capture logic to the pre-hook of
  `share.hid.Device.update` (already hooked for post-update lightbar
  enforcement). That hook fires every frame the engine calls `update()` on the
  device object; `args[2]` is the `this` pointer (the device instance itself).
  While `not NATIVE.available`, a `pcall` tries
  `sdk.to_managed_object(args[2])`, checks `get_IsDualSenseDevice() == true`
  and `find(“DualSense”)` on the native type name; if both pass, sets
  `current.device`/`native_device`/`available` directly — bypassing the
  AppSingleton path entirely. Once `available=true` the condition short-circuits
  immediately; no ongoing overhead.
- **Expected outcomes (best→worst):**
  - `share.hid.Device.update` fires during the main menu → zero cold-start delay
  - Fires at load-screen start → delay shrinks to sub-second
  - Both paths capture at the same time → stays 2-3s (no regression; existing
    retry still runs in parallel)
- `NATIVE.last_status` is set to `”captured via device.update hook”` when this
  path wins, visible in the Config UI Status row.

### Session summary (2026-07-01) — all hardware-confirmed

Full session arc confirmed working end-to-end:
- `hp_danger` pure red continuous pulse (no orange), synced Mic LED via `LED.danger_pulse_on`.
- `ammo_empty` continuous sine pulse (no hard blink), synced Mic LED via `AMMO.empty_pulse_active`/`empty_pulse_on`.
- Stutter from per-frame LED push fixed by `pulse_push_interval`/`pulse_steps` throttle.
- `ever_started_in_game` guard prevents adaptive-trigger/LED enable during loading screens; flag resets on every gameplay→menu transition, not just the first one per session.
- `resetLightBarColor()` removed from all three `native_feedback.lua` call sites; lightbar on menu exit now correctly restores Capcom's own blue.
- `AllowLedColor` exemption added to `readDualsense.cpp` guard block via `lightBarOverrideEnabled`; duaLib lightbar confirmed working both in isolation (`--test-lightbar`) and in live gameplay (`IPC.lightbar_enabled`).
- Pending items documented in AGENTS.md Coding Rules; no open regressions remaining at session end.

### Added (gyro presets + adaptive trigger presets + accelerometer-based drift correction, 2026-06-30)

#### Gyro presets (native_gyro.lua)
- Added five presets: **Precision** (yaw 500, pitch 450, dz 0.020), **PS5 Feel**
  (650/600/0.018), **Fast Flicks** (850/800/0.015), **Stable** (350/300/0.035),
  **Custom** (free-form). Defaults changed: yaw 600→500, pitch 600→450, dz 0.03→0.02,
  cal 1500→1000 ms to match Precision.
- Added **Invert Y** toggle (`invert_pitch`, default false).
- Added **Activation mode**: "While Holding L2" (default) or "Always On"
  (`activation_mode` field; always-on sets `effective_threshold=0`).
- `write_config()` serialises `invertPitch` to JSON so the bridge picks it up.
- `apply_preset()` / `mark_custom()` helpers; `apply_settings()` extended for new fields.

#### Adaptive trigger intensity presets (trigger_intensity.lua — new file)
- New module `src/reframework/autorun/DualSenseEnhanced/trigger_intensity.lua`:
  five presets (**Off** 0.0, **Native Only** 0.0, **Light** 0.6, **Enhanced** 1.0,
  **Strong** 1.25) plus per-weapon-class sliders (pistol/shotgun/rifle/automatic/magnum).
- `scale_effect(effect, class)` multiplies `strength`/`endStrength` by
  `global × class` before duaLib writes; returns an Off effect when the product ≤ 0.
- `disables_ipc()` is UI-label-only; it does **not** gate `IPC.tick()` — see the
  critical bug fix below.
- Loaded before `dualib_trigger_ipc.lua` in `DualSenseEnhanced.lua`.

#### UI changes (DualSenseEnhanced.lua)
- Gyro moved from inside the *Config → Native Game API* tree to its own **top-level
  tree node**, always visible regardless of `output_mode`, with a warning when the
  backend is not native.
- Gyro UI: preset buttons, per-slider mark_custom(), Invert Y checkbox, L2 / Always On
  activation mode buttons.
- Adaptive Trigger Preset tree (inside Config → Native Game API): preset buttons,
  global intensity slider, per-class sliders.

#### Settings persistence (settings.lua)
- `snapshot()` now includes `trigger_intensity {preset, global_intensity, class_intensity}`
  and `gyro.{preset, invert_pitch, activation_mode}`.
- `apply()` restores all new fields; applies preset then class overrides; marks "custom"
  when the saved preset name is not in the PRESETS table.

### Fixed (gyro aim drift — calibration accepted controller-in-motion bias, 2026-06-30)
- **Root cause**: gyro bias calibration used only gyro spread/mean to reject motion
  during the window. That check is self-referential: if the controller was being
  lifted/settled into an aim stance the whole window, the spread looks small and the
  mean looks stable, so the drift was locked in as "zero" for the entire session.
  Every subsequent L2 press then had the camera pulled in one direction with no
  recovery except re-releasing and re-holding L2.
- **Fix — accelerometer magnitude check**: duaLib exposes a linear-acceleration vector
  (offsets 28/32/36 in `s_ScePadData`). A controller truly at rest reads |a| ≈ 1g
  regardless of orientation; any real movement shifts the magnitude. Added `IsAtRest()`
  check: `|sample.AccelMagnitude - 1.0| < 0.15`. Calibration window is rejected if
  any accel sample exceeds this bound (in addition to the existing gyro spread/mean
  gates). Up to 5 retries before forcing accept.
- **Unit correction**: initial code used `RestAccelMagnitude = 9.81` (assuming m/sВІ).
  Live `--gyro-log` test with controller flat on table showed |a| ≈ 0.97 — duaLib
  reports in **g**, not m/sВІ. Corrected to `RestAccelMagnitude = 1.0`,
  `RestAccelTolerance = 0.15`. **Hardware-confirmed.**
- **Accel struct fields added**: `GyroMotionSample` now carries `AccelX/Y/Z` floats and
  `AccelMagnitude` property. `DuaLibBackend.ReadMotion()` passes them from the
  `ScePadData` struct (field offsets cross-validated against three known-good offsets:
  RightStickX@6, L2Analog@8, AngularVelocityX@40).
- **Background recalibration**: outside active L2 aiming, whenever `IsAtRest()` is true,
  bias is nudged toward the current reading via EMA (О±=0.01). Prevents long-session
  thermal/time creep without risking deliberate panning being absorbed.
- Log message unit label corrected: "accel m/s^2" → "accel g".

### Fixed (critical — trigger preset Off/Native Only was silently killing gyro, 2026-06-30)
- `dualib_trigger_ipc.lua`'s `tick()` was checking `TI.disables_ipc()` to skip writing
  the watcher-ready marker when trigger preset was "Off" or "Native Only". But gyro
  shares the same watcher process — no ready marker meant the watcher never launched,
  so gyro stopped working whenever the user chose either of those trigger presets.
- Fixed by removing the `TI.disables_ipc()` gate from the ready-marker path in
  `IPC.tick()`. Off/Native Only now only affects whether trigger effects are scaled to
  zero; the watcher always starts.

### Fixed (bridge zombie lingering after game close, 2026-06-30)
- `BridgeRuntimeOptions.GameProcessName` defaulted to `null`, which caused
  `WaitForGameExit` to spin `Task.Delay(Infinite)` — the bridge never noticed the
  game had exited and kept running. Fixed by defaulting to `"re4"`.
- Added `KillLeftoverTransport()` in `DualsenseAudioBridge/Program.cs`: kills any
  `DualSenseEnhancedTransport` process left over from a previous session
  before launching a new one, preventing mutex collision on game restart.

### Fixed (scePadSetPlayerIndicators crash on export-not-found, 2026-06-30)
- Some deployed `duaLib.dll` builds don't export `scePadSetPlayerIndicators`. The
  hard `Load<T>()` call threw "Entry point was not found" at every new session.
- Fixed by making the field `nullable` and using `TryLoad<T>()` (via
  `NativeLibrary.TryGetExport`). `SupportsPlayerIndicators` property added;
  `SetPlayerIndicators()` no-ops when the export is absent.
- Same pattern applied to `scePadSetLightBar`, `scePadResetLightBar`,
  `scePadSetMicLight` for future-proofing.

### Fixed (silent diagnostics — trigger_watcher.log always empty, 2026-06-30)
- `InitializeWatchLog` had an empty `catch` that swallowed any `StreamWriter` open
  failure, leaving the process running with no log output. Fixed by using
  `FileShare.ReadWrite` on the underlying `FileStream` and writing fallback errors to
  `trigger_watcher.initfail.log` instead of silently discarding them.

### Fixed (lightbar stuck black on exit to menu instead of restoring Capcom's blue, 2025-06-30)
- User reported the lightbar stayed black (not a brief flash) after
  exiting gameplay to the main menu with no custom menu color configured.
- Root cause: `native_feedback.lua`'s `apply_lightbar()` called the game's
  own `resetLightBarColor()` whenever no custom LED source was active
  (and the same pattern existed in the `lightbar_enabled = false` branch
  and in `NATIVE.release()`). That call doesn't just blank the bar
  momentarily -- it resets whatever cached color Capcom's own
  `share.hid.Device.update()` re-applies every frame. Capcom only calls
  `set_LightBarColor` again on its *own* state changes, not continuously,
  so once reset to black there was nothing left to make it repaint blue.
- Fixed by removing all three `write_lightbar("resetLightBarColor")`
  calls: on releasing ownership, just stop blocking Capcom's
  `set_LightBarColor` calls (`NATIVE.owns_lightbar = false`) and let its
  next natural call (already hardware-confirmed to fire exactly at
  `onStartInGameCleanup`, see the earlier same-day finding) repaint
  correctly, instead of forcing a reset with nothing to undo it.
- First retest still showed a stuck color after this fix -- false alarm,
  not a regression: `EVENTS.menu_enabled` had been left on from earlier
  same-day testing with `EVENTS.color_menu` set to red, so the lightbar
  was correctly showing that custom color, not stuck black. **Hardware-
  confirmed** after disabling that checkbox: exiting to menu now properly
  shows Capcom's own blue again.

### Fixed (custom menu lightbar never applied at boot; native device capture had no retry, 2025-06-30)
- Two stacked bugs found chasing a customizable menu-lightbar request
  (mirroring the DSX version's menu color, already exposed via
  `EVENTS.menu_enabled`/`EVENTS.color_menu`):
  1. `events_led.lua`'s `poll_game_state()` only pushed the menu LED
     source inside the `in_gameplay ~= was_in_gameplay` transition block.
     At the very first boot, both start `false`, so no transition is ever
     detected and the menu color was never applied for the entire
     boot/title-screen period -- Capcom's own blue won by default. Fixed
     by pushing the menu LED every poll tick whenever `not in_gameplay`,
     not only on a state change.
  2. Hardware-confirmed (2025-06-30, full session log): even after that
     fix, the custom lightbar didn't apply at all for an entire
     boot-to-gameplay session (stayed Capcom blue, then Capcom's own
     native green at `onStartInGame`) until the user manually toggled
     output mode native->off->native. Root cause:
     `native_feedback.lua` only calls `refresh_device()` once, at
     script-load time, which can run before
     `share.hid.DeviceSystem` has enumerated the controller as a native
     DualSense -- there was no retry, so `NATIVE.available` stayed false
     until something else (a manual mode-switch button, which calls
     `native.refresh()`) happened to trigger a second attempt. Fixed by
     retrying `refresh_device()` every `DEVICE_RETRY_INTERVAL` (60 frames,
     ~1s) from inside the existing per-frame tick whenever
     `NATIVE.available` is still false.
- **Hardware-confirmed (partial)**: a fresh full RE4R restart no longer
  needs a manual mode toggle -- the custom lightbar now self-recovers a
  few seconds after entering gameplay on its own. User decided the
  *menu*-color part of this isn't worth pursuing further (happy with
  Capcom's default there) and dropped that part of the request, so item 1
  above is implemented but not specifically retested/cared about anymore.
- The ~3s self-recovery delay was longer than an earlier (pre-fix)
  session where the same capture had happened to succeed in under a
  second -- device-capture timing appears to vary run to run depending on
  USB/driver readiness at script-load time, not something this fix
  controls precisely. Tightened `DEVICE_RETRY_INTERVAL` from 60 frames
  (~1s) to 15 frames (~0.25s); hardware-confirmed delay dropped from ~3s
  to ~1s, but did not disappear, since the remaining time is dominated by
  `share.hid.DeviceSystem`'s own native-DualSense enumeration, not by poll
  cadence. Tightened further to every frame (`DEVICE_RETRY_INTERVAL = 1`)
  to remove polling cadence as a contributor entirely -- not yet
  hardware-confirmed whether this measurably shortens the remaining ~1s,
  since that delay may now be fully hardware/driver-bound.

### Changed (removed remaining legacy baseline dependencies, 2025-06-30)
**For other agents:** game was closed all session; nothing here was
hardware/in-game tested, only syntax-sanity-checked (brace/paren balance)
and hash-verified as deployed. Treat as unverified until the user opens
RE4R, hits Reset Scripts, and confirms triggers/UI still work.
- Confirmed (before touching anything) that the live install's deployed
  `DSX_UDPClient.exe` was already this project's own
  `DSX_UDPClient_Test.exe` build (hash match), not the legacy baseline mod's
  binary -- that dependency was effectively already gone in practice, just
  undocumented. `AGENTS.md` updated to state this explicitly.
- Deleted `DualSenseEnhanced_loader.lua` (src and deployed): byte-identical copy
  of the legacy baseline file, and dead code -- not referenced by any
  `loadf()` call in `DualSenseEnhanced.lua`.
- Rewrote `reframework/data/RE4R_WeaponData.lua`. The deployed copy was a
  15,519-line byte-identical copy of the legacy baseline's full
  weapon/part/Mercenaries database; `weapon_equip_core.lua` only ever
  reads `data.Weapons[*].Enum/.Name/.Type` for the ~30 main-campaign
  weapons. Replaced with an ~85-line own file built from this project's
  own `id_database/CH_WEAPON_NAME_LOOKUP.json` ("eng" table) for names,
  plus the weapon categorization already established in
  `docs/weapon_audio_catalog/`/`MEMORY.md`, generated via a small
  `entry()` constructor instead of a hand-copied literal table. Same
  Enum/Name/Type facts where they overlap (these are RE4R's own internal
  IDs, not the third party's invention); Mercenaries/parts/upgrade data
  dropped since nothing in this project reads it.
- Rewrote `reframework/data/DualSenseEnhanced/weapon_trigger_profiles.lua`. Per explicit user
  direction, kept the same per-weapon-class trigger instruction values
  (resistance/force/snap numbers, lightbar colours) -- not re-deriving
  those by feel was a deliberate call, not an oversight -- but generated
  them through shared `l2_resistance()`/`r2_weapon()`/`r2_bow()`/
  `r2_resistance()`/`r2_vibrate()`/`r2_normal()`/`lightbar()`/`profile()`
  helpers instead of the original's repeated literal instruction tables.
  Verified every generated instruction table against the original
  byte-for-byte (manually diffed each profile's `parameters` arrays) --
  values unchanged, only the authoring structure is new.
- Rewrote `reframework/autorun/DualSenseEnhanced/weapon_equip_ui.lua` (previously
  marked **do not modify** in `AGENTS.md` only because it was an
  unmodified third-party file, not for a code-quality reason). Same
  panel/behavior (enable checkbox, reload-configs button, payload/UDP
  link status, current weapon readout), restructured into named local
  functions (`draw_enable_toggle`/`draw_reload_button`/
  `draw_link_status`/`draw_current_weapon`) instead of one inline
  `re.on_draw_ui` callback body.
- `AGENTS.md`: removed the **do not modify** marks on `weapon_equip_ui.lua`
  and `weapon_trigger_profiles.lua` (now this project's own code, tune freely), updated
  the `DSX_UDPClient.exe` description and the "stable external" coding
  rule to reflect that it's an own build, and dropped
  `DualSenseEnhanced_loader.lua` from the repo file-tree listing.
- Net effect: nothing under `src/` or in the live deployed install is a
  copy of the legacy baseline files anymore. Any separate baseline-mod copy
  inside the RE4R install, if one exists outside what this project deploys,
  can be deleted without affecting this mod.
- Historical note: at the time of this cleanup,
  `tools/verify_deploy.ps1` did not cover `reframework/data/**/*.lua`, so
  `weapon_trigger_profiles.lua`/`RE4R_WeaponData.lua` were hash-verified manually. This
  blind spot was closed on 2026-07-01; the script now checks deployed Lua
  data files too.

### Fixed (early-enable guard only protected the first load per session, 2025-06-30)
- Follow-up to the same-day fix gating `adaptive_gameplay_signal` on
  `ever_started_in_game`: that flag was set `true` inside the
  `onStartInGame` handler and never reset, so it only protected the very
  first load of a process lifetime. User physically felt adaptive-trigger
  resistance/vibration during a *second* load's loading screen (main menu
  -> load save, same `re4.exe` session) -- by then
  `ever_started_in_game` was already `true` from the first load, so
  `adaptive_gameplay_signal` could fire early again, re-enabling
  `EVENTS.in_game` (which gates `dualib_trigger_ipc.lua`'s `IPC.tick`)
  before the real `onStartInGame`.
- Fixed by resetting `ever_started_in_game = false` inside
  `poll_game_state()`'s existing in-gameplay-to-menu transition (the
  `in_gameplay ~= was_in_gameplay` block, `not in_gameplay` case), so the
  guard re-arms every time gameplay ends, not just once per process.
  Death/Continue recovery is unaffected since that path never sets
  `in_gameplay` false through this transition.
- **Hardware-confirmed**: no L2/R2 resistance during the loading screen
  on a second load (main menu -> load save), and the user reports it also
  holds when reloading a checkpoint without returning to the main menu at
  all -- broader coverage than the menu-transition fix alone implied,
  likely because `has_player` already drops out briefly during any load
  transition, not just the main-menu one.

### Fixed (custom lightbar/HP LED lit up during loading, ~6s before real gameplay, 2025-06-30)
- Found the original task-6 hook by decoding Capcom's own
  `set_LightBarColor` calls (see the diagnostic fix below): `via.Color`
  hook args are passed by value as a packed 4-byte little-endian RGBA
  integer, not a pointer -- `sdk.to_valuetype`/`sdk.to_managed_object`
  both threw/failed on it; `sdk.to_int64(args[2])` reads it correctly,
  decode via `r=packed%256, g=floor(packed/256)%256,
  b=floor(packed/65536)%256, a=floor(packed/16777216)%256`.
- With real colors logging, captured a clean one-shot transition: stable
  `(0,14,56)` boot/menu blue for the whole load, then a single step to
  `(53,196,48)` (native gameplay green) at a specific wall-clock second,
  held stable afterward. Cross-referenced against `events_debug.txt`'s
  timestamped state log from the same run and found
  `CampaignManager.onStartInGame` fires in that exact same second --
  already a confirmed/used hook, and already correctly gated on valid
  HP/weapon context in `events_led.lua`.
- The actual bug: a *different*, already-existing path,
  `adaptive_gameplay_signal()` (triggered by
  `PlayerManager.updateAdaptiveFeedBack` and friends, added as death/
  Continue recovery), has no guard against firing on the very first load
  of a session. `events_debug.txt` showed it flipping
  `gameplay_outputs_enabled` true ~6 seconds before `onStartInGame` (and
  therefore ~6 seconds before Capcom's own transition) on a fresh load --
  HP/PlayerManager data goes valid mid-level-streaming, well before the
  player actually gains control.
- Fixed by adding `ever_started_in_game` (set `true` inside the
  `onStartInGame` handler) and gating `adaptive_gameplay_signal` on it, so
  it only acts as recovery after a real `onStartInGame` has happened at
  least once this session -- exactly its originally intended death/
  Continue-recovery role -- and the very first load always waits for the
  real hook, matching Capcom's own timing.
- **Hardware-confirmed**: a fresh load now lights the custom lightbar in
  sync with real gameplay start instead of during the loading screen, and
  a death/Continue cycle confirmed `adaptive_gameplay_signal`'s recovery
  role still works correctly.

### Fixed (trigger watcher crashed entirely under the new lightbar/Mic pulse rate, 2025-06-29)
- Live in-game symptom: with `IPC.lightbar_enabled` on, switching to any
  empty-ammo weapon pulsed the lightbar/Mic LED for a few seconds, then
  the physical lightbar and ammo indicator went dark while the Mic LED
  froze stuck *on* -- yet the Lua LED bus (REFramework console) kept
  showing live, correctly-changing `ammo_empty` values the whole time.
  That split (Lua healthy, hardware dead) pointed at the external process,
  not Lua: `Get-Process` confirmed `DualSenseEnhancedTransport`
  had exited entirely (not hung, not respawned).
- Root cause in `trigger_watcher.log`: an uncaught
  `System.IO.InvalidDataException: Could not read a stable trigger command`
  from `CommandFile.ReadStable`, propagating out of `Program.Watch()` and
  killing the whole process. `ReadStable` requires two reads of
  `trigger_command.json` 10ms apart to come back byte-identical, retrying
  5 times before throwing; the continuous lightbar/Mic pulse now writes
  that file fast enough (every couple of frames) that the window
  occasionally never finds a quiet 10ms gap, and the resulting exception
  was never caught at the call site (unlike the adjacent gyro-sample read,
  which already had this exact "transient hiccup must not kill the
  watcher" guard).
- Fixed by wrapping the `CommandFile.ReadStable` call in `Watch()`'s own
  try/catch: on failure, log "Command read unstable, skipped" and continue
  the loop instead of propagating, applying the last-known command this
  iteration and retrying next tick.
- Found a second bug while fixing this: `DuaLibBackend.Reset()` never
  reset the Mic LED (`SetMicLight(0)`), only triggers and the lightbar --
  this is why the Mic LED specifically froze *on* rather than going dark
  like the lightbar/indicators did when the process died (even on a clean
  exit path, Mic LED would never have been reset). Added
  `_micLightOwned` tracking (mirrors `_lightBarOwned`) and a
  `SetMicLight(0)` call in `Reset()`.
- Rebuilt, redeployed `DualSenseEnhancedTransport.exe`, restarted
  `DualsenseAudioBridge.exe` so it respawns the watcher fresh.
- **Hardware-confirmed**: repeated the same empty-ammo weapon-switch test
  with `IPC.lightbar_enabled` on -- no stutter, lightbar/indicator/Mic LED
  all kept working normally, no crash.

### Fixed (duaLib lightbar stuck on last test color after process exit, 2025-06-29)
- Discovered while hardware-testing the `AllowLedColor` fix above: after a
  short `--test-lightbar` run, the physical lightbar stayed stuck on the
  test color instead of turning off, across several repeats. A run with a
  long `Thread.Sleep` before its reset call always cleared correctly; a
  short one did not.
- Root cause: duaLib's background read thread is the only thing that
  actually calls `hid_write`; `SetLightBar`/`ResetLightBar` only update an
  in-memory struct for that thread to pick up on its next iteration. With
  no settle time between the final reset and process exit, `Dispose()`
  closing the handle can race ahead of that next iteration, so the reset
  write never reaches the controller -- it's left showing the last color
  that *did* make it out.
- Fixed by adding `Thread.Sleep(50)` to the end of `DuaLibBackend.Reset()`
  (the common path for `Dispose()`, the `--watch` loop's game-exit
  cleanup, and Ctrl+C), rather than patching each `Test*()` method
  individually -- `Dispose()` already calls `Reset()` on every exit path
  when `resetTriggersOnDispose` is true (the default), so this one change
  covers all of them, including the live in-game watcher process exiting
  when RE4R closes.
- **Hardware-confirmed**: a short `--test-lightbar --duration 500` run
  that previously left the controller stuck now reliably turns off after
  the test, repeated twice.

### Fixed (duaLib lightbar AllowLedColor was also forced off, like AllowMuteLight was, 2025-06-29)
- User correctly recalled that the Mic LED's `AllowMuteLight` exemption bug
  (set the enable flag, forgot to wire it into the `readDualsense.cpp`
  guard block) was a pattern worth re-checking for the rejected duaLib
  lightbar path. Confirmed: `AllowLedColor` was unconditionally forced
  `false` in that same guard block, with no exemption -- the earlier
  "duaLib lightbar doesn't work" conclusion was reached while this bit was
  permanently off, so `scePadSetLightBar`'s direct `LedRed/Green/Blue`
  writes could never have reached the wire regardless of any race against
  Capcom.
- Added `controller.lightBarOverrideEnabled` (mirrors
  `playerIndicatorsEnabled`/`micLightEnabled`), set by `scePadSetLightBar`
  along with a `wasDisconnected = true` force-resend (same reasoning as
  `scePadSetMicLight`: a fresh process's zero-initialized struct can make a
  new value look like "no change" against stale hardware state).
- **First pass also repeated the exact same mistake**: set the new flag in
  `scePadSetLightBar` but forgot to actually exempt `AllowLedColor` in the
  guard block. Caught immediately by a clean isolated `--test-lightbar`
  CLI hardware test (outside the game, no Capcom involved) showing no
  color change. Fixed by wiring `AllowLedColor = controller.lightBarOverrideEnabled`
  where the unconditional `false` used to be.
- **Hardware-confirmed** with the real fix: `--test-lightbar` now lights
  the controller magenta, isolated from the game.
- **Open question, not yet retested**: does this change the live in-game
  conclusion (`IPC.lightbar_enabled` losing to Capcom)? The earlier
  "Capcom wins the per-frame race" finding was reached while this
  permission bit was also off, so that test was confounded by two bugs at
  once. Worth a clean live retest now that the protocol-level permission
  is actually correct -- it may still lose the frequency race, or it may
  not have been a fair test before.

### Fixed (unrelated audio events cut each other off, 2025-06-29)
- `SoundPlayer` used to track a single global "currently playing" slot:
  every `Play()` call stopped whatever was already playing first,
  regardless of which event it was. Reported symptom: using a healing
  item from the inventory played the heal sound, but immediately closing
  the inventory cut it off with the inventory-close sound. This could
  happen for any two different events firing close together, not just
  this pair.
- Fix: `SoundPlayer` now plays each event name on its own independent
  channel (`Play(channel, ...)`/`Dictionary<string, Channel> _channels`
  in `SoundPlayer.cs`). A new sound only interrupts a previous one if it's
  the *same* event re-firing (so e.g. the low-HP heartbeat, re-emitted
  every beat, still cleanly replaces itself instead of stacking). Sounds
  on different channels mix concurrently through WASAPI shared mode
  instead of one cutting the other off. `EventWatcher.Dispatch` now
  passes `eventName` as the channel and calls `_player.StopChannel("low_hp")`
  for `low_hp_end` instead of the old global `_player.Stop()` (which would
  otherwise still kill unrelated concurrent sounds).
- Rebuilt and redeployed `DualsenseAudioBridge.exe`; verified via SHA-256.
  User confirmed in-game: healing in inventory then immediately closing
  it no longer cuts the heal sound off.

### Fixed (Capcom lightbar color diagnostic logged nil/nil/nil, 2025-06-29)
- `native_feedback.lua`'s opt-in "Log Capcom lightbar calls (research)"
  diagnostic (`native_lightbar_debug.txt`) always logged `r=nil g=nil
  b=nil`. Root cause: `arg_object()` reads hook arguments via
  `sdk.to_managed_object`, which only works for reference-type managed
  objects -- `via.Color` is a value type passed by pointer, so it always
  returned `nil`. Added `arg_valuetype(args, index, type_name)` using
  `sdk.to_valuetype` instead, and switched the diagnostic to use it for
  the color argument. Not yet hardware-confirmed; user will retest later.

### Changed (HP resume fade removed, 2025-06-29)
- User wants the HP lightbar to return to full brightness immediately
  after an event (parry/damage/heal/grab/etc.) releases it, not ramp
  10%->100% over `DualSenseEnhancedFeedback.hp_resume_fade_duration` frames. Removed the fade
  trigger/application logic from `feedback_writer.lua`'s `get_active_led()` --
  HP now returns at full brightness on the very next frame. Left
  `DualSenseEnhancedFeedback.hp_resume_fade_duration`/`hp_resume_fade_remaining`, the UI slider,
  and the persisted setting in place but inert (`hp_resume_fade_remaining`
  is never set above 0 anymore) rather than ripping out the persisted
  setting key, since `DualSenseEnhanced.lua` was being edited concurrently by
  another session at the time.

### Changed (UI: top-level regroup + renames, NOT in-game tested, 2025-06-29)
**For other agents:** this is a pure `DualSenseEnhanced.lua` UI restructuring
(layout/labels only). No module logic, hooks, or persisted settings keys
changed. User explicitly said they will not test this in-game this
session -- treat the structural change as unverified until someone opens
the REFramework menu and confirms it renders without Lua errors and every
control still maps to the same underlying global it did before.
- Promoted `Mic LED` out of `Ammo Indicator` into its own top-level section
  (still reads/writes the same `MIC`/`AMMO.mic_led_*` fields; the ammo-driven
  Mic LED checkboxes moved with it into a "Ammo-driven Mic LED effects"
  sub-block of the new section).
- Promoted `Native Gyro` out of `Advanced / Diagnostics` into its own
  top-level section, renamed to `Gyro Aim`. No internal logic touched.
- Renamed `Audio` -> `Speaker Audio`.
- Renamed `Events (Grab / Parry)` -> `Combat Events`.
- New top-level order: Master Switch, Status, Config, HP Lightbar, Ammo
  Indicator, Mic LED, Speaker Audio, Combat Events, Gyro Aim, Advanced /
  Diagnostics (Event Monitor, Sound Event Diagnostics, Radio Dialogue
  (Experimental), Capcom Haptics Diagnostics, Console).
- `imgui.tree_node`/`imgui.tree_pop` call counts verified balanced (28/28)
  after the move; no manual in-game check was performed.
- Does not touch any separate baseline-mod UI.

### Fixed (stutter from today's continuous LED pulses, 2025-06-29)
- User reported the game started stuttering after the `ammo_empty`/
  `hp_danger` continuous-pulse changes earlier today. Root cause: both
  pulses pushed a near-continuous brightness value to the LED bus and
  called `flush()` every single frame (previously once every ~20-30
  frames for the old hard blink), and almost every frame produced a
  distinct rounded RGB value -- unlike the old 2-state blink, which only
  ever produced 2 distinct colours per cycle. In native mode this multiplies
  through `NATIVE.apply`/`apply_lightbar`'s managed `share.hid.Device`
  calls and the always-firing `device_update_post_hook` enforcement,
  visible in the Config UI counters (Lightbar writes / Post-update
  lightbar enforces both in the thousands after a short session).
- Fixed in both `ammo_led.lua` and `hp_led.lua`: phase still advances every
  frame (correct real-time pacing), but the actual LED bus push/`flush()`
  is now throttled to once every `pulse_push_interval` frames (new field,
  default 2) and brightness is quantized to `pulse_steps` discrete levels
  (new field, default 12) before being written. Consecutive pushes now
  often resolve to the same colour and get deduped by
  `native_feedback.lua`'s existing signature check, cutting real HID
  write/enforcement volume while remaining visually smooth (12 steps is
  still far smoother than the old 2-state blink).
- **Hardware-confirmed (2025-06-30)**: stutter resolved; user confirmed
  no stutters in extended empty-mag and low-HP sessions.

### Changed (hp_danger: pure red pulse, no orange substitute, 2025-06-29)
- User wanted the low-HP heartbeat to pulse pure red without ever shifting
  to orange. Replaced `hp_led.lua`'s on/off `blink_state` (full
  `vital_danger_rgb` color vs literal `0,0,0` black, toggled once per
  `danger_blink_rate` frames) with the same continuous-pulse style just
  used for `ammo_empty`: `vital_danger_rgb` now takes a `pulse_factor` and
  a per-frame sine oscillation between `LED.pulse_min_brightness` (new,
  default 0.25) and full brightness multiplies into it. Since `vital_danger_rgb`
  only ever returns `(brightness, 0, 0)`, this is red-only at every phase --
  removed `blink_state` entirely (it's gone from the file, not just unused).
- Removed `native_feedback.lua`'s orange (`255,70,0`) black-rest substitute
  for `led_name == "hp_danger"` -- it existed only because the old hard
  on/off blink's black phase didn't render reliably on the native lightbar;
  with no literal black phase left to substitute, it pulses pure red there
  too now.
- `dualib_trigger_ipc.lua`'s `hp_danger_mic_mode()` (the Mic LED sync added
  earlier today) can no longer detect on/off phase by checking r/g/b
  against `0,0,0`, since that condition no longer occurs. Added
  `LED.danger_pulse_on` (new field on `hp_led.lua`'s `LED` table, set
  alongside `danger_pulse_factor` every pulse tick) and switched the mic
  sync to read it directly instead of inspecting color magnitude.
- **Hardware-confirmed (2025-06-30)**: lightbar pulses pure red at low HP
  with no orange; Mic LED stays in sync via `LED.danger_pulse_on`.

### Changed (UI rename + Advanced/Diagnostics grouping, 2025-06-29)
- `DualSenseEnhanced.lua`: renamed the root REFramework menu node from "DualSense
  LED" to "RE4R DualSense Enhanced Edition".
- Consolidated every opt-in/experimental/research panel into one collapsed
  "Advanced / Diagnostics" group at the bottom of the UI: `Native Gyro`,
  `Event Monitor`, `Sound Event Diagnostics` (moved out from under `Audio`),
  `Radio Dialogue (Experimental)`, `Capcom Haptics Diagnostics`, and
  `Console`. Stable user-facing sections (`Status`, `Config`, `HP Lightbar`,
  `Ammo Indicator`, `Audio`, `Events`) keep their previous top-level order
  and behavior unchanged. No logic was touched in any moved panel, only
  their position/nesting in `re.on_draw_ui`.
- Does not touch any separate baseline-mod UI.

### Added (Mic LED synced to empty-mag lightbar pulse, 2025-06-29)
- Same lockstep approach as the low-HP heartbeat sync, applied to the
  empty-mag pulse: `ammo_led.lua` now exposes `AMMO.empty_pulse_active`
  (true while the empty-mag lightbar pulse owns `ammo_empty`) and
  `AMMO.empty_pulse_on` (this frame's on/off phase of that pulse).
  `dualib_trigger_ipc.lua`'s `mic_mode_for()` reads these directly and
  drives the Mic LED with manual On/Off instead of duaLib's
  firmware-driven Breathing mode, which animates on its own timing and
  would not stay in sync with the lightbar.
- `mic_led.lua`'s other use of Pulse mode (the short reload-finish
  blip, via `MIC.pulse_reload`) has no lightbar pulse to sync to --
  `empty_pulse_active` is false during that case, so it keeps the
  original Breathing mapping unchanged.
- **Hardware-confirmed (2025-06-30)**: Mic LED pulses in lockstep with the
  amber lightbar pulse on empty mag with `IPC.mic_enabled` on.

### Changed (ammo_empty lightbar: smooth pulse instead of hard blink, 2025-06-29)
- User reported `ammo_empty`'s hard on/off lightbar blink (full color vs
  literal `0,0,0` black every `ammo_blink_rate` frames) was not reliably
  visible in native mode, while `hp_danger`'s continuous brightness pulse
  (`vital_danger_rgb`, never a literal black frame) read as a smooth and
  clearly visible red/orange pulse. Changed `ammo_led.lua`'s empty-mag
  lightbar feedback to the same style: a continuous sine-based brightness
  oscillation between `AMMO.pulse_min_brightness` (new, default 0.25) and
  full `AMMO.color_empty`, updated every frame instead of once per
  `ammo_blink_rate` cycle (period is `ammo_blink_rate * 2` frames). Mic LED
  and the 5-LED indicator update on the same per-frame cadence now too
  (previously gated behind the same once-per-cycle throttle); both are
  idempotent so this is a frequency increase, not a behavior change for
  them. The `weapon_changed` instant-trigger logic from the prior fix is
  kept (now just resets `blink_cnt` to 0 -- continuous updates make the old
  "skip to the end of the cycle" trick unnecessary).
- **Hardware-confirmed (2025-06-30)**: user confirmed empty-mag pulse is
  visible in native mode. Root cause of original hard-blink invisibility
  was not isolated, but the continuous-pulse style sidesteps it.

### Added (Master mod switch + settings autosave, 2025-06-29)
- `feedback_writer.lua`: new `DualSenseEnhancedFeedback.set_master_enabled(enabled)`. Disabling snapshots
  and force-disables `HPLed`/`AmmoLed`/`EventsLed`/`DualSenseEnhancedAudio`/
  `DualSenseEnhancedWwiseAudioRouter`/`DualSenseEnhancedSoundEventDiag`/`DualSenseEnhancedRadio`/`DualSenseEnhancedMicLED`/
  `NativeGyro`/`DuaLibTriggerIpc`, clears the LED bus/indicator/Mic LED, and
  sets `output_mode = "off"`; re-enabling restores the pre-disable snapshot.
  Note: this only stops the mod's own output/IPC — it cannot terminate the
  external `DualsenseAudioBridge.exe`/`DSX_UDPClient.exe`/trigger-watcher
  processes from the Lua sandbox (no `os.execute`); they go idle instead.
- `DualSenseEnhanced.lua`: new "DISABLE MOD / ENABLE MOD" button at the top of the
  UI, wired to `DualSenseEnhancedFeedback.set_master_enabled`.
- `settings.lua`: new debounced autosave. A `current_signature()` snapshot
  comparison runs every `autosave_interval_frames` (default 90, ~1.5s) via
  `re.on_application_entry("UpdateBehavior", autosave_tick)`; it writes only
  when the serialized settings actually changed since the last save, so
  dragging a slider does not hammer the settings file. `SETTINGS.autosave_enabled`
  defaults to `true`; the existing manual Save/Load/Reset buttons are
  unchanged and remain the explicit profile snapshot/restore path.
- `DualSenseEnhanced.lua` Config section: added an "Autosave" checkbox and status
  line next to the existing Save/Load/Reset buttons.

### Added (experimental: duaLib-owned native lightbar, 2025-06-29)
- `DualSenseEnhancedTransport`: `DuaLibBackend` now optionally loads
  `scePadSetLightBar`/`scePadResetLightBar` (mirrors the existing optional
  `scePadSetPlayerIndicators` pattern; missing exports never block startup).
  Added `--test-lightbar` CLI command.
- `trigger_command.json` schema gained an optional `"led":{"r","g","b"}`
  field (`CommandFile.cs`); the watch loop applies it independently of the
  L2/R2/indicator diff, and `_backend.Reset()` now also resets the lightbar
  if the watcher had taken ownership of it.
- `dualib_trigger_ipc.lua`: new opt-in `IPC.lightbar_enabled` flag (default
  off). When set, the IPC tick reads the active LED color from
  `DualSenseEnhancedFeedback.get_active_led()` (same source `native_feedback.lua` polls) and emits
  it as the `led` field, gated by the same native+gameplay-ready condition as
  triggers/indicators.
- `native_feedback.lua`: `apply_lightbar()` now checks
  `DuaLibTriggerIpc.lightbar_enabled` first. When true it stops issuing its
  own managed `share.hid.Device` write and post-update enforcement (so the
  watcher's direct HID write is the only one reaching hardware) while still
  keeping `lightbar_pre_hook` blocking Capcom's native calls whenever an LED
  source is active. Goal: replace the existing post-update enforcement race
  (which still let a flicker slip through) with a single external writer.
### Added (Mic LED synced to low-HP heartbeat, 2025-06-29)
- `dualib_trigger_ipc.lua`: new `hp_danger_mic_mode()` reads the same
  per-frame `DualSenseEnhancedFeedback.get_active_led()` snapshot the lightbar itself uses
  (`hp_led.lua`'s danger heartbeat blink, consumed identically by
  `native_feedback.lua`'s lightbar tick). When `led_name == "hp_danger"`,
  returns On during the colored/lit phase and Off during the black-rest
  phase that `native_feedback.lua` substitutes with orange. Both the
  lightbar and the Mic LED now derive their on/off phase from the exact
  same frame's value written by `feedback_writer.lua`'s single
  `tick_led_sources()`, so they cannot drift out of sync against each
  other (no separate timer on the Mic LED side).
- `mic_mode_for()` only lets the heartbeat claim the Mic LED while ammo
  isn't otherwise using it (raw mode Off), mirroring the lightbar's own
  priority table where `ammo_empty` (20) outranks `hp_danger` (1).
- **Not yet hardware-confirmed.** Needs a real low-HP test with
  `IPC.mic_enabled` on to verify the Mic LED visually pulses in lockstep
  with the orange lightbar heartbeat.

### Fixed (mic LED still not working: forgot to redeploy the file with the actual fix, 2025-06-29)
- After adding `mic_mode_for()`/`encode_mic`/the `mic` field to
  `dualib_trigger_ipc.lua`, only `DualSenseEnhanced.lua` (UI checkbox) and
  `mic_led.lua` got redeployed to the game folder afterward --
  `dualib_trigger_ipc.lua` itself was never copied again, so the live
  session kept running a build without `mic_mode_for` at all. Caught via a
  full sha256 sweep of every deployed `.lua` file against its source after
  the previous two fixes still didn't work in-game. Deployed the correct
  version.
- Same sweep also found `feedback_writer.lua`'s `DualSenseEnhancedFeedback.set_master_enabled` (the
  Master Switch backend) was never deployed even though the corresponding
  UI button in `DualSenseEnhanced.lua` was -- unrelated to Mic LED, predates this
  session, but the button was a silent no-op without it. Deployed.
- Lesson: after editing a file across multiple turns, diff/hash *every*
  touched file against its deployed copy before declaring a feature ready
  to test, not just the one most recently edited.

### Fixed (mic LED via duaLib never sending a real mode, 2025-06-29)
- `IPC.lightbar_enabled`/`IPC.mic_enabled` were added to the UI but never
  wired into `settings.lua`'s save/load, unlike `IPC.enabled`/
  `indicators_enabled`. Every `Reset Scripts` or game restart silently
  reset them to off. Fixed by adding both to the save payload and the
  restore path. Added a rule to `AGENTS.md`: any new toggle must get its
  persistence wired in the same patch that adds it.
- Deeper bug even with the checkbox genuinely on: `mic_led.lua`'s
  `MIC.last_mode_raw` was only ever set inside `queue_mode`, which
  `MIC.set_empty`/`MIC.pulse_reload` only call on a real state *transition*
  (`if active == empty_active then return false end`). A session that
  never crosses an empty<->non-empty edge (e.g. testing with a full
  magazine, or before the first reload) left `last_mode_raw` at its
  initial `nil` forever, so `dualib_trigger_ipc.lua`'s `mic_mode_for()`
  always returned `nil` and the watcher log showed `Mic=unchanged` on
  every single tick regardless of the checkbox state. Fixed by
  initializing `MIC.last_mode_raw` to `MIC.modes.off` instead of `nil`, so
  there is always a real baseline value to send once `IPC.mic_enabled` is
  on, even before any empty/reload transition has happened.
- **Not yet hardware-confirmed** for the real empty-mag/reload-finish
  pulse through the full live path; only the persistence and nil-default
  bugs are fixed so far. Needs a retest: equip a weapon, fire it empty
  with `IPC.mic_enabled` on, confirm the Mic LED pulses.

### Fixed (instant empty/last-bullet feedback on weapon switch, 2025-06-29)
- `ammo_led.lua`: drawing a weapon that is already empty (or down to its
  last bullet) only showed the empty/last-bullet LED, indicator, and Mic
  LED pulse after waiting for the existing `ammo_blink_rate` throttle
  (~20 frames / ~0.3s at 60fps) to tick over, because `set_mic_empty`/
  `update_indicator` only run inside that throttle's `if blink_cnt >= ...`
  branch. Added a `weapon_changed` check that pre-loads `blink_cnt` to one
  short of the threshold whenever the weapon ID changes while
  empty/last-bullet, so the very next frame's increment crosses the
  threshold and fires immediately instead of waiting out a blink cycle.
  Applies to both DSX and native/duaLib Mic LED paths since both read from
  this same module.

### Added (Mic LED via duaLib, 2025-06-29)
- Added `scePadSetMicLight(handle, mode)` to the duaLib fork
  (`duaLibUtils.hpp`/`duaLib.h`/`duaLib.cpp`): new `controller.micLightEnabled`/
  `micLightMode` fields, consumed in `readDualsense.cpp` to override
  `MuteLightMode`/`AllowMuteLight` ahead of the physical-mute-button toggle.
- **Found and fixed the real reason the first build didn't light up**:
  `readDualsense.cpp` has a guard block (intentionally added for the
  trigger-only transport) that force-resets most `Allow*` output flags to
  `false` every read cycle so this process doesn't fight the game/Windows
  for unrelated report sections. `AllowPlayerIndicators` was already
  exempted there; `AllowMuteLight` was not, so the override from earlier in
  the function got silently wiped before the `hid_write`. Added the same
  exemption for `AllowMuteLight` gated on `micLightEnabled`. This also
  explains why the lightbar attempt below never even got a fair fight
  against Capcom: `AllowLedColor` is unconditionally forced `false` in that
  same block, so duaLib's lightbar write was a no-op at the protocol level,
  not just a frequency-losing race.
- Compiled the updated duaLib fork from source with the bundled
  `llvm-mingw` toolchain (`x86_64-w64-mingw32-clang++ -std=c++20 -shared
  -static`, linking `libhidapi.dll.a` + `setupapi`/`winmm`/`ole32`/`hid`).
  `-static` is required — a non-static build loads but throws
  `DllNotFoundException` for a missing libc++ runtime dependency once
  P/Invoked from the .NET watcher. Saved as
  `third_party/build/duaLib.mic-light.dll` (the deployed `duaLib.dll` at that
  stage; superseded by later lightbar-allowled builds).
- `DuaLibBackend`/`Program.cs`: optional `scePadSetMicLight` export
  (`SupportsMicLight`/`SetMicLight`), new `--test-mic-light` CLI command,
  and a `mic` field in `trigger_command.json` applied independently in the
  watch loop.
- `dualib_trigger_ipc.lua`: new opt-in `IPC.mic_enabled` (off by default).
  Reads `mic_led.lua`'s `MIC.last_mode_raw` (added there, tracked
  unconditionally regardless of `MIC.enabled`/output mode) and remaps
  DSX's On/Pulse/Off (0/1/2) to duaLib's `MuteLight` Off/On/Breathing
  (0/1/2) before sending.
- **Hardware-confirmed**: `--test-mic-light --mode 1` lit the Mic LED,
  independent of RE4R/DSX, after the `AllowMuteLight` fix.
- **Found and fixed a second bug**: turning the LED back off in a *new*
  process invocation (`--test-mic-light --mode 0`) silently did nothing.
  Root cause: `SetStateData::operator==` (used to decide whether
  `hid_write` actually fires) compares only field values, and a freshly
  constructed `controller` struct already zero-initializes
  `MuteLightMode` to `MuteLight::Off (0)`. Requesting Off from a fresh
  process therefore looks like "no change" to duaLib even though the
  physical controller is still lit from a *previous* process's last
  command -- there is no real hardware readback, only duaLib's own
  in-memory belief about current state. Fixed by setting
  `controller.wasDisconnected = true` inside `scePadSetMicLight`, the same
  force-resend lever this codebase already uses elsewhere (BT
  reconnect, `letGo()`) to guarantee the next read cycle's `hid_write`
  fires regardless of the stale-equality coincidence. Self-clears after
  one successful write.
- **Hardware-confirmed end-to-end**: mode 1 on, mode 0 off, both reflected
  immediately on the physical LED across separate process runs.
- **Not yet confirmed in real gameplay** through the full
  `ammo_led.lua -> mic_led.lua -> dualib_trigger_ipc.lua -> watcher`
  path with `IPC.mic_enabled = true`.

### Fixed (player indicators via duaLib, 2025-06-29)
- The deployed `reframework/data/DualSenseEnhanced/duaLib.dll` predated the
  `scePadSetPlayerIndicators` export and silently no-op'd indicator commands
  (the optional-export guard in `DuaLibBackend`/`Program.cs` masked this —
  `SupportsPlayerIndicators` was false, so nothing ever broke loudly).
  Found a matching build already in the repo
  (`third_party/build/duaLib.ammo-indicators.dll`, identical export set plus
  this one), verified its `scePadSetPlayerIndicators` implementation is
  fully wired (`readDualsense.cpp` maps the mask onto
  `PlayerLight1..5`/`AllowPlayerIndicators` every read cycle), and deployed
  it in place of the old `duaLib.dll` (old one backed up alongside it).
  Backed up the pre-swap exe build too
  (`DualSenseEnhancedTransport.exe.pre-lightbar.backup`).
- **Hardware-confirmed**: `--test-indicators --mask 31` lit all 5 player
  LEDs and changed brightness, independent of RE4R/DSX.
- Also clarified the real runtime wiring: `DualsenseAudioBridge.exe` (not
  the standalone transport exe run manually) is what spawns
  `DualSenseEnhancedTransport.exe` as a child process, gated on
  `trigger_transport.ready` flipping to `"ready"` (native mode +
  `EVENTS.in_game`), polled every 250ms (`Program.cs` in
  `DualsenseAudioBridge`). It kills any leftover instance first because the
  transport is single-instance via a named mutex. Restarting the bridge
  after replacing `duaLib.dll` was necessary because the old child process
  held the file handle open.
- **Not yet confirmed in real gameplay** with
  `IPC.indicators_enabled = true` end-to-end through `dualib_trigger_ipc.lua`
  — only the isolated `--test-indicators` CLI path is hardware-verified so
  far.

- **Hardware-tested 2025-06-29, result: not viable for lightbar ownership.**
  With `IPC.lightbar_enabled = true`, the watcher's `scePadSetLightBar` calls
  did land (confirmed via `Led=(r,g,b)` in `trigger_watcher.log`), but Capcom's
  native color won visually anyway. Root cause: `share.hid.Device.update()`
  re-writes the full compound HID report, including the cached lightbar
  field, every render frame (60+ Hz) regardless of caller. The external
  watcher only writes on JSON-file change and polls at ~50 ms, so it cannot
  win that per-frame race. This is exactly why the original (pre-duaLib)
  approach used a `share.hid.Device.update()` post-hook to re-assert the
  color synchronously in the same frame — that is the structurally correct
  mechanism, not a workaround to replace. Conclusion: leave
  `IPC.lightbar_enabled` off; the duaLib lightbar path stays in the code
  (harmless, opt-in, off by default) for potential future reuse but is not
  a fix for anything. Also: the flicker this was meant to fix was not
  actually visually observed by the user under normal play, so there is no
  known active lightbar bug to chase right now.

### Added (weapon audio — large Wwise mapping pass, 2025-06-27/28)
- Converted reload insert/finish triggers from ammo-count polling to direct
  Wwise event IDs (`wwise_audio_router.lua`, weapon-gated) for SG-09 R,
  Punisher, Red9, Blacktail, Matilda, Riot Gun, Striker, SR M1903, Broken
  Butterfly, Handcannon, Killer7, and Skull Shaker. Fixes the missing-insert
  edge case on magazine-fed handguns (firing only the externally-chambered
  extra round) and replaces several disproven by-ear candidates.
- Rebuilt Stingray's and CQBR's reload mapping entirely from live capture:
  removed the hook-triggered start for both, added a multi-stage Wwise chain
  (`release`/`open`/`safety`/`finish`) using real extracted WAVs in place of
  the previous cross-bank placeholder assets.
- Replaced W-870's and Broken Butterfly's/SR M1903's/Skull Shaker's/
  Handcannon's fixed-delay post-shot or pump-cycle timers with direct
  live-fire Wwise triggers where a confirmed ID exists (W-870's `event_0203`
  two-phase pump cycle works in both live-fire and post-reload contexts with
  no reload-session guard needed; SR M1903's `event_0226` and Broken
  Butterfly's startup `event_0191`/Handcannon's `event_0226` needed extra
  reload-session or ammo-aware gating since the same ID also fires during
  reload or dry fire).
- Added first-time weapon-audio mappings for TMP, Chicago Sweeper, LE 5, and
  Bolt Thrower (no prior catalog), and for Sentinel Nine (reusing SG-09 R's
  WAVs as placeholders pending its own Wwise bank extraction).
- Added dry-fire and last-shot (the shot that empties the magazine) cues for
  SG-09 R, Punisher, Red9, Blacktail, and Matilda. Punisher and Red9's
  dry-fire is a confirmed two-stage Wwise sequence perceived as one click.
  SG-09 R/Punisher reuse their reload-start Wwise ID/WAV for last-shot,
  gated to `ammo=0`.

### Research (weapon audio)
- Confirmed Broken Butterfly's and Handcannon's catalogued post-shot action
  IDs never fire on a live shot outside reload (revolver-type weapons may
  have no live-capturable Wwise ID for this action at all); both keep their
  original fixed-delay timers.
- Confirmed Sentinel Nine (`wp6000`) still has no extractable Wwise bank even
  after a clean `re_chunk_000` re-extraction with all mods disabled, despite
  being listed in the game's full asset manifest; its event IDs remain
  unconfirmed guesses from live capture alone.
- See `docs/MEMORY.md` for the full per-weapon final-state table and the
  general lessons learned (catalog by-ear labels are frequently wrong; the
  "last event before the ammo tick" heuristic is not universal; some Wwise
  IDs are shared across contexts and need extra gating beyond weapon ID).

### Added
- Native gyro presets (Precision/PS5 Feel/Fast Flicks/Stable/Custom) in the
  `Native Gyro` UI, with Precision now the default (yaw 500, pitch 450,
  deadzone 0.020, calibration 1000ms). Added an Invert Y (pitch) toggle and a
  While Holding L2 / Always On activation mode. Manual edits switch the shown
  preset to Custom; all values save/load through `settings.lua`.
- Adaptive trigger presets (Off/Native Only/Light/Enhanced/Strong/Custom) with
  a global intensity multiplier and per-weapon-class (pistol/shotgun/rifle/
  automatic/magnum) multipliers, in a new `trigger_intensity.lua` module. It
  scales the existing native duaLib trigger effects without modifying
  `weapon_trigger_profiles.lua`. Enhanced (default) keeps current confirmed behavior
  unchanged.
- Adaptive trigger profiles were initially tuned using community references as
  a starting point, but are integrated into an independent native DualSense
  pipeline that does not require DSX or Steam Input. Future releases may
  include fully custom-tuned trigger profiles per weapon class.

### Documentation
- Added `docs/NATIVE_HAPTICS_AUDIO_TASK.md`, a handoff for future native
  DualSense LED/controller-speaker/haptics research that explicitly excludes
  the already-confirmed duaLib trigger/gyro work and summarizes the closed
  DSX/native, PlayerManager, adaptive-trigger, and audio-haptics probe paths.
- Updated native gyro documentation now that the feature is hardware-confirmed:
  `DUALIB_HID_BRANCH.md`, `AGENTS.md`, `TASKS_FOR_CODEX.md`, `IDEAS.md`,
  `AUDIO_TASKS.md`, `MEMORY.md`, and the transport README now describe the
  separate `Native Gyro` UI/config, X pitch, inverted-Z yaw, L2/focus gating,
  right-stick arbitration, and the single shared delayed watcher boundary.

### Research
- Re-verified Blacktail (`wp4003`) reload audio via live `postRequestInfo`
  capture instead of by-ear classification. Disproved the previous
  `event_0256` reload-start mapping (never fired in any captured reload) and
  confirmed a stable reload-exclusive pair: `event_0264` then `event_0246`,
  verified with zero false positives against a dedicated aim/lower control
  test. Updated `docs/weapon_audio_catalog/wp4003_blacktail.md` accordingly.
- Found that `event_0274` (Wwise ID `3406633596`), initially suspected as a
  reload-finish cue, is actually a general weapon-lowering/aim-exit event
  unrelated to reload; rejected as a reload cue and documented in `MEMORY.md`
  as a future candidate hook (e.g. gyro auto-disable on aim exit).
- Removed the temporary diagnostic-only `wwise_audio_router.lua`/`SoundMap.cs`
  routes used to identify the above by ear.

### Fixed
- Fixed Blacktail (`wp4003`) reload-insert sound not playing when the
  magazine was already full and only the externally-chambered extra round
  was re-seated (ammo stays at 9/9 the whole reload, so the previous
  ammo-delta trigger in `ammo_led.lua` never fired). `wp4003_reload_insert`
  now routes directly off the confirmed `event_0268` Wwise ID
  (`3172553005`) in `wwise_audio_router.lua`, gated only by weapon ID, with
  no ammo-count dependency. Removed the now-unused `insert` key from
  `wp4003` in `audio_feedback.lua`'s `RELOAD_EVENTS_BY_WEAPON` to avoid a double
  trigger.
- Fixed the same already-full-magazine reload-insert bug for SG-09 R
  (`wp4000`) and Punisher (`wp4001`). The previously catalogued `event_0271`
  (SG-09 R) never fired in any live capture; replaced with `event_0246`
  (Wwise ID `635031351`). Punisher's `event_0260` (Wwise ID `2748519654`) was
  confirmed as the reliable, ammo-independent insert candidate. Both
  `*_reload_insert` routes now live in `wwise_audio_router.lua` gated only by
  weapon ID; removed the corresponding `insert` keys from `audio_feedback.lua`'s
  `RELOAD_EVENTS_BY_WEAPON`. Physically confirmed by the user on the
  controller speaker for normal and already-full-magazine edge-case reloads
  on both weapons.

## Unreleased - Experimental Native Feedback Backend

### Added

- Added an opt-in Wwise/sound event diagnostic logger for weapon-audio
  research. It opens a short capture window around reload requests, reload
  start/insert/finish, hooks candidate `soundlib.SoundManager` and
  `via.simplewwise.Driver` methods, and writes weapon/ammo/reload-context
  traces to `reframework/data/DualSenseEnhanced/sound_event_diag.log`.
- Confirmed `soundlib.SoundManager.postRequestInfo` as the low-latency Wwise
  event timing hook. `onEndOfEvent` remains useful for late event-ID
  confirmation, but it was about 0.545 seconds late for SG-09 R dry fire.
- Added the first confirmed Wwise ID -> audio event route:
  SG-09 R dry fire `event_id=2330373695` (`wp4000` `event_0260`) now emits
  `wp4000_dry_fire` through the audio bridge. The runtime Lua, bridge EXE, and
  WAV were deployed and SHA-256 checked; in-game/controller sync was confirmed.
- Split confirmed Wwise event playback out of `sound_event_diag.lua` into
  `wwise_audio_router.lua`. The router owns always-on confirmed mappings;
  `sound_event_diag.lua` is back to logging/manual-window investigation only.
- Added the opt-in native gyro checkbox marker consumed by the audio-bridge
  launcher, with writes only when its value changes so the launcher cannot
  read a transient empty file. Published and deployed self-contained EXEs
  rather than dependency-requiring build outputs.
- Restored a single watcher owner in native mode: the REFramework plugin now
  launches only the audio bridge, which starts the delayed duaLib watcher with
  the gyro option. This removes the race where an older plugin watcher could
  win the mutex without receiving `--gyro-mouse`.
- Inverted the confirmed native gyro yaw direction and added right-stick
  arbitration: a deliberate right-stick camera input now suppresses gyro
  mouse deltas instead of mixing two camera sources and causing jitter.
- Split native gyro from the experimental trigger IPC UI into its own
  persisted module with sensitivity, deadzone, L2 threshold, and calibration
  controls. It remains attached to the same delayed duaLib watcher to retain
  single controller ownership.
- Added an opt-in L2-gated gyro-to-mouse prototype to the delayed duaLib
  watcher. It maps confirmed USB IMU axes X (pitch) and Z (yaw), calibrates
  resting bias, applies a deadzone, uses a monotonic clock, and injects input
  only while RE4R owns the foreground window. The native UI setting is
  persisted and the launcher passes it only to the next native session. IMU
  reads, axis mapping, and in-game mouse control are hardware-confirmed.
- Added the first read-only native gyro diagnostic to
  `DualSenseEnhancedTransport`. It enables duaLib motion state and
  logs `scePadReadState` angular velocity without mouse injection or
  controller-output writes. `--gyro-log` can also be attached to the delayed
  trigger watcher, preserving its single controller-owner boundary. USB
  hardware testing confirmed stable IMU samples.
- Confirmed the complete native duaLib trigger path in RE4R: existing weapon
  mappings now reach L2/R2 through `dualib_trigger_ipc.lua`, while Capcom
  haptics, custom native lightbar, controller-speaker audio, and stable save
  loading remain active.
- Added a delayed in-game start boundary. The watcher may start with RE4R, but
  does not load duaLib or open the controller until Lua writes the ready marker
  after `CampaignManager.onStartInGame`; this replaced the unsafe early-HID
  attempt that could crash during save loading.
- Fixed settings persistence: Save/Load now use the same REFramework data-root
  file, `RE4R_DualSense_settings.lua`, and compile saved content read through
  `io.open` rather than a differently rooted `loadfile` call.
- Published self-contained current builds of `DualsenseAudioBridge.exe` and
  `DualSenseEnhancedTransport.exe`; deployment was SHA-256 checked.
- Documented the native gyro-to-mouse boundary. Motion state enables IMU reads
  only; the calibrated, aim-gated input mapper must explicitly inject mouse
  deltas and handle RE4R's keyboard/mouse prompt switch.
- Added the isolated
  `speaker/DualSenseEnhancedTransport` duaLib MVP.
- The standalone x64 C# transport dynamically loads `duaLib.dll`, verifies a
  USB DualSense, applies `scePadSetTriggerEffect`, and resets both triggers on
  normal shutdown.
- Added weak manual L2/R2 tests, explicit output-conflict acknowledgement,
  single-instance protection, offline ABI self-test, and an experimental JSON
  watch boundary for later reuse of the existing weapon mappings.
- The transport builds successfully and its 120-byte trigger-packet self-test
  passes. The standalone USB weak-L2 hardware test is confirmed: resistance
  was active for 800 ms and both triggers reset normally. RE4R coexistence is
  still pending; it is not loaded or started by the stable mod.
- Built local AMD64 `duaLib.dll` and `hidapi.dll` from pinned official source
  revisions with portable LLVM-MinGW, placed them beside the experimental EXE,
  and verified the required duaLib exports without opening the controller.
- Fixed the first hardware-test launcher after `scePadOpen(0, 0, 0)` returned
  `SCE_PAD_ERROR_INVALID_ARG`; duaLib player slots are one-based, so the
  transport now opens slot `1`.
- Added a short retry window after `scePadOpen` because duaLib discovers USB
  controllers on a background thread and can briefly return
  `SCE_PAD_ERROR_DEVICE_NOT_CONNECTED` while the opened slot is still binding.
- First RE4R coexistence test: weak L2 feedback and Capcom haptics worked.
  RE4R's solid-blue lightbar at startup is the normal baseline, not an observed
  duaLib regression. Custom-lightbar coexistence still requires an explicit
  gameplay-event check; the transport remains isolated in the meantime.
- Native-mode retest: custom lightbar, Capcom haptics, and the experimental
  weak-L2 effect worked with DSX closed and Steam Input disabled, but the
  audio-only WASAPI bridge did not produce controller-speaker output. This is
  recorded as a current diagnostic regression; its previously confirmed native
  speaker result must be revalidated from a manual test event and bridge log.
- Identified the speaker regression: after the weak-L2 test, the bridge still
  opened `DualSense Edge Wireless Controller` and played WAVs, but even the
  Windows test tone was silent. A teardown-only patch was rejected after it
  left trigger resistance stuck. The revised isolated duaLib build preserves
  the controller's audio route instead of forcing duaLib's initial audio-path
  reset, and uses a direct trigger-only close/reset report with no LED, audio,
  mute, volume, or rumble/haptics fields. Rebuilt the x64 DLL and passed the
  offline packet self-test plus required-export check; fresh controller
  verification is pending.
- The first revised DLL still silenced the speaker endpoint and left trigger
  resistance stuck. The current revision keeps the direct trigger-only reset
  and suppresses every non-trigger output-enable flag in duaLib's background
  reader, preventing its reconnect report from applying audio routing. It is
  hardware-confirmed with RE4R active: Windows speaker audio, `Play Test
  Sound`, native haptics, and custom lightbar still work after the weak-L2
  test. Continuous watcher/gameplay-event integration was pending at this
  stage; it is confirmed by the newer delayed-autostart entry above.
- Extended manual RE4R test confirmed: five-second L2 and R2 effects remained
  stable while aiming, firing, and reloading; native haptics, custom lightbar,
  and controller-speaker audio continued working after each reset. The
  long-running watcher and automatic gameplay-event path were pending at this
  stage; both are confirmed by the newer delayed-autostart entry above.
- Added opt-in `dualib_trigger_ipc.lua` and `04_WATCH_RE4R_NATIVE.bat` for the
  next experimental phase. The Lua bridge converts existing `weapon_trigger_profiles.lua`
  trigger mappings to the isolated watcher command file while native mode is
  active. It started disabled and was not hardware-tested at this stage; the
  persisted opt-in path is now confirmed by the newer entry above.
- Added next-start transport selection. Native is now the default marker and
  launches the audio bridge plus `DualSenseEnhancedTransport --watch`
  from the REFramework launcher; DSX UDP autostart is restricted to explicit
  `dsx` mode. The watcher exits with `re4.exe` and resets both triggers.
- Added opt-in `Native Game API (EXPERIMENTAL)` output alongside stable DualSenseEnhancedFeedback.
- Added `native_feedback.lua` to route the existing lightbar bus through
  RE4R's `share.hid.Device`.
- Added lightbar ownership hooks that suppress Capcom lightbar changes only
  while the custom LED bus owns an active color.
- Added a final lightbar write after `share.hid.Device.update` to override
  Capcom's internally cached lightbar state and remove residual flicker.
- Added backend/device/status/error diagnostics and settings persistence.

### Safety

- Native mode performs no direct HID writes and sends no DSX payload updates.
- DSX remains the default.
- Native adaptive-trigger output was hard-disabled after a confirmed crash.
- Documented that RE4R exposes no native DualSense API for the five
  player-indicator LEDs; ammo indicator and Mic LED remain DSX-only.
- Confirmed normal HP, heal, damage, parry, and event lightbar output in
  native gameplay while Capcom haptics remain active.
- Changed the native low-HP heartbeat to alternate red and orange after black
  and dim-red rest phases failed to produce a visible pulse.
- Confirmed the native red/orange low-HP pulse in gameplay.
- Added read-only PlayerManager adaptive-trigger parameter diagnostics; no
  trigger output methods are called by the monitor.
- Tested the guarded PlayerManager L2 path. No live PlayerManager was exposed
  through the managed-singleton lookup, and the passive `onUpdate` capture hook
  remained idle. Further PlayerManager trigger probing is rejected.
- Added `docs/DUALIB_HID_BRANCH.md` as the handoff for a separate native
  adaptive-trigger transport branch.
- Defined duaLib/direct HID success as preserving Capcom native haptics and
  the confirmed custom native lightbar, not merely producing trigger resistance.

### Research

- Confirmed RE4R's native PC DualSense mode with USB DualSense Edge, Steam
  Input disabled, and DSX closed. Native mode provides correct LED lifecycle,
  low-HP heartbeat, and partial haptics for shots, reloads, damage, and knife
  impacts.
- Confirmed DSX conflicts with native DualSense output ownership: native
  haptics disappear and the lightbar flickers between Capcom and mod/DSX
  states. Native and Custom DSX modes are now treated as separate backends.
- Added read-only diagnostics for `chainsaw.PlayerHapticsController` and
  `soundlib.SoundVibrationManager`, including trigger statistics, controller
  type, active vibration records, and JSON Event Mapper export.
- Tested the PC `IsTargetPlatform` gate. It creates HD/audio records but does
  not register vibration waves or send post-vibration output, while
  suppressing working native effects. Runtime gate use was rejected.
- Built `DualSenseHapticsProbe` v0.3 with 4-channel DSP presets and opt-in
  one-shot/burst HID audio-haptics tests. Native RE4R vibration mode still
  prevented reliable actuator playback, so native coexistence is deferred.
- Confirmed controller-speaker WAV playback remains usable in native
  DualSense mode. The current event-based extracted-WAV implementation remains
  the supported direction.
- Added future research notes for gyro aiming without Steam Input using
  duaLib/libScePad references; implementation is deferred to a separate branch.

### Changed
- Applied the June 25 manual weapon-audio corrections:
  - Broken Butterfly now uses Handcannon `event_0226` for cylinder/cartridge
    ejection, keeps `event_0193` as reload finish, and moves `event_0197` from
    reload insertion to a delayed post-shot family.
  - CQBR now uses `event_0252_01_899314204` for magazine insertion and
    `event_0248_01_872283622` for the final bolt rack.
  - Killer7 now uses `event_0238` for magazine extraction and `event_0224` for
    magazine insertion; the unrelated generic finish cue was removed.
  - Skull Shaker no longer emits its former end-action sound at reload start;
    that family now closes the reload, while
    `event_0204_07_520888437` is a delayed post-shot action.
  - Handcannon now uses `event_0226` for cylinder ejection, `event_0224` for
    reload finish, and `event_0218` for its post-shot action.
- W-870, SR M1903, and Handcannon now suppress their normal post-shot
  cycling when the shot empties the weapon. The skipped cycle is remembered
  and emitted once at the end of the following reload.
- Riot Gun remains on start + insert because no distinct reload-end/bolt-rack
  WAV has been identified.
- Updated the weapon-audio status after the latest in-game pass: SG-09 R,
  Striker, Handcannon, Skull Shaker, SR M1903, Broken Butterfly, and W-870 are
  now confirmed good; Stingray is marked as a regression requiring isolated
  phase testing; CQBR is marked improved but incomplete.
- Corrected weapon reload audio from a physical gameplay pass: removed extra
  finish cues from Striker and Handcannon, removed Stingray's incorrect insert
  cue, and removed CQBR's equip/draw-like finish cue.
- Broken Butterfly and Skull Shaker now schedule their close/cock cue from the
  final ammunition increase on a full reload instead of waiting for generic
  reload-state exit.
- SR M1903 no longer emits its bolt cue as reload finish; the cue is now
  scheduled approximately one second after a shot, following the confirmed
  W-870 pattern.
- Reduced weapon/ammo polling from six to three update frames to lower the
  script-side SG-09 R insertion delay while preserving the previous heartbeat
  interval.
- Marked W-870 reload and delayed post-shot pump timing as physically
  confirmed and intentionally unchanged.

### Added
- Added conservative reload-speaker prototypes for Punisher (`wp4001`), Red9
  (`wp4002`), Blacktail (`wp4003`), and Matilda (`wp4004`). Each profile emits
  a magazine-release/removal family at confirmed reload start and a
  magazine-seat/lock family when loaded ammunition increases. Slide/chamber
  finish cues remain disabled until tactical and empty reloads are compared in
  game.
- Added maintained weapon-audio profiles and curated catalog folders for the
  four remaining Leon-campaign handguns. Intermediate reload layers preserve
  their intended order but are explicitly marked `runtime_unmapped`.
- Corrected representative-WAV misclassifications in the supplied handgun
  analysis: the 17-asset material-switched groups (`wp4001 event_0236`,
  `wp4002 event_0234`, `wp4003 event_0244`, and `wp4004 event_0252`) are
  surface/impact families rather than ordinary single mechanical events.
- Added `speaker/weapon_sound_catalog_v2/`, a curated listening catalog that
  copies runtime WAV files into per-weapon `reload`, `misc`, and
  `unconfirmed` folders. Filenames preserve reload order and include both the
  flat runtime event name and the matched extracted source WAV; `MANIFEST.csv`
  records exact tracing.
- Added preliminary three-phase reload-speaker mappings for all currently
  cataloged rifles and magnums: SR M1903, Stingray, CQBR, Broken Butterfly,
  Killer7, and Handcannon. Only conservative start/insert/finish candidates
  are enabled; unresolved, surface, selector, hammer, and post-shot events
  remain excluded pending gameplay validation.
- Added `docs/weapon_audio_catalog/` with a reusable per-weapon research
  template and rifle profiles for SR M1903 (`wp4400`), Stingray (`wp4401`),
  CQBR (`wp4402`), and a corrected preliminary Broken Butterfly (`wp4500`)
  profile that preserves the audio observations without the erroneous
  pump-action-shotgun interpretation. Added a corrected Killer7 (`wp4501`)
  profile without the inferred gunshot and nonexistent auxiliary-mechanism
  classifications, plus a corrected Handcannon (`wp4502`) profile using
  neutral revolver-action phases instead of magazine/slide terminology.

- `audio_feedback.lua`, `events_led.lua`, `ammo_led.lua`, `DualsenseAudioBridge`: added a persisted prototype for weapon-specific three-phase reload audio. Confirmed reload start, actual loaded-ammo increases, and stable reload-state exit emit separate start/insert/finish sounds for SG-09 R (`wp4000`), W-870, Riot Gun, Striker, and Skull Shaker. Per-shell shotgun loading emits an insert sound for each ammunition increase.
- `ammo_led.lua`: aligned the W-870 post-shot pump cycle with gameplay by delaying the pump-open sound about one second after ammunition decreases, then playing the existing pump-close layer.
- Added deduplicated Wwise reload variants for the initial five weapon
  profiles. Additional cataloged rifles, magnums, and Leon-campaign handguns
  are deployed as unverified prototypes; unsupported weapon banks remain
  silent until classified.
- `audio_feedback.lua`, `item_ids.lua`, `events_led.lua`: enabled category-based item-pickup audio for ammo, pesetas, healing items, resources, grenades, knives, valuables, and Small Key; added Grab QTE input audio.
- `DualsenseAudioBridge`: added automatic random variants for numbered sound files (`parry2.wav`, `parry_2.wav`, `parry-v2.wav`, etc.) with immediate-repeat avoidance. Healing can also alternate between `heal_herb*` and `healing_spray_original*`.
- `DualSenseEnhanced.lua`, `settings.lua`: added persisted toggles for healing, parry, pickup, QTE, and pickup diagnostics.
- Updated the native REFramework launcher to start the audio bridge and the
  existing external `DSX_UDPClient.exe` automatically.
- Added duplicate-process protection and a kill-on-close Windows Job Object for
  UDP clients started by the launcher.
- Added WinDbg crash analysis documenting `nssvpd.sys` from Nefarius Virtual
  Gamepad Emulation Bus G2 2.62.0.0 as the `0xD1` BSOD module.
- `DualsenseAudioBridgeLauncher.dll`: added a native REFramework plugin that
  starts the audio bridge and external UDP client without Lua `os.execute`.
- `DualsenseAudioBridge`: added portable path discovery, automatic migration of
  legacy config paths, UTF-8 file logging, and automatic shutdown with
  `re4.exe`.
- Added compressed portable and framework-dependent compact release builds
  under `speaker/DualsenseAudioBridge/dist`.
- Updated bridge documentation for isolated installation, configuration,
  architecture, testing, and release packaging.
- `audio_feedback.lua`, `DualSenseEnhanced.lua`: replaced the old PowerShell audio test path with JSON event emission for `DualsenseAudioBridge.exe` and added a `Play Test Sound` button to the main Audio UI.
- `events_led.lua`, `audio_feedback.lua`, `DualSenseEnhanced.lua`: added optional `parry` audio emission from the existing confirmed parry handler for latency comparison against HP-polling-based heal audio.
- `audio_feedback.lua`, `DualSenseEnhanced.lua`, `settings.lua`, `DualsenseAudioBridge`: added runtime speaker output selection (`Auto`, `DualSense`, `DualSense Edge`) and per-event speaker volume control from the in-game UI.
- `DualsenseAudioBridge`: cached resolved WASAPI devices so runtime output selection does not enumerate Windows audio endpoints before every sound; this restores low-latency parry playback after the device-selector update.
- `audio_feedback.lua`, `DualSenseEnhanced.lua`: added a diagnostic-only `chainsaw.DropItem.onAcceptPickup` hook that logs item IDs and call counts without emitting audio, for validating a universal item-pickup event before sound mapping.
- `audio_feedback.lua`: fixed pickup diagnostics assuming `args[2]` was the `DropItem`; the hook now identifies the managed `chainsaw.DropItem` argument by runtime type because this build exposes `chainsaw.ContextID` in that slot.
- `audio_feedback.lua`: changed the pickup probe to log the runtime types and values of all hook arguments after confirming `DropItem` is not directly exposed in the observed `onAcceptPickup` argument layout.
- `audio_feedback.lua`: identified `onAcceptPickup` arguments as player `ContextID` plus drop `ContextID`; added a short-lived `DropItem` cache from `cantDoubleBilling` / `updateSleep` to resolve the pickup context back to `getItemID()`.
- `DualSenseEnhanced.lua`: removed unsupported diagnostic `imgui.text_wrapped` usage that caused a missing `TreePop` UI error.
- Added `item_ids.lua` with item ID names and categories from the Auto Pick Up Items v1.3 whitelist; pickup diagnostics now display item name, category, raw ID, and normalized base ID.
- Documented and verified the final portable and compact bridge builds under
  `speaker/DualsenseAudioBridge/dist`.
- Added an explicit audio verification sequence covering device enumeration, manual JSON event playback, timestamp deduplication, and physical controller-speaker output.
- Replaced the earlier PowerShell/source integration gap with the deployed JSON
  event emitter and audio-only C# bridge.
- Corrected audio format documentation: the current bridge supports WAV/MP3/AIFF through NAudio; OGG requires an additional Vorbis dependency and remains unverified.
- Recorded a successful `--list-devices` smoke test of the compiled bridge and detection of both DualSense and DualSense Edge WASAPI endpoints.
- Documented the current playback-test blocker: existing `pickup_sound.wav` / `test_sound.wav` files do not map to the proposed `heal_herb` event filename.
- Confirmed end-to-end controller-speaker playback from a manual JSON event, the in-game `Play Test Sound` button, and the heal event.
- Investigated the observed ~1 second latency and found approximately 0.64 seconds of leading silence in `test_sound.wav`; audio trimming should be tested before bridge-level latency optimization.
- `feedback_writer.lua`, `DualSenseEnhanced.lua`, `settings.lua`: HP lightbar fades from 10% to 100% brightness when control returns from an event effect; duration is configurable in the HP UI and saved with settings.
- Added direct grab-QTE widget lifecycle handling through `LargeActionSign_Grab3GuiBehavior.recieveGuiParam` and `onDeactivateEvent`.
- `events_led.lua`: added Cross edge polling through `via.hid.Gamepad.getMergedDevice(0).get_Button()`, gated by the active grab QTE.
- `events_led.lua`, `DualSenseEnhanced.lua`, `settings.lua`: added a cyan-blue Hookshot lightbar effect using `PlayerBaseContext.get_IsHookShot()` polling, with UI colour control and persisted settings.
- `events_led.lua`, `DualSenseEnhanced.lua`, `settings.lua`: added a purple Fatal Kick lightbar effect using `PlayerBaseContext.get_IsFatalKick()` / `get_IsFatalRoundKick()` polling, with UI colour control and persisted settings.
- `mic_led.lua`, `feedback_writer.lua`: added Mic LED support through the normal `payload.json` writer path.
- `ammo_led.lua`: added Mic LED pulse feedback for empty ammo and reload finish.
- `DualSenseEnhanced.lua`, `settings.lua`: added Mic LED UI controls, status, test buttons, and persisted settings.
- `audio_feedback.lua`: experimental heal sound playback for DSX/Virtual DualSense audio routing.
- `hp_led.lua`: heal detection now triggers `DualSenseEnhancedAudio.play_heal()` alongside the existing heal LED transition.
- `DualSenseEnhanced.lua`: added DualSenseEnhancedAudio load/status and a small Audio UI toggle.
- `audio_feedback.lua`: heal sound path now points to the deployed game folder WAV, with relative project paths as fallbacks.
- `events_led.lua`: added experimental reload flash using `chainsaw.PlayerEquipment.execReloadStart` with `execReload` fallback.
- `DualSenseEnhanced.lua`: added UI colour sliders for reload flash.
- `events_led.lua`: added reload hook diagnostics that print matching `PlayerEquipment` methods when `onReloadStart` is not found.
- Reload diagnostics found `execReloadStart`; `onReloadStart` does not exist in this RE4R build.
- `events_led.lua`: reload LED now persists through reload state using `get_IsTacticalReload` / `isLoopReload` polling with timer fallback.
- `DualSenseEnhanced.lua`: replaced RGB sliders with `imgui.color_edit3` colour pickers for HP, ammo, menu, and event colours.
- `events_led.lua`: reload hook now requires a short reload-state confirmation window before lighting LED, avoiding false reload flashes from aim/start weapon state.
- `ammo_led.lua`: added reload feedback on the 5-player-indicator LEDs based on actual ammo increases.
- `DualSenseEnhanced.lua`: added UI sliders and reset buttons for effect durations in HP, ammo indicator, and event sections.
- `settings.lua`: added manual UI save/load/reset for LED, ammo, event, audio, colour, threshold, and duration settings.
- `monitor.lua`: added an in-game Event Monitor UI list for recent LED/audio/config events.
- `events_led.lua`: added one-shot method diagnostics for Object Explorer finisher candidates `EnemyBehaviorTreeAction_MFSM_EnableKnifeFatal`, `EnemyHeadUpdater.KnifeFatalInfo`, and `Ch1c0HeadUpdaterCommon`.
- `events_led.lua`: added cutscene gate infrastructure that clears LEDs/indicator while active and restores gameplay outputs afterward.
- `events_led.lua`: added movie/cutscene diagnostics for `MoviePlayerInfo`, movie manager candidates, `EventManager`, and `System.Action<chainsaw.MoviePlayerInfo>`.
- `DualSenseEnhanced.lua`: added a temporary `Force cutscene gate` checkbox for validating LED cleanup before a real cutscene hook is confirmed.
- `events_led.lua`: added experimental `MovieManager.isPausingAny()` polling fallback for cutscene LED suppression.
- `events_led.lua`: added, tested, then disabled experimental automatic cutscene gate hooks on `chainsaw.MoviePlayer`, `chainsaw.MovieManager`, `chainsaw.TimelineEventManager`, and `chainsaw.RealTimeTimelineMediator` because their signals were too noisy for stable gameplay LED gating.

### Changed
- Disabled item-pickup ID diagnostics by default now that external item and
  weapon ID lookup databases are available. Pickup recognition and sounds stay
  active, while raw/base IDs, ContextID arguments, and per-pickup entries only
  reach Event Monitor when diagnostics are explicitly enabled for the current
  session.
- Replaced the two fatal-kick alternatives (clean B versus unwanted long
  environmental tail) with three clean layered composite variants: balanced,
  punchy, and heavy. The bridge randomly selects variants while preventing an
  immediate repeat.
- Added a full SG-09 R (`wp4000`) catalog profile comparing manual waveform
  analysis with the gameplay-confirmed runtime mapping. Preserved
  `event_0260` as reload start and `event_0271` as magazine insertion, while
  recording `event_0232–0252` as preliminary component layers and rejecting
  the unverified `event_0252` Fire classification.
- Migrated W-870, Riot Gun, Striker, and Skull Shaker from the combined
  shotgun research file into individual maintained weapon-audio profiles,
  including runtime/test status and corrected per-shell/lever-action
  terminology.
- Added manual-review corrections for SR M1903, CQBR, Killer7, and Handcannon;
  documented `surface_*` groups as confirmed material-routed casing/shell
  impacts and promoted them as high-priority controller-speaker candidates.
- Corrected the weapon audio catalog scope: the current candidate sets are not
  expected to contain primary gunshot audio. Removed preliminary `Fire`
  classifications for SR M1903 `event_0239`, Stingray `event_0223` /
  `event_0250`, and CQBR `event_0235`; these remain unresolved mechanical or
  composite events pending gameplay validation.
- Reload audio mapping corrected from in-game testing: SG-09 R no longer emits the unused `event_0258` finish cue; W-870 pump-open/pump-close events were removed from reload because they belong to the post-shot pump cycle. W-870 reload currently emits only per-shell insertion sounds.
- Added a short post-reload ammo-update grace window so one-round SG-09 R tactical reloads still emit their insert cue. Riot Gun no longer emits its unnecessary finish cue. W-870 now plays its separated pump-open/pump-close assets after an actual ammunition decrease (shot), independently of reload audio.
- Fatal kick now stays black during wind-up, flashes the configured purple at the actual enemy-damage impact, then returns to black until the animation ends; impact duration is configurable in the Events UI and defaults to ~0.5 seconds.
- Parry now performs one full blink over the existing configured duration: selected parry colour for the first half, black for the second half, then normal HP feedback.
- After the first grab-QTE Cross press, pauses between white flashes now use a priority-90 black lightbar state instead of revealing red damage/HP colours.
- `events_led.lua`, `DualSenseEnhanced.lua`: changed grab feedback from a continuous red pulse to a short white input flash, with UI duration control for the flash.
- `ammo_led.lua`, `mic_led.lua`: default reload Mic LED pulse duration is ~1 second.
- `events_led.lua`: parry defaults to a longer blue flash; damage flash duration doubled.
- `events_led.lua`: disabled the experimental reload lightbar effect by default; reload feedback now belongs to the ammo/player-indicator layer.
- `DualSenseEnhanced.lua`: removed the unused reload lightbar colour picker from the Events UI.
- `hp_led.lua`, `ammo_led.lua`, `events_led.lua`: effect durations now use runtime-configurable module fields instead of fixed local constants.
- `hp_led.lua`: low-HP heartbeat now replaces the fixed lower dim threshold while active; the heartbeat HP becomes the start of a pure red `255,0,0` dim range down to 1 HP.
- `hp_led.lua`, `DualSenseEnhanced.lua`, `settings.lua`: added a Vital danger fallback based on the bHaptics mod trail (`get_HeadUpdater` -> `get_Context` -> `getHitPointVital`), with `hp vital` Event Monitor diagnostics.
- `DualSenseEnhanced.lua`: loads `monitor.lua` before effect modules and `settings.lua` after effect modules, so saved settings can apply at startup.
- `settings.lua`: missing settings file is now reported as a normal first-run state, and Save attempts to create `reframework/data/DualSenseEnhanced`.
- `events_led.lua`: finisher diagnostics for `Ch1c0HeadUpdaterCommon` are now filtered to `fatal` methods to avoid huge debug logs.
- `events_led.lua`: automatic cutscene gate actions are disabled for now; the temporary `Force cutscene gate` UI checkbox remains available for manual validation while better cutscene state candidates are researched.
- `hp_led.lua`: HP danger/heartbeat now uses game Vital `Danger`, while caution colour is a visual percentage fallback active below the configurable caution-start ratio until Vital reaches `Danger`.
- `DualSenseEnhanced.lua`: HP UI exposes the caution visual start ratio plus Vital-driven danger behaviour.

### Removed
- Removed the custom `DualsenseDsxBridge` and its release artifacts after it
  caused repeatable in-game stutters.
- Removed UDP and `payload.json` handling from `DualsenseAudioBridge.exe`; it is
  audio-only again.
- Lua `os.execute` bridge launch attempt, which is unavailable in the active
  REFramework sandbox.
- `events_led.lua`: removed the unused `chainsaw.Ch6CommonBodyUpdater.on_low_hp_heartbeat` hook attempt because it is not present in this runtime.
- `hp_led.lua`, `DualSenseEnhanced.lua`, `settings.lua`: removed the experimental Wwise HP-ratio heartbeat fallback.
- `DualSenseEnhanced.lua`: removed the manual `Test low HP heartbeat` UI button after the Vital-based HP system was confirmed.

### Added
- `events_led.lua`: added `CampaignManager.onStartInGameSetup` / `onStartInGameCleanup` hooks as safer Continue recovery candidates than hot `GameStateInGame` lifecycle methods.
- `events_led.lua`: added Continue/loading/gameplay-state diagnostics for candidate managers and state snapshots in `reframework/data/DualSenseEnhanced/events_debug.txt`.

### Fixed
- Stabilized repeated death/Continue recovery for HP, ammo indicator, and Mic LED.
- `weapon_equip_core.lua`: inventory fallback now prefers a controller with a real equipped weapon, fixing intermittent `None 0/0` state after Continue.
- `events_led.lua`: gameplay recovery can use live HP context and adaptive-feedback activity without blocking all LED output on temporarily missing weapon data.
- Finalized grab QTE blinking across front/back variants: exact GUI start/end, deduplicated widget updates, white Cross flashes, black rest state, and immediate cleanup.
- Removed rejected grab hooks and fallback timers (`shieldingDecision`, `onApplyActionEnd`, `onCancelGrapple`, `ButtonMashingEscapeCondition`, `ActionSignGuiGrabOpenParam`, and damage-quiet timeout).
- `events_led.lua`: `onStartInGame` with empty weapon context now enters a pending gameplay-enable state and waits for both player context and valid weapon info before re-enabling HP/ammo/Mic LED outputs.
- `events_led.lua`, `ammo_led.lua`, `hp_led.lua`: added generation guards so stale REFramework callbacks from future script reloads cannot keep running old LED logic after `Reset Scripts`.
- `events_led.lua`, `ammo_led.lua`: fixed a death/Continue recovery edge case where HP lightbar, ammo indicator, or Mic LED could remain disabled; HP recovery uses live gameplay context while ammo state resets and resumes when equipped-weapon data returns.
- `mic_led.lua`, `feedback_writer.lua`: removed the command-file bridge path; Mic LED now works through the unified payload writer.
- `feedback_writer.lua`: payload now explicitly sends black lightbar and disabled player indicator when no source is active.
- `feedback_writer.lua`: writes a reset payload on load to clear stale controller LEDs from previous sessions.
- `events_led.lua`, `settings.lua`: data-file paths now use `DualSenseEnhanced/...` relative to REFramework data root, avoiding accidental `reframework/data/reframework/data/...` duplication.
- `events_led.lua`: fixed cutscene watchdog being cleared immediately by LED cleanup, which could leave cutscene gate stuck after movie hooks fired without a matching end hook.
- `ammo_led.lua`: added gameplay gate so ammo/player indicator stays off before gameplay and clears when gameplay ends.
- `events_led.lua`: return-to-menu polling now uses `PlayerManager.get_CurrentPlayer` as the active gameplay check.
- `events_led.lua`: non-gameplay transition clears HP, event, ammo lightbar sources, and player indicator together.
- `events_led.lua`: polling no longer enables gameplay outputs from early loading player context; only `onStartInGame` can start HP/ammo output.
- `events_led.lua`: damage flash now holds and refreshes its own high-priority LED source for the full damage duration, preventing low-HP dim danger colour from showing mid-flash.
- `events_led.lua`: removed post-load HP/ammo settle delay; HP and ammo indicator now enable immediately after `onStartInGame`.
- `hp_led.lua`: exiting gameplay cancels active heal lerp state.

### Known Issues
- Automatic cutscene LED suppression is disabled for now. Tested `MoviePlayer` / `MovieManager` / timeline hooks were too noisy and could break normal HP/ammo gameplay gating.
- Gameplay LEDs are not always suppressed during pause.
- Gameplay LEDs may appear briefly during loading transitions.
- These issues are non-critical and intentionally deferred to preserve the stable LED baseline.

### Research
- Rejected `chainsaw.GameStateInGame.setup/enter/leave` hooks for gameplay recovery. `setup` fired repeatedly during startup and could prevent the game from launching cleanly.
- `chainsaw.Melee.onHitAttack` was tested and found too broad for LED finisher feedback; it fires on general knife/melee hits for player and enemies. Kept as a future haptics/audio candidate only.
- Current heal sound prototype triggers Windows playback, but does not activate DSX's internal button-trigger sound feature. Need to investigate DSX profile/API or similar mods for direct sound trigger integration.

## v0.4 — HP Threshold Rework + Absolute HP Mode

### Changed
- `hp_led.lua`: added `threshold_mode` — `"absolute"` (default) or `"ratio"`.
- Absolute mode uses HP units instead of percentages, since max HP scales with upgrades.
- Default absolute thresholds: healthy=800, caution=400, danger=399, dim=150.
- `danger_rgb()` now uses absolute thresholds for dim zone calculation.
- `cached_max_hp` used to convert ratio → HP units in colour functions.

### Changed
- `events_led.lua`: default colours updated — parry now blue `{0, 120, 255}`.
- Parry duration doubled to 120 frames (~2s).
- Damage duration doubled to 80 frames (~1.3s).
- Added `SETTLE_FRAMES = 120` — HP LED suppressed for 2s after level load.
- Fixed `flush()` scoping bug — now defined before `poll_game_state()`.

### UI
- `DualSenseEnhanced.lua`: HP threshold section shows absolute/ratio toggle + correct sliders.
- Ammo mode uses button toggle instead of `radio_button` (fixes TreePop crash).

## v0.3 — Heal Lerp Fix + Per-Frame LED Tick

### Fixed
- `feedback_writer.lua`: `tick_led_sources()` moved from `apply_for_weapon()` to
  `re.on_application_entry("UpdateBehavior")`. Timers now decrement every real frame.
- `hp_led.lua`: heal transition now correctly lasts ~4 seconds (240 frames).
- `hp_led.lua`: heal lerp smoothly fades heal colour → current HP colour.
- `hp_led.lua`: no abrupt colour jump at end of heal — `push_hp_led()` called immediately after.
- `hp_led.lua`: heal transition cannot restart while already active (`heal_active` guard).

## v0.2 — Gameplay Gate + Death Detection + Grab Pulse

### Added
- `hp_led.lua`: `in_gameplay` gate — HP LED suppressed until `set_gameplay(true)`.
- `hp_led.lua`: `set_dead()` / `set_gameplay()` public API for `events_led`.
- `events_led.lua`: polling via `CharacterManager` every 30 frames for menu/death detection.
- `events_led.lua`: `onStartInGame` hook triggers gameplay entry + settle delay.
- `events_led.lua`: grab sine pulse (brightness modulated via `math.sin`).
- `events_led.lua`: `trigger_damage()` returns early if `grab_active == true`.

### Fixed
- Main menu on first launch: no green HP LED.
- Death: LED turns off.

## v0.1 — Initial Release

### Added
- DSX payload writing via `payload.json`.
- LED source bus with priority in `feedback_writer.lua`.
- Per-frame `tick_led_sources()`.
- HP gradient system (green → yellow-green → orange → red).
- Low HP danger blink.
- Damage LED flash.
- Parry LED flash.
- Grab LED effect.
- Ammo indicator (5 player LEDs).
- Empty mag amber blink.
- Weapon trigger profiles in `weapon_trigger_profiles.lua`.
- Unified REFramework UI in `DualSenseEnhanced.lua`.
- RGB sliders for all effect colours.
- Debug diagnostics in `debug_led.lua`.


### Research

Investigated bHaptics RE4R mod.

Discovered candidate hooks:

- onReloadStart
- onEquipChange
- onChangeHitPoint
- getHitPointVital
- onChangeJacked
- onHitAttack
- onHitDamage

Added to research documentation for future testing.
