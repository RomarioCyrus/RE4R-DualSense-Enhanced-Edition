local re = re
local os = os
local pcall = pcall

_G.DualSenseEnhancedRadioDialogueGeneration = (_G.DualSenseEnhancedRadioDialogueGeneration or 0) + 1
local generation = _G.DualSenseEnhancedRadioDialogueGeneration

local function is_current_generation()
    return _G.DualSenseEnhancedRadioDialogueGeneration == generation
end

-- ================================================================
-- radio_dialogue.lua
-- PS5-style radio dialogue routing (see docs/RADIO_DIALOGUE_TASK.md).
--
-- Phase 1 (Speaker Duplicate MVP): play a matching WAV on the DualSense
-- speaker alongside the unchanged main-mix dialogue. No game files or
-- Wwise events are muted in this mode.
--
-- Phase 3 (Runtime Mute) and Phase 4 (Repacked Silence) are not
-- implemented yet; the "mode" values for them are reserved.
-- ================================================================

local RADIO = {}
RADIO.enabled = false
RADIO.mode = "speaker_duplicate" -- "off" | "speaker_duplicate" | "repacked_silence" | "runtime_mute"
RADIO.speaker_volume = 1.0
RADIO.latency_offset_ms = 0
RADIO.haptics_enabled = false
RADIO.language = "auto"
RADIO.runtime_mute_experimental = false
RADIO.fallback_to_duplicate = true
RADIO.last_status = "idle"
RADIO.last_error = nil
RADIO.last_event = nil

local delayed_lines = {}

local function schedule_line(event_name, delay_frames)
    delayed_lines[#delayed_lines + 1] = {
        event = event_name,
        frames = math.max(0, delay_frames or 0),
    }
end

local function tick_delayed_lines()
    if not is_current_generation() then return end
    for index = #delayed_lines, 1, -1 do
        local pending = delayed_lines[index]
        pending.frames = pending.frames - 1
        if pending.frames <= 0 then
            local AUDIO = _G.DualSenseEnhancedAudio
            if AUDIO and AUDIO.emit then
                pcall(AUDIO.emit, pending.event, RADIO.speaker_volume)
            end
            table.remove(delayed_lines, index)
        end
    end
end

pcall(function()
    re.on_application_entry("UpdateBehavior", tick_delayed_lines)
end)

-- Plays a named radio-dialogue audio event (already mapped in
-- SoundMap.cs) through the controller speaker, honoring the configured
-- volume and latency offset. Does not touch the main game mix; that is
-- the defining trait of "speaker_duplicate" mode.
function RADIO.play_dialogue(event_name)
    if not RADIO.enabled or RADIO.mode == "off" then
        RADIO.last_status = "disabled"
        return false
    end
    if not event_name then return false end

    local offset_ms = tonumber(RADIO.latency_offset_ms) or 0
    local delay_frames = math.floor((offset_ms / 1000.0) * 60.0 + 0.5)

    if delay_frames > 0 then
        schedule_line(event_name, delay_frames)
    else
        local AUDIO = _G.DualSenseEnhancedAudio
        if not AUDIO or not AUDIO.emit then
            RADIO.last_status = "audio module missing"
            return false
        end
        local ok, err = pcall(AUDIO.emit, event_name, RADIO.speaker_volume)
        if not ok then
            RADIO.last_error = tostring(err)
            RADIO.last_status = "emit failed"
            return false
        end
    end

    RADIO.last_event = event_name
    RADIO.last_error = nil
    RADIO.last_status = "emitted " .. tostring(event_name)
    return true
end

-- Manual test button target: confirms the speaker path end-to-end before
-- any real radio-event hook is wired. Reuses an existing confirmed sound
-- as a placeholder; replace with an extracted radio-dialogue WAV once
-- Phase 2 mapping exists.
function RADIO.play_test()
    return RADIO.play_dialogue("radio_test")
end

-- Registered on _G.DualSenseEnhancedAudio (not RADIO) so wwise_audio_router.lua's generic
-- `handler` lookup -- which always reads from _G.DualSenseEnhancedAudio -- can call it
-- directly, the same way W-870's pump-cycle handler works.
pcall(function()
    local AUDIO = _G.DualSenseEnhancedAudio
    if AUDIO then
        function AUDIO.play_radio_ring()
            return RADIO.play_dialogue("radio_ring")
        end
    end
end)

_G.DualSenseEnhancedRadio = RADIO
