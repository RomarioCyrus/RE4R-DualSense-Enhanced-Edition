local sdk   = sdk
local re    = re
local pcall = pcall
local math  = math
local string = string

_G.DualSenseEnhancedEventsLedGeneration = (_G.DualSenseEnhancedEventsLedGeneration or 0) + 1
local generation = _G.DualSenseEnhancedEventsLedGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedEventsLedGeneration == generation
end

-- ================================================================
-- events_led.lua
-- Confirmed working hooks (from log):
--   onStartInGame, onHitParry, onHitDamageCheck,
--   LargeActionSign_Grab3GuiBehavior QTE lifecycle
-- Menu/death detection: polling via CharacterManager
-- ================================================================

-- Capture previous exported state BEFORE creating the new table, so
-- Reset Scripts mid-gameplay preserves in_game / player_dead.
local _prev = _G.EventsLed

local EVENTS = {}
EVENTS.enabled      = true
EVENTS.color_parry  = {0,   0,   255}
EVENTS.color_damage = {255, 0,   0}
EVENTS.color_fatal  = {180, 0,   255}
EVENTS.color_hookshot = {0, 160, 255}
EVENTS.color_reload = {255, 220, 80}
EVENTS.color_menu   = {0,   0,   40}
EVENTS.menu_enabled = false
-- Preserve in_game / player_dead across Reset Scripts so IPC/lightbar and
-- death-blackout stay active. poll_game_state() corrects within one frame.
EVENTS.in_game     = _prev and _prev.in_game == true or false
EVENTS.player_dead = _prev and _prev.player_dead == true or false
EVENTS.reload_lightbar_enabled = false

EVENTS.defaults = {
    parry_duration = 120,
    grab_flash_duration = 12,
    fatal_impact_duration = 30,
    damage_duration = 80,
}
EVENTS.parry_duration  = EVENTS.defaults.parry_duration
EVENTS.grab_flash_duration = EVENTS.defaults.grab_flash_duration
EVENTS.fatal_impact_duration = EVENTS.defaults.fatal_impact_duration
EVENTS.damage_duration = EVENTS.defaults.damage_duration

function EVENTS.reset_defaults()
    EVENTS.parry_duration  = EVENTS.defaults.parry_duration
    EVENTS.grab_flash_duration = EVENTS.defaults.grab_flash_duration
    EVENTS.fatal_impact_duration = EVENTS.defaults.fatal_impact_duration
    EVENTS.damage_duration = EVENTS.defaults.damage_duration
end

local RELOAD_DURATION = 180
local RELOAD_GRACE_FRAMES = 12
local RELOAD_CONFIRM_FRAMES = 10
local RELOAD_AUDIO_END_CONFIRM_FRAMES = 6
local GRAB_FLASH_COOLDOWN_FRAMES = 4
local hooks_installed = false
local gp_singleton = sdk.get_native_singleton("via.hid.Gamepad")
local gp_typedef = sdk.find_type_definition("via.hid.GamePad")
local GRAB_ESCAPE_BUTTON = 131104 -- A / Cross (X)

local parry_timer    = 0
local parry_black_at = 0
local parry_black_started = false
local damage_timer   = 0
local reload_timer   = 0
local reload_grace   = 0
local reload_pending = 0
local reload_audio_active = false
local reload_audio_end_pending = 0
local grab_active    = false
local grab_flash_timer = 0
local grab_flash_cooldown = 0
local grab_qte_started = false
local grab_input_pending = 0
local cross_was_down = false
local fatal_active = false
local fatal_impact_seen = false
local fatal_impact_flash_timer = 0
local hookshot_active = false

-- ----------------------------------------------------------------
-- Gameplay/menu/death state polling
-- Since CampaignManager menu hooks don't exist, we poll every N frames
-- ----------------------------------------------------------------
local poll_tick       = 0
local POLL_INTERVAL   = 30    -- check every 30 frames (~0.5s)
-- Seed from previous session state so the loading-protection guard
-- (in_gameplay and not was_in_gameplay) does not fire after Reset Scripts
-- mid-gameplay and clear all outputs. poll_game_state() will correct any
-- wrong value within one poll cycle (~0.5 s).
local _was_in_game    = _prev and _prev.in_game == true or false
local was_in_gameplay = _was_in_game
local current_player_supported = false
local current_player_missing_ticks = 0
local CURRENT_PLAYER_MISSING_LIMIT = 2
local gameplay_outputs_enabled = _was_in_game
local death_state_active = _prev and _prev.player_dead == true or false
local pending_gameplay_enable = false
local pending_gameplay_reason = nil
local pending_gameplay_log_tick = 0
-- Set once CampaignManager.onStartInGame has fired for real this session.
-- Gates adaptive_gameplay_signal so it only acts as death/Continue
-- recovery, never as the initial enable on a fresh load.
-- Seed true if we were already in-game so adaptive recovery can still fire.
local ever_started_in_game = _was_in_game

-- Reset Scripts mid-gameplay recovery.
-- Empirically confirmed (events_debug.txt): this REFramework build FULLY
-- resets the Lua state on Reset Scripts -- generation returns to 1 and
-- _G.EventsLed is nil, so nothing about the previous session survives (_prev
-- is always nil, the preserved flags in native_feedback.lua are always fresh
-- defaults). onStartInGame does NOT fire on a Reset Scripts, so without this
-- the mod stays dormant until the player exits to menu or reloads a save.
-- Detect an in-progress gameplay session by live-polling HP context instead:
-- a Reset Scripts triggered mid-gameplay has valid, non-dead player HP context
-- immediately (the engine keeps running, only Lua reloads), so if HP is valid
-- on the FIRST poll after load and stays valid for a couple of cycles, we were
-- reset mid-gameplay and must enable outputs ourselves. If the first poll has
-- no valid HP context, this is a cold start sitting at the title/menu -> the
-- flag disarms permanently so it cannot misfire during the initial level load
-- (where HP goes valid seconds before onStartInGame); that first enable belongs
-- to onStartInGame, matching Capcom's own lightbar timing.
local reset_recovery_pending = true
local reset_recovery_confirm = 0
local RESET_RECOVERY_CONFIRM_CYCLES = 2
local function has_valid_weapon_context()
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info
    if not info then return false end
    local id = tostring(info.id or "")
    local name = tostring(info.name or ""):lower()
    if id ~= "" and id ~= "none" and id ~= "nil" then return true end
    if name ~= "" and name ~= "none" and name ~= "searching..." then return true end
    return (info.ammoMax or 0) > 0
