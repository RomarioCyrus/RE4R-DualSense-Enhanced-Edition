local sdk    = sdk
local re     = re
local pcall  = pcall
local io     = io
local os     = os
local math   = math

-- ================================================================
-- audio_feedback.lua  —  DualSense Speaker events for RE4R
-- 
-- Writes JSON event files that audio_bridge.py watches.
-- Bridge plays matching .wav/.ogg files on the DualSense speaker.
--
-- Setup:
--   1. Run audio_bridge.py before launching RE4R
--   2. Place sound files in reframework/data/DualSenseEnhanced/sounds/
--   3. This file is loaded by DualSenseEnhanced.lua (add loadf("audio_feedback.lua"))
-- ================================================================

local AUDIO = {}
AUDIO.enabled       = true
AUDIO.events_file   = "reframework/data/audio_events.json"

-- Per-event enable toggles
AUDIO.ev = {
    heal_spray  = true,
    heal_herb   = true,
    heal_mixed  = true,
    reload      = true,
    empty_mag   = true,
    parry       = true,
    grab        = true,
    item_pickup = true,
    low_hp      = true,
}

-- ----------------------------------------------------------------
-- Event writing
-- Lua writes: {"event": "heal_spray", "ts": <time>}
-- Python detects new timestamp → plays sound
-- ----------------------------------------------------------------

local function emit(event_name)
    if not AUDIO.enabled then return end
    if not AUDIO.ev[event_name] then return end

    local ts = os.clock()  -- fractional seconds, unique enough
    local payload = string.format(
        '{"event":"%s","ts":%.6f}',
        event_name, ts
    )

    local f = io.open(AUDIO.events_file, "wb")
    if not f then return end
    f:write(payload)
    f:close()
end

-- ----------------------------------------------------------------
-- Low HP: emit looping heartbeat event while below threshold
-- Uses polling rate to avoid spamming events
-- ----------------------------------------------------------------

local LOW_HP_THRESHOLD  = 400     -- absolute HP units
local LOW_HP_EMIT_RATE  = 180     -- emit every N frames while low HP
local low_hp_active     = false
local low_hp_tick       = 0

local function check_low_hp(cur_hp)
    local new_low = (cur_hp > 0 and cur_hp < LOW_HP_THRESHOLD)
    if new_low ~= low_hp_active then
        low_hp_active = new_low
        if not new_low then
            -- HP recovered — emit a "cancel" event so bridge stops loop
            emit("low_hp_end")
        end
    end
    if low_hp_active then
        low_hp_tick = low_hp_tick + 1
        if low_hp_tick >= LOW_HP_EMIT_RATE then
            low_hp_tick = 0
            emit("low_hp")
        end
    else
        low_hp_tick = 0
    end
end

-- ----------------------------------------------------------------
-- HP polling (reuse CharacterManager path)
-- ----------------------------------------------------------------

local hp_poll_tick = 0
local HP_POLL_RATE = 10

local function poll_hp()
    hp_poll_tick = hp_poll_tick + 1
    if hp_poll_tick % HP_POLL_RATE ~= 0 then return end

    pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then return end
        local player = cm:call("getPlayerContextRef")
        if not player then player = cm:call("get_ManualPlayer") end
        if not player then return end
        local hp = player:call("get_HitPoint")
        if not hp then return end
        local cur = hp:call("get_CurrentHitPoint")
        if cur then check_low_hp(cur) end
    end)
end

-- ----------------------------------------------------------------
-- Heal detection: hook same HP increase as hp_led uses
-- We expose a public function for hp_led to call
-- ----------------------------------------------------------------

function AUDIO.on_heal(heal_amount)
    if not AUDIO.enabled then return end
    -- Distinguish spray vs herb by heal amount (rough heuristic)
    -- RE4R: spray heals ~full, herbs ~partial
    -- Without exact values, emit generic or use ammo type info
    -- For now emit heal_herb as default; can refine later
    emit("heal_herb")
end

function AUDIO.on_heal_spray()
    emit("heal_spray")
end

-- ----------------------------------------------------------------
-- Hooks: reload, empty mag, parry, grab
-- ----------------------------------------------------------------

local hooks_installed = false

