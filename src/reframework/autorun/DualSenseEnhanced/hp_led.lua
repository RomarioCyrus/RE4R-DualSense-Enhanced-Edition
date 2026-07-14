local sdk   = sdk
local re    = re
local pcall = pcall
local math  = math

_G.DualSenseEnhancedHPLedGeneration = (_G.DualSenseEnhancedHPLedGeneration or 0) + 1
local generation = _G.DualSenseEnhancedHPLedGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedHPLedGeneration == generation
end

-- ================================================================
-- hp_led.lua
-- ================================================================

local LED = {}
LED.enabled = true
LED.interval = 6
LED.last_ratio = -1
LED.threshold = 0.02

-- Thresholds
LED.healthy_threshold = 0.60   -- above: solid green
LED.caution_threshold = 0.30   -- above: yellow-green->orange
LED.danger_threshold  = 0.29   -- below: blink
LED.dim_threshold     = 0.10   -- below: dim red (within danger)

-- Colours
LED.color_healthy    = {0,   220, 0}
LED.color_caution_hi = {180, 255, 0}   -- 59%: yellow-green
LED.color_caution_lo = {255, 80,  0}   -- 30%: orange
LED.color_danger_hi  = {255, 80,  0}   -- 29%: orange
LED.color_danger_lo  = {180, 0,   0}   -- 10%: bright red
LED.color_heal       = {0,   180, 255}

LED.defaults = {
    heal_duration = 240,
    danger_blink_rate = 30,
}
LED.heal_duration = LED.defaults.heal_duration
LED.danger_blink_rate = LED.defaults.danger_blink_rate
LED.vital_status_enabled = true
-- Danger pulse floor: a continuous brightness pulse (never literal black,
-- never the orange substitute native_feedback.lua used to need) between
-- this fraction and full red, matching ammo_led.lua's empty-mag pulse style.
LED.pulse_min_brightness = 0.25
LED.pulse_push_interval = 2   -- frames between LED bus pushes while pulsing (perf)
LED.pulse_steps = 12          -- quantization steps per pulse cycle (perf + still smooth)
LED.danger_pulse_on = false

function LED.reset_defaults()
    LED.heal_duration = LED.defaults.heal_duration
    LED.danger_blink_rate = LED.defaults.danger_blink_rate
    LED.vital_status_enabled = true
end

-- Internal
local tick          = 0
local blink_counter = 0
local danger_pulse_factor = 1
local danger_pulse_push_tick = 0
local prev_hp_abs   = -1
local current_hp_abs = -1
local is_dead       = false
local in_gameplay   = false  -- set by events_led via _G.HPLed.set_gameplay
local heartbeat_active = false
local heartbeat_start_hp_abs = -1
local last_vital_key = nil
local current_vital_key = "Fine"

-- Heal lerp state
local heal_active   = false
local heal_frames   = 0
local heal_from     = {0, 180, 255}  -- start: heal colour
local heal_to       = {0, 220, 0}    -- end: current HP colour (updated at heal start)

function LED.set_gameplay(val)
    in_gameplay = val == true
    blink_counter  = 0
    danger_pulse_push_tick = 0
    danger_pulse_factor = 1
    LED.danger_pulse_on = false
    heal_active    = false
    heal_frames    = 0
    heartbeat_active = false
    heartbeat_start_hp_abs = -1
    last_vital_key = nil
    current_vital_key = "Fine"

    if val then
        is_dead       = false
        LED.last_ratio = -2
        prev_hp_abs    = -1
        current_hp_abs = -1
        last_vital_key = nil
        current_vital_key = "Fine"
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then FEEDBACK.clear_led("hp_heal") end
    else
        -- Exiting gameplay: clear HP sources immediately
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            FEEDBACK.clear_led("hp_gradient")
            FEEDBACK.clear_led("hp_danger")
            FEEDBACK.clear_led("hp_heal")
        end
        LED.last_ratio = -1
        prev_hp_abs    = -1
        current_hp_abs = -1
        current_vital_key = "Fine"
    end