end

local function get_hp_snapshot()
    local ok, cur, max, dead = pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then return nil, nil, nil end
        local player = cm:call("getPlayerContextRef")
        if not player then player = cm:call("get_ManualPlayer") end
        if not player then return nil, nil, nil end

        local dead_flag = false
        pcall(function()
            dead_flag = player:call("get_IsDead")
                     or player:call("get_IsDeadState")
                     or false
        end)

        local hp = player:call("get_HitPoint")
        if not hp then return nil, nil, dead_flag end
        local cur_hp = hp:call("get_CurrentHitPoint")
        local max_hp = hp:call("get_DefaultHitPoint")
        if cur_hp and cur_hp <= 0 then dead_flag = true end
        pcall(function()
            if hp:call("get_IsDeadState") then dead_flag = true end
        end)
        return cur_hp, max_hp, dead_flag
    end)
    if ok then return cur, max, dead end
    return nil, nil, nil
end

local function has_valid_hp_context()
    local cur, max, dead = get_hp_snapshot()
    return cur ~= nil
        and max ~= nil
        and max > 0
        and cur > 0
        and dead ~= true
end

local function can_enable_gameplay_outputs()
    return has_valid_hp_context()
end

local function flush()
    local FEEDBACK  = _G.DualSenseEnhancedFeedback
    local CORE = _G.WeaponEquipCore
    if FEEDBACK and FEEDBACK.apply_for_weapon and CORE and CORE.last_info then
        pcall(FEEDBACK.apply_for_weapon, CORE.last_info)
    end
end

local function debug_log(msg)
    pcall(function()
        local f = io.open("DualSenseEnhanced/events_debug.txt", "a")
        if not f then return end
        f:write(os.date("%H:%M:%S") .. " " .. tostring(msg) .. "\n")
        f:close()
    end)
end

local function debug_methods_matching(tdef, label, needle)
    local ok, methods = pcall(function() return tdef:get_methods() end)
    if not ok or not methods then
        debug_log("[EventsLed] " .. label .. ": cannot enumerate methods")
        return
    end

    local found = false
    for _, method in ipairs(methods) do
        local ok_name, name = pcall(function() return method:get_name() end)
        if ok_name and name and tostring(name):lower():find(needle, 1, true) then
            found = true
            debug_log("[EventsLed] " .. label .. " method candidate: " .. tostring(name))
        end
    end

    if not found then
        debug_log("[EventsLed] " .. label .. ": no methods containing '" .. needle .. "'")
    end
end

local function debug_type_methods(type_name, needle)
    local tdef = sdk.find_type_definition(type_name)
    if not tdef then
        debug_log("[EventsLed] " .. type_name .. " NOT FOUND")
        return
    end
    debug_log("[EventsLed] " .. type_name .. " FOUND")
    pcall(debug_methods_matching, tdef, type_name, needle or "")
end

local function debug_state(label, has_player, has_current_player, is_dead)
    local CORE = _G.WeaponEquipCore
    local info = CORE and CORE.last_info
    local hp_cur, hp_max, hp_dead = get_hp_snapshot()
    local detail = string.format(
        "[EventsLed] state %s hpPlayer=%s currentPlayer=%s dead=%s weapon=%s ammo=%s/%s validWeapon=%s hp=%s/%s hpDead=%s validHP=%s was=%s outputs=%s",
        tostring(label),
        tostring(has_player),
        tostring(has_current_player),
        tostring(is_dead),
        tostring(info and info.name or "nil"),
        tostring(info and info.ammo or "nil"),
        tostring(info and info.ammoMax or "nil"),
        tostring(has_valid_weapon_context()),
        tostring(hp_cur),
        tostring(hp_max),
        tostring(hp_dead),
        tostring(has_valid_hp_context()),
        tostring(was_in_gameplay),
        tostring(gameplay_outputs_enabled)
    )
    debug_log(detail)
end

local function hook_methods_named(type_name, names, label, post_fn)
    local tdef = sdk.find_type_definition(type_name)
    if not tdef then
        debug_log("[EventsLed] " .. label .. " type NOT FOUND: " .. type_name)
        return 0
    end

    local ok, methods = pcall(function() return tdef:get_methods() end)
    if not ok or not methods then
        debug_log("[EventsLed] " .. label .. " cannot enumerate methods")
        return 0
    end

    local wanted = {}
    for _, name in ipairs(names) do wanted[name] = true end

    local count = 0
    for _, method in ipairs(methods) do
        local ok_name, name = pcall(function() return method:get_name() end)
        if ok_name and name and wanted[tostring(name)] then
            local ok_hook = pcall(function()
                sdk.hook(method, function() end, function(r)
                    if not is_current_generation() then return r end
                    pcall(post_fn, tostring(name))
                    return r
                end)
            end)
            if ok_hook then
                count = count + 1
                debug_log("[EventsLed] " .. label .. " hook OK: " .. type_name .. "." .. tostring(name))
            else
                debug_log("[EventsLed] " .. label .. " hook FAILED: " .. type_name .. "." .. tostring(name))
            end
        end
    end

    if count == 0 then
        debug_log("[EventsLed] " .. label .. " hooks NOT FOUND on " .. type_name)
    end
    return count
end

