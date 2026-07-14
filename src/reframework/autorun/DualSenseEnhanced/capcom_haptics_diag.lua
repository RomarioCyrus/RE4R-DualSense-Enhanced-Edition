local io = io
local os = os
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local table = table
local string = string
local unpack_args = table.unpack or unpack

_G.CapcomHapticsDiagGeneration = (_G.CapcomHapticsDiagGeneration or 0) + 1
local generation = _G.CapcomHapticsDiagGeneration

local DIAG = {}
DIAG.enabled = true
DIAG.file_logging = true
DIAG.log_path = "DualSenseEnhanced/capcom_haptics_debug.txt"
DIAG.poll_interval = 60
DIAG.hook_status = {}
DIAG.manager = nil
DIAG.player_controller = nil
DIAG.share_device = nil
DIAG.device_system = nil
DIAG.native_gamepad = nil
DIAG.native_gamepad_type = nil
DIAG.native_gamepad_device_type = nil
DIAG.is_target_platform = nil
DIAG.pad_display_name = nil
DIAG.is_dualsense_device = nil
DIAG.device_type = nil
DIAG.manager_runtime_type = nil
DIAG.player_controller_runtime_type = nil
DIAG.last_event = "none"
DIAG.last_error = nil
DIAG.poll_count = 0
DIAG.wav_ids = {}
DIAG.wav_count = 0
DIAG.wav_batches = {}
DIAG.bus_ids = {}
DIAG.active_vibrations = {}
DIAG.trigger_counts = {}
DIAG.unique_trigger_count = 0
DIAG.joint_contact_counts = {}
DIAG.unique_joint_contact_count = 0
DIAG.gate_armed = false
DIAG.gate_active = false
DIAG.gate_duration_sec = 30
DIAG.gate_frames_left = 0
DIAG.gate_deadline = nil
DIAG.gate_status = "OFF (original PC state)"
DIAG.last_vibration_signature = nil
DIAG.mapper_label = "Shot"
DIAG.mapper_active = false
DIAG.mapper_started_at = nil
DIAG.mapper_started_epoch = nil
DIAG.mapper_trigger_counts = {}
DIAG.mapper_joint_counts = {}
DIAG.mapper_sessions = {}
DIAG.mapper_status = "idle"
DIAG.mapper_export_path = "DualSenseEnhanced/capcom_event_map.json"
DIAG.counters = {
    manager_awake = 0,
    trigger_vibration = 0,
    wav_data_added = 0,
    wave_index_registered = 0,
    post_vibration_event = 0,
    gamepad_connected = 0,
    player_start = 0,
    joint_contact = 0,
}

local poll_frames = 0

local function is_current_generation()
    return _G.CapcomHapticsDiagGeneration == generation
end

local function runtime_type_name(obj)
    if not obj then return nil end
    local name = nil
    pcall(function()
        local t = obj:get_type_definition()
        name = t and t:get_full_name() or nil
    end)
    return name
end

local function append_file(text)
    if not DIAG.file_logging then return end
    pcall(function()
        local f = io.open(DIAG.log_path, "a")
        if not f then return end
        f:write(os.date("%Y-%m-%d %H:%M:%S"), " ", text, "\n")
        f:close()
    end)
end

local function log(name, detail)
    local text = tostring(name or "haptics")
    if detail ~= nil and tostring(detail) ~= "" then
        text = text .. ": " .. tostring(detail)
    end
    DIAG.last_event = text
    print("[CapcomHapticsDiag] " .. text)
    append_file(text)
    local mon = _G.DualSenseEnhancedMonitor
    if mon and mon.log then
        mon.log("Capcom haptics", text)
    end
end

local function json_escape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    return "\"" .. value .. "\""
end

local function sorted_count_entries(counts, key_name)
    local entries = {}
    for key, count in pairs(counts or {}) do
        entries[#entries + 1] = {
            key = tostring(key),
            count = tonumber(count) or 0,
        }
    end
    table.sort(entries, function(a, b)
        if a.count == b.count then return a.key < b.key end
        return a.count > b.count
    end)
    return entries
