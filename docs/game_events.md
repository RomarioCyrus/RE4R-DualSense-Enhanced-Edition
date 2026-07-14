# docs/game_events.md — RE4R Game Events & Hooks

All hooks are in the `chainsaw.*` namespace (RE4R uses "chainsaw" as its app namespace).
Hooks are installed via `sdk.hook(method, pre_fn, post_fn)`.
All hook bodies should be wrapped in `pcall`.

---

## Confirmed Working Hooks

### Wwise Event Timing

| Field | Value |
|---|---|
| Class | `soundlib.SoundManager` |
| Method | `postRequestInfo` |
| Hook point | pre |
| Status | Confirmed in game and on DualSense speaker |
| Trigger | Wwise event request is about to be posted |
| Usage | Low-latency Wwise event ID -> extracted WAV / future haptics routing |
| Notes | `RequestInfo.get_EventId` is available in the managed argument. For SG-09 R dry fire, `postRequestInfo` emitted `event_id=2330373695` at `953.538`, playback was written at `953.541`, and `onEndOfEvent` for the same ID arrived at `954.086`. Use this for timing-sensitive output. |

Related hook status:

| Class | Method | Status | Notes |
|---|---|---|---|
| `soundlib.SoundManager` | `postEvent` | Useful fallback/diagnostic | Also exposed SG-09 R dry-fire ID as a raw argument after `postRequestInfo`. |
| `soundlib.SoundManager` | `onEndOfEvent` | Confirmed but late | Good for cataloging and cross-checking event IDs; too late for synchronized playback/haptics. |
| `via.simplewwise.Driver` | `callbackGlobal` | Rejected for ID mapping | Fires early but only exposed callback flags in the tested path, not a usable event ID. |

Confirmed Wwise event mappings:

| Wwise event ID | Weapon/context | Extracted group | Runtime audio event | Status |
|---|---|---|---|---|
| `2330373695` | SG-09 R (`wp4000`) empty trigger / dry fire, `ammo=0` | `event_0260` | `wp4000_dry_fire` | Confirmed in game and on controller speaker with synchronized playback |

## Native DualSense Output API Candidates

Implemented experimentally, awaiting physical verification:

| Type | Method | Intended use |
|---|---|---|
| `share.hid.Device` | `setLightBarColor(via.Color)` | Custom lightbar through the game's controller object |
| `share.hid.Device` | `resetLightBarColor()` | Release lightbar state back to Capcom |
| `share.hid.Device` | `setAdaptiveTriggerFeedback(...)` | Rejected: confirmed game crash |
| `share.hid.Device` | `resetAdaptiveTriggerFeedback()` | Disabled with the rejected native trigger path |

The active native device must be `via.hid.VendorNativeDualSenseDevice`. These
are output APIs, not gameplay hooks, and are not yet confirmed working.

### Parry

| Field | Value |
|---|---|
| Class | `chainsaw.PlayerHeadActionSign` |
| Method | `onHitParry` |
| Hook point | post (return hook) |
| Status | ✅ Confirmed in game log |
| Trigger | Player successfully parries an attack with knife |
| Usage | Trigger parry LED flash, clear grab effect |
| Notes | Fires reliably. Safe to use as parry primary trigger. |

---

### Player Takes Damage

| Field | Value |
|---|---|
| Class | `chainsaw.PlayerHeadActionSign` |
| Method | `onHitDamageCheck` |
| Hook point | post |
| Status | ✅ Confirmed in game log |
| Trigger | Player receives a damage check (hit registered) |
| Usage | Trigger damage LED flash outside grab QTE |
| Notes | Fires during grab damage too — guard with `if grab_active then return end` in damage handler. |

---

### Grab QTE Lifecycle

| Field | Value |
|---|---|
| Class | `chainsaw.LargeActionSign_Grab3GuiBehavior` |
| Start method | `recieveGuiParam` |
| End method | `onDeactivateEvent` |
| Hook point | post |
| Status | Confirmed across front/back grab variants |
| Trigger | Grab QTE widget appears/disappears |
| Usage | Exact `grab_active` lifecycle |
| Notes | Repeated `recieveGuiParam` updates are ignored while grab is already active. |