local function clear_gameplay_outputs()
    parry_timer    = 0
    parry_black_at = 0
    parry_black_started = false
    damage_timer   = 0
    reload_timer   = 0
    reload_grace   = 0
    reload_pending = 0
    reload_audio_active = false
    reload_audio_end_pending = 0
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO then
        AUDIO.reload_session_active = false
        AUDIO.reload_insert_grace = 0
        AUDIO.reload_finish_played = false
    end
    grab_active    = false
    grab_flash_timer = 0
    grab_flash_cooldown = 0
    grab_qte_started = false
    grab_input_pending = 0
    fatal_active = false
    fatal_impact_seen = false
    fatal_impact_flash_timer = 0
    hookshot_active = false

    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then
        FEEDBACK.clear_led("parry")
        FEEDBACK.clear_led("finisher")
        FEEDBACK.clear_led("hookshot")
        FEEDBACK.clear_led("grab")
        FEEDBACK.clear_led("damage")
        FEEDBACK.clear_led("reload")
        FEEDBACK.clear_led("hp_gradient")
        FEEDBACK.clear_led("hp_danger")
        FEEDBACK.clear_led("hp_heal")
        FEEDBACK.clear_led("ammo_empty")
        FEEDBACK.clear_led("ammo_last")
        FEEDBACK.clear_led("menu")
        FEEDBACK.clear_indicator()
    end
end

local function set_gameplay_outputs(enabled)
    gameplay_outputs_enabled = enabled

    local HP = _G.HPLed
    if HP and HP.set_gameplay then HP.set_gameplay(enabled) end

    local AMMO = _G.AmmoLed
    if AMMO and AMMO.set_gameplay then AMMO.set_gameplay(enabled) end

    if enabled then
        local AUDIO = _G.DualSenseEnhancedAudio
        if AUDIO and AUDIO.reset_heal_cooldown then pcall(AUDIO.reset_heal_cooldown) end
    end
end

local function begin_pending_gameplay_enable(reason, frames)
    pending_gameplay_enable = false
    pending_gameplay_reason = nil
    pending_gameplay_log_tick = 0
    was_in_gameplay = true
    EVENTS.in_game = true
    death_state_active = false
    EVENTS.player_dead = false
    local NATIVE = _G.NativeDualSenseFeedback
    if NATIVE then
        NATIVE.loading_blackout = false
        NATIVE.death_blackout = false
    end
    clear_gameplay_outputs()
    set_gameplay_outputs(true)

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then
        MON.log("gameplay enable", tostring(reason or "start"))
    end
end

local function request_gameplay_enable(reason)
    pending_gameplay_enable = true
    pending_gameplay_reason = reason or "pending"
    pending_gameplay_log_tick = 0
    EVENTS.in_game = false
    clear_gameplay_outputs()
    set_gameplay_outputs(false)

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then
        MON.log("gameplay enable pending", tostring(pending_gameplay_reason))
    end
end

local function disable_gameplay_outputs(reason)
    pending_gameplay_enable = false
    pending_gameplay_reason = nil
    pending_gameplay_log_tick = 0
    EVENTS.in_game = false
    clear_gameplay_outputs()
    set_gameplay_outputs(false)
    flush()

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then
        MON.log("gameplay disable", tostring(reason or "stop"))
    end
end

