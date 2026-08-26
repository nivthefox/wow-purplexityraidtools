-- tests/test_storage.lua
-- Exercises the Notes module's storage operations (spec 3.2).
-- These are pure table manipulations on PRT.Profiles:GetCurrent().notes.

local tests = {}

--------------------------------------------------------------------------------
-- Load the Notes module under test.
--
-- Notes.lua registers itself and declares PRT.defaults.notes on load, then
-- exposes the module table at PRT.Notes. The storage functions operate on
-- PRT.Profiles:GetCurrent().notes, so each test seeds that table directly.
--------------------------------------------------------------------------------

dofile("Modules/Notes/Notes.lua")

local PRT = PurplexityRaidTools

-- Save-time validation (spec 3.2) relies on NotesParser to detect notes with
-- more than one metadata line. The harness loads test_parser.lua first, so
-- PRT.NotesParser is usually already present, but load it here defensively so
-- this file runs standalone too.
if not PRT.NotesParser then
    dofile("Modules/Notes/NotesParser.lua")
end

local Notes = PRT.Notes

local MULTI_ENCOUNTER_ERROR =
    "A note may only contain one encounter. Use a separate note per encounter."

tests["legacy shared lock migrates to both independent locks"] = function()
    local settings = {
        locked = false,
        display = { locked = true },
        popups = { locked = true },
    }

    Notes:MigrateLockSettings(settings)

    assertNil(settings.locked)
    assertFalse(settings.display.locked)
    assertFalse(settings.popups.locked)
end

tests["independent note and popup locks survive migration"] = function()
    local settings = {
        display = { locked = true },
        popups = { locked = false },
    }

    Notes:MigrateLockSettings(settings)

    assertTrue(settings.display.locked)
    assertFalse(settings.popups.locked)
end

tests["missing note and popup locks default to locked"] = function()
    local settings = {}

    Notes:MigrateLockSettings(settings)

    assertTrue(settings.display.locked)
    assertTrue(settings.popups.locked)
end

-- Reset the fake profile's notes table to a known-empty state before each test.
local function resetNotes()
    PRT.Profiles.current.notes = { savedNotes = {}, annotations = {} }
    return PRT.Profiles.current.notes
end

tests["save creates a new note"] = function()
    local notes = resetNotes()
    local ok = Notes:SaveNote("Alpha", "text one")
    assertTrue(ok)
    assertNotNil(notes.savedNotes["Alpha"])
    assertEquals(notes.savedNotes["Alpha"], "text one")
end

