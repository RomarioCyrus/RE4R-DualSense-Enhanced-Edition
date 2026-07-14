# MEMORY.md — Confirmed Working Behavior

## DSX

- DSX payload writing works via `payload.json` file watched by DSX app.
- `feedback_writer.lua` contains a central LED source bus (`DualSenseEnhancedFeedback.led_sources`).
- LED sources are selected by priority — highest wins each frame.
- `tick_led_sources()` runs every frame via `re.on_application_entry("UpdateBehavior")`.
- Weapon/trigger mapping works via `weapon_trigger_profiles.lua`.
- Player indicator (5 LEDs, `type=3`) works via `DualSenseEnhancedFeedback.set_indicator()`.
- `DualSenseEnhanced.lua` UI uses `imgui.color_edit3` RGB pickers for HP, ammo, menu, and event colours.
- `DualSenseEnhanced.lua` UI exposes effect duration sliders with reset buttons for HP, ammo indicator, and event effects.
- HP return fade duration is configurable in the HP UI, saved by `settings.lua`, and defaults to 30 frames.
- Fatal Kick impact flash duration is configurable in the Events UI; default is 30 frames (~0.5 seconds).
- `settings.lua` saves/loads runtime UI settings from
  `reframework/data/RE4R_DualSense_settings.lua`. It reads the saved Lua source
  through `io.open` rather than `loadfile`, because those APIs resolve relative
  paths differently under REFramework.
- `monitor.lua` exposes recent events in the `Event Monitor` UI section.
- **UI consistency pass (2026-07-14, implemented/deployed but not yet visually
  confirmed):** the release-facing order is Status -> Global Preset -> Quick
  Controls -> Lightbar -> Adaptive Triggers -> Controller Speaker Audio ->
  Enhanced Haptics -> Gyro Aim -> Advanced. Quick Controls explicitly mirrors
  detailed master switches and now includes Enhanced Haptics. Selected
  lightbar/audio modes use `[x]` markers; brightness, speaker volume, trigger
  strength, and global haptic strength use percentages. Per-category haptics
  use `Soft / Normal / Strong`, where Normal is the tuned default for that
  category and the checkbox is the true Off state. The haptic test reports a
  result and is hidden behind its required master/audio states. Physical UI
  spacing and interaction still require an in-game `Reset Scripts` smoke test.
- Lua `io.open` data paths run relative to the REFramework data root; use `DualSenseEnhanced/...`, not `reframework/data/DualSenseEnhanced/...`.
- Mic LED output is confirmed working through the unified `DualSenseEnhancedFeedback` payload path.
- `feedback_writer.lua` appends Mic LED instruction `type=5`, parameters `{controllerIndex, mode}` to the same `payload.json` update as triggers/lightbar/player indicator.
- Mic LED enum: `On=0`, `Pulse=1`, `Off=2`.
- The old command-file/PowerShell bridge path was removed because it was not reboot-friendly.

## DualSense Audio Bridge

- `DualsenseAudioBridge.exe` is implemented, installed, and confirmed working.
- The main `src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua` emits JSON audio
  events to `reframework/data/audio_events.json`.
- Physical controller-speaker playback is confirmed through NAudio/WASAPI for
  manual test, healing, and parry events.
- Manual WASAPI endpoint selection is implemented and deployed. The bridge
  writes `reframework/data/DualSenseEnhanced/audio_devices.json`; audio events
  include `device_id`; playback resolves exact endpoint ID first, then legacy
  friendly-name fragment, then Auto DualSense detection. Live testing with a
  connected controller confirmed that devices appear in the UI, manual
  endpoint switching works, and `Test Speaker` plays through the selected
  endpoint, including non-controller Windows output devices. Two-controller
  routing remains unverified.
- **Controller speaker audio now works natively over USB with no DSX or
  third-party tool installed** (2026-07-11, confirmed on both standard
  DualSense and DualSense Edge/`ds5dongle`) — requires the current
  `duaLib.dll` build (`audioControlEnabled` fix, see
  `docs/DUALSENSE_SPEAKER_NATIVE_INIT.md`); older builds' trigger-only
  Allow-flag suppression silently blocks it even though the audio endpoint
  itself always enumerates and opens without error. `DualsenseAudioBridge.exe`
  runs a one-shot native speaker-route init at startup, before any save is
  active, so this also works in menus/loading screens.
- `Test Speaker` is the single audio endpoint smoke-test button and emits the
  confirmed `parry` event. The redundant `Test Parry` UI button was removed.
- Audio and DSX UDP are intentionally separate processes: the audio bridge
  handles only `audio_events.json`, while the external `DSX_UDPClient.exe`
  handles `payload.json`.
- `reframework/plugins/DualsenseAudioBridgeLauncher.dll` starts both helpers
  silently. Do not use Lua `os.execute`; it is unavailable in this
  REFramework sandbox.