local function poll_game_state()
    poll_tick = poll_tick + 1
    if poll_tick % POLL_INTERVAL ~= 0 then return end

    local HP = _G.HPLed
    if not HP then return end

    local ok, current_player = pcall(function()
        local pm = sdk.get_managed_singleton("chainsaw.PlayerManager")
        if not pm then return nil end
        return pm:call("get_CurrentPlayer")
    end)

    local has_current_player = ok and current_player ~= nil
    if has_current_player then
        current_player_supported = true
        current_player_missing_ticks = 0
    elseif current_player_supported then
        current_player_missing_ticks = current_player_missing_ticks + 1
    end

    local ok_ctx, player = pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then return nil end
        local p = cm:call("getPlayerContextRef")
        if not p then p = cm:call("get_ManualPlayer") end
        return p
    end)

    local has_player = ok_ctx and player ~= nil

    -- Check death via HP
    local is_dead = false
    if has_player then
        local ok2, hp_obj = pcall(function()
            return player:call("get_HitPoint")
        end)
        if ok2 and hp_obj then
            -- Dead if HP <= 0 or IsDead flag
            local ok3, cur = pcall(function() return hp_obj:call("get_CurrentHitPoint") end)
            if ok3 and cur and cur <= 0 then is_dead = true end
            -- Try IsDead flag as secondary check
            pcall(function()
                local dead_flag = hp_obj:call("get_IsDeadState")
                if dead_flag then is_dead = true end
            end)
        end
    end

    if is_dead then
        if not death_state_active then
            debug_state("death", has_player, has_current_player, is_dead)
            death_state_active = true
            EVENTS.player_dead = true
            HP.is_dead_external = true
            if HP.set_dead then HP.set_dead(true) end
            clear_gameplay_outputs()
            set_gameplay_outputs(false)
            local NATIVE = _G.NativeDualSenseFeedback
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if NATIVE and FEEDBACK and FEEDBACK.output_mode == "native" then
                NATIVE.death_blackout = true
            end
            flush()
        end
        return
    elseif has_player and death_state_active then
        if not can_enable_gameplay_outputs() then
            debug_state("death recovery wait", has_player, has_current_player, is_dead)
            clear_gameplay_outputs()
            flush()
            return
        end

        debug_state("death recovery enable", has_player, has_current_player, is_dead)
        death_state_active = false
        HP.is_dead_external = false
        if HP.set_dead then HP.set_dead(false) end

        was_in_gameplay = true
        begin_pending_gameplay_enable("death recovery")
        flush()
        return
    elseif has_player then
        if HP.is_dead_external then
            HP.is_dead_external = false
            if HP.set_dead then HP.set_dead(false) end
        end
    end

    if pending_gameplay_enable then
        if has_player and can_enable_gameplay_outputs() then
            debug_state("pending gameplay enable", has_player, has_current_player, is_dead)
            begin_pending_gameplay_enable(pending_gameplay_reason or "pending")
            flush()
        else
            pending_gameplay_log_tick = pending_gameplay_log_tick + 1
            if pending_gameplay_log_tick == 1 or pending_gameplay_log_tick % 20 == 0 then
                debug_state("pending gameplay wait", has_player, has_current_player, is_dead)
            end
            clear_gameplay_outputs()
            flush()
        end
        return
    end

    -- Gameplay fallback:
    -- CharacterManager is reliable for active gameplay in this build, while
    -- PlayerManager is only used as a stronger menu-exit signal if it ever works.
    local in_gameplay = has_player and not is_dead
    if current_player_supported
        and current_player_missing_ticks >= CURRENT_PLAYER_MISSING_LIMIT
    then
        in_gameplay = false
    end

    -- Reset Scripts mid-gameplay recovery (see reset_recovery_pending note).
    -- onStartInGame never fires on a Reset Scripts, so if we come up already
    -- in a valid, non-dead gameplay session we enable outputs ourselves.
    -- Requires HP context to stay valid for RESET_RECOVERY_CONFIRM_CYCLES
    -- consecutive polls so a script reset that lands during a level load does
    -- not enable outputs early. Disarms as soon as a real onStartInGame runs.
    if reset_recovery_pending then
        if ever_started_in_game then
            reset_recovery_pending = false
        elseif in_gameplay and has_valid_hp_context() then
            reset_recovery_confirm = reset_recovery_confirm + 1
            if reset_recovery_confirm >= RESET_RECOVERY_CONFIRM_CYCLES then
                reset_recovery_pending = false
                debug_state("reset scripts recovery enable", has_player, has_current_player, is_dead)
                was_in_gameplay = true
                ever_started_in_game = true
                begin_pending_gameplay_enable("reset scripts recovery")
                flush()
            end
            -- Hold outputs off until confirmed; skip the loading-protection
            -- guard below (which would clear on every poll while confirming).
            return
        else
            -- HP context is NOT valid on this poll. A Reset Scripts triggered
            -- mid-gameplay has rock-solid HP immediately (the engine keeps
            -- running, only Lua reloads), so a first poll without valid HP
            -- means this is instead a cold start sitting at the title/menu.
            -- Disarm permanently so recovery cannot later misfire during the
            -- initial level load, where HP context goes valid several seconds
            -- before onStartInGame -- that first real enable belongs to
            -- onStartInGame, matching Capcom's own lightbar timing.
            reset_recovery_pending = false
        end
    end

    if in_gameplay and not was_in_gameplay then
        -- Player/HP context can appear while a level is still loading.
        -- Only onStartInGame is allowed to enable gameplay outputs.
        clear_gameplay_outputs()
        flush()
        return
    end

    if in_gameplay ~= was_in_gameplay then
        debug_state(in_gameplay and "poll gameplay on" or "poll gameplay off", has_player, has_current_player, is_dead)
        was_in_gameplay = in_gameplay
        EVENTS.in_game = in_gameplay
        if not in_gameplay then
            -- Returning to the main menu re-arms the
            -- adaptive_gameplay_signal guard so the *next* load also waits
            -- for a real onStartInGame instead of reusing this session's
            -- one-time "already started once" flag. Without this,
            -- ever_started_in_game stayed true forever after the first
            -- load, so only the very first load in a process lifetime got
            -- the early-enable fix; any subsequent load/checkpoint-reload
            -- within the same session was still vulnerable.
            ever_started_in_game = false
            -- Safety: clear any blackout/death flags so returning to menu
            -- releases the lightbar back to Capcom's native blue.
            EVENTS.player_dead = false
            local NATIVE = _G.NativeDualSenseFeedback
            if NATIVE then
                NATIVE.loading_blackout = false
                NATIVE.death_blackout = false
            end
        end
        set_gameplay_outputs(in_gameplay)
        if not in_gameplay then clear_gameplay_outputs() end
        flush()
    end

    -- Push the menu LED state every poll tick, not just on a
    -- was_in_gameplay/in_gameplay transition. At the very first boot of
    -- the game, both start false (no transition is ever detected, since
    -- false == false), so the transition-only block above never applied
    -- the custom menu color at the title screen -- Capcom's own blue won
    -- by default for the entire boot/menu period before the first load.
    -- Customizable menu color requires this regardless of
    -- whether a transition just happened.
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then
        if not in_gameplay and EVENTS.menu_enabled then
            local c = EVENTS.color_menu
            FEEDBACK.set_led("menu", c[1], c[2], c[3], 2)
            flush()
        elseif not in_gameplay then
            FEEDBACK.clear_led("menu")
        end
    end
end

