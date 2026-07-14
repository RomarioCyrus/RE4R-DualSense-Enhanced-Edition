local sdk = sdk
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local math = math

_G.NativeDualSenseFeedback = _G.NativeDualSenseFeedback or {}
local NATIVE = _G.NativeDualSenseFeedback

-- Preserve device capture and lightbar ownership across Reset Scripts.
-- The underlying RE Engine device object is still valid; re-acquiring it
-- takes 2-3 s on cold start, so keep it if already captured.
-- poll_game_state / device_update pre-hook will correct stale refs quickly.
NATIVE.available = NATIVE.available == true
if not NATIVE.available then
    NATIVE.device = nil
    NATIVE.native_device = nil
    NATIVE.device_type = "nil"
    NATIVE.last_status = "not initialized"
end
NATIVE.last_error = "none"
NATIVE.apply_count = NATIVE.apply_count or 0
NATIVE.last_info = nil
NATIVE.last_mapping = nil
NATIVE.last_led = nil
NATIVE.frame_interval = 3
NATIVE.lightbar_enabled = NATIVE.lightbar_enabled ~= false
NATIVE.triggers_enabled = false
NATIVE.triggers_supported = false
NATIVE.lightbar_apply_count = NATIVE.lightbar_apply_count or 0
NATIVE.blocked_game_lightbar_calls =
    NATIVE.blocked_game_lightbar_calls or 0
-- Preserve ownership + blackout flags so lightbar stays on after Reset Scripts.
-- device_update_post_hook will re-enforce cached_color every frame.
NATIVE.owns_lightbar = NATIVE.owns_lightbar == true
NATIVE.loading_blackout = false  -- never mid-load when scripts reset
NATIVE.death_blackout = NATIVE.death_blackout == true
NATIVE.internal_lightbar_write = false
NATIVE.test_led_frames = 0
-- Keep last_written_color / cached_color so post-update hook keeps enforcing
-- the correct color without waiting for the next apply_lightbar call.
-- (nil = no-op, non-nil = continued enforcement — both are safe to preserve)
NATIVE.enforce_count = NATIVE.enforce_count or 0
NATIVE.adaptive_events = NATIVE.adaptive_events or {}
NATIVE.adaptive_counts = NATIVE.adaptive_counts or {}
NATIVE.adaptive_total = NATIVE.adaptive_total or 0
NATIVE.adaptive_hook_status = NATIVE.adaptive_hook_status or {}
NATIVE.probe_risk_ack = false
NATIVE.probe_active = false
NATIVE.probe_frames = 0
NATIVE.probe_status = NATIVE.probe_status or "idle"
NATIVE.probe_error = NATIVE.probe_error or "none"
NATIVE.player_manager = NATIVE.player_manager or nil
NATIVE.player_manager_status =
    NATIVE.player_manager_status or "not captured"
-- Opt-in diagnostic: logs Capcom's own set_LightBarColor calls (color +
-- timestamp) to DualSenseEnhanced/native_lightbar_debug.txt whenever they are not
-- blocked. Used to empirically find the exact moment Capcom switches from
-- boot/menu blue to a gameplay color, so a real hook for "actual gameplay
-- control start" (not load-press) can be found instead of guessed at.
NATIVE.capcom_lightbar_diag = NATIVE.capcom_lightbar_diag == true
NATIVE.capcom_lightbar_log_count = NATIVE.capcom_lightbar_log_count or 0

local frame = 0
local device_retry_frames = 0
-- Every frame while not yet available: refresh_device() is cheap, and the
-- remaining delay is dominated by share.hid.DeviceSystem's own native-
-- DualSense enumeration time, not by how often we ask -- this just removes
-- our own polling cadence as a contributor to that delay.
local DEVICE_RETRY_INTERVAL = 1

local function safe_call(obj, method_name, ...)
    if not obj then return nil end
    local args = {...}
    local value = nil
    local ok, err = pcall(function()
        value = obj:call(method_name, table.unpack(args))
    end)
    if not ok then
        NATIVE.last_error = tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function safe_static_call(type_name, method_name)
    local value = nil
    local ok, err = pcall(function()
        local t = sdk.find_type_definition(type_name)
        local method = t and t:get_method(method_name) or nil
        if method then value = method:call(nil) end
    end)
    if not ok then
        NATIVE.last_error = tostring(type_name) .. "." ..
            tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function runtime_type_name(obj)
    if not obj then return "nil" end
    local value = nil
    pcall(function()
        local t = obj:get_type_definition()
        value = t and t:get_full_name() or nil
    end)
    return value or tostring(obj)
