-- Opt-in IPC bridge for the isolated duaLib trigger transport.
-- It never calls native trigger APIs inside RE4R.

local io = io
local math = math
local os = os
local pcall = pcall
local tostring = tostring

-- Generation guard: incremented on every Reset Scripts so stale callbacks
-- from prior loads immediately no-op instead of writing trigger_command.json
-- in parallel with the new generation and producing stuck L2/R2 resistance.
_G.DuaLibTriggerIpcGeneration = (_G.DuaLibTriggerIpcGeneration or 0) + 1
local _generation = _G.DuaLibTriggerIpcGeneration
local function is_current() return _G.DuaLibTriggerIpcGeneration == _generation end

_G.DuaLibTriggerIpc = _G.DuaLibTriggerIpc or {}
local IPC = _G.DuaLibTriggerIpc

IPC.enabled = IPC.enabled == true
IPC.indicators_enabled = IPC.indicators_enabled == true
-- Opt-in: lets the external duaLib watcher own the lightbar HID write via
-- scePadSetLightBar instead of native_feedback.lua's share.hid.Device hook
-- enforcement trick. native_feedback.lua checks this flag and stops writing
-- so only one process ever owns the lightbar report.
IPC.lightbar_enabled = IPC.lightbar_enabled == true
-- Opt-in: lets the watcher drive the Mic LED via scePadSetMicLight, mirroring
-- mic_led.lua's feedback-payload path for native mode.
IPC.mic_enabled = IPC.mic_enabled == true
-- Experimental footstep-haptics support (docs/HAPTICS_FOOTSTEPS_TASK.md).
-- Forces the watcher to hold scePadSetVibrationMode's audio-haptics mode
-- instead of compatible rumble, which is required for the channels-3/4
-- actuator path to be audible at all. Stage 1's go/no-go test (2026-07-07)
-- confirmed this coexists with Capcom's native haptics, lightbar, adaptive
-- triggers, Mic LED, gyro, and controller-speaker audio. Single source of
-- truth for two independent subsystems: this module's haptics_mode_for()
-- (below) AND audio_feedback.lua's AUDIO.play_footstep_haptic() both read
-- this same field, so the controller's vibration mode and the
-- haptic-event stream can never drift out of sync. Persisted via
-- settings.lua; toggled from the debug-only UI section in
-- DualSenseEnhanced.lua's draw_debug() (never shown when RELEASE_BUILD is
-- true, so it cannot leak into the packaged v1.0 UI regardless of the
-- show_debug_tools state). Not a shipped feature; excluded from release
-- v1.0.
IPC.haptics_mode_enabled = IPC.haptics_mode_enabled == true
IPC.command_file = "trigger_command.json"
-- The audio bridge removes this marker at process start.  We create it only
-- after CampaignManager.onStartInGame has made gameplay live, so a watcher
-- never opens the controller while RE4R is still loading a save.
IPC.ready_file = "DualSenseEnhanced/trigger_transport.ready"
IPC.ready = true -- force the initial set_ready(false) write below
-- The watcher accepts only increasing sequences.  Seed a new RE4R process
-- above any command emitted by an earlier session while preserving a live
-- reload's existing in-memory sequence.
IPC.sequence = IPC.sequence or (os.time() * 1000)
IPC.last_signature = IPC.last_signature or nil
IPC.last_status = IPC.last_status or "disabled"
IPC.last_error = IPC.last_error or "none"
IPC.write_count = IPC.write_count or 0

local function clamp(value, low, high)
    value = tonumber(value) or low
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

local function off()
    return { mode = "off" }
end

local function set_ready(ready)
    ready = ready == true
    if IPC.ready == ready then return end

    local file = io.open(IPC.ready_file, "wb")
    if not file then
        IPC.last_error = "Cannot write " .. IPC.ready_file
        return
    end
    file:write(ready and "ready\n" or "waiting\n")
    file:close()
    IPC.ready = ready
end

