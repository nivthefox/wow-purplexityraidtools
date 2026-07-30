dofile("Modules/Notes/Notes.lua")
dofile("Modules/Notes/NotesParser.lua")
dofile("Modules/Notes/NotesSerializer.lua")

local PRT = PurplexityRaidTools
local Parser = PRT.NotesParser
local Serializer = PRT.NotesSerializer

local tests = {}

local function makeReminder(overrides)
    local r = {
        time = 30,
        tag = "everyone",
        text = "Go",
        spellID = nil,
        phase = 1,
        phaseKey = "1",
        duration = 5,
        displayType = "Text",
        tts = nil,
        ttsTimer = 5,
        countdown = nil,
        sound = nil,
        bossSpell = nil,
        colors = nil,
    }
    if overrides then
        for k, v in pairs(overrides) do
            r[k] = v
        end
    end
    return r
end

local function makeNote(overrides)
    local n = {
        encounterID = nil,
        name = nil,
        difficulty = nil,
        reminders = {},
        lines = {},
    }
    if overrides then
        for k, v in pairs(overrides) do
            n[k] = v
        end
    end
    return n
end

local function addReminderToNote(note, reminder)
    local bucket = note.reminders[reminder.phaseKey]
    if not bucket then
        bucket = {}
        note.reminders[reminder.phaseKey] = bucket
    end
    bucket[#bucket + 1] = reminder
    note.lines[#note.lines + 1] = { type = "reminder", reminder = reminder }
end

local function addFreeformToNote(note, text)
    note.lines[#note.lines + 1] = { type = "freeform", text = text }
end

local function reminderFieldsEqual(a, b)
    local fields = {
        "time", "tag", "text", "spellID", "phase", "phaseKey",
        "duration", "displayType", "tts", "ttsTimer", "countdown",
        "sound", "bossSpell", "colors",
    }
    for _, field in ipairs(fields) do
        if a[field] ~= b[field] then
            return false, field
        end
    end
    return true
end

local function assertRemindersEquivalent(noteA, noteB)
    for phaseKey, buckA in pairs(noteA.reminders) do
        local buckB = noteB.reminders[phaseKey]
        assertNotNil(buckB, "phase " .. phaseKey .. " missing after round-trip")
        assertEquals(#buckA, #buckB,
            "phase " .. phaseKey .. " reminder count mismatch")
        for i = 1, #buckA do
            local ok, field = reminderFieldsEqual(buckA[i], buckB[i])
            assertTrue(ok,
                "phase " .. phaseKey .. " reminder " .. i ..
                " field '" .. tostring(field) .. "' differs: " ..
                tostring(buckA[i][field or ""]) .. " vs " ..
                tostring(buckB[i][field or ""]))
        end
    end
    for phaseKey in pairs(noteB.reminders) do
        assertNotNil(noteA.reminders[phaseKey],
            "unexpected phase " .. phaseKey .. " after round-trip")
    end
end

local function roundTrip(text)
    local noteA = Parser:Parse(text)
    assertNotNil(noteA, "initial parse failed")
    local serialized = Serializer:Serialize(noteA)
    local noteB = Parser:Parse(serialized)
    assertNotNil(noteB, "re-parse failed")
    return noteA, noteB, serialized
end

tests["nil note returns empty string"] = function()
    local result = Serializer:Serialize(nil)
    assertEquals(result, "")
end

tests["empty note returns empty string"] = function()
    local note = makeNote()
    local result = Serializer:Serialize(note)
    assertEquals(result, "")
end

tests["single reminder with all defaults produces minimal output"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder()
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local lines = {}
    for line in result:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    assertTrue(#lines >= 2, "expected at least metadata + reminder lines")

    local reminderLine = lines[#lines]
    assertTrue(reminderLine:find("time:30", 1, true) ~= nil, "missing time")
    assertTrue(reminderLine:find("tag:everyone", 1, true) ~= nil, "missing tag")
    assertTrue(reminderLine:find("text:Go", 1, true) ~= nil, "missing text")
    assertNil(reminderLine:find("ph:", 1, true), "ph:1 should be omitted")
    assertNil(reminderLine:find("dur:", 1, true), "dur:5 should be omitted")
    assertNil(reminderLine:find("displaytype", 1, true),
        "displaytype:Text should be omitted for text-only reminder")
    assertNil(reminderLine:lower():find("displaytype", 1, true),
        "displaytype:Text should be omitted (case-insensitive check)")
end

tests["single reminder with all fields populated emits correct order"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        time = 60,
        tag = "Healer",
        phase = 2,
        phaseKey = "2",
        text = "Spirit Link",
        spellID = 98008,
        duration = 8,
        displayType = "Bar",
        tts = "Move now",
        ttsTimer = 3,
        countdown = 5,
        sound = "RaidWarning",
        bossSpell = 456789,
        colors = "red",
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local lines = {}
    for line in result:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    local reminderLine = lines[#lines]

    local timePos = reminderLine:find("time:", 1, true)
    local tagPos = reminderLine:find("tag:", 1, true)
    local phPos = reminderLine:find("ph:", 1, true)
    local textPos = reminderLine:find("text:", 1, true)
    local spellPos = reminderLine:find("spellid:", 1, true)
    local durPos = reminderLine:find("dur:", 1, true)
    local dtPos = reminderLine:lower():find("displaytype:", 1, true)
    local ttsPos = reminderLine:lower():find("tts:", 1, true)
    local ttsTimerPos = reminderLine:lower():find("ttstimer:", 1, true)
    local countdownPos = reminderLine:find("countdown:", 1, true)
    local soundPos = reminderLine:find("sound:", 1, true)
    local bossSpellPos = reminderLine:lower():find("bossspell:", 1, true)
    local colorsPos = reminderLine:find("colors:", 1, true)

    assertNotNil(timePos, "missing time field")
    assertNotNil(tagPos, "missing tag field")
    assertNotNil(phPos, "missing ph field")
    assertNotNil(textPos, "missing text field")
    assertNotNil(spellPos, "missing spellid field")
    assertNotNil(durPos, "missing dur field")
    assertNotNil(dtPos, "missing displaytype field")
    assertNotNil(ttsPos, "missing tts field")
    assertNotNil(ttsTimerPos, "missing ttstimer field")
    assertNotNil(countdownPos, "missing countdown field")
    assertNotNil(soundPos, "missing sound field")
    assertNotNil(bossSpellPos, "missing bossspell field")
    assertNotNil(colorsPos, "missing colors field")

    assertTrue(timePos < tagPos, "time before tag")
    assertTrue(tagPos < phPos, "tag before ph")
    assertTrue(phPos < textPos, "ph before text")
    assertTrue(textPos < spellPos, "text before spellid")
    assertTrue(spellPos < durPos, "spellid before dur")
    assertTrue(durPos < dtPos, "dur before displaytype")
    assertTrue(dtPos < ttsPos, "displaytype before tts")
    assertTrue(ttsPos < ttsTimerPos, "tts before ttstimer")
    assertTrue(ttsTimerPos < countdownPos, "ttstimer before countdown")
    assertTrue(countdownPos < soundPos, "countdown before sound")
    assertTrue(soundPos < bossSpellPos, "sound before bossspell")
    assertTrue(bossSpellPos < colorsPos, "bossspell before colors")
end

tests["multi-phase note: ph:1 omitted, ph:2 present"] = function()
    local note = makeNote({ encounterID = 1 })
    local r1 = makeReminder({ time = 10, text = "P1" })
    local r2 = makeReminder({
        time = 20, text = "P2", phase = 2, phaseKey = "2",
    })
    addReminderToNote(note, r1)
    addReminderToNote(note, r2)

    local result = Serializer:Serialize(note)
    local lines = {}
    for line in result:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    local foundP1 = false
    local foundP2 = false
    for _, line in ipairs(lines) do
        if line:find("text:P1", 1, true) then
            foundP1 = true
            assertNil(line:find("ph:", 1, true),
                "ph:1 should be omitted for phase 1 reminder")
        end
        if line:find("text:P2", 1, true) then
            foundP2 = true
            assertNotNil(line:find("ph:2", 1, true),
                "ph:2 should be present for phase 2 reminder")
        end
    end
    assertTrue(foundP1, "phase 1 reminder not found in output")
    assertTrue(foundP2, "phase 2 reminder not found in output")
end

tests["freeform lines preserved in position between reminders"] = function()
    local note = makeNote({ encounterID = 1 })
    addFreeformToNote(note, "-- Phase 1 CDs")
    local r1 = makeReminder({ time = 30, text = "Go" })
    addReminderToNote(note, r1)
    addFreeformToNote(note, "-- Phase 2 stuff")
    local r2 = makeReminder({
        time = 10, text = "Spread", phase = 2, phaseKey = "2",
    })
    addReminderToNote(note, r2)

    local result = Serializer:Serialize(note)
    local lines = {}
    for line in result:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    local metaOffset = 0
    if lines[1] and lines[1]:find("EncounterID:", 1, true) then
        metaOffset = 1
    end

    assertEquals(lines[metaOffset + 1], "-- Phase 1 CDs")
    assertTrue(lines[metaOffset + 2]:find("time:30", 1, true) ~= nil,
        "second content line should be the first reminder")
    assertEquals(lines[metaOffset + 3], "-- Phase 2 stuff")
    assertTrue(lines[metaOffset + 4]:find("text:Spread", 1, true) ~= nil,
        "fourth content line should be the second reminder")
end

tests["metadata line: encounterID only"] = function()
    local note = makeNote({ encounterID = 3176 })
    local r = makeReminder()
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local firstLine = result:match("^([^\n]+)")
    assertNotNil(firstLine, "expected at least one line")
    assertTrue(firstLine:find("EncounterID: 3176", 1, true) ~= nil
        or firstLine:find("EncounterID:3176", 1, true) ~= nil,
        "metadata should contain EncounterID: 3176")
    assertNil(firstLine:find("Name:", 1, true), "no Name when nil")
    assertNil(firstLine:find("Difficulty:", 1, true), "no Difficulty when nil")
end

tests["metadata line: encounterID + name + difficulty"] = function()
    local note = makeNote({
        encounterID = 3176,
        name = "Sszorak",
        difficulty = "Mythic",
    })
    local r = makeReminder()
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local firstLine = result:match("^([^\n]+)")
    assertNotNil(firstLine, "expected metadata line")
    assertTrue(firstLine:find("EncounterID", 1, true) ~= nil,
        "metadata should have EncounterID")
    assertTrue(firstLine:find("3176", 1, true) ~= nil,
        "metadata should have the ID value")
    assertTrue(firstLine:find("Name", 1, true) ~= nil,
        "metadata should have Name")
    assertTrue(firstLine:find("Sszorak", 1, true) ~= nil,
        "metadata should have name value")
    assertTrue(firstLine:find("Difficulty", 1, true) ~= nil,
        "metadata should have Difficulty")
    assertTrue(firstLine:find("Mythic", 1, true) ~= nil,
        "metadata should have difficulty value")
end

tests["round-trip: parse -> serialize -> parse produces equivalent reminders"] = function()
    local text = table.concat({
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic",
        "time:30;tag:Healer;spellid:98008;text:Spirit Link;ph:1;dur:8;DisplayType:Icon",
        "time:60;tag:everyone;text:Dodge Breath;ph:1;dur:5;DisplayType:Bar;bossSpell:456789",
        "time:5;tag:everyone;text:Spread Now;ph:2;dur:5;DisplayType:Text;sound:RaidWarning",
        "time:3;tag:everyone;text:Soak Orbs;ph:2.5;dur:3;DisplayType:Text",
    }, "\n")

    local noteA, noteB = roundTrip(text)

    assertEquals(noteB.encounterID, noteA.encounterID)
    assertEquals(noteB.name, noteA.name)
    assertEquals(noteB.difficulty, noteA.difficulty)
    assertRemindersEquivalent(noteA, noteB)
end

tests["round-trip with freeform lines"] = function()
    local text = table.concat({
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic",
        "-- Phase 1 Healing CDs",
        "time:30;tag:Healer;spellid:98008;text:Spirit Link;ph:1;dur:8;DisplayType:Icon",
        "-- Phase 2",
        "time:5;tag:everyone;text:Spread Now;ph:2;dur:5;DisplayType:Text",
    }, "\n")

    local noteA, noteB = roundTrip(text)

    assertRemindersEquivalent(noteA, noteB)

    local freeformA = {}
    local freeformB = {}
    for _, line in ipairs(noteA.lines) do
        if line.type == "freeform" then
            freeformA[#freeformA + 1] = line.text
        end
    end
    for _, line in ipairs(noteB.lines) do
        if line.type == "freeform" then
            freeformB[#freeformB + 1] = line.text
        end
    end
    assertTableEquals(freeformA, freeformB)
end

tests["default omission: dur:5 omitted"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ duration = 5 })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertNil(line:find("dur:", 1, true),
                "dur:5 is the default and should be omitted")
        end
    end
end

tests["default omission: displaytype:Icon omitted when spellID present"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        spellID = 98008,
        displayType = "Icon",
        text = nil,
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("spellid:", 1, true) then
            assertNil(line:lower():find("displaytype:", 1, true),
                "displaytype:Icon should be omitted when spellID is present")
        end
    end
end

tests["default omission: displaytype:Text omitted when spellID nil"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ displayType = "Text", spellID = nil })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("text:Go", 1, true) then
            assertNil(line:lower():find("displaytype:", 1, true),
                "displaytype:Text should be omitted when spellID is nil")
        end
    end
end

tests["non-default displaytype is included"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        spellID = 98008,
        displayType = "Bar",
        text = nil,
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local found = false
    for line in result:gmatch("[^\n]+") do
        if line:find("spellid:", 1, true) then
            found = true
            assertNotNil(line:lower():find("displaytype:", 1, true),
                "non-default displaytype:Bar should be emitted")
            assertTrue(line:find("Bar", 1, true) ~= nil,
                "displaytype value should be Bar")
        end
    end
    assertTrue(found, "reminder line not found in output")
end

tests["TTS true serializes as string true"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = true })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertTrue(line:lower():find("tts:true", 1, true) ~= nil,
                "boolean true should serialize as tts:true")
        end
    end
end

tests["TTS false serializes as string false"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = false })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertTrue(line:lower():find("tts:false", 1, true) ~= nil,
                "boolean false should serialize as tts:false")
        end
    end
end

tests["TTS custom string serializes as raw string"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = "Move out now" })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertTrue(line:find("Move out now", 1, true) ~= nil,
                "custom TTS string should appear in output")
        end
    end
end

tests["duration clamped to time is serialized as-is"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ time = 4, duration = 4, ttsTimer = 4 })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:4", 1, true) then
            assertNotNil(line:find("dur:4", 1, true),
                "clamped duration of 4 (not default 5) should be emitted")
        end
    end
end

tests["colors field preserved"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ colors = "red green blue" })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local found = false
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            found = true
            assertTrue(line:find("colors:red green blue", 1, true) ~= nil,
                "colors field should be preserved")
        end
    end
    assertTrue(found, "reminder line not found")
end

tests["sound, countdown, bossSpell fields preserved"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        sound = "RaidWarning",
        countdown = 3,
        bossSpell = 456789,
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local found = false
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            found = true
            assertTrue(line:find("sound:RaidWarning", 1, true) ~= nil,
                "sound field should be preserved")
            assertTrue(line:find("countdown:3", 1, true) ~= nil,
                "countdown field should be preserved")
            assertTrue(line:lower():find("bossspell:456789", 1, true) ~= nil,
                "bossSpell field should be preserved")
        end
    end
    assertTrue(found, "reminder line not found")
end

tests["ttstimer omitted when it equals duration"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = true, duration = 8, ttsTimer = 8 })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertNil(line:lower():find("ttstimer:", 1, true),
                "ttstimer should be omitted when it equals duration")
        end
    end
end

tests["ttstimer emitted when it differs from duration"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = true, duration = 8, ttsTimer = 3 })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    local found = false
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            found = true
            assertNotNil(line:lower():find("ttstimer:3", 1, true),
                "ttstimer should be emitted when it differs from duration")
        end
    end
    assertTrue(found, "reminder line not found")
end

tests["inert note (no encounterID) with reminders serializes without metadata line"] = function()
    local note = makeNote()
    local r = makeReminder({ time = 10, text = "Stack" })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    assertNotNil(result, "expected non-empty output")
    assertTrue(result ~= "", "expected non-empty output for inert note with content")

    local firstLine = result:match("^([^\n]+)")
    assertNil(firstLine:find("EncounterID", 1, true),
        "inert note should have no metadata line")
    assertTrue(firstLine:find("time:10", 1, true) ~= nil,
        "first line should be the reminder")
end

tests["tts nil is not emitted"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({ tts = nil })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertNil(line:lower():find("tts:", 1, true),
                "tts:nil should not produce a tts field")
        end
    end
end

tests["round-trip preserves tts boolean false"] = function()
    local text = table.concat({
        "EncounterID:1000",
        "time:30;tag:everyone;text:Move;tts:false",
    }, "\n")

    local noteA, noteB = roundTrip(text)
    local rA = noteA.reminders["1"][1]
    local rB = noteB.reminders["1"][1]
    assertEquals(rA.tts, false)
    assertEquals(rB.tts, false)
end

tests["round-trip preserves tts boolean true"] = function()
    local text = table.concat({
        "EncounterID:1000",
        "time:30;tag:everyone;text:Move;tts:true",
    }, "\n")

    local noteA, noteB = roundTrip(text)
    local rA = noteA.reminders["1"][1]
    local rB = noteB.reminders["1"][1]
    assertEquals(rA.tts, true)
    assertEquals(rB.tts, true)
end

tests["serialized output uses semicolon-space separator"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        time = 30,
        tag = "everyone",
        text = "Go",
        phase = 2,
        phaseKey = "2",
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("time:", 1, true) then
            assertTrue(line:find("; ", 1, true) ~= nil,
                "fields should be separated by semicolon-space")
        end
    end
end

tests["field keys are lowercase in serialized output"] = function()
    local note = makeNote({ encounterID = 1 })
    local r = makeReminder({
        spellID = 98008,
        displayType = "Bar",
        bossSpell = 456789,
        text = nil,
    })
    addReminderToNote(note, r)

    local result = Serializer:Serialize(note)
    for line in result:gmatch("[^\n]+") do
        if line:find("spellid:", 1, true) then
            assertTrue(line:find("displaytype:", 1, true) ~= nil,
                "displaytype key should be lowercase")
            assertTrue(line:find("bossspell:", 1, true) ~= nil,
                "bossspell key should be lowercase")
            assertNil(line:find("DisplayType", 1, true),
                "DisplayType should not appear (must be lowercase)")
            assertNil(line:find("bossSpell", 1, true),
                "bossSpell should not appear (must be lowercase)")
        end
    end
end

return tests