end

function LED.set_dead(val)
    is_dead = val
    if val then
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            FEEDBACK.clear_led("hp_gradient")
            FEEDBACK.clear_led("hp_danger")
            FEEDBACK.clear_led("hp_heal")
        end
        LED.last_ratio = -1
        current_hp_abs = -1
        heartbeat_active = false
        heartbeat_start_hp_abs = -1
        last_vital_key = nil
        current_vital_key = "Dead"
    end
end

local function lerp(a, b, t)
    return math.floor(a + (b - a) * t + 0.5)
end

-- Returns r,g,b for a given ratio
-- Handles dim effect for 10%->1% range within danger blink
local function danger_rgb(r, hp_abs)
    -- Map ratio within danger zone for brightness
    if r <= 0 then return 0, 0, 0 end
    if heartbeat_active then
        local start_hp = math.max(1, heartbeat_start_hp_abs or 1)
        local cur_hp = math.max(1, hp_abs or current_hp_abs or 1)
        local t = math.max(0, math.min(1, cur_hp / start_hp))
        local brightness = math.floor(255 * t + 0.5)
        return brightness, 0, 0
    end
    if r <= LED.dim_threshold then
        -- 10%->1%: bright red -> very dim red
        -- brightness scale: 1.0 at 10%, 0.08 at 1%
        local t = (r - 0.01) / (LED.dim_threshold - 0.01)
        t = math.max(0, math.min(1, t))
        local lo = LED.color_danger_lo
        -- Dim: multiply by brightness
        local brightness = lerp(20, 255, t)  -- 20 at 1%, 255 at 10%
        return math.floor(lo[1] * brightness / 255 + 0.5),
               math.floor(lo[2] * brightness / 255 + 0.5),
               math.floor(lo[3] * brightness / 255 + 0.5)
    else
        -- 29%->10%: orange -> bright red
        local t = (r - LED.dim_threshold) / (LED.danger_threshold - LED.dim_threshold)
        t = math.max(0, math.min(1, t))
        local hi = LED.color_danger_hi
        local lo = LED.color_danger_lo
        return lerp(lo[1], hi[1], t),
               lerp(lo[2], hi[2], t),
               lerp(lo[3], hi[3], t)
    end
end

local function ratio_to_rgb(r)
    if r <= 0 then return 0, 0, 0 end
    if r >= LED.healthy_threshold then
        local c = LED.color_healthy
        return c[1], c[2], c[3]
    elseif r >= LED.caution_threshold then
        local t = (r - LED.caution_threshold) / (LED.healthy_threshold - LED.caution_threshold)
        local hi = LED.color_caution_hi
        local lo = LED.color_caution_lo
        return lerp(lo[1], hi[1], t),
               lerp(lo[2], hi[2], t),
               lerp(lo[3], hi[3], t)
    else
        return danger_rgb(r, current_hp_abs)
    end
end

local function vital_danger_rgb(hp_abs, pulse_factor)
    local start_hp = math.max(1, heartbeat_start_hp_abs or hp_abs or current_hp_abs or 1)
    local cur_hp = math.max(1, hp_abs or current_hp_abs or 1)
    local t = math.max(0, math.min(1, cur_hp / start_hp))
    local brightness = math.floor(255 * t * (pulse_factor or 1) + 0.5)
    return brightness, 0, 0
end

local function vital_ratio_to_rgb(r, vital_key)
    if r <= 0 then return 0, 0, 0 end
    if vital_key == "Danger" then
        return vital_danger_rgb(current_hp_abs)
    elseif vital_key == "Caution" or vital_key == "Poison" then
        local t = math.max(0, math.min(1, r))
        local hi = LED.color_caution_hi
        local lo = LED.color_caution_lo
        return lerp(lo[1], hi[1], t),
               lerp(lo[2], hi[2], t),
               lerp(lo[3], hi[3], t)
    elseif r <= LED.healthy_threshold then
        local t = math.max(0, math.min(1, r / math.max(0.01, LED.healthy_threshold)))
        local hi = LED.color_caution_hi
        local lo = LED.color_caution_lo
        return lerp(lo[1], hi[1], t),
               lerp(lo[2], hi[2], t),
               lerp(lo[3], hi[3], t)
    else
        local c = LED.color_healthy
        return c[1], c[2], c[3]
    end
