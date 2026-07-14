local re = re
local io = io
local os = os
local pcall = pcall

_G.DualSenseEnhancedAudioGeneration = (_G.DualSenseEnhancedAudioGeneration or 0) + 1
local generation = _G.DualSenseEnhancedAudioGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedAudioGeneration == generation
end

-- ================================================================
-- audio_feedback.lua
-- Emits small JSON events for DualsenseAudioBridge.exe.
-- REFramework data I/O is rooted at reframework/data, so this writes
-- directly to <game>/reframework/data/audio_events.json.
-- ================================================================

local AUDIO = {}
AUDIO.enabled = true
AUDIO.events_file = "audio_events.json"
AUDIO.devices_file = "DualSenseEnhanced/audio_devices.json"

-- The events file is append-only NDJSON (one JSON object per line), read by
-- DualsenseAudioBridge.exe as a growing log rather than a single
-- overwritten file. This avoids a race where two emits close together
-- could be coalesced into a single FileSystemWatcher notification and the
-- earlier write silently lost. Truncate on script (re)load so a fresh
-- session doesn't replay leftover events from a previous run.
pcall(function()
    local file = io.open(AUDIO.events_file, "wb")
    if file then file:close() end
end)
AUDIO.test_event = "parry"
AUDIO.heal_enabled = true
AUDIO.parry_enabled = true
AUDIO.fatal_kick_enabled = true
AUDIO.knife_hit_enabled = true
AUDIO.reload_enabled = true
AUDIO.reload_session_active = false
AUDIO.reload_insert_grace = 0
AUDIO.reload_finish_played = false
AUDIO.deferred_postshot = {}
AUDIO.pickup_enabled = true
AUDIO.qte_enabled = true
AUDIO.pickup_debug_enabled = false
AUDIO.device_index = 1
AUDIO.device_mode = "auto" -- "auto" | "manual" | "legacy"
AUDIO.manual_device_index = 1
AUDIO.manual_device_id = ""
AUDIO.manual_device_label = ""
AUDIO.manual_devices = {}
AUDIO.devices_status = "not loaded"
AUDIO.devices_count = 0
AUDIO.volume = 0.85
-- Enhanced Haptics (docs/HAPTICS_FOOTSTEPS_TASK.md). Footstep source
-- switched 2026-07-13 to audio-to-haptics: the real Leon footstep SFX
-- (ch_cha0.bnk event 1528453721, extracted via tools/extract_sounds/ +
-- tools/audio_to_haptic.py's low-pass/trim/normalize) instead of a
-- synthesized gated-sine tone -- live-confirmed clearly better than synth
-- ("реальный звук однозначно лучше"). The original synthesized WAVs
-- (haptic_footstep*.wav) are kept on disk as the A/B reference in the debug
-- UI, not deleted.
--
-- Intensity used to be 3 discrete WAV presets (soft/normal/strong); now a
-- single continuous 0..1 slider sent to the bridge as "haptic_intensity" in
-- the event payload, which HapticPlayer.cs maps live to a low-pass cutoff +
-- gain (see QuadRouteSampleProvider) -- true continuous control instead of
-- picking between pre-baked variants, since felt intensity is driven by
-- frequency, not just gain.
AUDIO.haptic_intensity = 0.6
AUDIO.FOOTSTEP_HAPTIC_EVENT = "haptic_footstep_real"

-- User feedback 2026-07-13: on PS5, native footstep haptics stay in the
-- background -- much weaker than combat/weapon pulses -- which is why they
-- don't feel like constant noise while just walking around. Our footsteps
-- fire on the same 0..1 slider as everything else, so slider=1 hit far
-- harder than the PS5 reference; slider=0 was the closest match. Scale the
-- slider down before sending it for footstep events only, so the slider's
-- upper end still keeps footsteps subtle while parry/impact/etc keep full
-- range at slider=1.
AUDIO.FOOTSTEP_INTENSITY_SCALE = 0.35

-- Per-category enable toggles, all on by default. "footsteps" gates
-- play_footstep_haptic() directly; the rest gate entries in
-- COMPANION_HAPTIC_PATTERNS below via each entry's `category` field.
AUDIO.haptic_category_enabled = {
    footsteps = true,
    parry = true,
    knife = true,
    dry_fire = true,
    aim = true,
    draw = true,
    heal = true,
    pickup = true,
}
AUDIO.haptic_category_intensity = {
    footsteps = 1.0,
    parry = 1.0,
    knife = 1.0,
    dry_fire = 1.0,
    aim = 1.0,
    draw = 1.0,
    heal = 1.0,
    pickup = 1.0,
}
AUDIO.HAPTIC_CATEGORY_LABELS = {
    {key = "footsteps", label = "Footsteps"},
    {key = "parry", label = "Parry"},
    {key = "knife", label = "Knife Hits"},
    {key = "dry_fire", label = "Dry Fire"},
    {key = "aim", label = "Aim In/Out"},
    {key = "draw", label = "Weapon Draw"},
    {key = "heal", label = "Healing"},
    {key = "pickup", label = "Item Pickup"},
}
AUDIO.device_options = {
    {label = "Auto", value = ""},
    {label = "DualSense", value = "DualSense Wireless Controller"},
    {label = "DualSense Edge", value = "DualSense Edge Wireless Controller"},
}
AUDIO.heal_cooldown_frames = 10   -- blocks same-heal double HP ticks only (~0.16s at 60fps)
AUDIO.last_error = nil
AUDIO.last_event = nil
AUDIO.last_status = "ready"
AUDIO.haptic_test_status = "Not tested"
AUDIO.pickup_hook_status = "not installed"
AUDIO.last_pickup_id = nil
AUDIO.last_pickup_base_id = nil
AUDIO.last_pickup_name = nil
AUDIO.last_pickup_category = nil
AUDIO.last_pickup_type = nil
AUDIO.last_pickup_args = nil
AUDIO.last_pickup_event = nil
AUDIO.pickup_count = 0
AUDIO.bridge_path = "reframework\\data\\DualSenseEnhanced\\DualsenseAudioBridge.exe"
AUDIO.bridge_status = "launcher plugin"

local heal_cooldown = 0
local event_sequence = 0
local pickup_hooks_installed = false
local item_use_hook_installed = false
local last_used_item_id = nil

local HERB_IDS = {
    [114400000] = true,  -- Green Herb
    [114401600] = true,  -- Red Herb
    [114403200] = true,  -- Yellow Herb
    [114404800] = true,  -- Mixed (G+G)
    [114406400] = true,  -- Mixed (G+G+G)
    [114408000] = true,  -- Mixed (G+R)
    [114409600] = true,  -- Mixed (G+Y)
    [114411200] = true,  -- Mixed (R+Y)
    [114412800] = true,  -- Mixed (G+R+Y)
    [114414400] = true,  -- Mixed (G+G+Y)
}
local EGG_STEMS = {
    [277080000] = "heal_egg",        -- Chicken Egg      (raw 277080256)
    [277081600] = "heal_egg_brown",  -- Brown Chicken Egg (raw 277081856)
    [277083200] = "heal_egg_gold",   -- Gold Chicken Egg  (raw 277083456)
}
local FISH_STEMS = {
    [114417600] = "heal_fish",        -- Black Bass
    [114419200] = "heal_fish_lunker", -- Lunker Bass
    [114420800] = "heal_fish_large",  -- Black Bass (L)
    [114422400] = "heal_viper",       -- Viper
    [114424000] = "heal_beetle",      -- Rhinoceros Beetle
}
AUDIO.heal_rare_always = false  -- set true to force rare sound (testing)
local pickup_candidates = {}
local device_refresh_timer = 0

local RELOAD_EVENTS_BY_WEAPON = {
    [4000] = {
        start = "wp4000_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0246 candidate route in wwise_audio_router.lua
        -- (weapon_id=4000), because the previously catalogued event_0271
        -- never fired in live capture and ammo-delta polling misses the
        -- already-full re-chamber edge case. Pending speaker confirmation.
        -- Preliminary game test: no separate finish sound.
    },
    [4001] = {
        start = "wp4001_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0260 candidate route in wwise_audio_router.lua
        -- (weapon_id=4001); ammo-delta polling missed the already-full
        -- re-chamber edge case at 12/12.
    },
    [4002] = {
        start = "wp4002_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0240 candidate route in wwise_audio_router.lua
        -- (weapon_id=4002), same bug family as wp4000/wp4001/wp4003.
    },
    [4003] = {
        start = "wp4003_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the confirmed Wwise event_0268 route in wwise_audio_router.lua
        -- (weapon_id=4003), because ammo-delta polling misses the case
        -- where the mag is already full and only the chamber is refilled.
    },
    [4004] = {
        start = "wp4004_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0238 candidate route in wwise_audio_router.lua
        -- (weapon_id=4004), same bug family as wp4000/wp4001/wp4002/wp4003.
    },
    [4100] = {
        -- Pump-open/pump-close normally belong to the post-shot cycle.
        -- After the last shot the cycle is deferred until reload completion.
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0215 candidate route in wwise_audio_router.lua
        -- (weapon_id=4100), confirmed to repeat once per shell.
    },
    [4101] = {
        start = "wp4101_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0220 candidate route in wwise_audio_router.lua
        -- (weapon_id=4101), confirmed to repeat once per shell.
        -- Preliminary game test: no separate finish sound.
    },
    [4102] = {
        start = "wp4102_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0208 candidate route in wwise_audio_router.lua
        -- (weapon_id=4102), confirmed to repeat once per shell.
    },
    [4400] = {
        start = "wp4400_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0241 candidate route in wwise_audio_router.lua
        -- (weapon_id=4400), confirmed to repeat once per shell.
        -- Bolt cycle is deferred to reload completion after the last shot.
        -- finish_on_full_insert mirrors wp4500/wp4502 (which use the same
        -- deferred-postshot mechanism): it makes ammo_led.lua call
        -- play_reload_finish ~0.1s after ammo reaches max, instead of
        -- waiting on the much slower reload-exit confirmation polling in
        -- events_led.lua (which lagged by close to a second).
        finish_on_full_insert = true,
    },
    [4401] = {
        start = "wp4401_reload_start",
        -- finish removed: the previous wp4401_reload_finish WAV was never
        -- tied to any confirmed Wwise event (the catalog's event_0231 guess
        -- was untested) and the user heard it as an extra/wrong bolt sound
        -- after the real mechanical sequence (event_0242/0240/0252/0248)
        -- already finished.
    },
    [4402] = {
        -- No start/insert/finish keys: the user rejected the hook-triggered
        -- start sound and the event_0216 insert candidate entirely. The
        -- confirmed sequence (event_0210 -> event_0231 -> event_0235) is
        -- driven directly by wwise_audio_router.lua (weapon_id=4402); this
        -- empty table is kept only so reload_events() still returns a
        -- valid (non-nil) entry for the existing hook/session bookkeeping.
    },
    [4500] = {
        -- start/insert/finish are intentionally NOT keyed here: all three
        -- are driven directly by the event_0191/event_0197/event_0193
        -- routes in wwise_audio_router.lua (weapon_id=4500). The
        -- hook-triggered start fired ~0.9s before the catalog-confirmed
        -- "Reload Open" cartridge-ejection sound (event_0191), which the
        -- user heard as too early; event_0191 replaces it directly.
        -- event_0197 does not fire on a live shot outside reload (unlike
        -- wp4100/wp4400's post-shot cues); the separate post-shot action
        -- still uses the old fixed-delay timer (no live ID exists for it).
    },
    [4501] = {
        start = "wp4501_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0214 candidate route in wwise_audio_router.lua
        -- (weapon_id=4501), same bug family as wp4000/wp4001/wp4003/wp4501.
    },
    [4502] = {
        -- start/insert/finish WAV emission is intentionally NOT keyed here:
        -- all three are driven directly by the event_0226/event_0198/
        -- event_0224 routes in wwise_audio_router.lua (weapon_id=4502).
        -- The hook-triggered start fired ~0.9s before the catalog-confirmed
        -- "cylinder cartridge ejection" sound (event_0226), which the user
        -- heard as too early; event_0226 replaces it directly.
        -- finish_on_full_insert stays true so the fast ammo-path still
        -- calls play_reload_finish (needed for the deferred post-shot
        -- consume after an empty-shot reload); it just no longer
        -- self-emits the finish WAV directly.
        finish_on_full_insert = true,
    },
    [6001] = {
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0229 candidate route in wwise_audio_router.lua
        -- (weapon_id=6001), confirmed to repeat once per shell.
        -- finish WAV emission is intentionally NOT keyed here either: it is
        -- driven directly by the event_0219 route in wwise_audio_router.lua
        -- (weapon_id=6001), the later of two ambiguous post-tick candidates
        -- (event_0209/event_0219; neither catalog label clearly means
        -- finish, picked as the last-firing one). No deferred-postshot use
        -- for this weapon, so finish_on_full_insert is no longer needed.
    },
    [6000] = {
        start = "wp6000_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_id=1498116241 route in wwise_audio_router.lua
        -- (weapon_id=6000), same approach as wp4000 (SG-09 R), which this
        -- weapon is mechanically near-identical to. Unlike the other
        -- weapons, this ID was never cross-checked against wp6000's own
        -- Wwise bank (not yet extracted) or any catalog -- low confidence,
        -- pending speaker confirmation. WAV assets are reused from wp4000
        -- as temporary placeholders.
    },
    [4200] = {
        start = "wp4200_reload_start",
        -- insert/finish are intentionally NOT keyed here: they are driven
        -- directly by the event_0234/event_0242 routes in
        -- wwise_audio_router.lua (weapon_id=4200). First-time mapping for
        -- TMP (no prior catalog); WAV assets extracted directly from the
        -- matching wem sources, pending speaker confirmation.
    },
    [4202] = {
        start = "wp4202_reload_start",
        -- insert/finish are intentionally NOT keyed here: they are driven
        -- directly by the event_0226/event_0258 routes in
        -- wwise_audio_router.lua (weapon_id=4202). First-time mapping for
        -- LE 5 (no prior catalog); WAV assets extracted directly from the
        -- matching wem sources, pending speaker confirmation.
    },
    [4201] = {
        start = "wp4201_reload_start",
        -- insert/finish are intentionally NOT keyed here: they are driven
        -- directly by the event_0242/event_0236 routes in
        -- wwise_audio_router.lua (weapon_id=4201). First-time mapping for
        -- Chicago Sweeper (no prior catalog); WAV assets extracted directly
        -- from the matching wem sources, pending speaker confirmation.
    },
    [4600] = {
        start = "wp4600_reload_start",
        -- insert is intentionally NOT keyed here: it is driven directly by
        -- the event_0260 route in wwise_audio_router.lua (weapon_id=4600).
        -- First-time mapping for Bolt Thrower (no prior catalog); no
        -- reliable finish candidate was found (the only post-tick
        -- candidate, event_0283, also fires before the tick and on other
        -- handling actions, so it was excluded). WAV assets extracted
        -- directly from the matching wem sources, pending speaker
        -- confirmation.
    },
}

local PICKUP_EVENT_BY_ID = {
    [124000000] = "pickup_pesetas",
    [119244800] = "pickup_key_item",
}

local PICKUP_EVENT_BY_CATEGORY = {
    ammo = "pickup_ammo",
    healing = "pickup_healing",
    resources = "pickup_metal",
    grenades = "pickup_metal",
    knives = "pickup_metal",
    -- valuables: no sound for v1.0 (correct WEM not identified)
    key_items = "pickup_key_item",
}

local function object_address(obj)
    if not obj then return nil end
    local address = nil
    pcall(function()
        if obj.get_address then
            address = tostring(obj:get_address())
        else
            address = tostring(sdk.to_int64(obj))
        end
    end)
    return address
end

local function context_id_text(value)
    if value == nil then return nil end
    local fields = {}
    pcall(function()
        local type_def = value:get_type_definition()
        for _, field in ipairs(type_def and type_def:get_fields() or {}) do
            local name = field:get_name()
            local field_value = field:get_data(value)
            fields[#fields + 1] = tostring(name) .. "=" .. tostring(field_value)
        end
    end)
    if #fields > 0 then
        table.sort(fields)
        return table.concat(fields, ",")
    end
    return tostring(value)
end

local function remember_pickup_candidate(drop_item)
    if not drop_item then return end
    local address = object_address(drop_item)
    if not address then return end

    local item_id = nil
    local context_id = nil
    pcall(function() item_id = drop_item:call("getItemID") end)
    pcall(function() context_id = context_id_text(drop_item._ID) end)

    pickup_candidates[address] = {
        object = drop_item,
        item_id = item_id,
        context_id = context_id,
        seen_at = os.clock(),
    }
end

local function find_pickup_candidate(context_id)
    local wanted = context_id_text(context_id)
    local now = os.clock()
    local found = nil

    for address, candidate in pairs(pickup_candidates) do
        if (now - candidate.seen_at) > 10 then
            pickup_candidates[address] = nil
        elseif wanted and candidate.context_id == wanted then
            found = candidate
            break
        end
    end

    return found, wanted
end

local function json_escape(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub('"', '\\"')
    text = text:gsub("\r", "\\r")
    text = text:gsub("\n", "\\n")
    return text
end

local function json_unescape(text)
    text = tostring(text or "")
    text = text:gsub('\\"', '"')
    text = text:gsub("\\\\", "\\")
    return text
end

local function refresh_audio_devices()
    local file = io.open(AUDIO.devices_file, "rb")
    if not file then
        AUDIO.manual_devices = {}
        AUDIO.devices_count = 0
        AUDIO.devices_status = "waiting for bridge"
        return false
    end

    local text = file:read("*a") or ""
    file:close()

    local devices = {}
    -- Do not split device objects by braces: Windows endpoint IDs themselves
    -- contain {...}, so a naive "{[^{}]-}" object pattern returns no devices.
    for id, name, index, is_dualsense, is_default_auto in text:gmatch(
        '"id"%s*:%s*"(.-)"%s*,%s*' ..
        '"name"%s*:%s*"(.-)"%s*,%s*' ..
        '"index"%s*:%s*(%d+)%s*,%s*' ..
        '"is_dualsense"%s*:%s*(%a+)%s*,%s*' ..
        '"is_default_auto"%s*:%s*(%a+)'
    ) do
        devices[#devices + 1] = {
            id = json_unescape(id),
            label = json_unescape(name),
            index = tonumber(index) or (#devices + 1),
            is_dualsense = is_dualsense == "true",
            is_default_auto = is_default_auto == "true",
        }
    end

    AUDIO.manual_devices = devices
    AUDIO.devices_count = #devices
    AUDIO.devices_status = #devices > 0
        and ("ready (" .. tostring(#devices) .. ")")
        or "no active endpoints"

    if AUDIO.manual_device_id and AUDIO.manual_device_id ~= "" then
        for i, device in ipairs(devices) do
            if device.id == AUDIO.manual_device_id then
                AUDIO.manual_device_index = i
                AUDIO.manual_device_label = device.label
                return true
            end
        end
    end

    if AUDIO.manual_device_index < 1 or AUDIO.manual_device_index > #devices then
        AUDIO.manual_device_index = 1
    end

    local selected = devices[AUDIO.manual_device_index]
    if selected then
        AUDIO.manual_device_id = selected.id
        AUDIO.manual_device_label = selected.label
    end
    return true
end

function AUDIO.refresh_devices()
    return refresh_audio_devices()
end

local function selected_device_payload()
    if AUDIO.device_mode == "manual" then
        local selected = AUDIO.manual_devices[AUDIO.manual_device_index]
        if selected then
            AUDIO.manual_device_id = selected.id
            AUDIO.manual_device_label = selected.label
            return selected.id or "", selected.label or ""
        end
        return AUDIO.manual_device_id or "", AUDIO.manual_device_label or ""
    end

    if AUDIO.device_mode == "legacy" then
        local device_option = AUDIO.device_options[AUDIO.device_index] or AUDIO.device_options[1]
        return "", device_option.value or ""
    end

    return "", ""
end

-- Companion haptics for existing speaker-audio events (docs/HAPTICS_FOOTSTEPS_TASK.md).
-- Matched by substring against the event name, so the ~150 weapon
-- draw/aim/dry-fire/reload event_map entries in wwise_audio_router.lua (one
-- set per weapon) don't each need an explicit per-entry haptic field --
-- naming convention does the work, since every emit (router-routed or
-- direct, e.g. reload/heal/knife/pickup functions below) funnels through
-- this single local emit(). Order matters: first match wins.
-- fatal_kick intentionally NOT mapped: Capcom's own native haptics already
-- cover the finishing kick, a companion pulse here was redundant (user
-- feedback 2026-07-12).
local COMPANION_HAPTIC_PATTERNS = {
    -- Native RE4R has zero controller vibration for parry, so this is
    -- deliberately the strongest pulse in the whole system (haptic_parry,
    -- not the shared haptic_impact_strong) -- see tools/gen_haptic_wavs.py.
    {pattern = "knife_e129",     haptic = "haptic_parry", category = "parry"}, -- parry window
    {pattern = "knife_e135",     haptic = "haptic_parry", category = "parry"}, -- parry window
    {pattern = "knife_e125",     haptic = "haptic_parry", category = "parry"}, -- parry window
    {pattern = "knife_finish",   haptic = "haptic_impact_strong", category = "knife"},
    {pattern = "knife_swing_hit",haptic = "haptic_impact_medium", category = "knife"},
    {pattern = "knife_hit",      haptic = "haptic_impact_medium", category = "knife"},
    -- reload_* intentionally NOT mapped: Capcom's own native haptics
    -- already cover reload, a companion pulse here was redundant (user
    -- feedback 2026-07-12, same reasoning as fatal_kick above).
    --
    -- dry_fire/aim_in/aim_out/draw/heal switched 2026-07-13 to audio-to-
    -- haptics (real extracted SFX, one representative weapon -- wp4000/
    -- wp4001 -- per category rather than per-weapon-specific for now; see
    -- tools/audio_to_haptic.py). User: "все можно включить, но не как
    -- синтетику". Per-weapon draw variation (the one thing native RE4R
    -- doesn't have at all) is a possible follow-up, not done here -- this
    -- reuses one draw sound for every weapon's draw/lower/attach.
    {pattern = "dry_fire",       haptic = "haptic_dry_fire_real", category = "dry_fire"},
    {pattern = "last_shot",      haptic = "haptic_dry_fire_real", category = "dry_fire"},
    {pattern = "aim_in",         haptic = "haptic_aim_in_real", category = "aim"},
    {pattern = "aim_out",        haptic = "haptic_aim_out_real", category = "aim"},
    {pattern = "draw",           haptic = "haptic_draw_real", category = "draw"},
    {pattern = "lower",          haptic = "haptic_draw_real", category = "draw"},
    {pattern = "attach",         haptic = "haptic_draw_real", category = "draw"},
    -- Herb rare/mock must come before herb (plain find — "heal_herb" matches all three)
    {pattern = "heal_herb_rare", haptic = "haptic_heal_herb_rare", category = "heal"},
    {pattern = "heal_herb_mock", haptic = "haptic_heal_herb_mock", category = "heal"},
    {pattern = "heal_herb",      haptic = "haptic_heal_herb",      category = "heal"},
    -- Eggs: brown/gold before generic egg
    {pattern = "heal_egg_brown", haptic = "haptic_heal_egg_brown", category = "heal"},
    {pattern = "heal_egg_gold",  haptic = "haptic_heal_egg_gold",  category = "heal"},
    {pattern = "heal_egg",       haptic = "haptic_heal_egg",       category = "heal"},
    -- Fish: lunker/large before generic fish
    {pattern = "heal_fish_lunker", haptic = "haptic_heal_fish_lunker", category = "heal"},
    {pattern = "heal_fish_large",  haptic = "haptic_heal_fish_large",  category = "heal"},
    {pattern = "heal_fish",        haptic = "haptic_heal_fish",        category = "heal"},
    {pattern = "heal_viper",       haptic = "haptic_heal_viper",       category = "heal"},
    {pattern = "heal_beetle",      haptic = "haptic_heal_beetle",      category = "heal"},
    -- Fallback: heal_spray (original game WEM) keeps haptic_heal_real
    {pattern = "heal",           haptic = "haptic_heal_real", category = "heal"},
    {pattern = "pickup",         haptic = "haptic_pickup", category = "pickup"},
}

-- Approximate WAV duration per companion haptic (tools/gen_haptic_wavs.py),
-- used as the footstep-suppression window below -- long enough to keep the
-- footstep tone from muddying the more important pulse, short enough that
-- footsteps resume as soon as it's done rather than going silent for a
-- fixed guess.
local COMPANION_HAPTIC_DURATION_S = {
    haptic_impact_strong = 0.17,
    haptic_parry = 0.22,
    haptic_impact_medium = 0.10,
    haptic_dry_fire_real = 0.02,
    haptic_aim_in_real = 0.05,
    haptic_aim_out_real = 0.05,
    haptic_draw_real = 0.06,
    haptic_heal_real         = 0.20,
    haptic_heal_herb         = 0.80,
    haptic_heal_herb_rare    = 0.80,
    haptic_heal_herb_mock    = 0.30,
    haptic_heal_egg          = 0.09,
    haptic_heal_egg_brown    = 0.30,
    haptic_heal_egg_gold     = 0.30,
    haptic_heal_fish         = 0.23,
    haptic_heal_fish_lunker  = 0.30,
    haptic_heal_fish_large   = 0.50,
    haptic_heal_viper        = 0.30,
    haptic_heal_beetle       = 0.30,
    haptic_pickup = 0.02,
}

-- Priority system (user feedback 2026-07-12): with footsteps firing every
-- ~200-300ms during normal movement, a companion pulse landing on top of one
-- gets muddied in the actuator mixer (both pulses sum together). Any
-- companion haptic briefly suppresses footstep haptics for roughly its own
-- duration so it lands cleanly; footsteps resume on their own on the very
-- next step once the window passes -- no separate re-enable needed.
local footstep_suppressed_until = 0

local function haptic_category_intensity(category)
    local value = 1.0
    if category and AUDIO.haptic_category_intensity then
        value = tonumber(AUDIO.haptic_category_intensity[category]) or 1.0
    end
    if value < 0 then value = 0 end
    if value > 2 then value = 2 end
    return value
end

local function companion_haptic_for(event_name)
    -- Never chain off a haptic event itself (channels 3/4 pulses don't get
    -- their own companion pulse -- would recurse: "haptic_reload" contains
    -- "reload" and would otherwise match its own rule).
    if not event_name or event_name:sub(1, 7) == "haptic_" then return nil, nil end
    for _, rule in ipairs(COMPANION_HAPTIC_PATTERNS) do
        if event_name:find(rule.pattern, 1, true) then
            if rule.category and AUDIO.haptic_category_enabled[rule.category] == false then
                return nil, nil
            end
            return rule.haptic, rule.category
        end
    end
    return nil, nil
end

local function emit(event_name, volume_override, intensity_override)
    if not AUDIO.enabled then
        AUDIO.last_status = "disabled"
        return false
    end

    event_sequence = event_sequence + 1
    local timestamp = os.clock() + (event_sequence * 0.000001)
    local device_id, device = selected_device_payload()
    local volume = tonumber(volume_override) or tonumber(AUDIO.volume) or 0.85
    if volume < 0 then volume = 0 end
    if volume > 2 then volume = 2 end

    local payload
    if event_name and event_name:sub(1, 7) == "haptic_" then
        -- Live intensity slider (HapticPlayer.cs maps this to a low-pass
        -- cutoff + gain at play time) -- only meaningful for haptic events,
        -- harmless extra field otherwise so kept out of normal speaker
        -- payloads for a cleaner log. intensity_override lets a caller
        -- (footsteps) send a value scaled independently of the raw slider.
        local intensity = tonumber(intensity_override) or tonumber(AUDIO.haptic_intensity) or 0.6
        if intensity < 0 then intensity = 0 end
        if intensity > 1 then intensity = 1 end
        payload = string.format(
            '{"event":"%s","ts":%.6f,"device_id":"%s","device":"%s","volume":%.3f,"haptic_intensity":%.3f}',
            json_escape(event_name),
            timestamp,
            json_escape(device_id),
            json_escape(device),
            volume,
            intensity
        )
    else
        payload = string.format(
            '{"event":"%s","ts":%.6f,"device_id":"%s","device":"%s","volume":%.3f}',
            json_escape(event_name),
            timestamp,
            json_escape(device_id),
            json_escape(device),
            volume
        )
    end

    local file, open_error = io.open(AUDIO.events_file, "ab")
    if not file then
        AUDIO.last_error = "Cannot write " .. AUDIO.events_file .. ": " .. tostring(open_error)
        AUDIO.last_status = "write failed"
        return false
    end

    local ok, write_error = pcall(function()
        file:write(payload .. "\n")
        file:flush()
        file:close()
    end)

    if not ok then
        pcall(function() file:close() end)
        AUDIO.last_error = "JSON write failed: " .. tostring(write_error)
        AUDIO.last_status = "write failed"
        return false
    end

    AUDIO.last_event = event_name
    AUDIO.last_error = nil
    AUDIO.last_status = "emitted " .. tostring(event_name)

    -- Companion haptic pulse. Same IPC.haptics_mode_enabled gate as
    -- footstep haptics -- one opt-in toggle for the whole feature.
    local companion, companion_category = companion_haptic_for(event_name)
    if companion then
        local IPC = _G.DuaLibTriggerIpc
        if IPC and IPC.haptics_mode_enabled then
            local intensity = (tonumber(AUDIO.haptic_intensity) or 0.6)
                * haptic_category_intensity(companion_category)
            pcall(emit, companion, nil, intensity)
            local duration = COMPANION_HAPTIC_DURATION_S[companion] or 0.1
            footstep_suppressed_until = os.clock() + duration
        end
    end

    return true
end

function AUDIO.play_test()
    return emit(AUDIO.test_event)
end

local function heal_stem_for_item(item_id)
    if not item_id then return "heal_spray" end
    local base = math.floor(item_id / 1600) * 1600
    local egg_stem = EGG_STEMS[base]
    if egg_stem then return egg_stem end
    local fish_stem = FISH_STEMS[base]
    if fish_stem then return fish_stem end
    if not HERB_IDS[base] then return "heal_spray" end
    if AUDIO.heal_rare_always then return "heal_herb_rare" end
    local hp_ratio = (_G.HPLed and _G.HPLed.last_ratio) or 0.0
    -- Mock (just cough): inverse HP probability, max 10% at >=90% HP
    local mock_chance = math.floor(math.min(hp_ratio, 0.9) / 0.9 * 10)
    if mock_chance > 0 and math.random(100) <= mock_chance then
        return "heal_herb_mock"
    end
    -- Rare combined (herb + cough): 5% normal, 20% in danger zone
    local in_danger = _G.HPLed and _G.HPLed.is_danger
    local chance    = in_danger and 20 or 5
    if math.random(100) <= chance then return "heal_herb_rare" end
    return "heal_herb"
end

function AUDIO.reset_heal_cooldown()
    heal_cooldown = 0
    last_used_item_id = nil
end

function AUDIO.play_heal()
    if not AUDIO.heal_enabled then return false end
    if heal_cooldown > 0 then return false end
    local stem = heal_stem_for_item(last_used_item_id)
    last_used_item_id = nil
    local ok = emit(stem)
    if ok then heal_cooldown = AUDIO.heal_cooldown_frames end
    return ok
end

function AUDIO.play_parry()
    -- Bypassed: audio now routed via Wwise event 3415105559/2078013350 in wwise_audio_router.lua
    return false
end

function AUDIO.play_fatal_kick()
    -- Bypassed: audio now routed via Wwise event 1793304701 (play_cha0_se_chc_cm_fatal_kick_hit)
    return false
end

function AUDIO.play_knife_hit()
    if not AUDIO.knife_hit_enabled then return false end
    return emit("knife_hit")
end

local function reload_events(weapon_info)
    local weapon_id = weapon_info and tonumber(weapon_info.id) or nil
    return weapon_id and RELOAD_EVENTS_BY_WEAPON[weapon_id] or nil, weapon_id
end

local delayed_events = {}

local function schedule_event(event_name, frames)
    delayed_events[#delayed_events + 1] = {
        event = event_name,
        frames = math.max(1, tonumber(frames) or 1),
    }
end

function AUDIO.mark_deferred_postshot(weapon_info)
    local weapon_id = type(weapon_info) == "table"
        and tonumber(weapon_info.id)
        or tonumber(weapon_info)
    if not weapon_id then return false end
    AUDIO.deferred_postshot[weapon_id] = true
    return true
end

local function consume_deferred_postshot(weapon_id)
    if not weapon_id or not AUDIO.deferred_postshot[weapon_id] then
        return false
    end
    AUDIO.deferred_postshot[weapon_id] = nil
    return true
end

function AUDIO.reset_reload_audio_state()
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    if DIAG and DIAG.end_window then
        pcall(DIAG.end_window, "reload_reset")
    end
    AUDIO.reload_session_active = false
    AUDIO.reload_insert_grace = 0
    AUDIO.reload_finish_played = false
    AUDIO.deferred_postshot = {}
    delayed_events = {}
end

function AUDIO.begin_reload_session(weapon_info)
    if not AUDIO.reload_enabled then return false end
    local events, weapon_id = reload_events(weapon_info)
    if not events then
        AUDIO.last_status = "reload profile missing for " .. tostring(weapon_id)
        return false
    end
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    if DIAG and DIAG.begin_window then
        pcall(DIAG.begin_window, "reload_start", 300)
    end
    AUDIO.reload_session_active = true
    AUDIO.reload_finish_played = false
    if events.start then emit(events.start) end
    return true
end

local function play_reload_phase(phase, weapon_info)
    if not AUDIO.reload_enabled then return false end
    local events, weapon_id = reload_events(weapon_info)
    if not events then
        AUDIO.last_status = "reload profile missing for " .. tostring(weapon_id)
        return false
    end
    local event_name = events[phase]
    if not event_name then return false end
    return emit(event_name)
end

function AUDIO.play_reload_start(weapon_info)
    return AUDIO.begin_reload_session(weapon_info)
end

function AUDIO.play_reload_insert(weapon_info)
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    if DIAG and DIAG.extend_window then
        pcall(DIAG.extend_window, "reload_insert", 180)
    end
    return play_reload_phase("insert", weapon_info)
end

function AUDIO.play_reload_finish(weapon_info)
    if AUDIO.reload_finish_played then return false end
    local events, weapon_id = reload_events(weapon_info)
    if not events then return false end
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    if DIAG and DIAG.extend_window then
        pcall(DIAG.extend_window, "reload_finish", 150)
    end

    local played = false
    if events.finish then
        played = emit(events.finish)
    end

    if consume_deferred_postshot(weapon_id) then
        if weapon_id == 4400 then
            played = emit("wp4400_reload_finish") or played
        elseif weapon_id == 4502 then
            schedule_event("wp4502_postshot", 6)
            played = true
        end
    end

    if played then AUDIO.reload_finish_played = true end
    return played
end

function AUDIO.should_finish_on_full_insert(weapon_info)
    local events = reload_events(weapon_info)
    return events and events.finish_on_full_insert == true
end

-- Was 20 frames (widened from 10 to avoid FileSystemWatcher race in the
-- old bridge). Bridge fix resolved the race; reduced to 8 frames (~0.13s)
-- for a natural pump timing. Raise if the open sound gets dropped again.
local W870_PUMP_CLOSE_GAP_FRAMES = 8

function AUDIO.play_w870_pump_cycle()
    if not AUDIO.reload_enabled then return false end
    -- No reload_session_active guard: event_0203 is the same chamber/pump
    -- cue whether it follows a live shot or the final shell of a from-empty
    -- reload (confirmed identical Wwise ID in both live captures), so it
    -- must fire in either context instead of waiting for reload-exit
    -- confirmation in events_led.lua, which lags behind the real sound by
    -- close to a second.
    local played = emit("wp4100_reload_start")
    schedule_event("wp4100_reload_finish", W870_PUMP_CLOSE_GAP_FRAMES)
    return played
end

function AUDIO.play_sr1903_postshot_event()
    if not AUDIO.reload_enabled then return false end
    -- event_0226 also fires as part of the normal reload bolt sequence, so
    -- it must not play here while a reload session is active (the reload's
    -- own start/insert/finish sounds already cover that case).
    if AUDIO.reload_session_active then return false end
    return emit("wp4400_reload_finish")
end

-- event_0268 (Wwise ID 4245683861) is shared by three roles: reload
-- finish, a dry-fire-time no-op (ammo=0, must stay silent), and the
-- generic aim-out/weapon-lowering cue. Disambiguated by reload session
-- state: during an active reload with ammo > 0 it's the finish cue;
-- otherwise (not reloading) it's aim-out, regardless of ammo.
function AUDIO.play_wp4004_weapon_lower_event()
    if not AUDIO.reload_enabled then return false end
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info

    if AUDIO.reload_session_active then
        if not info or tonumber(info.ammo) == 0 then return false end
        return emit("wp4004_reload_finish")
    end

    return emit("wp4004_aim_out")
end

-- event_0240 (712539726) is shared: dry-fire stage 2 when ammo=0,
-- aim-out/weapon-lower when ammo>0. Same pattern as Matilda event_0268.
function AUDIO.play_wp4001_lower_event()
    if not AUDIO.reload_enabled then return false end
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info
    if not info or tonumber(info.id) ~= 4001 then return false end
    if tonumber(info.ammo) == 0 then
        return emit("wp4001_dry_fire_b")
    end
    return emit("wp4001_aim_out")
end

-- event_0272 (3924820871) is shared: dry-fire stage 2 when ammo=0,
-- aim-out/weapon-lower when ammo>0. Same pattern as wp4001.
function AUDIO.play_wp4002_lower_event()
    if not AUDIO.reload_enabled then return false end
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info
    if not info or tonumber(info.id) ~= 4002 then return false end
    if tonumber(info.ammo) == 0 then
        return emit("wp4002_dry_fire_b")
    end
    return emit("wp4002_aim_out")
end

function AUDIO.play_broken_butterfly_postshot()
    if not AUDIO.reload_enabled then return false end
    return emit("wp4500_postshot")
end

function AUDIO.play_handcannon_postshot()
    if not AUDIO.reload_enabled then return false end
    return emit("wp4502_postshot")
end

function AUDIO.play_qte()
    if not AUDIO.qte_enabled then return false end
    return emit("qte")
end

-- Footstep-haptics route (docs/HAPTICS_FOOTSTEPS_TASK.md). Gated on
-- dualib_trigger_ipc.lua's IPC.haptics_mode_enabled -- the single source of
-- truth shared with the watcher's audio-haptics vibration-mode hold, so the
-- actuator event stream and the controller's vibration mode can never drift
-- out of sync. Ships in v1.0 as an opt-in feature, default off. Uniform
-- across all surfaces -- a per-surface intensity variant was prototyped and
-- removed before release; see project-haptics-experiment memory and git
-- history if picking that back up. Intensity is AUDIO.haptic_intensity (a
-- continuous slider, see above), live-filtered in HapticPlayer.cs -- not a
-- discrete WAV-swap preset anymore.
function AUDIO.play_footstep_haptic()
    local IPC = _G.DuaLibTriggerIpc
    if not IPC or not IPC.haptics_mode_enabled then return false end
    if AUDIO.haptic_category_enabled.footsteps == false then return false end
    -- Live-confirmed 2026-07-13 (player_movement.lua): the footstep Wwise
    -- event also fires from idle weight-shift while standing still, and
    -- fires on every walk step too -- matching PS5's own haptics (subtle,
    -- run-only) means gating on RequestRun here rather than relaxing the
    -- cooldown, which only thinned cadence without fixing the standing-
    -- still false positive.
    local PM = _G.PlayerMovement
    if not (PM and PM.is_running) then return false end
    -- Priority system: skip this step's pulse while a more important
    -- companion haptic (parry/reload/impact/etc) is still landing, instead
    -- of mixing on top of it and muddying both. See footstep_suppressed_until
    -- above -- resumes on its own on the next step, no re-enable needed.
    if os.clock() < footstep_suppressed_until then return false end
    local intensity = (tonumber(AUDIO.haptic_intensity) or 0.6)
        * haptic_category_intensity("footsteps")
        * AUDIO.FOOTSTEP_INTENSITY_SCALE
    return emit(AUDIO.FOOTSTEP_HAPTIC_EVENT, nil, intensity)
end

-- UI smoke test. Use the packaged synthesized parry pulse instead of the
-- footstep route: play_footstep_haptic() intentionally rejects calls while
-- the player is not sprinting, which made the old menu test appear broken.
function AUDIO.play_haptic_test()
    local IPC = _G.DuaLibTriggerIpc
    if not IPC or not IPC.haptics_mode_enabled then
        AUDIO.haptic_test_status = "Enable Enhanced Haptics first"
        return false
    end
    if not AUDIO.enabled then
        AUDIO.haptic_test_status = "Enable Controller Speaker Audio first"
        return false
    end
    local intensity = (tonumber(AUDIO.haptic_intensity) or 0.6)
        * haptic_category_intensity("parry")
    local ok = emit("haptic_parry", nil, intensity)
    if ok then
        AUDIO.haptic_test_status = "Parry test pulse sent"
    else
        AUDIO.haptic_test_status = "Test failed: " .. tostring(AUDIO.last_error or AUDIO.last_status or "unknown error")
    end
    return ok
end

function AUDIO.emit(event_name, volume_override)
    return emit(event_name, volume_override)
end

local function tick_delayed_events()
    if not is_current_generation() then return end
    for index = #delayed_events, 1, -1 do
        local pending = delayed_events[index]
        pending.frames = pending.frames - 1
        if pending.frames <= 0 then
            emit(pending.event)
            table.remove(delayed_events, index)
        end
    end
end

pcall(function()
    re.on_application_entry("UpdateBehavior", tick_delayed_events)
end)

local function log_pickup(drop_item)
    if not AUDIO.pickup_debug_enabled or not drop_item then return end

    local item_id = nil
    local type_name = nil

    pcall(function()
        item_id = drop_item:call("getItemID")
    end)
    pcall(function()
        local type_def = drop_item:get_type_definition()
        if type_def then
            type_name = type_def:get_full_name() or type_def:get_name()
        end
    end)

    AUDIO.last_pickup_id = item_id
    AUDIO.last_pickup_type = type_name or "chainsaw.DropItem"
    AUDIO.pickup_count = AUDIO.pickup_count + 1

    local detail = "id=" .. tostring(item_id) ..
        " type=" .. tostring(AUDIO.last_pickup_type) ..
        " count=" .. tostring(AUDIO.pickup_count)

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("item pickup", detail) end
    print("[DualSenseEnhancedAudio] item pickup: " .. detail)
end

local function describe_hook_args(args)
    local parts = {}
    for index = 1, 6 do
        local raw = args[index]
        local type_name = nil
        local value_text = nil

        pcall(function()
            local managed = sdk.to_managed_object(raw)
            if managed then
                local type_def = managed:get_type_definition()
                if type_def then
                    type_name = type_def:get_full_name() or type_def:get_name()
                end
                value_text = tostring(managed)
            end
        end)

        if not value_text then
            pcall(function() value_text = tostring(raw) end)
        end

        parts[#parts + 1] = string.format(
            "a%d=%s%s",
            index,
            tostring(type_name or "raw"),
            value_text and ("(" .. value_text .. ")") or ""
        )
    end
    return table.concat(parts, " | ")
end

local function install_pickup_hooks()
    if pickup_hooks_installed then return end

    local drop_type = sdk.find_type_definition("chainsaw.DropItem")
    if not drop_type then
        AUDIO.pickup_hook_status = "DropItem type not found"
        return
    end

    local methods = drop_type:get_methods()
    local installed = 0
    for _, method in ipairs(methods or {}) do
        local ok_name, name = pcall(function() return method:get_name() end)
        if ok_name and (name == "cantDoubleBilling" or name == "updateSleep") then
            pcall(function()
                sdk.hook(method, function(args)
                    if not is_current_generation() then return end
                    pcall(function()
                        remember_pickup_candidate(sdk.to_managed_object(args[2]))
                    end)
                end, function(retval)
                    return retval
                end)
            end)
        elseif ok_name and name == "onAcceptPickup" then
            local ok_hook = pcall(function()
                sdk.hook(method, function(args)
                    if not is_current_generation() then return end
                    pcall(function()
                        AUDIO.pickup_count = AUDIO.pickup_count + 1
                        AUDIO.last_pickup_args = AUDIO.pickup_debug_enabled
                            and describe_hook_args(args) or nil
                        local pickup_context = sdk.to_managed_object(args[3])
                        local candidate, context_text = find_pickup_candidate(pickup_context)
                        if candidate then
                            AUDIO.last_pickup_id = candidate.item_id
                            AUDIO.last_pickup_type = "chainsaw.DropItem"
                            AUDIO.pickup_hook_status = "matched DropItem cache"
                        else
                            AUDIO.last_pickup_id = nil
                            AUDIO.pickup_hook_status = "pickup fired; cache miss"
                        end

                        local item_info = nil
                        local ITEM_IDS = _G.DualSenseEnhancedItemIDs
                        if ITEM_IDS and ITEM_IDS.resolve then
                            item_info = ITEM_IDS.resolve(AUDIO.last_pickup_id)
                        end
                        AUDIO.last_pickup_base_id = item_info and item_info.base_id or nil
                        AUDIO.last_pickup_name = item_info and item_info.name or nil
                        AUDIO.last_pickup_category = item_info and item_info.category or nil
                        AUDIO.last_pickup_event = nil

                        if AUDIO.pickup_enabled and item_info then
                            local pickup_event =
                                PICKUP_EVENT_BY_ID[item_info.base_id] or
                                PICKUP_EVENT_BY_CATEGORY[item_info.category]
                            if pickup_event then
                                AUDIO.last_pickup_event = pickup_event
                                emit(pickup_event)
                            end
                        end

                        if AUDIO.pickup_debug_enabled then
                            local MON = _G.DualSenseEnhancedMonitor
                            if MON and MON.log then
                                MON.log(
                                    "item pickup",
                                    tostring(AUDIO.last_pickup_name or "Unknown Item") ..
                                    " [" .. tostring(AUDIO.last_pickup_category or "unknown") .. "]" ..
                                    " raw=" .. tostring(AUDIO.last_pickup_id) ..
                                    " base=" .. tostring(AUDIO.last_pickup_base_id) ..
                                    " sound=" .. tostring(AUDIO.last_pickup_event or "none") ..
                                    " context=" .. tostring(context_text) ..
                                    " count=" .. tostring(AUDIO.pickup_count)
                                )
                            end
                            print(
                                "[DualSenseEnhancedAudio] item pickup: id=" ..
                                tostring(AUDIO.last_pickup_id) ..
                                " context=" .. tostring(context_text)
                            )
                        end
                    end)
                end, function(retval)
                    return retval
                end)
            end)
            if ok_hook then installed = installed + 1 end
        end
    end

    if installed > 0 then
        pickup_hooks_installed = true
        AUDIO.pickup_hook_status = "installed (" .. tostring(installed) .. ")"
        print("[DualSenseEnhancedAudio] DropItem.onAcceptPickup hooks: " .. tostring(installed))
    else
        AUDIO.pickup_hook_status = "onAcceptPickup not found"
    end
end

local function install_item_use_hook()
    if item_use_hook_installed then return end
    local t = sdk.find_type_definition("chainsaw.CsInventoryController")
    if not t then return end
    local m = t:get_method("applyUseResult")
    if not m then return end
    sdk.hook(m, function(args)
        last_used_item_id = tonumber(sdk.to_int64(args[3]))
    end, function(retval) return retval end)
    item_use_hook_installed = true
end

pcall(install_pickup_hooks)
pcall(install_item_use_hook)
pcall(refresh_audio_devices)
pcall(function()
    re.on_application_entry("UpdateBehavior", function()
        if not is_current_generation() then return end
        if not pickup_hooks_installed then pcall(install_pickup_hooks) end
        if not item_use_hook_installed then pcall(install_item_use_hook) end
        if heal_cooldown > 0 then heal_cooldown = heal_cooldown - 1 end
        device_refresh_timer = device_refresh_timer - 1
        if device_refresh_timer <= 0 then
            device_refresh_timer = 180
            pcall(refresh_audio_devices)
        end
    end)
end)

_G.DualSenseEnhancedAudio = AUDIO
