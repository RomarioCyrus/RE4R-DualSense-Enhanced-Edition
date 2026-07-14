# BUGS.md — Active Bugs

## Resolved: All LED/Trigger Output Dead After Reset Scripts Mid-Gameplay

**Priority:** Medium
**Status:** Resolved 2026-07-10 (hardware-confirmed)

- After a REFramework **Reset Scripts** triggered while already in active
  gameplay, the lightbar, adaptive triggers, ammo indicator, and Mic LED all
  stayed off. Output only came back after exiting to the menu or reloading a
  save — both of which fire `CampaignManager.onStartInGame`.
- Root cause (confirmed empirically via `events_debug.txt`: `gen=1` and
  `prev=nil` on every reset): this REFramework build **fully resets the Lua
  state** on Reset Scripts. `_G` does NOT persist across a reload — the
  generation counter returns to 1 and `_G.EventsLed` is nil. The earlier
  preservation-based fix attempts (seeding `in_game` from `_prev`, and the
  preserved `owns_lightbar`/`cached_color`/blackout flags in
  `native_feedback.lua`) therefore never actually ran. With no preserved
  state and no `onStartInGame` on a Reset Scripts, nothing ever re-enabled
  gameplay outputs.
- **Do not rely on `_G` surviving Reset Scripts in this build.** Generation
  guards still no-op stale `sdk.hook` callbacks correctly, but any state a
  reloaded script needs must be re-derived from the live game, not read back
  from `_G`.
- Fixed in `events_led.lua` by live-polling instead: `poll_game_state` arms a
  one-shot `reset_recovery_pending`; if valid non-dead player HP context holds
  for 2 consecutive poll cycles (~1 s) and no real `onStartInGame` has fired,
  it calls `begin_pending_gameplay_enable("reset scripts recovery")`. A fresh
  boot sits in the menu with invalid HP context, so recovery never misfires
  there; it disarms once a real `onStartInGame` runs.
- **Follow-up (2026-07-11, confirmed):** the recovery misfired on the first
  cold-start load — lightbar/triggers lit during the initial loading screen,
  because on a cold start HP context goes valid mid-load, several seconds
  before `onStartInGame`, satisfying the "valid for 2 cycles" condition. Fixed
  with a first-poll discriminator: a mid-gameplay Reset Scripts has valid HP
  *immediately* (engine keeps running, only Lua reloads), so if the FIRST poll
  after load has no valid HP context it's a cold start and
  `reset_recovery_pending` disarms permanently, leaving the first enable to
  `onStartInGame`. Both paths confirmed in-game.

## Resolved: Custom Lightbar/HP LED Lit During Loading, ~6s Before Real Gameplay

**Priority:** Medium
**Status:** Resolved 2025-06-30

