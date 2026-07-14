local re   = re
local math = math

_G.DualSenseEnhancedAmmoLedGeneration = (_G.DualSenseEnhancedAmmoLedGeneration or 0) + 1
local generation = _G.DualSenseEnhancedAmmoLedGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedAmmoLedGeneration == generation
end

-- ================================================================
-- ammo_led.lua - Empty mag blink, ammo indicator (5 LEDs)
-- Two indicator modes:
--   warning      - silent until <=threshold, then counts down
--   proportional - always shows ammo/max scaled to 5 LEDs
-- ================================================================

local AMMO = {}
AMMO.enabled          = true
AMMO.mode             = "warning"   -- "warning" | "proportional"
AMMO.warn_threshold   = 5           -- warning mode: show when ammo <= this
AMMO.color_empty      = {255, 80, 0}  -- amber pulse on empty mag
AMMO.color_last       = {255, 80, 0}  -- last bullet indicator colour (unused on lightbar)
AMMO.pulse_min_brightness = 0.25      -- empty-mag lightbar pulse floor (never literal black)
AMMO.pulse_push_interval = 2          -- frames between LED bus pushes while pulsing (perf)
AMMO.pulse_steps = 12                 -- quantization steps per pulse cycle (perf + still smooth)
AMMO.defaults = {
    ammo_blink_rate = 20,
    reload_count_hold = 45,
    reload_blink_rate = 8,
    reload_blink_count = 2,
}
AMMO.ammo_blink_rate = AMMO.defaults.ammo_blink_rate
AMMO.reload_count_hold = AMMO.defaults.reload_count_hold
AMMO.reload_blink_rate = AMMO.defaults.reload_blink_rate
AMMO.reload_blink_count = AMMO.defaults.reload_blink_count
AMMO.mic_led_enabled = true
AMMO.mic_led_empty_enabled = true
AMMO.mic_led_reload_enabled = true
AMMO.mic_led_reload_frames = 60

function AMMO.reset_defaults()
    AMMO.ammo_blink_rate = AMMO.defaults.ammo_blink_rate
    AMMO.reload_count_hold = AMMO.defaults.reload_count_hold
    AMMO.reload_blink_rate = AMMO.defaults.reload_blink_rate
    AMMO.reload_blink_count = AMMO.defaults.reload_blink_count
    AMMO.mic_led_enabled = true
    AMMO.mic_led_empty_enabled = true
    AMMO.mic_led_reload_enabled = true
    AMMO.mic_led_reload_frames = 60
end

local blink_on    = false
local blink_cnt   = 0
local pulse_push_tick = 0

local last_ammo    = -1
local last_ammoMax = -1
local last_weapon_id = nil

local tick = 0
local in_gameplay = false

local reload_mode          = "none" -- "none" | "count" | "blink"
local reload_hold          = 0
local reload_blink_on      = false
local reload_blink_tick    = 0
local reload_blink_toggles = 0
local broken_butterfly_postshot_pending = 0
local handcannon_postshot_pending = 0
local reload_finish_pending = 0
local reload_finish_info = nil
local BROKEN_BUTTERFLY_POSTSHOT_DELAY_FRAMES = 12
local HANDCANNON_POSTSHOT_DELAY_FRAMES = 60
local FULL_RELOAD_FINISH_DELAY_FRAMES = 6

local function flush()
    local FEEDBACK  = _G.DualSenseEnhancedFeedback
    local CORE = _G.WeaponEquipCore
    if FEEDBACK and FEEDBACK.apply_for_weapon and CORE and CORE.last_info then
        pcall(FEEDBACK.apply_for_weapon, CORE.last_info)
    end
end

local function is_melee(wtype)
    return wtype == "knf" or wtype == "knife"
        or wtype == "grenade" or wtype == "thrw"
end

local function set_indicator_count(count)
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    local lit = math.max(0, math.min(5, count or 0))
    FEEDBACK.set_indicator(lit >= 1, lit >= 2, lit >= 3, lit >= 4, lit >= 5)
end

local function set_mic_empty(active)
    local MIC = _G.DualSenseEnhancedMicLED
    if not MIC or not MIC.set_empty then return end
    MIC.set_empty(AMMO.mic_led_enabled and AMMO.mic_led_empty_enabled and active)
end

local function pulse_mic_reload()
    local MIC = _G.DualSenseEnhancedMicLED
    if not MIC or not MIC.pulse_reload then return end
    if not AMMO.mic_led_enabled or not AMMO.mic_led_reload_enabled then return end
    MIC.pulse_reload(math.max(1, AMMO.mic_led_reload_frames or 45))
end

