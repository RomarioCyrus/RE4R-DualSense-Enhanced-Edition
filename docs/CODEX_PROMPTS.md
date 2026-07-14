# CODEX_PROMPTS.md — Ready-To-Use Prompts

## Initial Context Prompt (use at start of every session)

```
Read AGENTS.md, MEMORY.md, BUGS.md, TASKS_FOR_CODEX.md, and docs/game_events.md.

Then inspect the Lua source files in src/, especially:
- events_led.lua
- hp_led.lua
- feedback_writer.lua

Do not edit yet. Confirm you understand the current architecture and active bugs.
```

---

## Start Separate duaLib / Direct HID Branch

```
Read docs/DUALIB_HID_BRANCH.md first, then read:
- docs/AGENTS.md
- docs/MEMORY.md
- docs/TASKS_FOR_CODEX.md
- docs/RE9_DUALSENSE_RESEARCH.md
- speaker/ExperimentalDualsenseHidBridge/README.md

Task: create an isolated experimental branch/prototype for native DualSense
adaptive triggers in RE4R without DualSenseEnhancedFeedback.

Confirmed baseline:
- USB DualSense/Edge
- Steam Input disabled
- DSX closed
- Capcom native haptics must remain active
- custom native lightbar must remain active
- existing DSX weapon/event mappings already provide trigger intent

First compare duaLib and direct HID as transports. Do not modify the stable
runtime yet. The first MVP is one weak L2 effect plus immediate reset, tested
outside RE4R and then during native RE4R haptics.

Do not use share.hid.Device.setAdaptiveTriggerFeedback; it caused a confirmed
game crash. Do not continue the PlayerManager L2 probe.

Success requires the trigger effect, Capcom native haptics, and the custom
native lightbar to coexist without flicker, suppression, or controller-mode
changes.
```

---

## Tune Native Gyro-To-Mouse

```
Read docs/DUALIB_HID_BRANCH.md first, then read:
- docs/AGENTS.md
- docs/MEMORY.md
- docs/TASKS_FOR_CODEX.md
- docs/RE9_DUALSENSE_RESEARCH.md
- speaker/DualSenseEnhancedTransport/README.md

Task: tune or debug the confirmed native gyro-to-mouse path for RE4R without
Steam Input or DualSenseEnhancedFeedback.

Confirmed baseline:
- USB DualSense/Edge; Steam Input disabled; DSX closed.
- Delayed duaLib weapon triggers, native haptics, custom native lightbar, and
  controller-speaker audio already coexist in gameplay.
- Native gyro-to-mouse is opt-in, hardware-confirmed, and launched by the same
  delayed duaLib watcher. Do not replace the trigger-only transport or add a
  second HID output owner.
- The current mapping is X pitch and inverted-Z yaw. Right-stick camera input
  suppresses gyro to avoid jitter from mixed input sources.

Important distinction:
- `scePadSetMotionSensorState(handle, true)` only enables IMU values returned
  by `scePadReadState`; it does not move the RE4R camera or inject mouse input.

Use the `Native Gyro` UI and `DualSenseEnhanced/native_gyro.json` for normal tuning:
enable state, yaw/pitch sensitivity, deadzone, L2 aim threshold, and
calibration time. For diagnostics, use `--gyro-log` in the shared watcher and
check `trigger_watcher.log`.

Do not use RE4R's `share.hid.Device.setAdaptiveTriggerFeedback` and do not
resume the PlayerManager probe; both paths are closed.
```

---

## Historical: Stale HP LED After Returning To Main Menu

This prompt is retained for history. The bug is resolved; do not run this task unless a regression is reproduced.

```
Read AGENTS.md and BUGS.md (Bug #1).

Task: fix the stale HP LED when returning from gameplay to main menu.

Constraints:
- Do not rewrite or remove confirmed working hooks (grab, parry, damage, onStartInGame).
- Preserve flush() definition order — it must be defined before poll_game_state().
- Do not reintroduce post-load HP/ammo delay unless explicitly requested.
- Prefer adding a stronger gameplay check over a full rewrite.

Steps:
1. Inspect events_led.lua → poll_game_state().
2. Explain why in_gameplay may stay true after returning to menu.
3. Propose the smallest fix.
4. Apply the fix.
5. Update CHANGELOG.md.
6. If a new hook or method is found, update docs/game_events.md.
```

---

## Investigate Return-To-Menu Hook

```
Read docs/game_events.md (Needs Investigation section).

Task: find a reliable RE4R hook or state that fires when returning to main menu/title.

Steps:
1. List all chainsaw.CampaignManager methods visible via Object Explorer.
2. Try chainsaw.TitleManager, chainsaw.GameFlowManager if they exist.
3. Check CampaignManager instance fields for state/phase enum.
4. If a working method is found: add a hook in events_led.lua and document in docs/game_events.md.
5. Update MEMORY.md confirmed hooks list.
```

---

## Historical: Add Save/Load Settings

This prompt is retained for history. Settings persistence is already implemented in `settings.lua`.

```
Read TASKS_FOR_CODEX.md (Task 5).

Task: add persistent settings save/load.

Requirements:
- Save to reframework/data/DualSenseEnhanced_settings.json.
- Load on startup in DualSenseEnhanced.lua.
- Settings to save: all colour tables, threshold values, mode toggles (ammo mode, threshold mode, menu_enabled).
- Do not break existing behaviour if file is missing (use defaults).
- Do not affect LED logic — settings layer only.

After implementing:
- Update CHANGELOG.md.
```
