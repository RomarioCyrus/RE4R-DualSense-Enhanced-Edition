local sdk = sdk
local re = re
local io = io
local os = os
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local type = type

_G.DualSenseEnhancedSoundEventDiagGeneration = (_G.DualSenseEnhancedSoundEventDiagGeneration or 0) + 1
local generation = _G.DualSenseEnhancedSoundEventDiagGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedSoundEventDiagGeneration == generation
end

local DIAG = {}
DIAG.enabled = false
DIAG.window_frames = 0
DIAG.default_window_frames = 240
DIAG.tail_window_frames = 90
DIAG.max_events_per_window = 2000
DIAG.log_path = "DualSenseEnhanced/sound_event_diag.log"
DIAG.event_log_path = "DualSenseEnhanced/sound_event_ids.log"
DIAG.hook_status = {}
DIAG.installed_hooks = 0
DIAG.last_status = "not installed"
DIAG.last_error = nil
DIAG.last_event = nil
DIAG.window_reason = "none"
DIAG.window_event_count = 0
DIAG.total_event_count = 0
DIAG.method_counts = {}
DIAG.max_events_per_method = 80
-- Footstep-haptics Stage 3 research: default on so the wider
-- switch/state/trigger method scan below actually runs. This whole tool is
-- already gated behind RELEASE_BUILD + the "Enable Wwise logging" checkbox,
-- so this doesn't add exposure beyond what's already dev-only.
DIAG.discovery_hook_patterns_enabled = true
-- Auto-correlation: watch state transitions and open labelled windows
-- automatically so one pass through each weapon action is enough to
-- identify event roles without manual log cross-referencing.
DIAG.auto_mode = false

-- State tracking for auto-correlation (Option 2). Updated once per frame.
-- Values are nil until the first frame where WeaponEquipCore has data.
local auto_prev_weapon_id = nil
local auto_prev_ammo = nil
local auto_prev_reload = false
-- Last observed ammo delta; exposed in log lines for Option 1 context.
local auto_ammo_delta = 0

-- L2 detection via via.hid.GamePad (same singleton as events_led.lua).
-- We try get_AnalogTriggerL first (float 0-1); if that method doesn't
-- exist we fall back to the digital button bitmask. Cross is confirmed
-- at 0x0020 in the RE4R pad bitmask, so L2 digital sits at 0x0400
-- (standard PS layout: Square=0x10, Cross=0x20, Circle=0x40,
-- Triangle=0x80, L1=0x100, R1=0x200, L2=0x400, R2=0x800).
local l2_gp_singleton = nil
local l2_gp_typedef   = nil
local l2_init_done    = false
local l2_analog_method = nil  -- cached working method name, or false=use button
local L2_BUTTON_BIT   = 0x0400
local L2_ANALOG_THRESHOLD = 0.15
local l2_was_held = false

local function l2_ensure_init()
    if l2_init_done then return end
    l2_init_done = true
    pcall(function()
        l2_gp_singleton = sdk.get_native_singleton("via.hid.Gamepad")
        l2_gp_typedef   = sdk.find_type_definition("via.hid.GamePad")
    end)
end

local function read_l2_held()
    l2_ensure_init()
    if not l2_gp_singleton or not l2_gp_typedef then return false end
    local ok, result = pcall(function()
        local pad = sdk.call_native_func(l2_gp_singleton, l2_gp_typedef, "getMergedDevice", 0)
        if not pad then return false end
        -- First call: probe for analog trigger method.
        if l2_analog_method == nil then
            for _, name in ipairs({"get_AnalogTriggerL", "getAnalogTriggerL"}) do
                local tok, tv = pcall(function() return pad:call(name) end)
                if tok and type(tv) == "number" then
                    l2_analog_method = name
                    break
                end
            end
            if l2_analog_method == nil then l2_analog_method = false end
        end
        if l2_analog_method then
            local v = pad:call(l2_analog_method)
            return type(v) == "number" and v > L2_ANALOG_THRESHOLD
        else
            local buttons = pad:call("get_Button")
            return buttons ~= nil and (buttons & L2_BUTTON_BIT) ~= 0
        end
    end)
    return ok and result == true
end