end

local function flush()
    local FEEDBACK  = _G.DualSenseEnhancedFeedback
    local CORE = _G.WeaponEquipCore
    if FEEDBACK and FEEDBACK.apply_for_weapon and CORE and CORE.last_info then
        pcall(FEEDBACK.apply_for_weapon, CORE.last_info)
    end
end

local function push_hp_led()
    local FEEDBACK = _G.DualSenseEnhancedFeedback
    if not FEEDBACK then return end
    local ratio = LED.last_ratio
    if ratio < 0 or is_dead or not in_gameplay then
        FEEDBACK.clear_led("hp_gradient")
        FEEDBACK.clear_led("hp_danger")
        return
    end
    if current_vital_key == "Danger" then
        FEEDBACK.clear_led("hp_gradient")
        -- Continuous brightness pulse between LED.pulse_min_brightness and
        -- full red -- never a literal black frame, so native_feedback.lua
        -- no longer needs an orange black-rest substitute for this source.
        local r, g, b = vital_danger_rgb(current_hp_abs, danger_pulse_factor)
        FEEDBACK.set_led("hp_danger", r, g, b, 1)
    else
        FEEDBACK.clear_led("hp_danger")
        local r, g, b = vital_ratio_to_rgb(ratio, current_vital_key)
        FEEDBACK.set_led("hp_gradient", r, g, b, 1)
    end
end

function LED.trigger_low_hp_heartbeat(source)
    if not LED.enabled or not LED.vital_status_enabled then return end
    if not in_gameplay or is_dead then return end
    if LED.last_ratio <= 0 then return end

    local hp_abs = current_hp_abs
    if hp_abs == nil or hp_abs <= 0 then hp_abs = prev_hp_abs end
    if hp_abs == nil or hp_abs <= 0 then return end

    heartbeat_active = true
    heartbeat_start_hp_abs = math.max(1, hp_abs)
    blink_counter = 0
    danger_pulse_factor = 1
    LED.danger_pulse_on = true
    push_hp_led()
    flush()

    local MON = _G.DualSenseEnhancedMonitor
    if MON and MON.log then
        MON.log("low hp heartbeat", string.format("%s %.0f%% hp=%d", tostring(source or "vital"), LED.last_ratio * 100, heartbeat_start_hp_abs))
    end
end

local function get_hp()
    local ok, cur, max, dead = pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then return nil, nil, nil end
        local player = cm:call("getPlayerContextRef")
        if not player then player = cm:call("get_ManualPlayer") end
        if not player then return nil, nil, nil end

        -- Try death flag
        local dead_flag = false
        pcall(function()
            dead_flag = player:call("get_IsDead")
                     or player:call("get_IsDeadState")
                     or false
        end)
        -- Fallback: check via HitPoint
        local hp = player:call("get_HitPoint")
        if not hp then return nil, nil, dead_flag end
        local cur_hp = hp:call("get_CurrentHitPoint")
        local max_hp = hp:call("get_DefaultHitPoint")
        -- Secondary death check: HP <= 0 or get_IsDown
        if not dead_flag then
            pcall(function()
                dead_flag = hp:call("get_IsDeadState") or false
            end)
        end
        return cur_hp, max_hp, dead_flag
    end)
    if ok then return cur, max, dead end
    return nil, nil, false
end

