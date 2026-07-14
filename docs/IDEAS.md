# IDEAS.md — Future Ideas

## Completed: разные звуки лечения для разных предметов (2026-07-13)

Идея реализована и больше не является будущей задачей. Подтверждённый hook
`chainsaw.CsInventoryController.applyUseResult` передаёт точный Item ID в
`audio_feedback.lua`. Отдельные speaker/haptic stems используются для трав,
First Aid Spray, трёх видов яиц, трёх видов рыбы, Viper и Rhinoceros Beetle.

Текущая таблица маршрутизации и важные детали Item ID находятся в
`docs/TASK_HEAL_ITEM_HOOK.md` и `docs/game_events.md`. Дальнейшая замена или
перетюнинг WAV — это audio tuning, а не незавершённая runtime-функция.

## Knife surface: материальный выбор WAV через состояние игрока (2026-07-07)

Удары ножом по поверхностям идут через одно Wwise-событие `1953686865`
(`ch_wp_knife_cm.bnk`) для всех материалов — switch-выбор WEM происходит внутри
Wwise и в хук `postRequestInfo` не попадает. Сейчас водная группа WEM
(248642604/522632479/551564106/768805111) исключена из пула `knife_surface`,
чтобы на дереве/камне не играл всплеск; на воде играет «сухой» вариант.

Идея: определять воду косвенно — читать у персонажа состояние wading/in-water
(поискать поле в character controller / environment context RE Engine) и при
нём переключать пул на водную группу WAV. Требует исследования доступных
полей; низкий приоритет.

## Gyro: IsAiming gate вместо L2 threshold (2026-07-05, реализовано и откачено)

**Проблема:** `--gyro-aim-threshold 32` иногда активирует гиро от адаптивного триггера без нажатия L2.

**Реализованный подход (откачен — поведение не понравилось):**

`wwise_audio_router.lua` — в `emit_mapped()` после успешного emit:
```lua
local ev = tostring(effective_event or "")
if ev:find("aim_in", 1, true) then
    _G.NativeGyroAimingAt = now  -- os.clock()
elseif ev:find("aim_out", 1, true) then
    _G.NativeGyroAimingAt = nil
end
```

`native_gyro.lua` — `read_is_aiming()` читает глобал, таймаут 3s на случай missed aim_out:
```lua
local function read_is_aiming()
    local t = _G.NativeGyroAimingAt
    if not t then return false end
    return (os.clock() - t) < 3.0
end
```

Gate file `gyro_aim_gate.txt` ("1"/"0") пишется per-frame из `re.on_application_entry("UpdateBehavior", ...)`.
C# `GyroMouseMapper` читает gate file вместо `sample.L2 >= _aimThreshold` когда передан `--gyro-aim-gate-file`.

**Что не понравилось:** поведение strange — вероятно задержка из-за Wwise event latency или таймаут создаёт артефакты.

**Альтернативы для будущего:**
- Попробовать `chainsaw.PlayerBaseContext.get_IsAiming()` напрямую через REFramework (предыдущая попытка не удалась — декларированный тип `CharacterContext` не имеет метода, runtime dispatch не сработал)
- Снизить `aim_threshold` до 5-10 вместо 32 — если проблема от адаптивного триггера, меньший порог может не помочь
- Читать L2 из игрового `InputController` (не из HID), который знает о нажатии кнопки независимо от сопротивления

## DSX Controller Speaker

**Concept:**
Play extracted RE4R sound files through DualSense speaker via DSX when specific events occur.
Not real-time audio routing — pre-extracted files triggered by Lua events.

**Current state:**
- The loaded `src/reframework/autorun/DualSenseEnhanced/audio_feedback.lua` writes JSON
  events to the confirmed C# NAudio/WASAPI bridge.
- Physical controller-speaker output is confirmed for manual test, healing,
  parry, item pickup, fatal kick, knife hit, and selected weapon reload events.
- Runtime device selection, volume control, random numbered variants, and
  immediate-repeat avoidance are implemented.
- The PowerShell `System.Media.SoundPlayer` prototype is obsolete and must not
  be restored.

**Sound candidates:**
- First aid spray use
- Herb use
- Reload complete
- Weapon switch
- Item pickup
- Inventory confirm/cancel
- Typewriter save
- Merchant interaction
- Low HP warning

**Flow:**
1. Extract WEM file from RE4R via REtool.
2. Convert WEM → OGG/WAV via ww2ogg.
3. Add a named event to `SoundMap.cs`.
4. Detect the event in Lua through an existing confirmed hook/state, or through
   a confirmed Wwise event ID from `soundlib.SoundManager.postRequestInfo`.
5. Emit it through `audio_events.json`.
6. Optionally drive haptics from the same audio.

**Status:** Integrated and physically confirmed. Direct DSX UDP audio remains
unavailable and unnecessary.

---

## Audio-To-Haptics

**Concept:** use audio to drive the DualSense actuators.

**Research result:**

- A standalone 4-channel WASAPI probe can map stereo audio to left/right
  DualSense actuators with Raw, Natural, PS5-like, and Impact DSP presets.
- In native RE4R mode, Capcom's vibration mode prevents reliable playback from
  the same actuator audio channels. One-shot and short-burst HID selection did
  not solve coexistence.
- DSX can keep audio-haptics working, but conflicts with games' native
  DualSense LED/triggers/haptics.

**Decision:**

- Keep the current event-based extracted-WAV speaker implementation.
- Defer live game-mix/SFX-bus routing. RE4R does not expose a separate PC SFX
  device, native Wwise interception remains high risk, and spatial pipelines
  such as Dolby Atmos make post-mix channel extraction less attractive.
