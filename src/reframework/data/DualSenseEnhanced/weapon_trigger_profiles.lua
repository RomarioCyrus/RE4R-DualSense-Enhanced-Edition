-- DualSense Enhanced adaptive trigger profiles per weapon category.
--
-- Each profile is a list of DSX-compatible feedback instructions written to payload.json:
--   { type = 1, parameters = {controller, trigger, mode, ...mode args} }
--     trigger: 1 = L2, 2 = R2
--     mode 13 = Resistance, mode 2 = Weapon, mode 3 = Bow, mode 8 = Vibrate
--   { type = 2, parameters = {controller, r, g, b} }  -- lightbar colour
--
-- Resistance/force numbers are this project's own tuning pass:
-- pistols light, shotguns/magnums heavy, SMGs buzzy, throwables stiff.

local function l2_resistance(force)
    return { type = 1, parameters = { 0, 1, 13, 0, force } }
end

local function r2_weapon(start_pos, end_pos, force)
    return { type = 1, parameters = { 0, 2, 2, start_pos, end_pos, force } }
end

local function r2_bow(start_pos, end_pos, force, snap)
    return { type = 1, parameters = { 0, 2, 3, start_pos, end_pos, force, snap } }
end

local function r2_resistance(force)
    return { type = 1, parameters = { 0, 2, 13, 0, force } }
end

local function r2_vibrate(intensity)
    return { type = 1, parameters = { 0, 2, 8, intensity } }
end

local function r2_normal()
    return { type = 1, parameters = { 0, 2, 0 } }
end

local function lightbar(r, g, b)
    return { type = 2, parameters = { 0, r, g, b } }
end

local function profile(...)
    return { instructions = { ... } }
end

local MAPPING = {}

-- Default: light L2 spring, untouched R2.
MAPPING.default = profile(
    l2_resistance(3),
    r2_normal(),
    lightbar(0, 0, 0)
)

-- Handguns: light aim pull, R2 maxed out (the hardware's absolute ceiling
-- so every pistol shot feels like a hard, distinct break).
MAPPING["type:hg"] = profile(
    l2_resistance(3),
    r2_weapon(0, 9, 8),
    lightbar(0, 120, 255)
)

-- Crossbow: stiffer aim pull, slightly softer late break than handguns.
local crossbow_profile = profile(
    l2_resistance(5),
    r2_weapon(5, 9, 6),
    lightbar(0, 255, 255)
)
MAPPING["type:xbow"] = crossbow_profile
MAPPING["type:bowgun"] = crossbow_profile

-- Shotguns: heavy aim pull, snappy bow-mode break.
MAPPING["type:sg"] = profile(
    l2_resistance(6),
    r2_bow(0, 6, 8, 8),
    lightbar(255, 40, 40)
)

-- Magnums: heaviest sustained pull this side of throwables, full-travel
-- elastic break.
local magnum_profile = profile(
    l2_resistance(6),
    r2_bow(0, 8, 8, 8),
    lightbar(180, 0, 255)
)
MAPPING["type:mag"] = magnum_profile
MAPPING["type:magnum"] = magnum_profile

-- SMGs / CQBR: light aim pull, buzzy vibrate-on-fire to sell full-auto.
local rapid_fire_profile = profile(
    l2_resistance(2),
    r2_vibrate(20),
    lightbar(255, 140, 0)
)
MAPPING["type:smg"] = rapid_fire_profile
MAPPING.cqbr = rapid_fire_profile

-- Bolt-action / semi-auto rifles: same heavy elastic break as magnums.
local rifle_profile = profile(
    l2_resistance(6),
    r2_bow(0, 8, 8, 8),
    lightbar(255, 255, 0)
)
MAPPING["type:sr"] = rifle_profile
MAPPING["type:rf"] = rifle_profile

-- Throwables: max-resistance pull-and-release pin pull, weighted release.
local throwable_profile = profile(
    l2_resistance(8),
    r2_resistance(4),
    lightbar(0, 255, 0)
)
MAPPING["type:grenade"] = throwable_profile
MAPPING["type:thrw"] = throwable_profile

-- Knife: faint aim resistance, no R2 shaping.
local knife_profile = profile(
    l2_resistance(1),
    r2_normal(),
    lightbar(255, 255, 255)
)
MAPPING["type:knf"] = knife_profile
MAPPING["type:knife"] = knife_profile

return MAPPING
