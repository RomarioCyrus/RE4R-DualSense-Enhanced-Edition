local re    = re
local sdk   = sdk
local pcall = pcall

-- ================================================================
-- debug_led.lua - on-screen diagnostics via imgui
-- ================================================================

local state = {
    feedback_loaded = false,
    core_loaded   = false,
    hp_loaded     = false,
    ammo_loaded   = false,
    events_loaded = false,
    out_path      = "?",
    hp_cur        = "?",
    hp_max        = "?",
    weapon_name   = "?",
    weapon_type   = "?",
    ammo          = "?",
    ammo_max      = "?",
    led_sources   = {},
    indicator     = "?",
}

local tick = 0

local function on_update()
    tick = tick + 1
    if tick % 60 ~= 0 then return end

    local FEEDBACK  = _G.DualSenseEnhancedFeedback
    local CORE = _G.WeaponEquipCore

    state.feedback_loaded = FEEDBACK ~= nil
    state.core_loaded   = CORE   ~= nil
    state.hp_loaded     = _G.HPLed     ~= nil
    state.ammo_loaded   = _G.AmmoLed   ~= nil
    state.events_loaded = _G.EventsLed ~= nil
    state.out_path      = FEEDBACK and tostring(FEEDBACK.out_path) or "nil"

    if CORE and CORE.last_info then
        local info = CORE.last_info
        state.weapon_name = tostring(info.name)
        state.weapon_type = tostring(info.type)
        state.ammo        = tostring(info.ammo)
        state.ammo_max    = tostring(info.ammoMax)
    end

    if FEEDBACK and FEEDBACK.led_sources then
        state.led_sources = {}
        for name, src in pairs(FEEDBACK.led_sources) do
            table.insert(state.led_sources, string.format(
                "%s: rgb(%d,%d,%d) pri=%d fr=%s",
                name, src.r, src.g, src.b, src.priority,
                tostring(src.frames)
            ))
        end
    end

    state.indicator = FEEDBACK and tostring(FEEDBACK.indicator_source ~= nil) or "?"

    pcall(function()
        local cm = sdk.get_managed_singleton("chainsaw.CharacterManager")
        if not cm then state.hp_cur = "no CM"; return end
        local player = cm:call("getPlayerContextRef")
        if not player then player = cm:call("get_ManualPlayer") end
        if not player then state.hp_cur = "no player"; return end
        local hp = player:call("get_HitPoint")
        if not hp then state.hp_cur = "no HP obj"; return end
        state.hp_cur = tostring(hp:call("get_CurrentHitPoint"))
        state.hp_max = tostring(hp:call("get_DefaultHitPoint"))
    end)
end

pcall(function()
    re.on_application_entry("UpdateBehavior", on_update)
end)

re.on_draw_ui(function()
    if imgui.tree_node("LED Debug") then
        imgui.text("=== Modules ===")
        imgui.text("DualSenseEnhancedFeedback: "   .. tostring(state.feedback_loaded))
        imgui.text("WeaponCore: "  .. tostring(state.core_loaded))
        imgui.text("HPLed: "       .. tostring(state.hp_loaded))
        imgui.text("AmmoLed: "     .. tostring(state.ammo_loaded))
        imgui.text("EventsLed: "   .. tostring(state.events_loaded))
        imgui.separator()
        imgui.text("=== Feedback ===")
        imgui.text("out_path: "    .. state.out_path)
        imgui.text("indicator: "   .. state.indicator)
        imgui.separator()
        imgui.text("=== Weapon ===")
        imgui.text("name: "  .. state.weapon_name)
        imgui.text("type: "  .. state.weapon_type)
        imgui.text("ammo: "  .. state.ammo .. " / " .. state.ammo_max)
        imgui.separator()
        imgui.text("=== HP ===")
        imgui.text("cur: " .. state.hp_cur .. " / " .. state.hp_max)
        imgui.separator()
        imgui.text("=== LED Bus ===")
        if #state.led_sources == 0 then
            imgui.text("(empty)")
        else
            for _, s in ipairs(state.led_sources) do
                imgui.text(s)
            end
        end
        imgui.tree_pop()
    end
end)

print("[DBG] debug_led.lua loaded")