- `SoundPlayer` (the C# bridge's playback layer) plays each event name on
  its own independent channel; a new sound only interrupts a previous one
  on the *same* event name, never a different one (fixed 2025-06-29 -- the
  old single-global-slot design let any new sound cut off any other, e.g.
  closing the inventory right after using a healing item cut the heal
  sound off with the inventory-close sound). `low_hp_end` stops only the
  `low_hp` channel, not all playback.
- The bridge is deployed under
  `reframework/data/DualSenseEnhanced/DualsenseAudioBridge.exe`, writes a UTF-8 log
  beside itself, and exits automatically with `re4.exe`.
- Recommended artifact:
  `speaker/DualsenseAudioBridge/dist/audio-portable/DualsenseAudioBridge.exe`
  (compressed self-contained, approximately 66 MiB).
- Optional artifact:
  `speaker/DualsenseAudioBridge/dist/audio-compact/DualsenseAudioBridge.exe`
  (approximately 0.7 MiB, requires .NET 6 Desktop Runtime).
- OGG playback remains unsupported until `NAudio.Vorbis` is added and tested.
- Grab-QTE input and category-based item pickup audio are implemented and
  awaiting the current gameplay verification pass.
- Numbered WAV files are random variants with immediate-repeat avoidance.
- Fatal Kick speaker audio uses three clean layered composites (balanced,
  punchy, heavy). The old long environmental/breaking layer was removed.
- Pickup diagnostics are opt-in and no longer restore an old persisted `true`
  value. Pickup recognition and sounds remain active without Event Monitor ID
  spam.
- External lookup data under the sibling `id_database` directory contains
  valid CH/AO/MC item and weapon JSON tables. It is a research/reference
  database; runtime still uses its local `item_ids.lua` mapping.
- Weapon audio profiles are maintained under `docs/weapon_audio_catalog/`.
- SG-09 R, W-870, Riot Gun, Striker, Skull Shaker, SR M1903, Broken
  Butterfly, and Handcannon reload audio are physically confirmed.
- W-870's approximately one-second post-shot pump delay is physically
  confirmed for shots that leave ammunition. A final shot now defers the pump
  cycle until the following reload ends. SR M1903 and Handcannon use the same
  last-shot/deferred-cycle rule.
- Stingray currently has a broken/regressed mapping and needs phase-by-phase
  retesting. CQBR improved after removing its equip/draw-like finish cue, but
  still lacks part of the reload sequence. Killer7 still awaits its first
  gameplay validation.
- Punisher, Red9, Blacktail, and Matilda have conservative two-phase reload
  prototypes in the project tree. They emit magazine release/removal at reload
  start and magazine seat/lock on the ammunition increase. They are not yet
  gameplay- or controller-confirmed.
- Their slide/chamber candidates remain unmapped to avoid replaying
  empty-reload-only mechanics on tactical reloads.
- Broken Butterfly, CQBR, Killer7, Skull Shaker, and Handcannon received a
  later manual correction pass. Their current runtime files and catalog order
  follow the June 25 findings; treat them as implemented but awaiting the next
  physical retest.
- The current bridge build and 47 rifle/magnum reload WAVs were hash-verified
  after deployment. A bridge smoke test reached the configured REFramework,
  sounds, events, and volume paths successfully.
- Controller-speaker WAV playback also works in native DualSense mode with
  DSX closed and Steam Input disabled. Keep the current event-based,
  pre-extracted-WAV implementation; it remains useful even though live game
  SFX-bus extraction was not achieved.
- Wwise event-ID routing is confirmed for extracted-WAV timing. Use
  `soundlib.SoundManager.postRequestInfo` pre-hook for low-latency timing and
  read `soundlib.SoundManager.RequestInfo.get_EventId`; keep
  `onEndOfEvent` only as a late catalog/confirmation path.
- First confirmed Wwise route: SG-09 R dry fire uses `event_id=2330373695`
  (`wp4000` `event_0260`) gated to weapon `4000` and `ammo=0`, emitting
  `wp4000_dry_fire` through `audio_events.json`. The bridge `SoundMap`,
  runtime Lua, WAV, and deployed EXE were SHA-256 checked, and the user
  confirmed in-game/controller sync.
- Confirmed Wwise route playback is now separated from diagnostics:
  `wwise_audio_router.lua` owns always-on mappings, while
  `sound_event_diag.lua` is only for manual windows and event logging.
- Blacktail (`wp4003`) reload re-verification (2025-06-27): live
  `postRequestInfo` capture across multiple real tactical reloads disproved
  the by-ear `event_0256` reload-start mapping (never fired) and confirmed a
  stable, reload-exclusive pair `event_0264` (Wwise ID `2857560191`) then
  `event_0246` (Wwise ID `814494088`), verified against a dedicated 5x
  aim/lower control test with zero false positives.
- Discovered a confirmed general-purpose hook during the same Blacktail
  research: `event_0274` (Wwise ID `3406633596`) fires on weapon
  lowering/aim-exit, independent of reload. It is not reload-specific and
  must not be used as a reload-finish cue, but it is a candidate timing
  signal for future work such as auto-disabling gyro on aim exit.
- Identified a recurring bug class across magazine-fed weapons: the
  ammo-delta-based reload-insert trigger in `ammo_led.lua` never fires when
  the player only re-chambers an externally-loaded extra round (ammo never
  numerically increases). Fixed for `wp4000` (SG-09 R) and `wp4001`
  (Punisher) the same way as `wp4003`: route `*_reload_insert` directly off a
  confirmed ammo-independent Wwise event in `wwise_audio_router.lua` instead
  of ammo polling, and remove the `insert` key from `audio_feedback.lua`'s
  `RELOAD_EVENTS_BY_WEAPON` for that weapon. SG-09 R uses `event_0246`
  (Wwise ID `635031351`, replacing the previously uncatalogued/unconfirmed
  `event_0271`); Punisher uses `event_0260` (Wwise ID `2748519654`). Both
  physically confirmed by the user on the controller speaker for normal and
  already-full-magazine edge-case reloads. The same pattern should be checked
  per-weapon (Red9, Matilda, and the rest) before assuming it is universal.

## Weapon Audio — Wwise Event Mapping Summary (2025-06-27/28 session)

**For current per-weapon completion status, check `docs/WEAPON_AUDIO_STATUS.md`
first** — it's the maintained source of truth (start/insert/finish/dry-fire/
last-shot/draw/aim-in/aim-out per weapon). The table below is the detailed
historical record with exact Wwise event numbers from the original mapping
pass; it won't be kept in sync with later changes the way the status table is.

A large pass converted most weapons' reload insert/finish triggers from
ammo-count polling to direct Wwise event IDs (`wwise_audio_router.lua`,
weapon-gated), and added dry-fire and last-shot (the shot that empties the
magazine) cues for the five Leon-campaign handguns. Per-weapon final state:

| Weapon | start | insert | finish | dry fire | last shot |
|---|---|---|---|---|---|
| SG-09 R (`4000`) | hook | `event_0246` | `event_0258` (re-confirmed; previously rejected) | `event_0260` (shared with start) | `event_0248` |
| Punisher (`4001`) | hook | `event_0260` | `event_0254` | `event_0252`→`event_0240` (2-stage) | `event_0234` (shared with start) |
| Red9 (`4002`) | hook | `event_0240` (was `0230`, never fired) | `event_0252` | `event_0248`→`event_0272` (2-stage) | `event_0238` |
| Blacktail (`4003`) | hook | `event_0268` | `event_0254` | `event_0256` (own WAV) | `event_0272` |
| Matilda (`4004`) | hook | `event_0238` (was `0234`, unverified edge case) | `event_0268` (handler-gated `ammo>0`, also fires on dry fire) | `event_0234` | not yet found |
| Sentinel Nine (`6000`) | hook (reused wp4000 WAVs) | `event_id=1498116241` | `event_id=3601070767` (1 of 3 ambiguous) | not yet found | `event_id=4056224971` |
| Riot Gun (`4101`) | hook | `event_0220` (per-shell) | `event_0222` | — | — |
| W-870 (`4100`) | — | `event_0215` (per-shell) | n/a (2-phase post-shot handler `event_0203`, fires live-fire and after empty-reload, no reload-session guard) | — | — |
| Striker (`4102`) | hook | `event_0208` (per-shell) | — | — | — |
| SR M1903 (`4400`) | hook | `event_0241` (per-shell) | none exists (catalog confirms no finish stage); deferred post-shot via `finish_on_full_insert` fast path | — | — |
| Stingray (`4401`) | **none** (removed) | — | `event_0248` | — | — — full chain: `release(0242)→open(0240)→insert(0252)→finish(0248)`, all real WAVs |
| CQBR (`4402`) | **none** (removed) | — (no insert stage; user rejected `event_0216`) | `event_0235` | — | — — chain: `release(0210)→safety(0231)→finish(0235)` |
| Broken Butterfly (`4500`) | `event_0191` (was hook; ~0.9s late) | `event_0197` (per-shell) | `event_0193` | — | — — post-shot stays on the old fixed ~1s timer; `event_0197` confirmed NOT to fire on a live shot outside reload |
| Handcannon (`4502`) | `event_0226` (was hook; ~0.9s late) | `event_0198` | `event_0224` | — | — — post-shot stays on the old fixed timer for the same reason as Broken Butterfly |
| Killer7 (`4501`) | hook | `event_0214` | — | — | — |
| Skull Shaker (`6001`) | hook | `event_0229` (per-shell) | `event_0219` (1 of 2 ambiguous, picked as later-firing) | — | — |
| TMP (`4200`) | hook | `event_0234` | `event_0242` | — | — — first-time mapping, no prior catalog |
| Chicago Sweeper (`4201`) | hook | `event_0242` | `event_0236` | — | — — first-time mapping |
| LE 5 (`4202`) | hook | `event_0226` | `event_0258` | — | — — first-time mapping |
| Bolt Thrower (`4600`) | hook | `event_0260` | none found | — | — — first-time mapping |

