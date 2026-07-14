local io = io
local table = table
local string = string
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local os = os

_G.DualSenseEnhancedFeedback = _G.DualSenseEnhancedFeedback or {}
local FEEDBACK = _G.DualSenseEnhancedFeedback

local PAYLOAD_CANDIDATE = "DualSenseEnhanced/payload.json"
local MAPPING_NAME = "weapon_trigger_profiles.lua"
local TRANSPORT_MODE_FILE = "DualSenseEnhanced/transport_mode.txt"

FEEDBACK.out_path    = nil
FEEDBACK.mapping     = {}
FEEDBACK.last_applied = 0
FEEDBACK.ready       = false
FEEDBACK.output_mode = FEEDBACK.output_mode or "native"
FEEDBACK.mapping_status = FEEDBACK.mapping_status or "not loaded"
FEEDBACK.mapping_error = FEEDBACK.mapping_error or "none"
FEEDBACK.mapping_path = FEEDBACK.mapping_path or nil
FEEDBACK.mapping_count = FEEDBACK.mapping_count or 0
FEEDBACK.mapping_load_attempted = false

local function write_transport_mode(mode)
    local file = io.open(TRANSPORT_MODE_FILE, "wb")
    if not file then return false end
    file:write(mode)
    file:close()
    return true
end

-- ----------------------------------------------------------------
-- LED source bus
-- Modules register themselves with a priority.
-- apply_for_weapon always picks the highest active source.
-- Usage:
--   FEEDBACK.set_led("hp",    r, g, b, 1)         -- persistent
--   FEEDBACK.set_led("event", r, g, b, 100, 24)   -- expires in 24 frames
--   FEEDBACK.clear_led("event")
-- ----------------------------------------------------------------

FEEDBACK.led_sources = FEEDBACK.led_sources or {}
FEEDBACK.hp_resume_fade_duration = 30
FEEDBACK.hp_resume_fade_remaining = 0
FEEDBACK.last_active_led_name = nil
FEEDBACK.last_hp_color = FEEDBACK.last_hp_color or nil
FEEDBACK.lightbar_brightness = tonumber(FEEDBACK.lightbar_brightness) or 1.0

local HP_LED_SOURCES = {
    hp_gradient = true,
    hp_danger = true,
}

local HP_RETURN_EVENT_SOURCES = {
    parry = true,
    finisher = true,
    hookshot = true,
    grab = true,
    damage = true,
    reload = true,
    hp_heal = true,
}

function FEEDBACK.set_led(name, r, g, b, priority, frames)
    FEEDBACK.led_sources[name] = {
        r        = r,
        g        = g,
        b        = b,
        priority = priority or 1,
        frames   = frames or nil,   -- nil = persistent
    }
    if HP_LED_SOURCES[name] and ((r or 0) > 0 or (g or 0) > 0 or (b or 0) > 0) then
        FEEDBACK.last_hp_color = {r or 0, g or 0, b or 0}
    end
end

function FEEDBACK.clear_led(name)
    FEEDBACK.led_sources[name] = nil
end

function FEEDBACK.tick_led_sources()
    for name, src in pairs(FEEDBACK.led_sources) do
        if src.frames then
            src.frames = src.frames - 1
            if src.frames <= 0 then
                FEEDBACK.led_sources[name] = nil
            end
        end
    end
end

local function get_active_led()
    local best = nil
    local best_name = nil
    for name, src in pairs(FEEDBACK.led_sources) do
        if not best or src.priority > best.priority then
            best = src
            best_name = name
        end
    end

    -- HP resume fade removed by user request: HP returns to full
    -- brightness immediately when an event (parry/damage/heal/etc.)
    -- releases the lightbar, instead of ramping 10%->100%. Left
    -- FEEDBACK.hp_resume_fade_duration/remaining and the UI slider/settings
    -- field in place but inert (never set above 0 below) rather than
    -- ripping out the persisted setting.
    FEEDBACK.last_active_led_name = best_name

    if best then
        local brightness = tonumber(FEEDBACK.lightbar_brightness) or 1.0
        if brightness < 0.0 then brightness = 0.0 end
        if brightness > 1.0 then brightness = 1.0 end
        return math.floor((best.r or 0) * brightness + 0.5),
            math.floor((best.g or 0) * brightness + 0.5),
            math.floor((best.b or 0) * brightness + 0.5),
            best_name
    end
    return nil, nil, nil, nil
