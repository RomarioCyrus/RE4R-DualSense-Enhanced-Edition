-- Item ID names/categories used by pickup diagnostics and future sound mapping.
-- Base IDs come from the confirmed Auto Pick Up Items v1.3 whitelist.

local ITEMS = {}

-- Bulk-categorized 2025-06-29 from CH_ITEM_NAME_LOOKUP.json (eng table),
-- mechanically by ID range matching the categories already wired to sounds
-- in audio_feedback.lua's PICKUP_EVENT_BY_CATEGORY. Not individually verified
-- in-game (no per-item audio testing) -- only the bucket assignment is
-- reviewed, since pickup sound is per-category, not per-item.
local BY_ID = {
    [124000000] = {"Pesetas", "pesetas"},

    [112800000] = {"Handgun Ammo", "ammo"},
    [112801600] = {"Magnum Ammo", "ammo"},
    [112803200] = {"Shotgun Shells", "ammo"},
    [112804800] = {"Rifle Ammo", "ammo"},
    [112806400] = {"Submachine Gun Ammo", "ammo"},
    [112808000] = {"Bolts", "ammo"},
    [117603200] = {"Attachable Mines", "ammo"},
    [112320000] = {"Explosive Arrows (Mercenaries)", "ammo"},
    [112480000] = {"Explosive Arrows (Separate Ways)", "ammo"},
    [127361600] = {"Handgun Ammo (pre-order)", "ammo"},

    [277075456] = {"Hand Grenade", "grenades"},
    [277077056] = {"Heavy Grenade", "grenades"},
    [277078656] = {"Flash Grenade", "grenades"},

    [114400000] = {"Green Herb", "healing"},
    [114401600] = {"Red Herb", "healing"},
    [114403200] = {"Yellow Herb", "healing"},
    [114404800] = {"Mixed Herb (G+G)", "healing"},
    [114406400] = {"Mixed Herb (G+G+G)", "healing"},
    [114408000] = {"Mixed Herb (G+R)", "healing"},
    [114409600] = {"Mixed Herb (G+Y)", "healing"},
    [114411200] = {"Mixed Herb (R+Y)", "healing"},
    [114412800] = {"Mixed Herb (G+R+Y)", "healing"},
    [114414400] = {"Mixed Herb (G+G+Y)", "healing"},
    [114416000] = {"First Aid Spray", "healing"},
    [114417600] = {"Black Bass", "healing"},
    [114419200] = {"Lunker Bass", "healing"},
    [114420800] = {"Black Bass (L)", "healing"},
    [114422400] = {"Viper", "healing"},
    [114424000] = {"Rhinoceros Beetle", "healing"},
    [277080256] = {"Chicken Egg", "healing"},
    [277081856] = {"Brown Chicken Egg", "healing"},
    [277083456] = {"Gold Chicken Egg", "healing"},

    [117600000] = {"Gunpowder", "resources"},
    [117601600] = {"Resources (L)", "resources"},
    [117604800] = {"Broken Knife", "resources"},
    [117606400] = {"Resources (S)", "resources"},

    [276435456] = {"Combat Knife", "knives"},
    [276437056] = {"Fighting Knife", "knives"},
    [276438656] = {"Kitchen Knife", "knives"},
    [276440256] = {"Boot Knife", "knives"},
    [276445056] = {"Primal Knife", "knives"},

    [120800000] = {"Spinel", "valuables"},
    [120801600] = {"Pearl Pendant", "valuables"},
    [120803200] = {"Dirty Pearl Pendant", "valuables"},
    [120809600] = {"Brass Pocket Watch", "valuables"},
    [120812800] = {"Elegant Headdress", "valuables"},
    [120814400] = {"Antique Pipe", "valuables"},
    [120816000] = {"Pearl Bangle", "valuables"},
    [120817600] = {"Red Gemstone Ring", "valuables"},
    [120819200] = {"Gold Bangle", "valuables"},
    [120820800] = {"Iluminados Pendant", "valuables"},
    [120822400] = {"Mirror with Pearls & Rubies", "valuables"},
    [120824000] = {"Golden Hourglass", "valuables"},
    [120825600] = {"Elegant Perfume Bottle", "valuables"},
    [120827200] = {"Elegant Chessboard", "valuables"},
    [120828800] = {"Staff of Royalty", "valuables"},
    [120830400] = {"Ruby", "valuables"},
    [120832000] = {"Emerald", "valuables"},
    [120833600] = {"Sapphire", "valuables"},
    [120835200] = {"Yellow Diamond", "valuables"},
    [120838400] = {"Alexandrite", "valuables"},
    [120840000] = {"Gold Bar", "valuables"},
    [120841600] = {"Gold Bar (L)", "valuables"},
    [120843200] = {"Gold Ingot", "valuables"},
    [120844800] = {"Depraved Idol", "valuables"},
    [120846400] = {"Vintage Compass", "valuables"},
    [120848000] = {"Justitia Statue", "valuables"},
    [120849600] = {"Crystal Ore", "valuables"},
    [120851200] = {"Ornate Beetle", "valuables"},
    [120852800] = {"Mendez's False Eye", "valuables"},
    [120854400] = {"Gold Monocle", "valuables"},
    [120856000] = {"Lip Rouge", "valuables"},
    [120857600] = {"Red Beryl", "valuables"},
    [120860800] = {"Antique Camera", "valuables"},
    [120864000] = {"Velvet Blue", "valuables"},
    [120865600] = {"Scratched Emerald", "valuables"},
    [122400000] = {"Elegant Mask", "valuables"},
    [122401600] = {"Flagon", "valuables"},
    [122403200] = {"Butterfly Lamp", "valuables"},
    [122404800] = {"Elegant Crown", "valuables"},
    [122406400] = {"Golden Lynx", "valuables"},
    [122408000] = {"Extravagant Clock", "valuables"},
    [122409600] = {"Splendid Bangle", "valuables"},
    [122411200] = {"Chalice of Atonement", "valuables"},
    [122412800] = {"Ornate Necklace", "valuables"},
    [122416000] = {"Elegant Bangle", "valuables"},

    -- Key items: doors/puzzles/quest progression. Body armor, treasure
    -- maps, and the one-off accessory unlock are bucketed here too --
    -- single-use special pickups, not crafting upgrades.
    [119203200] = {"Hexagonal Emblem", "key_items"},
    [119204800] = {"Insignia Key", "key_items"},
    [119206400] = {"Halo Wheel", "key_items"},
    [119209600] = {"Crimson Lantern", "key_items"},
    [119211200] = {"Level 1 Keycard", "key_items"},
    [119212800] = {"Level 2 Keycard", "key_items"},
    [119214400] = {"Level 3 Keycard", "key_items"},
    [119217600] = {"Crystal Marble", "key_items"},
    [119219200] = {"Wrench", "key_items"},
    [119220800] = {"Salazar Family Insignia", "key_items"},
    [119222400] = {"Lion Head", "key_items"},
    [119224000] = {"Goat Head", "key_items"},
    [119225600] = {"Serpent Head", "key_items"},
    [119230400] = {"Blasphemer's Head", "key_items"},
    [119232000] = {"Apostate's Head", "key_items"},
    [119235200] = {"Wooden Cog", "key_items"},
    [119236800] = {"Dynamite", "key_items"},
    [119238400] = {"Luis's Key", "key_items"},
    [119244800] = {"Small Key", "key_items"},
    [119246400] = {"Checkpoint Crank", "key_items"},
    [119248000] = {"Hexagon Piece A", "key_items"},
    [119249600] = {"Hexagon Piece B", "key_items"},
    [119251200] = {"Hexagon Piece C", "key_items"},
    [119254400] = {"Dungeon Key", "key_items"},
    [119256000] = {"Old Wayshrine Key", "key_items"},
    [119257600] = {"Church Insignia", "key_items"},
    [119259200] = {"Water Scooter Key", "key_items"},
    [119260800] = {"Golden Sword", "key_items"},
    [119262400] = {"Iron Sword", "key_items"},
    [119265600] = {"Lithographic Stone A", "key_items"},
    [119267200] = {"Lithographic Stone B", "key_items"},
    [119268800] = {"Lithographic Stone C", "key_items"},
    [119270400] = {"Lithographic Stone D", "key_items"},
    [119273600] = {"Boat Fuel", "key_items"},
    [119275200] = {"Bunch of Keys", "key_items"},
    [119276800] = {"Cubic Device", "key_items"},
    [119278400] = {"Bloodied Sword", "key_items"},
    [119280000] = {"Rusted Sword", "key_items"},
    [119281600] = {"Hunter's Lodge Key", "key_items"},
    [119283200] = {"Unicorn Horn", "key_items"},
    [119284800] = {"Blue Dial", "key_items"},
    [119286400] = {"Silver Token", "key_items"},
    [119288000] = {"Gold Token", "key_items"},
    [119289600] = {"Wooden Planks", "key_items"},
    [124001600] = {"Body Armor", "key_items"},
    [124003200] = {"Treasure Map: Village", "key_items"},
    [124004800] = {"Treasure Map: Castle", "key_items"},
    [124006400] = {"Treasure Map: Island", "key_items"},
    [124644800] = {"Accessory: Sunglasses (Cat Eye)", "key_items"},

    -- Case upgrades and crafting recipes: new category, no sound wired
    -- yet (pickup_upgrade not in PICKUP_EVENT_BY_CATEGORY until a real
    -- WAV is sourced).
    [124160000] = {"Case Upgrade (7x10)", "case_upgrades"},
    [124161600] = {"Case Upgrade (7x12)", "case_upgrades"},
    [124163200] = {"Case Upgrade (8x12)", "case_upgrades"},
    [124164800] = {"Case Upgrade (8x13)", "case_upgrades"},
    [124166400] = {"Case Upgrade (9x13)", "case_upgrades"},
    [124176000] = {"Attache Case: Silver", "case_upgrades"},
    [124177600] = {"Attache Case: Black", "case_upgrades"},
    [124179200] = {"Attache Case: Leather", "case_upgrades"},
    [124321600] = {"Recipe: Handgun Ammo", "case_upgrades"},
    [124323200] = {"Recipe: Shotgun Shells", "case_upgrades"},
    [124324800] = {"Recipe: Submachine Gun Ammo", "case_upgrades"},
    [124326400] = {"Recipe: Rifle Ammo", "case_upgrades"},
    [124328000] = {"Recipe: Magnum Ammo", "case_upgrades"},
    [124329600] = {"Recipe: Bolts", "case_upgrades"},
    [124331200] = {"Recipe: Bolts", "case_upgrades"},
    [124334400] = {"Recipe: Attachable Mines", "case_upgrades"},
    [124336000] = {"Recipe: Heavy Grenade", "case_upgrades"},
    [124337600] = {"Recipe: Flash Grenade", "case_upgrades"},
    [124353600] = {"Recipe: Mixed Herb (G+G)", "case_upgrades"},
    [124355200] = {"Recipe: Mixed Herb (G+R)", "case_upgrades"},
    [124356800] = {"Recipe: Mixed Herb (G+Y)", "case_upgrades"},
    [124358400] = {"Recipe: Mixed Herb (R+Y)", "case_upgrades"},
    [124360000] = {"Recipe: Mixed Herb (G+G+G)", "case_upgrades"},
    [124361600] = {"Recipe: Mixed Herb (G+G+Y)", "case_upgrades"},
    [124363200] = {"Recipe: Mixed Herb (G+G+Y)", "case_upgrades"},
    [124364800] = {"Recipe: Mixed Herb (G+R+Y)", "case_upgrades"},
    [124366400] = {"Recipe: Mixed Herb (G+R+Y)", "case_upgrades"},
    [124368000] = {"Recipe: Mixed Herb (G+R+Y)", "case_upgrades"},

    -- Weapon attachments: new category, no sound wired yet.
    [116000000] = {"Scope", "attachments"},
    [116001600] = {"Red9 Stock", "attachments"},
    [116003200] = {"High-power Scope", "attachments"},
    [116004800] = {"Biosensor Scope", "attachments"},
    [116006400] = {"TMP Stock", "attachments"},
    [116008000] = {"Laser Sight", "attachments"},
    [116009600] = {"Matilda Stock", "attachments"},

    -- Weapons picked up directly off the ground (not the in-menu weapon
    -- list): new category, no sound wired yet.
    [274835456] = {"SG-09 R", "weapons"},
    [274837056] = {"Punisher", "weapons"},
    [274838656] = {"Red9", "weapons"},
    [274840256] = {"Blacktail", "weapons"},
    [274841856] = {"Matilda", "weapons"},
    [274843456] = {"Minecart Handgun", "weapons"},
    [274995456] = {"W-870", "weapons"},
    [274997056] = {"Riot Gun", "weapons"},
    [274998656] = {"Striker", "weapons"},
    [275155456] = {"TMP", "weapons"},
    [275157056] = {"Chicago Sweeper", "weapons"},
    [275158656] = {"LE 5", "weapons"},
    [275475456] = {"SR M1903", "weapons"},
    [275477056] = {"Stingray", "weapons"},
    [275478656] = {"CQBR Assault Rifle", "weapons"},
    [275635456] = {"Broken Butterfly", "weapons"},
    [275637056] = {"Killer7", "weapons"},
    [275638656] = {"Handcannon", "weapons"},
    [275795456] = {"Bolt Thrower", "weapons"},
    [276275456] = {"Rocket Launcher", "weapons"},
    [276277056] = {"Rocket Launcher (Special)", "weapons"},
    [276278656] = {"Infinite Rocket Launcher", "weapons"},

    -- Mercenaries figure collectibles: deliberately uncategorized into any
    -- sound bucket (no pickup sound wanted for these per user request).
    -- "figure" is intentionally absent from PICKUP_EVENT_BY_CATEGORY.
    [127200000] = {"Figure: Don Jose", "figure"},
    [127201600] = {"Figure: Don Diego", "figure"},
    [127203200] = {"Figure: Don Esteban", "figure"},
    [127204800] = {"Figure: Don Manuel", "figure"},
    [127206400] = {"Figure: Isabel", "figure"},
    [127208000] = {"Figure: Maria", "figure"},
    [127209600] = {"Figure: Dr. Salvador", "figure"},
    [127211200] = {"Figure: Bella Sisters", "figure"},
    [127212800] = {"Figure: Don Pedro", "figure"},
    [127214400] = {"Figure: Zealot w/ scythe", "figure"},
    [127216000] = {"Figure: Zealot w/ shield", "figure"},
    [127217600] = {"Figure: Zealot w/ bowgun", "figure"},
    [127219200] = {"Figure: Leader zealot", "figure"},
    [127220800] = {"Figure: Soldier w/ dynamite", "figure"},
    [127222400] = {"Figure: Soldier w/ stun-rod", "figure"},
    [127224000] = {"Figure: Soldier w/ hammer", "figure"},
    [127225600] = {"Figure: J.J.", "figure"},
    [127227200] = {"Figure: Leon w/ handgun", "figure"},
    [127228800] = {"Figure: Leon w/ shotgun", "figure"},
    [127230400] = {"Figure: Leon w/ rocket launcher", "figure"},
    [127232000] = {"Figure: Merchant", "figure"},
    [127233600] = {"Figure: Ashley Graham", "figure"},
    [127235200] = {"Figure: Luis Sera", "figure"},
    [127236800] = {"Figure: Ada Wong", "figure"},
    [127238400] = {"Figure: Chicken", "figure"},
    [127240000] = {"Figure: Black Bass", "figure"},
    [127241600] = {"Figure: Rhinoceros Beetle", "figure"},
    [127243200] = {"Figure: Iluminados Emblem", "figure"},
    [127244800] = {"Figure: Striker", "figure"},
    [127246400] = {"Figure: Cute Bear", "figure"},
}

local function numeric_id(value)
    local number = tonumber(value)
    if not number then return nil end
    return math.floor(number)
end

function ITEMS.resolve(raw_id)
    local raw = numeric_id(raw_id)
    if not raw then return nil end

    local exact = BY_ID[raw]
    if exact then
        return {
            raw_id = raw,
            base_id = raw,
            name = exact[1],
            category = exact[2],
            normalized = false,
        }
    end

    -- Some DropItem IDs contain a low variant/stack component. Confirmed
    -- example: 114400160 resolves to base ID 114400000 (Green Herb).
    local base = math.floor(raw / 1600) * 1600
    local normalized = BY_ID[base]
    if normalized then
        return {
            raw_id = raw,
            base_id = base,
            name = normalized[1],
            category = normalized[2],
            normalized = true,
        }
    end

    return {
        raw_id = raw,
        base_id = base,
        name = "Unknown Item",
        category = "unknown",
        normalized = base ~= raw,
    }
end

ITEMS.by_id = BY_ID
_G.DualSenseEnhancedItemIDs = ITEMS

