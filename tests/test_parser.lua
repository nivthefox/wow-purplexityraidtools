-- tests/test_parser.lua
-- Exercises NotesParser:Parse against the NEW single-encounter contract
-- (spec 21a81ca §2 note format, §3.2 validation, §4 parsing).
--
-- Parse(text) -> note, nil  on success, or  nil, errMessage  on invalid input.
-- The note is FLAT (one encounter per note), per the FROZEN DATA CONTRACT
-- (rev 2) at the top of Modules/Notes/Notes.lua:
--
--   note = {
--     encounterID = number or nil,   -- nil = inert note (no metadata line)
--     name,                          -- string or nil
--     difficulty,                    -- "Normal"|"Heroic"|"Mythic" or nil (any)
--     reminders = { [phaseKey(string)] = array sorted by time },
--     lines = ordered { type = "reminder"|"freeform", ... },  -- note-frame order
--   }
--   Reminder = { time, tag, text, spellID, phase(number), phaseKey(string),
--                duration, displayType, tts, ttsTimer, countdown, sound,
--                bossSpell, colors, relevant(bool, set by tag matcher) }
--
-- INVALID (more than one line containing "EncounterID:") -> nil, EXACT message:
--   "A note may only contain one encounter. Use a separate note per encounter."
--
-- These tests assert only fields the PARSER is responsible for. `relevant` is
-- the tag matcher's job (Phase 5) and is not asserted here.

dofile("Modules/Notes/Notes.lua")
dofile("Modules/Notes/NotesParser.lua")

local PRT = PurplexityRaidTools
local Parser = PRT.NotesParser

local INVALID_MSG =
    "A note may only contain one encounter. Use a separate note per encounter."

local tests = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Parse and assert success (note, nil). Returns the note.
local function parseOK(text)
    local note, err = Parser:Parse(text)
    assertNil(err, "expected no error, got: " .. tostring(err))
    assertNotNil(note, "expected a note table on success")
    return note
end

-- Return the single reminder in a phase array, asserting there is exactly one.
local function onlyReminder(note, phaseKey)
    assertNotNil(note.reminders, "note.reminders should exist")
    local phase = note.reminders[phaseKey]
    assertNotNil(phase, "phase " .. phaseKey .. " should exist")
    assertEquals(#phase, 1, "expected exactly one reminder in phase " .. phaseKey)
    return phase[1]
end

local function countFreeform(note)
    local n = 0
    for _, line in ipairs(note.lines) do
        if line.type == "freeform" then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- Metadata line & flat note shape (spec 2.1, 4.3)
--------------------------------------------------------------------------------

tests["metadata populates encounterID, name, difficulty on the flat note"] = function()
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;dur:5"
    )
    assertEquals(note.encounterID, 3176)
    assertEquals(note.name, "Sszorak")
    assertEquals(note.difficulty, "Mythic")
end

tests["encounterID is stored as a number"] = function()
    -- ENCOUNTER_START hands consumers a numeric encounterID; a string here makes
    -- note.encounterID == liveEncounterID silently fail ("3176" ~= 3176).
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertEquals(note.encounterID, 3176)
    assertEquals(type(note.encounterID), "number")
end

tests["Difficulty present is stored as the difficulty string"] = function()
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak;Difficulty:Heroic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertEquals(note.difficulty, "Heroic")
    assertEquals(note.name, "Sszorak")
end

tests["missing Difficulty yields nil difficulty (matches any)"] = function()
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertNil(note.difficulty, "absent Difficulty should be nil")
    assertEquals(note.name, "Sszorak")
    assertEquals(note.encounterID, 3176)
end