end

FEEDBACK.get_active_led = get_active_led

-- Player indicator source (separate from lightbar)
FEEDBACK.indicator_source = FEEDBACK.indicator_source or nil
FEEDBACK.mic_led_source = FEEDBACK.mic_led_source or { controller = 0, mode = 2 }

function FEEDBACK.set_indicator(p1, p2, p3, p4, p5)
    FEEDBACK.indicator_source = {p1, p2, p3, p4, p5}
end

function FEEDBACK.clear_indicator()
    FEEDBACK.indicator_source = nil
end

function FEEDBACK.set_mic_led(controller, mode)
    FEEDBACK.mic_led_source = {
        controller = tonumber(controller) or 0,
        mode = tonumber(mode) or 2
    }
end

function FEEDBACK.clear_mic_led()
    FEEDBACK.set_mic_led(0, 2)
end

-- ----------------------------------------------------------------
-- Core payload machinery (unchanged)
-- ----------------------------------------------------------------

local function find_payload()
    local f = io.open(PAYLOAD_CANDIDATE, "rb")
    if f then f:close(); return PAYLOAD_CANDIDATE end
    local f2 = io.open("DualSenseEnhanced/payload.json", "rb")
    if f2 then f2:close(); return "DualSenseEnhanced/payload.json" end
    return nil
end

FEEDBACK.out_path = find_payload()
FEEDBACK.ready    = (FEEDBACK.out_path ~= nil)