end

local function arg_object(args, index)
    local value = nil
    pcall(function() value = sdk.to_managed_object(args[index]) end)
    return value
end

-- via.Color (and similar hook arguments like trigger-effect param structs)
-- are value types passed by pointer, not managed reference objects, so
-- sdk.to_managed_object on them returns nil. Use sdk.to_valuetype instead.
local function arg_valuetype(args, index, type_name)
    local value = nil
    local ok, err = pcall(function() value = sdk.to_valuetype(args[index], type_name) end)
    if not ok then
        NATIVE.last_error = "arg_valuetype(" .. tostring(type_name) .. "): " .. tostring(err)
    end
    return value
end

local function arg_int(args, index)
    local value = nil
    pcall(function() value = tonumber(sdk.to_int64(args[index])) end)
    return value
end

local function arg_float(args, index)
    local value = nil
    pcall(function() value = tonumber(sdk.to_float(args[index])) end)
    return value
end

local function fmt_float(value)
    if value == nil then return "nil" end
    return string.format("%.3f", value)
end

local function push_adaptive_event(kind, detail)
    local key = kind .. " " .. detail
    NATIVE.adaptive_counts[key] =
        (NATIVE.adaptive_counts[key] or 0) + 1
    NATIVE.adaptive_total = NATIVE.adaptive_total + 1
    table.insert(NATIVE.adaptive_events, 1, {
        kind = kind,
        detail = detail,
    })
    while #NATIVE.adaptive_events > 30 do
        table.remove(NATIVE.adaptive_events)
    end
end

local function clamp(v, low, high)
    v = tonumber(v) or low
    if v < low then return low end
    if v > high then return high end
    return v
end

local function refresh_device()
    local device_system = safe_static_call(
        "AppSingleton`1<share.hid.DeviceSystem>",
        "get_Instance"
    )
    local device = safe_call(device_system, "getGamePadDevice", 0)
    if not device then device = safe_call(device_system, "getDevice", 0) end

    NATIVE.device = device
    NATIVE.native_device =
        device and safe_call(device, "get_NativeDevice") or nil
    NATIVE.device_type = runtime_type_name(NATIVE.native_device)
    NATIVE.available = device ~= nil
        and safe_call(device, "get_IsDualSenseDevice") == true
        and NATIVE.device_type:find("DualSense", 1, true) ~= nil

    if NATIVE.available then
        NATIVE.last_status = "native DualSense captured"
    elseif device then
        NATIVE.last_status = "share.hid.Device is not a native DualSense"
    else
        NATIVE.last_status = "share.hid.Device not found"
    end
    return NATIVE.available
end

local function get_player_manager()
    if NATIVE.player_manager then
        return NATIVE.player_manager
    end

    local manager = nil
    pcall(function()
        manager = sdk.get_managed_singleton("chainsaw.PlayerManager")
    end)
    if manager then
        NATIVE.player_manager = manager
        NATIVE.player_manager_status =
            "captured via managed singleton: " .. runtime_type_name(manager)
    end
    return manager
end

local function player_manager_capture_pre(args)
    local current = _G.NativeDualSenseFeedback
    if not current then
        return sdk.PreHookResult.CALL_ORIGINAL
    end

    local manager = arg_object(args, 2)
    if manager then
        current.player_manager = manager
        current.player_manager_status =
            "captured via onUpdate: " .. runtime_type_name(manager)
        if current.probe_status == "apply failed"
            and current.probe_error == "chainsaw.PlayerManager not found"
        then
            current.probe_status = "ready; PlayerManager captured"
            current.probe_error = "none"
        end
    end

    return sdk.PreHookResult.CALL_ORIGINAL
end

local function install_player_manager_capture_hook()
    if _G.NativePlayerManagerCaptureHookInstalled then return end

    local t = sdk.find_type_definition("chainsaw.PlayerManager")
    local method = t and t:get_method("onUpdate") or nil
    if not method then
        NATIVE.player_manager_status =
            "capture hook unavailable: onUpdate not found"
        return
    end

    local ok, err = pcall(
        sdk.hook,
        method,
        player_manager_capture_pre,
        function(retval) return retval end
    )
    if ok then
        _G.NativePlayerManagerCaptureHookInstalled = true
        NATIVE.player_manager_status = "waiting for onUpdate"
    else
        NATIVE.player_manager_status =
            "capture hook failed: " .. tostring(err)
    end
