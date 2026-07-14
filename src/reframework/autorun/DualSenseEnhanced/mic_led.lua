local tostring = tostring
local tonumber = tonumber

-- ================================================================
-- mic_led.lua
-- Routes Mic LED commands through DualSenseEnhancedFeedback/payload.json.
-- ================================================================

local MIC = {}

MIC.enabled = true
MIC.controller_index = 0
MIC.port = nil
MIC.command_path = "DualSenseEnhanced/payload.json"
MIC.last_error = nil
MIC.last_command = nil
MIC.last_status = "not sent"

MIC.modes = {
    on = 0,
    pulse = 1,
    off = 2,
}

local empty_active = false
local reload_cooldown = 0
local reload_timer = 0

-- Tracked independently of the feedback writer so the native duaLib IPC path
-- (dualib_trigger_ipc.lua) can mirror the same Mic LED intent without going
-- through payload.json.
-- Defaults to Off rather than nil: MIC.set_empty/pulse_reload are
-- edge-triggered (they no-op when the requested state already matches
-- their internal last-known state), so without a real Off baseline here,
-- a session that never crosses an empty<->non-empty transition would leave
-- this nil forever and the duaLib IPC path would never send a real mode.
MIC.last_mode_raw = MIC.last_mode_raw or MIC.modes.off

local function queue_mode(mode, reason)
    MIC.last_mode_raw = mode
    if not MIC.enabled then return false end

    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK or not FEEDBACK.set_mic_led or not FEEDBACK.apply_for_weapon then
        MIC.last_error = "DualSenseEnhancedFeedback missing"
        MIC.last_status = "failed: " .. tostring(reason or "sent")
        return false
    end

    FEEDBACK.set_mic_led(MIC.controller_index, mode)
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info or { id = "none", name = "None", type = "none", ammo = 0, ammoMax = 0 }
    pcall(FEEDBACK.apply_for_weapon, info)

    MIC.last_command = "controller=" .. tostring(MIC.controller_index) ..
        " mode=" .. tostring(mode) ..
        " reason=" .. tostring(reason or "sent")
    MIC.last_error = nil
    MIC.last_status = "payload: " .. tostring(reason or "sent") .. " mode=" .. tostring(mode)

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("mic led payload", MIC.last_status) end
    return true
end

function MIC.set_empty(active)
    active = active == true
    if active == empty_active then return false end
    empty_active = active

    if active then
        return queue_mode(MIC.modes.pulse, "empty")
    end
    return queue_mode(MIC.modes.off, "empty clear")
end

function MIC.pulse_reload(frames)
    if reload_cooldown > 0 then return false end
    reload_cooldown = 15
    reload_timer = tonumber(frames) or 120
    if reload_timer < 1 then reload_timer = 1 end
    return queue_mode(MIC.modes.pulse, "reload")
end

function MIC.off()
    empty_active = false
    reload_timer = 0
    return queue_mode(MIC.modes.off, "off")
end

function MIC.pulse(frames)
    reload_timer = tonumber(frames) or 120
    if reload_timer < 1 then reload_timer = 1 end
    return queue_mode(MIC.modes.pulse, "test pulse")
end

function MIC.on()
    reload_timer = 0
    return queue_mode(MIC.modes.on, "on")
end

function MIC.refresh_port()
    MIC.port = nil
    MIC.last_status = "uses payload.json"
    return MIC.port
end

pcall(function()
    re.on_application_entry("UpdateBehavior", function()
        if reload_cooldown > 0 then reload_cooldown = reload_cooldown - 1 end
        if reload_timer > 0 then
            reload_timer = reload_timer - 1
            if reload_timer <= 0 and not empty_active then
                queue_mode(MIC.modes.off, "reload clear")
            end
        end
    end)
end)

_G.DualSenseEnhancedMicLED = MIC
