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
    local edit = NotesEditor.GetAlertFieldKeys("edit")
    assertTrue(contains(edit, "duration"))
    assertTrue(contains(edit, "bossSpell"))
    assertFalse(contains(edit, "displayType"))
    assertFalse(contains(edit, "sound"))
    assertFalse(contains(edit, "ttsMode"))
    assertFalse(contains(edit, "ttsCustom"))
    assertFalse(contains(edit, "audioLeadTime"))
    assertFalse(contains(edit, "countdown"))

    local annotation = NotesEditor.GetAlertFieldKeys("annotation")
    assertTrue(contains(annotation, "displayType"))
    assertTrue(contains(annotation, "sound"))
    assertTrue(contains(annotation, "ttsMode"))
    assertTrue(contains(annotation, "audioLeadTime"))
    assertTrue(contains(annotation, "countdown"))
    assertFalse(contains(annotation, "duration"))
    assertFalse(contains(annotation, "time"))
    assertFalse(contains(annotation, "who"))

    local personal = NotesEditor.GetAlertFieldKeys("personal")
    assertTrue(contains(personal, "duration"))
    assertTrue(contains(personal, "displayType"))
    assertTrue(contains(personal, "sound"))
    assertTrue(contains(personal, "ttsMode"))
    assertTrue(contains(personal, "audioLeadTime"))
    assertTrue(contains(personal, "countdown"))
    assertTrue(contains(personal, "bossSpell"))
    assertTrue(contains(personal, "colors"))
    assertFalse(contains(personal, "who"))

    for _, field in ipairs(edit) do
        if field ~= "who" then
            assertTrue(contains(personal, field),
                "personal reminders should include main-note field " .. field)
        end
    end
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

tests["editing display text recovers the stored ability when the target is unavailable"] = function()
    local originalSpellData = PurplexityRaidTools.SpellData
    PurplexityRaidTools.SpellData = {
        [71] = {
            abilities = {
                rallyingCry = {
                    name = "Rallying Cry",
                    spellId = 97462,
                    cooldown = 180,
                },
            },
        },
    }

    local ok, ability, displayText = pcall(
        NotesEditor.SplitReminderText,
        "Rallying Cry first Dirge",
        {},
        97462
    )
    PurplexityRaidTools.SpellData = originalSpellData

    if not ok then
        error(ability)
    end
    assertEquals(ability, "Rallying Cry")
    assertEquals(displayText, "first Dirge")
    assertEquals(
        NotesEditor.BuildReminderText(ability, "second Dirge"),
        "Rallying Cry second Dirge"
    )

    ability, displayText = NotesEditor.SplitReminderText(
        "Soak the next orbs",
        {},
        nil
    )
    assertEquals(ability, "")
    assertEquals(displayText, "Soak the next orbs")
    assertEquals(
        NotesEditor.BuildReminderText(ability, "Soak the final orbs"),
        "Soak the final orbs"
    )
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
