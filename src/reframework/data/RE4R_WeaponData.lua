-- Weapon ID -> display name / category lookup for the main campaign
-- loadout. Sourced from this project's own id_database research
-- (id_database/CH_WEAPON_NAME_LOOKUP.json, "eng" table) plus the weapon
-- categorization already documented in docs/weapon_audio_catalog/ and
-- MEMORY.md, not copied from any third-party mod's data file.
--
-- Only the fields weapon_equip_core.lua actually reads (Enum/Name/Type)
-- need to be accurate; ID/Game are kept for readability and possible
-- future use. Type values mirror RE4R's own internal weapon-type enum
-- abbreviations (HG/SG/SMG/SR/MAG/XBOW/THRW/KNF/GL), not an invention of
-- any specific mod author.

local function entry(short_id, enum, name, kind)
    return {
        ID = short_id,
        Enum = enum,
        Name = name,
        Type = kind,
        Game = "Main",
    }
end

local ENTRIES = {
    -- Handguns
    entry("wp4000", 4000, "SG-09 R",          "HG"),
    entry("wp4001", 4001, "Punisher",         "HG"),
    entry("wp4002", 4002, "Red9",             "HG"),
    entry("wp4003", 4003, "Blacktail",        "HG"),
    entry("wp4004", 4004, "Matilda",          "HG"),
    entry("wp6000", 6000, "Sentinel Nine",    "HG"),

    -- Shotguns
    entry("wp4100", 4100, "W-870",            "SG"),
    entry("wp4101", 4101, "Riot Gun",         "SG"),
    entry("wp4102", 4102, "Striker",          "SG"),
    entry("wp6001", 6001, "Skull Shaker",     "SG"),

    -- SMGs
    entry("wp4200", 4200, "TMP",              "SMG"),
    entry("wp4201", 4201, "Chicago Sweeper",  "SMG"),
    entry("wp4202", 4202, "LE 5",             "SMG"),

    -- Rifles
    entry("wp4400", 4400, "SR M1903",         "SR"),
    entry("wp4401", 4401, "Stingray",         "SR"),
    entry("wp4402", 4402, "CQBR Assault Rifle", "SR"),

    -- Magnums
    entry("wp4500", 4500, "Broken Butterfly", "MAG"),
    entry("wp4501", 4501, "Killer7",          "MAG"),
    entry("wp4502", 4502, "Handcannon",       "MAG"),

    -- Crossbow
    entry("wp4600", 4600, "Bolt Thrower",     "XBOW"),

    -- Launchers (no dedicated trigger profile; fall back to default)
    entry("wp4900", 4900, "Rocket Launcher",          "GL"),
    entry("wp4902", 4902, "Infinite Rocket Launcher",  "GL"),

    -- Knives
    entry("wp5000", 5000, "Combat Knife",     "KNF"),
    entry("wp5001", 5001, "Fighting Knife",   "KNF"),
    entry("wp5006", 5006, "Primal Knife",     "KNF"),

    -- Throwables
    entry("wp5400", 5400, "Hand Grenade",        "THRW"),
    entry("wp5401", 5401, "Heavy Grenade",       "THRW"),
    entry("wp5402", 5402, "Flash Grenade",       "THRW"),
    entry("wp5403", 5403, "Chicken Egg",         "THRW"),
    entry("wp5404", 5404, "Brown Chicken Egg",   "THRW"),
    entry("wp5405", 5405, "Gold Chicken Egg",    "THRW"),
}

local Weapons = {}
for _, w in ipairs(ENTRIES) do
    Weapons[w.ID] = w
end

return {
    Weapons = Weapons,
}
