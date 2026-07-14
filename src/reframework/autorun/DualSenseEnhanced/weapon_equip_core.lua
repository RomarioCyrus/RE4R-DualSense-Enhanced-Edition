local sdk = sdk
local re = re
local pcall = pcall
local tostring = tostring

-- Keep ammo-driven audio responsive. Three UpdateBehavior frames cap the
-- polling contribution at roughly 50 ms at 60 FPS.
local POLL_INTERVAL = 3

_G.WeaponEquipCore = _G.WeaponEquipCore or {}
local CORE = _G.WeaponEquipCore

CORE.config = CORE.config or { enabled = true }
CORE.callbacks = CORE.callbacks or {}
CORE.last_info = CORE.last_info or nil
CORE.status = CORE.status or {
    ready = false,
    controller_found = false,
    weapon_name = "None",
    ammo = 0,
    ammoMax = 0
}

local function safe_call(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function controller_has_equipped_weapon(ctrl)
    if not ctrl then return false end
    local weapon = safe_call(ctrl.call, ctrl, "getEquippedWeapon")
    if not weapon then weapon = safe_call(ctrl.call, ctrl, "getEquippedWeapon", 0) end
    return weapon ~= nil
end

local WEAPON_DATA_PATH = "reframework/data/RE4R_WeaponData.lua"
local WEAPON_NAMES = {}

local function load_weapon_names()
    local ok, chunk = pcall(loadfile, WEAPON_DATA_PATH)
    if not ok or not chunk then return end
    local ok2, data = pcall(chunk)
    if not ok2 or type(data) ~= "table" then return end
    
    local src = data.Weapons or {}
    for _, w in pairs(src) do
        if type(w) == "table" then
            local enum = tonumber(w.Enum)
            local name = w.Name
            local typ  = w.Type or w.TypeName
            if enum and name then
                WEAPON_NAMES[enum] = { name = name, type = typ and tostring(typ):lower() or nil }
            end
        end
    end
end
load_weapon_names()

local function find_inventory_controller()
    local fallback = nil

    local pm = safe_call(sdk.get_managed_singleton, "chainsaw.PlayerManager")
    if pm then
        local player = safe_call(pm.call, pm, "get_CurrentPlayer")
        if player then
            local inv = safe_call(player.call, player, "get_InventoryController")
            if controller_has_equipped_weapon(inv) then return inv end
            fallback = fallback or inv
        end
    end

    local cm = safe_call(sdk.get_managed_singleton, "chainsaw.CharacterManager")
    if cm then
        local player = safe_call(cm.call, cm, "getPlayerContextRef")
        if not player then player = safe_call(cm.call, cm, "get_ManualPlayer") end
        if player then
            local inv = safe_call(player.call, player, "get_InventoryController")
            if controller_has_equipped_weapon(inv) then return inv end
            fallback = fallback or inv
        end
    end

    local im = safe_call(sdk.get_managed_singleton, "chainsaw.InventoryManager")
    if im then
        local tdef = safe_call(im.get_type_definition, im)
        local field = tdef and safe_call(tdef.get_field, tdef, "_ControllerTable")
        local dict = field and safe_call(field.get_data, field, im)
        local vals = dict and safe_call(dict.call, dict, "get_Values")
        local enum = vals and safe_call(vals.call, vals, "GetEnumerator")
        
        if enum then
            while safe_call(enum.call, enum, "MoveNext") do
                local cur = safe_call(enum.call, enum, "get_Current")
                if cur then
                    local t = safe_call(cur.get_type_definition, cur)
                    local name = t and safe_call(t.get_full_name, t)
                    if name == "chainsaw.CsInventoryController" then
                        if controller_has_equipped_weapon(cur) then return cur end
                        fallback = fallback or cur
                    end
                end
            end
        end
    end

    return fallback
end

local function get_weapon_info(ctrl)
    if not ctrl then return nil end
    local weapon = safe_call(ctrl.call, ctrl, "getEquippedWeapon")
    if not weapon then weapon = safe_call(ctrl.call, ctrl, "getEquippedWeapon", 0) end
    
    if not weapon then 
        return { id = "none", name = "None", type = "none", ammo = 0, ammoMax = 0 }
    end

    local ammo     = safe_call(weapon.call, weapon, "get_CurrentAmmoCount") or 0
    local ammoMax  = safe_call(weapon.call, weapon, "get_CurrentAmmoMax") or 0
    local enum_obj = safe_call(weapon.call, weapon, "get_WeaponId")
    local enum_val = enum_obj and tonumber(enum_obj) or nil

    local weapon_name = "Unknown"
    local weapon_type = nil

    if enum_val and WEAPON_NAMES[enum_val] then
        local entry = WEAPON_NAMES[enum_val]
        weapon_name = entry.name or weapon_name
        weapon_type = entry.type or nil
    else
        weapon_name = safe_call(weapon.call, weapon, "get_Name") or weapon_name
    end

    return {
        id = enum_val,
        name = weapon_name,
        type = weapon_type,
        ammo = ammo,
        ammoMax = ammoMax
    }
end

local tick = 0
local last_id = nil
local heartbeat = 0

function CORE.on_weapon_change(fn)
    if type(fn) == "function" then CORE.callbacks[#CORE.callbacks + 1] = fn end
end

local function notify_all(info)
    for _,cb in ipairs(CORE.callbacks) do pcall(cb, info) end
end

local function on_update()
    tick = tick + 1
    if tick % POLL_INTERVAL ~= 0 then return end

    if not CORE.config.enabled then return end

    local controller = find_inventory_controller()
    
    local info = nil
    if controller then
        CORE.status.controller_found = true
        info = get_weapon_info(controller)
    else
        CORE.status.controller_found = false
        info = { id = "none", name = "Searching...", type = "none", ammo = 0, ammoMax = 0 }
    end

    CORE.status.weapon_name = info.name
    CORE.status.ammo = info.ammo
    CORE.status.ammoMax = info.ammoMax
    CORE.last_info = info 

    heartbeat = heartbeat + 1
    local force_pulse = (heartbeat > 20)

    if (info.id ~= last_id) or force_pulse then
        last_id = info.id
        CORE.status.ready = true
        notify_all(info)
        
        if force_pulse then heartbeat = 0 end 
    end
end

pcall(function() re.on_application_entry("UpdateBehavior", on_update) end)

CORE._internal = { poll = POLL_INTERVAL }
