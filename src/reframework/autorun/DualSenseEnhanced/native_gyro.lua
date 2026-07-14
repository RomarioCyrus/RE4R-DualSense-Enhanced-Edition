-- Native gyro-to-mouse configuration. Input is read by the existing delayed
-- duaLib transport; this module never opens a controller or writes HID output.

local io = io
local string = string
local math = math

_G.NativeGyro = _G.NativeGyro or {}
local GYRO = _G.NativeGyro

GYRO.enabled = GYRO.enabled == true
GYRO.yaw_sensitivity = tonumber(GYRO.yaw_sensitivity) or 500
GYRO.pitch_sensitivity = tonumber(GYRO.pitch_sensitivity) or 450
GYRO.deadzone = tonumber(GYRO.deadzone) or 0.02
GYRO.aim_threshold = tonumber(GYRO.aim_threshold) or 32
GYRO.calibration_ms = tonumber(GYRO.calibration_ms) or 1000
GYRO.invert_pitch = GYRO.invert_pitch == true
GYRO.activation_mode = GYRO.activation_mode or "l2"
GYRO.config_file = "DualSenseEnhanced/native_gyro.json"
GYRO.last_serialized = GYRO.last_serialized or nil
GYRO.last_error = GYRO.last_error or "none"

-- Named presets matching gyro_trigger_presets_codex_task.md. Selecting one
-- overwrites yaw/pitch/deadzone/calibration; the L2 threshold is left to the
-- activation mode below. Manual slider edits move the preset to "custom".
GYRO.PRESETS = {
    precision = { yaw_sensitivity = 500, pitch_sensitivity = 450, deadzone = 0.020, calibration_ms = 1000 },
    ps5_feel  = { yaw_sensitivity = 650, pitch_sensitivity = 600, deadzone = 0.018, calibration_ms = 1000 },
    fast_flicks = { yaw_sensitivity = 850, pitch_sensitivity = 800, deadzone = 0.015, calibration_ms = 1000 },
    stable    = { yaw_sensitivity = 350, pitch_sensitivity = 300, deadzone = 0.035, calibration_ms = 1000 },
}
GYRO.PRESET_ORDER = { "precision", "ps5_feel", "fast_flicks", "stable", "custom" }
GYRO.PRESET_LABELS = {
    precision = "Precision", ps5_feel = "PS5 Feel",
    fast_flicks = "Fast Flicks", stable = "Stable", custom = "Custom",
}
GYRO.preset = GYRO.preset or "precision"

function GYRO.apply_preset(name)
    local preset = GYRO.PRESETS[name]
    if not preset then return end
    GYRO.preset = name
    GYRO.yaw_sensitivity = preset.yaw_sensitivity
    GYRO.pitch_sensitivity = preset.pitch_sensitivity
    GYRO.deadzone = preset.deadzone
    GYRO.calibration_ms = preset.calibration_ms
end

function GYRO.mark_custom()
    GYRO.preset = "custom"
end

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function GYRO.normalize()
    GYRO.yaw_sensitivity = clamp(GYRO.yaw_sensitivity, 100, 2000)
    GYRO.pitch_sensitivity = clamp(GYRO.pitch_sensitivity, 100, 2000)
    GYRO.deadzone = clamp(GYRO.deadzone, 0.005, 0.20)
    GYRO.aim_threshold = math.floor(clamp(GYRO.aim_threshold, 1, 128) + 0.5)
    GYRO.calibration_ms = math.floor(clamp(GYRO.calibration_ms, 500, 5000) + 0.5)
end

function GYRO.write_config()
    GYRO.normalize()
    -- "Always On" activation is implemented as a zero L2 gate so the
    -- existing watcher/mapper code path does not need an activation enum.
    local effective_threshold = GYRO.activation_mode == "always" and 0 or GYRO.aim_threshold
    local text = string.format(
        '{"enabled":%s,"yawSensitivity":%.4f,"pitchSensitivity":%.4f,' ..
        '"deadzone":%.4f,"aimThreshold":%d,"calibrationMs":%d,"invertPitch":%s}\n',
        GYRO.enabled and "true" or "false",
        GYRO.yaw_sensitivity,
        GYRO.pitch_sensitivity,
        GYRO.deadzone,
        effective_threshold,
        GYRO.calibration_ms,
        GYRO.invert_pitch and "true" or "false")
    if text == GYRO.last_serialized then return true end

    local file, err = io.open(GYRO.config_file, "wb")
    if not file then
        GYRO.last_error = "Cannot write " .. GYRO.config_file .. ": " .. tostring(err)
        return false
    end
    file:write(text)
    file:close()
    GYRO.last_serialized = text
    GYRO.last_error = "none"
    return true
end

function GYRO.apply_settings(values)
    if type(values) ~= "table" then return end
    GYRO.enabled = values.enabled == true
    GYRO.yaw_sensitivity = values.yaw_sensitivity or GYRO.yaw_sensitivity
    GYRO.pitch_sensitivity = values.pitch_sensitivity or GYRO.pitch_sensitivity
    GYRO.deadzone = values.deadzone or GYRO.deadzone
    GYRO.aim_threshold = values.aim_threshold or GYRO.aim_threshold
    GYRO.calibration_ms = values.calibration_ms or GYRO.calibration_ms
    GYRO.invert_pitch = values.invert_pitch == true
    GYRO.activation_mode = values.activation_mode or GYRO.activation_mode
    GYRO.preset = values.preset or GYRO.preset
    GYRO.write_config()
end

GYRO.write_config()