---

### Gameplay Start

| Field | Value |
|---|---|
| Class | `chainsaw.CampaignManager` |
| Method | `onStartInGame` |
| Hook point | post |
| Status | ✅ Confirmed in game log |
| Trigger | Player loads into gameplay (after loading screen) |
| Usage | Reset all effects, enable HP/ammo output after gameplay starts |
| Notes | Fires on initial load and after loading screens. Good for cleanup + state init. |

---

### HP Vital State

| Field | Value |
|---|---|
| Access path | `CharacterManager.getPlayerContextRef()` -> `get_HeadUpdater()` -> `get_Context()` -> `getHitPointVital()` |
| Status | Confirmed in game |
| Values | `Fine`, `Caution`, `Danger`, `Poison`, `Dead` |
| Trigger | Polled by `hp_led.lua` during gameplay |
| Usage | Primary HP lightbar state source. `Danger` starts pure-red low-HP heartbeat/dim mode. |
| Notes | Discovered from bHaptics plugin strings and confirmed by Event Monitor: `hp vital: Danger(2)` + `low hp heartbeat: vital`. |

---

## HP / Player State Access

### Get Current Player HP

```lua
local cm     = sdk.get_managed_singleton("chainsaw.CharacterManager")
local player = cm:call("getPlayerContextRef")
-- fallback:
if not player then player = cm:call("get_ManualPlayer") end

local hp     = player:call("get_HitPoint")
local cur    = hp:call("get_CurrentHitPoint")   -- current HP (float)
local max    = hp:call("get_DefaultHitPoint")   -- max HP (float)
```

- `cur / max` gives ratio 0.0–1.0.
- Max HP increases with upgrades (base ~1200, upgraded ~3000+).
- Use absolute HP thresholds rather than ratios for consistency.
- Death: `cur <= 0` is the most reliable death check found so far.

---

## Confirmed Not Found / Not Working

These methods were searched for and do not exist in RE4R:

| Class | Method | Notes |
|---|---|---|
| `chainsaw.CampaignManager` | `onStartTitle` | Not found |
| `chainsaw.CampaignManager` | `onStartPause` | Not found |
| `chainsaw.CampaignManager` | `onStartLoading` | Not found |
| `chainsaw.CampaignManager` | `onStartResult` | Not found |
| `chainsaw.CampaignManager` | `onStartGameOver` | Not found |
| `chainsaw.CampaignManager` | `onPlayerDead` | Not found |
| `chainsaw.CampaignManager` | `onExitGame` | Not found |
| `chainsaw.PlayerBaseContext` | `onDead` | Not found |
| `chainsaw.PlayerBaseContext` | `onDeath` | Not found |
| `HitPoint` | `get_IsDeadState` | Not found |

---

## Needs Investigation

### Return To Main Menu Detection

**Goal:** detect when player quits gameplay back to title screen.  
**Why needed:** player context may remain alive after returning to menu, causing `poll_game_state()` to think gameplay is still active.

**Search suggestions:**
```
chainsaw.CampaignManager  → inspect all methods via Object Explorer
chainsaw.GameFlowManager  → may exist
chainsaw.SceneManager     → scene transitions
chainsaw.TitleManager     → title/menu manager
app.GameClock             → game state flags
```

**Approach in Object Explorer:**
1. Open REFramework → Object Explorer.
2. Search `CampaignManager` → inspect instance.
3. Look for fields like `_CurrentState`, `_Phase`, `_GameFlow`, `_IsTitle`.
4. Look for methods starting with `onStart*`, `onExit*`, `onTransit*`.

---

### Item Use Detection (per-item ID, not just heal-delta)

**Goal:** detect specific herb/spray/consumable use (for future per-item
speaker/haptics), not just "HP went up".
**Current fallback still active in `hp_led.lua`:** `cur > prev_hp_abs` HP
increase detection (no item context).

**Status: SHIPPED** (research 2026-07-12; wired 2026-07-13).
Hook stores `last_used_item_id` in `audio_feedback.lua`; `AUDIO.play_heal()`
reads it via `heal_stem_for_item()` to route to per-item WAV stems.
All healing consumables covered as of 2026-07-13:

| Item | Stem | File |
|------|------|------|
| All herb combos (10 IDs) | `heal_herb` | `heal_herb.wav` (3.80s) |
| Herb rare (5% / 20% danger zone) | `heal_herb_rare` | `heal_herb_rare.wav` (6.10s) |
| Herb mock (inverse HP, max 10% at ≥90% HP) | `heal_herb_mock` | `heal_herb_mock.wav` (0.9s) |
| Chicken Egg | `heal_egg` | `heal_egg.wav` (0.19s) |
| Brown Chicken Egg | `heal_egg_brown` | `heal_egg_brown.wav` (0.63s) |
| Gold Chicken Egg | `heal_egg_gold` | `heal_egg_gold.wav` (0.75s) |
| Black Bass | `heal_fish` | `heal_fish.wav` (0.38s) |
| Lunker Bass | `heal_fish_lunker` | `heal_fish_lunker.wav` (0.74s) |
| Black Bass (L) | `heal_fish_large` | `heal_fish_large.wav` (2.55s) |
| Viper | `heal_viper` | `heal_viper.wav` (0.54s) |
| Rhinoceros Beetle | `heal_beetle` | `heal_beetle.wav` (0.77s) |
| First Aid Spray | `heal_spray` | `heal_spray.wav` (original game WEM 363831734) |

| Field | Value |
|---|---|
| Class | `chainsaw.CsInventoryController` |
| Method | `applyUseResult(chainsaw.ItemID itemId, chainsaw.ItemUseResult result)` |
| Hook position | pre-hook (args); item ID is available before the method body runs |
| item_id | `sdk.to_int64(args[3])` — direct raw read, **no** `to_valuetype`/`to_managed_object` needed |
| result info | `args[4]` → `sdk.to_managed_object` → `chainsaw.ItemUseResult`, field `_ResultType` (int; `1` observed on both confirmed successful uses) and `_ResultInfo` (nested `REManagedObject`, unexplored, likely not needed) |

Notes:
- `chainsaw.ItemID` is a plain C#-enum-backed value (329 named constants +
  `value__`), not a struct — reads correctly with a direct
  `sdk.to_int64(args[3])`, unlike other value-type args elsewhere in this
  project that need `sdk.to_valuetype`.
- Hardware/live-confirmed twice with exact ID matches against
  `item_ids.lua`: Chicken Egg (`277080256`) and First Aid Spray
  (`114416000`).
- **Egg ID base gotcha**: egg IDs (`277080256` etc.) are NOT multiples of
  1600. `math.floor(id / 1600) * 1600` gives `277080000`, not `277080256`.
  `EGG_STEMS` keys must use the pre-computed base values, not the raw
  `item_ids.lua` values (herb IDs are exact multiples of 1600 and are
  unaffected). Confirmed bug and fix: `e716219`.
- Fires exactly once per real item use (not per-frame) — safe to hook
  without any throttling.
- Does **not** fire on equipping/selecting a grenade (weapon/throwable path
  is separate, likely `useWeapon`). Confirms this hook is scoped to the
  inventory *consumable-use* action, not weapon actions — a useful
  constraint, not a gap, for future per-item audio routing.