-- Always-on ring buffer of recent raw Wwise postRequestInfo candidates,
-- independent of whether a logging window is open. Cheap (in-memory only,
-- no file I/O) and lets begin_window() back-fill a short pre-roll into the
-- log -- needed because some Wwise events fire slightly *before* the game
-- hook that triggers begin_window() (e.g. a parry/fatal-kick stinger that
-- starts as part of the input window, not the confirmation frame), which
-- a purely forward-looking window would silently miss.
DIAG.PRE_ROLL_CAPACITY = 40
DIAG.PRE_ROLL_SECONDS = 1.5
local pre_roll = {}
local pre_roll_head = 1

local function pre_roll_record(label, event_id, arg_index)
    pre_roll[pre_roll_head] = {
        ts = os.clock(),
        label = label,
        event_id = event_id,
        arg_index = arg_index,
    }
    pre_roll_head = (pre_roll_head % DIAG.PRE_ROLL_CAPACITY) + 1
end

local hook_names = {
    "soundlib.SoundManager",
    "via.simplewwise.Driver",
}

local sound_manager_methods = {
    onEndOfEvent = true,
    postEvent = true,
    postRequestInfo = true,
}

local driver_methods = {
}

local ignored_method_names = {
    incRequestId = true,
}

local dynamic_hook_patterns = {
    "post",
    "request",
    "event",
    -- Footstep-haptics Stage 3: surface type is very likely communicated via
    -- a Wwise Switch/State/Trigger call (AK::SoundEngine::SetSwitch style),
    -- not a distinct postEvent event ID -- the same handful of footstep
    -- event IDs repeat regardless of surface in a first capture pass. None
    -- of "post"/"request"/"event" would ever match a method literally named
    -- e.g. "SetSwitch"/"PostTrigger"/"SetState", so this was never hooked.
    "switch",
    "state",
    "trigger",
}

local dynamic_hook_excluded_prefixes = {
    "get_",
    "set_",
    "add_",
    "remove_",
    -- soundlib.SoundManager's internal per-frame pump methods
    -- (updateEndOfEvent, updateState, updateGameObjectState, etc.) match the
    -- "state"/"event" discovery patterns above but fire every frame
    -- regardless of movement -- pure noise that was saturating the 800
    -- events/window cap within the first couple seconds of a capture,
    -- crowding out the real postEvent footstep data (2026-07-11).
    "update",
}

local interesting_field_patterns = {
    "event",
    "id",
    "name",
    "hash",
    "game",
    "object",
    "bank",
    "container",
    "request",
    "playing",
    "callback",
    "marker",
    "duration",
    "state",
    "switch",
    "frame",
    "count",
    "weapon",
    -- Footstep-haptics Stage 3 (per-surface variation): ch_ground_attribute
    -- and similar surface-switch fields have never been confirmed reachable
    -- from Lua. Widening the field-name scan for a "Capture Footsteps"
    -- window to catch whatever this field is actually called.
    "ground",
    "surface",
    "attribute",
    "material",
    "terrain",
    "floor",
    "footstep",
    "foot",
}

