local base = "reframework/autorun/DualSenseEnhanced/"

-- Set to true when packaging the Nexus/Fluffy Mod Manager release build:
-- skips loading and drawing the debug/experimental UI (event monitor,
-- native haptics diagnostics, Wwise event logger, radio speaker routing).
-- See release/v1.0/RELEASE_MANIFEST.md for the full packaging policy.
local RELEASE_BUILD = false

local LOG = {}
local LOG_MAX = 30

local function log(msg)
    table.insert(LOG, msg)
    if #LOG > LOG_MAX then table.remove(LOG, 1) end
    print("[DualSenseEnhanced] " .. msg)
end

local function loadf(name)
    local p = base .. name
    local f, err = loadfile(p)
    if not f then
        log("FAILED: " .. name .. " | " .. tostring(err))
        return false
    end
    local ok, res = pcall(f)
    if not ok then
        log("ERROR: " .. name .. " | " .. tostring(res))
        return false
    end
    log("OK: " .. name)
    return true
end

loadf("weapon_equip_core.lua")
loadf("feedback_writer.lua")
loadf("native_feedback.lua")
loadf("trigger_intensity.lua")
loadf("dualib_trigger_ipc.lua")
loadf("native_gyro.lua")
if not RELEASE_BUILD then
    loadf("monitor.lua")
    loadf("capcom_haptics_diag.lua")
end
loadf("item_ids.lua")
loadf("player_movement.lua")
loadf("audio_feedback.lua")
loadf("wwise_audio_router.lua")
if not RELEASE_BUILD then
    loadf("sound_event_diag.lua")
    loadf("radio_dialogue.lua")
    loadf("movement_diag.lua")
    if _G.MovementDiag then _G.MovementDiag.logger = log end
end
loadf("mic_led.lua")
loadf("hp_led.lua")
loadf("ammo_led.lua")
loadf("events_led.lua")

_G.DualSenseEnhancedUI = _G.DualSenseEnhancedUI or {}
local UI = _G.DualSenseEnhancedUI
UI.global_preset = UI.global_preset or "immersive"
UI.lightbar_mode = UI.lightbar_mode or "enhanced"
UI.show_debug_tools = UI.show_debug_tools == true

loadf("settings.lua")