-- Clear the ready marker left by any previous session/generation.
set_ready(false)
-- Unconditionally push an all-off trigger command so any stuck L2/R2
-- resistance from a prior generation is cleared immediately on script load,
-- regardless of last_signature dedupe (force=true bypasses it).
do
    local file = io.open(IPC.command_file, "wb")
    if file then
        local seq = IPC.sequence + 1
        IPC.sequence = seq
        file:write(string.format(
            '{"sequence":%d,"l2":{"mode":"off","position":0,"strength":0,"endPosition":0,"endStrength":0,"frequency":0},"r2":{"mode":"off","position":0,"strength":0,"endPosition":0,"endStrength":0,"frequency":0},"indicators":{"mask":0},"led":null,"mic":null,"haptics":null}',
            seq))
        file:close()
        IPC.last_signature = nil
    end
end

local function from_instruction(inst)
    local p = inst and inst.parameters or nil
    if not p or inst.type ~= 1 then return nil, nil end

    local side = tonumber(p[2]) == 1 and "l2"
        or tonumber(p[2]) == 2 and "r2" or nil
    if not side then return nil, nil end

    local mode = tonumber(p[3]) or 0
    if mode == 0 then return side, off() end
    if mode == 13 then
        return side, {
            mode = "feedback",
            position = clamp(p[4], 0, 9),
            strength = clamp(p[5], 0, 8),
        }
    end
    if mode == 2 or mode == 3 then
        -- DSX "bow" mode has no identical duaLib counterpart; use its weapon
        -- range and resistance values as the closest stable hardware effect.
        -- DSX accepts 0..9; duaLib weapon mode requires start 2..7 and end
        -- strictly above start, capped at 8.
        local start_pos = clamp(p[4], 2, 7)
        return side, {
            mode = "weapon",
            position = start_pos,
            endPosition = clamp(p[5], start_pos + 1, 8),
            strength = clamp(p[6], 0, 8),
        }
    end
    if mode == 8 then
        return side, {
            mode = "vibration",
            position = 0,
            strength = clamp((tonumber(p[4]) or 0) * 8 / 20, 0, 8),
            frequency = 10,
        }
    end

    return side, off()
end

local function effects_for(info, mapping)
    local l2, r2 = off(), off()
    local instructions = mapping and mapping.instructions or nil
    if type(instructions) ~= "table" then return l2, r2 end

    for _, inst in ipairs(instructions) do
        local side, effect = from_instruction(inst)
        if side == "l2" then l2 = effect end
        if side == "r2" then r2 = effect end
    end

    -- Keep the existing empty-magazine intent in the native transport.
    if info and tonumber(info.ammo) == 0 and tonumber(info.ammoMax) > 0 then
        r2 = { mode = "feedback", position = 0, strength = 8 }
    end

    local TI = _G.TriggerIntensity
    if TI then
        local class = TI.class_for_info(info)
        l2 = TI.scale_effect(l2, class)
        r2 = TI.scale_effect(r2, class)
    end
    return l2, r2
end

-- Mirrors ammo_led.lua's default "warning" mode: silent until ammo drops to
-- AMMO.warn_threshold (5), then shows the loaded count, with the first LED
-- blinking on the last bullet. Kept independent of ammo_led.lua's own blink
-- timer since the duaLib watcher reads file state on its own poll cycle.
local INDICATOR_BLINK_FRAMES = 20
local indicator_blink_tick = 0
local indicator_blink_on = false

local function indicator_mask_for(info)
    if not IPC.indicators_enabled or type(info) ~= "table" then return 0 end
    if info.melee == true then return 0 end

    local ammo = tonumber(info.ammo) or 0
    local ammo_max = tonumber(info.ammoMax) or 0
    if ammo <= 0 or ammo_max <= 0 then return 0 end

    local AMMO = _G.AmmoLed
    local threshold = (AMMO and AMMO.warn_threshold) or 5
    if ammo > threshold then return 0 end

    indicator_blink_tick = indicator_blink_tick + 1
    if indicator_blink_tick >= INDICATOR_BLINK_FRAMES then
        indicator_blink_tick = 0
        indicator_blink_on = not indicator_blink_on
    end

    local lit = clamp(math.min(ammo, 5), 0, 5)
    if ammo == 1 and not indicator_blink_on then lit = 0 end
    return (2 ^ lit) - 1
end

local function encode(effect)
    return string.format(
        '{"mode":"%s","position":%d,"strength":%d,"endPosition":%d,"endStrength":%d,"frequency":%d}',
        effect.mode,
        effect.position or 0,
        effect.strength or 0,
        effect.endPosition or 0,
        effect.endStrength or 0,
        effect.frequency or 0
    )