local function vital_to_key(vital)
    local s = tostring(vital or "")
    local lower = string.lower(s)
    if lower:find("danger", 1, true) then return "Danger", 2 end
    if lower:find("caution", 1, true) then return "Caution", 1 end
    if lower:find("poison", 1, true) then return "Poison", 3 end
    if lower:find("dead", 1, true) then return "Dead", 4 end
    if lower:find("fine", 1, true) then return "Fine", 0 end

    local n = tonumber(vital)
    if n == 0 then return "Fine", n end
    if n == 1 then return "Caution", n end
    if n == 2 then return "Danger", n end
    if n == 3 then return "Poison", n end
    if n == 4 then return "Dead", n end
    return s ~= "" and s or "?", n
end

local function get_hit_point_vital()
    local ok, vital = pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then return nil end
        local player = cm:call("getPlayerContextRef")
        if not player then player = cm:call("get_ManualPlayer") end
        if not player then return nil end

        local head = nil
        pcall(function() head = player:call("get_HeadUpdater") end)
        if head then
            local ctx = nil
            pcall(function() ctx = head:call("get_Context") end)
            if ctx then
                local v = ctx:call("getHitPointVital")
                if v ~= nil then return v end
            end
        end

        return player:call("getHitPointVital")
    end)
    if ok then return vital end
    return nil
end