end

local function make_color(r, g, b)
    local color = nil
    local ok, err = pcall(function()
        local t = sdk.find_type_definition("via.Color")
        if not t then error("via.Color type not found") end
        color = ValueType.new(t)
        if not color then error("via.Color creation failed") end
        color:call(
            ".ctor",
            math.floor(clamp(r, 0, 255) + 0.5),
            math.floor(clamp(g, 0, 255) + 0.5),
            math.floor(clamp(b, 0, 255) + 0.5),
            255
        )
    end)
    if not ok then
        NATIVE.last_error = "make_color: " .. tostring(err)
        return nil
    end
    return color
end

local function reset_triggers()
    return false
end

local function set_trigger(motor, power, frequency, start_pos, end_pos)
    return false
end

local function convert_trigger_instruction(inst)
    local p = inst and inst.parameters or nil
    if not p or inst.type ~= 1 then return nil end

    local trigger = tonumber(p[2])
    local mode = tonumber(p[3]) or 0
    local motor = trigger == 1 and 0 or trigger == 2 and 1 or nil
    if motor == nil then return nil end

    if mode == 0 then
        return {motor, 0.0, 0.0, 0.0, 0.0}
    end

    if mode == 13 then
        local start_pos = clamp(tonumber(p[4]) or 0, 0, 9) / 9.0
        local force = clamp(tonumber(p[5]) or 0, 0, 8) / 8.0
        return {motor, force, 0.0, start_pos, 1.0}
    end

    if mode == 2 then
        local start_pos = clamp(tonumber(p[4]) or 0, 0, 9) / 9.0
        local end_pos = clamp(tonumber(p[5]) or 9, 0, 9) / 9.0
        local force = clamp(tonumber(p[6]) or 0, 0, 8) / 8.0
        return {motor, force, 0.0, start_pos, end_pos}
    end

    if mode == 3 then
        local start_pos = clamp(tonumber(p[4]) or 0, 0, 9) / 9.0
        local end_pos = clamp(tonumber(p[5]) or 9, 0, 9) / 9.0
        local force = clamp(tonumber(p[6]) or 0, 0, 8) / 8.0
        local snap = clamp(tonumber(p[7]) or 0, 0, 8) / 8.0
        return {motor, force, snap, start_pos, end_pos}
    end

    if mode == 8 then
        local intensity = clamp(tonumber(p[4]) or 0, 0, 20) / 20.0
        return {motor, intensity, 0.65, 0.0, 1.0}
    end

    NATIVE.last_status = "unsupported DSX trigger mode: " .. tostring(mode)
    return {motor, 0.0, 0.0, 0.0, 0.0}
end

local function apply_triggers(mapping, info)
    return
end

local function write_lightbar(method_name, ...)
    if not NATIVE.native_device then return nil end
    local args = {...}
    local value = nil
    local ok, err = pcall(function()
        NATIVE.internal_lightbar_write = true
        value = NATIVE.native_device:call(method_name, table.unpack(args))
    end)
    NATIVE.internal_lightbar_write = false
    if not ok then
        NATIVE.last_error = tostring(method_name) .. ": " .. tostring(err)
        return nil
    end
    return value
end

local function dualib_owns_lightbar()
    local IPC = _G.DuaLibTriggerIpc
    return IPC ~= nil and IPC.lightbar_enabled == true
end

