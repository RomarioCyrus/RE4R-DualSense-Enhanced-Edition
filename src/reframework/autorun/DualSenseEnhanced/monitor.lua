local os = os
local table = table
local tostring = tostring

local MON = {}
MON.max_events = 40
MON.events = {}

function MON.log(name, detail)
    local text = tostring(name or "event")
    if detail ~= nil and tostring(detail) ~= "" then
        text = text .. ": " .. tostring(detail)
    end

    table.insert(MON.events, 1, {
        time = os.date("%H:%M:%S"),
        text = text,
    })

    while #MON.events > MON.max_events do
        table.remove(MON.events)
    end
end

function MON.clear()
    for i = #MON.events, 1, -1 do
        table.remove(MON.events, i)
    end
end

_G.DualSenseEnhancedMonitor = MON