- The custom lightbar/HP LED activated during the level-loading screen,
  visibly earlier than Capcom's own native lightbar transition from
  boot/menu blue to gameplay color (confirmed by decoding real RGB values
  from hooked `set_LightBarColor` calls and timestamp-correlating against
  `events_led.lua`'s state log -- see `MEMORY.md`).
- Root cause: `adaptive_gameplay_signal()` (a `PlayerManager`
  adaptive-feedback-driven recovery path, meant only for death/Continue)
  had no guard against firing on the very first load of a session, and
  enabled gameplay outputs ~6 seconds before `CampaignManager.onStartInGame`
  -- which turned out to already be correctly timed and already in use.
- Fixed by gating `adaptive_gameplay_signal` on a new `ever_started_in_game`
  flag, set only inside the `onStartInGame` handler, so the recovery path
  can never fire before a real `onStartInGame` has happened at least once.
- Hardware-confirmed: fresh load now lights the lightbar in sync with
  Capcom's own transition; a death/Continue cycle still recovers correctly.
- **Follow-up bug found same day**: `ever_started_in_game` was set once
  and never reset, so it only protected the first load per process
  lifetime. A second load (main menu -> load save, same session) let
  `adaptive_gameplay_signal` fire early again, this time enabling adaptive
  triggers (`dualib_trigger_ipc.lua`) before real gameplay -- physically
  felt as L2/R2 resistance during the loading screen. Fixed by resetting
  the flag inside `poll_game_state()`'s existing in-gameplay-to-menu
  transition. Hardware-confirmed, including the case of reloading a
  checkpoint without ever returning to the main menu.

## Resolved: Lightbar Stuck Black on Menu Exit

**Priority:** Medium
**Status:** Resolved 2026-07-01

- After exiting gameplay to the main menu with no custom menu color configured,
  the lightbar stayed black instead of restoring Capcom's own blue.
- Root cause: `native_feedback.lua`'s `apply_lightbar()` called
  `write_lightbar("resetLightBarColor")` whenever releasing ownership. That
  call permanently resets Capcom's own cached color with nothing to restore it —
  Capcom only calls `set_LightBarColor` again on its own state changes, not
  continuously, so once reset to black there was nothing left to make it repaint.
  Same call existed in the `lightbar_enabled=false` branch and in `NATIVE.release()`.
- Fixed by removing all three `resetLightBarColor` calls. On release, just set
  `NATIVE.owns_lightbar = false` and clear `cached_color`/`last_written_color`;
  Capcom's next natural call (hardware-confirmed to be `onStartInGameCleanup`)
  repaints correctly. Never call `resetLightBarColor()` when releasing ownership.
- First retest still appeared stuck — false alarm: `EVENTS.menu_enabled` was
  still on from earlier testing with `EVENTS.color_menu` set to red. After
  disabling that checkbox everything works correctly.
- **Hardware-confirmed**: exiting to menu now shows Capcom's own blue.

## Resolved: All LED/Trigger Output Stays Active on Player Death

**Priority:** Medium
**Status:** Resolved 2026-07-02; live-tested 2026-07-04

- On death, lightbar continued showing the last HP color (red from `hp_danger`),
  ammo indicator kept last ammo count, Mic LED stayed active, and L2/R2 adaptive
  triggers kept their last weapon resistance profile.
- Root cause (lightbar): `EVENTS.in_game` stays `true` during death by design.
  The entry-flash `in_game` hold in `apply_lightbar` kept `owns_lightbar = true`
  and `cached_color` at the last red; `device_update_post_hook` enforced it every frame.
- Root cause (triggers): `IPC.tick()` is gated on `EVENTS.in_game == true` — never
  saw a false signal during death, so trigger effects continued writing.
- Fixed by adding `EVENTS.player_dead` flag (in `events_led.lua`) and
  `NATIVE.death_blackout` flag (in `native_feedback.lua`), both set on first
  dead-tick detection and cleared in `begin_pending_gameplay_enable` (recovery)
  and on menu exit. `death_blackout` causes `apply_lightbar` to write `0,0,0`
  every frame, overriding `cached_color`. `player_dead` makes `IPC.tick()`'s
  `gameplay_ready` check false, triggering `IPC.reset()` every frame until recovery.
- 2026-07-04 live result: death cleanup works. Lightbar, player indicators, and
  Mic LED turn off, but not perfectly simultaneously yet because they are
  driven through separate runtime paths/ticks. Future polish: a single forced
  blackout command that clears all controller outputs in one frame.

## Current Status

- Core LED modules are in a stable, user-approved state.
- HP, event effects, ammo indicator, Mic LED, death cleanup, and repeated death/Continue recovery are confirmed working.
- Controller-speaker endpoint routing is confirmed with a connected controller:
  devices appear in the UI, manual switching works, and `Test Speaker` plays on
  the selected endpoint. `Test Parry` was removed as redundant.
- Menu-to-gameplay lightbar entry is confirmed good. Loading from an
  already-active gameplay session can still show Capcom blue before the current
  hook takes ownership; keep this as a follow-up hook-discovery task.
- L2 spam no longer causes gyro drift or stuck haptics in the latest live test.
  Keep it on the watchlist because gyro and trigger effects share the delayed
  duaLib transport. If it returns, investigate atomic `trigger_command.json`
  writes and forced reset/off on L2 release before touching the audio bridge.
- 2026-07-02 post-refactor check: `DualSenseEnhanced` namespace cleanup is
  confirmed working in the deployed game folder. The duaLib trigger mapping
  regression was fixed by robustly loading
  `DualSenseEnhanced/weapon_trigger_profiles.lua`; the lightbar regression was
  fixed by replacing the deployed older trigger-only `duaLib.dll` with the
  `third_party/build_out/duaLib.dll` lightbar-allowled build. User confirmed
  everything now works as expected after redeploy/restart.
- Cutscene/pause/loading suppression has been removed from the active mod and
  moved to `IDEAS.md`; do not track it as an open runtime bug.
- `chainsaw.Melee.onHitAttack` is not suitable for LED finisher feedback because it fires on general knife/melee hits.
- Pickup ID diagnostics are opt-in and silent by default.
- W-870 reload and ordinary delayed post-shot pump are confirmed. Its new
  final-shot deferral branch still needs a focused retest.
- Latest gameplay testing confirmed the correction pass for SG-09 R, Striker,
  Handcannon, Skull Shaker, SR M1903, Broken Butterfly, and the already-stable
  W-870.
- Stingray confirmed working 2026-07-04: normal draw, aim-out, and all
  special-draw stages verified in-game. No longer a known regression.
- The June 25 correction pass for Broken Butterfly, CQBR, Killer7, Skull
  Shaker, SR M1903, Handcannon, and the W-870 last-shot branch is implemented
  but not yet retested.
- Punisher, Red9, Blacktail, and Matilda are new unverified prototypes rather
  than confirmed bugs. Their finish/action cues are intentionally omitted
  until tactical and empty reloads are tested separately.
- Native DualSense and DSX cannot currently coexist cleanly: DSX suppresses
  native Capcom haptics and competes for lightbar ownership.
- 2025-06-29/2026-07-01: player indicators and Mic LED via duaLib are
  hardware-confirmed end-to-end. `ammo_empty`/`hp_danger` continuous-sine
  pulses are confirmed visible and stutter-free. Both pulses are synced to
  the Mic LED (lockstep, not firmware Breathing). duaLib lightbar
  (`IPC.lightbar_enabled`) is confirmed working in live gameplay after the
  `AllowLedColor` guard-block exemption fix. Lightbar stuck-black on menu
  exit resolved by removing `resetLightBarColor()` calls from
  `native_feedback.lua`. `ever_started_in_game` guard prevents early
  lightbar/trigger enable during loading screens on any load, not just the
  first. See `MEMORY.md` and `CHANGELOG.md` for full detail;
  `tools/verify_deploy.ps1` catches deploy drift.

## Resolved: ammo_empty Lightbar Pulse Not Reliably Visible (native mode)

**Priority:** Medium
**Status:** Resolved 2025-06-29

- User reported the empty-mag lightbar feedback (amber blink, priority 20)
  was not visible in native mode even though the Mic LED correctly pulsed
  for the same empty-mag state.
- Root cause not isolated for the original hard on/off blink design
  (alternating full colour vs literal `0,0,0` black every
  `AMMO.ammo_blink_rate` frames); fixed by switching to the same
  continuous-brightness-pulse style already confirmed visible for
  `hp_danger` (never a literal black frame). User confirmed the redesigned
  pulse is visible.
- Side effect: pushing the new continuous pulse to the LED bus every frame
  (instead of once per blink cycle) caused a real stutter, fixed separately
  (see `pulse_push_interval`/`pulse_steps` in `CHANGELOG.md`).

## Test Required: W-870 Pump Cycle Gap Timing

**Priority:** Low
**Status:** Needs in-game test

- `W870_PUMP_CLOSE_GAP_FRAMES` reduced from 20 → 8 frames (~0.13s) after
  bridge fix resolved the FileSystemWatcher race condition that required the
  wider gap.
- If 8 frames still sounds too wide, combine `wp4100_reload_start.wav` and
  `wp4100_reload_finish.wav` into a single WAV and simplify
  `play_w870_pump_cycle()` to a single `emit` call.

## New: Haptic Buzz Noise on Sentinel Nine (wp6000) — Aim and Weapon Select

**Priority:** Low
**Status:** Cause identified (unconfirmed), not yet fixed

- User reports a motor-vibration/haptic-buzz noise specifically when switching
  to the Sentinel Nine (wp6000) and when aiming with it (L2 press).
- **Trigger profile is not the cause:** Sentinel Nine maps to `type:hg`
  (`l2_resistance(3)`, DSX mode 13 Resistance). No Vibration mode (8) anywhere
  on L2 for any handgun profile. Confirmed by tracing `find_mapping_for_info`
  with weapon type `"HG"` → `type:hg`.
- **Likely cause:** the audio bridge plays `wp6000_aim_in.wav` through the
  DualSense speaker on L2 press. DualSense on PC can convert speaker audio
  into physical vibration — low-frequency content in the WAV drives the speaker
  membrane and is perceived as haptic/trigger noise. The WAV files for wp6000
  aim sounds exist as separate files (`wp6000_aim_in.wav`, `wp6000_aim_in2.wav`,
  `wp6000_aim_out.wav`, `wp6000_aim_out2.wav`) but their audio content has not
  been verified for low-frequency artifacts.
- **"When selecting" case:** no explicit weapon-equip/draw event is mapped for
  wp6000 in `wwise_audio_router.lua`. Possible that some Wwise event fired on
  weapon switch coincidentally matches a mapped ID for another weapon, playing
  an unexpected sound. Needs `sound_event_diag.lua` capture during weapon
  selection to identify the firing IDs.
- **To confirm:** temporarily comment out `wp6000_aim_in` (event 3761912333)
  and `wp6000_aim_out` (event 3601070767) in `wwise_audio_router.lua` and test.
  If buzz on aim disappears → source is `wp6000_aim_in.wav`; inspect WAV for
  low-frequency content or replace with a high-passed version.

## New: Gyro Aim Still Drifts In Some Cases Despite Calibration-Reject + Background Correction

**Priority:** Medium
**Status:** Confirmed still occurring 2026-07-04, partially mitigated, root cause not fully identified

- User confirms live: even with today's calibration-rejection and background
  drift-correction additions to `GyroMouseMapper.cs` deployed and active,
  gyro aim still drifts in some cases.
- Live-tested the calibration-rejection path itself in isolation and it is
  working as designed, but surfaced a likely-related tuning problem: in one
  calibration window it rejected 5 consecutive attempts before falling back
  to force-accepting (`(accepted after max retries; aim may drift)`), driven
  entirely by `spreadX`/`spreadZ` exceeding `MaxPlausibleBias` (0.05 rad/s)
  while the *mean* bias each attempt was small and reasonable (e.g.
  X=0.0046, Z=0.0121 rad/s on the accepted attempt -- close to a separately
  observed clean calibration of X=0.0004, Z=0.0101 rad/s). Observed spreads
  during rejected attempts: 0.06-0.20 rad/s.
- **Working theory:** `MaxPlausibleBias` (0.05 rad/s) as a *spread* threshold
  may be tuned too tight for a controller actually held in a hand -- natural
  hand micro-tremor plausibly produces gyro noise in the 0.06-0.2 rad/s range
  on its own, independent of any real drift-causing motion, causing repeated
  false rejections and pushing calibration into the force-accept fallback
  more often than intended. The mean-bias check (also gated at 0.05 rad/s)
  looks correctly tuned by comparison -- every observed mean stayed well
  under it even on rejected attempts.
- Not yet confirmed whether the residual drift symptom is fully explained by
  this (an imperfect force-accepted calibration, before the slow background
  `BackgroundRecalibrationAlpha` correction has had time to converge) or
  whether a separate contributing cause exists -- e.g. the background
  correction only runs via `IsAtRest()` checks while not actively aiming,
  so it may rarely get a chance to run during gameplay sessions with mostly
  continuous aiming.
- **To investigate:** loosen or split the spread threshold from the mean-bias
  threshold (e.g. allow a wider spread tolerance while keeping the mean check
  strict), and/or log `IsAtRest()` trigger frequency during a real play
  session to check whether background correction is actually getting enough
  opportunities to run.

## Deferred: Native DualSense / DSX Output Conflict

**Priority:** Medium  
**Status:** Confirmed limitation; deferred

- With DSX closed and Steam Input disabled, RE4R native DualSense support
  provides partial haptics and correct native LED behavior.
- Starting DSX in native or DualSense-emulation mode removes native haptics and
  causes LED flicker/state contention.
- This also occurs in other native-DualSense games without this RE4R mod, so
  disabling the REFramework payload alone is not expected to solve it.
- Do not attempt to merge native and DSX HID ownership in the stable branch.

## Deferred: Native Audio-To-Haptics Coexistence

**Priority:** Low  
**Status:** Experiment completed; no reliable coexistence

- The DualSense 4-channel endpoint opens successfully in native RE4R mode, but
  actuator tones are silent while Capcom native vibration mode is active.
- One-shot and five-report/200 ms HID audio-haptics selection tests were
  accepted by the DualSense Edge but still produced no reliable vibration.
- Preserve the experimental probe for research; do not auto-start or integrate
  it into the stable bridge.

## 0. HP/Ammo/Mic LED Disabled After Death Retry

**Priority:** Resolved  
**Status:** Confirmed working

**Symptom:**
- After death, ammo indicator and Mic LED could go dark and stay inactive until returning to the menu and entering gameplay again.
- On another death/retry attempt, ammo indicator stayed active but HP lightbar stayed off.
- The bug was intermittent and reproducible only after several death/retry cycles.
- Additional clue: after pressing `Continue`, HP LED could light during the loading screen, before real gameplay resumed.
- Delayed retry enable made session 2 worse: no LEDs worked after Continue, so timer-based retry gating was rejected.

**Root cause (suspected):**
- `poll_game_state()` sometimes saw the player context disappear during game-over/retry and disabled gameplay outputs.
- On retry, a live player context could reappear without `CampaignManager.onStartInGame` firing.
- `CampaignManager.onStartInGame` can also fire with `WeaponEquipCore.last_info = None 0/0`; enabling outputs at that point lets a following loading/menu poll clear HP/ammo again with no later re-enable.

**Patch notes:**
- `events_led.lua`: added `death_state_active` tracking.
- On death, gameplay outputs are explicitly cleared and disabled, including ammo/player indicator and Mic LED empty state.
- When a live player context returns after a known death state, recovery now waits for `PlayerManager.get_CurrentPlayer` or valid `WeaponEquipCore.last_info` before re-enabling HP/ammo outputs.
- `ammo_led.lua`: `AMMO.set_gameplay(true)` now resets cached ammo/weapon/reload state, so retry cannot keep stale `last_ammo`/weapon data.
- `events_led.lua`, `ammo_led.lua`, `hp_led.lua`: added generation guards for future script reloads; stale callbacks from versions loaded before this guard still require a full game restart.
- `events_led.lua`: added diagnostics for Continue/loading/gameplay-state candidates and state snapshots around death, `onStartInGame`, and recovery.
- `events_led.lua`: if `onStartInGame` fires before weapon context is valid, gameplay LED enable is now deferred until polling sees both player context and valid weapon info.
- Normal first-load protection still remains: a random early player context cannot enable gameplay outputs unless it follows a death/retry recovery or `onStartInGame`.

**Current conclusion:**
- `CampaignManager.onStartInGame` is too early for `Continue`; it can fire during loading.
- Rejected `chainsaw.GameStateInGame.setup/enter/leave`: `setup` spammed during startup and made the game fail to launch cleanly.
- Final recovery uses live HP context plus `PlayerManager` adaptive-feedback activity.
- HP can recover without waiting for weapon data; ammo/Mic resume when `weapon_equip_core.lua` resolves a real equipped weapon.
- Inventory fallback now prefers a `CsInventoryController` with an equipped weapon instead of the first controller.

**Verification:**
- Repeated death -> Continue cycles confirmed HP, ammo indicator, and Mic LED recovery.

## Experimental: Native Game API Feedback Backend

**Priority:** Experimental  
**Status:** Lightbar confirmed; native triggers rejected

- Native `via.Color` construction and custom gameplay lightbar output are
  hardware-confirmed.
- Calling RE4R's exposed native adaptive-trigger API caused a confirmed game
  crash. Native trigger output is now rejected and hard-disabled.
- The guarded PlayerManager-level L2 probe failed safely because no live
  `chainsaw.PlayerManager` was available. Its `onUpdate` capture hook also
  remained idle. Stop this probe; it does not replace the missing native
  output transport.
- Native lightbar output flickered when Capcom and the mod wrote concurrently.
  Setter ownership hooks alone were insufficient because Capcom reapplied
  cached color during device update. The post-update final-write hook is
  hardware-confirmed in gameplay.
- Player indicator and Mic LED are not included in the native MVP.
  Dump review confirms no managed DualSense player-indicator setter exists;
  this is a native-mode limitation, not a pending lightbar bug.

- Native menu override does not currently replace Capcom's blue menu
  lightbar. Deferred/non-critical.
- Native low-HP black/dim-red rest phases were rejected. Red/orange pulse is
  confirmed working.
- RE4R managed trigger calls remain rejected. The separate trigger-only duaLib
  transport is hardware-confirmed; retain its delayed-start and output-field
  suppression safeguards. Direct HID is still deferred because a second blind
  full-report writer may conflict with Capcom's compound output reports.

## 1. Stale HP LED After Returning To Main Menu From Gameplay

**Priority:** High  
**Status:** Resolved

**Symptom:**
- Main menu is clean on first launch. ✅
- Main menu is clean after death. ✅
- But quitting from gameplay back to main menu leaves the last HP effect active.

**Root cause (suspected):**
- `poll_game_state()` uses `has_player = CharacterManager.getPlayerContextRef != nil`.
- In RE Engine, the player context likely stays alive after returning to main menu.
- So `in_gameplay` stays `true` and HP LED is never cleared.

**Patch notes:**
- `events_led.lua`: uses `PlayerManager.get_CurrentPlayer` as active gameplay signal.
- `events_led.lua`: clears HP, event, ammo LED sources and player indicator on non-gameplay transition.
- `ammo_led.lua`: added `AMMO.set_gameplay()` and blocks indicator updates outside gameplay.
- `feedback_writer.lua`: always writes explicit black lightbar and disabled player indicator when inactive.

**Historical verification checklist:**
- Launch game -> main menu -> main lightbar off, player indicator off.
- Load save -> LEDs work normally in gameplay.
- Quit from gameplay to main menu through menu -> both lightbar and player indicator turn off within ~1 second.

**Investigation points:**
- `events_led.lua` → `poll_game_state()`
- `CharacterManager` — does `getPlayerContextRef` return nil in title screen?
- `CampaignManager` — are there any methods that fire on return-to-title? (Not found yet, see `docs/game_events.md`)
- Scene/flow managers in `chainsaw.*` namespace

**Possible fixes:**
- Find a `CampaignManager` method that fires on title/menu — hook it.
- Add a secondary check: e.g. `PlayerManager.get_CurrentPlayer` returns nil in menu.
- Check if `CharacterManager.getPlayerContextRef` actually does return nil in menu.
- Poll `Application` or scene name to detect title screen.

---

## 3. Effect Priority Review

**Priority:** Low  
**Status:** Verified

**Notes:**
- Parry (100) > Grab (90) > Damage (80) > Heal (50) > HP (1) — correct order.
- Grab priority over damage is confirmed; `trigger_damage()` returns early while `grab_active == true`.
- Verify heal lerp doesn't restart every HP poll tick.
  - Guard: `if heal_active then ... return end` at poll entry.

## Resolved

### ~~Grab QTE blinking lifecycle~~ ✅ Resolved

- QTE start/end is driven by `LargeActionSign_Grab3GuiBehavior.recieveGuiParam` / `onDeactivateEvent`.
- New Cross presses flash white; pauses after the first press are black.
- Confirmed with front and back grab variants, with immediate cleanup when QTE closes.

### ~~Healing Gradient Lasting ~14 Seconds~~ ✅ Fixed in v0.3

- Root cause: `tick_led_sources()` was called inside `apply_for_weapon()` instead of per-frame.
  - `frames=240` decremented once per weapon heartbeat (~60 real frames each) = ~14400 frames total.
- Fix: moved `tick_led_sources()` to `re.on_application_entry("UpdateBehavior")` in `feedback_writer.lua`.
- Heal lerp now runs correctly at ~4 seconds.

### ~~Green HP LED in Main Menu On First Launch~~ ✅ Fixed in v0.2

- Fix: added `in_gameplay` gate in `hp_led.lua`.
- HP LED only renders when `in_gameplay == true`.
- Set to `false` by default, `true` after `onStartInGame`.

## Research Task

Evaluate whether onChangeHitPoint can replace HP polling.

Potential benefits:
- More accurate healing detection.
- Reduced polling logic.
- Cleaner healing transitions.
