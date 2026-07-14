-- Live sprint-state polling for gating footstep haptics on actual running,
-- not just event cadence. Live-confirmed 2026-07-13 via movement_diag.lua:
-- get_RequestRun() on the player object flips false (standing/walking) <->
-- true (sprinting) in lockstep with the sprint button. IsRunPassThrough
-- tracks the same true/false pattern but looks like a collision-passthrough
-- side effect of running (enemy pass-through while sprinting), not the
-- source of truth -- RequestRun was picked as the primary signal.
--
-- Which object exposes get_RequestRun() (the player itself vs a nested
-- CharacterController/MotionController) wasn't disambiguated from the dump
-- alone, so this probes the player object first, then the usual nested
-- controllers, and caches whichever one answers.

local sdk = sdk
local pcall = pcall

_G.PlayerMovement = _G.PlayerMovement or {}
local PM = _G.PlayerMovement
PM.is_running = false
PM.source = nil -- "player" or a nested getter name, once resolved

local POLL_INTERVAL = 2 -- frames; sprint state doesn't need per-frame precision

local function safe_call(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function find_player()
    local pm = safe_call(sdk.get_managed_singleton, "chainsaw.PlayerManager")
    if pm then
        local player = safe_call(pm.call, pm, "get_CurrentPlayer")
        if player then return player end
    end

    local cm = safe_call(sdk.get_managed_singleton, "chainsaw.CharacterManager")
    if cm then
        local player = safe_call(cm.call, cm, "getPlayerContextRef")
        if not player then player = safe_call(cm.call, cm, "get_ManualPlayer") end
        if player then return player end
    end

    return nil
end

local NESTED_GETTERS = {
    "get_CharacterController",
    "get_MotionController",
    "get_MoveController",
    "get_PlayerCondition",
    "get_ActionController",
}

local function try_get_running(obj)
    if not obj then return nil end
    local ok, val = pcall(function() return obj:call("get_RequestRun") end)
    if ok and type(val) == "boolean" then return val end
    return nil
end

local frame_counter = 0

function PM.update()
    frame_counter = frame_counter + 1
    if frame_counter % POLL_INTERVAL ~= 0 then return end

    local player = find_player()
    if not player then return end

    if PM.source == "player" then
        local v = try_get_running(player)
        if v ~= nil then PM.is_running = v; return end
        PM.source = nil
    elseif PM.source then
        local nested = safe_call(player.call, player, PM.source)
        local v = try_get_running(nested)
        if v ~= nil then PM.is_running = v; return end
        PM.source = nil
    end

    -- Not resolved (or lost, e.g. area transition) -- probe in order and
    -- cache the first hit so subsequent polls skip straight to it.
    local v = try_get_running(player)
    if v ~= nil then
        PM.source = "player"
        PM.is_running = v
        return
    end
    for _, getter in ipairs(NESTED_GETTERS) do
        local nested = safe_call(player.call, player, getter)
        v = try_get_running(nested)
        if v ~= nil then
            PM.source = getter
            PM.is_running = v
            return
        end
    end
end

return PM