Key lessons from this session:

- **Catalog by-ear labels are frequently wrong.** Confirmed wrong: SG-09 R's
  `event_0258` (previously "rejected, no finish cue heard"; now confirmed
  live), Red9's `event_0230` (never fires), Matilda's `event_0234` (was
  insert; live data shows it is dry-fire instead, with `event_0238` as the
  real insert). Live `postRequestInfo` capture is the only reliable source.
- **The "last event before the ammo tick" heuristic is not universal.**
  Sometimes the correct insert/seat sound is a middle event in the pre-tick
  sequence, not the last one (Blacktail's `event_0268` beat the
  chronologically-later `event_0246`).
- **Some Wwise IDs are shared across contexts and need extra gating beyond
  weapon ID.** Examples: `wp4000`/`wp4001` reuse their reload-start ID for
  dry-fire/last-shot (gated by `ammo=0`); Matilda's `event_0268` fires on
  both reload-finish and dry-fire (gated by a custom ammo>0 handler instead
  of the plain weapon-only route); Blacktail's/Stingray's `event_0274`/
  `event_0262` are generic weapon-lowering cues, not reload-specific at all.
- **Revolver-type weapons' post-shot cues may have no live Wwise ID at all.**
  Confirmed for both Broken Butterfly and Handcannon via clean single-shot
  captures: their catalogued post-shot event never fired outside reload.
  Both keep the original fixed-delay timer; do not retry this without new
  evidence.
- **Dry fire can be a two-stage sequence perceived as one click** (Punisher:
  `event_0252`→`event_0240`; Red9: `event_0248`→`event_0272`), confirmed
  reproducible across separate captures in the same order.
- Sentinel Nine (`wp6000`) still has no extracted Wwise bank in the project's
  FusionTools/re_chunk_000 tooling (confirmed absent even after a clean
  re-extraction with mods disabled), despite being listed in the game's full
  asset manifest. All its event IDs are unconfirmed guesses from live
  capture alone; WAV assets are reused from SG-09 R as placeholders.

## UI Audio (2025-06-28 session)

Added the first non-weapon Wwise routes, confirmed via the same
`postRequestInfo`/`postEvent` hook used for weapons. Not weapon-gated.

| UI action | Wwise ID | Source |
|---|---|---|
| Attache case (inventory) open | `465888893` | `play_CH_GUI_ATTACHECASE_OPEN`, `ch_ui_ingame.bnk` event_0570 |
| Attache case (inventory) close | `1699876315` | `play_CH_GUI_ATTACHECASE_CLOSE`, `ch_ui_ingame.bnk` event_0640 |
| Quick-select wheel confirm click | `3244343389` | `ch_cha0.bnk` event_18204; confirmed identical across 5+ captures on different weapons (SG-09 R, W-870, Handcannon) -- this is a single generic confirm cue, **not** weapon-specific despite the perceived per-weapon difference (that difference likely comes from an internal Wwise switch container, invisible to the event-ID-level hook) |

Naming note: prefix `ao_` = Separate Ways DLC banks, `ch_` = base
campaign/Mercenaries banks. Use `ch_ui_ingame.bnk`/`ch_ui_ingame_media.bnk`
for base-game UI sounds, not the `ao_ui_*` equivalents.

Deployed and confirmed working in-game (2025-06-28).

### Per-weapon draw/quick-select sound (deployed 2025-06-28)

Added per-weapon **draw/equip sounds** (play when a new weapon appears in
hand after a quick-select switch). Methodology: the `weapon=` field in the
diagnostic log reflects the weapon still equipped at event time, and the
switch doesn't register until close to/after the end of a 1s window opened
at the button press -- the manual window must be opened **after** the press
(or use a 5s window starting at the press) to capture the full sequence.

`3333492782`/`3898613260` (`ch_cha0.bnk` event_18206) are a generic
character-level "weapon grab" cue common to every weapon switch -- not
routed, since they carry no per-weapon information. Each weapon's real
draw sound is one or more dedicated events in its own bank
(`ch_wp<id>.bnk`), confirmed via 2-3 independent captures each:

| Weapon | Draw sequence (own bank event_ids) |
|---|---|
| SG-09 R (`4000`) normal draw | none found beyond the generic cue |
| SG-09 R (`4000`) special draw (rare animation variant) | `491310844`(0244) -> `1159279911`(0252) -> `3826103781`(0271) |
| W-870 (`4100`) | `2390921771`(0213) -> `2047712154`(0207) -> `1963824255`(0205) |
| Riot Gun (`4101`) | `3445929668`(0226) -> `514608480`(0214) -> `514608483`(0216) -- same sequence for both "normal" and "special-looking" draws, i.e. Riot Gun has only one draw animation |
| Skull Shaker (`6001`) | `960381449`(0215) -> `1840028007`(bank not found yet -- see TODO below) |
| Striker (`4102`) normal draw | `315968521`(0204), single stage -- deployed |
| Stingray (`4401`) normal draw | `1764992833`, unconfirmed bank, not yet deployed; `1131449975` also recurs but appears in both normal AND special draws, likely a generic mechanism sound, not mapped |
| Stingray (`4401`) special draw | `1944767134`(0231) -> `3247665678`(0250) -> `4033741106`(0262), 3 stages, not yet deployed (holding for rifle batch) |
| SR M1903 (`4400`) special draw | `1545855344`(0228) -> `4065062720`(0256) -> `1441789338`(0224) -> `1357901439`(0222) -> `1477056167`(0226), 5 stages -- deployed. The originally-captured bookend `3851521877` turned out to be the generic aim-out cue (see below), not part of the draw; removed from the draw sequence |

Deployed 2025-06-28 along with draw/dry-fire for all 3 rifles (Stingray,
SR M1903, CQBR).

## Aim-in / aim-out (L2 press/release), deployed 2025-06-28

Confirmed via live capture per weapon, same hook. Naming pattern in the
banks: aim-in events are usually `play_wp<id>_SE_set`; aim-out (where it
exists) is a separate, sometimes-shared generic weapon-lowering event.