local function install_hooks()
    if hooks_installed then return end

    -- Parry
    local head = sdk.find_type_definition("chainsaw.PlayerHeadActionSign")
    if head then
        local m = head:get_method("onHitParry")
        if m then
            sdk.hook(m, function() end, function(r)
                pcall(function() emit("parry") end)
                return r
            end)
            print("[EnhancedAudio] onHitParry hook OK")
        end
    end

    -- Grab start
    local GRAB_ATTACK_TYPES = {[0]=true,[4]=true,[6]=true,[17]=true,[23]=true}
    local hit = sdk.find_type_definition("chainsaw.HitController")
    if hit then
        local m = hit:get_method("shieldingDecision")
        if m then
            sdk.hook(m, function(args)
                local ok, ad = pcall(sdk.to_managed_object, args[6])
                if not ok or not ad then return end
                if ad._AttackToPlayerUserData == nil then return end
                if not GRAB_ATTACK_TYPES[ad._AttackType] then return end
                pcall(function() emit("grab") end)
            end, function(r) return r end)
            print("[EnhancedAudio] shieldingDecision hook OK")
        end
    end

    -- Reload / fire events via app.Gun
    local gun = sdk.find_type_definition("chainsaw.Gun")
    if not gun then gun = sdk.find_type_definition("app.Gun") end
    if gun then
        -- onEndReload fires when reload animation completes
        local reload_m = gun:get_method("onEndReload")
        if reload_m then
            sdk.hook(reload_m, function() end, function(r)
                pcall(function() emit("reload") end)
                return r
            end)
            print("[EnhancedAudio] onEndReload hook OK")
        end

        -- onDryFire = empty mag click
        local dry_m = gun:get_method("onDryFire")
        if dry_m then
            sdk.hook(dry_m, function() end, function(r)
                pcall(function() emit("empty_mag") end)
                return r
            end)
            print("[EnhancedAudio] onDryFire hook OK")
        end
    end

    -- Item pickup — try InventoryController or ItemManager
    local inv = sdk.find_type_definition("chainsaw.CsInventoryController")
    if inv then
        for _, mname in ipairs({"onAddItem", "onPickupItem", "addItem"}) do
            local m = inv:get_method(mname)
            if m then
                sdk.hook(m, function() end, function(r)
                    pcall(function() emit("item_pickup") end)
                    return r
                end)
                print("[EnhancedAudio] " .. mname .. " hook OK")
                break
            end
        end
    end

    hooks_installed = true
    print("[EnhancedAudio] hooks installed")
end

-- ----------------------------------------------------------------
-- Per-frame
-- ----------------------------------------------------------------

local function on_update()
    if not AUDIO.enabled then return end
    if not hooks_installed then pcall(install_hooks) end
    poll_hp()
end

pcall(install_hooks)
pcall(function()
    re.on_application_entry("UpdateBehavior", on_update)
end)

-- ----------------------------------------------------------------
-- UI
-- ----------------------------------------------------------------

re.on_draw_ui(function()
    if imgui.tree_node("Speaker Audio") then
        local c, v = imgui.checkbox("Enable##audio", AUDIO.enabled)
        if c then AUDIO.enabled = v end

        imgui.separator()
        imgui.text("Events:")

        local events = {
            {"heal_herb",   "Herb heal"},
            {"heal_spray",  "First Aid Spray"},
            {"reload",      "Reload complete"},
            {"empty_mag",   "Empty magazine"},
            {"parry",       "Knife parry"},
            {"grab",        "Enemy grab"},
            {"item_pickup", "Item pickup"},
            {"low_hp",      "Low HP heartbeat"},
        }
        for _, pair in ipairs(events) do
            local key, label = pair[1], pair[2]
            local ce, ve = imgui.checkbox(label .. "##audio_" .. key, AUDIO.ev[key] or false)
            if ce then AUDIO.ev[key] = ve end
        end

        imgui.separator()
        imgui.text("Low HP threshold:")
        local ct, vt = imgui.slider_int("##audio_lhp", LOW_HP_THRESHOLD, 0, 1000)
        if ct then LOW_HP_THRESHOLD = vt end

        imgui.separator()
        imgui.text("Events file:")
        imgui.text("  " .. AUDIO.events_file)

        if imgui.button("Test: emit heal##audio_test") then
            emit("heal_herb")
        end

        imgui.tree_pop()
    end
end)

_G.EnhancedAudio = AUDIO
