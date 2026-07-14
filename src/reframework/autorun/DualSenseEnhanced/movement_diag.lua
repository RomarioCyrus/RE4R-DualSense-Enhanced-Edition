-- Dev-only diagnostic: locate a run/sprint/speed signal on the player so
-- footstep haptics can be gated on actual movement state instead of a
-- fixed cooldown. See wwise_audio_router.lua's footstep-handler comment
-- ("If revisiting per-actor filtering, it needs ... the player's own
-- CharacterController velocity/movement state via REFramework reflection").
--
-- Not wired into any runtime behavior yet -- this only reads and logs, it
-- does not gate anything. Excluded from RELEASE_BUILD like the rest of the
-- debug tools.

local sdk = sdk
local pcall = pcall

_G.MovementDiag = _G.MovementDiag or {}
local M = _G.MovementDiag

-- Set by DualSenseEnhanced.lua to the main script's log() so dump() output
-- lands in the mod's own "Console" panel (in-game imgui), not just
-- REFramework's separate dev console which is easy to miss. Falls back to
-- print() if never wired up.
M.logger = M.logger or print

local function out(msg)
    M.logger(msg)
end

local KEYWORDS = {
    "speed", "run", "sprint", "dash", "walk", "motion", "veloc", "moving",
    "locomot", "gait", "pace",
}

local function safe_call(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function contains_any(name, patterns)
    if not name then return false end
    local lower = name:lower()
    for _, p in ipairs(patterns) do
        if lower:find(p, 1, true) then return true end
    end
    return false
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

local function value_text(v)
    if v == nil then return "nil" end
    local ok, s = pcall(tostring, v)
    if ok then return s end
    return "?"
end

-- Dumps every method/field on `obj` whose name matches a movement keyword.
-- Zero-arg methods are also invoked (best-effort, pcall-guarded) so the
-- live value shows up next to the name -- makes it obvious in the log which
-- one moves when you start sprinting.
local function dump_object(obj, label)
    if not obj then
        out(label .. ": nil (not found)")
        return
    end

    local t = safe_call(obj.get_type_definition, obj)
    local type_name = t and safe_call(t.get_full_name, t) or "?"
    out(label .. " = " .. type_name)

    if not t then return end

    local methods = safe_call(t.get_methods, t) or {}
    for _, m in ipairs(methods) do
        local name = safe_call(m.get_name, m)
        if contains_any(name, KEYWORDS) then
            local params = safe_call(m.get_num_params, m) or -1
            if params == 0 then
                local ok, ret = pcall(function() return obj:call(name) end)
                if ok then
                    out("  method " .. name .. "() = " .. value_text(ret))
                else
                    out("  method " .. name .. "() [call failed]")
                end
            else
                out("  method " .. name .. "(" .. tostring(params) .. " params)")
            end
        end
    end

    local fields = safe_call(t.get_fields, t) or {}
    for _, f in ipairs(fields) do
        local name = safe_call(f.get_name, f)
        if contains_any(name, KEYWORDS) then
            local ok, val = pcall(function() return f:get_data(obj) end)
            if ok then
                out("  field " .. tostring(name) .. " = " .. value_text(val))
            end
        end
    end
end

-- Common nested objects worth checking too -- best-effort, any that don't
-- exist on this type just print "nil (not found)" and are skipped.
local NESTED_GETTERS = {
    "get_CharacterController",
    "get_MotionController",
    "get_MoveController",
    "get_PlayerCondition",
    "get_ActionController",
}

function M.dump()
    out("--- Movement dump @ " .. tostring(os.clock()) .. " ---")
    local player = find_player()
    dump_object(player, "player")
    if not player then return end

    for _, getter in ipairs(NESTED_GETTERS) do
        local nested = safe_call(player.call, player, getter)
        if nested then
            dump_object(nested, getter)
        end
    end
end

return M