local function clamp_byte(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return math.floor(v + 0.5)
end

local function rgb_to_vec3(tbl)
    return Vector3f.new(
        clamp_byte(tbl[1]) / 255.0,
        clamp_byte(tbl[2]) / 255.0,
        clamp_byte(tbl[3]) / 255.0
    )
end

local function vec3_to_rgb(vec)
    local function channel(v)
        v = tonumber(v) or 0
        if v <= 1.0 then v = v * 255.0 end
        return clamp_byte(v)
    end
    return channel(vec.x), channel(vec.y), channel(vec.z)
end

local function rgb_sliders(label, tbl, uid)
    local changed, vec = imgui.color_edit3(label .. "##" .. uid, rgb_to_vec3(tbl), nil)
    if changed and vec then
        tbl[1], tbl[2], tbl[3] = vec3_to_rgb(vec)
    end
    imgui.text(string.format("  rgb(%d, %d, %d)", tbl[1], tbl[2], tbl[3]))
    return changed
end

local function frame_slider(label, tbl, key, uid, min_v, max_v)
    tbl[key] = tonumber(tbl[key]) or min_v
    local changed, value = imgui.slider_int(label .. "##" .. uid, tbl[key], min_v, max_v)
    if changed then tbl[key] = value end
    imgui.text(string.format("  %d frames (~%.2fs)", tbl[key], tbl[key] / 60.0))
    return changed
end

local function mark_custom()
    UI.global_preset = "custom"
end

local function current_preset_label()
    if UI.global_preset == "immersive" then return "Immersive (Default)" end
    return "Custom"
end

local function set_output_native()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK and FEEDBACK.set_output_mode then pcall(FEEDBACK.set_output_mode, "native") end
end

local function set_lightbar_mode(mode)
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    local NATIVE = _G.NativeDualSenseFeedback
    local IPC = _G.DuaLibTriggerIpc

    if mode ~= "enhanced" and mode ~= "native" then return end
    UI.lightbar_mode = mode

    local enhanced = mode == "enhanced"
    if NATIVE then NATIVE.lightbar_enabled = enhanced end
    if IPC then IPC.lightbar_enabled = enhanced end

    if not enhanced and FEEDBACK then
        if FEEDBACK.clear_led then
            for _, name in ipairs({
                "parry", "finisher", "hookshot", "grab", "damage", "reload",
                "hp_gradient", "hp_danger", "hp_heal", "ammo_empty",
                "ammo_last", "menu",
            }) do
                pcall(FEEDBACK.clear_led, name)
            end
        end
        local native = _G.NativeDualSenseFeedback
        if native and native.release then pcall(native.release) end
    end
end

set_output_native()
set_lightbar_mode(UI.lightbar_mode == "native" and "native" or "enhanced")

local function apply_global_preset(name)
    if name ~= "immersive" then return end
    UI.global_preset = "immersive"
    UI.lightbar_mode = "enhanced"

    set_output_native()

    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then
        FEEDBACK.mod_master_enabled = true
        FEEDBACK.lightbar_brightness = 1.0
    end

    local CORE = _G.WeaponEquipCore
    if CORE and CORE.config then CORE.config.enabled = true end

    local HP = _G.HPLed
    if HP then HP.enabled = true end

    local AMMO = _G.AmmoLed
    if AMMO then
        AMMO.enabled = true
        AMMO.mic_led_enabled = true
        AMMO.mic_led_empty_enabled = true
        AMMO.mic_led_reload_enabled = true
    end

    local EVENTS = _G.EventsLed
    if EVENTS then
        EVENTS.enabled = true
        EVENTS.menu_enabled = false
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
        AUDIO.volume = 0.85
    end

    local WWISE = _G.DualSenseEnhancedWwiseAudioRouter
    if WWISE then WWISE.enabled = true end

    local MIC = _G.DualSenseEnhancedMicLED
    if MIC then MIC.enabled = true end

    local IPC = _G.DuaLibTriggerIpc
    if IPC then
        IPC.enabled = true
        IPC.indicators_enabled = true
        IPC.lightbar_enabled = true
        IPC.mic_enabled = true
    end

    local NATIVE = _G.NativeDualSenseFeedback
    if NATIVE then NATIVE.lightbar_enabled = true end

    local TI = _G.TriggerIntensity
    if TI and TI.apply_preset then pcall(TI.apply_preset, "enhanced") end

    local GYRO = _G.NativeGyro
    if GYRO then
        GYRO.enabled = true
        if GYRO.apply_preset then pcall(GYRO.apply_preset, "precision") end
        if GYRO.write_config then pcall(GYRO.write_config) end
    end

    local RADIO = _G.DualSenseEnhancedRadio
    if RADIO then RADIO.enabled = false end
end

local function status_line(label, state)
    imgui.text(label .. ": " .. tostring(state))
end

local function bool_status(value)
    return value and "Ready" or "Missing"
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function audio_files_ready()
    return file_exists("DualSenseEnhanced/sounds/parry1.wav")
        or file_exists("DualSenseEnhanced/sounds/wp4000_dry_fire.wav")
        or file_exists("DualSenseEnhanced/sounds/heal_herb.wav")
end

local function draw_status(FEEDBACK, NATIVE, AUDIO, GYRO, IPC, EVENTS)
    if imgui.tree_node("Status") then
        local native_ready = NATIVE and NATIVE.available == true
        local speaker_ready = AUDIO and AUDIO.enabled ~= false and AUDIO.last_status ~= "missing"
        local gameplay_state = EVENTS and EVENTS.in_game and "Active" or "Waiting for gameplay"

        status_line("Native DualSense", bool_status(native_ready))
        status_line("Controller Speaker", speaker_ready and "Configured" or "Missing")
        status_line("Audio Files", audio_files_ready() and "Found" or "Missing")
        status_line("Native Features", gameplay_state)
        if GYRO then status_line("Gyro Aim", GYRO.enabled and "On" or "Off") end
        if IPC then status_line("Adaptive Triggers", IPC.enabled and "On" or "Off") end
        if IPC then
            status_line("Enhanced Haptics", IPC.haptics_mode_enabled and "On" or "Off")
        end

        if not native_ready then
            imgui.text_colored(
                "Native DualSense is not ready. Use USB, close controller tools, and disable Steam Input.",
                0xFF8888FF)
        end
        if not audio_files_ready() then
            imgui.text_colored(
                "Controller speaker audio files are missing. Run setup_sounds.bat.",
                0xFF8888FF)
        end
        imgui.tree_pop()
    end
end

local function draw_global_preset()
    if imgui.tree_node("Global Preset") then
        imgui.text("Current preset: " .. current_preset_label())
        if imgui.button("Apply Immersive Defaults##global_preset_immersive") then
            apply_global_preset("immersive")
        end
        imgui.text_colored(
            "Changing any feature below automatically marks the preset as Custom.",
            0xFFAAAAAA)
        imgui.tree_pop()
    end
end

local function draw_quick_controls(HP, AMMO, EVENTS, AUDIO, GYRO, IPC, MIC)
    if imgui.tree_node("Quick Controls") then
        imgui.text_colored(
            "Quick access to the same feature switches available in the detailed sections below.",
            0xFFAAAAAA)
        local enhanced = UI.lightbar_mode == "enhanced"
        local lc, lv = imgui.checkbox("Enhanced Lightbar##core_lightbar", enhanced)
        if lc then set_lightbar_mode(lv and "enhanced" or "native"); mark_custom() end

        local trigger_on = IPC and IPC.enabled == true
        local tc, tv = imgui.checkbox("Adaptive Triggers##core_triggers", trigger_on)
        if tc and IPC then
            IPC.enabled = tv
            if not tv and IPC.reset then pcall(IPC.reset, "UI disabled") end
            mark_custom()
        end

        local ac, av = imgui.checkbox("Controller Speaker Audio##core_audio", AUDIO and AUDIO.enabled == true or false)
        if ac and AUDIO then AUDIO.enabled = av; mark_custom() end

        local gc, gv = imgui.checkbox("Gyro Aim##core_gyro", GYRO and GYRO.enabled == true or false)
        if gc and GYRO then
            GYRO.enabled = gv
            if GYRO.write_config then pcall(GYRO.write_config) end
            mark_custom()
        end

        local hc, hv = imgui.checkbox(
            "Enhanced Haptics##core_haptics",
            IPC and IPC.haptics_mode_enabled == true or false)
        if hc and IPC then
            IPC.haptics_mode_enabled = hv
            mark_custom()
        end

        imgui.tree_pop()
    end
end

local function draw_lightbar(FEEDBACK, HP, AMMO, EVENTS)
    if imgui.tree_node("Lightbar") then
        imgui.text("Mode:")
        local enhanced_marker = UI.lightbar_mode == "enhanced" and "[x] " or "[ ] "
        local native_marker = UI.lightbar_mode == "native" and "[x] " or "[ ] "
        if imgui.button(enhanced_marker .. "Enhanced Mod Lightbar##lightbar_mode_enhanced") then
            set_lightbar_mode("enhanced")
            mark_custom()
        end
        imgui.same_line()
        if imgui.button(native_marker .. "Native Game Lightbar##lightbar_mode_native") then
            set_lightbar_mode("native")
            mark_custom()
        end
        imgui.text_colored(
            "Native Game Lightbar releases RGB control back to the game.",
            0xFFAAAAAA)

        if FEEDBACK then
            local brightness_percent = math.floor(((FEEDBACK.lightbar_brightness or 1.0) * 100) + 0.5)
            local bc, bv = imgui.slider_int(
                "Brightness (%)##lightbar_brightness",
                brightness_percent, 0, 100)
            if bc then FEEDBACK.lightbar_brightness = bv / 100; mark_custom() end
        end

        if imgui.tree_node("Advanced Lightbar Colors") then
            if HP then
                local c1 = rgb_sliders("Health - Fine", HP.color_healthy, "hp_healthy")
                local c2 = rgb_sliders("Health - Caution High", HP.color_caution_hi, "hp_caut_hi")
                local c3 = rgb_sliders("Health - Caution Low", HP.color_caution_lo, "hp_caut_lo")
                local c4 = rgb_sliders("Healing", HP.color_heal, "hp_heal")
                if c1 or c2 or c3 or c4 then mark_custom() end
            end
            if AMMO then
                if rgb_sliders("Empty Ammo", AMMO.color_empty, "ammo_empty") then mark_custom() end
            end
            if EVENTS then
                local e1 = rgb_sliders("Damage", EVENTS.color_damage, "ev_damage")
                local e2 = rgb_sliders("Parry", EVENTS.color_parry, "ev_parry")
                local e3 = rgb_sliders("Fatal Kick", EVENTS.color_fatal, "ev_fatal")
                local e4 = rgb_sliders("Hookshot", EVENTS.color_hookshot, "ev_hookshot")
                local e5 = rgb_sliders("Menu", EVENTS.color_menu, "ev_menu")
                if e1 or e2 or e3 or e4 or e5 then mark_custom() end
            end
            imgui.tree_pop()
        end

        if imgui.tree_node("Advanced Lightbar Timing") then
            local changed = false
            if HP then
                changed = frame_slider("Heal transition", HP, "heal_duration", "hp_heal_dur", 30, 600) or changed
                changed = frame_slider("Danger pulse rate", HP, "danger_blink_rate", "hp_danger_rate", 5, 120) or changed
            end
            if EVENTS then
                changed = frame_slider("Parry flash", EVENTS, "parry_duration", "ev_parry_dur", 5, 240) or changed
                changed = frame_slider("Grab input flash", EVENTS, "grab_flash_duration", "ev_grab_flash_dur", 2, 60) or changed
                changed = frame_slider("Fatal kick impact", EVENTS, "fatal_impact_duration", "ev_fatal_dur", 2, 120) or changed
                changed = frame_slider("Damage flash", EVENTS, "damage_duration", "ev_damage_dur", 5, 240) or changed
            end
            if changed then mark_custom() end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end

local function draw_triggers(IPC, TI)
    if imgui.tree_node("Adaptive Triggers") then
        if IPC then
            local c, v = imgui.checkbox("Enabled##triggers_enabled", IPC.enabled)
            if c then
                IPC.enabled = v
                if not v and IPC.reset then pcall(IPC.reset, "UI disabled") end
                mark_custom()
            end
        end
        if TI then
            imgui.text("Preset:")
            for _, name in ipairs(TI.PRESET_ORDER) do
                if name ~= "custom" then
                    if imgui.button(TI.PRESETS[name].label .. "##trigger_preset_" .. name) then
                        pcall(TI.apply_preset, name)
                        mark_custom()
                    end
                    imgui.same_line()
                end
            end
            imgui.new_line()
            imgui.text("Current preset: " .. tostring(TI.preset))
            local trigger_percent = math.floor(((TI.global_intensity or 1.0) * 100) + 0.5)
            local gc, gv = imgui.slider_int(
                "Global Strength (%)##trigger_global",
                trigger_percent, 0, 200)
            if gc then TI.global_intensity = gv / 100; TI.mark_custom(); mark_custom() end

            if imgui.tree_node("Advanced Trigger Settings") then
                for _, class in ipairs({ "pistol", "shotgun", "rifle", "automatic", "magnum" }) do
                    local class_percent = math.floor(((TI.class_intensity[class] or 1.0) * 100) + 0.5)
                    local cc, cv = imgui.slider_int(
                        class:sub(1, 1):upper() .. class:sub(2) .. " Strength (%)##trigger_class_" .. class,
                        class_percent, 0, 200)
                    if cc then TI.class_intensity[class] = cv / 100; TI.mark_custom(); mark_custom() end
                end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
end

local function draw_audio(AUDIO)
    if AUDIO and imgui.tree_node("Controller Speaker Audio") then
        local c, v = imgui.checkbox("Enabled##audio", AUDIO.enabled)
        if c then AUDIO.enabled = v; mark_custom() end

        imgui.text("Output Mode:")
        local auto_marker = AUDIO.device_mode == "auto" and "[x] " or "[ ] "
        local manual_marker = AUDIO.device_mode == "manual" and "[x] " or "[ ] "
        if imgui.button(auto_marker .. "Auto DualSense##audio_mode_auto") then
            AUDIO.device_mode = "auto"
            mark_custom()
        end
        imgui.same_line()
        if imgui.button(manual_marker .. "Manual Endpoint##audio_mode_manual") then
            AUDIO.device_mode = "manual"
            if AUDIO.refresh_devices then pcall(AUDIO.refresh_devices) end
            mark_custom()
        end

        if AUDIO.device_mode == "manual" then
            if imgui.button("Refresh Devices##audio_device_refresh") and AUDIO.refresh_devices then
                pcall(AUDIO.refresh_devices)
            end

            imgui.text("Devices: " .. tostring(AUDIO.devices_status or "unknown"))
            local devices = AUDIO.manual_devices or {}
            if #devices == 0 then
                imgui.text("No active audio endpoints reported by the bridge yet.")
            else
                for index, device in ipairs(devices) do
                    local selected = AUDIO.manual_device_id ~= "" and device.id == AUDIO.manual_device_id
                    if not selected then selected = index == AUDIO.manual_device_index end

                    local marker = selected and "[x] " or "[ ] "
                    local suffix = ""
                    if device.is_default_auto then suffix = suffix .. "  Auto" end
                    if device.is_dualsense then suffix = suffix .. "  DualSense" end
                    local label = tostring(device.label or ("Endpoint " .. tostring(index)))
                    if #label > 72 then label = label:sub(1, 69) .. "..." end

                    if imgui.button(marker .. label .. suffix .. "##audio_endpoint_" .. tostring(index)) then
                        AUDIO.manual_device_index = index
                        AUDIO.manual_device_id = device.id or ""
                        AUDIO.manual_device_label = device.label or ""
                        mark_custom()
                    end
                end
            end

            local selected = (AUDIO.manual_devices or {})[AUDIO.manual_device_index]
            local label = selected and selected.label or AUDIO.manual_device_label or "none"
            imgui.text("Selected Endpoint: " .. tostring(label))
        elseif AUDIO.device_mode == "legacy" then
            local device_option = AUDIO.device_options[AUDIO.device_index] or AUDIO.device_options[1]
            imgui.text("Compatibility Output: " .. tostring(device_option.label))
        else
            imgui.text("Selected Endpoint: automatic DualSense detection")
            imgui.text("Devices: " .. tostring(AUDIO.devices_status or "unknown"))
        end

        local volume_percent = math.floor(((AUDIO.volume or 0.85) * 100) + 0.5)
        local cv, vv = imgui.slider_int(
            "Speaker Volume (%)##audio_volume",
            volume_percent, 0, 100)
        if cv then AUDIO.volume = vv / 100; mark_custom() end

        if imgui.button("Test Speaker##audio_test") and AUDIO.play_test then pcall(AUDIO.play_test) end

        if imgui.tree_node("Compatibility Audio Output") then
            local legacy_marker = AUDIO.device_mode == "legacy" and "[x] " or "[ ] "
            if imgui.button(legacy_marker .. "Legacy Presets##audio_mode_legacy") then
                AUDIO.device_mode = "legacy"
                mark_custom()
            end
            if AUDIO.device_mode == "legacy" then
                local device_option = AUDIO.device_options[AUDIO.device_index] or AUDIO.device_options[1]
                imgui.text("Legacy Output: " .. tostring(device_option.label))
                if imgui.button("Previous##audio_legacy_device_prev") then
                    AUDIO.device_index = AUDIO.device_index - 1
                    if AUDIO.device_index < 1 then AUDIO.device_index = #AUDIO.device_options end
                    mark_custom()
                end
                imgui.same_line()
                if imgui.button("Next##audio_legacy_device_next") then
                    AUDIO.device_index = AUDIO.device_index + 1
                    if AUDIO.device_index > #AUDIO.device_options then AUDIO.device_index = 1 end
                    mark_custom()
                end
            end
            imgui.tree_pop()
        end

        if imgui.tree_node("Advanced Audio Events") then
            local ch, vh = imgui.checkbox("Healing##audio_heal", AUDIO.heal_enabled)
            if ch then AUDIO.heal_enabled = vh; mark_custom() end
            local cp, vp = imgui.checkbox("Parry##audio_parry", AUDIO.parry_enabled)
            if cp then AUDIO.parry_enabled = vp; mark_custom() end
            local cfk, vfk = imgui.checkbox("Fatal Kick##audio_fatal_kick", AUDIO.fatal_kick_enabled)
            if cfk then AUDIO.fatal_kick_enabled = vfk; mark_custom() end
            if not RELEASE_BUILD then
                local ckh, vkh = imgui.checkbox("Knife Hit##audio_knife_hit", AUDIO.knife_hit_enabled)
                if ckh then AUDIO.knife_hit_enabled = vkh; mark_custom() end
            end
            local crl, vrl = imgui.checkbox("Weapon Reloads##audio_reload", AUDIO.reload_enabled)
            if crl then AUDIO.reload_enabled = vrl; mark_custom() end
            local cq, vq = imgui.checkbox("Grab QTE##audio_qte", AUDIO.qte_enabled)
            if cq then AUDIO.qte_enabled = vq; mark_custom() end
            local cpk, vpk = imgui.checkbox("Item Pickups##audio_pickup", AUDIO.pickup_enabled)
            if cpk then AUDIO.pickup_enabled = vpk; mark_custom() end
            if not RELEASE_BUILD then
                imgui.text("Status: " .. tostring(AUDIO.last_status or "unknown"))
                imgui.text("Last event: " .. tostring(AUDIO.last_event or "none"))
            end
            if AUDIO.last_error then
                imgui.text_colored("Last error: " .. tostring(AUDIO.last_error), 0xFF8888FF)
            end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end

local function draw_gyro(GYRO)
    if GYRO and imgui.tree_node("Gyro Aim") then
        local changed = false
        local c, v = imgui.checkbox("Enabled##native_gyro_enabled", GYRO.enabled)
        if c then GYRO.enabled = v; changed = true; mark_custom() end

        imgui.text("Preset:")
        for _, name in ipairs(GYRO.PRESET_ORDER) do
            if name ~= "custom" then
                if imgui.button(GYRO.PRESET_LABELS[name] .. "##gyro_preset_" .. name) then
                    pcall(GYRO.apply_preset, name)
                    changed = true
                    mark_custom()
                end
                imgui.same_line()
            end
        end
        imgui.new_line()
        imgui.text("Current: " .. tostring(GYRO.PRESET_LABELS[GYRO.preset] or GYRO.preset))
        imgui.text("Gyro injects mouse movement while aiming; the game may show keyboard/mouse prompts.")

        if imgui.tree_node("Advanced Gyro Settings") then
            local yc, yv = imgui.slider_int("Yaw Sensitivity##native_gyro_yaw", math.floor(GYRO.yaw_sensitivity + 0.5), 100, 2000)
            if yc then GYRO.yaw_sensitivity = yv; GYRO.mark_custom(); changed = true; mark_custom() end
            local pc, pv = imgui.slider_int("Pitch Sensitivity##native_gyro_pitch", math.floor(GYRO.pitch_sensitivity + 0.5), 100, 2000)
            if pc then GYRO.pitch_sensitivity = pv; GYRO.mark_custom(); changed = true; mark_custom() end
            local dc, dv = imgui.slider_float("Deadzone##native_gyro_deadzone", GYRO.deadzone, 0.005, 0.20)
            if dc then GYRO.deadzone = dv; GYRO.mark_custom(); changed = true; mark_custom() end
            local ac, av = imgui.slider_int("L2 Aim Threshold##native_gyro_aim_threshold", GYRO.aim_threshold, 1, 128)
            if ac then GYRO.aim_threshold = av; GYRO.mark_custom(); changed = true; mark_custom() end
            local cc, cv = imgui.slider_int("Calibration Time (ms)##native_gyro_calibration", GYRO.calibration_ms, 500, 5000)
            if cc then GYRO.calibration_ms = cv; GYRO.mark_custom(); changed = true; mark_custom() end
            local ic, iv = imgui.checkbox("Invert Y##native_gyro_invert_pitch", GYRO.invert_pitch)
            if ic then GYRO.invert_pitch = iv; changed = true; mark_custom() end
            imgui.tree_pop()
        end

        if changed and GYRO.write_config then pcall(GYRO.write_config) end
        imgui.text("Config: " .. tostring(GYRO.last_error))
        imgui.tree_pop()
    end
end

local function draw_advanced(CONFIG, RADIO, IPC, MIC, AMMO, CORE)
    if imgui.tree_node("Advanced") then
        if CONFIG and imgui.tree_node("Config") then
            if imgui.button("Save##config") then CONFIG.save() end
            imgui.same_line()
            if imgui.button("Load##config") then CONFIG.load() end
            imgui.same_line()
            if imgui.button("Reset Defaults##config") then CONFIG.reset_runtime_defaults() end
            imgui.text("Path: " .. tostring(CONFIG.path))
            imgui.text("Status: " .. tostring(CONFIG.last_status))
            local ca, va = imgui.checkbox("Autosave##config_autosave", CONFIG.autosave_enabled)
            if ca then CONFIG.autosave_enabled = va end
            imgui.text("Autosave: " .. tostring(CONFIG.autosave_status))
            imgui.tree_pop()
        end

        if IPC and imgui.tree_node("Native Indicators and Mic LED") then
            local ic, iv = imgui.checkbox("Ammo Indicator LEDs##dualib_indicators", IPC.indicators_enabled)
            if ic then IPC.indicators_enabled = iv; mark_custom() end
            local mc, mv = imgui.checkbox("Mic LED Sync##dualib_mic", IPC.mic_enabled)
            if mc then IPC.mic_enabled = mv; mark_custom() end
            if AMMO then
                local cme, vme = imgui.checkbox("Ammo Mic LED Effects##ammo_mic_enable", AMMO.mic_led_enabled)
                if cme then AMMO.mic_led_enabled = vme; mark_custom() end
                local cem, vem = imgui.checkbox("Empty Ammo Pulse##ammo_mic_empty", AMMO.mic_led_empty_enabled)
                if cem then AMMO.mic_led_empty_enabled = vem; mark_custom() end
                local crm, vrm = imgui.checkbox("Reload Finish Pulse##ammo_mic_reload", AMMO.mic_led_reload_enabled)
                if crm then AMMO.mic_led_reload_enabled = vrm; mark_custom() end
            end
            if MIC then imgui.text("Mic LED status: " .. tostring(MIC.last_status)) end
            imgui.tree_pop()
        end

        if CORE and imgui.tree_node("Weapon State") then
            if CORE.last_info then
                local i = CORE.last_info
                imgui.text(string.format("Weapon: %s [%s]  Ammo: %d/%d",
                    tostring(i.name), tostring(i.type), i.ammo or 0, i.ammoMax or 0))
            else
                imgui.text("Weapon: not detected")
            end
            imgui.tree_pop()
        end

        if RADIO and imgui.tree_node("Radio Speaker Routing (Experimental)") then
            imgui.text("Coming soon / experimental. Kept off for v1.0.")
            local ce, ve = imgui.checkbox("Enabled##radio", RADIO.enabled)
            if ce then RADIO.enabled = ve; mark_custom() end
            imgui.text("Status: " .. tostring(RADIO.last_status))
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
end

local HAPTIC_CATEGORY_LEVEL_VALUES = {0.5, 1.0, 1.5}
local HAPTIC_CATEGORY_LEVEL_LABELS = {"Soft", "Normal", "Strong"}

local function draw_enhanced_haptics(IPC)
    if not IPC then return end
    if imgui.tree_node("Enhanced Haptics") then
        imgui.text_colored(
            "Adds detailed actuator feedback for footsteps, combat actions, healing, and pickups.",
            0xFFAAAAAA)
        local he, ve = imgui.checkbox("Enable Enhanced Haptics##ipc_haptics_mode", IPC.haptics_mode_enabled)
        if he then
            IPC.haptics_mode_enabled = ve
            mark_custom()
        end
        if not IPC.haptics_mode_enabled then
            imgui.text_colored("Enable the checkbox above first.", 0xFF888888)
        end

        local AUDIO = _G.DualSenseEnhancedAudio
        if AUDIO then
            local global_percent = math.floor(((AUDIO.haptic_intensity or 0.6) * 100) + 0.5)
            local hi_changed, hi_value = imgui.slider_int(
                "Global strength (%)##haptic_intensity",
                global_percent, 0, 100)
            if hi_changed then
                AUDIO.haptic_intensity = hi_value / 100
                mark_custom()
            end
            imgui.text_colored(
                "Global strength affects every category. Use the master/category checkboxes for Off.",
                0xFFAAAAAA)

            imgui.separator()
            imgui.text("Category controls")
            imgui.text_colored(
                "Soft, Normal, and Strong are tuned relative to each effect.",
                0xFFAAAAAA)
            imgui.text_colored(
                "Soft still gives a light pulse; use the checkbox for Off.",
                0xFFAAAAAA)
            if imgui.button("Enable All##haptic_categories_enable_all") then
                for key, _ in pairs(AUDIO.haptic_category_enabled) do
                    AUDIO.haptic_category_enabled[key] = true
                end
                mark_custom()
            end
            imgui.same_line()
            if imgui.button("Disable All##haptic_categories_disable_all") then
                for key, _ in pairs(AUDIO.haptic_category_enabled) do
                    AUDIO.haptic_category_enabled[key] = false
                end
                mark_custom()
            end
            if imgui.button("Reset Levels to Normal##haptic_categories_reset_strength") then
                for key, _ in pairs(AUDIO.haptic_category_intensity) do
                    AUDIO.haptic_category_intensity[key] = 1.0
                end
                mark_custom()
            end
            if AUDIO.HAPTIC_CATEGORY_LABELS and AUDIO.haptic_category_enabled
                and AUDIO.haptic_category_intensity
            then
                for _, cat in ipairs(AUDIO.HAPTIC_CATEGORY_LABELS) do
                    local ce, cv = imgui.checkbox(
                        "##haptic_cat_enabled_" .. cat.key,
                        AUDIO.haptic_category_enabled[cat.key])
                    if ce then
                        AUDIO.haptic_category_enabled[cat.key] = cv
                        mark_custom()
                    end
                    imgui.same_line()
                    local current = AUDIO.haptic_category_intensity[cat.key] or 1.0
                    local current_level = 2
                    if current < 0.75 then
                        current_level = 1
                    elseif current >= 1.25 then
                        current_level = 3
                    end
                    local ci_changed, ci_value = imgui.slider_int(
                        cat.label .. ": " .. HAPTIC_CATEGORY_LEVEL_LABELS[current_level]
                            .. "##haptic_cat_intensity_" .. cat.key,
                        current_level, 1, 3)
                    if ci_changed then
                        AUDIO.haptic_category_intensity[cat.key] = HAPTIC_CATEGORY_LEVEL_VALUES[ci_value]
                        mark_custom()
                    end
                end
            end
        end

        if AUDIO and IPC.haptics_mode_enabled and AUDIO.enabled then
            if imgui.button("Test Haptics (Parry Pulse)##ipc_haptics_test") then
                if AUDIO.play_haptic_test then pcall(AUDIO.play_haptic_test) end
            end
            imgui.text_colored("Test status: " .. tostring(AUDIO.haptic_test_status or "Not tested"), 0xFFAAAAAA)
        elseif AUDIO and not AUDIO.enabled then
            imgui.text_colored("Enable Controller Speaker Audio to test haptics.", 0xFF888888)
        else
            imgui.text_colored("Enable Enhanced Haptics to run the test pulse.", 0xFF888888)
        end
        imgui.tree_pop()
    end
end

local function draw_debug(MON, SND, CAPCOM, FEEDBACK, IPC)
    local changed, value = imgui.checkbox("Show Debug Tools##show_debug", UI.show_debug_tools)
    if changed then UI.show_debug_tools = value end
    if not UI.show_debug_tools then return end

    if imgui.tree_node("Debug Tools") then
        if MON and imgui.tree_node("Event Monitor") then
            if imgui.button("Clear events##monitor") then MON.clear() end
            for _, ev in ipairs(MON.events) do
                imgui.text(string.format("%s  %s", tostring(ev.time), tostring(ev.text)))
            end
            if #MON.events == 0 then imgui.text("(no events)") end
            imgui.tree_pop()
        end

        if _G.MovementDiag and imgui.tree_node("Movement Diagnostics") then
            imgui.text_colored(
                "Dumps player fields/methods matching run/sprint/speed/etc",
                0xFFAAAAAA)
            imgui.text_colored(
                "to the console. Click once standing still, once while",
                0xFFAAAAAA)
            imgui.text_colored(
                "sprinting, and compare which values changed.",
                0xFFAAAAAA)
            if imgui.button("Dump Movement Fields##movement_diag_dump") then
                pcall(_G.MovementDiag.dump)
            end
            imgui.tree_pop()
        end

        if SND and imgui.tree_node("Sound Event Diagnostics") then
            local cse, vse = imgui.checkbox("Enable Wwise logging##sound_diag_enable", SND.enabled)
            if cse then SND.enabled = vse end

            if SND.enabled then
                local cam, vam = imgui.checkbox("Auto-correlate (Option 2)##sound_diag_auto", SND.auto_mode)
                if cam then SND.auto_mode = vam end
                imgui.same_line()
                imgui.text_colored("Auto opens labelled windows on weapon switch / shot / reload", 0xFFAAAAAA)

                imgui.separator()
                -- Manual capture for dry-fire (can't be auto-detected from ammo alone)
                if imgui.button("Capture Dry Fire (3s)##sound_diag_dry") and SND.begin_window then
                    pcall(SND.begin_window, "dry_fire", 180)
                end
                imgui.same_line()
                if imgui.button("Manual 5s##sound_diag_manual") and SND.begin_window then
                    pcall(SND.begin_window, "manual", 300)
                end
                imgui.same_line()
                -- Footstep-haptics research (docs/HAPTICS_FOOTSTEPS_TASK.md
                -- Stage 3): 15s @ 60fps = 900 frames, long enough to run
                -- across a couple of different surfaces in one capture.
                if imgui.button("Capture Footsteps (15s)##sound_diag_footsteps") and SND.begin_window then
                    pcall(SND.begin_window, "footstep_walk", 900)
                end

                imgui.separator()
                local win_fr = SND.window_frames or 0
                if win_fr > 0 then
                    imgui.text_colored(
                        string.format("CAPTURING: %s  (%d frames left)", tostring(SND.window_reason), win_fr),
                        0xFF44FF44)
                else
                    imgui.text("Window: closed")
                end
                imgui.text(string.format("Events this window: %d  Total: %d",
                    SND.window_event_count or 0, SND.total_event_count or 0))
            end

            imgui.separator()
            if imgui.button("Clear log##sound_diag_clear") and SND.clear_log then pcall(SND.clear_log) end
            imgui.text("Status: " .. tostring(SND.last_status or "unknown"))
            imgui.text("Last error: " .. tostring(SND.last_error or "none"))
            imgui.text("Log: " .. tostring(SND.log_path or "none"))
            imgui.tree_pop()
        end

        if CAPCOM and imgui.tree_node("Native Haptics Diagnostics") then
            imgui.text("Read-only diagnostics.")
            local ce, ve = imgui.checkbox("Enable diagnostics##capcom_haptics", CAPCOM.enabled)
            if ce then CAPCOM.enabled = ve end
            if imgui.button("Refresh now##capcom_haptics") and CAPCOM.refresh then pcall(CAPCOM.refresh) end
            imgui.text("Native DeviceType: " .. tostring(CAPCOM.native_gamepad_device_type or "unknown"))
            imgui.text("Last: " .. tostring(CAPCOM.last_event or "none"))
            imgui.text("Error: " .. tostring(CAPCOM.last_error or "none"))
            imgui.tree_pop()
        end

        if imgui.tree_node("Enhanced Haptics: Synth vs Real A/B (dev)") then
            imgui.text_colored(
                "Dev-only comparison tool, not part of the shipped feature.",
                0xFFAAAAAA)
            imgui.text_colored(
                "Real = extracted SFX, low-pass filtered + trimmed offline",
                0xFFAAAAAA)
            imgui.text_colored(
                "(tools/audio_to_haptic.py). Synth = the earlier synthesized",
                0xFFAAAAAA)
            imgui.text_colored(
                "tone, kept only for this comparison.", 0xFFAAAAAA)
            imgui.text_colored(
                "Requires Enhanced Haptics enabled above.", 0xFFAAAAAA)
            local AUDIO = _G.DualSenseEnhancedAudio
            if AUDIO and AUDIO.emit then
                if imgui.button("Synth: Parry (current)##ab_parry_synth") then
                    pcall(AUDIO.emit, "haptic_parry")
                end
                imgui.same_line()
                if imgui.button("Real: Parry##ab_parry_real") then
                    pcall(AUDIO.emit, "haptic_parry_real")
                end
            end
            imgui.separator()
            imgui.text_colored(
                "Footstep: real Leon footstep SFX (ch_cha0.bnk event",
                0xFFAAAAAA)
            imgui.text_colored(
                "1528453721), same 3-tier intensity split as synth.",
                0xFFAAAAAA)
            if AUDIO and AUDIO.emit then
                if imgui.button("Synth: Footstep Soft (current)##ab_fs_soft_synth") then
                    pcall(AUDIO.emit, "haptic_footstep_soft")
                end
                imgui.same_line()
                if imgui.button("Real: Footstep Soft##ab_fs_soft_real") then
                    pcall(AUDIO.emit, "haptic_footstep_real_soft")
                end
                if imgui.button("Synth: Footstep Normal (current)##ab_fs_normal_synth") then
                    pcall(AUDIO.emit, "haptic_footstep")
                end
                imgui.same_line()
                if imgui.button("Real: Footstep Normal##ab_fs_normal_real") then
                    pcall(AUDIO.emit, "haptic_footstep_real")
                end
                if imgui.button("Synth: Footstep Strong (current)##ab_fs_strong_synth") then
                    pcall(AUDIO.emit, "haptic_footstep_strong")
                end
                imgui.same_line()
                if imgui.button("Real: Footstep Strong##ab_fs_strong_real") then
                    pcall(AUDIO.emit, "haptic_footstep_real_strong")
                end
            end
            imgui.tree_pop()
        end

        if imgui.tree_node("Console") then
            if imgui.button("Clear log") then
                for i = #LOG, 1, -1 do table.remove(LOG, i) end
            end
            if FEEDBACK and FEEDBACK.led_sources then
                imgui.text("Active LED sources:")
                local any = false
                for name, src in pairs(FEEDBACK.led_sources) do
                    any = true
                    imgui.text(string.format("  [%s] rgb(%d,%d,%d) pri=%d fr=%s",
                        name, src.r, src.g, src.b, src.priority, tostring(src.frames)))
                end
                if not any then imgui.text("  (none)") end
            end
            imgui.separator()
            imgui.text("Load log:")
            for _, line in ipairs(LOG) do imgui.text(line) end
            imgui.tree_pop()
        end

        local AUDIO_D = _G.DualSenseEnhancedAudio
        if AUDIO_D and imgui.tree_node("Heal Sound Debug") then
            local ch, vh = imgui.checkbox("Force rare herb sound (100%)##heal_rare_always", AUDIO_D.heal_rare_always)
            if ch then AUDIO_D.heal_rare_always = vh end
            imgui.text_colored("Normal: 5% | Danger zone (<29% HP): 20%", 0xFFAAAAAA)
            imgui.tree_pop()
        end

        imgui.tree_pop()
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("RE4R DualSense Enhanced Edition") then return end

    local FEEDBACK    = _G.DualSenseEnhancedFeedback
    local CORE   = _G.WeaponEquipCore
    local HP     = _G.HPLed
    local AMMO   = _G.AmmoLed
    local EVENTS = _G.EventsLed
    local AUDIO  = _G.DualSenseEnhancedAudio
    local SND    = _G.DualSenseEnhancedSoundEventDiag
    local MIC    = _G.DualSenseEnhancedMicLED
    local CONFIG = _G.DualSenseEnhancedSettings
    local MON    = _G.DualSenseEnhancedMonitor
    local CAPCOM = _G.CapcomHapticsDiag
    local RADIO  = _G.DualSenseEnhancedRadio
    local GYRO   = _G.NativeGyro
    local IPC    = _G.DuaLibTriggerIpc
    local TI     = _G.TriggerIntensity
    local NATIVE = _G.NativeDualSenseFeedback

    if FEEDBACK and FEEDBACK.mod_master_enabled == false then
        if imgui.button("Enable Mod##master_switch") then pcall(FEEDBACK.set_master_enabled, true) end
        imgui.text("Mod is disabled.")
        imgui.tree_pop()
        return
    elseif FEEDBACK then
        if imgui.button("Disable Mod##master_switch") then pcall(FEEDBACK.set_master_enabled, false) end
    end

    if FEEDBACK and FEEDBACK.output_mode ~= "native" then
        set_output_native()
    end
    if UI.lightbar_mode == "native" then
        set_lightbar_mode("native")
    elseif UI.lightbar_mode == "enhanced" then
        set_lightbar_mode("enhanced")
    end

    imgui.separator()
    draw_status(FEEDBACK, NATIVE, AUDIO, GYRO, IPC, EVENTS)
    draw_global_preset()
    draw_quick_controls(HP, AMMO, EVENTS, AUDIO, GYRO, IPC, MIC)
    draw_lightbar(FEEDBACK, HP, AMMO, EVENTS)
    draw_triggers(IPC, TI)
    draw_audio(AUDIO)
    draw_enhanced_haptics(IPC)
    draw_gyro(GYRO)
    imgui.separator()
    draw_advanced(CONFIG, RADIO, IPC, MIC, AMMO, CORE)
    if not RELEASE_BUILD then
        imgui.separator()
        draw_debug(MON, SND, CAPCOM, FEEDBACK, IPC)
    end

    imgui.tree_pop()
end)