local function on_update()
    if not is_current_generation() then return end
    if not LED.enabled then return end
    tick = tick + 1

    -- Don't show HP LED while not in gameplay (menu, loading)
    if not in_gameplay then return end

    -- Heal lerp tick (runs every frame)
    if heal_active then
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then
            local duration = math.max(1, LED.heal_duration)
            local t = 1.0 - (heal_frames / duration)  -- 0->1 over duration
            t = math.max(0, math.min(1, t))
            local r = math.floor(heal_from[1] + (heal_to[1] - heal_from[1]) * t + 0.5)
            local g = math.floor(heal_from[2] + (heal_to[2] - heal_from[2]) * t + 0.5)
            local b = math.floor(heal_from[3] + (heal_to[3] - heal_from[3]) * t + 0.5)
            FEEDBACK.set_led("hp_heal", r, g, b, 50)
            flush()
        end
        heal_frames = heal_frames - 1
        if heal_frames <= 0 then
            heal_active = false
            local feedback = _G.DualSenseEnhancedFeedback
            if feedback then feedback.clear_led("hp_heal") end
            -- Force immediate HP colour refresh
            push_hp_led()
            flush()
        end
        return  -- skip normal HP poll while heal lerp is running
    end

    -- Danger pulse tick: continuous sine brightness oscillation. Phase
    -- advances every frame for correct pacing, but the actual LED bus
    -- push/flush() is throttled to once every LED.pulse_push_interval
    -- frames and brightness is quantized to LED.pulse_steps discrete
    -- levels -- pushing a near-continuous value every single frame
    -- measurably increased native lightbar HID write/enforcement traffic
    -- (reported as stutter), because almost every frame produced a
    -- distinct rounded colour, unlike the old 2-state hard blink.
    if LED.last_ratio > 0 and current_vital_key == "Danger" and not is_dead then
        local period = math.max(2, LED.danger_blink_rate * 2)
        blink_counter = (blink_counter + 1) % period
        local phase = blink_counter / period
        local raw_factor = LED.pulse_min_brightness
            + (1 - LED.pulse_min_brightness)
            * (0.5 + 0.5 * math.sin(2 * math.pi * phase))
        local steps = math.max(2, LED.pulse_steps)
        danger_pulse_factor = math.floor(raw_factor * steps + 0.5) / steps
        -- Exposed so dualib_trigger_ipc.lua's Mic LED sync can read this
        -- frame's phase directly instead of inspecting r/g/b magnitude
        -- (no longer a reliable signal now that this never hits literal
        -- black).
        LED.danger_pulse_on = danger_pulse_factor > 0.5

        danger_pulse_push_tick = danger_pulse_push_tick + 1
        if danger_pulse_push_tick >= math.max(1, LED.pulse_push_interval) then
            danger_pulse_push_tick = 0
            push_hp_led()
            flush()
        end
    end

    if tick % LED.interval ~= 0 then return end

    local cur, max, dead = get_hp()

    -- Death check
    if dead then
        if not is_dead then
            is_dead = true
            LED.set_dead(true)
            flush()
        end
        return
    else
        if is_dead then
            is_dead = false
        end
    end

    -- Not in game
    if cur == nil then
        if LED.last_ratio ~= -1 then
            LED.last_ratio = -1
            prev_hp_abs    = -1
            current_hp_abs = -1
            blink_counter  = 0
            danger_pulse_factor = 1
            LED.danger_pulse_on = false
            heartbeat_active = false
            heartbeat_start_hp_abs = -1
            local FEEDBACK = _G.DualSenseEnhancedFeedback
            if FEEDBACK then
                FEEDBACK.clear_led("hp_gradient")
                FEEDBACK.clear_led("hp_danger")
                FEEDBACK.clear_led("hp_heal")
            end
            flush()
        end
        return
    end

    max = (max and max > 0) and max or 1
    cur = math.max(0, cur)
    current_hp_abs = cur
    local new_ratio = math.min(1, cur / max)

    local vital_key, vital_id = vital_to_key(get_hit_point_vital())
    local vital_changed = vital_key ~= last_vital_key
    local was_danger = heartbeat_active
    current_vital_key = vital_key
    if vital_changed then
        last_vital_key = vital_key
        local MON = _G.DualSenseEnhancedMonitor
        if MON and MON.log then
            MON.log("hp vital", string.format("%s(%s)", tostring(vital_key), tostring(vital_id or "?")))
        end
    end

    if LED.vital_status_enabled and vital_key == "Danger" and new_ratio > 0 and not heartbeat_active then
        LED.last_ratio = new_ratio
        LED.trigger_low_hp_heartbeat("vital")
    elseif heartbeat_active and vital_key ~= "Danger" then
        heartbeat_active = false
        heartbeat_start_hp_abs = -1
    end

    -- Heal detection: start lerp transition
    if prev_hp_abs >= 0 and cur > prev_hp_abs then
        local MON = _G.DualSenseEnhancedMonitor
        if MON and MON.log then MON.log("heal", string.format("%.0f -> %.0f", prev_hp_abs, cur)) end
        local AUDIO = _G.DualSenseEnhancedAudio
        if AUDIO and AUDIO.play_heal then pcall(AUDIO.play_heal) end
        -- Capture target HP colour at moment of healing
        local tr, tg, tb = vital_ratio_to_rgb(new_ratio, vital_key)
        heal_from   = {LED.color_heal[1], LED.color_heal[2], LED.color_heal[3]}
        heal_to     = {tr, tg, tb}
        heal_active = true
        heal_frames = math.max(1, LED.heal_duration)
        -- Remove old flash source, lerp loop will drive hp_heal
        local FEEDBACK = _G.DualSenseEnhancedFeedback
        if FEEDBACK then FEEDBACK.clear_led("hp_heal") end
    end
    prev_hp_abs = cur

    local is_danger  = vital_key == "Danger"
    LED.is_danger    = is_danger
    local changed    = (LED.last_ratio == -2)
        or math.abs(new_ratio - (LED.last_ratio < 0 and 0 or LED.last_ratio)) >= LED.threshold
        or LED.last_ratio < 0
        or vital_changed

    if was_danger and not is_danger then
        LED.last_ratio = new_ratio
        blink_counter  = 0
        danger_pulse_factor = 1
        LED.danger_pulse_on = false
        heartbeat_active = false
        heartbeat_start_hp_abs = -1
        push_hp_led()
        flush()
    elseif not is_danger and changed then
        LED.last_ratio = new_ratio
        push_hp_led()
        flush()
    else
        if LED.last_ratio == -2 then LED.last_ratio = new_ratio end
        if is_danger then LED.last_ratio = new_ratio end
    end
end

pcall(function()
    re.on_application_entry("UpdateBehavior", on_update)
end)

_G.HPLed = LED