local function adaptive_gameplay_signal(method_name)
    -- Hardware-confirmed 2025-06-30 (Capcom lightbar color logging
    -- diagnostic): on a fresh session, HP/PlayerManager adaptive-feedback
    -- activity (this hook's trigger) goes valid mid-level-load, several
    -- seconds before CampaignManager.onStartInGame fires -- which is the
    -- moment Capcom's own native lightbar switches from boot/menu blue to
    -- gameplay color. Enabling gameplay outputs here unconditionally made
    -- the custom lightbar/HP LED light up during loading, ahead of real
    -- gameplay. This signal is only a valid *recovery* path for
    -- death/Continue (where gameplay already started at least once this
    -- session); gate it on that so the very first load always waits for
    -- the real onStartInGame, matching Capcom's own timing.
    if not ever_started_in_game then return end
    if not has_valid_hp_context() then return end
    if gameplay_outputs_enabled and not pending_gameplay_enable and not death_state_active then return end

    debug_state("adaptive gameplay enable " .. tostring(method_name), nil, nil, nil)
    death_state_active = false

    local HP = _G.HPLed
    if HP then
        HP.is_dead_external = false
        if HP.set_dead then HP.set_dead(false) end
    end

    begin_pending_gameplay_enable("adaptive " .. tostring(method_name))
    flush()
end

-- ----------------------------------------------------------------
-- Grab escape input flash
-- ----------------------------------------------------------------
local function trigger_grab_flash(source)
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end

    if not EVENTS.enabled then return end
    if not grab_active then return end
    if grab_flash_cooldown > 0 then return end

    grab_flash_timer = math.max(1, EVENTS.grab_flash_duration or EVENTS.defaults.grab_flash_duration)
    grab_flash_cooldown = GRAB_FLASH_COOLDOWN_FRAMES
    grab_qte_started = true
    FEEDBACK.set_led("grab", 255, 255, 255, 90)
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("grab input" .. (source and (": " .. source) or "")) end
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO and AUDIO.play_qte then pcall(AUDIO.play_qte) end
    flush()
    return
end

-- ----------------------------------------------------------------
-- Triggers
-- ----------------------------------------------------------------
local function trigger_parry()
    if not EVENTS.enabled then return end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    grab_active  = false
    grab_flash_timer = 0
    grab_flash_cooldown = 0
    grab_qte_started = false
    grab_input_pending = 0
    FEEDBACK.clear_led("grab")
    FEEDBACK.clear_led("damage")
    local c = EVENTS.color_parry
    FEEDBACK.set_led("parry", c[1], c[2], c[3], 100)
    parry_timer = EVENTS.parry_duration
    parry_black_at = math.floor(parry_timer / 2)
    parry_black_started = false
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("parry", "onHitParry hook fired -- diag window opened") end
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO and AUDIO.play_parry then pcall(AUDIO.play_parry) end
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    -- 120 frames (~2s) window: parry Wwise events sometimes arrive late;
    -- pre-roll captures events that fired just before onHitParry.
    if DIAG and DIAG.begin_window then pcall(DIAG.begin_window, "parry", 120) end
    flush()
end

local function trigger_grab()
    if not EVENTS.enabled then return end
    if parry_timer > 0 then return end
    if grab_active then return end
    grab_active  = true
    grab_flash_timer = 0
    grab_flash_cooldown = 0
    grab_qte_started = false
    grab_input_pending = 0
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("grab start") end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    FEEDBACK.clear_led("grab")
    flush()
end

local function trigger_damage()
    if not EVENTS.enabled then return end
    if parry_timer > 0 then return end
    if grab_active then return end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    local c = EVENTS.color_damage
    FEEDBACK.set_led("damage", c[1], c[2], c[3], 80)
    damage_timer = EVENTS.damage_duration
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("damage") end
    flush()
end

local function trigger_reload()
    local CORE = _G.WeaponEquipCore
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO and AUDIO.begin_reload_session then
        local ok, supported = pcall(AUDIO.begin_reload_session, CORE and CORE.last_info)
        if ok and supported then
            reload_audio_active = true
            reload_audio_end_pending = 0
            local MON = _G.DualSenseEnhancedMonitor
            if MON and MON.log then MON.log("reload audio start") end
        end
    end

    if not EVENTS.reload_lightbar_enabled then return end
    if not EVENTS.enabled then return end
    if parry_timer > 0 or grab_active or damage_timer > 0 then return end
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    local c = EVENTS.color_reload
    FEEDBACK.set_led("reload", c[1], c[2], c[3], 30)
    reload_timer = RELOAD_DURATION
    reload_grace = RELOAD_GRACE_FRAMES
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("reload lightbar") end
    flush()
end

local function request_reload()
    local DIAG = _G.DualSenseEnhancedSoundEventDiag
    if DIAG and DIAG.begin_window then
        pcall(DIAG.begin_window, "reload_request", 180)
    end
    local AUDIO = _G.DualSenseEnhancedAudio
    local wants_audio = AUDIO and AUDIO.enabled and AUDIO.reload_enabled
    local wants_lightbar = EVENTS.enabled and EVENTS.reload_lightbar_enabled
    if not wants_audio and not wants_lightbar then return end
    reload_pending = RELOAD_CONFIRM_FRAMES
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("reload requested") end
end

local function is_reloading_now()
    local ok, result = pcall(function()
        local pm = sdk.get_managed_singleton("chainsaw.PlayerManager")
        local player = pm and pm:call("get_CurrentPlayer")
        if not player then
            local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
            player = cm and (cm:call("getPlayerContextRef") or cm:call("get_ManualPlayer"))
        end
        if not player then return false end

        -- Reload state belongs to PlayerBaseContext in this RE4R build.
        local reloading = false
        pcall(function()
            if player:call("get_IsReloading") then reloading = true end
        end)
        pcall(function()
            if player:call("get_IsExReload") then reloading = true end
        end)
        if reloading then return true end

        -- Older fallback retained for builds exposing state through equipment.
        local equip = player:call("get_Equipment")
        if not equip then equip = player:call("get_PlayerEquipment") end
        if not equip then return false end

        pcall(function()
            if equip:call("get_IsTacticalReload") then reloading = true end
        end)
        pcall(function()
            if equip:call("isLoopReload") then reloading = true end
        end)
        return reloading
    end)
    return ok and result == true
end

local function get_player_self_context()
    local ok, context = pcall(function()
        local scene_manager = sdk.get_native_singleton("via.SceneManager")
        if not scene_manager then return nil end
        local scene = sdk.call_native_func(scene_manager, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        if not scene then return nil end
        local obj = scene:call("findGameObject(System.String)", "PlayerInventoryObserver")
        if not obj then return nil end
        local observer_component = obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerInventoryObserver"))
        if not observer_component then return nil end
        local observer = observer_component:get_field("_Observer")
        if not observer then return nil end
        return observer:get_field("_SelfCharacterContext")
    end)
    if ok then return context end
    return nil
end

local function is_fatal_kick_now()
    local context = get_player_self_context()
    if not context then return false end
    local active = false
    pcall(function()
        if context:get_IsFatalKick() then active = true end
    end)
    pcall(function()
        if context:get_IsFatalRoundKick() then active = true end
    end)
    return active
end

local function is_hookshot_now()
    local context = get_player_self_context()
    if not context then return false end
    local active = false
    pcall(function()
        if context:get_IsHookShot() then active = true end
    end)
    return active
end

local function update_fatal_kick()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    if not EVENTS.enabled or not gameplay_outputs_enabled or death_state_active then
        if fatal_active then
            fatal_active = false
            fatal_impact_seen = false
            fatal_impact_flash_timer = 0
            FEEDBACK.clear_led("finisher")
            flush()
        end
        return
    end

    local active = is_fatal_kick_now()
    if active then
        if not fatal_active then
            fatal_active = true
            fatal_impact_seen = false
            fatal_impact_flash_timer = 0
            local MON = _G.DualSenseEnhancedMonitor
            if MON and MON.log then MON.log("fatal kick") end
        end

        if fatal_impact_flash_timer > 0 then
            fatal_impact_flash_timer = fatal_impact_flash_timer - 1
            local c = EVENTS.color_fatal
            FEEDBACK.set_led("finisher", c[1], c[2], c[3], 85)
        else
            FEEDBACK.set_led("finisher", 0, 0, 0, 85)
        end
        flush()
    elseif fatal_active then
        fatal_active = false
        fatal_impact_seen = false
        fatal_impact_flash_timer = 0
        FEEDBACK.clear_led("finisher")
        flush()
    end
end

local function update_hookshot()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    if not EVENTS.enabled or not gameplay_outputs_enabled or death_state_active then
        if hookshot_active then
            hookshot_active = false
            FEEDBACK.clear_led("hookshot")
            flush()
        end
        return
    end

    local active = is_hookshot_now()
    if active then
        local c = EVENTS.color_hookshot
        FEEDBACK.set_led("hookshot", c[1], c[2], c[3], 84)
        if not hookshot_active then
            hookshot_active = true
            local MON = _G.DualSenseEnhancedMonitor
            if MON and MON.log then MON.log("hookshot") end
        end
        flush()
    elseif hookshot_active then
        hookshot_active = false
        FEEDBACK.clear_led("hookshot")
        flush()
    end
end

local function stop_grab(reason)
    if grab_active then
        local MON = _G.DualSenseEnhancedMonitor
        if MON and MON.log then MON.log("grab end", tostring(reason or "unknown")) end
    end
    grab_active  = false
    grab_flash_timer = 0
    grab_flash_cooldown = 0
    grab_qte_started = false
    grab_input_pending = 0
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then FEEDBACK.clear_led("grab") end
    flush()
end

local function reset_all()
    parry_timer  = 0
    parry_black_at = 0
    parry_black_started = false
    damage_timer = 0
    reload_timer = 0
    reload_grace = 0
    reload_pending = 0
    reload_audio_active = false
    reload_audio_end_pending = 0
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO then
        AUDIO.reload_session_active = false
        AUDIO.reload_insert_grace = 0
        AUDIO.reload_finish_played = false
    end
    grab_active  = false
    grab_flash_timer = 0
    grab_flash_cooldown = 0
    grab_qte_started = false
    grab_input_pending = 0
    fatal_active = false
    fatal_impact_seen = false
    fatal_impact_flash_timer = 0
    hookshot_active = false
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if FEEDBACK then
        FEEDBACK.clear_led("parry")
        FEEDBACK.clear_led("finisher")
        FEEDBACK.clear_led("hookshot")
        FEEDBACK.clear_led("grab")
        FEEDBACK.clear_led("damage")
        FEEDBACK.clear_led("reload")
    end
end

-- ----------------------------------------------------------------
-- Hooks (only confirmed-working ones)
-- ----------------------------------------------------------------
local function install_hooks()
    if hooks_installed then return end

    -- Parry
    local head = sdk.find_type_definition("chainsaw.PlayerHeadActionSign")
    if head then
        local m = head:get_method("onHitParry")
        if m then
            sdk.hook(m, function() end, function(r)
                if is_current_generation() then pcall(trigger_parry) end
                return r
            end)
            print("[EventsLed] onHitParry OK")
        end
        local d = head:get_method("onHitDamageCheck")
        if d then
            sdk.hook(d, function() end, function(r)
                if not is_current_generation() then return r end
                pcall(trigger_damage)
                return r
            end)
            print("[EventsLed] onHitDamageCheck OK")
        end
    end

    -- Fatal kick impact: only accept enemy damage while the confirmed
    -- FatalKick/FatalRoundKick player state is active.
    local enemy_hit = sdk.find_type_definition("chainsaw.EnemyBodyHitDriver")
    if enemy_hit then
        local m = enemy_hit:get_method("onHitDamage")
        if m then
            sdk.hook(m, function() end, function(r)
                if is_current_generation() then
                    local AUDIO = _G.DualSenseEnhancedAudio
                    if fatal_active and not fatal_impact_seen then
                        fatal_impact_seen = true
                        fatal_impact_flash_timer = math.max(
                            1,
                            EVENTS.fatal_impact_duration or EVENTS.defaults.fatal_impact_duration
                        )
                        local MON = _G.DualSenseEnhancedMonitor
                        if MON and MON.log then MON.log("fatal kick impact") end
                        if AUDIO and AUDIO.play_fatal_kick then
                            pcall(AUDIO.play_fatal_kick)
                        end
                        local DIAG = _G.DualSenseEnhancedSoundEventDiag
                        if DIAG and DIAG.begin_window then
                            pcall(DIAG.begin_window, "fatal_kick", 60)
                        end
                    end
                end
                return r
            end)
            print("[EventsLed] EnemyBodyHitDriver.onHitDamage fatal impact OK")
        else
            debug_log("[EventsLed] EnemyBodyHitDriver.onHitDamage NOT FOUND")
        end
    else
        debug_log("[EventsLed] EnemyBodyHitDriver NOT FOUND")
    end

    -- Melee.onHitAttack was here (knife hit audio). Removed 2026-07-08:
    -- Wwise event 2846967310 in wwise_audio_router.lua covers knife hits
    -- in campaign with correct context; the Lua hook caused double-fires.

    -- Exact grab-QTE widget lifecycle.
    local grab_gui = sdk.find_type_definition("chainsaw.LargeActionSign_Grab3GuiBehavior")
    if grab_gui then
        local receive_method = grab_gui:get_method("recieveGuiParam")
        if receive_method then
            sdk.hook(receive_method, function() end, function(r)
                if is_current_generation() and not grab_active then
                    local MON = _G.DualSenseEnhancedMonitor
                    if MON and MON.log then MON.log("grab gui open") end
                    pcall(trigger_grab)
                end
                return r
            end)
            print("[EventsLed] LargeActionSign_Grab3GuiBehavior.recieveGuiParam OK")
        else
            debug_log("[EventsLed] LargeActionSign_Grab3GuiBehavior.recieveGuiParam NOT FOUND")
        end

        local deactivate_method = grab_gui:get_method("onDeactivateEvent")
        if deactivate_method then
            sdk.hook(deactivate_method, function() end, function(r)
                if is_current_generation() and grab_active then
                    local MON = _G.DualSenseEnhancedMonitor
                    if MON and MON.log then MON.log("grab gui close") end
                    pcall(stop_grab, "gui close")
                end
                return r
            end)
            print("[EventsLed] LargeActionSign_Grab3GuiBehavior.onDeactivateEvent OK")
        else
            debug_log("[EventsLed] LargeActionSign_Grab3GuiBehavior.onDeactivateEvent NOT FOUND")
        end
    else
        debug_log("[EventsLed] LargeActionSign_Grab3GuiBehavior NOT FOUND")
    end

    -- Finisher / knife fatal research from Object Explorer.
    pcall(debug_type_methods, "chainsaw.EnemyBehaviorTreeAction_MFSM_EnableKnifeFatal", "")
    pcall(debug_type_methods, "chainsaw.EnemyHeadUpdater.KnifeFatalInfo", "")
    pcall(debug_type_methods, "chainsaw.Ch1c0HeadUpdaterCommon", "fatal")

    -- Continue/loading/gameplay-state research. These diagnostics are
    -- intentionally broad; they only enumerate method names in events_debug.txt.
    pcall(debug_type_methods, "chainsaw.GameFlowManager", "")
    pcall(debug_type_methods, "chainsaw.SceneManager", "")
    pcall(debug_type_methods, "chainsaw.TitleManager", "")
    pcall(debug_type_methods, "chainsaw.LoadingManager", "")
    pcall(debug_type_methods, "chainsaw.PlayerManager", "")
    pcall(debug_type_methods, "chainsaw.PlayerController", "control")
    pcall(debug_type_methods, "chainsaw.PlayerBaseContext", "control")
    pcall(debug_type_methods, "chainsaw.PlayerBaseContext", "load")
    pcall(debug_type_methods, "chainsaw.CampaignManager", "load")
    pcall(debug_type_methods, "chainsaw.CampaignManager", "continue")
    pcall(debug_type_methods, "chainsaw.CampaignManager", "game")

    -- Reload start
    local equip = sdk.find_type_definition("chainsaw.PlayerEquipment")
    if equip then
        local m = equip:get_method("execReloadStart")
        local method_name = "execReloadStart"
        if not m then
            m = equip:get_method("execReload")
            method_name = "execReload"
        end
        if m then
            sdk.hook(m, function() end, function(r)
                if is_current_generation() then pcall(request_reload) end
                return r
            end)
            debug_log("[EventsLed] " .. method_name .. " OK")
            print("[EventsLed] " .. method_name .. " OK")
        else
            debug_log("[EventsLed] chainsaw.PlayerEquipment reload hook NOT FOUND")
            pcall(debug_methods_matching, equip, "chainsaw.PlayerEquipment", "reload")
        end
    else
        debug_log("[EventsLed] chainsaw.PlayerEquipment NOT FOUND")
    end

    hook_methods_named(
        "chainsaw.PlayerManager",
        {
            "updateAdaptiveFeedBack",
            "updatePlayerAdaptiveFeedBackParam",
            "updatePlayerAdaptiveFeedBackParamMcPlus",
            "setAdaptiveTriggerFeedback",
        },
        "adaptive gameplay signal",
        adaptive_gameplay_signal
    )

    -- onStartInGame: set gameplay=true
    local camp = sdk.find_type_definition("chainsaw.CampaignManager")
    if camp then
        local m_setup = camp:get_method("onStartInGameSetup")
        if m_setup then
            sdk.hook(m_setup, function() end, function(r)
                if not is_current_generation() then return r end
                pcall(function()
                    debug_state("onStartInGameSetup", nil, nil, nil)
                    -- This hook can fire while the level is still loading.
                    -- Always clear stale gameplay LED sources here; otherwise
                    -- a previous HP/custom color can leak into the loading
                    -- screen until the next real gameplay enable.
                    clear_gameplay_outputs()
                    set_gameplay_outputs(false)
                    -- Suppress native Capcom blue during level loading.
                    -- Cleared only when gameplay outputs are actually enabled
                    -- (begin_pending_gameplay_enable), not at the earlier
                    -- onStartInGame hook, because HP/weapon state can still
                    -- lag behind by a few seconds there.
                    local NATIVE = _G.NativeDualSenseFeedback
                    local FEEDBACK = _G.DualSenseEnhancedFeedback
                    if NATIVE and FEEDBACK and FEEDBACK.output_mode == "native" then
                        NATIVE.loading_blackout = true
                    end
                end)
                return r
            end)
            debug_log("[EventsLed] onStartInGameSetup OK")
        end

        local m = camp:get_method("onStartInGame")
        if m then
            sdk.hook(m, function() end, function(r)
                if not is_current_generation() then return r end
                pcall(function()
                    debug_state("onStartInGame", nil, nil, nil)
                    ever_started_in_game = true
                    reset_all()
                    local FEEDBACK = _G.DualSenseEnhancedFeedback
                    if FEEDBACK then FEEDBACK.clear_led("menu") end
                    if not can_enable_gameplay_outputs() then
                        request_gameplay_enable("onStartInGame wait hp/weapon")
                    elseif death_state_active or was_in_gameplay then
                        begin_pending_gameplay_enable("onStartInGame retry")
                    else
                        begin_pending_gameplay_enable("onStartInGame")
                    end
                    flush()
                end)
                return r
            end)
            print("[EventsLed] onStartInGame OK")
        end

        local m_cleanup = camp:get_method("onStartInGameCleanup")
        if m_cleanup then
            sdk.hook(m_cleanup, function() end, function(r)
                if not is_current_generation() then return r end
                pcall(function()
                    debug_state("onStartInGameCleanup", nil, nil, nil)
                    if can_enable_gameplay_outputs() then
                        begin_pending_gameplay_enable("onStartInGameCleanup")
                    else
                        request_gameplay_enable("onStartInGameCleanup wait hp/weapon")
                    end
                    flush()
                end)
                return r
            end)
            debug_log("[EventsLed] onStartInGameCleanup OK")
            print("[EventsLed] onStartInGameCleanup OK")
        end
    end

    hooks_installed = true
    print("[EventsLed] hooks installed")
end

local function on_update_hid()
    if not is_current_generation() then return end
    if not gp_singleton or not gp_typedef then return end

    local ok, held = pcall(function()
        local pad = sdk.call_native_func(gp_singleton, gp_typedef, "getMergedDevice", 0)
        if not pad then return false end
        local buttons = pad:call("get_Button")
        if not buttons then return false end
        return (buttons | GRAB_ESCAPE_BUTTON) == buttons
    end)

    if not ok then return end

    local pressed = held and not cross_was_down
    cross_was_down = held

    if pressed and EVENTS.enabled and grab_active then
        grab_input_pending = grab_input_pending + 1
    end
end

-- ----------------------------------------------------------------
-- Per-frame update
-- ----------------------------------------------------------------
local function on_update()
    if not is_current_generation() then return end
    if not hooks_installed then pcall(install_hooks); return end

    -- Poll game state for menu/death detection
    poll_game_state()
    update_fatal_kick()
    update_hookshot()

    if grab_input_pending > 0 then
        grab_input_pending = 0
        trigger_grab_flash("button")
    end

    if grab_flash_cooldown > 0 then
        grab_flash_cooldown = grab_flash_cooldown - 1
    end

    if grab_flash_timer > 0 then
        grab_flash_timer = grab_flash_timer - 1
        if grab_flash_timer == 0 then
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if FEEDBACK then
                if grab_active and grab_qte_started then
                    FEEDBACK.set_led("grab", 0, 0, 0, 90)
                else
                    FEEDBACK.clear_led("grab")
                end
            end
            flush()
        end
    end

    if parry_timer > 0 then
        parry_timer = parry_timer - 1
        if not parry_black_started and parry_timer <= parry_black_at then
            parry_black_started = true
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if FEEDBACK then FEEDBACK.set_led("parry", 0, 0, 0, 100) end
            flush()
        end
        if parry_timer == 0 then
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if FEEDBACK then FEEDBACK.clear_led("parry") end
            parry_black_at = 0
            parry_black_started = false
            flush()
        end
    end

    if reload_pending > 0 then
        if is_reloading_now() then
            reload_pending = 0
            trigger_reload()
        else
            reload_pending = reload_pending - 1
            if reload_pending == 0 then
                local MON = _G.DualSenseEnhancedMonitor
                if MON and MON.log then MON.log("reload confirmation timeout") end
            end
        end
    end

    if reload_audio_active then
        if is_reloading_now() then
            reload_audio_end_pending = 0
        else
            reload_audio_end_pending = reload_audio_end_pending + 1
            if reload_audio_end_pending >= RELOAD_AUDIO_END_CONFIRM_FRAMES then
                reload_audio_active = false
                reload_audio_end_pending = 0
                local CORE = _G.WeaponEquipCore
                local AUDIO = _G.DualSenseEnhancedAudio
                if AUDIO then
                    AUDIO.reload_session_active = false
                    AUDIO.reload_insert_grace = 30
                end
                local finish_played = false
                if AUDIO and AUDIO.play_reload_finish then
                    local ok, played = pcall(AUDIO.play_reload_finish, CORE and CORE.last_info)
                    finish_played = ok and played == true
                end
                local MON = _G.DualSenseEnhancedMonitor
                if MON and MON.log then
                    MON.log(finish_played and "reload audio finish" or "reload session finish")
                end
            end
        end
    end

    if reload_timer > 0 then
        if is_reloading_now() then
            reload_timer = RELOAD_DURATION
            reload_grace = RELOAD_GRACE_FRAMES
        else
            reload_timer = reload_timer - 1
            if reload_grace > 0 then
                reload_grace = reload_grace - 1
                reload_timer = math.max(reload_timer, reload_grace)
            end
        end
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            local c = EVENTS.color_reload
            FEEDBACK.set_led("reload", c[1], c[2], c[3], 30)
        end
        if reload_timer == 0 then
            if FEEDBACK then FEEDBACK.clear_led("reload") end
            flush()
        else
            flush()
        end
    end

    if damage_timer > 0 then
        damage_timer = damage_timer - 1
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            local c = EVENTS.color_damage
            FEEDBACK.set_led("damage", c[1], c[2], c[3], 80)
        end
        if damage_timer == 0 then
            if FEEDBACK then FEEDBACK.clear_led("damage") end
            flush()
        else
            flush()
        end
    end
end

pcall(install_hooks)
pcall(function() re.on_application_entry("UpdateHID", on_update_hid) end)
pcall(function() re.on_application_entry("UpdateBehavior", on_update) end)

_G.EventsLed = EVENTS