| Weapon | Aim-in | Aim-out |
|---|---|---|
| SG-09 R (`4000`) | `1722211355`(0256) | none (confirmed via clean capture) |
| Punisher (`4001`) | `1428456100`(0250) | `712539726`(0240) |
| Red9 (`4002`) | `3461965221`(0266) | `3924820871`(0272) |
| Blacktail (`4003`) | `1680709590`(0252) | `3406633596`(0274) -- this is the same generic weapon-lowering ID found during the 2025-06-27 Blacktail reload research; finally given a real use |
| Matilda (`4004`) | `2927861719`(0258) | shares `4245683861`(0268) with reload-finish; disambiguated in `AUDIO.play_wp4004_weapon_lower_event` by `reload_session_active` (true+ammo>0 = finish, otherwise = aim-out) |
| Sentinel Nine (`6000`) | `3761912333` (bank-unconfirmed) | `3601070767` (bank-unconfirmed) -- this is the same ID originally guessed/rejected as Sentinel's reload finish; it's the generic aim-exit cue, not finish-related. Confirms wp6000 does NOT share wp4000's bank at the event-ID level, despite using the same WAV assets |
| W-870 (`4100`) | `3027281516`(0219) | none |
| Riot Gun (`4101`) | `3844674851`(0236) | none |
| CQBR (`4402`) | `892036529`(0201) | `666856267`(0199) |
| Stingray (`4401`) | `1122442048`(0225) | `4033741106`(0262) -- this ID was originally mapped as draw stage 3/3; turned out to be the generic aim-out cue and was reassigned |
| SR M1903 (`4400`) | `3302244247`(0248) | `3851521877`(0252) -- originally mapped as draw stage 1/6; same generic-cue situation as Stingray |
| Skull Shaker (`6001`) | `101476094`(0207) | none |

Key lesson reinforced multiple times this session: several weapons'
"special draw animation" stage candidates from earlier captures turned out
on a clean aim-in/aim-out test to be the generic weapon-lowering/aim-exit
cue, not draw-specific (SR M1903's stage 1/6, Stingray's stage 3/3). When
adding a new per-weapon event role, always cross-check it isn't already a
known generic cue before trusting a single-context capture.

## Remaining weapon-audio module scope

See `docs/WEAPON_AUDIO_STATUS.md` → "Remaining scope" section for the
maintained list of what's left (per-weapon draw sounds, magnums,
automatics/SMGs, crossbow). Don't duplicate that list here -- update the
status file instead when scope changes.

**TODO**: `1840028007` (Skull Shaker draw stage 2) is not in any bank
extracted so far (`ch_wp6001.bnk`/`_media`), only listed by ID in
`wwnames.txt` with no hashname -- its source bank/chunk hasn't been pulled
from REtool yet (possibly a `_c_media`-style extra chunk, as happened with
Stingray). Find and extract it before mapping Skull Shaker's 2nd draw
stage. The first stage (`960381449`, `ch_wp6001.bnk` event_0215) is not
yet deployed either since it's only one of two stages -- hold off
deploying it alone until the 2nd is found, per user request
("запиши что искать потом").

- RE4R has a native PC DualSense path. With USB DualSense/Edge, Steam Input
  disabled, and DSX closed, the game sees
  `via.hid.VendorNativeDualSenseDevice`.
- Native mode provides correct menu/loading/gameplay LED behavior, low-HP
  heartbeat vibration, and partial haptics for shots, reloads, damage, and
  knife hits.
- DSX in DualSense emulation or native mode conflicts with the game's HID
  output: native haptics disappear and the lightbar alternates between Capcom
  and mod/DSX states. This is a DSX-level conflict, not only a
  `payload.json` issue.
- `soundlib.SoundVibrationManager.IsTargetPlatform` is `false` on PC.
  `chainsaw.PlayerHapticsController`, `triggerVibration`, joint-contact
  callbacks, and empty WAV-haptics loading calls are nevertheless active.
- Temporarily forcing `IsTargetPlatform=true` creates HD/audio vibration
  records, but the PC build has no registered vibration-wave indices and no
  `onPostVibrationEvent` output. It also suppresses the working native PC
  effects. Keep this gate off.
- `DualSenseHapticsProbe` proved 4-channel WASAPI audio-to-haptics works when
  another controller manager keeps audio-haptics mode active. In native RE4R
  mode, even one-shot and short-burst HID mode selection did not produce a
  reliable tone; the coexistence path was deferred until 2026-07-05.
