-- Adaptive trigger intensity presets for the native duaLib transport.
-- Scales Strength/EndStrength on the l2/r2 effect tables that
-- dualib_trigger_ipc.lua already builds from weapon_trigger_profiles.lua. It never
-- touches weapon_trigger_profiles.lua itself and never talks to duaLib directly.

local tonumber = tonumber
local tostring = tostring
local math = math
local pairs = pairs

_G.TriggerIntensity = _G.TriggerIntensity or {}
local TI = _G.TriggerIntensity

local PRESETS = {
    off = {
        label = "Off",
        global = 0.0,
        classes = { pistol = 1.0, shotgun = 1.0, rifle = 1.0, automatic = 1.0, magnum = 1.0 },
    },
    native_only = {
        label = "Native Only",
        global = 0.0,
        classes = { pistol = 1.0, shotgun = 1.0, rifle = 1.0, automatic = 1.0, magnum = 1.0 },
    },
    light = {
        label = "Light",
        global = 0.6,
        classes = { pistol = 0.9, shotgun = 0.8, rifle = 1.0, automatic = 0.8, magnum = 0.85 },
    },
    enhanced = {
        label = "Enhanced",
        global = 1.0,
        classes = { pistol = 1.0, shotgun = 1.0, rifle = 1.0, automatic = 1.0, magnum = 1.0 },
    },
    strong = {
        label = "Strong",
        global = 1.25,
        classes = { pistol = 1.1, shotgun = 1.3, rifle = 1.0, automatic = 1.1, magnum = 1.4 },
    },
}
TI.PRESETS = PRESETS
TI.PRESET_ORDER = { "off", "native_only", "light", "enhanced", "strong", "custom" }

-- "enhanced" keeps every multiplier at 1.0 so the current confirmed weapon
-- profiles are unchanged unless the user explicitly picks another preset.
TI.preset = TI.preset or "enhanced"
TI.global_intensity = tonumber(TI.global_intensity) or 1.0
TI.class_intensity = TI.class_intensity or {
    pistol = 1.0,
    shotgun = 1.0,
    rifle = 1.0,
    automatic = 1.0,
    magnum = 1.0,
}

-- info.type values come from weapon_equip_core.lua; group them the same way
-- weapon_trigger_profiles.lua's "type:*" mapping keys do.
local TYPE_TO_CLASS = {
    hg = "pistol",
    sg = "shotgun",
    sr = "rifle",
    rf = "rifle",
    xbow = "rifle",
    bowgun = "rifle",
    smg = "automatic",
    mag = "magnum",
    magnum = "magnum",
}
TI.TYPE_TO_CLASS = TYPE_TO_CLASS

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function TI.class_for_info(info)
    local type_l = info and info.type and tostring(info.type):lower():gsub("%s", "") or nil
    return type_l and TYPE_TO_CLASS[type_l] or nil
end

function TI.apply_preset(name)
    local preset = PRESETS[name]
    if not preset then return end
    TI.preset = name
    TI.global_intensity = preset.global
    for class, value in pairs(preset.classes) do
        TI.class_intensity[class] = value
    end
end

-- Call after any manual slider edit so the UI reflects a no-longer-stock preset.
function TI.mark_custom()
    TI.preset = "custom"
end

-- "Off" and "Native Only" both mean: do not apply custom duaLib trigger
-- effects. They are distinguished only for the user-facing label/docs; the
-- IPC enable checkbox is the actual on/off switch and is left to the caller.
function TI.disables_ipc()
    return TI.preset == "off" or TI.preset == "native_only"
end

-- Scales an l2/r2 effect table in place (mode/position/strength/...).
-- `strength` and `endStrength` are duaLib 0..8 fields; clamp after scaling.
function TI.scale_effect(effect, class)
    if type(effect) ~= "table" or effect.mode == "off" then return effect end

    local multiplier = TI.global_intensity * (TI.class_intensity[class] or 1.0)
    if multiplier == 1.0 then return effect end
    if multiplier <= 0.0 then return { mode = "off" } end

    local scaled = {}
    for k, v in pairs(effect) do scaled[k] = v end
    if scaled.strength then
        scaled.strength = math.floor(clamp(scaled.strength * multiplier, 0, 8) + 0.5)
    end
    if scaled.endStrength then
        scaled.endStrength = math.floor(clamp(scaled.endStrength * multiplier, 0, 8) + 0.5)
    end
    return scaled
end

if not PRESETS[TI.preset] and TI.preset ~= "custom" then
    TI.apply_preset("enhanced")
end
