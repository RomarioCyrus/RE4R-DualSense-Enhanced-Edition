local io = io
local os = os
local load = load
local pairs = pairs
local tostring = tostring
local type = type
local string = string

local SETTINGS = {}
SETTINGS.path = "RE4R_DualSense_settings.lua"
SETTINGS.last_status = "not loaded"

-- Debounced autosave: any UI change marks state dirty; a periodic check
-- (not a per-change file write) saves only if the serialized snapshot
-- actually differs from what's on disk. This avoids hammering the file
-- system while a slider is being dragged and avoids persisting identical
-- no-op writes every tick. Manual Save/Load/Reset buttons stay as the
-- explicit profile snapshot/restore mechanism; autosave is additive.
SETTINGS.autosave_enabled = true
SETTINGS.autosave_interval_frames = 90 -- ~1.5s at 60fps
SETTINGS.autosave_status = "idle"
local autosave_frame_counter = 0
local last_saved_signature = nil

local function copy_rgb(src)
    if type(src) ~= "table" then return {0, 0, 0} end
    return {src[1] or 0, src[2] or 0, src[3] or 0}
end

local function apply_rgb(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    dst[1] = src[1] or dst[1]
    dst[2] = src[2] or dst[2]
    dst[3] = src[3] or dst[3]
end

local function bool(v, fallback)
    if type(v) == "boolean" then return v end
    return fallback
end

local function num(v, fallback)
    v = tonumber(v)
    if v == nil then return fallback end
    return v
end

local function serialize_value(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "number" then return tostring(v) end
    if t == "boolean" then return v and "true" or "false" end
    if t == "string" then
        return string.format("%q", v)
    end
    if t == "table" then
        local next_indent = indent .. "    "
        local parts = {"{\n"}
        for k, val in pairs(v) do
            local key
            if type(k) == "number" then
                key = "[" .. tostring(k) .. "]"
            else
                key = "[" .. string.format("%q", tostring(k)) .. "]"
            end
            parts[#parts + 1] = next_indent .. key .. " = " .. serialize_value(val, next_indent) .. ",\n"
        end
        parts[#parts + 1] = indent .. "}"
        return table.concat(parts)
    end
    return "nil"
end

local function snapshot()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    local HP = _G.HPLed
    local AMMO = _G.AmmoLed
    local EVENTS = _G.EventsLed
    local AUDIO = _G.DualSenseEnhancedAudio
    local RADIO = _G.DualSenseEnhancedRadio
    local MIC = _G.DualSenseEnhancedMicLED
    local IPC = _G.DuaLibTriggerIpc
    local GYRO = _G.NativeGyro
    local TI = _G.TriggerIntensity
    local UI = _G.DualSenseEnhancedUI

    return {
        version = 1,
        ui = UI and {
            global_preset = UI.global_preset,
            lightbar_mode = UI.lightbar_mode,
            show_debug_tools = UI.show_debug_tools,
        } or nil,
        feedback = FEEDBACK and {
            hp_resume_fade_duration = FEEDBACK.hp_resume_fade_duration,
            output_mode = FEEDBACK.output_mode,
            lightbar_brightness = FEEDBACK.lightbar_brightness,
        } or nil,
        dualib = IPC and {
            trigger_ipc_enabled = IPC.enabled,
            indicators_enabled = IPC.indicators_enabled,
            lightbar_enabled = IPC.lightbar_enabled,
            mic_enabled = IPC.mic_enabled,
            haptics_mode_enabled = IPC.haptics_mode_enabled,
        } or nil,
        trigger_intensity = TI and {
            preset = TI.preset,
            global_intensity = TI.global_intensity,
            class_intensity = {
                pistol = TI.class_intensity.pistol,
                shotgun = TI.class_intensity.shotgun,
                rifle = TI.class_intensity.rifle,
                automatic = TI.class_intensity.automatic,
                magnum = TI.class_intensity.magnum,
            },
        } or nil,
        gyro = GYRO and {
            enabled = GYRO.enabled,
            preset = GYRO.preset,
            yaw_sensitivity = GYRO.yaw_sensitivity,
            pitch_sensitivity = GYRO.pitch_sensitivity,
            deadzone = GYRO.deadzone,
            aim_threshold = GYRO.aim_threshold,
            calibration_ms = GYRO.calibration_ms,
            invert_pitch = GYRO.invert_pitch,
            activation_mode = GYRO.activation_mode,
        } or nil,
        mic = MIC and {
            enabled = MIC.enabled,
            controller_index = MIC.controller_index,
            port = MIC.port,
        } or nil,
        hp = HP and {
            enabled = HP.enabled,
            healthy_threshold = HP.healthy_threshold,
            caution_threshold = HP.caution_threshold,
            danger_threshold = HP.danger_threshold,
            dim_threshold = HP.dim_threshold,
            heal_duration = HP.heal_duration,
            danger_blink_rate = HP.danger_blink_rate,
            color_healthy = copy_rgb(HP.color_healthy),
            color_caution_hi = copy_rgb(HP.color_caution_hi),
            color_caution_lo = copy_rgb(HP.color_caution_lo),
            color_danger_lo = copy_rgb(HP.color_danger_lo),
            color_heal = copy_rgb(HP.color_heal),
        } or nil,
        ammo = AMMO and {
            enabled = AMMO.enabled,
            mode = AMMO.mode,
            warn_threshold = AMMO.warn_threshold,
            ammo_blink_rate = AMMO.ammo_blink_rate,
            reload_count_hold = AMMO.reload_count_hold,
            reload_blink_rate = AMMO.reload_blink_rate,
            reload_blink_count = AMMO.reload_blink_count,
            mic_led_enabled = AMMO.mic_led_enabled,
            mic_led_empty_enabled = AMMO.mic_led_empty_enabled,
            mic_led_reload_enabled = AMMO.mic_led_reload_enabled,
            mic_led_reload_frames = AMMO.mic_led_reload_frames,
            color_empty = copy_rgb(AMMO.color_empty),
        } or nil,
        events = EVENTS and {
            enabled = EVENTS.enabled,
            menu_enabled = EVENTS.menu_enabled,
            parry_duration = EVENTS.parry_duration,
            grab_flash_duration = EVENTS.grab_flash_duration,
            fatal_impact_duration = EVENTS.fatal_impact_duration,
            damage_duration = EVENTS.damage_duration,
            color_parry = copy_rgb(EVENTS.color_parry),
            color_damage = copy_rgb(EVENTS.color_damage),
            color_fatal = copy_rgb(EVENTS.color_fatal),
            color_hookshot = copy_rgb(EVENTS.color_hookshot),
            color_menu = copy_rgb(EVENTS.color_menu),
        } or nil,
        audio = AUDIO and {
            enabled = AUDIO.enabled,
            heal_enabled = AUDIO.heal_enabled,
            parry_enabled = AUDIO.parry_enabled,
            fatal_kick_enabled = AUDIO.fatal_kick_enabled,
            knife_hit_enabled = AUDIO.knife_hit_enabled,
            reload_enabled = AUDIO.reload_enabled,
            pickup_enabled = AUDIO.pickup_enabled,
            qte_enabled = AUDIO.qte_enabled,
            pickup_debug_enabled = AUDIO.pickup_debug_enabled,
            device_index = AUDIO.device_index,
            device_mode = AUDIO.device_mode,
            manual_device_index = AUDIO.manual_device_index,
            manual_device_id = AUDIO.manual_device_id,
            manual_device_label = AUDIO.manual_device_label,
            volume = AUDIO.volume,
            haptic_intensity = AUDIO.haptic_intensity,
            haptic_category_enabled = AUDIO.haptic_category_enabled,
            haptic_category_intensity = AUDIO.haptic_category_intensity,
        } or nil,
        radio = RADIO and {
            enabled = RADIO.enabled,
            mode = RADIO.mode,
            speaker_volume = RADIO.speaker_volume,
            latency_offset_ms = RADIO.latency_offset_ms,
            haptics_enabled = RADIO.haptics_enabled,
            language = RADIO.language,
            runtime_mute_experimental = RADIO.runtime_mute_experimental,
            fallback_to_duplicate = RADIO.fallback_to_duplicate,
        } or nil,
    }
end

local function apply(data)
    if type(data) ~= "table" then return false end

    local UI = _G.DualSenseEnhancedUI
    local ui = data.ui
    if UI and type(ui) == "table" then
        if ui.global_preset == "immersive" or ui.global_preset == "custom" then
            UI.global_preset = ui.global_preset
        end
        if ui.lightbar_mode == "enhanced" or ui.lightbar_mode == "native" then
            UI.lightbar_mode = ui.lightbar_mode
        end
        UI.show_debug_tools = bool(ui.show_debug_tools, UI.show_debug_tools)
    end

    local FEEDBACK = _G.DualSenseEnhancedFeedback
    local feedback = data.feedback or data.dsx
    if FEEDBACK and type(feedback) == "table" then
        FEEDBACK.hp_resume_fade_duration = num(
            feedback.hp_resume_fade_duration,
            FEEDBACK.hp_resume_fade_duration
        )
        FEEDBACK.lightbar_brightness = num(feedback.lightbar_brightness, FEEDBACK.lightbar_brightness)
        if FEEDBACK.lightbar_brightness < 0 then FEEDBACK.lightbar_brightness = 0 end
        if FEEDBACK.lightbar_brightness > 1 then FEEDBACK.lightbar_brightness = 1 end
        if feedback.output_mode == "dsx" or feedback.output_mode == "native"
            or feedback.output_mode == "off"
        then
            if FEEDBACK.set_output_mode then
                FEEDBACK.set_output_mode(feedback.output_mode)
            else
                FEEDBACK.output_mode = feedback.output_mode
            end
        end
        -- Also refresh the marker consumed by the native launcher before Lua
        -- itself loads on the next game start.
        if FEEDBACK.set_output_mode then
            FEEDBACK.set_output_mode(FEEDBACK.output_mode)
        end
    end

    local IPC = _G.DuaLibTriggerIpc
    local dualib = data.dualib
    if IPC and type(dualib) == "table" then
        IPC.enabled = bool(dualib.trigger_ipc_enabled, IPC.enabled)
        IPC.indicators_enabled = bool(dualib.indicators_enabled, IPC.indicators_enabled)
        IPC.lightbar_enabled = bool(dualib.lightbar_enabled, IPC.lightbar_enabled)
        IPC.mic_enabled = bool(dualib.mic_enabled, IPC.mic_enabled)
        IPC.haptics_mode_enabled = bool(dualib.haptics_mode_enabled, IPC.haptics_mode_enabled)
        if not IPC.enabled and IPC.reset then
            pcall(IPC.reset, "settings load")
        end
    end

    local GYRO = _G.NativeGyro
    if GYRO and GYRO.apply_settings then
        GYRO.apply_settings(data.gyro)
    end

    local TI = _G.TriggerIntensity
    local trigger_intensity = data.trigger_intensity
    if TI and type(trigger_intensity) == "table" then
        if trigger_intensity.preset and TI.PRESETS[trigger_intensity.preset] then
            TI.apply_preset(trigger_intensity.preset)
        end
        TI.global_intensity = num(trigger_intensity.global_intensity, TI.global_intensity)
        local saved_classes = trigger_intensity.class_intensity
        if type(saved_classes) == "table" then
            for class, value in pairs(saved_classes) do
                TI.class_intensity[class] = num(value, TI.class_intensity[class])
            end
        end
        if not trigger_intensity.preset or not TI.PRESETS[trigger_intensity.preset] then
            TI.preset = "custom"
        end
    end

    local HP = _G.HPLed
    local MIC = _G.DualSenseEnhancedMicLED
    local mic = data.mic
    if MIC and type(mic) == "table" then
        MIC.enabled = bool(mic.enabled, MIC.enabled)
        MIC.controller_index = num(mic.controller_index, MIC.controller_index)
        MIC.port = num(mic.port, MIC.port)
    end

    local hp = data.hp
    if HP and type(hp) == "table" then
        HP.enabled = bool(hp.enabled, HP.enabled)
        HP.healthy_threshold = num(hp.healthy_threshold, HP.healthy_threshold)
        HP.caution_threshold = num(hp.caution_threshold, HP.caution_threshold)
        HP.danger_threshold = num(hp.danger_threshold, HP.danger_threshold)
        HP.dim_threshold = num(hp.dim_threshold, HP.dim_threshold)
        HP.heal_duration = num(hp.heal_duration, HP.heal_duration)
        HP.danger_blink_rate = num(hp.danger_blink_rate, HP.danger_blink_rate)
        HP.vital_status_enabled = true
        apply_rgb(HP.color_healthy, hp.color_healthy)
        apply_rgb(HP.color_caution_hi, hp.color_caution_hi)
        apply_rgb(HP.color_caution_lo, hp.color_caution_lo)
        apply_rgb(HP.color_danger_lo, hp.color_danger_lo)
        apply_rgb(HP.color_heal, hp.color_heal)
    end

    local AMMO = _G.AmmoLed
    local ammo = data.ammo
    if AMMO and type(ammo) == "table" then
        AMMO.enabled = bool(ammo.enabled, AMMO.enabled)
        AMMO.mode = ammo.mode or AMMO.mode
        AMMO.warn_threshold = num(ammo.warn_threshold, AMMO.warn_threshold)
        AMMO.ammo_blink_rate = num(ammo.ammo_blink_rate, AMMO.ammo_blink_rate)
        AMMO.reload_count_hold = num(ammo.reload_count_hold, AMMO.reload_count_hold)
        AMMO.reload_blink_rate = num(ammo.reload_blink_rate, AMMO.reload_blink_rate)
        AMMO.reload_blink_count = num(ammo.reload_blink_count, AMMO.reload_blink_count)
        AMMO.mic_led_enabled = bool(ammo.mic_led_enabled, AMMO.mic_led_enabled)
        AMMO.mic_led_empty_enabled = bool(ammo.mic_led_empty_enabled, AMMO.mic_led_empty_enabled)
        AMMO.mic_led_reload_enabled = bool(ammo.mic_led_reload_enabled, AMMO.mic_led_reload_enabled)
        AMMO.mic_led_reload_frames = num(ammo.mic_led_reload_frames, AMMO.mic_led_reload_frames)
        apply_rgb(AMMO.color_empty, ammo.color_empty)
    end

    local EVENTS = _G.EventsLed
    local events = data.events
    if EVENTS and type(events) == "table" then
        EVENTS.enabled = bool(events.enabled, EVENTS.enabled)
        EVENTS.menu_enabled = bool(events.menu_enabled, EVENTS.menu_enabled)
        EVENTS.parry_duration = num(events.parry_duration, EVENTS.parry_duration)
        EVENTS.grab_flash_duration = num(events.grab_flash_duration, EVENTS.grab_flash_duration)
        EVENTS.fatal_impact_duration = num(events.fatal_impact_duration, EVENTS.fatal_impact_duration)
        EVENTS.damage_duration = num(events.damage_duration, EVENTS.damage_duration)
        apply_rgb(EVENTS.color_parry, events.color_parry)
        apply_rgb(EVENTS.color_damage, events.color_damage)
        apply_rgb(EVENTS.color_fatal, events.color_fatal)
        apply_rgb(EVENTS.color_hookshot, events.color_hookshot)
        apply_rgb(EVENTS.color_menu, events.color_menu)
    end

    local AUDIO = _G.DualSenseEnhancedAudio
    local audio = data.audio
    if AUDIO and type(audio) == "table" then
        AUDIO.enabled = bool(audio.enabled, AUDIO.enabled)
        AUDIO.heal_enabled = bool(audio.heal_enabled, AUDIO.heal_enabled)
        AUDIO.parry_enabled = bool(audio.parry_enabled, AUDIO.parry_enabled)
        AUDIO.fatal_kick_enabled = bool(audio.fatal_kick_enabled, AUDIO.fatal_kick_enabled)
        AUDIO.knife_hit_enabled = bool(audio.knife_hit_enabled, AUDIO.knife_hit_enabled)
        AUDIO.reload_enabled = bool(audio.reload_enabled, AUDIO.reload_enabled)
        AUDIO.pickup_enabled = bool(audio.pickup_enabled, AUDIO.pickup_enabled)
        AUDIO.qte_enabled = bool(audio.qte_enabled, AUDIO.qte_enabled)
        -- ID lookup databases now cover routine item/weapon identification.
        -- Keep pickup diagnostics opt-in for the current session instead of
        -- restoring an old persisted "true" value on every script reset.
        AUDIO.pickup_debug_enabled = false
        AUDIO.device_index = num(audio.device_index, AUDIO.device_index)
        if AUDIO.device_index < 1 or AUDIO.device_index > #AUDIO.device_options then
            AUDIO.device_index = 1
        end
        if audio.device_mode == "auto" or audio.device_mode == "manual"
            or audio.device_mode == "legacy"
        then
            AUDIO.device_mode = audio.device_mode
        end
        AUDIO.manual_device_index = num(audio.manual_device_index, AUDIO.manual_device_index)
        if AUDIO.manual_device_index < 1 then AUDIO.manual_device_index = 1 end
        if type(audio.manual_device_id) == "string" then
            AUDIO.manual_device_id = audio.manual_device_id
        end
        if type(audio.manual_device_label) == "string" then
            AUDIO.manual_device_label = audio.manual_device_label
        end
        AUDIO.volume = num(audio.volume, AUDIO.volume)
        if AUDIO.volume < 0 then AUDIO.volume = 0 end
        if AUDIO.volume > 1 then AUDIO.volume = 1 end
        AUDIO.haptic_intensity = num(audio.haptic_intensity, AUDIO.haptic_intensity)
        if AUDIO.haptic_intensity < 0 then AUDIO.haptic_intensity = 0 end
        if AUDIO.haptic_intensity > 1 then AUDIO.haptic_intensity = 1 end
        if type(audio.haptic_category_enabled) == "table" then
            for key, _ in pairs(AUDIO.haptic_category_enabled) do
                if audio.haptic_category_enabled[key] ~= nil then
                    AUDIO.haptic_category_enabled[key] = bool(audio.haptic_category_enabled[key], AUDIO.haptic_category_enabled[key])
                end
            end
        end
        if type(audio.haptic_category_intensity) == "table" then
            for key, current in pairs(AUDIO.haptic_category_intensity) do
                local value = num(audio.haptic_category_intensity[key], current)
                if value < 0.75 then
                    value = 0.5
                elseif value < 1.25 then
                    value = 1.0
                else
                    value = 1.5
                end
                AUDIO.haptic_category_intensity[key] = value
            end
        end
        if AUDIO.refresh_devices then pcall(AUDIO.refresh_devices) end
    end

    local RADIO = _G.DualSenseEnhancedRadio
    local radio = data.radio
    if RADIO and type(radio) == "table" then
        RADIO.enabled = bool(radio.enabled, RADIO.enabled)
        RADIO.mode = radio.mode or RADIO.mode
        RADIO.speaker_volume = num(radio.speaker_volume, RADIO.speaker_volume)
        if RADIO.speaker_volume < 0 then RADIO.speaker_volume = 0 end
        if RADIO.speaker_volume > 1 then RADIO.speaker_volume = 1 end
        RADIO.latency_offset_ms = num(radio.latency_offset_ms, RADIO.latency_offset_ms)
        RADIO.haptics_enabled = bool(radio.haptics_enabled, RADIO.haptics_enabled)
        RADIO.language = radio.language or RADIO.language
        RADIO.runtime_mute_experimental = bool(radio.runtime_mute_experimental, RADIO.runtime_mute_experimental)
        RADIO.fallback_to_duplicate = bool(radio.fallback_to_duplicate, RADIO.fallback_to_duplicate)
    end

    return true
end

local function current_signature()
    return serialize_value(snapshot(), "")
end

function SETTINGS.save()
    local signature = current_signature()
    local f = io.open(SETTINGS.path, "wb")
    if not f then
        SETTINGS.last_status = "save failed: cannot open " .. SETTINGS.path
        return false
    end
    f:write("return ")
    f:write(signature)
    f:write("\n")
    f:close()
    SETTINGS.last_status = "saved"
    last_saved_signature = signature
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("settings saved", SETTINGS.path) end
    return true
end

function SETTINGS.load()
    local probe = io.open(SETTINGS.path, "rb")
    if not probe then
        SETTINGS.last_status = "no settings file yet (press Save)"
        return false
    end
    local source = probe:read("*a")
    probe:close()

    -- io.open is resolved from REFramework's data directory, whereas loadfile
    -- is resolved from the game directory.  Compile the file that io.open
    -- actually found so Save and Load always use the same location.
    local chunk, err = load(source, "@" .. SETTINGS.path, "t")
    if not chunk then
        SETTINGS.last_status = "load skipped: " .. tostring(err)
        return false
    end
    local ok, data = pcall(chunk)
    if not ok then
        SETTINGS.last_status = "load failed: " .. tostring(data)
        return false
    end
    if not apply(data) then
        SETTINGS.last_status = "load failed: invalid data"
        return false
    end
    SETTINGS.last_status = "loaded"
    last_saved_signature = current_signature()
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("settings loaded", SETTINGS.path) end
    return true
end

local function autosave_tick()
    if not SETTINGS.autosave_enabled then return end
    autosave_frame_counter = autosave_frame_counter + 1
    if autosave_frame_counter < SETTINGS.autosave_interval_frames then return end
    autosave_frame_counter = 0

    local signature = current_signature()
    if signature == last_saved_signature then return end

    if SETTINGS.save() then
        SETTINGS.autosave_status = "autosaved"
    else
        SETTINGS.autosave_status = "autosave failed: " .. tostring(SETTINGS.last_status)
    end
end

function SETTINGS.reset_runtime_defaults()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then
        FEEDBACK.hp_resume_fade_duration = 30
        FEEDBACK.lightbar_brightness = 1.0
        if FEEDBACK.set_output_mode then FEEDBACK.set_output_mode("native") end
    end

    local UI = _G.DualSenseEnhancedUI
    if UI then
        UI.global_preset = "immersive"
        UI.lightbar_mode = "enhanced"
        UI.show_debug_tools = false
    end

    local HP = _G.HPLed
    if HP then
        HP.enabled = true
        HP.healthy_threshold = 0.60
        HP.caution_threshold = 0.30
        HP.danger_threshold = 0.29
        HP.dim_threshold = 0.10
        HP.color_healthy = {0, 220, 0}
        HP.color_caution_hi = {180, 255, 0}
        HP.color_caution_lo = {255, 80, 0}
        HP.color_danger_lo = {180, 0, 0}
        HP.color_heal = {0, 180, 255}
        if HP.reset_defaults then HP.reset_defaults() end
    end

    local AMMO = _G.AmmoLed
    if AMMO then
        AMMO.enabled = true
        AMMO.mode = "warning"
        AMMO.warn_threshold = 5
        AMMO.color_empty = {255, 80, 0}
        AMMO.mic_led_enabled = true
        AMMO.mic_led_empty_enabled = true
        AMMO.mic_led_reload_enabled = true
        if AMMO.reset_defaults then AMMO.reset_defaults() end
    end

    local EVENTS = _G.EventsLed
    if EVENTS then
        EVENTS.enabled = true
        EVENTS.menu_enabled = false
        EVENTS.color_parry = {0, 0, 255}
        EVENTS.color_damage = {255, 0, 0}
        EVENTS.color_fatal = {180, 0, 255}
        EVENTS.color_hookshot = {0, 160, 255}
        EVENTS.color_menu = {0, 0, 40}
        if EVENTS.reset_defaults then EVENTS.reset_defaults() end
    end

    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO then
        AUDIO.enabled = true
        AUDIO.heal_enabled = true
        AUDIO.parry_enabled = true
        AUDIO.fatal_kick_enabled = true
        AUDIO.knife_hit_enabled = true
        AUDIO.reload_enabled = true
        AUDIO.pickup_enabled = true
        AUDIO.qte_enabled = true
        AUDIO.pickup_debug_enabled = false
        AUDIO.device_index = 1
        AUDIO.device_mode = "auto"
        AUDIO.manual_device_index = 1
        AUDIO.manual_device_id = ""
        AUDIO.manual_device_label = ""
        AUDIO.volume = 0.85
        AUDIO.haptic_intensity = 0.6
        for key, _ in pairs(AUDIO.haptic_category_enabled) do
            AUDIO.haptic_category_enabled[key] = true
        end
        for key, _ in pairs(AUDIO.haptic_category_intensity) do
            AUDIO.haptic_category_intensity[key] = 1.0
        end
    end

    local RADIO = _G.DualSenseEnhancedRadio
    if RADIO then
        RADIO.enabled = false
        RADIO.mode = "speaker_duplicate"
        RADIO.speaker_volume = 1.0
        RADIO.latency_offset_ms = 0
        RADIO.haptics_enabled = false
        RADIO.language = "auto"
        RADIO.runtime_mute_experimental = false
        RADIO.fallback_to_duplicate = true
    end

    local MIC = _G.DualSenseEnhancedMicLED
    if MIC then
        MIC.enabled = true
        MIC.controller_index = 0
        MIC.port = nil
        if MIC.off then MIC.off() end
    end

    local IPC = _G.DuaLibTriggerIpc
    if IPC then
        IPC.enabled = true
        IPC.indicators_enabled = true
        IPC.lightbar_enabled = true
        IPC.mic_enabled = true
        -- Experimental, excluded from v1.0: always force off here so
        -- resetting to runtime defaults never silently re-enables it.
        IPC.haptics_mode_enabled = false
    end

    local NATIVE = _G.NativeDualSenseFeedback
    if NATIVE then
        NATIVE.lightbar_enabled = true
    end

    local GYRO = _G.NativeGyro
    if GYRO then
        GYRO.enabled = true
        if GYRO.apply_preset then GYRO.apply_preset("precision") end
        if GYRO.write_config then GYRO.write_config() end
    end

    local TI = _G.TriggerIntensity
    if TI and TI.apply_preset then TI.apply_preset("enhanced") end

    SETTINGS.last_status = "runtime defaults restored"
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("settings reset", "runtime defaults") end
end

_G.DualSenseEnhancedSettings = SETTINGS
SETTINGS.load()

pcall(function()
    re.on_application_entry("UpdateBehavior", autosave_tick)
end)
