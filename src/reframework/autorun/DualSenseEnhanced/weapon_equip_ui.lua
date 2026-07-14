-- Minimal status/trigger panel for the weapon-equip core: lets the player
-- toggle adaptive triggers, force a config reload, and see at a glance
-- whether the payload link and current weapon poll look healthy.

local CORE = _G.WeaponEquipCore or {}
local FEEDBACK  = _G.DualSenseEnhancedFeedback or {}

local UDP_LINK_TIMEOUT_SECONDS = 3

local function payload_link_is_fresh()
    if not FEEDBACK.last_applied then return false end
    return (os.time() - FEEDBACK.last_applied) < UDP_LINK_TIMEOUT_SECONDS
end

local function reset_payload_to_neutral()
    if not (FEEDBACK.payload_reset and FEEDBACK.out_path) then return end
    local neutral = FEEDBACK.payload_reset()
    local f = io.open(FEEDBACK.out_path, "wb")
    if not f then return end
    f:write(neutral)
    f:close()
end

local function draw_enable_toggle()
    local enabled = CORE.config and CORE.config.enabled or false
    local changed, value = imgui.checkbox("Enable Adaptive Triggers", enabled)
    if not changed then return end

    if CORE.config then CORE.config.enabled = value end
    if not value then reset_payload_to_neutral() end
end

local function draw_reload_button()
    if not imgui.button("Reload Trigger Configs") then return end
    if not FEEDBACK.reload_mapping then return end

    FEEDBACK.reload_mapping()
    if CORE.last_info and FEEDBACK.apply_for_weapon then
        FEEDBACK.apply_for_weapon(CORE.last_info)
    end
end

local function draw_link_status()
    imgui.text("Payload File: " .. (FEEDBACK.out_path and "OK" or "MISSING"))
    imgui.text("Controller UDP Link: " ..
        (payload_link_is_fresh() and "ACTIVE (Heartbeat OK)" or "WAITING..."))
end

local function draw_current_weapon()
    imgui.text("---- Current Weapon ----")
    local info = CORE.last_info
    if info and info.name then
        imgui.text("Weapon: " .. tostring(info.name))
        imgui.text("Ammo: " .. tostring(info.ammo) .. " / " .. tostring(info.ammoMax))
    else
        imgui.text("Searching for Leon...")
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("DualSenseEnhanced Status") then return end

    draw_enable_toggle()
    imgui.separator()
    draw_reload_button()
    imgui.separator()
    draw_link_status()
    imgui.separator()
    draw_current_weapon()

    imgui.tree_pop()
end)