local getter_names = {
    "get_EventId",
    "get_EventID",
    "get_EventName",
    "get_EventNameTbl",
    "get_PlayingId",
    "get_PlayingID",
    "get_GameObjectId",
    "get_GameObjId",
    "get_GameObject",
    "get_CallbackType",
    "get_MarkerHash",
    "get_Label",
    "get_Frame",
    "get_Count",
    "get_Duration",
    "get_EstimatedDuration",
    -- Footstep-haptics Stage 3: speculative surface-switch getters, never
    -- confirmed to exist -- harmless no-ops (pcall'd) if the method isn't
    -- actually present on a given managed object.
    "get_SwitchId",
    "get_SwitchID",
    "get_SwitchName",
    "get_GroundAttribute",
    "get_Surface",
    "get_SurfaceType",
}

local function lower(text)
    text = tostring(text or "")
    return string.lower(text)
end

local function contains_any(text, patterns)
    local l = lower(text)
    for _, pattern in ipairs(patterns) do
        if string.find(l, pattern, 1, true) then return true end
    end
    return false
end

local function should_hook_method(type_name, method_name)
    if ignored_method_names[method_name] then return false end
    if type_name == "soundlib.SoundManager" then
        if sound_manager_methods[method_name] == true then return true end
        if not DIAG.discovery_hook_patterns_enabled then return false end
        local method_l = lower(method_name)
        for _, prefix in ipairs(dynamic_hook_excluded_prefixes) do
            if string.sub(method_l, 1, string.len(prefix)) == prefix then
                return false
            end
        end
        for _, pattern in ipairs(dynamic_hook_patterns) do
            if string.find(method_l, pattern, 1, true) then return true end
        end
        return false
    end
    if type_name == "via.simplewwise.Driver" then
        if driver_methods[method_name] == true then return true end
        if not DIAG.discovery_hook_patterns_enabled then return false end
        local method_l = lower(method_name)
        for _, prefix in ipairs(dynamic_hook_excluded_prefixes) do
            if string.sub(method_l, 1, string.len(prefix)) == prefix then
                return false
            end
        end
        for _, pattern in ipairs(dynamic_hook_patterns) do
            if string.find(method_l, pattern, 1, true) then return true end
        end
        return false
    end
    return false
end

local function current_weapon_text()
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or nil
    if not info then return "weapon=none ammo=?/?" end
    return string.format(
        "weapon=%s:%s ammo=%s/%s",
        tostring(info.id or "none"),
        tostring(info.name or "unknown"),
        tostring(info.ammo or "?"),
        tostring(info.ammoMax or "?")
    )
end

local function reload_state_text()
    local AUDIO = _G.DualSenseEnhancedAudio
    return string.format(
        "reload_session=%s grace=%s delta=%s",
        tostring(AUDIO and AUDIO.reload_session_active == true),
        tostring(AUDIO and AUDIO.reload_insert_grace or 0),
        tostring(auto_ammo_delta)
    )
end

-- Open a window for this reason. If a window with the same reason is
-- already open, extend it instead of resetting the event counter.
local function auto_begin(reason, frames)
    if not DIAG.enabled then return end
    if DIAG.window_frames > 0 and DIAG.window_reason == reason then
        DIAG.extend_window(reason, frames)
    else
        DIAG.begin_window(reason, frames)
    end
end

local function current_weapon_id_and_ammo()
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or nil
    if not info then return nil, nil end
    return tonumber(info.id), tonumber(info.ammo)
end

local function value_text(value)
    if value == nil then return "nil" end
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then
        return tostring(value)
    end
    local ok, text = pcall(tostring, value)
    if ok and text then return text end
    return "<value>"
end

local function managed_type_name(obj)
    local type_name = nil
    pcall(function()
        local t = obj and obj:get_type_definition()
        if t then type_name = t:get_full_name() or t:get_name() end
    end)
    return type_name
end

local function describe_managed_object(obj, depth)
    if not obj then return nil end
    depth = depth or 0
    local type_name = managed_type_name(obj)
    local parts = { tostring(type_name or "managed") }

    pcall(function()
        for _, getter in ipairs(getter_names) do
            local ok, value = pcall(function() return obj:call(getter) end)
            if ok and value ~= nil then
                parts[#parts + 1] = getter .. "=" .. value_text(value)
            end
        end
    end)

    if depth <= 0 then
        pcall(function()
            local t = obj:get_type_definition()
            local fields = t and t:get_fields() or {}
            local used = 0
            for _, field in ipairs(fields) do
                if used >= 18 then break end
                local name = field:get_name()
                if contains_any(name, interesting_field_patterns) then
                    local ok, value = pcall(function()
                        return field:get_data(obj)
                    end)
                    if ok then
                        used = used + 1
                        parts[#parts + 1] = tostring(name) .. "=" .. value_text(value)
                    end
                end
            end
        end)
    end

    return table.concat(parts, " ")
end

local function describe_arg(raw)
    local managed = nil
    pcall(function() managed = sdk.to_managed_object(raw) end)
    if managed then
        return describe_managed_object(managed, 0)
    end

    local int_text = nil
    pcall(function() int_text = tostring(sdk.to_int64(raw)) end)
    if int_text then return "raw=" .. int_text end
    return "raw=" .. value_text(raw)
end

-- Buffered writes: opening/closing a file handle per logged event (as this
-- used to do) is synchronous disk I/O on the hook's calling thread. With the
-- widened discovery patterns firing dozens of events/sec, that was enough
-- per-event I/O to visibly stutter/freeze the game (2026-07-11 user report).
-- Lines are now queued in memory and flushed together on the UpdateBehavior
-- tick (see flush_log_buffers below) with a single open/write/close per file
-- per flush instead of one per line.
local log_buffer = {}
local event_log_buffer = {}
local flush_tick_counter = 0

local function append_line(line)
    log_buffer[#log_buffer + 1] = line
    return true
end

local function append_event_line(line)
    event_log_buffer[#event_log_buffer + 1] = line
    return true
end

local function flush_buffer_to_file(path, buffer)
    if #buffer == 0 then return end
    local file, err = io.open(path, "ab")
    if not file then
        DIAG.last_error = tostring(err)
        DIAG.last_status = "log open failed"
        return
    end
    local ok, write_err = pcall(function()
        for i = 1, #buffer do
            file:write(buffer[i])
            file:write("\n")
        end
        file:close()
    end)
    if not ok then
        pcall(function() file:close() end)
        DIAG.last_error = tostring(write_err)
        DIAG.last_status = "log write failed"
    end
end

function DIAG.flush_log_buffers()
    if #log_buffer == 0 and #event_log_buffer == 0 then return end
    flush_buffer_to_file(DIAG.log_path, log_buffer)
    flush_buffer_to_file(DIAG.event_log_path, event_log_buffer)
    log_buffer = {}
    event_log_buffer = {}
end

local function should_log()
    return DIAG.enabled
        and DIAG.window_frames > 0
        and DIAG.window_event_count < DIAG.max_events_per_window
end

local function method_log_allowed(name)
    local key = tostring(name or "unknown")
    local count = DIAG.method_counts[key] or 0
    if count >= DIAG.max_events_per_method then
        return false
    end
    DIAG.method_counts[key] = count + 1
    return true
end

function DIAG.log(kind, name, detail)
    if not should_log() then return false end
    if kind ~= "mark" and not method_log_allowed(name) then return false end

    DIAG.window_event_count = DIAG.window_event_count + 1
    DIAG.total_event_count = DIAG.total_event_count + 1
    local line = string.format(
        "%.6f\t%s\t%s\t%s\t%s\twindow=%s\t%s",
        os.clock(),
        tostring(kind),
        tostring(name),
        current_weapon_text(),
        reload_state_text(),
        tostring(DIAG.window_reason),
        tostring(detail or "")
    )
    DIAG.last_event = line
    DIAG.last_status = "logged " .. tostring(name)
    return append_line(line)
end

function DIAG.mark(label, detail)
    if not DIAG.enabled then return end
    local saved = DIAG.window_frames
    if DIAG.window_frames <= 0 then DIAG.window_frames = 1 end
    DIAG.log("mark", label, detail)
    DIAG.window_frames = saved
end

-- Dump the ring buffer's still-recent entries (within PRE_ROLL_SECONDS of
-- now) into the event log as "preroll" lines, oldest first, so a Wwise
-- event that fired just before this window opened isn't lost.
local function flush_pre_roll()
    local now = os.clock()
    local entries = {}
    for i = 1, DIAG.PRE_ROLL_CAPACITY do
        local e = pre_roll[i]
        if e and (now - e.ts) <= DIAG.PRE_ROLL_SECONDS then
            entries[#entries + 1] = e
        end
    end
    table.sort(entries, function(a, b) return a.ts < b.ts end)
    for _, e in ipairs(entries) do
        append_event_line(string.format(
            "%.6f\tpreroll\t%s\t%s\t%s\twindow=%s\tevent_id=%s\targ=%s",
            e.ts,
            tostring(e.label),
            current_weapon_text(),
            reload_state_text(),
            tostring(DIAG.window_reason),
            value_text(e.event_id),
            tostring(e.arg_index)
        ))
    end
end

function DIAG.begin_window(reason, frames)
    if not DIAG.enabled then return end
    DIAG.window_frames = math.max(DIAG.window_frames, tonumber(frames) or DIAG.default_window_frames)
    DIAG.window_reason = tostring(reason or "manual")
    DIAG.window_event_count = 0
    DIAG.method_counts = {}
    append_line("")
    append_event_line("")
    DIAG.mark("window_begin", "frames=" .. tostring(DIAG.window_frames))
    pcall(flush_pre_roll)
end

function DIAG.extend_window(reason, frames)
    if not DIAG.enabled then return end
    DIAG.window_frames = math.max(DIAG.window_frames, tonumber(frames) or DIAG.tail_window_frames)
    DIAG.window_reason = tostring(reason or DIAG.window_reason)
    DIAG.mark("window_extend", "frames=" .. tostring(DIAG.window_frames))
end

function DIAG.end_window(reason)
    if not DIAG.enabled then return end
    DIAG.mark("window_end", tostring(reason or "end"))
    DIAG.window_frames = 0
    DIAG.window_reason = "none"
    pcall(DIAG.flush_log_buffers)
end

function DIAG.clear_log()
    log_buffer = {}
    event_log_buffer = {}
    local file, err = io.open(DIAG.log_path, "wb")
    if not file then
        DIAG.last_error = tostring(err)
        DIAG.last_status = "clear failed"
        return false
    end
    file:write("")
    file:close()
    local event_file, event_err = io.open(DIAG.event_log_path, "wb")
    if not event_file then
        DIAG.last_error = tostring(event_err)
        DIAG.last_status = "event clear failed"
        return false
    end
    event_file:write("")
    event_file:close()
    DIAG.last_error = nil
    DIAG.last_status = "log cleared"
    DIAG.total_event_count = 0
    DIAG.window_event_count = 0
    DIAG.method_counts = {}
    return true
end

local function describe_args(args)
    local parts = {}
    for index = 1, 7 do
        local raw = args[index]
        if raw ~= nil then
            parts[#parts + 1] = "a" .. tostring(index) .. "{" .. describe_arg(raw) .. "}"
        end
    end
    return table.concat(parts, " | ")
end

local function read_callback_field(obj, getter)
    local ok, value = pcall(function() return obj:call(getter) end)
    if ok and value ~= nil then return value end
    return nil
end

local function event_id_from_managed(managed)
    if not managed then return nil end
    return read_callback_field(managed, "get_EventId")
        or read_callback_field(managed, "get_EventID")
        or read_callback_field(managed, "get_EventHash")
        or read_callback_field(managed, "get_Id")
        or read_callback_field(managed, "get_ID")
end

local function event_id_from_raw(raw)
    if raw == nil then return nil end

    local managed = nil
    pcall(function() managed = sdk.to_managed_object(raw) end)
    local event_id = event_id_from_managed(managed)
    if event_id ~= nil then return event_id end

    local int_value = nil
    pcall(function() int_value = sdk.to_int64(raw) end)
    return int_value
end

local function scan_args_for_event_id(args)
    for index = 1, 7 do
        local value = event_id_from_raw(args[index])
        local numeric = tonumber(value)
        if numeric and numeric > 0 and numeric <= 4294967295 then
            return value, index
        end
    end
    return nil, nil
end

local function log_event_callback(label, args)
    if not should_log() then return end
    local managed = nil
    pcall(function() managed = sdk.to_managed_object(args[2]) end)
    if not managed then return end

    local type_name = managed_type_name(managed) or ""
    if not string.find(type_name, "EventCallbackInfo", 1, true) then return end

    local event_id = read_callback_field(managed, "get_EventId") or read_callback_field(managed, "get_EventID")
    local playing_id = read_callback_field(managed, "get_PlayingId") or read_callback_field(managed, "get_PlayingID")
    local game_obj_id = read_callback_field(managed, "get_GameObjId") or read_callback_field(managed, "get_GameObjectId")
    local callback_type = read_callback_field(managed, "get_CallbackType")
    local line = string.format(
        "%.6f\t%s\t%s\t%s\twindow=%s\tevent_id=%s\tplaying_id=%s\tgame_obj_id=%s\tcallback_type=%s",
        os.clock(),
        tostring(label),
        current_weapon_text(),
        reload_state_text(),
        tostring(DIAG.window_reason),
        value_text(event_id),
        value_text(playing_id),
        value_text(game_obj_id),
        value_text(callback_type)
    )
    append_event_line(line)
end

local function log_pre_event_candidate(label, args)
    local event_id, arg_index = scan_args_for_event_id(args)
    if not event_id then return end
    pre_roll_record(label, event_id, arg_index)
    if not should_log() then return end
    append_event_line(string.format(
        "%.6f\tcandidate\t%s\t%s\t%s\twindow=%s\tevent_id=%s\targ=%s",
        os.clock(),
        tostring(label),
        current_weapon_text(),
        reload_state_text(),
        tostring(DIAG.window_reason),
        value_text(event_id),
        tostring(arg_index)
    ))
end

local function hook_method(type_name, method)
    local method_name = method:get_name()
    local label = type_name .. "." .. tostring(method_name)
    local ok, err = pcall(function()
        sdk.hook(method, function(args)
            if not is_current_generation() then return end
            if method_name == "onEndOfEvent" then
                log_event_callback(label, args)
            else
                log_pre_event_candidate(label, args)
            end
            DIAG.log("pre", label, describe_args(args))
        end, function(retval)
            return retval
        end)
    end)
    if ok then
        DIAG.installed_hooks = DIAG.installed_hooks + 1
        DIAG.hook_status[label] = "OK"
    else
        DIAG.hook_status[label] = "ERR " .. tostring(err)
    end
end

local function install_hooks_for_type(type_name)
    local t = sdk.find_type_definition(type_name)
    if not t then
        DIAG.hook_status[type_name] = "type not found"
        return
    end

    local count = 0
    for _, method in ipairs(t:get_methods() or {}) do
        local ok_name, method_name = pcall(function() return method:get_name() end)
        if ok_name and method_name and should_hook_method(type_name, method_name) then
            count = count + 1
            hook_method(type_name, method)
        end
    end
    if count == 0 then
        DIAG.hook_status[type_name] = "no matching methods"
    else
        append_line(string.format(
            "%.6f\tinventory\t%s\t%s\t%s\twindow=%s\tmatching_methods=%s",
            os.clock(),
            tostring(type_name),
            current_weapon_text(),
            reload_state_text(),
            tostring(DIAG.window_reason),
            tostring(count)
        ))
    end
end

local hooks_installed = false

local function install_hooks()
    if hooks_installed then return end
    hooks_installed = true
    for _, type_name in ipairs(hook_names) do
        pcall(install_hooks_for_type, type_name)
    end
    DIAG.last_status = "hooks installed: " .. tostring(DIAG.installed_hooks)
    print("[DualSenseEnhancedSoundDiag] " .. DIAG.last_status)
end

pcall(install_hooks)

pcall(function()
    re.on_application_entry("UpdateBehavior", function()
        if not is_current_generation() then return end
        if not hooks_installed then pcall(install_hooks) end
        if DIAG.window_frames > 0 then
            DIAG.window_frames = DIAG.window_frames - 1
            if DIAG.window_frames == 0 then
                DIAG.mark("window_auto_close", "limit reached")
                DIAG.window_reason = "none"
                pcall(DIAG.flush_log_buffers)
            end
        end

        -- Periodic buffered flush (roughly every quarter-second at 60fps)
        -- instead of one disk open/write/close per logged event -- avoids
        -- the per-event I/O stutter this used to cause during busy capture
        -- windows (2026-07-11).
        flush_tick_counter = flush_tick_counter + 1
        if flush_tick_counter >= 15 then
            flush_tick_counter = 0
            pcall(DIAG.flush_log_buffers)
        end

        -- Option 2: auto-open labelled capture windows on state transitions.
        -- Runs every frame when enabled and auto_mode is on, cheap (no I/O).
        if DIAG.enabled and DIAG.auto_mode then
            local AUDIO = _G.DualSenseEnhancedAudio
            local reload_session = AUDIO and AUDIO.reload_session_active == true
            local weapon_id, ammo = current_weapon_id_and_ammo()

            -- L2 edge detection (aim-in / aim-out).
            local l2_held = read_l2_held()
            if l2_held and not l2_was_held then
                auto_begin("aim_in", 90)
            elseif not l2_held and l2_was_held then
                auto_begin("aim_out", 90)
            end
            l2_was_held = l2_held

            if weapon_id ~= nil then
                local delta = (ammo or 0) - (auto_prev_ammo or ammo or 0)
                auto_ammo_delta = delta

                if auto_prev_weapon_id ~= nil and weapon_id ~= auto_prev_weapon_id then
                    -- Weapon switch → draw/equip sounds
                    auto_begin("draw", 210)
                elseif not auto_prev_reload and reload_session then
                    -- Reload session opened → reload-start event
                    auto_begin("reload_start", 90)
                elseif auto_prev_reload and not reload_session then
                    -- Reload session closed → reload-finish event
                    auto_begin("reload_finish", 150)
                elseif delta > 0 then
                    -- Ammo increased within a session → per-shell insert
                    auto_begin("reload_insert", 60)
                elseif delta < 0 then
                    -- Ammo decreased → shot family
                    if (ammo or 0) == 0 then
                        auto_begin("last_shot", 90)
                    else
                        auto_begin("shot", 60)
                    end
                end

                auto_prev_weapon_id = weapon_id
                auto_prev_ammo = ammo
                auto_prev_reload = reload_session
            else
                auto_prev_weapon_id = nil
                auto_prev_ammo = nil
                auto_prev_reload = false
                auto_ammo_delta = 0
            end
        else
            l2_was_held = false
            auto_ammo_delta = 0
        end
    end)
end)

_G.DualSenseEnhancedSoundEventDiag = DIAG
