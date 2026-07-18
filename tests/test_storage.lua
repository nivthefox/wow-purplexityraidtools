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

-- Reset the fake profile's notes table to a known-empty state before each test.
local function resetNotes()
    PRT.Profiles.current.notes = { savedNotes = {} }
    return PRT.Profiles.current.notes
end

--------------------------------------------------------------------------------
-- Save
--------------------------------------------------------------------------------

tests["save creates a new note"] = function()
    local notes = resetNotes()
    local ok = Notes:SaveNote("Alpha", "text one")
    assertTrue(ok)
    assertNotNil(notes.savedNotes["Alpha"])
    assertEquals(notes.savedNotes["Alpha"].text, "text one")
end

tests["save overwrites an existing note's text"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:SaveNote("Alpha", "text two")
    assertTrue(ok)
    assertEquals(notes.savedNotes["Alpha"].text, "text two")
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
    assertEquals(notes.savedNotes["Alpha"].text, "EncounterID:3176;Name:Sszorak")
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
    assertEquals(notes.savedNotes["Alpha"].text, "EncounterID:3176;Name:Sszorak")
end

tests["rejected save over the active note keeps it active with old content"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "EncounterID:3176;Name:Sszorak")
    Notes:ActivateNote("Alpha")
    local text = "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"
    local ok = Notes:SaveNote("Alpha", text)
    assertFalse(ok)
    assertEquals(notes.activeNote, "Alpha")
    assertEquals(notes.savedNotes["Alpha"].text, "EncounterID:3176;Name:Sszorak")
end

--------------------------------------------------------------------------------
-- Delete
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Rename
--------------------------------------------------------------------------------

tests["rename moves the note text"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    local ok = Notes:RenameNote("Alpha", "Gamma")
    assertTrue(ok)
    assertNil(notes.savedNotes["Alpha"])
    assertNotNil(notes.savedNotes["Gamma"])
    assertEquals(notes.savedNotes["Gamma"].text, "text one")
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
    assertEquals(notes.savedNotes["Alpha"].text, "text one")
    assertEquals(notes.savedNotes["Beta"].text, "text two")
end

tests["rename of a nonexistent note fails"] = function()
    resetNotes()
    local ok = Notes:RenameNote("Ghost", "Gamma")
    assertFalse(ok)
end

--------------------------------------------------------------------------------
-- Activate
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- GetActiveNote
--------------------------------------------------------------------------------

tests["GetActiveNote round-trips name and table"] = function()
    local notes = resetNotes()
    Notes:SaveNote("Alpha", "text one")
    Notes:ActivateNote("Alpha")
    local name, noteTable = Notes:GetActiveNote()
    assertEquals(name, "Alpha")
    assertNotNil(noteTable)
    assertEquals(noteTable.text, "text one")
end

tests["GetActiveNote returns nil when nothing is active"] = function()
    resetNotes()
    local name, noteTable = Notes:GetActiveNote()
    assertNil(name)
    assertNil(noteTable)
end

return tests