end

-- mic_led.lua's On/Pulse/Off (0/1/2) to dualsenseData::MuteLight's
-- Off/On/Breathing (0/1/2) used by scePadSetMicLight.
local MIC_MODE_TO_DUALIB = { [0] = 1, [1] = 2, [2] = 0 }

-- Low-HP heartbeat sync: reads the exact same per-frame feedback get_active_led()
-- snapshot the lightbar itself uses (both native_feedback.lua's lightbar
-- tick and this IPC tick run as UpdateBehavior callbacks fed by
-- feedback_writer.lua's single tick_led_sources() per frame), so the Mic LED's
-- on/off phase always lands on the identical frame as the lightbar's
-- colored/black-rest phase -- no separate timer to drift out of sync.
-- Returns a duaLib-space mode (0=Off,1=On) directly, or nil if the
-- low-HP heartbeat isn't the active LED source.
local function hp_danger_mic_mode()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK or not FEEDBACK.get_active_led then return nil end
    local _, _, _, led_name = FEEDBACK.get_active_led()
    if led_name ~= "hp_danger" then return nil end
    -- hp_led.lua's danger pulse never hits literal black (continuous
    -- brightness oscillation), so read its own phase flag directly instead
    -- of inspecting r/g/b magnitude.
    local HP = _G.HPLed
    if not HP then return nil end
    return HP.danger_pulse_on and 1 or 0
end

local function mic_mode_for()
    if not IPC.mic_enabled then return nil end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK or FEEDBACK.output_mode ~= "native" then return nil end
    local MIC = _G.DualSenseEnhancedMicLED
    local ammo_mode = MIC and MIC.last_mode_raw
    if ammo_mode == nil then return nil end

    -- Ammo-empty/reload feedback keeps priority over the low-HP sync,
    -- mirroring the lightbar's own priority table (ammo_empty=20 outranks
    -- hp_danger=1). Only let the heartbeat claim the Mic LED while ammo
    -- isn't otherwise using it (raw mode Off).
    if ammo_mode == 2 then
        local hp_mode = hp_danger_mic_mode()
        if hp_mode ~= nil then return hp_mode end
        return MIC_MODE_TO_DUALIB[ammo_mode]
    end

    -- Empty-mag pulse: drive On/Off manually in lockstep with the
    -- lightbar's own per-frame pulse phase instead of duaLib's
    -- firmware-driven Breathing mode, which animates on its own timing and
    -- would drift out of sync. mic_led.lua's other use of Pulse (the
    -- short reload-finish blip) has no lightbar to sync to and keeps the
    -- normal Breathing mapping.
    if ammo_mode == 1 then
        local AMMO = _G.AmmoLed
        if AMMO and AMMO.empty_pulse_active then
            return AMMO.empty_pulse_on and 1 or 0
        end
    end

    return MIC_MODE_TO_DUALIB[ammo_mode]
end

local function encode_mic(mode)
    if mode == nil then return "null" end
    return string.format('{"mode":%d}', mode)
end

-- Mirrors the hp_danger black-rest substitution in native_feedback.lua: the
-- watcher process should show the same visible orange rest phase, since it
-- is now the only writer driving the lightbar in native mode.
local function led_for_lightbar()
    if not IPC.lightbar_enabled then return nil end
    local NATIVE = _G.NativeDualSenseFeedback
    local EVENTS = _G.EventsLed
    if (NATIVE and (NATIVE.loading_blackout or NATIVE.death_blackout))
        or (EVENTS and EVENTS.player_dead) then
        return {0, 0, 0}
    end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK or FEEDBACK.output_mode ~= "native" or not FEEDBACK.get_active_led then
        return nil
    end

    local r, g, b, led_name = FEEDBACK.get_active_led()
    if r == nil then return nil end
    if led_name == "hp_danger" and r == 0 and g == 0 and b == 0 then
        r, g, b = 255, 70, 0
    end
    return {
        clamp(r, 0, 255),
        clamp(g, 0, 255),
        clamp(b, 0, 255),
    }
end

local function encode_led(led)
    if not led then return "null" end
    return string.format('{"r":%d,"g":%d,"b":%d}', led[1], led[2], led[3])
end

