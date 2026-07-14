-- RE9 DualSense diagnostics
-- READ-ONLY: no hooks, setters, output calls, or saved settings.

local state = {
    manager = nil,
    device_manager = nil,
    sound_manager = nil,
    last_error = "none",
    events = {},
    event_counts = {},
    total_events = 0,
    hook_status = {},
    capture_started = os.clock(),
}

local function safe_call(obj, method_name, ...)
    if obj == nil then return nil end
    local args = {...}
    local value = nil
    local ok, err = pcall(function()
        value = obj:call(method_name, table.unpack(args))
    end)
    if not ok then
        state.last_error = tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_field(obj, field_name)
    if obj == nil then return nil end
    local value = nil
    local ok, err = pcall(function()
        value = obj[field_name]
        if value ~= nil then return end

        local type_def = obj:get_type_definition()
        local field = type_def and type_def:get_field(field_name) or nil
        if field ~= nil then value = field:get_data(obj) end
    end)
    if not ok then
        state.last_error = tostring(field_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_static_call(type_name_value, method_name)
    local value = nil
    local ok, err = pcall(function()
        local type_def = sdk.find_type_definition(type_name_value)
        local method = type_def and type_def:get_method(method_name) or nil
        if method ~= nil then value = method:call(nil) end
    end)
    if not ok then
        state.last_error = tostring(type_name_value) .. "." ..
            tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_static_field(type_name_value, field_name)
    local value = nil
    local ok, err = pcall(function()
        local type_def = sdk.find_type_definition(type_name_value)
        local field = type_def and type_def:get_field(field_name) or nil
        if field ~= nil then value = field:get_data(nil) end
    end)
    if not ok then
        state.last_error = tostring(type_name_value) .. "." ..
            tostring(field_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function type_name(obj)
    if obj == nil then return "nil" end
    local name = nil
    pcall(function()
        local type_def = obj:get_type_definition()
        name = type_def and type_def:get_full_name() or nil
    end)
    return name or tostring(obj)
end

local function value_text(value)
    if value == nil then return "nil" end
    if type(value) == "boolean" then return value and "true" or "false" end
    return tostring(value)
end

local function arg_u32(args, index)
    local value = nil
    pcall(function() value = tonumber(sdk.to_int64(args[index])) end)
    if value == nil then return nil end
    return value % 4294967296
end

local function arg_object(args, index)
    local value = nil
    pcall(function() value = sdk.to_managed_object(args[index]) end)
    return value
end

local function push_event(kind, detail)
    local key = kind .. " " .. tostring(detail)
    state.total_events = state.total_events + 1
    state.event_counts[key] = (state.event_counts[key] or 0) + 1
    table.insert(state.events, 1, {
        time = os.clock() - state.capture_started,
        kind = kind,
        detail = tostring(detail),
    })
    while #state.events > 40 do table.remove(state.events) end
end

local function nullable_text(value)
    if value == nil then return "nil" end

    local has_value = safe_call(value, "get_HasValue")
    if has_value == false then return "none" end
    if has_value == true then
        return value_text(safe_call(value, "get_Value"))
    end

    return value_text(value)
end

local function collection_count(collection)
    if collection == nil then return 0 end

    local count = safe_call(collection, "get_Count")
    if count ~= nil then return tonumber(count) or 0 end

    local size = nil
    pcall(function() size = collection:get_size() end)
    return tonumber(size) or 0
end

local function array_element(array, index)
    if array == nil then return nil end
    local value = nil
    pcall(function() value = array:get_element(index) end)
    return value
end

local function line(label, value)
    imgui.text(label .. ": " .. value_text(value))
end

local function refresh()
    state.last_error = "none"

    local ok, value = pcall(
        sdk.get_managed_singleton,
        "app.DeviceFeedbackManager"
    )
    state.manager = ok and value or nil

    ok, value = pcall(
        sdk.get_managed_singleton,
        "app.DeviceManager"
    )
    state.device_manager = ok and value or nil

    ok, value = pcall(
        sdk.get_managed_singleton,
        "soundlib.SoundVibrationManager"
    )
    state.sound_manager = ok and value or nil
    if state.sound_manager == nil then
        state.sound_manager = safe_static_call(
            "soundlib.SoundVibrationManager",
            "get_Instance"
        )
    end
    if state.sound_manager == nil then
        state.sound_manager = safe_static_field(
            "soundlib.SoundVibrationManager",
            "_Instance"
        )
    end
end

local function draw_assigned_device(status, index)
    if status == nil then
        line("Assigned device[" .. tostring(index) .. "]", "nil")
        return
    end

    local device = safe_call(status, "get_Device")
    if device == nil then device = safe_field(status, "_Device") end

    local label = "Assigned device[" .. tostring(index) .. "]"
    line(label, device and type_name(device) or "nil")
    if device == nil then return end

    imgui.indent()
    line("Valid", safe_call(device, "get_Valid"))
    line("Assigned", safe_call(device, "get_IsAssigned"))
    line("Device type", safe_call(device, "get_DeviceType"))
    line("Native device type", safe_call(device, "get_NativeDeviceType"))
    line("Native kind details",
        safe_call(device, "get_NativeDeviceKindDetails"))

    local native_gamepad = safe_call(device, "get_Device")
    if native_gamepad == nil then
        native_gamepad = safe_call(device, "get_NativeDevice")
    end
    line("Native gamepad",
        native_gamepad and type_name(native_gamepad) or "nil")

    local vibration_provider = safe_call(device, "get_VibrationProvider")
    line("Vibration provider",
        vibration_provider and type_name(vibration_provider) or "nil")
    if vibration_provider ~= nil then
        imgui.indent()
        line("Provider vibwav available",
            safe_call(vibration_provider, "get_VibwavVibrationAvailable"))
        line("Provider vibration-wave index",
            nullable_text(
                safe_call(vibration_provider, "get_VibrationWaveIndex")
            ))

        local dualsense_device =
            safe_call(vibration_provider, "get_DualSenseDevice")
        line("DualSense device",
            dualsense_device and type_name(dualsense_device) or "nil")
        if dualsense_device ~= nil then
            line("DualSense vibration-wave index",
                safe_call(dualsense_device, "get_VibrationWaveIndex"))
            line("Bluetooth connection",
                safe_call(dualsense_device, "get_BluetoothConnection"))
        end
        imgui.unindent()
    end

    imgui.unindent()
end

local function draw_manager(manager)
    line("Instance", manager and type_name(manager) or "not found")
    if manager == nil then return end

    line("_IsInitialized", safe_field(manager, "_IsInitialized"))
    line("_VibwavVibrationSupported",
        safe_field(manager, "_VibwavVibrationSupported"))
    line("_BnvibVibrationSupported",
        safe_field(manager, "_BnvibVibrationSupported"))
    line("_ApplicateVibration",
        safe_field(manager, "_ApplicateVibration"))
    line("_ApplicateVibrationWaveIndex",
        safe_field(manager, "_ApplicateVibrationWaveIndex"))
    line("_ApplicateAdaptiveTrigger",
        safe_field(manager, "_ApplicateAdaptiveTrigger"))
    line("_ApplicateLightBar",
        safe_field(manager, "_ApplicateLightBar"))
    line("_VibrationPlayingType",
        safe_field(manager, "_VibrationPlayingType"))
    line("_VibrationWaveIndexAssignStrategy",
        safe_field(manager, "_VibrationWaveIndexAssignStrategy"))
    line("_InitializedVibwavVibrationPort",
        safe_field(manager, "_InitializedVibwavVibrationPort"))
    line("_VibrationPowerGain",
        safe_field(manager, "_VibrationPowerGain"))

    local vibration_catalog = safe_field(manager, "_VibrationDataCatalog")
    local vibration_dict = safe_field(vibration_catalog, "_Dict")
    line("Vibration catalog entries", collection_count(vibration_dict))

    local trigger_catalog = safe_field(manager, "_AdaptiveTriggerDataCatalog")
    local trigger_dict = safe_field(trigger_catalog, "_Dict")
    line("Adaptive-trigger catalog entries", collection_count(trigger_dict))

    local requests = safe_field(manager, "_VibrationRequests")
    line("Active vibration requests", collection_count(requests))

    if imgui.tree_node("Player 0 provider##re9_ds_diag") then
        local providers = safe_field(manager, "_FeedbackProviders")
        local provider_array = safe_field(providers, "_FeedbackProviders")
        local capacity = safe_call(providers, "get_Capacity")
        line("Provider collection capacity", capacity)

        local provider = array_element(provider_array, 0)
        line("Provider", provider and type_name(provider) or "nil")

        if provider ~= nil then
            line("_VibrationEnabled",
                safe_field(provider, "_VibrationEnabled"))
            line("_VibwavVibrationAvailable",
                safe_field(provider, "_VibwavVibrationAvailable"))
            line("_VibrationWaveIndex",
                nullable_text(safe_field(provider, "_VibrationWaveIndex")))
            line("_AdaptiveTriggerEnabled",
                safe_field(provider, "_AdaptiveTriggerEnabled"))
            line("Adaptive-trigger requests",
                collection_count(safe_field(provider, "_AdaptiveTriggerRequests")))
            line("_LightBarEnabled",
                safe_field(provider, "_LightBarEnabled"))
            line("_HasLightBarColor",
                safe_field(provider, "_HasLightBarColor"))

            local device = safe_field(provider, "_Device")
            line("Merged feedback device",
                device and type_name(device) or "nil")

            if device ~= nil then
                line("Device valid", safe_call(device, "get_Valid"))
                line("Device vibwav available",
                    safe_call(device, "get_VibwavVibrationAvailable"))
                line("Device vibration-wave index",
                    nullable_text(safe_call(device, "get_VibrationWaveIndex")))

                local active_gamepad = safe_field(device, "_ActiveGamePad")
                line("Active gamepad",
                    active_gamepad and type_name(active_gamepad) or "nil")

                local devices = safe_field(device, "_Devices")
                line("Assigned feedback devices", collection_count(devices))
                local device_count = collection_count(devices)
                for i = 0, math.min(device_count, 8) - 1 do
                    draw_assigned_device(
                        safe_call(devices, "get_Item", i),
                        i
                    )
                end
            end
        end

        imgui.tree_pop()
    end
end

local function draw_sound_manager(manager)
    if not imgui.tree_node("Sound vibration manager##re9_ds_diag") then
        return
    end

    line("Instance", manager and type_name(manager) or "not found")
    if manager ~= nil then
        line("isHDVibrationPlatform",
            safe_call(manager, "get_isHDVibrationPlatform"))
        line("Playing vibration count",
            safe_field(manager, "_PlayingVibrationCount"))
        line("Warning vibration count",
            safe_field(manager, "_WarningVibrationCount"))
        line("WAV haptics entries",
            collection_count(safe_field(manager, "_VibInfoByWavList")))
        line("Definition pairs",
            collection_count(safe_field(manager, "_DefinePair")))
        line("Active vibration objects",
            collection_count(safe_field(manager, "_PlayingVibrationDict")))
    end

    imgui.tree_pop()
end

local function draw_device_manager(manager)
    if not imgui.tree_node("Device manager##re9_ds_diag") then return end

    line("Instance", manager and type_name(manager) or "not found")
    if manager ~= nil then
        line("_IsInitialized", safe_field(manager, "_IsInitialized"))
        line("_IsAvailableGamePad",
            safe_field(manager, "_IsAvailableGamePad"))
        line("_IsAvailableKeyboard",
            safe_field(manager, "_IsAvailableKeyboard"))
        line("_IsAvailableMouse",
            safe_field(manager, "_IsAvailableMouse"))

        local active_gamepad = safe_call(manager, "getActiveGamePad", 0)
        line("Player 0 active gamepad",
            active_gamepad and type_name(active_gamepad) or "nil")
        if active_gamepad ~= nil then
            imgui.indent(8)
            line("Valid", safe_call(active_gamepad, "get_Valid"))
            line("Assigned", safe_call(active_gamepad, "get_IsAssigned"))
            line("Native device type",
                safe_call(active_gamepad, "get_NativeDeviceType"))
            line("Native kind details",
                safe_call(active_gamepad, "get_NativeDeviceKindDetails"))
            line("Adaptive triggers supported",
                safe_call(active_gamepad, "get_AdaptiveTriggerSupported"))
            line("Has vibrator",
                safe_call(active_gamepad, "get_HasVibrator"))

            local native = safe_call(active_gamepad, "get_Device")
            if native == nil then
                native = safe_call(active_gamepad, "get_NativeDevice")
            end
            line("Native gamepad", native and type_name(native) or "nil")

            local provider =
                safe_call(active_gamepad, "get_VibrationProvider")
            line("Vibration provider",
                provider and type_name(provider) or "nil")
            if provider ~= nil then
                line("Vibwav available",
                    safe_call(provider, "get_VibwavVibrationAvailable"))
                line("Vibration-wave index",
                    nullable_text(
                        safe_call(provider, "get_VibrationWaveIndex")
                    ))
                local dualsense =
                    safe_call(provider, "get_DualSenseDevice")
                line("DualSense device",
                    dualsense and type_name(dualsense) or "nil")
            end
            imgui.unindent(8)
        end

        local assigned = safe_call(manager, "getAssignedDevices", 0)
        line("Player 0 assigned device count",
            collection_count(assigned))
    end

    imgui.tree_pop()
end

local function handle_hook(kind, args, meta)
    local overload = meta and
        (" params=" .. tostring(meta.param_count)) or ""
    if kind == "sound_trigger" then
        push_event("sound vibration",
            "id=" .. tostring(arg_u32(args, 3)))
    elseif kind == "manager_play_vibration" then
        push_event("manager play vibration",
            "id=" .. tostring(arg_u32(args, 4)) ..
            overload)
    elseif kind == "manager_schedule_vibration" then
        local gamepad = arg_object(args, 4)
        push_event("manager schedule vibration",
            "player=" .. tostring(arg_u32(args, 3)) ..
            " gamepad=" .. type_name(gamepad))
    elseif kind == "play_vibration" then
        push_event("play vibration",
            "id=" .. tostring(arg_u32(args, 3)))
    elseif kind == "adaptive_trigger" then
        push_event("adaptive trigger",
            "id=" .. tostring(arg_u32(args, 3)) ..
            " motors=" .. tostring(arg_u32(args, 4)))
    elseif kind == "lightbar_animator" then
        local animator = arg_object(args, 3)
        push_event("lightbar animator", type_name(animator))
    elseif kind == "gamepad_motor" then
        push_event("gamepad motor",
            "power=" .. tostring(args[3]) ..
            " motor=" .. tostring(arg_u32(args, 4)))
    elseif kind == "gamepad_adaptive" then
        push_event("gamepad adaptive trigger",
            "motor=" .. tostring(arg_u32(args, 3)))
    elseif kind == "dualsense_wave_index" then
        push_event("DualSense wave index",
            "index=" .. tostring(arg_u32(args, 3)))
    end
end

local function install_hooks(type_name_value, method_map)
    _G.RE9DualSenseInstalledHooks =
        _G.RE9DualSenseInstalledHooks or {}
    local installed = _G.RE9DualSenseInstalledHooks

    local type_def = sdk.find_type_definition(type_name_value)
    if type_def == nil then
        state.hook_status[type_name_value] = "type not found"
        return
    end

    for _, method in ipairs(type_def:get_methods() or {}) do
        local name = method:get_name()
        local kind = method_map[name]
        if kind ~= nil then
            local key = type_name_value .. "." .. name .. "." ..
                tostring(method)
            if not installed[key] then
                local hook_kind = kind
                local hook_meta = {
                    param_count = method:get_num_params(),
                }
                local ok, err = pcall(function()
                    sdk.hook(method, function(args)
                        local current = _G.RE9DualSenseDiag
                        if current and current.handle_hook then
                            pcall(
                                current.handle_hook,
                                hook_kind,
                                args,
                                hook_meta
                            )
                        end
                    end, function(retval)
                        return retval
                    end)
                end)
                if ok then
                    installed[key] = true
                    state.hook_status[key] = "installed"
                else
                    state.hook_status[key] =
                        "failed: " .. tostring(err)
                end
            else
                state.hook_status[key] = "already installed"
            end
        end
    end
end

local function draw_event_monitor()
    if not imgui.tree_node("Feedback event monitor##re9_ds_diag") then
        return
    end

    imgui.text(
        "Passive hooks only. Original methods and return values are unchanged.")
    if imgui.button("Clear capture##re9_ds_diag") then
        state.events = {}
        state.event_counts = {}
        state.total_events = 0
        state.capture_started = os.clock()
    end

    line("Captured calls", state.total_events)
    line("Recent calls shown", #state.events)

    if imgui.tree_node("Unique call counts##re9_ds_diag") then
        local keys = {}
        for key, _ in pairs(state.event_counts) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            imgui.text(key .. ": " .. tostring(state.event_counts[key]))
        end
        imgui.tree_pop()
    end

    for _, event in ipairs(state.events) do
        imgui.text(string.format(
            "%6.2fs  %s  %s",
            event.time, event.kind, event.detail
        ))
    end

    if imgui.tree_node("Hook status##re9_ds_diag") then
        local keys = {}
        for key, _ in pairs(state.hook_status) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            imgui.text(key .. ": " .. tostring(state.hook_status[key]))
        end
        imgui.tree_pop()
    end

    imgui.tree_pop()
end

state.handle_hook = handle_hook
_G.RE9DualSenseDiag = state

install_hooks("soundlib.SoundVibrationManager", {
    triggerVibration = "sound_trigger",
})
install_hooks("app.DeviceFeedbackManager", {
    playVibration = "manager_play_vibration",
    schedulePlayVibration = "manager_schedule_vibration",
})
install_hooks("app.DeviceFeedbackProvider", {
    playVibration = "play_vibration",
    setAdaptiveTrigger = "adaptive_trigger",
    set_LightBarIllumination = "lightbar_animator",
})
install_hooks("app.ManagedGamePad", {
    setVibrationPower = "gamepad_motor",
    setAdaptiveTriggerFeedback = "gamepad_adaptive",
})
install_hooks("via.hid.DualSenseDevice", {
    set_VibrationWaveIndex = "dualsense_wave_index",
})

refresh()

re.on_draw_ui(function()
    if not imgui.tree_node("RE9 DualSense Diagnostics") then return end

    imgui.text("READ-ONLY: this panel does not enable or trigger feedback.")
    if imgui.button("Refresh instances##re9_ds_diag") then refresh() end

    draw_manager(state.manager)
    draw_device_manager(state.device_manager)
    draw_sound_manager(state.sound_manager)
    draw_event_monitor()
    line("Last read error", state.last_error)

    imgui.tree_pop()
end)

log.info("[RE9 DualSense Diagnostics] Loaded read-only diagnostics.")