- **2026-07-06 stand-test confirmation**: the duaLib watcher is that
  "another controller manager". `DualSenseEnhancedTransport.exe
  --test-haptics-mode` holding haptics mode (`scePadSetVibrationMode`,
  1=haptics, 2=rumble) makes the bridge's channels-3/4 test tone produce
  physical actuator vibration on a USB DualSense Edge (DSX closed, game
  closed). A duaLib.dll rebuild turned out to be required after all: the
  first control-condition check (tone after mode restore) still vibrated,
  traced to `SetStateData::operator==` in `dataStructures.h` not comparing
  `UseRumbleNotHaptics`/`EnableRumbleEmulation`/`EnableImprovedRumbleEmulation`,
  so a vibration-mode-only change never registered as "different" and
  `readDualsense.cpp` never wrote it to hardware. Fixed and rebuilt;
  confirmed `build_out/duaLib.dll` hash is now
  `0C355C4B9071A86E728A77847BD1D8702AEE8335937C8E689528F040BD3BFF9E`
  (supersedes the earlier `0BF8351F...` lightbar-allowled build referenced
  elsewhere in this file/AGENTS.md/BUILD.md — update those references too
  if found stale). Footstep-haptics experiment **stopped 2026-07-07** (not
  a v1.0 priority): the pipeline works end-to-end but is blocked on a
  suspected RE4R-vs-duaLib write race that prevents the actuator content
  itself from being physically felt while RE4R is running (Capcom's own
  native haptics do survive holding audio-haptics mode — that part was
  real — but this project's own channel-3/4 content does not). Full
  writeup and stage plan in `docs/HAPTICS_FOOTSTEPS_TASK.md`. Excluded from
  release v1.0 by user decision; everything is opt-in and default-off, and
  the enabling UI is unreachable outside `RELEASE_BUILD == false`.
- The Capcom Event Mapper is diagnostic only. It confirmed useful internal
  vibration IDs exist, but most overlap with background/melee/HP activity.
  Existing confirmed gameplay hooks remain preferred.
- Experimental `native_feedback.lua` reuses the custom LED bus through
  RE4R's `share.hid.Device`, without DSX or direct HID reports. Its gameplay
  lightbar path is hardware-confirmed while native Capcom haptics remain active.
- Direct native adaptive-trigger application through
  `share.hid.Device.setAdaptiveTriggerFeedback` caused a confirmed game crash.
  The native trigger path is hard-disabled and must not be tested again without
  a different mechanism.
- Native lightbar calls initially flickered because Capcom and the mod both
  wrote the same state. The current experiment hooks the game's
  `setLightBarColor/resetLightBarColor` calls only while the custom LED bus
  owns a color, while allowing the mod's marked internal writes. Because
  Capcom also reapplies cached state during `share.hid.Device.update`, the
  custom color is enforced in that method's post-hook as the final lightbar
  write. This intentionally disables Capcom lightbar ownership only in native
  custom mode; native haptics are not hooked.
- RE4R exposes no managed DualSense player-indicator setter. The only
  `PlayerLedPattern` metadata in the dump belongs to `via.hid.NpadDevice`,
  not DualSense. The active native implementation therefore drives the five
  ammo LEDs and Mic LED through the external duaLib watcher, not through a
  RE4R managed API.
- Native custom lightbar is gameplay-confirmed for normal HP, healing,
  damage, parry, and other existing event effects while Capcom native haptics
  remain active.
- The menu lightbar still shows Capcom blue instead of the custom menu effect;
  this is accepted as deferred/non-critical.
- Native low-HP feedback (2025-06-29 redesign): the danger heartbeat is now
  a continuous red brightness pulse (`hp_led.lua`'s `vital_danger_rgb` with
  a per-frame sine `pulse_factor`, floor `LED.pulse_min_brightness`
  default 0.25), never a literal on/off blink to black. This replaced the
  earlier on/off `blink_state` design (and its `native_feedback.lua`
  orange `255,70,0` black-rest substitute, now removed) after the
  black-rest blink proved unreliable on the native lightbar. Pulses pure
  red in both DSX and native mode now -- no orange. The Mic LED sync
  (`dualib_trigger_ipc.lua`'s `hp_danger_mic_mode()`) reads the new
  `LED.danger_pulse_on` phase flag rather than inspecting color magnitude.
- Read-only adaptive-trigger diagnostics observe
  `chainsaw.PlayerManager.setAdaptiveFeedBack` and both
  `setAdaptiveTriggerFeedback` overloads. This is the safe research layer;
  direct `share.hid.Device` trigger calls remain prohibited.
- Read-only PlayerManager diagnostics captured no adaptive-trigger calls during
  normal weapon actions. The guarded L2 probe could not acquire a live
  `chainsaw.PlayerManager`; an `onUpdate` capture hook also remained idle.
  This path is closed because the existing DSX mode already supplies the
  necessary event mappings and PlayerManager did not provide a viable native
  trigger transport.
- The separate duaLib transport is now hardware-confirmed in native gameplay:
  existing weapon mappings reach L2/R2 through JSON IPC while Capcom haptics,
  the custom native lightbar, and controller-speaker audio remain active.
  It starts automatically but waits for `CampaignManager.onStartInGame`'s Lua
  ready marker before opening the controller. Preserve this trigger-only
  boundary; do not add another blind full-report writer.
- Player indicator, RGB lightbar, and Mic LED are no longer DSX-only. They are
  hardware-confirmed through custom duaLib exports,
  `scePadSetPlayerIndicators`, `scePadSetLightBar`, and `scePadSetMicLight`,
  applied via the external trigger watcher's `trigger_command.json` IPC
  (`IPC.indicators_enabled` / `IPC.lightbar_enabled` / `IPC.mic_enabled` in
  `dualib_trigger_ipc.lua`). The deployed `duaLib.dll` is a custom build from
  `third_party/src/duaLib-master` (compiled with the bundled llvm-mingw
  toolchain, `-static`, see `CHANGELOG.md`), not the upstream prebuilt binary.
  `readDualsense.cpp` has a guard block that forces most `Allow*` output flags
  off each cycle so this transport doesn't fight the game/Windows for
  unrelated report sections (audio routing, volume, unrelated haptics);
  `AllowPlayerIndicators`, `AllowLedColor`, and `AllowMuteLight` are explicitly
  exempted through their opt-in flags.
- **2025-06-29 end-to-end hardware confirmation** (full session arc, in
  order): player indicators via duaLib confirmed (`--test-indicators`,
  then live in-game with `IPC.indicators_enabled`, warning-mode logic
  matching DSX's default -- silent above `warn_threshold`, count-down LEDs
  with last-bullet blink below it). Mic LED via duaLib confirmed
  (`--test-mic-light`, then live with `IPC.mic_enabled`; required both the
  `AllowMuteLight` exemption above and a `controller.wasDisconnected=true`
  force-resend in `scePadSetMicLight`, since a fresh process's
  zero-initialized struct made requesting Off look like "no change" against
  stale hardware state from a prior process). `ammo_empty`'s lightbar
  feedback was redesigned from a hard on/off blink to the same continuous
  sine pulse style as `hp_danger` (new `AMMO.pulse_min_brightness`,
  default 0.25) because the hard blink was not reliably visible in native
  mode. Mic LED was then synced to both pulses (`hp_danger_mic_mode()` /
  `AMMO.empty_pulse_active`+`empty_pulse_on` in `dualib_trigger_ipc.lua`),
  driving manual On/Off in lockstep with the lightbar's own per-frame phase
  instead of duaLib's independently-timed firmware Breathing mode. Finally,
  the continuous per-frame pulse push caused a real performance regression
  (stutter) by multiplying `share.hid.Device` managed calls and
  `device_update_post_hook` enforcement traffic; fixed by throttling the
  LED-bus push to every `pulse_push_interval` frames (default 2) and
  quantizing brightness to `pulse_steps` discrete levels (default 12,
  fields added to both `AMMO` and `LED` tables) while still advancing phase
  every frame for correct pacing. All of the above is now user-confirmed
  working end-to-end, including the perf fix.
- Two persistence/deploy lessons from the same session, now codified in
  `AGENTS.md`'s "Deploy Hygiene" section and `tools/verify_deploy.ps1`:
  (1) `IPC.lightbar_enabled`/`IPC.mic_enabled` UI checkboxes were added
  without wiring them into `settings.lua`'s save/load, so they silently
  reset on every `Reset Scripts`; (2) `dualib_trigger_ipc.lua` was edited
  across several turns but only redeployed once early on, so two
  subsequent fixes silently ran against a stale in-game copy. A full
  sha256 sweep of every deployed file (not just the most recently edited
  one) caught both.
- Tried moving native lightbar ownership to the external duaLib watcher via
  `scePadSetLightBar` (opt-in `IPC.lightbar_enabled` in
  `dualib_trigger_ipc.lua`, defaults off). First hardware test (2025-06-29)
  concluded Capcom's native color always wins visually, attributed to
  `share.hid.Device.update()` re-writing the cached lightbar field into
  the full HID report every render frame, faster than the watcher's
  ~50ms-polling writes could compete with.
- **That conclusion was confounded and is now superseded (still
  2025-06-29).** `readDualsense.cpp`'s trigger-only output-suppression
  guard forced `AllowLedColor` unconditionally `false` with no exemption
  (unlike `AllowPlayerIndicators`/`AllowMuteLight`, which already had
  one) -- the exact same bug class found and fixed for the Mic LED earlier
  the same session. This means the original duaLib-lightbar test ran with
  the protocol-level permission bit permanently off, so it was never a
  fair test of the frequency-race theory; `scePadSetLightBar`'s direct
  `LedRed/Green/Blue` writes could not have reached the wire regardless of
  any race against Capcom. Added `controller.lightBarOverrideEnabled`
  (mirrors the other two flags) and wired `AllowLedColor =
  controller.lightBarOverrideEnabled` into the guard block.
  **Hardware-confirmed in isolation** (`--test-lightbar`, no game running):
  the lightbar now changes color correctly.
- **Live in-game retest (2025-06-29): duaLib lightbar now works,
  superseding the "Capcom always wins" finding.** With the `AllowLedColor`
  fix in place, `IPC.lightbar_enabled` + `IPC.mic_enabled` confirmed
  working in real gameplay -- lightbar pulses, Mic LED pulses in sync,
  `Lightbar writes`/`Post-update lightbar enforces` correctly read near
  zero (native_feedback.lua's own write path stays idle, as designed),
  `Blocked Capcom lightbar calls` climbs normally. The original
  "frequency race" theory was never actually tested cleanly -- the
  permission bit was off the whole time during that test too. duaLib can
  now be a legitimate native lightbar owner, gated behind this opt-in flag.
- **Post-refactor retest (2026-07-02): confirmed working after the
  `DualSenseEnhanced` namespace cleanup.** A regression where the watcher
  started but triggers stayed `Off` was fixed by making `feedback_writer.lua`
  load `DualSenseEnhanced/weapon_trigger_profiles.lua` independently of
  `payload.json` and by retrying mapping load from `dualib_trigger_ipc.lua`.
  A second regression where watcher logs showed `Led=(...)` but the physical
  lightbar stayed unchanged was traced to the deployed `duaLib.dll`: the game
  folder still had the older 2026-06-26 trigger-only DLL. Replacing it with
  the newer `third_party/build_out/duaLib.dll` lightbar-allowled build
  restored lightbar output. The user confirmed that lightbar, adaptive
  triggers, audio bridge, and UI now all work as expected; `tools/verify_deploy.ps1`
  reported `373/373` matching deployed files.
- Found a second, unrelated duaLib bug while chasing the above: a
  short-lived process (e.g. `--test-lightbar` with a short `--duration`)
  that sets a color and then immediately calls `ResetLightBar()`/exits can
  leave the controller stuck on the last color. duaLib's background read
  thread is what actually performs `hid_write`; `Set*`/`Reset*` calls only
  update an in-memory struct for that thread to pick up next iteration.
  With no settle time before `Dispose()` closes the handle, the final
  reset write can lose the race against process teardown. Fixed by adding
  `Thread.Sleep(50)` to the end of `DuaLibBackend.Reset()` (covers
  `Dispose()`, the `--watch` loop's game-exit cleanup, and Ctrl+C in one
  place). Hardware-confirmed: a previously-stuck short test now reliably
  clears.
- The continuous lightbar/Mic LED pulse writing `trigger_command.json`
  every couple of frames once exposed a real crash:
  `CommandFile.ReadStable` (two reads 10ms apart must match byte-for-byte,
  5 retries) can legitimately exhaust its retries under that write rate,
  and the resulting exception was uncaught at the `Watch()` call site,
  killing the whole transport process. Symptom looked like a Lua bug at
  first (lightbar/indicator went dark, Mic LED froze *on*) but the
  REFramework console showed the Lua LED bus still computing fine --
  `Get-Process` showing the transport exe simply gone was the real tell.
  Fixed by catching that specific exception in `Watch()` and skipping the
  iteration (mirrors the adjacent gyro-sample catch, which already had
  this guard). Also found `DuaLibBackend.Reset()` never reset the Mic
  LED, which is why it froze on rather than going dark like the
  lightbar/indicators did on the same crash -- added `_micLightOwned`
  tracking and a `SetMicLight(0)` call to `Reset()`. Both
  hardware-confirmed fixed: repeated empty-ammo weapon switches with
  `IPC.lightbar_enabled` on no longer crash the watcher.
- The existing `device_update` post-hook enforcement in
  `native_feedback.lua` (re-assert synchronously in the same frame) remains
  the only lightbar mechanism confirmed to win against Capcom in real
  gameplay; do not abandon it in favor of the duaLib path without a clean
  live retest first. Also noted: the flicker the duaLib attempt was meant
  to fix was not actually visible to the user under normal play with the
  existing mechanism, so there is no known active lightbar bug being
  chased in gameplay right now -- this whole thread is exploratory.
- Native gyro-to-mouse is confirmed as an opt-in native input path. It uses
  the same delayed duaLib watcher as the trigger transport, enables
  `scePadSetMotionSensorState`, reads IMU angular velocity through
  `scePadReadState`, calibrates startup bias, maps X to pitch and inverted Z
  to yaw, injects mouse deltas only while L2 is held and RE4R has focus, and
  suppresses gyro while the right stick is deliberately moved. Settings live
  in the separate `Native Gyro` UI and are persisted to
  `DualSenseEnhanced/native_gyro.json`. It may still switch visible RE4R prompts to
  keyboard/mouse while active.
- Gyro presets (Precision/PS5 Feel/Fast Flicks/Stable/Custom), an Invert Y
  (pitch) toggle, and an activation mode (While Holding L2 / Always On) are
  implemented in `native_gyro.lua`. Precision is the new default
  (yaw 500, pitch 450, deadzone 0.020, calibration 1000ms), replacing the old
  raw test defaults (600/600/0.030/1500ms). Manual slider edits switch the
  shown preset to `Custom`; `Always On` is implemented as an L2 threshold of 0
  written to `native_gyro.json` rather than a second code path.
- **Gyro UI placement**: the `Native Gyro` section is a **top-level tree node**
  in `DualSenseEnhanced.lua`, always visible regardless of `output_mode`. A warning
  is shown when the backend is not native. It was previously buried 4 levels
  deep inside Config → Native Game API.
- **duaLib IMU struct offsets (confirmed live, 2026-06-30)**:
  `AccelerationX/Y/Z` at byte offsets 28/32/36 in `s_ScePadData` (floats);
  `AngularVelocityX/Y/Z` at 40/44/48. duaLib reports acceleration in **g**,
  NOT m/s² — a flat resting controller reads |a| ≈ 0.97, not 9.81.
  `GyroMotionSample` carries `AccelX/Y/Z` and `AccelMagnitude` property.
- **Gyro aim drift fix (2026-06-30)**: calibration now rejects windows where
  the accelerometer magnitude deviates from 1.0g (±0.15g). Old gyro-only
  spread check was self-referential; accel magnitude is the independent
  "controller is actually still" signal. Up to 5 retries before force-accept.
  Background recalibration (α=0.01 EMA) nudges bias whenever `IsAtRest()` is
  true outside active aiming, correcting thermal drift mid-session.
  `IsAtRest(sample)`: `|sample.AccelMagnitude - 1.0| < 0.15`.
- Adaptive trigger presets (Off/Native Only/Light/Enhanced/Strong/Custom) with
  a global intensity multiplier and per-weapon-class (pistol/shotgun/rifle/
  automatic/magnum) multipliers are implemented in the new
  `trigger_intensity.lua`. It scales the l2/r2 effect strength that
  `dualib_trigger_ipc.lua` already derives from `weapon_trigger_profiles.lua`;
  `weapon_trigger_profiles.lua` itself is untouched. `Enhanced` keeps every multiplier at
  1.0, so existing confirmed weapon profiles are unchanged unless the user
  picks another preset.
- **Critical bug fixed (2026-06-30)**: `Off`/`Native Only` presets must NOT
  gate `IPC.tick()`'s watcher-ready marker. The old code called
  `TI.disables_ipc()` there, which killed the watcher entirely — since gyro
  shares that same watcher, choosing Off/Native Only for triggers silently
  disabled gyro too. Fixed: `disables_ipc()` is UI-label-only; watcher always
  starts. Off/Native Only only means `scale_effect` returns a zero-strength
  effect for L2/R2.

## HP LED

- HP colors update correctly during active gameplay.
- HP danger/heartbeat is driven by game Vital `Danger` from `getHitPointVital`. Caution colour remains a visual percentage fallback below the configurable caution-start ratio (default 60%) until Vital reaches `Danger`.
- Current HP system is confirmed working well and should be kept as-is.
- HP color driven through LED bus (`hp_gradient`, `hp_danger`, `hp_heal` sources).
- After an event releases the lightbar, HP returns with a configurable 10% to 100% brightness fade (default 30 frames), independent of HP state.
- Heal transition: smooth lerp from heal colour → HP colour over ~4 seconds (240 frames). Fixed in v0.3.
- `in_gameplay` gate prevents HP LED from showing in main menu on first launch. Working.
- Death detection: clears HP LED. Working via polling + `get_CurrentHitPoint <= 0`.
- `Danger` Vital triggers the low-HP heartbeat LED mode: pure red `255,0,0` at the HP value where `Danger` began, fading proportionally by current HP down to 1 HP; death cleanup remains unchanged.
- bHaptics RE4 plugin strings revealed the useful low-HP path: `CharacterManager.getPlayerContextRef` -> `get_HeadUpdater` -> `get_Context` -> `getHitPointVital`, logging `Vital=Fine/Caution/Danger/Poison/Dead`. In-game test confirmed `hp vital: Danger(2)` and `low hp heartbeat: vital`.
- The direct `chainsaw.Ch6CommonBodyUpdater.on_low_hp_heartbeat` hook was removed because this runtime reports it as `NOT FOUND`.
- The experimental Wwise HP-ratio fallback was removed after Vital-state detection was confirmed.
- `via.Application.HeartbeatEnabled` exists in the dump, but it is an engine/application timing flag near `FrameCount`, `DeltaTime`, `MaxFps`, and `HasFocus`; do not treat it as HP heartbeat.

### HP Colour Ranges

| HP Range | Behaviour |
|---|---|
| Above `abs_healthy` (default 800) | Solid green |
| `abs_caution` → `abs_healthy` | Gradient yellow-green → orange |
| `abs_danger` → `abs_caution` | Danger blink, orange → bright red |
| `abs_dim` → `abs_danger` | Danger blink, bright red → dim red |
| Below `abs_dim` / dead | LED off |

- Default threshold mode: `absolute` HP units (not percent), because max HP scales with upgrades.
- Ratio mode also available as fallback.

## Ammo Indicator

- Player indicator (5 LEDs) shows ammo in two modes:
  - **Warning**: silent until `ammo <= warn_threshold`, then counts down. Default.
  - **Proportional**: always shows ammo/max ratio.
- Empty mag: amber blink on lightbar.
- Last bullet: first LED blinks.
- Reload feedback uses actual ammo increases instead of reload hooks:
  - `+1` ammo below 5 shows the current loaded count on the 5 player-indicator LEDs.
  - Instant/multi-round increases, or reaching 5+ ammo, blink all 5 player-indicator LEDs twice.
- Mic LED feedback:
  - Empty ammo keeps Mic LED in Pulse mode while the weapon is empty.
  - Reload finish sends a short Mic LED Pulse.
  - Reload finish sends `Off` after the configured reload Mic LED pulse duration if the weapon is no longer empty.
- Experimental reload lightbar feedback is disabled by default because `execReloadStart` also fires from aim/weapon-state transitions.

## Menu / Gameplay State

- Main menu on first launch: no HP LED. Working.
- Death cleanup: LED off. Working.
- `onStartInGame` hook: resets effects and enables HP/ammo outputs immediately.
- Repeated death/Continue recovery is confirmed working for HP, ammo indicator, and Mic LED.
- `events_led.lua` uses live HP context plus `PlayerManager` adaptive-feedback activity as gameplay recovery signals.
- HP can recover without waiting for weapon data; ammo/Mic resume when weapon polling resolves a real equipped weapon.
- `weapon_equip_core.lua` checks `get_CurrentPlayer`, `getPlayerContextRef`, `get_ManualPlayer`, then `InventoryManager`, preferring a controller with an equipped weapon.
- Timer-based retry/Continue delay was tested and rejected: it made the second Continue session lose all LEDs. Need a real "gameplay/control restored" hook or state.
- `CampaignManager.onStartInGame` can fire during Continue loading, so it is too early to be the sole enable signal after death/retry.
- `chainsaw.GameStateInGame.setup/enter/leave` hooks were rejected. `setup` fired repeatedly during startup and could break launch; do not hook these lifecycle methods directly.
- `ammo_led.lua` resets cached ammo/weapon/reload state both when gameplay disables and when it re-enables, so retry starts from a clean ammo indicator baseline.
- Polling plus `PlayerManager.get_CurrentPlayer` handles return-to-menu cleanup.
- Returning from gameplay to main menu clears lightbar and player indicator. Working.
- Cutscene/pause/loading suppression is no longer an active mod feature. The
  old manual `Force cutscene gate` UI, `EventsLed.set_cutscene`, and
  Movie/Timeline diagnostics were removed from runtime code; keep this topic
  in `IDEAS.md` unless the user explicitly reopens it.
- After disabling bad `sdk.hook` experiments, a full game/REFramework process restart may be required; script reload may leave previously installed native hooks active until the process exits.
- `events_led.lua`, `ammo_led.lua`, and `hp_led.lua` use generation guards so future `Reset Scripts` reloads do not leave old per-frame callbacks or hooks mutating current LED state. Versions loaded before the guard still require a full process restart.

## Confirmed Working Hooks

See `docs/game_events.md` for full details.

| Class | Method | Purpose |
|---|---|---|
| `chainsaw.PlayerHeadActionSign` | `onHitParry` | Parry LED flash |
| `chainsaw.PlayerHeadActionSign` | `onHitDamageCheck` | Damage LED flash |
| `chainsaw.LargeActionSign_Grab3GuiBehavior` | `recieveGuiParam` | Grab QTE start |
| `chainsaw.LargeActionSign_Grab3GuiBehavior` | `onDeactivateEvent` | Grab QTE end |
| `via.hid.Gamepad` | `getMergedDevice(0)` + `get_Button()` | Cross press edges during grab QTE |
| `chainsaw.PlayerBaseContext` | `get_IsFatalKick` / `get_IsFatalRoundKick` | Purple Fatal Kick LED polling |
| `chainsaw.EnemyBodyHitDriver` | `onHitDamage` | Fatal Kick impact while fatal state is active |
| `chainsaw.PlayerEquipment` | `execReloadStart` / `execReload` fallback | Pending reload request; audio starts only after reload-state confirmation |
| `chainsaw.PlayerBaseContext` | `get_IsReloading` / `get_IsExReload` | Confirm actual reload session and stable exit |
| `chainsaw.Melee` | `onHitAttack` | General knife/melee impact audio only |
| `chainsaw.PlayerBaseContext` | `get_IsHookShot` | Cyan-blue Hookshot LED polling |
| `chainsaw.CampaignManager` | `onStartInGame` | Gameplay start reset |
| `chainsaw.CsInventoryController` | `applyUseResult` | Shipped item-use detection with per-item healing audio/haptics routing; see `docs/TASK_HEAL_ITEM_HOOK.md` |

- **2025-06-30: `onStartInGame` is confirmed to fire in the same
  wall-clock second as Capcom's own native lightbar transition from
  boot/menu blue to gameplay color**, found by decoding real RGB values
  out of hooked `set_LightBarColor` calls and cross-referencing the
  timestamp against `events_led.lua`'s own state log. `via.Color` hook
  args here are passed by value as a packed little-endian RGBA uint32, not
  a pointer -- `sdk.to_valuetype`/`sdk.to_managed_object` fail on it,
  `sdk.to_int64(args[2])` reads it correctly (decode:
  `r=packed%256, g=floor(packed/256)%256, b=floor(packed/65536)%256,
  a=floor(packed/16777216)%256`). This finally answers the long-open
  question of "what hook fires at the same moment as real gameplay
  control start, not just the load-press": it was already `onStartInGame`
  all along -- the actual bug was a *different* path
  (`adaptive_gameplay_signal`, triggered by `PlayerManager` adaptive-
  feedback activity) enabling gameplay outputs ~6 seconds early on a
  fresh load, before `onStartInGame` ever fired. Fixed by gating that
  path on `ever_started_in_game` (set inside the `onStartInGame` handler)
  so it only acts as death/Continue recovery, its original intent, never
  as the initial-load enable. Hardware-confirmed: fresh load now lights
  the custom lightbar in sync with Capcom's own transition, and a death/
  Continue cycle still recovers correctly through the same path.
- **Follow-up same day**: `ever_started_in_game` only protected the
  *first* load of a process lifetime (it was set `true` once and never
  reset), so a second load within the same `re4.exe` session -- e.g. main
  menu -> load save again -- still let `adaptive_gameplay_signal` fire
  early, this time re-enabling `EVENTS.in_game` (and therefore
  `dualib_trigger_ipc.lua`'s adaptive triggers) before real gameplay,
  physically felt as L2/R2 resistance during the loading screen. Fixed by
  resetting `ever_started_in_game = false` inside `poll_game_state()`'s
  existing in-gameplay-to-menu transition. Hardware-confirmed to also
  cover reloading a checkpoint without ever returning to the main menu --
  broader than the menu-transition fix alone implied, likely because
  `has_player` already drops out briefly during any load transition.
- **2026-07-12: `chainsaw.CsInventoryController.applyUseResult(chainsaw.ItemID, chainsaw.ItemUseResult)`
  confirmed as the item-use-with-ID hook** (docs/TASK_HEAL_ITEM_HOOK.md).
  `chainsaw.ItemID` reads correctly as a direct `sdk.to_int64(args[3])` (it's
  a C#-enum-backed value, not a struct) — live-confirmed exact ID matches
  for Chicken Egg and First Aid Spray. Does not fire on weapon/throwable
  equip (grenade). **Wired and shipped 2026-07-13:** `audio_feedback.lua`
  stores the item ID and routes herbs, spray, three egg types, three fish
  types, viper, and rhinoceros beetle to distinct speaker and companion-haptic
  stems. The existing HP-delta path still determines when healing playback
  occurs. `useItem` does not
  exist on this type — an earlier probe hooking that name is suspected to
  have hit an unrelated near-per-frame method and hung the game via
  unbounded per-call disk I/O; any hook-based probe on this controller
  should keep a hard write-count cap regardless of assumed call frequency.
- **Symmetric finding, same diagnostic technique**: a death -> return to
  main menu transition was captured the same way (output mode `off`, so
  Capcom had full native lightbar control). Capcom's lightbar held steady
  native danger red (`180,0,0`, its own HP-low gradient, distinct from
  this mod's colors) right up to one specific second, then switched to
  menu blue (`0,14,56`) and held. `events_debug.txt` showed
  `CampaignManager.onStartInGameCleanup` firing in that exact same second
  (`hpDead=true validHP=false outputs=false`). This is the exit-side
  mirror of `onStartInGame`: already a confirmed/used hook
  (`events_led.lua`'s handler already clears/requests-disable gameplay
  outputs there), already correctly timed -- no bug found, just
  confirmation that the existing death/menu-return path is synchronized
  with Capcom's own transition, same as the load/gameplay-entry path.

## Confirmed NOT Working / Not Found

These methods were attempted but do not exist in RE4R:
- `CampaignManager.onStartTitle`
- `CampaignManager.onStartPause`
- `CampaignManager.onStartLoading`
- `CampaignManager.onStartResult`
- `CampaignManager.onStartGameOver`
- `CampaignManager.onPlayerDead`
- `PlayerBaseContext.onDead`
- `HitPoint.get_IsDeadState`
- `chainsaw.CsInventoryController.useItem` (does not exist; 173-method
  enumeration confirmed no such name)
- `chainsaw.RecoveryController`, `chainsaw.PlayerItemController`,
  `app.UseItemAction`, `chainsaw.ItemUseController`, `chainsaw.HealManager`,
  `chainsaw.VitalController`, `chainsaw.PlayerInventoryManager`,
  `chainsaw.PlayerHealth` (types not found in this build)
- `chainsaw.CsInventoryController.onItemUsed` (exists, hooks cleanly, never
  fires on a real item use)

## LED Priority Table

| Priority | Source name | Effect |
|---|---|---|
| 100 | `parry` | One blink: configured colour, then black, over the configured duration |
| 90 | `grab` | White Cross-input flash; black between flashes during grab QTE |
| 85 | `finisher` | Fatal Kick: black wind-up, short purple impact flash, then black until animation ends |
| 84 | `hookshot` | Cyan-blue Hookshot state |
| 80 | `damage` | Red flash on hit |
| 50 | `hp_heal` | Blue→HP colour lerp on heal |
| 30 | `reload` | Warm yellow reload state/flash |
| 20 | `ammo_empty` | Amber blink on empty mag |
| 10 | `ammo_last` | (indicator only) |
| 2 | `menu` | Dim colour in menu (optional) |
| 1 | `hp_gradient` | Normal HP colour |
| 1 | `hp_danger` | Danger blink |

## External Research

### bHaptics RE4 Mod

Investigated a third-party RE4R haptics mod.

Useful discovered methods:

- chainsaw.PlayerEquipment.execReloadStart
- chainsaw.CharacterBodyUpdater.onEquipChange
- chainsaw.PlayerHeadUpdater.onChangeHitPoint
- chainsaw.Context.getHitPointVital
- chainsaw.PlayerBodyUpdater.onChangeJacked
- chainsaw.Melee.onHitAttack
- chainsaw.PlayerBodyHitDriver.onHitDamage

Validation status differs by method:

- `PlayerEquipment.execReloadStart`: confirmed, with reload-state confirmation
  required for reliable audio.
- `Context.getHitPointVital`: confirmed for HP state.
- `Melee.onHitAttack`: confirmed broad melee/knife-hit audio hook; rejected for
  finisher-only LED logic.
- The remaining methods in this list are still unvalidated here.

### Experimental / Rejected Hooks

- chainsaw.PlayerEquipment.execReloadStart: hooked for experimental reload LED; confirmed to trigger, now extended via reload state polling.
- chainsaw.PlayerEquipment.onReloadStart: not found in this RE4R build.
- chainsaw.Melee.onHitAttack: too broad for LED finisher feedback; fires on
  general knife/melee hits for player and enemies. It is now used for
  general knife/melee impact audio.
