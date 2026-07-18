-- NotesParser: parses one encounter's raw note text into the frozen data
-- contract (rev 2). See the FROZEN DATA CONTRACT block at the top of Notes.lua.
local PRT = PurplexityRaidTools
local NotesParser = {}
PRT.NotesParser = NotesParser

local MULTI_ENCOUNTER_ERROR =
    "A note may only contain one encounter. Use a separate note per encounter."

--------------------------------------------------------------------------------
-- Line splitting
--------------------------------------------------------------------------------

local function splitLines(text)
    local lines = {}
    local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local pos = 1
    local len = #normalized
    while pos <= len + 1 do
        local nl = normalized:find("\n", pos, true)
        if nl then
            lines[#lines + 1] = normalized:sub(pos, nl - 1)
            pos = nl + 1
        else
            lines[#lines + 1] = normalized:sub(pos)
            break
        end
    end
    return lines
end

local function splitOnSemicolons(line)
    local parts = {}
    local pos = 1
    local len = #line
    while pos <= len + 1 do
        local sc = line:find(";", pos, true)
        if sc then
            parts[#parts + 1] = line:sub(pos, sc - 1)
            pos = sc + 1
        else
            parts[#parts + 1] = line:sub(pos)
            break
        end
    end
    return parts
end

local function parseFields(line)
    local fields = {}
    for _, pair in ipairs(splitOnSemicolons(line)) do
        local colon = pair:find(":", 1, true)
        if colon then
            local key = pair:sub(1, colon - 1):match("^%s*(.-)%s*$")
            local value = pair:sub(colon + 1):match("^%s*(.-)%s*$")
            if key ~= "" then
                fields[key:lower()] = value
            end
        end
    end
    return fields
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function toNumber(value)
    if value == nil then return nil end
    return tonumber(value)
end

local function isTimedLine(line)
    return line:find("time:", 1, true)
        and line:find("tag:", 1, true)
        and (line:find("text:", 1, true) or line:find("spellid:", 1, true))
end

--------------------------------------------------------------------------------
-- Reminder construction
--------------------------------------------------------------------------------

local function buildReminder(fields)
    local time = toNumber(fields["time"])
    local tag = fields["tag"]
    local text = fields["text"]
    local spellID = toNumber(fields["spellid"])

    if time == nil or tag == nil or tag == "" then
        return nil
    end
    if (text == nil or text == "") and spellID == nil then
        return nil
    end

    local reminder = {}
    reminder.time = time
    reminder.tag = tag
    if text ~= nil and text ~= "" then
        reminder.text = text
    end
    reminder.spellID = spellID

    local phase = toNumber(fields["ph"]) or 1
    reminder.phase = phase
    reminder.phaseKey = tostring(phase)

    local duration = toNumber(fields["dur"]) or 5
    if duration > time then
        duration = time
    end
    reminder.duration = duration

    local displayType = fields["displaytype"]
    if displayType == nil or displayType == "" then
        if spellID ~= nil then
            displayType = "Icon"
        else
            displayType = "Text"
        end
    end
    reminder.displayType = displayType

    local ttsRaw = fields["tts"]
    if ttsRaw ~= nil then
        local lowered = ttsRaw:lower()
        if lowered == "true" then
            reminder.tts = true
        elseif lowered == "false" then
            reminder.tts = false
        else
            reminder.tts = ttsRaw
        end
    end

    local ttsTimer = toNumber(fields["ttstimer"])
    if ttsTimer == nil then
        ttsTimer = duration
    end
    if ttsTimer > time then
        ttsTimer = time
    end
    reminder.ttsTimer = ttsTimer

    reminder.countdown = toNumber(fields["countdown"])
    reminder.sound = fields["sound"]
    reminder.bossSpell = toNumber(fields["bossspell"])

    local colors = fields["colors"]
    if colors ~= nil and colors ~= "" then
        reminder.colors = colors
    end

    return reminder
end

--------------------------------------------------------------------------------
-- Parse
--------------------------------------------------------------------------------

local function newNote()
    return {
        encounterID = nil,
        name = nil,
        difficulty = nil,
        reminders = {},
        lines = {},
    }
end

local function addFreeform(note, text)
    note.lines[#note.lines + 1] = { type = "freeform", text = text }
end

local function addReminder(note, reminder)
    local bucket = note.reminders[reminder.phaseKey]
    if not bucket then
        bucket = {}
        note.reminders[reminder.phaseKey] = bucket
    end
    bucket[#bucket + 1] = reminder
    note.lines[#note.lines + 1] = { type = "reminder", reminder = reminder }
end

local function applyMetadata(note, line)
    local fields = parseFields(line)
    note.encounterID = tonumber(fields["encounterid"]) or fields["encounterid"]
    local name = fields["name"]
    local difficulty = fields["difficulty"]
    if name ~= "" then
        note.name = name
    end
    if difficulty ~= "" then
        note.difficulty = difficulty
    end
end

function NotesParser:Parse(noteText)
    local note = newNote()
    if type(noteText) ~= "string" or noteText == "" then
        return note, nil
    end

    local lines = splitLines(noteText)

    local metadataCount = 0
    for _, rawLine in ipairs(lines) do
        if rawLine:find("EncounterID:", 1, true) then
            metadataCount = metadataCount + 1
        end
    end
    if metadataCount > 1 then
        return nil, MULTI_ENCOUNTER_ERROR
    end

    local seenMetadata = false
    for _, rawLine in ipairs(lines) do
        local line = rawLine:match("^%s*(.-)%s*$")

        if line == "" then
        elseif line:find("EncounterID:", 1, true) then
            applyMetadata(note, line)
            seenMetadata = true
        elseif not seenMetadata then
            addFreeform(note, line)
        else
            local reminder = nil
            if isTimedLine(line) then
                reminder = buildReminder(parseFields(line))
            end
            if reminder then
                addReminder(note, reminder)
            else
                addFreeform(note, line)
            end
        end
    end

    for _, bucket in pairs(note.reminders) do
        table.sort(bucket, function(a, b)
            return a.time < b.time
        end)
    end

    return note, nil
end