tests["save overwrites an existing note's text"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:SaveNote("Alpha", "text two")
    assertTrue(ok)
    assertEquals(notes.savedNotes["Alpha"], "text two")
end

--------------------------------------------------------------------------------
-- Validation (spec 3.2)
--
-- SaveNote returns ok(boolean), errMessage(string or nil). A note with more
-- than one line containing "EncounterID:" is rejected and not stored.
--------------------------------------------------------------------------------

tests["save of a single-encounter note returns true, nil"] = function()
    local notes = resetNotes()
    local ok, err = Notes:SaveNote("Alpha", "EncounterID:3176;Name:Sszorak")
    assertTrue(ok)
    assertNil(err)
    assertNotNil(notes.savedNotes["Alpha"])
    assertEquals(notes.savedNotes["Alpha"], "EncounterID:3176;Name:Sszorak")
end

tests["save of an inert note (no metadata line) is valid"] = function()
    local notes = resetNotes()
    local ok, err = Notes:SaveNote("Alpha", "just a freeform reminder\nsecond line")
    assertTrue(ok)
    assertNil(err)
    assertNotNil(notes.savedNotes["Alpha"])
end

tests["save of a multi-encounter note is rejected and not stored"] = function()
    local notes = resetNotes()
    local text = "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"
    local ok, err = Notes:SaveNote("Alpha", text)
    assertFalse(ok)
    assertEquals(err, MULTI_ENCOUNTER_ERROR)
    assertNil(notes.savedNotes["Alpha"])
end

tests["rejected save leaves an existing note's content untouched"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "EncounterID:3176;Name:Sszorak")
    local text = "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"
    local ok, err = Notes:SaveNote("Alpha", text)
    assertFalse(ok)
    assertEquals(err, MULTI_ENCOUNTER_ERROR)
    assertEquals(notes.savedNotes["Alpha"], "EncounterID:3176;Name:Sszorak")
end

tests["rejected save over the active note keeps it active with old content"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "EncounterID:3176;Name:Sszorak")
    Notes:ActivateNote("Alpha")
    local text = "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"
    local ok = Notes:SaveNote("Alpha", text)
    assertFalse(ok)
    assertEquals(notes.activeNote, "Alpha")
    assertEquals(notes.savedNotes["Alpha"], "EncounterID:3176;Name:Sszorak")
end

tests["delete removes the note"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:DeleteNote("Alpha")
    assertTrue(ok)
    assertNil(notes.savedNotes["Alpha"])
end

tests["delete of the active note clears activeNote"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    assertEquals(notes.activeNote, "Alpha")
    Notes:DeleteNote("Alpha")
    assertNil(notes.activeNote)
end

tests["delete of a non-active note leaves activeNote alone"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:SaveNote("Beta", "text two")
    Notes:ActivateNote("Alpha")
    Notes:DeleteNote("Beta")
    assertEquals(notes.activeNote, "Alpha")
end

tests["delete of a nonexistent note returns false"] = function()
    resetNotes()
    local ok = Notes:DeleteNote("Ghost")
    assertFalse(ok)
end

tests["rename moves the note text"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:RenameNote("Alpha", "Gamma")
    assertTrue(ok)
    assertNil(notes.savedNotes["Alpha"])
    assertNotNil(notes.savedNotes["Gamma"])
    assertEquals(notes.savedNotes["Gamma"], "text one")
end

tests["rename of the active note updates activeNote"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    Notes:RenameNote("Alpha", "Gamma")
    assertEquals(notes.activeNote, "Gamma")
end

tests["rename onto an existing name fails and changes nothing"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:SaveNote("Beta", "text two")
    local ok = Notes:RenameNote("Alpha", "Beta")
    assertFalse(ok)
    assertEquals(notes.savedNotes["Alpha"], "text one")
    assertEquals(notes.savedNotes["Beta"], "text two")
end

tests["rename of a nonexistent note fails"] = function()
    resetNotes()
    local ok = Notes:RenameNote("Ghost", "Gamma")
    assertFalse(ok)
end

tests["activate sets activeNote"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:ActivateNote("Alpha")
    assertTrue(ok)
    assertEquals(notes.activeNote, "Alpha")
end

tests["activate of a nonexistent note fails and leaves state"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    local ok = Notes:ActivateNote("Ghost")
    assertFalse(ok)
    assertEquals(notes.activeNote, "Alpha")
end

tests["activate(nil) deactivates"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    local ok = Notes:ActivateNote(nil)
    assertTrue(ok)
    assertNil(notes.activeNote)
end

tests["GetActiveNote round-trips name and text"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    local name, text = Notes:GetActiveNote()
    assertEquals(name, "Alpha")
    assertEquals(text, "text one")
end

tests["GetActiveNote returns nil when nothing is active"] = function()
    resetNotes()
    local name, text = Notes:GetActiveNote()
    assertNil(name)
    assertNil(text)
end

tests["SaveAnnotation stores a plain string"] = function()
    local notes = resetNotes()
    local ok = Notes:SaveAnnotation("Alpha", "my annotation")
    assertTrue(ok)
    assertEquals(notes.annotations["Alpha"], "my annotation")
end

tests["SaveAnnotation validates via parser"] = function()
    local notes = resetNotes()
    local text = "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"
    local ok, err = Notes:SaveAnnotation("Alpha", text)
    assertFalse(ok)
    assertEquals(err, MULTI_ENCOUNTER_ERROR)
    assertNil(notes.annotations["Alpha"])
end

tests["GetAnnotation returns the stored string"] = function()
    local notes = resetNotes()
    Notes:SaveAnnotation("Alpha", "my annotation")
    local text = Notes:GetAnnotation("Alpha")
    assertEquals(text, "my annotation")
end

tests["GetAnnotation returns nil for nonexistent name"] = function()
    resetNotes()
    local text = Notes:GetAnnotation("Ghost")
    assertNil(text)
end

tests["DeleteAnnotation removes annotation"] = function()
    local notes = resetNotes()
    Notes:SaveAnnotation("Alpha", "my annotation")
    local ok = Notes:DeleteAnnotation("Alpha")
    assertTrue(ok)
    assertNil(notes.annotations["Alpha"])
end

tests["DeleteAnnotation of nonexistent name returns false"] = function()
    resetNotes()
    local ok = Notes:DeleteAnnotation("Ghost")
    assertFalse(ok)
end

tests["RenameNote also renames annotation"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:SaveAnnotation("Alpha", "my annotation")
    Notes:RenameNote("Alpha", "Gamma")
    assertNil(notes.annotations["Alpha"])
    assertEquals(notes.annotations["Gamma"], "my annotation")
end

tests["RenameNote with no annotation does not crash"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:RenameNote("Alpha", "Gamma")
    assertTrue(ok)
    assertNil(notes.annotations["Alpha"])
    assertNil(notes.annotations["Gamma"])
end

tests["DeleteNote also deletes annotation"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:SaveAnnotation("Alpha", "my annotation")
    Notes:DeleteNote("Alpha")
    assertNil(notes.annotations["Alpha"])
end

tests["DeleteNote with no annotation does not crash"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:DeleteNote("Alpha")
    assertTrue(ok)
    assertNil(notes.annotations["Alpha"])
end

return tests