-- See IPC.haptics_mode_enabled above. Mode 1 = audio-haptics (required for
-- the channels-3/4 actuator path); returning nil omits the field entirely,
-- which the transport treats as "restore compatible rumble."
local function haptics_mode_for()
    if IPC.haptics_mode_enabled then return 1 end
    return nil
end

local function encode_haptics(mode)
    if mode == nil then return "null" end
    return string.format('{"mode":%d}', mode)
end

local function emit(l2, r2, indicators, led, mic, haptics, force)
    indicators = clamp(indicators or 0, 0, 31)
    local text = encode(l2) .. "/" .. encode(r2) .. "/" .. tostring(indicators)
        .. "/" .. encode_led(led) .. "/" .. encode_mic(mic) .. "/" .. encode_haptics(haptics)
    if not force and text == IPC.last_signature then return true end

    IPC.sequence = IPC.sequence + 1
    local payload = string.format(
        '{"sequence":%d,"l2":%s,"r2":%s,"indicators":{"mask":%d},"led":%s,"mic":%s,"haptics":%s}',
        IPC.sequence, encode(l2), encode(r2), indicators, encode_led(led), encode_mic(mic), encode_haptics(haptics)
    )
    local file, err = io.open(IPC.command_file, "wb")
    if not file then
        IPC.last_error = "Cannot write " .. IPC.command_file .. ": " .. tostring(err)
        IPC.last_status = "write failed"
        return false
    end

    local ok, write_err = pcall(function()
        file:write(payload)
        file:close()
    end)
    if not ok then
        IPC.last_error = tostring(write_err)
        IPC.last_status = "write failed"
        return false
    end

    IPC.last_signature = text
    IPC.write_count = IPC.write_count + 1
    IPC.last_error = "none"
    IPC.last_status = "sequence " .. tostring(IPC.sequence)
    return true
end

function IPC.reset(reason)
    -- Reset must always bypass last_signature dedupe so a stuck trigger is
    -- cleared even when the last written state happened to be all-off.
    -- haptics is forced nil (not haptics_mode_for()) so a reset always
    -- restores compatible rumble regardless of the Stage 1 test flag.
    IPC.last_signature = nil
    local ok = emit(off(), off(), 0, nil, nil, nil, true)
    IPC.last_status = ok and ("reset: " .. tostring(reason or "manual"))
        or IPC.last_status
    return ok
end

function IPC.tick()
    -- Stale callback from a prior Reset Scripts: do nothing so this generation
    -- cannot write trigger_command.json in parallel with the current one.
    if not is_current() then return end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    local EVENTS = _G.EventsLed
    local NATIVE = _G.NativeDualSenseFeedback
    local blackout = (NATIVE and (NATIVE.loading_blackout or NATIVE.death_blackout))
        or (EVENTS and EVENTS.player_dead)
    -- Trigger intensity presets (Off/Native Only/etc.) must never stop this
    -- watcher: native gyro-to-mouse rides the same shared duaLib transport
    -- and ready marker. Off/Native Only zero the effect strength instead
    -- (see TI.scale_effect), so resistance disappears without killing gyro.
    local gameplay_ready = EVENTS and EVENTS.in_game == true and not EVENTS.player_dead
    if IPC.enabled and FEEDBACK and FEEDBACK.output_mode == "native" and blackout then
        set_ready(true)
        emit(off(), off(), 0, led_for_lightbar(), nil, haptics_mode_for(), false)
        return
    end
    if not IPC.enabled or not FEEDBACK or FEEDBACK.output_mode ~= "native" or not gameplay_ready then
        set_ready(false)
        if IPC.last_signature ~= nil then IPC.reset("disabled or non-native") end
        return
    end

    set_ready(true)

    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or nil
    if FEEDBACK.reload_mapping and (not FEEDBACK.mapping or not next(FEEDBACK.mapping)) then
        pcall(FEEDBACK.reload_mapping)
    end
    local mapping = FEEDBACK.find_mapping_for_info and FEEDBACK.find_mapping_for_info(info) or nil
    local l2, r2 = effects_for(info, mapping)
    emit(l2, r2, indicator_mask_for(info), led_for_lightbar(), mic_mode_for(), haptics_mode_for(), false)
end

re.on_application_entry("UpdateBehavior", IPC.tick)