local function apply_lightbar(led)
    if not NATIVE.native_device then return end
    -- Force lightbar black during level loading or player death.
    -- loading_blackout: onStartInGameSetup..onStartInGame
    -- death_blackout:   is_dead detected..death recovery/onStartInGame
    if NATIVE.loading_blackout or NATIVE.death_blackout then
        NATIVE.owns_lightbar = true
        local sig = "0,0,0"
        if NATIVE.last_written_color ~= sig then
            local color = make_color(0, 0, 0)
            if color then
                NATIVE.cached_color = color
                write_lightbar("set_LightBarColor", color)
                NATIVE.last_written_color = sig
                NATIVE.lightbar_apply_count = NATIVE.lightbar_apply_count + 1
            end
        end
        return
    end
    if dualib_owns_lightbar() then
        -- The external duaLib watcher now writes scePadSetLightBar directly
        -- as its own independent HID report. Keep blocking Capcom's
        -- share.hid.Device calls (owns_lightbar stays true so
        -- lightbar_pre_hook keeps doing that) but stop issuing our own
        -- managed write/enforcement; cached_color=nil makes
        -- device_update_post_hook a no-op so only duaLib's write reaches
        -- hardware while a source is active.
        if led and led[1] ~= nil then
            NATIVE.owns_lightbar = true
        else
            NATIVE.owns_lightbar = false
        end
        NATIVE.last_written_color = nil
        NATIVE.cached_color = nil
        return
    end
    if not NATIVE.lightbar_enabled then
        if NATIVE.owns_lightbar then
            -- Hardware-confirmed 2025-06-30: calling the game's own
            -- resetLightBarColor() here doesn't just blank the bar for a
            -- moment, it resets whatever cached color Capcom's own
            -- device_update() re-applies every frame -- and since Capcom
            -- only calls set_LightBarColor again on its own state changes
            -- (not continuously), nothing tells it to restore its color
            -- afterward, leaving the lightbar stuck black until the next
            -- real Capcom-side transition. Just release ownership
            -- (stop blocking Capcom's calls) instead of forcing a reset;
            -- the next natural Capcom call repaints it correctly.
            NATIVE.owns_lightbar = false
            NATIVE.last_written_color = nil
            NATIVE.cached_color = nil
        end
        return
    end
    if led and led[1] ~= nil then
        NATIVE.owns_lightbar = true
        local signature = string.format(
            "%d,%d,%d",
            math.floor(led[1] + 0.5),
            math.floor(led[2] + 0.5),
            math.floor(led[3] + 0.5)
        )
        if signature ~= NATIVE.last_written_color then
            local color = make_color(led[1], led[2], led[3])
            if color then
                NATIVE.cached_color = color
                write_lightbar("set_LightBarColor", color)
                NATIVE.last_written_color = signature
                NATIVE.lightbar_apply_count =
                    NATIVE.lightbar_apply_count + 1
            end
        end
    else
        -- While gameplay is active (EVENTS.in_game=true), the LED bus can be
        -- momentarily empty for 1-2 frames between reset_all() and the first
        -- hp_led push (onStartInGame entry transition). Keep the claim during
        -- that window so Capcom's green doesn't slip through. cached_color=nil
        -- means the post-update hook enforces nothing during the hold.
        -- Release normally when not in gameplay (menu, pre-load, death).
        local EL = _G.EventsLed
        local holding_for_gameplay = EL and EL.in_game or false
        if not holding_for_gameplay and NATIVE.owns_lightbar then
            -- Don't call resetLightBarColor() here (see the comment in
            -- apply_lightbar's lightbar_enabled=false branch): it resets
            -- Capcom's own cached color with nothing to make Capcom restore
            -- it, leaving the lightbar stuck black instead of returning to
            -- Capcom's own blue. Just stop blocking and let the next natural
            -- Capcom call repaint.
            NATIVE.owns_lightbar = false
            NATIVE.last_written_color = nil
            NATIVE.cached_color = nil
        end
    end
end

function NATIVE.apply(info, mapping, led)
    NATIVE.last_info = info
    NATIVE.last_mapping = mapping
    NATIVE.last_led = led

    if not NATIVE.available and not refresh_device() then return false end

    apply_lightbar(led)
    NATIVE.apply_count = NATIVE.apply_count + 1
    NATIVE.last_status = "native feedback applied"
    return true
end

function NATIVE.apply_lightbar(led)
    NATIVE.last_led = led
    if not NATIVE.available and not refresh_device() then return false end
    apply_lightbar(led)
    return true
end

function NATIVE.release()
    if not NATIVE.device then refresh_device() end
    if NATIVE.device then
        -- Same finding as apply_lightbar(): resetLightBarColor() resets
        -- Capcom's own cached color with nothing to make it restore it on
        -- its own. Just stop blocking; do not force a reset.
        NATIVE.owns_lightbar = false
        NATIVE.last_written_color = nil
        NATIVE.cached_color = nil
    end
    NATIVE.last_status = "native feedback released to game"
end

function NATIVE.refresh()
    return refresh_device()
end

function NATIVE.test_lightbar()
    if not NATIVE.available and not refresh_device() then return false end
    NATIVE.lightbar_enabled = true
    NATIVE.test_led_frames = 180
    apply_lightbar({255, 0, 255})
    NATIVE.last_status = "test magenta lightbar sent"
    return true
end

local function player_manager_set_adaptive(
    motor, power, frequency, start_pos, end_pos)
    local manager = get_player_manager()
    if not manager then
        NATIVE.probe_error = "chainsaw.PlayerManager not found"
        return false
    end

    local ok, err = pcall(function()
        manager:call(
            "setAdaptiveFeedBack",
            motor,
            power,
            frequency,
            start_pos,
            end_pos
        )
    end)
    if not ok then
        NATIVE.probe_error =
            "PlayerManager.setAdaptiveFeedBack: " .. tostring(err)
        return false
    end
    return true
end

function NATIVE.start_l2_probe()
    if not NATIVE.probe_risk_ack then
        NATIVE.probe_status = "blocked: acknowledge crash risk first"
        return false
    end
    if NATIVE.probe_active then
        NATIVE.probe_status = "already active"
        return false
    end

    NATIVE.probe_error = "none"
    -- Weak resistance on L2. Uses the PlayerManager lifecycle instead of
    -- calling share.hid.Device or via.hid.DualSenseDevice directly.
    if not player_manager_set_adaptive(0, 0.18, 0.0, 0.20, 0.70) then
        NATIVE.probe_status = "apply failed"
        return false
    end

    NATIVE.probe_active = true
    NATIVE.probe_frames = 60
    NATIVE.probe_status = "weak L2 active; auto-reset in 1 second"
    return true
end

function NATIVE.stop_l2_probe(reason)
    local ok = player_manager_set_adaptive(0, 0.0, 0.0, 0.0, 0.0)
    NATIVE.probe_active = false
    NATIVE.probe_frames = 0
    NATIVE.probe_status = ok and
        ("reset: " .. tostring(reason or "manual")) or "reset failed"
    return ok
end

-- Diagnostic only: logs every Capcom-originated set_LightBarColor call that
-- is NOT blocked by our own ownership, so the exact frame where Capcom
-- switches from boot/menu blue to a gameplay color can be read back from
-- DualSenseEnhanced/native_lightbar_debug.txt and compared against when the
-- player actually gains control. This is the ground-truth signal Capcom
-- itself uses; the goal is to find a hook that fires at the same time
-- instead of guessing at GameFlowManager/PlayerController-style names.
local function log_capcom_lightbar_call(args)
    NATIVE.capcom_lightbar_log_count =
        (NATIVE.capcom_lightbar_log_count or 0) + 1
    local count = NATIVE.capcom_lightbar_log_count
    -- Throttle after the first 200 calls; the interesting data is the
    -- transition itself, not a per-frame flood once color stabilizes.
    if count > 200 and count % 30 ~= 0 then return end

    local ok = pcall(function()
        -- via.Color here is small enough (4 bytes) to be passed by value in
        -- a register rather than by pointer, so sdk.to_valuetype/
        -- to_managed_object both fail. sdk.to_int64 reads the raw packed
        -- bits correctly; decode as little-endian r,g,b,a bytes (confirmed
        -- 2025-06-30: packed=4281863680 decoded to r=0 g=14 b=56 a=255, a
        -- plausible dark "boot/menu blue").
        local packed = tonumber(sdk.to_int64(args[2])) or 0
        local r = packed % 256
        local g = math.floor(packed / 256) % 256
        local b = math.floor(packed / 65536) % 256
        local a = math.floor(packed / 16777216) % 256

        local f = io.open("DualSenseEnhanced/native_lightbar_debug.txt", "a")
        if not f then return end
        f:write(string.format(
            "%s #%d capcom set_LightBarColor r=%d g=%d b=%d a=%d\n",
            os.date("%H:%M:%S"), count, r, g, b, a
        ))
        f:close()
    end)
    if not ok then end
end

local function lightbar_pre_hook(args)
    local current = _G.NativeDualSenseFeedback
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if current
        and FEEDBACK
        and FEEDBACK.output_mode == "native"
        and current.owns_lightbar
        and not current.internal_lightbar_write
    then
        current.blocked_game_lightbar_calls =
            (current.blocked_game_lightbar_calls or 0) + 1
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
    if current and current.capcom_lightbar_diag and args then
        pcall(log_capcom_lightbar_call, args)
    end
    return sdk.PreHookResult.CALL_ORIGINAL
end

local function lightbar_post_hook(retval)
    return retval
end

local function device_update_post_hook(retval)
    local current = _G.NativeDualSenseFeedback
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if current
        and FEEDBACK
        and FEEDBACK.output_mode == "native"
        and current.owns_lightbar
        and current.cached_color
    then
        current.internal_lightbar_write = true
        local ok, err = pcall(function()
            if current.native_device then
                current.native_device:call(
                    "set_LightBarColor",
                    current.cached_color
                )
            end
        end)
        current.internal_lightbar_write = false
        if ok then
            current.enforce_count = (current.enforce_count or 0) + 1
        else
            current.last_error =
                "post-update lightbar enforce: " .. tostring(err)
        end
    end
    return retval
end

local function install_lightbar_hooks()
    if _G.NativeDualSenseNativeLightbarHooksInstalled then return end
    local t = sdk.find_type_definition("via.hid.PSGamePadDevice")
    if not t then
        NATIVE.last_error = "via.hid.PSGamePadDevice type not found for hooks"
        return
    end

    local installed = 0
    for _, name in ipairs({"set_LightBarColor", "resetLightBarColor"}) do
        local method = t:get_method(name)
        if method then
            local ok, err = pcall(
                sdk.hook,
                method,
                lightbar_pre_hook,
                lightbar_post_hook
            )
            if ok then
                installed = installed + 1
            else
                NATIVE.last_error = "hook " .. name .. ": " .. tostring(err)
            end
        end
    end

    if installed == 2 then
        _G.NativeDualSenseNativeLightbarHooksInstalled = true
    end
end

local function install_device_update_hook()
    if _G.NativeDualSenseDeviceUpdateHookInstalled then return end
    local t = sdk.find_type_definition("share.hid.Device")
    local method = t and t:get_method("update") or nil
    if not method then
        NATIVE.last_error = "share.hid.Device.update hook not found"
        return
    end

    local ok, err = pcall(
        sdk.hook,
        method,
        function(args)
            -- Opportunistic early capture: share.hid.Device:update() is called
            -- every frame by the engine, and args[2] is the device instance
            -- (the `this` pointer). getGamePadDevice(0) via AppSingleton can
            -- return nil for 2-3s on cold start because DeviceSystem hasn't
            -- finished its own enumeration yet. Capturing directly from the
            -- update hook fires as soon as the engine starts ticking this
            -- device, which may be during the main menu -- long before
            -- onStartInGame. Once available=true the pcall is a no-op.
            local current = _G.NativeDualSenseFeedback
            if current and not current.available then
                pcall(function()
                    local dev = sdk.to_managed_object(args[2])
                    if dev and dev:call("get_IsDualSenseDevice") == true then
                        local native_dev = dev:call("get_NativeDevice")
                        local tname = ""
                        if native_dev then
                            local td = native_dev:get_type_definition()
                            tname = td and td:get_full_name() or ""
                        end
                        if tname:find("DualSense", 1, true) then
                            current.device = dev
                            current.native_device = native_dev
                            current.device_type = tname
                            current.available = true
                            current.last_status = "captured via device.update hook"
                        end
                    end
                end)
            end
            return sdk.PreHookResult.CALL_ORIGINAL
        end,
        device_update_post_hook
    )
    if ok then
        _G.NativeDualSenseDeviceUpdateHookInstalled = true
    else
        NATIVE.last_error =
            "share.hid.Device.update hook: " .. tostring(err)
    end
end

local function adaptive_pre_hook(kind, param_count)
    return function(args)
        local current = _G.NativeDualSenseFeedback
        if not current then
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        pcall(function()
            if kind == "raw" then
                push_adaptive_event(
                    "setAdaptiveFeedBack",
                    "motor=" .. tostring(arg_int(args, 3)) ..
                    " power=" .. fmt_float(arg_float(args, 4)) ..
                    " freq=" .. fmt_float(arg_float(args, 5)) ..
                    " start=" .. fmt_float(arg_float(args, 6)) ..
                    " end=" .. fmt_float(arg_float(args, 7))
                )
            elseif kind == "userdata" and param_count == 2 then
                local param = arg_object(args, 3)
                push_adaptive_event(
                    "setAdaptiveTriggerFeedback",
                    "userdata=" .. runtime_type_name(param) ..
                    " skipFrequency=" .. tostring(arg_int(args, 4))
                )
            elseif kind == "data" and param_count == 3 then
                local data = arg_object(args, 4)
                local range = safe_call(data, "get_Range")
                push_adaptive_event(
                    "setAdaptiveTriggerFeedback",
                    "motor=" .. tostring(arg_int(args, 3)) ..
                    " power=" .. fmt_float(safe_call(data, "get_Power")) ..
                    " freq=" .. fmt_float(safe_call(data, "get_Frequency")) ..
                    " range=" .. tostring(range) ..
                    " skipFrequency=" .. tostring(arg_int(args, 5))
                )
            elseif kind == "update" then
                push_adaptive_event("updateAdaptiveFeedBack", "tick")
            end
        end)

        return sdk.PreHookResult.CALL_ORIGINAL
    end
end

local function install_adaptive_diagnostics()
    _G.NativeAdaptiveDiagInstalled =
        _G.NativeAdaptiveDiagInstalled or {}
    local installed = _G.NativeAdaptiveDiagInstalled

    local t = sdk.find_type_definition("chainsaw.PlayerManager")
    if not t then
        NATIVE.adaptive_hook_status["chainsaw.PlayerManager"] =
            "type not found"
        return
    end

    for _, method in ipairs(t:get_methods() or {}) do
        local name = method:get_name()
        local kind = nil
        if name == "setAdaptiveFeedBack" then kind = "raw" end
        if name == "setAdaptiveTriggerFeedback" then
            kind = method:get_num_params() == 2 and "userdata" or "data"
        end
        -- updateAdaptiveFeedBack is intentionally not logged: it runs every
        -- frame and would drown the meaningful parameter changes.

        if kind then
            local key = name .. "/" .. tostring(method:get_num_params())
            if not installed[key] then
                local ok, err = pcall(
                    sdk.hook,
                    method,
                    adaptive_pre_hook(kind, method:get_num_params()),
                    function(retval) return retval end
                )
                if ok then
                    installed[key] = true
                    NATIVE.adaptive_hook_status[key] = "installed"
                else
                    NATIVE.adaptive_hook_status[key] =
                        "failed: " .. tostring(err)
                end
            else
                NATIVE.adaptive_hook_status[key] = "already installed"
            end
        end
    end
end

re.on_application_entry("UpdateBehavior", function()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if NATIVE.probe_active then
        NATIVE.probe_frames = NATIVE.probe_frames - 1
        if NATIVE.probe_frames <= 0 then
            pcall(NATIVE.stop_l2_probe, "automatic timeout")
        end
    end
    if not FEEDBACK or FEEDBACK.output_mode ~= "native" then return end

    -- refresh_device() only ran once, at script-load time, which can be
    -- too early in the boot sequence for share.hid.DeviceSystem to have
    -- enumerated the controller as a native DualSense yet. With no retry,
    -- NATIVE.native_device stayed nil for the rest of the session unless
    -- something else (a manual custom DSX/native mode button toggle, which
    -- calls native.refresh()) happened to trigger a second attempt --
    -- hardware-confirmed 2025-06-30: the custom lightbar/menu color never
    -- applied for an entire boot-to-gameplay session until the user
    -- manually flipped the mode native->off->native. Retry periodically
    -- here instead of only on an explicit mode-change call.
    if not NATIVE.available then
        device_retry_frames = (device_retry_frames or 0) + 1
        if device_retry_frames >= DEVICE_RETRY_INTERVAL then
            device_retry_frames = 0
            refresh_device()
        end
        if not NATIVE.available then return end
    end

    frame = frame + 1
    if frame < NATIVE.frame_interval then return end
    frame = 0

    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or NATIVE.last_info
    local mapping = FEEDBACK.find_mapping_for_info and
        FEEDBACK.find_mapping_for_info(info) or NATIVE.last_mapping
    local r, g, b, led_name = nil, nil, nil, nil
    if FEEDBACK.get_active_led then
        r, g, b, led_name = FEEDBACK.get_active_led()
    end
    if NATIVE.test_led_frames > 0 then
        NATIVE.test_led_frames =
            math.max(0, NATIVE.test_led_frames - NATIVE.frame_interval)
        r, g, b = 255, 0, 255
    end
    -- hp_led.lua's danger pulse is now a continuous red brightness
    -- oscillation (never a literal black frame), so the orange black-rest
    -- substitute this used to need is gone -- it now pulses pure red.
    local led = r ~= nil and {r, g, b} or nil
    pcall(NATIVE.apply_lightbar, led)
end)

install_lightbar_hooks()
install_device_update_hook()
install_adaptive_diagnostics()
install_player_manager_capture_hook()
refresh_device()
