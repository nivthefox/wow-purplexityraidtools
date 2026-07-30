local PRT = PurplexityRaidTools
local NotesSerializer = {}
PRT.NotesSerializer = NotesSerializer

local function formatTTS(value)
    if value == true then
        return "true"
    end
    if value == false then
        return "false"
    end
    return value
end

local function isDefaultDisplayType(displayType, spellID)
    if displayType == "Icon" and spellID ~= nil then
        return true
    end
    if displayType == "Text" and spellID == nil then
        return true
    end
    return false
end

local function serializeMetadata(note)
    local parts = { "EncounterID: " .. tostring(note.encounterID) }
    if note.name ~= nil then
        parts[#parts + 1] = "Name: " .. note.name
    end
    if note.difficulty ~= nil then
        parts[#parts + 1] = "Difficulty: " .. note.difficulty
    end
    return table.concat(parts, "; ")
end

local function serializeReminder(reminder)
    local parts = {}

    parts[#parts + 1] = "time:" .. tostring(reminder.time)
    parts[#parts + 1] = "tag:" .. reminder.tag

    if reminder.phase ~= nil and reminder.phase ~= 1 then
        parts[#parts + 1] = "ph:" .. tostring(reminder.phase)
    end

    if reminder.text ~= nil then
        parts[#parts + 1] = "text:" .. reminder.text
    end

    if reminder.spellID ~= nil then
        parts[#parts + 1] = "spellid:" .. tostring(reminder.spellID)
    end

    if reminder.duration ~= nil and reminder.duration ~= 5 then
        parts[#parts + 1] = "dur:" .. tostring(reminder.duration)
    end

    if reminder.displayType ~= nil and not isDefaultDisplayType(reminder.displayType, reminder.spellID) then
        parts[#parts + 1] = "displaytype:" .. reminder.displayType
    end

    local ttsValue = formatTTS(reminder.tts)
    if ttsValue ~= nil then
        parts[#parts + 1] = "tts:" .. ttsValue
    end

    if reminder.ttsTimer ~= nil and reminder.ttsTimer ~= reminder.duration then
        parts[#parts + 1] = "ttstimer:" .. tostring(reminder.ttsTimer)
    end

    if reminder.countdown ~= nil then
        parts[#parts + 1] = "countdown:" .. tostring(reminder.countdown)
    end

    if reminder.sound ~= nil then
        parts[#parts + 1] = "sound:" .. reminder.sound
    end

    if reminder.bossSpell ~= nil then
        parts[#parts + 1] = "bossspell:" .. tostring(reminder.bossSpell)
    end

    if reminder.colors ~= nil then
        parts[#parts + 1] = "colors:" .. reminder.colors
    end

    return table.concat(parts, "; ")
end

local function hasContent(note)
    if note.encounterID ~= nil then
        return true
    end
    if note.lines and #note.lines > 0 then
        return true
    end
    return false
end

local function chronologicalKey(reminder)
    return (reminder.phase or 1) * 1000000 + (reminder.time or 0)
end

function NotesSerializer:Serialize(note)
    if not note then
        return ""
    end
    if not hasContent(note) then
        return ""
    end

    local output = {}

    if note.encounterID ~= nil then
        output[#output + 1] = serializeMetadata(note)
    end

    if not note.lines then
        return table.concat(output, "\n")
    end

    local sortedReminders = {}
    local freeformAfter = {}
    local leadingFreeform = {}
    local lastReminder = nil

    for _, entry in ipairs(note.lines) do
        if entry.type == "freeform" then
            if lastReminder then
                if not freeformAfter[lastReminder] then
                    freeformAfter[lastReminder] = {}
                end
                freeformAfter[lastReminder][#freeformAfter[lastReminder] + 1] = entry.text
            else
                leadingFreeform[#leadingFreeform + 1] = entry.text
            end
        elseif entry.type == "reminder" then
            sortedReminders[#sortedReminders + 1] = entry.reminder
            lastReminder = entry.reminder
        end
    end

    table.sort(sortedReminders, function(a, b)
        return chronologicalKey(a) < chronologicalKey(b)
    end)

    for _, text in ipairs(leadingFreeform) do
        output[#output + 1] = text
    end

    for _, reminder in ipairs(sortedReminders) do
        output[#output + 1] = serializeReminder(reminder)
        if freeformAfter[reminder] then
            for _, text in ipairs(freeformAfter[reminder]) do
                output[#output + 1] = text
            end
        end
    end

    return table.concat(output, "\n")
end