local function update_indicator(ammo, ammoMax, melee)
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end

    if not in_gameplay then
        FEEDBACK.clear_indicator()
        return
    end

    if melee or ammoMax <= 0 then
        FEEDBACK.clear_indicator()
        return
    end

    local p1, p2, p3, p4, p5 = false, false, false, false, false

    if AMMO.mode == "proportional" then
        -- Always show scaled proportion
        local ratio = ammo / ammoMax
        local lit   = math.max(0, math.min(5, math.ceil(ratio * 5)))
        p1 = lit >= 1
        p2 = lit >= 2
        p3 = lit >= 3
        p4 = lit >= 4
        p5 = lit >= 5
        if ammo == 1 then p1 = blink_on end

    else
        -- Warning mode: only show when <= threshold
        if ammo > 0 and ammo <= AMMO.warn_threshold then
            local lit = math.min(ammo, 5)
            p1 = lit >= 1
            p2 = lit >= 2
            p3 = lit >= 3
            p4 = lit >= 4
            p5 = lit >= 5
            if ammo == 1 then p1 = blink_on end
        end
    end

    FEEDBACK.set_indicator(p1, p2, p3, p4, p5)
end

local function stop_reload_feedback(ammo, ammoMax, melee)
    reload_mode          = "none"
    reload_hold          = 0
    reload_blink_on      = false
    reload_blink_tick    = 0
    reload_blink_toggles = 0
    update_indicator(ammo or 0, ammoMax or 0, melee)
end

local function start_reload_count(ammo)
    reload_mode = "count"
    reload_hold = math.max(1, AMMO.reload_count_hold)
    set_indicator_count(ammo)
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("reload count", tostring(ammo)) end
end

local function start_reload_blink()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    reload_mode          = "blink"
    reload_blink_on      = true
    reload_blink_tick    = math.max(1, AMMO.reload_blink_rate)
    reload_blink_toggles = math.max(1, AMMO.reload_blink_count) * 2
    FEEDBACK.set_indicator(true, true, true, true, true)
    pulse_mic_reload()
    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then MON.log("reload blink", tostring(AMMO.reload_blink_count) .. "x") end
end

local function tick_reload_feedback(ammo, ammoMax, melee)
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK or reload_mode == "none" then return false end

    if reload_mode == "count" then
        reload_hold = reload_hold - 1
        set_indicator_count(ammo)
        flush()
        if reload_hold <= 0 then
            stop_reload_feedback(ammo, ammoMax, melee)
            flush()
            return false
        end
        return true
    end

    if reload_mode == "blink" then
        reload_blink_tick = reload_blink_tick - 1
        if reload_blink_tick <= 0 then
            reload_blink_tick = math.max(1, AMMO.reload_blink_rate)
            reload_blink_on = not reload_blink_on
            reload_blink_toggles = reload_blink_toggles - 1
            if reload_blink_toggles <= 0 then
                stop_reload_feedback(ammo, ammoMax, melee)
                flush()
                return false
            end
        end

        FEEDBACK.set_indicator(
            reload_blink_on, reload_blink_on, reload_blink_on,
            reload_blink_on, reload_blink_on
        )
        flush()
        return true
    end

    return false
end

function AMMO.set_gameplay(val)
    in_gameplay = val
    blink_on     = false
    blink_cnt    = 0
    pulse_push_tick = 0
    AMMO.empty_pulse_active = false
    AMMO.empty_pulse_on = false
    last_ammo    = -1
    last_ammoMax = -1
    last_weapon_id = nil
    reload_mode          = "none"
    reload_hold          = 0
    reload_blink_on      = false
    reload_blink_tick    = 0
    reload_blink_toggles = 0
    broken_butterfly_postshot_pending = 0
    handcannon_postshot_pending = 0
    reload_finish_pending = 0
    reload_finish_info = nil
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO and AUDIO.reset_reload_audio_state then
        pcall(AUDIO.reset_reload_audio_state)
    end

    if not val then
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            FEEDBACK.clear_led("ammo_empty")
            FEEDBACK.clear_led("ammo_last")
            FEEDBACK.clear_indicator()
        end
        set_mic_empty(false)
        flush()
    end
end

