local tests = {}

if not PurplexityRaidTools.NotesPlanner then
    dofile("Modules/Notes/NotesPlanner.lua")
end

if not PurplexityRaidTools.NotesEditor then
    dofile("Modules/Notes/NotesEditor.lua")
end

if not PurplexityRaidTools.NotesSerializer then
    dofile("Modules/Notes/NotesSerializer.lua")
end

local NotesEditor = PurplexityRaidTools.NotesEditor

local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then
            return true
        end
    end
    return false
end

local function makeNote(reminders)
    return {
        reminders = { ["1"] = reminders },
        lines = {},
    }
end

tests["TTS form state distinguishes off reminder text and custom text"] = function()
    local mode, customText = NotesEditor.GetTTSFormState(nil)
    assertEquals(mode, "off")
    assertEquals(customText, "")

    mode, customText = NotesEditor.GetTTSFormState(false)
    assertEquals(mode, "off")
    assertEquals(customText, "")

    mode, customText = NotesEditor.GetTTSFormState(true)
    assertEquals(mode, "reminder")
    assertEquals(customText, "")

    mode, customText = NotesEditor.GetTTSFormState("Move now")
    assertEquals(mode, "custom")
    assertEquals(customText, "Move now")
end

tests["TTS form values preserve the parser contract"] = function()
    assertNil(NotesEditor.BuildTTSValue("off", "ignored"))
    assertEquals(NotesEditor.BuildTTSValue("reminder", "ignored"), true)
    assertEquals(NotesEditor.BuildTTSValue("custom", "Move now"), "Move now")

    local value, err = NotesEditor.BuildTTSValue("custom", "")
    assertNil(value)
    assertEquals(err, "Custom TTS text is required.")
end

tests["alert timing accepts numeric seconds and optional countdown"] = function()
    local values = NotesEditor.ParseAlertTiming("8", "3", "")
    assertTableEquals(values, {
        duration = 8,
        audioLeadTime = 3,
        countdown = nil,
    })

    values = NotesEditor.ParseAlertTiming("", "0", "10")
    assertTableEquals(values, {
        duration = 5,
        audioLeadTime = 0,
        countdown = 10,
    })
end

tests["alert timing rejects invalid ranges"] = function()
    local values, err = NotesEditor.ParseAlertTiming("0", "3", "3")
    assertNil(values)
    assertEquals(err, "Duration must be at least 1 second.")

    values, err = NotesEditor.ParseAlertTiming("5", "-1", "3")
    assertNil(values)
    assertEquals(err, "Audio Lead Time cannot be negative.")

    values, err = NotesEditor.ParseAlertTiming("5", "3", "11")
    assertNil(values)
    assertEquals(err, "Countdown must be between 1 and 10 seconds.")
end

tests["annotation reminder includes every presentation override"] = function()
    local source = {
        time = 30,
        tag = "Niv",
        text = "Move",
        phase = 1,
        phaseKey = "1",
        duration = 5,
    }
    local annotation = NotesEditor.BuildAnnotationReminder(source, {
        displayType = "Bar",
        sound = "Raid Warning",
        tts = "Move now",
        audioLeadTime = 3,
        countdown = 5,
    })

    assertEquals(annotation.displayType, "Bar")
    assertEquals(annotation.sound, "Raid Warning")
    assertEquals(annotation.tts, "Move now")
    assertEquals(annotation.ttsTimer, 3)
    assertEquals(annotation.countdown, 5)

    local note = makeNote({ annotation })
    note.lines = { { type = "reminder", reminder = annotation } }
    local serialized = PurplexityRaidTools.NotesSerializer:Serialize(note)
    assertTrue(serialized:find("sound:Raid Warning", 1, true) ~= nil)
    assertTrue(serialized:find("tts:Move now", 1, true) ~= nil)
    assertTrue(serialized:find("ttstimer:3", 1, true) ~= nil)
    assertTrue(serialized:find("countdown:5", 1, true) ~= nil)
end

tests["field layouts keep annotation content immutable and personal forms consistent"] = function()
    local annotation = NotesEditor.GetAlertFieldKeys("annotation")
    assertTrue(contains(annotation, "displayType"))
    assertTrue(contains(annotation, "audioLeadTime"))
    assertFalse(contains(annotation, "duration"))
    assertFalse(contains(annotation, "time"))
    assertFalse(contains(annotation, "who"))

    local personal = NotesEditor.GetAlertFieldKeys("personal")
    assertTrue(contains(personal, "duration"))
    assertTrue(contains(personal, "displayType"))
    assertTrue(contains(personal, "audioLeadTime"))
    assertFalse(contains(personal, "who"))
end

tests["sound options are sorted and preserve an unavailable current value"] = function()
    local options = NotesEditor.BuildSoundOptions(
        { "Zing", "Alarm", "Alarm", "None" },
        "Old\\Custom.ogg"
    )

    assertEquals(options[1].value, "")
    assertEquals(options[1].name, "None")
    assertEquals(options[2].value, "Alarm")
    assertEquals(options[3].value, "Zing")
    assertEquals(options[4].value, "Old\\Custom.ogg")
    assertEquals(options[4].name, "Old\\Custom.ogg (current)")
end

tests["editing a personal reminder replaces the stored annotation copy"] = function()
    local original = {
        time = 30,
        tag = "Niv",
        text = "Old",
        phase = 1,
        phaseKey = "1",
    }
    local replacement = {
        time = 35,
        tag = "Niv",
        text = "New",
        phase = 1,
        phaseKey = "1",
    }
    local note = makeNote({ original })
    note.lines = {
        { type = "reminder", reminder = original },
        { type = "freeform", text = "Keep position" },
    }

    NotesEditor.ReplaceAnnotationReminder(note, original, replacement)

    assertEquals(#note.reminders["1"], 1)
    assertEquals(note.reminders["1"][1], replacement)
    assertEquals(#note.lines, 2)
    assertEquals(note.lines[1].reminder, replacement)
    assertEquals(note.lines[2].text, "Keep position")
end

tests["deleting a personal reminder removes the stored annotation copy"] = function()
    local original = {
        time = 30,
        tag = "Niv",
        text = "Old",
        phase = 1,
        phaseKey = "1",
    }
    local note = makeNote({ original })
    note.lines = {
        { type = "reminder", reminder = original },
        { type = "freeform", text = "Keep me" },
    }

    local removed = NotesEditor.ReplaceAnnotationReminder(note, original, nil)

    assertTrue(removed)
    assertNil(note.reminders["1"])
    assertEquals(#note.lines, 1)
    assertEquals(note.lines[1].text, "Keep me")
end

return tests