tests["non-numeric EncounterID falls back to the raw string"] = function()
    -- Regression: a garbage id must not crash; the raw value is kept so the
    -- (never-matching) note still parses.
    local note = parseOK(
        "EncounterID:notanumber;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertEquals(note.encounterID, "notanumber")
    assertEquals(type(note.encounterID), "string")
end

--------------------------------------------------------------------------------
-- Multi-metadata rejection (spec 2.1, 3.2) — COUNT-BASED
--------------------------------------------------------------------------------

tests["two EncounterID lines are rejected with the exact message"] = function()
    local note, err = Parser:Parse(
        "EncounterID:3176;Name:Boss A;Difficulty:Mythic\n" ..
        "time:10;tag:everyone;text:A\n" ..
        "EncounterID:3009;Name:Boss B;Difficulty:Heroic\n" ..
        "time:20;tag:everyone;text:B"
    )
    assertNil(note, "a two-encounter note must not return a note")
    assertEquals(err, INVALID_MSG)
end

tests["three EncounterID lines are rejected with the exact message"] = function()
    local note, err = Parser:Parse(
        "EncounterID:3176;Name:A;Difficulty:Mythic\n" ..
        "time:10;tag:everyone;text:A\n" ..
        "EncounterID:3009;Name:B;Difficulty:Heroic\n" ..
        "time:20;tag:everyone;text:B\n" ..
        "EncounterID:2917;Name:C;Difficulty:Normal\n" ..
        "time:30;tag:everyone;text:C"
    )
    assertNil(note)
    assertEquals(err, INVALID_MSG)
end

tests["two IDENTICAL EncounterID lines are still rejected (count-based)"] = function()
    -- Rejection is by COUNT of "EncounterID:" lines, not by distinct ids: two
    -- lines for the same boss/difficulty are still two metadata lines.
    local note, err = Parser:Parse(
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:10;tag:everyone;text:A\n" ..
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:20;tag:everyone;text:B"
    )
    assertNil(note, "two metadata lines are invalid even when identical")
    assertEquals(err, INVALID_MSG)
end

--------------------------------------------------------------------------------
-- Inert note: no metadata line (spec 2.1, 2.3)
--------------------------------------------------------------------------------

tests["a note with no metadata line is valid but inert"] = function()
    local note, err = Parser:Parse(
        "-- just some notes\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertNil(err, "an inert note is valid, not an error")
    assertNotNil(note)
    assertNil(note.encounterID, "an inert note has no encounterID")
    assertNil(note.difficulty)
end

tests["inert note: every line is freeform, including timed-looking lines"] = function()
    -- Spec 2.1/2.2: with no metadata line there is no encounter context, so a
    -- line that would otherwise be a reminder is freeform instead.
    local note = parseOK(
        "-- header\n" ..
        "time:30;tag:everyone;text:Go\n" ..
        "time:60;tag:everyone;spellid:98008"
    )
    assertEquals(#note.lines, 3)
    for _, line in ipairs(note.lines) do
        assertEquals(line.type, "freeform",
            "inert-note lines must all be freeform")
    end
    -- No reminders were produced under any phase.
    local phases = 0
    for _ in pairs(note.reminders) do phases = phases + 1 end
    assertEquals(phases, 0, "an inert note produces no reminders")
end

tests["inert note preserves freeform text content in order"] = function()
    local note = parseOK(
        "First line\n" ..
        "Second line\n" ..
        "Third line"
    )
    assertEquals(#note.lines, 3)
    assertEquals(note.lines[1].text, "First line")
    assertEquals(note.lines[2].text, "Second line")
    assertEquals(note.lines[3].text, "Third line")
end

--------------------------------------------------------------------------------
-- Empty / nil input (contract reading: valid inert note, never an error)
--------------------------------------------------------------------------------

tests["empty string parses to a valid inert note (no error)"] = function()
    -- Reading: empty input has no metadata line, so it is an inert note, not an
    -- error. It carries no encounter, no reminders, and no lines.
    local note, err = Parser:Parse("")
    assertNil(err, "empty input is not an error")
    assertNotNil(note, "empty input still yields a note")
    assertNil(note.encounterID)
    assertNotNil(note.reminders, "reminders table should exist even when empty")
    assertNotNil(note.lines, "lines table should exist even when empty")
    assertEquals(#note.lines, 0)
end

tests["nil input parses to a valid inert note (no error)"] = function()
    -- Reading: nil is treated the same as empty — a valid inert note.
    local note, err = Parser:Parse(nil)
    assertNil(err, "nil input is not an error")
    assertNotNil(note)
    assertNil(note.encounterID)
    assertEquals(#note.lines, 0)
end

--------------------------------------------------------------------------------
-- Content BEFORE the metadata line is KEPT as freeform (flipped behavior)
--------------------------------------------------------------------------------

tests["freeform lines before the metadata line are kept, in order"] = function()
    -- OLD behavior dropped pre-metadata content; the NEW contract keeps it as
    -- freeform, and it must precede the metadata-derived lines in note.lines.
    local note = parseOK(
        "Title of the fight\n" ..
        "-- author: someone\n" ..
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    assertEquals(note.encounterID, 3176)
    -- 2 pre-metadata freeform lines + 1 reminder line = 3 note-frame lines.
    assertEquals(#note.lines, 3)
    assertEquals(note.lines[1].type, "freeform")
    assertEquals(note.lines[1].text, "Title of the fight")
    assertEquals(note.lines[2].type, "freeform")
    assertEquals(note.lines[2].text, "-- author: someone")
    assertEquals(note.lines[3].type, "reminder")
end

tests["a timed-looking line BEFORE the metadata line is freeform, not a reminder"] = function()
    -- A line with time/tag/text before the metadata line has no encounter
    -- context yet, so it is freeform (spec 2.2). Only the post-metadata timed
    -- line becomes a reminder.
    local note = parseOK(
        "time:99;tag:everyone;text:Too early\n" ..
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    -- Exactly one reminder, from the post-metadata line.
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Go")
    -- The pre-metadata timed line survives as freeform.
    assertEquals(note.lines[1].type, "freeform")
    assertEquals(note.lines[1].text, "time:99;tag:everyone;text:Too early")
    assertEquals(countFreeform(note), 1)
end

--------------------------------------------------------------------------------
-- Timed-line recognition (spec 2.2, 4.2)
--------------------------------------------------------------------------------

tests["a full timed line under the metadata line is a reminder"] = function()
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\n" ..
        "time:30;tag:Healer;spellid:98008;text:Spirit Link;ph:1;dur:8"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.time, 30)
    assertEquals(r.tag, "Healer")
    assertEquals(r.text, "Spirit Link")
    assertEquals(r.spellID, 98008)
end

tests["a line with time and tag and text (no spellid) is a reminder"] = function()
    local note = parseOK(
        "EncounterID:3176;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Dodge"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Dodge")
    assertNil(r.spellID)
end

tests["a line with time and tag and spellid (no text) is a reminder"] = function()
    local note = parseOK(
        "EncounterID:3176;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;spellid:62618"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.spellID, 62618)
    assertNil(r.text)
end

tests["a line missing tag is not a reminder (freeform)"] = function()
    local note = parseOK(
        "EncounterID:3176;Difficulty:Mythic\n" ..
        "time:30;text:No tag here"
    )
    assertNil(note.reminders["1"], "line without tag should not create a phase-1 reminder")
    assertEquals(countFreeform(note), 1, "the tag-less line should be recorded as freeform")
end

tests["a line missing both text and spellid is not a reminder"] = function()
    local note = parseOK(
        "EncounterID:3176;Difficulty:Mythic\n" ..
        "time:30;tag:everyone"
    )
    assertNil(note.reminders["1"], "line without text/spellid should not create a reminder")
end

--------------------------------------------------------------------------------
-- Field defaults (spec 2.2)
--------------------------------------------------------------------------------

tests["default phase is 1 with phaseKey '1'"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.phase, 1)
    assertEquals(r.phaseKey, "1")
end

tests["default duration is 5"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.duration, 5)
end

tests["DisplayType defaults to Icon when spellid present"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;spellid:98008"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.displayType, "Icon")
end

tests["DisplayType defaults to Text when no spellid"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.displayType, "Text")
end

tests["explicit DisplayType overrides the default"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;DisplayType:Bar"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.displayType, "Bar")
end

tests["ttsTimer defaults to dur when TTS is set"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;dur:8;TTS:true"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.ttsTimer, 8)
end

tests["ttsTimer defaults to dur even at the default duration"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;TTS:true"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.ttsTimer, 5)
end

tests["explicit TTSTimer is honored"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;dur:8;TTS:true;TTSTimer:3"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.ttsTimer, 3)
end

--------------------------------------------------------------------------------
-- Decimal times & fractional phases (spec 2.2)
--------------------------------------------------------------------------------

tests["decimal time is parsed as a number"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:90.5;tag:everyone;text:Go"
    )
    local r = onlyReminder(note, "1")
    assertNear(r.time, 90.5, 1e-9)
end

tests["fractional phase yields phase number and matching phaseKey"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:3;tag:everyone;text:Soak;ph:2.5"
    )
    local r = onlyReminder(note, "2.5")
    assertNear(r.phase, 2.5, 1e-9)
    assertEquals(r.phaseKey, "2.5")
end

--------------------------------------------------------------------------------
-- Clamping (spec 9.2.1)
--------------------------------------------------------------------------------

tests["duration is clamped to time"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:4;tag:everyone;text:Go;dur:10"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.duration, 4)
end

tests["ttsTimer is clamped to time"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:4;tag:everyone;text:Go;dur:4;TTS:true;TTSTimer:10"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.ttsTimer, 4)
end

--------------------------------------------------------------------------------
-- Unknown fields (spec 2.2 glowunit, 9.4)
--------------------------------------------------------------------------------

tests["unknown field glowunit is ignored without error"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;glowunit:Playername"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Go")
    assertNil(r.glowunit, "glowunit must not be stored on the reminder")
end

--------------------------------------------------------------------------------
-- TTS handling (spec 2.2, 9.1)
--------------------------------------------------------------------------------

tests["TTS:true parses to boolean true"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;TTS:true"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.tts, true)
end

tests["TTS:false parses to boolean false"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;TTS:false"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.tts, false)
end

tests["TTS custom string is preserved"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;TTS:Move out now"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.tts, "Move out now")
end

--------------------------------------------------------------------------------
-- Optional passthrough fields (spec 2.2)
--------------------------------------------------------------------------------

tests["sound, countdown, and bossSpell are captured"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go;sound:RaidWarning;countdown:3;bossSpell:456789"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.sound, "RaidWarning")
    assertEquals(r.countdown, 3)
    assertEquals(r.bossSpell, 456789)
end

--------------------------------------------------------------------------------
-- Robustness: CRLF, empty & garbage lines (spec 2.3, 4.2)
--------------------------------------------------------------------------------

tests["CRLF line endings are handled"] = function()
    local note = parseOK(
        "EncounterID:3176;Name:Sszorak;Difficulty:Mythic\r\n" ..
        "time:30;tag:everyone;text:Go\r\n"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Go")
    -- The trailing carriage return must not leak into difficulty/name.
    assertEquals(note.difficulty, "Mythic")
    assertEquals(note.name, "Sszorak")
end

tests["empty lines and garbage lines do not crash"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "\n" ..
        "-- just a comment\n" ..
        "totally unrelated garbage !@#$%\n" ..
        "\n" ..
        "time:30;tag:everyone;text:Go\n"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Go")
end

--------------------------------------------------------------------------------
-- First-colon-only pair splitting (spec 2.2: values may contain colons)
--------------------------------------------------------------------------------

tests["only the first colon in a pair splits key from value"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Stack at 3:00 mark"
    )
    local r = onlyReminder(note, "1")
    assertEquals(r.text, "Stack at 3:00 mark")
end

--------------------------------------------------------------------------------
-- Sorting (spec 4.3)
--------------------------------------------------------------------------------

tests["reminders are sorted by time within a phase"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:60;tag:everyone;text:Second\n" ..
        "time:10;tag:everyone;text:First\n" ..
        "time:30;tag:everyone;text:Middle"
    )
    local phase = note.reminders["1"]
    assertEquals(#phase, 3)
    assertEquals(phase[1].text, "First")
    assertEquals(phase[2].text, "Middle")
    assertEquals(phase[3].text, "Second")
    assertEquals(phase[1].time, 10)
    assertEquals(phase[2].time, 30)
    assertEquals(phase[3].time, 60)
end

tests["reminders split across phases land in separate phase arrays"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:10;tag:everyone;text:P1;ph:1\n" ..
        "time:20;tag:everyone;text:P2;ph:2"
    )
    local reminders = note.reminders
    assertEquals(#reminders["1"], 1)
    assertEquals(#reminders["2"], 1)
    assertEquals(reminders["1"][1].text, "P1")
    assertEquals(reminders["2"][1].text, "P2")
end

--------------------------------------------------------------------------------
-- lines array (contract: ordered note-frame lines)
--------------------------------------------------------------------------------

tests["lines array preserves note order and includes freeform lines"] = function()
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "-- Phase 1 CDs\n" ..
        "time:30;tag:everyone;text:Go\n" ..
        "-- trailing note\n" ..
        "time:60;tag:everyone;text:Again"
    )
    local lines = note.lines
    assertNotNil(lines, "note.lines should exist")
    -- Four content lines (the metadata line itself is not a note-frame line).
    assertEquals(#lines, 4)
    assertEquals(lines[1].type, "freeform")
    assertEquals(lines[2].type, "reminder")
    assertEquals(lines[3].type, "freeform")
    assertEquals(lines[4].type, "reminder")
end

tests["reminder lines in the lines array reference the reminder"] = function()
    -- A reminder-type line exposes the parsed reminder (line.reminder) so the
    -- note frame can render it. We assert the text round-trips through it.
    local note = parseOK(
        "EncounterID:1;Difficulty:Mythic\n" ..
        "time:30;tag:everyone;text:Go"
    )
    local lines = note.lines
    assertEquals(#lines, 1)
    assertEquals(lines[1].type, "reminder")
    assertNotNil(lines[1].reminder, "reminder line should carry a .reminder field")
    assertEquals(lines[1].reminder.text, "Go")
    -- The back-reference points at the very reminder stored in the phase array.
    assertEquals(lines[1].reminder, note.reminders["1"][1],
        "line.reminder should be the same object filed under its phase")
end

--------------------------------------------------------------------------------
-- Integration: the spec 2.4 complete-note fixture (single encounter)
--------------------------------------------------------------------------------

local SPEC_EXAMPLE = table.concat({
    "EncounterID:3176;Name:Sszorak;Difficulty:Mythic",
    "-- Phase 1 Healing CDs",
    "time:30;tag:Healername1 Healername2;spellid:98008;text:Spirit Link;ph:1;dur:8;DisplayType:Icon",
    "time:60;tag:Healername3;spellid:62618;text:Barrier;ph:1;dur:8;DisplayType:Icon",
    "time:90;tag:Healername4;spellid:102342;text:Ironbark on Tank;ph:1;dur:8;DisplayType:Icon",
    "-- Phase 1 Dodge",
    "time:45;tag:everyone;text:Dodge Breath;ph:1;dur:5;DisplayType:Bar;bossSpell:456789",
    "-- Phase 2",
    "time:5;tag:everyone;text:Spread Now;ph:2;dur:5;DisplayType:Text;sound:RaidWarning",
    "-- Intermission",
    "time:3;tag:everyone;text:Soak Orbs;ph:2.5;dur:5;DisplayType:Text",
}, "\n")

tests["spec 2.4 fixture: single encounter metadata"] = function()
    local note = parseOK(SPEC_EXAMPLE)
    assertEquals(note.encounterID, 3176)
    assertEquals(note.name, "Sszorak")
    assertEquals(note.difficulty, "Mythic")
end

tests["spec 2.4 fixture: reminder counts per phase"] = function()
    local note = parseOK(SPEC_EXAMPLE)
    local reminders = note.reminders
    -- Phase 1: three healing CDs + one dodge = 4.
    assertEquals(#reminders["1"], 4, "phase 1 should hold 4 reminders")
    -- Phase 2: one spread = 1.
    assertEquals(#reminders["2"], 1, "phase 2 should hold 1 reminder")
    -- Phase 2.5 intermission: one soak = 1.
    assertEquals(#reminders["2.5"], 1, "phase 2.5 should hold 1 reminder")
end

tests["spec 2.4 fixture: phase-1 reminders are time-sorted"] = function()
    local note = parseOK(SPEC_EXAMPLE)
    local phase1 = note.reminders["1"]
    -- Note order is 30, 60, 90, 45; sorted must be 30, 45, 60, 90.
    assertEquals(phase1[1].time, 30)
    assertEquals(phase1[2].time, 45)
    assertEquals(phase1[3].time, 60)
    assertEquals(phase1[4].time, 90)
    assertEquals(phase1[1].text, "Spirit Link")
    assertEquals(phase1[2].text, "Dodge Breath")
    assertEquals(phase1[3].text, "Barrier")
    assertEquals(phase1[4].text, "Ironbark on Tank")
end

tests["spec 2.4 fixture: spot-check field values"] = function()
    local note = parseOK(SPEC_EXAMPLE)
    local phase1 = note.reminders["1"]

    -- Spirit Link (time 30): spellID, Icon, dur 8, multi-target tag.
    local spiritLink = phase1[1]
    assertEquals(spiritLink.spellID, 98008)
    assertEquals(spiritLink.displayType, "Icon")
    assertEquals(spiritLink.duration, 8)
    assertEquals(spiritLink.tag, "Healername1 Healername2")
    assertEquals(spiritLink.phase, 1)

    -- Dodge Breath (time 45): Bar display, bossSpell, no spellID.
    local dodge = phase1[2]
    assertEquals(dodge.displayType, "Bar")
    assertEquals(dodge.bossSpell, 456789)
    assertNil(dodge.spellID)

    -- Spread Now (phase 2): sound set.
    local spread = note.reminders["2"][1]
    assertEquals(spread.sound, "RaidWarning")
    assertEquals(spread.displayType, "Text")

    -- Soak Orbs (phase 2.5): fractional phase, phaseKey "2.5".
    local soak = note.reminders["2.5"][1]
    assertNear(soak.phase, 2.5, 1e-9)
    assertEquals(soak.phaseKey, "2.5")
    assertEquals(soak.time, 3)
end

tests["spec 2.4 fixture: freeform comment lines are recorded in the lines array"] = function()
    local note = parseOK(SPEC_EXAMPLE)
    local freeform = 0
    local reminderLines = 0
    for _, line in ipairs(note.lines) do
        if line.type == "freeform" then
            freeform = freeform + 1
        elseif line.type == "reminder" then
            reminderLines = reminderLines + 1
        end
    end
    -- Four comment lines: Healing CDs, Dodge, Phase 2, Intermission.
    assertEquals(freeform, 4, "the fixture has 4 comment lines")
    assertEquals(reminderLines, 6, "the fixture has 6 timed reminder lines")
end

return tests