local function on_update()
    if not is_current_generation() then return end
    if not AMMO.enabled then return end
    tick = tick + 1

    if not in_gameplay then
        return
    end

    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO and (AUDIO.reload_insert_grace or 0) > 0 then
        AUDIO.reload_insert_grace = AUDIO.reload_insert_grace - 1
    end
    if broken_butterfly_postshot_pending > 0 then
        broken_butterfly_postshot_pending = broken_butterfly_postshot_pending - 1
        if broken_butterfly_postshot_pending == 0
            and AUDIO and AUDIO.play_broken_butterfly_postshot then
            pcall(AUDIO.play_broken_butterfly_postshot)
        end
    end
    if handcannon_postshot_pending > 0 then
        handcannon_postshot_pending = handcannon_postshot_pending - 1
        if handcannon_postshot_pending == 0
            and AUDIO and AUDIO.play_handcannon_postshot then
            pcall(AUDIO.play_handcannon_postshot)
        end
    end
    if reload_finish_pending > 0 then
        reload_finish_pending = reload_finish_pending - 1
        if reload_finish_pending == 0
            and AUDIO and AUDIO.play_reload_finish then
            pcall(AUDIO.play_reload_finish, reload_finish_info)
            reload_finish_info = nil
        end
    end

    local CORE = _G.WeaponEquipCore
    if not CORE or not CORE.last_info then return end

    local info    = CORE.last_info
    local ammo    = info.ammo    or 0
    local ammoMax = info.ammoMax or 0
    local weapon_id = tostring(info.id or info.name or "none")
    local wtype   = info.type    or "none"
    local melee   = is_melee(wtype)

    local is_empty    = (ammo == 0 and ammoMax > 0 and not melee)
    local is_last_one = (ammo == 1 and ammoMax > 1 and not melee)
    local needs_blink = is_empty or is_last_one
    local reload_feedback_active = tick_reload_feedback(ammo, ammoMax, melee)

    -- Drawing a weapon that is already empty/last-bullet should show empty
    -- LED/Mic-LED feedback immediately, not after waiting out a partial
    -- pulse cycle.
    local weapon_changed = weapon_id ~= last_weapon_id
    if weapon_changed and needs_blink then
        blink_cnt = 0
        pulse_push_tick = math.max(0, AMMO.pulse_push_interval - 1)
    end

    if needs_blink then
        -- Smooth brightness pulse instead of a hard on/off blink, matching
        -- hp_led.lua's vital_danger_rgb style (continuous colour, never a
        -- literal black frame). A hard on/off cycle here was reported as
        -- not reliably visible on the native lightbar.
        --
        -- Phase advances every frame for correct real-time pacing, but the
        -- actual LED bus write/flush() below is throttled to once every
        -- AMMO.pulse_push_interval frames and brightness is quantized to
        -- AMMO.pulse_steps discrete levels. Pushing a near-continuous value
        -- every single frame measurably increased native lightbar HID
        -- write/enforcement traffic (reported as stutter) because almost
        -- every frame produced a distinct rounded colour, unlike the old
        -- 2-state hard blink. Quantizing means consecutive pushes often
        -- resolve to the same colour and get deduped by native_feedback.lua's
        -- own signature check, while still looking smooth at this many steps.
        local period = math.max(2, AMMO.ammo_blink_rate * 2)
        blink_cnt = (blink_cnt + 1) % period
        local phase = blink_cnt / period
        local raw_brightness = AMMO.pulse_min_brightness
            + (1 - AMMO.pulse_min_brightness)
            * (0.5 + 0.5 * math.sin(2 * math.pi * phase))
        local steps = math.max(2, AMMO.pulse_steps)
        local brightness = math.floor(raw_brightness * steps + 0.5) / steps
        blink_on = brightness > 0.5
        -- Exposed so dualib_trigger_ipc.lua's Mic LED can read the exact
        -- same phase this frame computed for the lightbar, instead of
        -- relying on duaLib's firmware-driven Breathing mode (which
        -- animates on its own timing and would drift out of sync).
        -- empty_pulse_active distinguishes "currently driving the
        -- empty-mag lightbar pulse" from mic_led.lua's other Pulse use
        -- (the short reload-finish blip), which has no lightbar to sync to.
        AMMO.empty_pulse_active = is_empty
        AMMO.empty_pulse_on = is_empty and blink_on or false

        pulse_push_tick = pulse_push_tick + 1
        if pulse_push_tick >= math.max(1, AMMO.pulse_push_interval) then
            pulse_push_tick = 0
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if FEEDBACK then
                if is_empty then
                    local c = AMMO.color_empty
                    local r = math.floor(c[1] * brightness + 0.5)
                    local g = math.floor(c[2] * brightness + 0.5)
                    local b = math.floor(c[3] * brightness + 0.5)
                    FEEDBACK.set_led("ammo_empty", r, g, b, 20)
                    FEEDBACK.clear_led("ammo_last")
                    set_mic_empty(true)
                else
                    FEEDBACK.clear_led("ammo_empty")
                    FEEDBACK.clear_led("ammo_last")
                    set_mic_empty(false)
                end
            end

            if not reload_feedback_active then
                update_indicator(ammo, ammoMax, melee)
            end
            flush()
        end
    else
        blink_on  = false
        blink_cnt = 0
        pulse_push_tick = 0
        AMMO.empty_pulse_active = false
        AMMO.empty_pulse_on = false
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            FEEDBACK.clear_led("ammo_empty")
            FEEDBACK.clear_led("ammo_last")
            set_mic_empty(false)
        end
    end

    if ammo ~= last_ammo or ammoMax ~= last_ammoMax then
        local ammo_delta = 0
        local same_weapon = last_weapon_id ~= nil and weapon_id == last_weapon_id
        if same_weapon and last_ammo >= 0 and ammoMax > 0 and not melee then
            ammo_delta = ammo - last_ammo
        end

        last_ammo    = ammo
        last_ammoMax = ammoMax
        last_weapon_id = weapon_id

        if ammo_delta > 0 then
            if AUDIO
                and (AUDIO.reload_session_active or (AUDIO.reload_insert_grace or 0) > 0)
                and AUDIO.play_reload_insert then
                pcall(AUDIO.play_reload_insert, info)
                if ammoMax > 0 and ammo >= ammoMax
                    and AUDIO.should_finish_on_full_insert
                    and AUDIO.should_finish_on_full_insert(info) then
                    reload_finish_pending = FULL_RELOAD_FINISH_DELAY_FRAMES
                    reload_finish_info = info
                end
            end
            if ammo_delta > 1 or ammo >= 5 then
                start_reload_blink()
            else
                pulse_mic_reload()
                start_reload_count(ammo)
            end
        elseif ammo_delta < 0
            and AUDIO
            and not AUDIO.reload_session_active then
            local current_id = tonumber(info.id)
            local MON = _G.DualSenseEnhancedMonitor
            if current_id == 4100 then
                -- No scheduling needed for either case: event_0203 (routed
                -- in wwise_audio_router.lua to AUDIO.play_w870_pump_cycle)
                -- fires directly off the real game audio for both a live
                -- shot's pump cycle and the final chamber action after a
                -- from-empty reload, so timing stays in sync even with a
                -- pump-speed upgrade and isn't gated by reload-exit polling.
            elseif current_id == 4400 then
                -- Live (non-empty) bolt cycle is no longer scheduled here:
                -- it is now triggered directly by the event_0228 candidate
                -- route in wwise_audio_router.lua (wp4400_reload_finish).
                -- Only the empty-shot deferral (played after reload
                -- finishes) remains handled here.
                if ammo == 0 and AUDIO.mark_deferred_postshot then
                    pcall(AUDIO.mark_deferred_postshot, info)
                    if MON and MON.log then MON.log("SR M1903 post-shot bolt deferred until reload") end
                end
            elseif current_id == 4500 then
                -- Reverted: event_0197 was wrongly assumed to fire after a
                -- live shot like wp4100/wp4400's post-shot cues. A clean
                -- single-shot capture (2025-06-27) showed it does NOT fire
                -- outside reload -- it is reload-insert-only. No confirmed
                -- live post-shot ID exists yet, so this keeps the original
                -- fixed-delay timer rather than leaving postshot silent.
                broken_butterfly_postshot_pending = BROKEN_BUTTERFLY_POSTSHOT_DELAY_FRAMES
                if MON and MON.log then MON.log("Broken Butterfly post-shot action scheduled") end
            elseif current_id == 4502 then
                if ammo > 0 then
                    handcannon_postshot_pending = HANDCANNON_POSTSHOT_DELAY_FRAMES
                    if MON and MON.log then MON.log("Handcannon post-shot action scheduled") end
                elseif AUDIO.mark_deferred_postshot then
                    pcall(AUDIO.mark_deferred_postshot, info)
                    if MON and MON.log then MON.log("Handcannon post-shot action deferred until reload") end
                end
            elseif current_id == 6001 then
                -- No scheduling needed: event_0233 (routed in
                -- wwise_audio_router.lua to wp6001_postshot) fires directly
                -- off the real game audio ~0.1-0.3s after every shot,
                -- including the last one, replacing the old fixed
                -- ~1s-delay timer.
            end
            if not reload_feedback_active then
                update_indicator(ammo, ammoMax, melee)
            end
        elseif not reload_feedback_active then
            update_indicator(ammo, ammoMax, melee)
        end
        flush()
    end
end

pcall(function()
    re.on_application_entry("UpdateBehavior", on_update)
end)

_G.AmmoLed = AMMO
