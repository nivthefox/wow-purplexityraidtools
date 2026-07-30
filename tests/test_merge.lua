dofile("Modules/Notes/Notes.lua")
dofile("Modules/Notes/NotesParser.lua")
dofile("Modules/Notes/NotesMerge.lua")

local PRT = PurplexityRaidTools
local Merge = PRT.NotesMerge

local tests = {}

local function makeReminder(overrides)
    local phase = (overrides and overrides.phase) or 1
    local r = {
        time = 30,
        tag = "everyone",
        text = "Go",
        spellID = nil,
        phase = phase,
        phaseKey = (overrides and overrides.phaseKey) or tostring(phase),
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

local function deepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function countReminders(note)
    local n = 0
    for _, bucket in pairs(note.reminders) do
        n = n + #bucket
    end
    return n
end

local function countLines(note, lineType)
    local n = 0
    for _, line in ipairs(note.lines) do
        if line.type == lineType then
            n = n + 1
        end
    end
    return n
end

tests["merge with nil annotationNote returns result identical to canonical"] = function()
    local canonical = makeNote({ encounterID = 3176, name = "Sszorak", difficulty = "Mythic" })
    local r1 = makeReminder({ time = 30, text = "Spirit Link" })
    addReminderToNote(canonical, r1)

    local merged, orphans = Merge:Merge(canonical, nil)

    assertNotNil(merged)
    assertEquals(merged.encounterID, 3176)
    assertEquals(merged.name, "Sszorak")
    assertEquals(merged.difficulty, "Mythic")
    assertEquals(countReminders(merged), 1)
    assertEquals(merged.reminders["1"][1].text, "Spirit Link")
    assertEquals(merged.reminders["1"][1].time, 30)
    assertNotNil(orphans)
    assertEquals(#orphans, 0)
end

tests["merge with empty annotationNote returns result identical to canonical"] = function()
    local canonical = makeNote({ encounterID = 3176, name = "Sszorak", difficulty = "Mythic" })
    local r1 = makeReminder({ time = 30, text = "Spirit Link" })
    addReminderToNote(canonical, r1)

    local annotation = makeNote()

    local merged, orphans = Merge:Merge(canonical, annotation)

    assertNotNil(merged)
    assertEquals(countReminders(merged), 1)
    assertEquals(merged.reminders["1"][1].text, "Spirit Link")
    assertEquals(#orphans, 0)
end

tests["presentation override replaces displayType sound tts ttsTimer countdown"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    local r1 = makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Text", sound = nil, tts = nil, ttsTimer = 5, countdown = nil,
    })
    addReminderToNote(canonical, r1)

    local annotation = makeNote()
    local override = makeReminder({
        time = 30, text = "Spirit Link", phase = 1, tag = "Healername1",
        displayType = "Icon", sound = "RaidWarning", tts = "Use Link Now",
        ttsTimer = 3, countdown = 5,
    })
    addReminderToNote(annotation, override)

    local merged, orphans = Merge:Merge(canonical, annotation)

    local result = merged.reminders["1"][1]
    assertEquals(result.displayType, "Icon")
    assertEquals(result.sound, "RaidWarning")
    assertEquals(result.tts, "Use Link Now")
    assertEquals(result.ttsTimer, 3)
    assertEquals(result.countdown, 5)
    assertEquals(#orphans, 0)
end

tests["presentation override does not change time tag text spellID duration bossSpell colors"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    local r1 = makeReminder({
        time = 30, tag = "Healer1 Healer2", text = "Spirit Link",
        spellID = 98008, phase = 1, duration = 8, bossSpell = 456789, colors = "red",
    })
    addReminderToNote(canonical, r1)

    local annotation = makeNote()
    local override = makeReminder({
        time = 30, text = "Spirit Link", phase = 1, tag = "DifferentTag",
        displayType = "Bar", sound = "Alert", spellID = 99999,
        duration = 20, bossSpell = 111111, colors = "blue",
    })
    addReminderToNote(annotation, override)

    local merged = Merge:Merge(canonical, annotation)

    local result = merged.reminders["1"][1]
    assertEquals(result.time, 30)
    assertEquals(result.tag, "Healer1 Healer2")
    assertEquals(result.text, "Spirit Link")
    assertEquals(result.spellID, 98008)
    assertEquals(result.duration, 8)
    assertEquals(result.bossSpell, 456789)
    assertEquals(result.colors, "red")
end

tests["personal reminder injection: non-matching annotation appears with isPersonal"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    local r1 = makeReminder({ time = 30, text = "Spirit Link", phase = 1 })
    addReminderToNote(canonical, r1)

    local annotation = makeNote()
    local personal = makeReminder({ time = 45, text = "Use Healthstone", phase = 1 })
    addReminderToNote(annotation, personal)

    local merged, orphans = Merge:Merge(canonical, annotation)

    assertEquals(countReminders(merged), 2)
    local bucket = merged.reminders["1"]
    local found = false
    for _, r in ipairs(bucket) do
        if r.text == "Use Healthstone" then
            found = true
            assertTrue(r.isPersonal, "personal reminder should have isPersonal = true")
        end
    end
    assertTrue(found, "personal reminder should appear in merged result")
    assertEquals(#orphans, 0)
end

tests["personal reminder injected at correct time position within phase"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({ time = 10, text = "First", phase = 1 }))
    addReminderToNote(canonical, makeReminder({ time = 50, text = "Third", phase = 1 }))

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({ time = 30, text = "Personal Middle", phase = 1 }))

    local merged = Merge:Merge(canonical, annotation)

    local bucket = merged.reminders["1"]
    assertEquals(#bucket, 3)
    assertEquals(bucket[1].time, 10)
    assertEquals(bucket[1].text, "First")
    assertEquals(bucket[2].time, 30)
    assertEquals(bucket[2].text, "Personal Middle")
    assertEquals(bucket[3].time, 50)
    assertEquals(bucket[3].text, "Third")
end

tests["personal reminder in merged result has correct phase bucket"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({ time = 30, text = "P1 Reminder", phase = 1 }))

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({
        time = 15, text = "Personal P2", phase = 2, phaseKey = "2",
    }))

    local merged = Merge:Merge(canonical, annotation)

    assertNotNil(merged.reminders["2"], "phase 2 bucket should exist")
    assertEquals(#merged.reminders["2"], 1)
    assertEquals(merged.reminders["2"][1].text, "Personal P2")
    assertTrue(merged.reminders["2"][1].isPersonal)
end

tests["multiple overrides across different phases"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Text",
    }))
    addReminderToNote(canonical, makeReminder({
        time = 15, text = "Spread", phase = 2, phaseKey = "2",
        displayType = "Text",
    }))

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Icon",
    }))
    addReminderToNote(annotation, makeReminder({
        time = 15, text = "Spread", phase = 2, phaseKey = "2",
        displayType = "Bar",
    }))

    local merged = Merge:Merge(canonical, annotation)

    assertEquals(merged.reminders["1"][1].displayType, "Icon")
    assertEquals(merged.reminders["2"][1].displayType, "Bar")
end

tests["collision: two canonical reminders with same triple override applies to first only"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    local dup1 = makeReminder({ time = 30, text = "Spirit Link", phase = 1, tag = "Healer1" })
    local dup2 = makeReminder({ time = 30, text = "Spirit Link", phase = 1, tag = "Healer2" })
    addReminderToNote(canonical, dup1)
    addReminderToNote(canonical, dup2)

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Icon", sound = "Alert",
    }))

    local merged = Merge:Merge(canonical, annotation)

    local bucket = merged.reminders["1"]
    assertEquals(#bucket, 2)
    assertEquals(bucket[1].displayType, "Icon")
    assertEquals(bucket[1].sound, "Alert")
    assertEquals(bucket[2].displayType, "Text")
    assertNil(bucket[2].sound)
end

tests["merged result lines ordering includes reminders and freeform in order"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addFreeformToNote(canonical, "-- Phase 1 CDs")
    addReminderToNote(canonical, makeReminder({ time = 30, text = "Go" }))
    addFreeformToNote(canonical, "-- Phase 1 Dodge")
    addReminderToNote(canonical, makeReminder({ time = 60, text = "Dodge" }))

    local merged = Merge:Merge(canonical, nil)

    assertEquals(#merged.lines, 4)
    assertEquals(merged.lines[1].type, "freeform")
    assertEquals(merged.lines[1].text, "-- Phase 1 CDs")
    assertEquals(merged.lines[2].type, "reminder")
    assertEquals(merged.lines[2].reminder.text, "Go")
    assertEquals(merged.lines[3].type, "freeform")
    assertEquals(merged.lines[3].text, "-- Phase 1 Dodge")
    assertEquals(merged.lines[4].type, "reminder")
    assertEquals(merged.lines[4].reminder.text, "Dodge")
end

tests["canonical note not mutated after merge"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Text", sound = nil,
    }))
    local originalSnapshot = deepCopy(canonical)

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Icon", sound = "Alert",
    }))

    Merge:Merge(canonical, annotation)

    assertEquals(canonical.reminders["1"][1].displayType, "Text")
    assertNil(canonical.reminders["1"][1].sound)
    assertEquals(canonical.encounterID, originalSnapshot.encounterID)
    assertEquals(#canonical.lines, #originalSnapshot.lines)
end

tests["annotation note not mutated after merge"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({ time = 30, text = "Spirit Link", phase = 1 }))

    local annotation = makeNote()
    local personal = makeReminder({ time = 45, text = "Use Healthstone", phase = 1 })
    addReminderToNote(annotation, personal)
    local annotationSnapshot = deepCopy(annotation)

    Merge:Merge(canonical, annotation)

    assertNil(annotation.reminders["1"][1].isPersonal, "annotation should not gain isPersonal")
    assertEquals(#annotation.lines, #annotationSnapshot.lines)
end

tests["merged result metadata matches canonical"] = function()
    local canonical = makeNote({ encounterID = 3176, name = "Sszorak", difficulty = "Mythic" })
    addReminderToNote(canonical, makeReminder({ time = 30, text = "Go" }))

    local annotation = makeNote({ encounterID = 9999, name = "Wrong Boss", difficulty = "Normal" })
    addReminderToNote(annotation, makeReminder({ time = 45, text = "Personal", phase = 1 }))

    local merged = Merge:Merge(canonical, annotation)

    assertEquals(merged.encounterID, 3176)
    assertEquals(merged.name, "Sszorak")
    assertEquals(merged.difficulty, "Mythic")
end

tests["merged result includes freeform lines from canonical note"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addFreeformToNote(canonical, "-- Healing assignments")
    addFreeformToNote(canonical, "-- Healer1: left, Healer2: right")
    addReminderToNote(canonical, makeReminder({ time = 30, text = "Go" }))

    local merged = Merge:Merge(canonical, nil)

    assertEquals(countLines(merged, "freeform"), 2)
    assertEquals(merged.lines[1].type, "freeform")
    assertEquals(merged.lines[1].text, "-- Healing assignments")
    assertEquals(merged.lines[2].type, "freeform")
    assertEquals(merged.lines[2].text, "-- Healer1: left, Healer2: right")
end

tests["personal reminder from a different phase than any canonical"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({ time = 30, text = "P1 Go", phase = 1 }))

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({
        time = 10, text = "Personal Intermission", phase = 2.5, phaseKey = "2.5",
    }))

    local merged, orphans = Merge:Merge(canonical, annotation)

    assertNotNil(merged.reminders["1"], "phase 1 bucket should still exist")
    assertEquals(#merged.reminders["1"], 1)
    assertEquals(merged.reminders["1"][1].text, "P1 Go")

    assertNotNil(merged.reminders["2.5"], "phase 2.5 bucket should exist for personal reminder")
    assertEquals(#merged.reminders["2.5"], 1)
    local personal = merged.reminders["2.5"][1]
    assertEquals(personal.text, "Personal Intermission")
    assertEquals(personal.time, 10)
    assertTrue(personal.isPersonal)
    assertEquals(#orphans, 0)
end

tests["override with nil fields does not wipe canonical values"] = function()
    local canonical = makeNote({ encounterID = 3176 })
    addReminderToNote(canonical, makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Text", sound = "RaidWarning", tts = "Go now",
        ttsTimer = 3, countdown = 5,
    }))

    local annotation = makeNote()
    local annReminder = makeReminder({
        time = 30, text = "Spirit Link", phase = 1,
        displayType = "Bar",
    })
    annReminder.sound = nil
    annReminder.tts = nil
    annReminder.ttsTimer = nil
    annReminder.countdown = nil
    addReminderToNote(annotation, annReminder)

    local merged = Merge:Merge(canonical, annotation)

    local result = merged.reminders["1"][1]
    assertEquals(result.displayType, "Bar")
    assertEquals(result.sound, "RaidWarning")
    assertEquals(result.tts, "Go now")
    assertEquals(result.ttsTimer, 3)
    assertEquals(result.countdown, 5)
end

tests["empty canonical with annotation reminders injects personal reminders"] = function()
    local canonical = makeNote({ encounterID = 3176 })

    local annotation = makeNote()
    addReminderToNote(annotation, makeReminder({ time = 30, text = "Personal" }))

    local merged, orphans = Merge:Merge(canonical, annotation)

    assertNotNil(merged.reminders["1"])
    assertEquals(#merged.reminders["1"], 1)
    assertEquals(merged.reminders["1"][1].text, "Personal")
    assertTrue(merged.reminders["1"][1].isPersonal)
    assertEquals(#orphans, 0)
end

return tests