- Use confirmed Wwise event IDs only as event triggers for extracted WAVs; this
  is separate from live Wwise bus capture.
- Preserve `DualSenseHapticsProbe` as an experimental research tool only.

---

## Weapon Effects

- Shotgun: brief white flash on fire.
- Sniper: dim/blue tint while scoped.
- Empty mag warning: amber blink (implemented).
- Reload: brief flash on reload complete.
- Weapon-specific trigger profiles: done via `weapon_trigger_profiles.lua`.

---

## DualSense Mic LED — Implemented

**Concept:** use the DualSense microphone LED as an additional small status/effect channel.

Potential DSX API:
```csharp
// Three modes: ON, PULSE, or OFF
// Needs 1 Param (MicLEDMode: Enum)
Packet packet = new Packet();
int controllerIndex = 0;

packet = AddMicLEDToPacket(packet, controllerIndex, MicLEDMode.Pulse);

SendDataToDSX(packet);
GetDataFromDSX();
```

Implemented:
- Empty ammo: Mic LED pulses while the current weapon is empty.
- Reload finish: short Mic LED pulse, then `Off` if the weapon is no longer empty.

  Confirmed DSX payload details:
  - Instruction `type=5`, parameters `{controllerIndex, mode}`.
  - Enum: `On=0`, `Pulse=1`, `Off=2`.
  
  Implementation:
  - `mic_led.lua` sets Mic LED state on `DualSenseEnhancedFeedback`.
  - `feedback_writer.lua` writes Mic LED state into the same `payload.json` as triggers, lightbar, and player indicator.
  - No external bridge or startup task is required.

Deferred:
- Low HP heartbeat Mic LED pulse remains optional future work.

---

## Boss / Enemy Proximity Effects

- Chainsaw enemy nearby: orange warning pulse.
- Regenerador: slow red pulse matching breathing.
- Garrador: silence effect (LED off or near-off) when crouching nearby.
- Boss encounter: distinct colour scheme while boss HP is non-zero.

---

## Settings Persistence

Implemented through `settings.lua`. Colours, thresholds, modes, durations, event/audio toggles, and related UI settings persist under the REFramework data directory.

---

## Port To Other RE Engine Games

- RE2R: different namespace (`app.*`), different weapon IDs and HP paths. Needs new `weapon_equip_core`.
- RE3R: similar to RE2R.
- RE Village: `app.*` namespace, needs investigation.
- RE9/Requiem: already has native DualSense support — only triggers mod needed (done separately).

Author (lunati) is working on a universal RE Engine version. May obsolete individual ports.

## Cutscene, Pause, And Loading Suppression

This was removed from the active RE4R mod runtime on 2026-07-01. The previous
manual `Force cutscene gate` UI, `EventsLed.set_cutscene`, `cutscene_active`
gating, and Movie/Timeline diagnostic enumeration were intentionally deleted so
the stable gameplay/death/Continue recovery path stays simpler.

Keep this as a future idea only. Reopen it only if there is a reliable,
independently verified state signal for player control, pause, cutscene, or
loading. Previously tested Movie/Timeline hooks were too noisy and could break
normal HP/ammo gating.

## Native Adaptive Triggers And Gyro Without DSX

**Current state:** native adaptive triggers are confirmed through the delayed
duaLib transport while preserving RE4R haptics, custom native lightbar, and
controller-speaker audio. L2-aim native gyro-to-mouse is also confirmed as an
opt-in input feature through the same delayed watcher.

**Separate-branch references:**

- [WujekFoliarz/duaLib](https://github.com/WujekFoliarz/duaLib)
- [MasonLeeBack/libscepad_windows_sdk](https://github.com/MasonLeeBack/libscepad_windows_sdk)
- [WujekFoliarz/Dying-Light-1-DUALSENSE-MOD](https://github.com/WujekFoliarz/Dying-Light-1-DUALSENSE-MOD)

**Constraints:**

- Reuse existing DSX weapon/event mappings; replace only the output transport.
- Avoid a second blind full-report writer. Prefer one owner or merged state.
- Keep gyro-to-mouse enabled only while L2 aiming, with user-configurable yaw
  and pitch sensitivity, deadzone, aim threshold, and startup calibration.
- `scePadSetMotionSensorState` enables IMU data only; it does not produce mouse
  movement. The confirmed mapper injects mouse deltas, so RE4R may switch
  visible prompts to keyboard/mouse.
- Keep gyro input attached to the one confirmed delayed watcher and separate
  from trigger-only output-field suppression. Do not add a second HID owner.

See `DUALIB_HID_BRANCH.md` for the branch handoff and test order.

## Audio System Roadmap

### Speaker Events

High Priority

- Heal spray
- Herb use
- Parry
- Finisher
- Radio calls

Medium Priority

- Validate remaining weapon reload profiles
- Weapon switch

Low Priority

- Item pickup
- Menu sounds

Avoid

- Every gunshot
- Every inventory action

Current research:

- maintained weapon profiles: `docs/weapon_audio_catalog/`;
- `surface_*` casing/shell impacts are strong future speaker candidates;
- fatal kick now uses three clean layered composites without the unwanted
  environmental long layer.

## Heartbeat System

Possible Hook:
- chainsaw.Ch6CommonBodyUpdater.on_low_hp_heartbeat

Ideas:
- Speaker heartbeat
- Haptics heartbeat
- Red LED pulse
- Brightness synchronized with heartbeat