end

local function encode_count_entries(entries, key_name, indent)
    indent = indent or ""
    local child = indent .. "  "
    local out = {"[\n"}
    for i, entry in ipairs(entries or {}) do
        out[#out + 1] = child .. "{"
        out[#out + 1] = json_escape(key_name) .. ":" ..
            json_escape(entry.key) .. ","
        out[#out + 1] = json_escape("count") .. ":" ..
            tostring(entry.count) .. "}"
        if i < #entries then out[#out + 1] = "," end
        out[#out + 1] = "\n"
    end
    out[#out + 1] = indent .. "]"
    return table.concat(out)
end

local function encode_mapper_sessions(sessions)
    local out = {"{\n  \"version\":1,\n  \"sessions\":[\n"}
    for i, session in ipairs(sessions or {}) do
        out[#out + 1] = "    {\n"
        out[#out + 1] = "      \"label\":" ..
            json_escape(session.label) .. ",\n"
        out[#out + 1] = "      \"started_at\":" ..
            json_escape(session.started_at) .. ",\n"
        out[#out + 1] = "      \"stopped_at\":" ..
            json_escape(session.stopped_at) .. ",\n"
        out[#out + 1] = "      \"duration_sec\":" ..
            tostring(session.duration_sec or 0) .. ",\n"
        out[#out + 1] = "      \"controller\":" ..
            json_escape(session.controller) .. ",\n"
        out[#out + 1] = "      \"trigger_ids\":" ..
            encode_count_entries(session.trigger_ids, "id", "      ") .. ",\n"
        out[#out + 1] = "      \"joint_contacts\":" ..
            encode_count_entries(session.joint_contacts, "event_trigger", "      ") ..
            "\n    }"
        if i < #sessions then out[#out + 1] = "," end
        out[#out + 1] = "\n"
    end
    out[#out + 1] = "  ]\n}\n"
    return table.concat(out)
end

local function safe_call(obj, method_name, ...)
    if not obj then return nil end
    local args = {...}
    local value = nil
    local ok, err = pcall(function()
        value = obj:call(method_name, unpack_args(args))
    end)
    if not ok then
        DIAG.last_error = tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_field(obj, field_name)
    if not obj then return nil end
    local value = nil
    pcall(function()
        value = obj[field_name]
        if value ~= nil then return end
        local t = obj:get_type_definition()
        local field = t and t:get_field(field_name) or nil
        if field then value = field:get_data(obj) end
    end)
    return value
end

local arg_object

local function sequence_elements(sequence, limit)
    local result = {}
    if not sequence then return result end
    limit = limit or 256

    local array_size = nil
    pcall(function() array_size = tonumber(sequence:get_size()) end)
    if array_size ~= nil then
        if array_size > limit then array_size = limit end
        for i = 0, array_size - 1 do
            local value = nil
            pcall(function() value = sequence:get_element(i) end)
            if value ~= nil then result[#result + 1] = value end
        end
        return result
    end

    local direct = nil
    pcall(function() direct = sequence:get_elements() end)
    if type(direct) == "table" then
        for _, value in pairs(direct) do
            if #result >= limit then break end
            result[#result + 1] = value
        end
        return result
    end

    local count = safe_call(sequence, "get_Count")
    if count == nil then count = safe_call(sequence, "get_Length") end
    count = tonumber(count) or 0
    if count > limit then count = limit end
    for i = 0, count - 1 do
        local value = safe_call(sequence, "get_Item", i)
        if value == nil then value = safe_call(sequence, "GetValue", i) end
        if value ~= nil then result[#result + 1] = value end
    end
    return result
end

local function arg_sequence(args, index)
    local raw = args[index]
    if #sequence_elements(raw, 1) > 0 then return raw end
    local managed = arg_object(args, index)
    if managed then return managed end
    return raw
end

local function read_number_field(obj, field_name)
    local value = safe_field(obj, field_name)
    return tonumber(value)
end

local function collect_wav_ids(sequence)
    local ids = {}
    local seen = {}
    for _, item in ipairs(sequence_elements(sequence, 4096)) do
        local wave_id = safe_call(item, "get_WaveId")
        if wave_id == nil then wave_id = safe_field(item, "_WaveId") end
        wave_id = tonumber(wave_id)
        if wave_id and not seen[wave_id] then
            seen[wave_id] = true
            ids[#ids + 1] = wave_id
        end
    end
    table.sort(ids)
    return ids
end

local function inspect_wav_argument(args)
    local snapshots = {}
    for index = 3, 4 do
        local raw = args[index]
        local managed = arg_object(args, index)
        local sequence = managed or raw
        local elements = sequence_elements(sequence, 64)
        local sample = {}
        for i = 1, math.min(#elements, 4) do
            local item = elements[i]
            local getter = safe_call(item, "get_WaveId")
            local field = safe_field(item, "_WaveId")
            sample[#sample + 1] = string.format(
                "%d(type=%s getter=%s field=%s)",
                i, tostring(runtime_type_name(item)),
                tostring(getter), tostring(field))
        end
        snapshots[#snapshots + 1] = {
            index = index,
            raw_type = type(raw),
            raw_value = tostring(raw),
            managed_type = runtime_type_name(managed),
            element_count = #elements,
            array_size = (function()
                local value = nil
                pcall(function() value = managed:get_size() end)
                return tonumber(value)
            end)(),
            sample = table.concat(sample, ";"),
            ids = collect_wav_ids(sequence),
        }
    end
    return snapshots
end

local function collect_bus_ids(sequence)
    local ids = {}
    for _, value in ipairs(sequence_elements(sequence, 64)) do
        local id = tonumber(value)
        if id then ids[#ids + 1] = id end
    end
    return ids
end

local function collect_vibration_records(sequence)
    local records = {}
    for _, item in ipairs(sequence_elements(sequence, 64)) do
        records[#records + 1] = {
            trigger_id = read_number_field(item, "VibTrgId"),
            request_id = read_number_field(item, "ReqId"),
            pad_index = read_number_field(item, "PadIdx"),
            is_hd = safe_field(item, "IsHD"),
            is_legacy = safe_field(item, "IsLegacy"),
            playing = safe_field(item, "Playing"),
            left_time = read_number_field(item, "LeftTimeSec"),
            power_l = read_number_field(item, "PowerL"),
            power_r = read_number_field(item, "PowerR"),
            volume = read_number_field(item, "Volume"),
            has_audio_source = safe_field(item, "VibAudioSource") ~= nil,
        }
    end
    return records
end

local function vibration_signature(records)
    local parts = {}
    for i, v in ipairs(records or {}) do
        parts[#parts + 1] = table.concat({
            tostring(i), tostring(v.trigger_id), tostring(v.request_id),
            tostring(v.pad_index), tostring(v.is_hd), tostring(v.is_legacy),
            tostring(v.playing), tostring(v.left_time), tostring(v.power_l),
            tostring(v.power_r), tostring(v.volume),
            tostring(v.has_audio_source)
        }, "/")
    end
    return table.concat(parts, "|")
end

local function log_vibration_records(records)
    if #(records or {}) == 0 then return end
    for i, v in ipairs(records) do
        log("active vibration",
            "index=" .. tostring(i) ..
            " trigger=" .. tostring(v.trigger_id) ..
            " request=" .. tostring(v.request_id) ..
            " pad=" .. tostring(v.pad_index) ..
            " HD=" .. tostring(v.is_hd) ..
            " legacy=" .. tostring(v.is_legacy) ..
            " playing=" .. tostring(v.playing) ..
            " time=" .. tostring(v.left_time) ..
            " L=" .. tostring(v.power_l) ..
            " R=" .. tostring(v.power_r) ..
            " volume=" .. tostring(v.volume) ..
            " audio=" .. tostring(v.has_audio_source))
    end
end

local function safe_static_call(type_name, method_name)
    local value = nil
    local ok, err = pcall(function()
        local t = sdk.find_type_definition(type_name)
        local method = t and t:get_method(method_name) or nil
        if method then value = method:call(nil) end
    end)
    if not ok then
        DIAG.last_error = tostring(type_name) .. "." .. tostring(method_name) ..
            ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_static_field(type_name, field_name)
    local value = nil
    pcall(function()
        local t = sdk.find_type_definition(type_name)
        local field = t and t:get_field(field_name) or nil
        if field then value = field:get_data(nil) end
    end)
    return value
end

local function set_target_platform(value)
    local requested = value == true
    local ok, err = pcall(function()
        local t = sdk.find_type_definition("soundlib.SoundVibrationManager")
        if not t then error("SoundVibrationManager type not found") end

        local setter = t:get_method("set_IsTargetPlatform")
        if setter then
            setter:call(nil, requested)
        else
            local field = t:get_field("<IsTargetPlatform>k__BackingField")
            if not field then error("IsTargetPlatform field not found") end
            field:set_data(nil, requested)
        end
    end)
    if not ok then
        DIAG.last_error = "set_IsTargetPlatform: " .. tostring(err)
        return false
    end

    local actual = safe_static_call(
        "soundlib.SoundVibrationManager", "get_IsTargetPlatform")
    DIAG.is_target_platform = actual
    if actual ~= requested then
        DIAG.last_error = "set_IsTargetPlatform verification failed"
        return false
    end
    return true
end

function DIAG.enable_gate_test()
    if not DIAG.gate_armed then
        DIAG.gate_status = "BLOCKED: arm the test first"
        return false
    end
    if not set_target_platform(true) then
        DIAG.gate_status = "FAILED: " .. tostring(DIAG.last_error)
        return false
    end
    DIAG.gate_active = true
    local duration = math.max(10, tonumber(DIAG.gate_duration_sec) or 30)
    DIAG.gate_deadline = os.time() + duration
    DIAG.gate_frames_left = duration * 60
    DIAG.gate_status = "ACTIVE: temporary IsTargetPlatform=true"
    _G.CapcomHapticsGateOwned = true
    log("EXPERIMENTAL GATE ENABLED",
        "auto-off=" .. tostring(DIAG.gate_duration_sec) .. " sec")
    return true
end

function DIAG.disable_gate_test(reason)
    local restored = set_target_platform(false)
    DIAG.gate_active = false
    DIAG.gate_frames_left = 0
    DIAG.gate_deadline = nil
    DIAG.gate_armed = false
    _G.CapcomHapticsGateOwned = nil
    if restored then
        DIAG.gate_status = "OFF: " .. tostring(reason or "manual")
        log("experimental gate disabled", tostring(reason or "manual"))
    else
        DIAG.gate_status = "RESTORE FAILED: " .. tostring(DIAG.last_error)
    end
    return restored
end

function DIAG.mapper_start(label)
    if DIAG.gate_active then
        DIAG.disable_gate_test("event mapper safety")
    end
    DIAG.mapper_label = tostring(label or DIAG.mapper_label or "Unnamed")
    if DIAG.mapper_label == "" then DIAG.mapper_label = "Unnamed" end
    DIAG.mapper_trigger_counts = {}
    DIAG.mapper_joint_counts = {}
    DIAG.mapper_started_epoch = os.time()
    DIAG.mapper_started_at = os.date("%Y-%m-%d %H:%M:%S")
    DIAG.mapper_active = true
    DIAG.mapper_status = "CAPTURING: " .. DIAG.mapper_label
    log("event mapper started", DIAG.mapper_label)
end

function DIAG.mapper_stop()
    if not DIAG.mapper_active then
        DIAG.mapper_status = "not capturing"
        return false
    end
    local session = {
        label = DIAG.mapper_label,
        started_at = DIAG.mapper_started_at,
        stopped_at = os.date("%Y-%m-%d %H:%M:%S"),
        duration_sec = math.max(
            0, os.time() - (DIAG.mapper_started_epoch or os.time())),
        controller = DIAG.native_gamepad_type or "unknown",
        trigger_ids = sorted_count_entries(DIAG.mapper_trigger_counts, "id"),
        joint_contacts = sorted_count_entries(
            DIAG.mapper_joint_counts, "event_trigger"),
    }
    DIAG.mapper_sessions[#DIAG.mapper_sessions + 1] = session
    DIAG.mapper_active = false
    DIAG.mapper_status = "saved session: " .. session.label
    log("event mapper stopped",
        session.label .. " triggers=" .. tostring(#session.trigger_ids) ..
        " joints=" .. tostring(#session.joint_contacts))
    return true
end

function DIAG.mapper_clear_sessions()
    DIAG.mapper_sessions = {}
    DIAG.mapper_status = "sessions cleared"
end

function DIAG.mapper_export()
    local ok, err = pcall(function()
        local f = io.open(DIAG.mapper_export_path, "w")
        if not f then error("cannot open export path") end
        f:write(encode_mapper_sessions(DIAG.mapper_sessions))
        f:close()
    end)
    if ok then
        DIAG.mapper_status = "exported: " .. DIAG.mapper_export_path
        log("event mapper exported",
            tostring(#DIAG.mapper_sessions) .. " sessions")
        return true
    end
    DIAG.mapper_status = "export failed: " .. tostring(err)
    DIAG.last_error = DIAG.mapper_status
    return false
end

arg_object = function(args, index)
    local obj = nil
    pcall(function() obj = sdk.to_managed_object(args[index]) end)
    return obj
end

local function arg_u32(args, index)
    local value = nil
    pcall(function()
        value = tonumber(sdk.to_int64(args[index]))
    end)
    return value
end

local function set_manager(obj, source)
    if not obj then return end
    DIAG.manager = obj
    DIAG.manager_runtime_type = runtime_type_name(obj)
    if source then
        log("manager captured", tostring(source) .. " / " .. tostring(DIAG.manager_runtime_type))
    end
end

local function set_player_controller(obj, source)
    if not obj then return end
    DIAG.player_controller = obj
    DIAG.player_controller_runtime_type = runtime_type_name(obj)
    if source then
        log("PlayerHapticsController captured",
            tostring(source) .. " / " .. tostring(DIAG.player_controller_runtime_type))
    end
end

function DIAG.refresh()
    if not DIAG.enabled then return end
    DIAG.poll_count = DIAG.poll_count + 1
    DIAG.last_error = nil

    if not DIAG.manager then
        local manager = safe_static_call(
            "soundlib.SoundVibrationManager", "get_Instance")
        pcall(function()
            if not manager then
                manager = sdk.get_managed_singleton(
                    "soundlib.SoundVibrationManager")
            end
        end)
        if manager then set_manager(manager, nil) end
    end

    if not DIAG.share_device then
        pcall(function()
            DIAG.share_device = sdk.get_managed_singleton("share.hid.Device")
        end)
        if runtime_type_name(DIAG.share_device) ~= "share.hid.Device" then
            DIAG.share_device = nil
        end
    end

    if not DIAG.device_system then
        DIAG.device_system = safe_static_call(
            "AppSingleton`1<share.hid.DeviceSystem>", "get_Instance")
    end
    if DIAG.device_system then
        DIAG.native_gamepad = safe_call(
            DIAG.device_system, "get_LastInputGamePadDevice")
        DIAG.native_gamepad_type = runtime_type_name(DIAG.native_gamepad)
        local device_type = safe_call(DIAG.native_gamepad, "get_DeviceType")
        if device_type ~= nil then
            DIAG.native_gamepad_device_type = tostring(device_type)
        end
    end

    local manager = DIAG.manager
    local target = safe_static_call(
        "soundlib.SoundVibrationManager", "get_IsTargetPlatform")
    if target == nil then
        target = safe_static_field(
            "soundlib.SoundVibrationManager",
            "<IsTargetPlatform>k__BackingField")
    end
    DIAG.is_target_platform = target

    local pad_name = safe_static_call(
        "soundlib.SoundVibrationManager", "get_PadDisplayName")
    if pad_name == nil then
        pad_name = safe_static_field(
            "soundlib.SoundVibrationManager",
            "<PadDisplayName>k__BackingField")
    end
    if pad_name ~= nil then DIAG.pad_display_name = tostring(pad_name) end

    local device = DIAG.share_device
    if device then
        DIAG.is_dualsense_device = safe_call(device, "get_IsDualSenseDevice")
        local dtype = safe_call(device, "get_DeviceType")
        if dtype ~= nil then DIAG.device_type = tostring(dtype) end
    end

    if manager then
        local wav_list = safe_field(manager, "_SoundVibInfoByWavList")
        DIAG.wav_ids = collect_wav_ids(wav_list)
        DIAG.wav_count = #DIAG.wav_ids
        DIAG.bus_ids = collect_bus_ids(safe_field(manager, "_BusIdTbl"))
        DIAG.active_vibrations = collect_vibration_records(
            safe_field(manager, "_VibrationInfoList"))
        local signature = vibration_signature(DIAG.active_vibrations)
        if DIAG.gate_active and signature ~= DIAG.last_vibration_signature then
            DIAG.last_vibration_signature = signature
            log_vibration_records(DIAG.active_vibrations)
        end
    end

    if DIAG.player_controller then
        local vibration_manager = safe_field(DIAG.player_controller, "_RefVibrationManager")
        if vibration_manager and not DIAG.manager then
            set_manager(vibration_manager, nil)
        end
    end
end

function DIAG.handle_hook(kind, args)
    local current = _G.CapcomHapticsDiag
    if not current or not current.enabled then return end

    if kind == "manager_awake" then
        current.counters.manager_awake = current.counters.manager_awake + 1
        set_manager(arg_object(args, 2), "awake")
        return
    end

    if kind == "trigger_vibration" then
        current.counters.trigger_vibration = current.counters.trigger_vibration + 1
        local trigger_id = arg_u32(args, 3)
        local key = trigger_id or "unknown"
        local previous = current.trigger_counts[key] or 0
        current.trigger_counts[key] = previous + 1
        if current.mapper_active then
            current.mapper_trigger_counts[key] =
                (current.mapper_trigger_counts[key] or 0) + 1
        end
        if previous == 0 then
            current.unique_trigger_count = current.unique_trigger_count + 1
            log("new triggerVibration", "id=" .. tostring(trigger_id))
        end
        return
    end

    if kind == "wav_data_added" then
        current.counters.wav_data_added = current.counters.wav_data_added + 1
        local snapshots = inspect_wav_argument(args)
        current.wav_batches[#current.wav_batches + 1] = snapshots
        for _, snapshot in ipairs(snapshots) do
            log("addVibByWavData raw",
                "call=" .. tostring(current.counters.wav_data_added) ..
                " arg=" .. tostring(snapshot.index) ..
                " rawType=" .. tostring(snapshot.raw_type) ..
                " managedType=" .. tostring(snapshot.managed_type) ..
                " elements=" .. tostring(snapshot.element_count) ..
                " ids=" .. table.concat(snapshot.ids, ",") ..
                " sample=" .. tostring(snapshot.sample))
        end
        return
    end

    if kind == "wave_index_registered" then
        current.counters.wave_index_registered = current.counters.wave_index_registered + 1
        log("registerVibrationWaveIndex",
            "call=" .. tostring(current.counters.wave_index_registered))
        return
    end

    if kind == "post_vibration_event" then
        current.counters.post_vibration_event = current.counters.post_vibration_event + 1
        log("onPostVibrationEvent",
            "call=" .. tostring(current.counters.post_vibration_event))
        return
    end

    if kind == "gamepad_connected" then
        current.counters.gamepad_connected = current.counters.gamepad_connected + 1
        local device = arg_object(args, 3)
        log("gamepad connected", runtime_type_name(device) or "unknown")
        return
    end

    if kind == "player_start" then
        current.counters.player_start = current.counters.player_start + 1
        set_player_controller(arg_object(args, 2), "start")
        return
    end

    if kind == "joint_contact" then
        current.counters.joint_contact = current.counters.joint_contact + 1
        local request = arg_object(args, 3)
        local event_id = safe_call(request, "get_EventId")
        local trigger_id = safe_call(request, "get_TriggerId")
        local key = tostring(event_id) .. "/" .. tostring(trigger_id)
        local previous = current.joint_contact_counts[key] or 0
        current.joint_contact_counts[key] = previous + 1
        if current.mapper_active then
            current.mapper_joint_counts[key] =
                (current.mapper_joint_counts[key] or 0) + 1
        end
        if previous == 0 then
            current.unique_joint_contact_count =
                current.unique_joint_contact_count + 1
            log("new joint contact",
                "event=" .. tostring(event_id) ..
                " trigger=" .. tostring(trigger_id))
        end
    end
end

local function install_hooks(type_name, method_map)
    _G.CapcomHapticsInstalledHooks = _G.CapcomHapticsInstalledHooks or {}
    local installed = _G.CapcomHapticsInstalledHooks

    local tdef = sdk.find_type_definition(type_name)
    if not tdef then
        DIAG.hook_status[type_name] = "type not found"
        return
    end

    local found = 0
    local methods = tdef:get_methods()
    for _, method in ipairs(methods or {}) do
        local method_name = method:get_name()
        local kind = method_map[method_name]
        if kind then
            found = found + 1
            local key = type_name .. "." .. tostring(method_name)
            if not installed[key] then
                local ok, err = pcall(function()
                    sdk.hook(method, function(args)
                        local current = _G.CapcomHapticsDiag
                        if current and current.handle_hook then
                            pcall(current.handle_hook, kind, args)
                        end
                    end, function(retval)
                        return retval
                    end)
                end)
                if ok then
                    installed[key] = true
                    DIAG.hook_status[key] = "installed"
                else
                    DIAG.hook_status[key] = "failed: " .. tostring(err)
                end
            else
                DIAG.hook_status[key] = "already installed"
            end
        end
    end

    if found == 0 then
        DIAG.hook_status[type_name] = "methods not found"
    end
end

_G.CapcomHapticsDiag = DIAG

if _G.CapcomHapticsGateOwned then
    DIAG.disable_gate_test("script reload safety restore")
end

install_hooks("soundlib.SoundVibrationManager", {
    awake = "manager_awake",
    triggerVibration = "trigger_vibration",
    addVibByWavData = "wav_data_added",
    registerVibrationWaveIndex = "wave_index_registered",
    onPostVibrationEvent = "post_vibration_event",
    onGamePadConnectedEvent = "gamepad_connected",
})

install_hooks("chainsaw.PlayerHapticsController", {
    start = "player_start",
    onJointContactTrigger = "joint_contact",
})

re.on_application_entry("UpdateBehavior", function()
    if not is_current_generation() then return end

    if DIAG.gate_active then
        local seconds_left = math.max(
            0, (DIAG.gate_deadline or os.time()) - os.time())
        DIAG.gate_frames_left = seconds_left * 60
        if seconds_left <= 0 then
            DIAG.disable_gate_test("automatic timeout")
        end
    end

    poll_frames = poll_frames + 1
    if poll_frames < DIAG.poll_interval then return end
    poll_frames = 0
    pcall(DIAG.refresh)
end)

pcall(DIAG.refresh)
log("diagnostic loaded", "read-only; no haptics state is modified")