- Not confirmed whether it fires before, after, or the same frame as the
  resulting HP change; likely same-tick given the method name ("apply the
  use result"), but this should be verified empirically (e.g. compare
  `os.clock()` between this hook and `hp_led.lua`'s HP-delta detection)
  before relying on read-after-write ordering in the wiring pass.
- `CsInventoryController.use(chainsaw.InventorySlotType, chainsaw.CsSlotIndex)`
  also fires once per use but only carries the UI *slot* being used, not
  the item ID — not useful for this purpose.
- `chainsaw.CsInventoryController.useItem` does **not exist** on this type
  (173-method enumeration confirmed) — an earlier probe script that hooked
  it by that name is suspected to have resolved to an unrelated, extremely
  hot (near-per-frame) method, and unbounded per-call disk I/O in that
  hook hung the game. Any future probe/hook work on this controller should
  keep a hard write-count cap regardless of expected call frequency.
- `onItemUsed` (+ `add_OnItemUsed`/`remove_OnItemUsed` event pair) exists on
  `CsInventoryController` but a pre-hook on it never fired on a real Green
  Herb use in testing — not a reliable direct call site, do not use.
- Types not found in this build (ruled out, do not re-search):
  `chainsaw.RecoveryController`, `chainsaw.PlayerItemController`,
  `app.UseItemAction`, `chainsaw.ItemUseController`, `chainsaw.HealManager`,
  `chainsaw.VitalController`, `chainsaw.PlayerInventoryManager`,
  `chainsaw.PlayerHealth`. `chainsaw.ItemManager` exists but only exposes
  sub-manager getters (no use-shaped methods). `chainsaw.PlayerCondition`
  exists (4 methods) but none are use-shaped.

Minimal probe snippet (research-only, no audio wiring):
```lua
local t = sdk.find_type_definition("chainsaw.CsInventoryController")
local m = t:get_method("applyUseResult")
sdk.hook(m, function(args)
    local item_id = sdk.to_int64(args[3])
    print("[probe] item used, id=" .. tostring(item_id))
end, function(retval) return retval end)
```

---

### Player Control State

**Goal:** distinguish "player has control in gameplay" from "cutscene" or "loading".

**Status:** Removed from active runtime. This is now an idea/research topic,
not an open mod feature. Do not re-add cutscene/pause/loading suppression to
`events_led.lua` unless the user explicitly reopens it.

**Search suggestions:**
```
chainsaw.PlayerManager.get_CurrentPlayer
chainsaw.PlayerController → get_IsControllable
chainsaw.EventManager → is event/cutscene active
```

Previous implementation, now removed:
- `EventsLed.set_cutscene(true/false)` and the temporary `Force cutscene gate`
  checkbox were removed from the runtime.
- Movie/cutscene diagnostics for `MoviePlayerInfo`, movie managers,
  `EventManager`, and `System.Action<chainsaw.MoviePlayerInfo>` were removed
  from `events_led.lua`.
- Previously tested Movie/Timeline hooks were too noisy and could break stable
  gameplay recovery.

Recent Object Explorer clue:
- `System.Action<chainsaw.MoviePlayerInfo>` / `System.Action\`1<chainsaw.MoviePlayerInfo>` appears to be a movie-player callback/delegate candidate.

Confirmed from debug log:
- `chainsaw.MoviePlayerInfo`: `get_CurrentStatus`, `get_CurrentFrame`, `get_MaxFrame`.
- `chainsaw.MoviePlayer`: `play`, `stop`, `stopMovie`, `updateCleanup`, `getPlayerInfo`, `changeCurrentStatus`.
- `chainsaw.MovieManager`: `playMovie`, `stopMovie`, `skipMovie`, `unloadMovie`, `getPlayerInfo`, `updatePlayerInfoList`.
- `chainsaw.TimelineEventManager`: `playTimelineEvent`, `stopTimelineEvent`, `skipTimelineEvent`, `unloadTimelineEvent`, `getPlayerInfo`.
- `chainsaw.RealTimeTimelineMediator`: `play`, `unload`, `get_IsPause`, `requestPause`, `requestResume`.

## Candidates From bHaptics RE4 Mod

### Reload

Type:
- chainsaw.PlayerEquipment

Method:
- execReloadStart

Status:
- Confirmed hook, used for audio session start after reload-state confirmation.
- Rejected only for direct reload LED feedback.

Current use:
- Start a pending reload request.
- Confirm the request through
  `PlayerBaseContext.get_IsReloading` / `get_IsExReload`.
- Open the weapon-specific audio session.
- Actual ammunition increases trigger insert sounds.
- Stable reload-state exit triggers a finish sound only when the weapon profile
  defines one.

Notes:
- `onReloadStart` was not found in this RE4R build.
- `execReload` exists and is used as fallback if `execReloadStart` is unavailable.
- `execReloadStart` can fire from aim/weapon-state transitions, causing false LED reload feedback.
- Active reload indicator feedback now lives in `ammo_led.lua` and is based on actual ammo count increases.
- The state-confirmation gate prevents false audio starts from the noisy raw
  hook.
- The established SG-09 R, Riot Gun, W-870, Striker, Skull Shaker, SR M1903,
  Broken Butterfly, and Handcannon foundations were physically confirmed.
  Later manual event identification refined several mappings and those changes
  require another pass.
- W-870 and SR M1903 post-shot cycles are detected from ammunition decreases.
  If ammunition remains, the confirmed approximately one-second delay is used.
  If the shot emptied the weapon, the cycle is deferred until reload-state
  exit.
- Handcannon uses the same last-shot/deferred-cycle state, while Broken
  Butterfly and Skull Shaker have independent delayed post-shot events.
- Broken Butterfly, Skull Shaker, and Handcannon still use the final full-ammo
  increase for their normal reload-finish cue where configured.
- Stingray remains regressed. CQBR and Killer7 received corrected phase WAVs
  and now require a focused retest.

---

### Weapon Change

Type:
- chainsaw.CharacterBodyUpdater

Methods:
- onEquipChange
- get_EquipWeaponID

Status:
- Not tested

Potential use:
- Auto-switch DSX weapon profiles

---

### HP Change

Type:
- chainsaw.PlayerHeadUpdater

Method:
- onChangeHitPoint

Status:
- Not tested

Potential use:
- Replace HP polling
- More accurate healing detection

---

### HP Vital State

Path:
- CharacterManager.getPlayerContextRef
- get_HeadUpdater
- get_Context
- getHitPointVital

Status:
- Confirmed. Replaces percentage thresholds for HP lightbar state selection.
- LED pulse

---

### Grab Escape Input Flash

Type:
- via.hid.Gamepad

Methods:
- getMergedDevice
- get_Button

Status:
- Confirmed working, gated by the QTE widget lifecycle.

Potential use:
- While `grab_active` is true, flash the lightbar white when a new Cross press is detected.
- Cross edges are derived from `get_Button()`.
- After the first detected Cross press, the lightbar rests at black between white input flashes, masking damage and HP colours until grab ends.
- `LargeActionSign_Grab3GuiBehavior.recieveGuiParam(...)` opens grab/QTE state.
- `LargeActionSign_Grab3GuiBehavior.onDeactivateEvent()` closes grab/QTE state immediately.
- Repeated `recieveGuiParam` widget updates are edge-filtered and logged only once per QTE.

Notes:
- Rejected hooks: `shieldingDecision`, `onApplyActionEnd`, `onCancelGrapple`, `ButtonMashingEscapeCondition.set_CurrentCount`, and `ActionSignGuiGrabOpenParam.set_IsClose`.

---

### Knife Fatal / Finisher Candidates

Types:
- chainsaw.EnemyBehaviorTreeAction_MFSM_EnableKnifeFatal
- chainsaw.EnemyHeadUpdater.KnifeFatalInfo
- chainsaw.Ch1c0HeadUpdaterCommon

Status:
- Found in Object Explorer; method diagnostics added to `events_led.lua`.

---

### Fatal Kick

Type:
- chainsaw.PlayerBaseContext

Methods:
- get_IsFatalKick
- get_IsFatalRoundKick

Status:
- Implemented via polling from `PlayerInventoryObserver -> _Observer -> _SelfCharacterContext`.

Usage:
- Fatal state opens a black wind-up.
- `EnemyBodyHitDriver.onHitDamage` flashes the configured purple at the actual enemy-damage impact; default duration is 30 frames (~0.5 seconds) and is configurable in the Events UI.
- The lightbar returns to black after the impact flash and clears when fatal kick / fatal round kick state ends.
- The same confirmed `EnemyBodyHitDriver.onHitDamage` impact point emits the
  `fatal_kick` speaker event.
- Runtime audio randomly selects three clean composites (balanced, punchy,
  heavy) with no immediate repeat.
- Each composite layers the common transient and critical layer A immediately,
  then critical layer B after 80-125 ms. The unwanted long environmental layer
  was removed.

---

### Hookshot

Type:
- chainsaw.PlayerBaseContext

Method:
- get_IsHookShot

Status:
- Implemented via polling from `PlayerInventoryObserver -> _Observer -> _SelfCharacterContext`.

Usage:
- Cyan-blue `hookshot` lightbar effect while hookshot movement/action is active.

Potential use:
- Finisher LED effect
- Future haptics/audio finisher cue

Notes:
- `EnemyBehaviorTreeAction_MFSM_EnableKnifeFatal` exposes `fatalActionName` / `Null pointer` fields in Object Explorer.
- Active LED hook not added yet; next step is to inspect `events_debug.txt` method output after game load.

---

### Melee / General Hit

Type:
- chainsaw.Melee

Method:
- onHitAttack

Status:
- Confirmed broad melee/knife-impact hook.
- Rejected for finisher-only LED feedback.

Current use:
- Emit the general knife/melee impact speaker event.

Potential future use:
- Melee haptics.

Notes:
- Fires on general knife/melee hits for player and enemies.
- Not suitable as a finisher-only LED trigger.

---

### Damage

Type:
- chainsaw.PlayerBodyHitDriver

Methods:
- onHitDamage
- get_Damage

Status:
- Not tested

Potential use:
- Damage intensity scaling
- Directional effects

---

### Capcom Native Haptics Pipeline

Types:

- `chainsaw.PlayerHapticsController`
- `soundlib.SoundVibrationManager`
- `soundlib.SoundVibInfoByWav`
- `soundlib.SoundVibrationManager.VibrationInfo`

Methods:

- `PlayerHapticsController.start`
- `PlayerHapticsController.onJointContactTrigger`
- `SoundVibrationManager.triggerVibration`
- `SoundVibrationManager.addVibByWavData`
- `SoundVibrationManager.registerVibrationWaveIndex`
- `SoundVibrationManager.onPostVibrationEvent`

Status:

- Confirmed active on PC as an internal event pipeline.
- PC `IsTargetPlatform=false`; WAV arrays are empty, vibration-wave indices are
  not registered, and post-vibration output does not fire.
- Forcing the gate true creates `IsHD=true`/audio-source records but disables
  the working PC native vibration path and still produces no HD output.
- Gate experimentation is rejected for runtime use.

Native controller result:

- Without DSX/Steam Input, RE4R sees
  `via.hid.VendorNativeDualSenseDevice`.
- Native PC effects include shots, reloads, player damage, knife impacts, and
  low-HP heartbeat.
- With DSX running, native haptics and stable LED behavior are not preserved.

Adaptive-trigger transport result:

- Existing DSX weapon/event mappings are sufficient; no new gameplay hook is
  required merely to select trigger profiles.
- Read-only hooks on `PlayerManager.setAdaptiveFeedBack` and both
  `setAdaptiveTriggerFeedback` overloads captured no normal weapon calls.
- `PlayerManager` was not available through `sdk.get_managed_singleton`, and a
  passive `PlayerManager.onUpdate` capture hook remained idle.
- Direct `share.hid.Device.setAdaptiveTriggerFeedback` crashed the game.
- Therefore PlayerManager and direct managed Device trigger calls are rejected
  as native output transports. The confirmed replacement is the external,
  trigger-only duaLib transport: `dualib_trigger_ipc.lua` reuses the existing
  mappings, writes a command file, and a delayed watcher opens duaLib only
  after `CampaignManager.onStartInGame`. Native weapon-trigger effects coexist
  with Capcom haptics, the custom native lightbar, and controller-speaker
  audio. Direct HID remains a future comparison path, not the active backend.

### Capcom Event Mapper

Status:

- Implemented as an experimental diagnostic panel and JSON exporter.
- Knife IDs `1118898055` and `1124327350` repeated across knife captures.
- Shot ID `2115789788` repeated, but many other IDs vary by action/weapon.
- Parry, HP, movement, and joint-contact IDs overlap with background activity.

Decision:

- Keep the mapper for research.
- Prefer existing confirmed gameplay hooks for stable runtime features.
- Do not replace the working knife/parry/HP detectors solely with mapper IDs.