local function build(tbl)
    local parts = {"{\"instructions\":["}
    for i, inst in ipairs(tbl) do
        parts[#parts+1] = "{\"type\":"..tostring(inst.type)..",\"parameters\":["
        local params = inst.parameters or {}
        for j, v in ipairs(params) do
            if type(v) == "number" then
                parts[#parts+1] = v
            elseif type(v) == "boolean" then
                parts[#parts+1] = v and "true" or "false"
            else
                parts[#parts+1] = "\""..tostring(v):gsub("\\","\\\\"):gsub("\"","\\\"").."\""
            end
            if j < #params then parts[#parts+1] = "," end
        end
        parts[#parts+1] = "]}"
        if i < #tbl then parts[#parts+1] = "," end
    end
    parts[#parts+1] = "]}"
    return table.concat(parts)
end

local function write_payload(text)
    if not FEEDBACK.out_path then return false end
    local f = io.open(FEEDBACK.out_path, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    FEEDBACK.last_applied = os.time()
    return true
end

function FEEDBACK.payload_for_target()
    return build({
        { type = 1, parameters = {0,1,7} },
        { type = 1, parameters = {0,2,13,0,3} },
        { type = 2, parameters = {0,220,28,28} },
        { type = 3, parameters = {0,false,false,false,false,false} },
        { type = 5, parameters = {0,2} }
    })
end

function FEEDBACK.payload_reset()
    return build({
        { type = 1, parameters = {0,1,0} },
        { type = 1, parameters = {0,2,0} },
        { type = 2, parameters = {0,0,0,0} },
        { type = 3, parameters = {0,false,false,false,false,false} },
        { type = 5, parameters = {0,2} }
    })
end

local function load_mapping()
    FEEDBACK.mapping = {}
    FEEDBACK.mapping_status = "loading"
    FEEDBACK.mapping_error = "none"
    FEEDBACK.mapping_path = nil
    FEEDBACK.mapping_count = 0
    FEEDBACK.mapping_load_attempted = true

    local base = FEEDBACK.out_path and FEEDBACK.out_path:match("^(.*)[/\\]payload%.json$")
    local tries = {}
    local seen = {}
    local function add(path)
        if path and not seen[path] then
            seen[path] = true
            tries[#tries + 1] = path
        end
    end

    add(base and (base.."/"..MAPPING_NAME))
    add(base and (base.."\\"..MAPPING_NAME))
    add("DualSenseEnhanced/"..MAPPING_NAME)
    add("reframework/data/DualSenseEnhanced/"..MAPPING_NAME)
    add(MAPPING_NAME)

    local errors = {}
    for _,p in ipairs(tries) do
        local fh = io.open(p, "rb")
        if fh then
            local src = fh:read("*a")
            fh:close()
            if src and src:sub(1, 3) == "\239\187\191" then
                src = src:sub(4)
            end
            local chunk, load_err = load(src, "@"..p)
            if chunk then
                local ok, ret = pcall(chunk)
                if ok and type(ret) == "table" then
                    local norm = {}
                    local count = 0
                    for k, v in pairs(ret) do
                        norm[tostring(k):lower()] = v
                        count = count + 1
                    end
                    FEEDBACK.mapping = norm
                    FEEDBACK.mapping_path = p
                    FEEDBACK.mapping_count = count
                    FEEDBACK.mapping_status = "loaded"
                    FEEDBACK.mapping_error = "none"
                    return FEEDBACK.mapping
                end
                errors[#errors + 1] = p .. ": " .. tostring(ok and ("returned " .. type(ret)) or ret)
            else
                errors[#errors + 1] = p .. ": " .. tostring(load_err or "load failed")
            end
        else
            errors[#errors + 1] = p .. ": not found"
        end
    end
    FEEDBACK.mapping_status = "failed"
    FEEDBACK.mapping_error = table.concat(errors, " | ")
    return FEEDBACK.mapping
end

local function find_mapping_for_info(info)
    if not next(FEEDBACK.mapping) and not FEEDBACK.mapping_load_attempted then
        load_mapping()
    end
    if not info then return nil end
    local name_l = info.name and tostring(info.name):lower() or nil
    local id_l   = info.id   and tostring(info.id) or nil
    local type_l = info.type and tostring(info.type):lower():gsub("%s","") or nil
    if type_l and FEEDBACK.mapping["type:"..type_l] then return FEEDBACK.mapping["type:"..type_l] end
    if type_l and FEEDBACK.mapping[type_l]           then return FEEDBACK.mapping[type_l] end
    if id_l   and FEEDBACK.mapping[id_l]             then return FEEDBACK.mapping[id_l] end
    if name_l then
        for key, v in pairs(FEEDBACK.mapping) do
            if key ~= "default" and name_l:find(key, 1, true) then return v end
        end
    end
    return FEEDBACK.mapping["default"]
end

FEEDBACK.find_mapping_for_info = find_mapping_for_info

-- ----------------------------------------------------------------
-- apply_for_weapon: triggers + LED bus + indicator
-- ----------------------------------------------------------------

function FEEDBACK.apply_for_weapon(info)
    local mapping = find_mapping_for_info(info)
    local r, g, b = get_active_led()

    if FEEDBACK.output_mode == "native" then
        local native = _G.NativeDualSenseFeedback
        if native and native.apply then
            return native.apply(
                info,
                mapping,
                r ~= nil and {r, g, b} or nil
            )
        end
        return false
    end

    if FEEDBACK.output_mode == "off" then return false end
    if not FEEDBACK.out_path then return false end

    local instructions = {}

    if mapping and mapping.instructions then
        -- Empty magazine: stiffen R2
        local src = mapping.instructions
        if info.ammo and info.ammo == 0 and info.ammoMax and info.ammoMax > 0 then
            src = {}
            for _, inst in ipairs(mapping.instructions) do
                if inst.type == 1 and inst.parameters and inst.parameters[2] == 2 then
                    table.insert(src, { type = 1, parameters = {0, 2, 1, 0, 8} })
                else
                    table.insert(src, inst)
                end
            end
        end
        -- Copy trigger instructions only (strip type=2 and type=3)
        for _, inst in ipairs(src) do
            if inst.type ~= 2 and inst.type ~= 3 then
                table.insert(instructions, inst)
            end
        end
    else
        table.insert(instructions, { type = 1, parameters = {0, 1, 0} })
        table.insert(instructions, { type = 1, parameters = {0, 2, 0} })
    end

    -- Inject LED from bus (highest priority source wins), or explicitly turn it off.
    if r then
        table.insert(instructions, { type = 2, parameters = {0, r, g, b} })
    else
        table.insert(instructions, { type = 2, parameters = {0, 0, 0, 0} })
    end

    -- Inject player indicator, or explicitly turn it off.
    local ind = FEEDBACK.indicator_source
    if ind then
        table.insert(instructions, { type = 3, parameters = {0, ind[1], ind[2], ind[3], ind[4], ind[5]} })
    else
        table.insert(instructions, { type = 3, parameters = {0, false, false, false, false, false} })
    end

    -- Inject Mic LED state through the same payload path. Mode: 0 on, 1 pulse, 2 off.
    local mic = FEEDBACK.mic_led_source or { controller = 0, mode = 2 }
    table.insert(instructions, {
        type = 5,
        parameters = {mic.controller or 0, mic.mode or 2}
    })

    if #instructions > 0 then
        write_payload(build(instructions))
    else
        write_payload(FEEDBACK.payload_reset())
    end
end

function FEEDBACK.set_output_mode(mode)
    if mode ~= "dsx" and mode ~= "native" and mode ~= "off" then
        return false
    end
    if FEEDBACK.output_mode == mode then
        write_transport_mode(mode)
        return true
    end

    if FEEDBACK.output_mode == "native" then
        local native = _G.NativeDualSenseFeedback
        if native and native.release then pcall(native.release) end
    elseif FEEDBACK.output_mode == "dsx" and FEEDBACK.out_path then
        write_payload(FEEDBACK.payload_reset())
    end

    FEEDBACK.output_mode = mode
    write_transport_mode(mode)

    if mode == "native" then
        local native = _G.NativeDualSenseFeedback
        if native and native.refresh then pcall(native.refresh) end
    elseif mode == "off" and FEEDBACK.out_path then
        write_payload(FEEDBACK.payload_reset())
    end

    if _G.WeaponEquipCore and _G.WeaponEquipCore.last_info then
        pcall(FEEDBACK.apply_for_weapon, _G.WeaponEquipCore.last_info)
    end
    return true
end

-- ----------------------------------------------------------------
-- Master mod switch
-- Disables every feedback/audio module, clears all bus state, and
-- drops output_mode to "off" so the game regains full native control.
-- External helper processes (DualsenseAudioBridge.exe, DSX_UDPClient.exe,
-- the trigger watcher) are started by the native launcher plugin and
-- cannot be terminated from this Lua sandbox; with everything disabled
-- they simply receive no more events/payload and sit idle.
-- ----------------------------------------------------------------

FEEDBACK.mod_master_enabled = FEEDBACK.mod_master_enabled == nil or FEEDBACK.mod_master_enabled
FEEDBACK._pre_disable_state = FEEDBACK._pre_disable_state or nil

local function clear_all_bus_state()
    for name in pairs(FEEDBACK.led_sources) do
        FEEDBACK.led_sources[name] = nil
    end
    if FEEDBACK.clear_indicator then pcall(FEEDBACK.clear_indicator) end
    if FEEDBACK.clear_mic_led then pcall(FEEDBACK.clear_mic_led) end
end

function FEEDBACK.set_master_enabled(enabled)
    enabled = enabled == true
    if enabled == FEEDBACK.mod_master_enabled then return FEEDBACK.mod_master_enabled end

    if not enabled then
        local HP, AMMO, EVENTS = _G.HPLed, _G.AmmoLed, _G.EventsLed
        local AUDIO, WWISE, SND, RADIO = _G.DualSenseEnhancedAudio, _G.DualSenseEnhancedWwiseAudioRouter, _G.DualSenseEnhancedSoundEventDiag, _G.DualSenseEnhancedRadio
        local MIC, GYRO, IPC = _G.DualSenseEnhancedMicLED, _G.NativeGyro, _G.DuaLibTriggerIpc

        FEEDBACK._pre_disable_state = {
            output_mode = FEEDBACK.output_mode,
            hp = HP and HP.enabled,
            ammo = AMMO and AMMO.enabled,
            events = EVENTS and EVENTS.enabled,
            audio = AUDIO and AUDIO.enabled,
            wwise = WWISE and WWISE.enabled,
            sound_diag = SND and SND.enabled,
            radio = RADIO and RADIO.enabled,
            mic = MIC and MIC.enabled,
            gyro = GYRO and GYRO.enabled,
            ipc = IPC and IPC.enabled,
            ipc_indicators = IPC and IPC.indicators_enabled,
        }

        if HP then HP.enabled = false end
        if AMMO then AMMO.enabled = false end
        if EVENTS then EVENTS.enabled = false end
        if AUDIO then AUDIO.enabled = false end
        if WWISE then WWISE.enabled = false end
        if SND then SND.enabled = false end
        if RADIO then RADIO.enabled = false end
        if MIC then
            MIC.enabled = false
            if MIC.off then pcall(MIC.off) end
        end
        if GYRO then GYRO.enabled = false end
        if IPC then
            IPC.enabled = false
            IPC.indicators_enabled = false
            if IPC.reset then pcall(IPC.reset, "master switch off") end
        end

        clear_all_bus_state()
        pcall(FEEDBACK.set_output_mode, "off")
    else
        local saved = FEEDBACK._pre_disable_state or {}
        local HP, AMMO, EVENTS = _G.HPLed, _G.AmmoLed, _G.EventsLed
        local AUDIO, WWISE, SND, RADIO = _G.DualSenseEnhancedAudio, _G.DualSenseEnhancedWwiseAudioRouter, _G.DualSenseEnhancedSoundEventDiag, _G.DualSenseEnhancedRadio
        local MIC, GYRO, IPC = _G.DualSenseEnhancedMicLED, _G.NativeGyro, _G.DuaLibTriggerIpc

        if HP then HP.enabled = saved.hp ~= false end
        if AMMO then AMMO.enabled = saved.ammo ~= false end
        if EVENTS then EVENTS.enabled = saved.events ~= false end
        if AUDIO then AUDIO.enabled = saved.audio ~= false end
        if WWISE then WWISE.enabled = saved.wwise ~= false end
        if SND then SND.enabled = saved.sound_diag == true end
        if RADIO then RADIO.enabled = saved.radio == true end
        if MIC then MIC.enabled = saved.mic ~= false end
        if GYRO then GYRO.enabled = saved.gyro == true end
        if IPC then
            IPC.enabled = saved.ipc == true
            IPC.indicators_enabled = saved.ipc_indicators == true
        end

        pcall(FEEDBACK.set_output_mode, saved.output_mode or "native")
        FEEDBACK._pre_disable_state = nil
    end

    FEEDBACK.mod_master_enabled = enabled
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("master switch", enabled and "mod enabled" or "mod disabled") end
    return FEEDBACK.mod_master_enabled
end
if _G.WeaponEquipCore and WeaponEquipCore.on_weapon_change then
    WeaponEquipCore.on_weapon_change(function(info)
        if not next(FEEDBACK.mapping) then load_mapping() end
        pcall(function() FEEDBACK.apply_for_weapon(info) end)
    end)
end

function FEEDBACK.reload_mapping()
    FEEDBACK.mapping_load_attempted = false
    return load_mapping()
end
load_mapping()
write_transport_mode(FEEDBACK.output_mode)
if FEEDBACK.output_mode == "dsx" then write_payload(FEEDBACK.payload_reset()) end

-- Tick LED source timers every frame (not tied to weapon heartbeat)
pcall(function()
    re.on_application_entry("UpdateBehavior", function()
        FEEDBACK.tick_led_sources()
        if FEEDBACK.hp_resume_fade_remaining > 0
            and HP_LED_SOURCES[FEEDBACK.last_active_led_name]
        then
            local CORE = _G.WeaponEquipCore
            local info = CORE and CORE.last_info
            if info then pcall(FEEDBACK.apply_for_weapon, info) end
            FEEDBACK.hp_resume_fade_remaining = FEEDBACK.hp_resume_fade_remaining - 1
        end
    end)
end)
