-- tests/test_wiring.lua
-- Characterization tests for the Notes broadcast send seam and the Comms
-- receive-handler wiring (Notes.lua §"Broadcast send seam" and
-- §"Comms receive handlers"). These pin committed composition behavior that was
-- previously verified only by reading: the send gates and their exact reason
-- strings, the hard combat ban on the send path, the payloads Send emits, and
-- the privilege/validation gates on the receive handlers registered by
-- Notes:OnEnable and driven through Comms:Dispatch.
--
-- The shared harness loads test files in sorted order, so by the time this file
-- runs Notes.lua, Comms.lua, the pure libs, NotesParser, and NotesTags are all
-- already present in the Lua state. Each dependency is loaded defensively below
-- so this file also runs standalone, mirroring test_storage.lua's convention.

local tests = {}

if strmatch == nil then
    strmatch = string.match
end

if not (PurplexityRaidTools.Comms) then
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/LibSerialize/LibSerialize.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
    dofile("Comms.lua")
end

if not PurplexityRaidTools.Notes then
    dofile("Modules/Notes/Notes.lua")
end
if not PurplexityRaidTools.NotesParser then
    dofile("Modules/Notes/NotesParser.lua")
end
if not PurplexityRaidTools.NotesTags then
    dofile("Modules/Notes/NotesTags.lua")
end

local PRT = PurplexityRaidTools
local Notes = PRT.Notes
local Comms = PRT.Comms

local REASON_NO_PRIVILEGE = "Requires raid leader or assistant."
local REASON_COMBAT = "Cannot send during combat."
local REASON_NO_NOTE = "No note selected."

local VALID_NOTE_TEXT = "EncounterID:3176;Name:Sszorak"
local INVALID_NOTE_TEXT =
    "EncounterID:3176;Name:Sszorak\nEncounterID:3009;Name:Anub"

--------------------------------------------------------------------------------
-- Isolation helpers
--------------------------------------------------------------------------------

-- Snapshot and restore an arbitrary set of globals around a test body so WoW-API
-- overrides never leak between tests (or into wow_stubs.lua). Mirrors the
-- withGlobals helper in test_comms.lua.
local function withGlobals(overrides, body)
    local saved = {}
    for k, v in pairs(overrides) do
        saved[k] = _G[k]
        _G[k] = v
    end
    local ok, err = pcall(body)
    for k in pairs(overrides) do
        _G[k] = saved[k]
    end
    if not ok then
        error(err, 0)
    end
end

-- Merge two override tables into a fresh table (right wins on key collision).
local function merge(a, b)
    local out = {}
    for k, v in pairs(a) do out[k] = v end
    if b then
        for k, v in pairs(b) do out[k] = v end
    end
    return out
end

-- Activating a note runs Notes:OnActiveNoteChanged -> BuildPlayerCtx, which
-- reads player context via WoW APIs that wow_stubs does not provide. These
-- neutral stubs let the ctx build succeed headless; GetNumGroupMembers returns 0
-- so the raid-roster loop body never executes (avoiding GetRaidRosterInfo).
local CTX_GLOBALS = {
    UnitGroupRolesAssigned = function() return "DAMAGER" end,
    GetNumGroupMembers = function() return 0 end,
    GetRaidRosterInfo = function() return nil end,
}

-- Reset the fake profile's notes table to a known-empty state.
local function resetNotes()
    PRT.Profiles.current.notes = { savedNotes = {} }
    return PRT.Profiles.current.notes
end

-- makeFrameSpy is defined below; seedActiveNote forward-references it.
local makeFrameSpy

-- Seed a single active saved note. Must run with CTX_GLOBALS in scope because
-- ActivateNote reparses through BuildPlayerCtx, which also calls
-- PRT.NotesFrame:SetNote once NotesTags is loaded. A frame spy is installed so
-- that side-effect has something to land on even in send-seam tests that do not
-- otherwise care about the frame.
local function seedActiveNote(name, text)
    if not PRT.NotesFrame then
        PRT.NotesFrame = makeFrameSpy()
    end
    Notes:SaveNote(name, text)
    Notes:ActivateNote(name)
end

-- A spy standing in for PRT.NotesFrame that records every call the send/receive
-- paths make against it. Show/Hide are the visibility signals the gate-order
-- regression guards assert against.
function makeFrameSpy()
    local spy = { showCount = 0, hideCount = 0, setNoteCalls = {}, rebuildCount = 0 }
    function spy:Init() end
    function spy:RebuildRoster()
        self.rebuildCount = self.rebuildCount + 1
    end
    function spy:SetNote(note)
        self.setNoteCalls[#self.setNoteCalls + 1] = note
        self.lastNote = note
    end
    function spy:Show()
        self.showCount = self.showCount + 1
    end
    function spy:Hide()
        self.hideCount = self.hideCount + 1
    end
    function spy:TickUpdate() end
    function spy:OnEncounterEnd() end
    return spy
end

-- Install a fresh frame spy, a no-op popups stub, a fresh eventFrame, and an
-- empty notes store, then register the receive handlers via the real
-- Notes:OnEnable. Returns the frame spy. The RegisterModule stub does not create
-- an eventFrame, so we assign a fake one before OnEnable touches it.
local function installReceiveHarness(overrides)
    resetNotes()
    local frameSpy = makeFrameSpy()
    PRT.NotesFrame = frameSpy
    PRT.NotesPopups = {
        Init = function() end,
        Show = function() end,
        PlayAudio = function() end,
        AnnounceCountdown = function() end,
        Expire = function() end,
        Dismiss = function() end,
        DismissAll = function() end,
    }
    Notes.eventFrame = {
        RegisterEvent = function() end,
        UnregisterAllEvents = function() end,
        SetScript = function() end,
    }
    withGlobals(overrides or {}, function()
        Notes:OnEnable()
    end)
    return frameSpy
end

-- Build the encoded wire string a compliant sender would broadcast for the given
-- msgType/data, so receive tests drive Dispatch with a real payload.
local function encode(msgType, data)
    return Comms:Encode({ type = msgType, data = data })
end

--------------------------------------------------------------------------------
-- Send seam: gate order and exact reason strings
--------------------------------------------------------------------------------

tests["BroadcastNote solo activates locally, shows the frame, never sends"] = function()
    resetNotes()

    local sent = false
    local frameSpy = makeFrameSpy()
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return false end,
        InCombatLockdown = function() return false end,
    }), function()
        PRT.NotesFrame = frameSpy
        Notes:SaveNote("Alpha", VALID_NOTE_TEXT)
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastNote("Alpha")
        assertTrue(ok, "solo send must succeed as a send-to-self")
        assertNil(reason)
        local activeName = Notes:GetActiveNote()
        assertEquals(activeName, "Alpha", "solo send must activate the note locally")
        assertEquals(frameSpy.showCount, 1, "solo send must show the frame (show-on-receive parity)")
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "solo send must never touch the wire")
end

tests["BroadcastNote refuses when in a group but not privileged"] = function()
    resetNotes()

    local sent = false
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return false end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return false end,
        UnitName = function(unit) return unit, nil end,
    }), function()
        seedActiveNote("Alpha", VALID_NOTE_TEXT)
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastNote("Alpha")
        assertFalse(ok, "a non-privileged member must be refused")
        assertEquals(reason, REASON_NO_PRIVILEGE)
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "no send may occur without privilege")
end

tests["BroadcastNote refuses in combat (privileged, in group) and NEVER sends"] = function()
    resetNotes()

    local sent = false
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return true end,
        UnitName = function(unit) return unit, nil end,
    }), function()
        seedActiveNote("Alpha", VALID_NOTE_TEXT)
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastNote("Alpha")
        assertFalse(ok, "combat must refuse even for a privileged leader")
        assertEquals(reason, REASON_COMBAT)
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "the combat ban must refuse before any send")
end

tests["BroadcastNote refuses in combat when solo (no local activation either)"] = function()
    resetNotes()

    local sent = false
    local frameSpy = makeFrameSpy()
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return false end,
        InCombatLockdown = function() return true end,
    }), function()
        PRT.NotesFrame = frameSpy
        Notes:SaveNote("Alpha", VALID_NOTE_TEXT)
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastNote("Alpha")
        assertFalse(ok, "the combat ban applies solo too")
        assertEquals(reason, REASON_COMBAT)
        assertNil((Notes:GetActiveNote()), "combat refusal must not activate")
        assertEquals(frameSpy.showCount, 0, "combat refusal must not show the frame")
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "no send may occur in combat")
end

tests["BroadcastNote refuses a nil or unknown selection (all gates green)"] = function()
    resetNotes()

    local sent = false
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return false end,
        UnitName = function(unit) return unit, nil end,
    }), function()
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastNote()
        assertFalse(ok, "nil selection must refuse")
        assertEquals(reason, REASON_NO_NOTE)
        local ok2, reason2 = Notes:BroadcastNote("DoesNotExist")
        assertFalse(ok2, "an unknown note name must refuse")
        assertEquals(reason2, REASON_NO_NOTE)
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "no send may occur without a valid selection")
end

tests["BroadcastNote sends the SELECTED note, not the active one"] = function()
    resetNotes()

    local captured = {}
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return false end,
        UnitName = function(unit) return unit, nil end,
    }), function()
        seedActiveNote("Alpha", VALID_NOTE_TEXT)
        Notes:SaveNote("Beta", "EncounterID:2000;Name:Other")
        Comms.sendFunc = function(encoded, channel)
            captured.encoded = encoded
            captured.channel = channel
        end
        local ok = Notes:BroadcastNote("Beta")
        assertTrue(ok, "sending a saved, non-active note must succeed")
    end)
    Comms.sendFunc = nil

    local ok, decoded = Comms:Decode(captured.encoded)
    assertTrue(ok)
    assertEquals(decoded.type, "note")
    assertEquals(decoded.data.name, "Beta", "the selection, not the active note, goes out")
    assertEquals(decoded.data.text, "EncounterID:2000;Name:Other")
end

--------------------------------------------------------------------------------
-- Send seam: success payloads
--------------------------------------------------------------------------------

tests["BroadcastNote sends msgType 'note' with {name, text} on the happy path"] = function()
    resetNotes()

    local captured = {}
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return false end,
        UnitName = function(unit) return unit, nil end,
    }), function()
        Notes:SaveNote("Alpha", VALID_NOTE_TEXT)
        Comms.sendFunc = function(encoded, channel)
            captured.encoded = encoded
            captured.channel = channel
        end
        local ok, reason = Notes:BroadcastNote("Alpha")
        assertTrue(ok, "all gates green must succeed")
        assertNil(reason, "success returns no reason")
    end)
    Comms.sendFunc = nil

    assertEquals(type(captured.encoded), "string", "Send must have been invoked")
    assertEquals(captured.channel, "RAID", "notes broadcast on the RAID channel")

    local ok, decoded = Comms:Decode(captured.encoded)
    assertTrue(ok, "captured payload must decode")
    assertEquals(decoded.type, "note")
    assertNotNil(decoded.data)
    assertEquals(decoded.data.name, "Alpha")
    assertEquals(decoded.data.text, VALID_NOTE_TEXT)
end

tests["BroadcastClear solo deactivates locally, hides, never sends"] = function()
    resetNotes()

    local sent = false
    local frameSpy
    withGlobals(merge(CTX_GLOBALS, {
        IsInGroup = function() return false end,
        InCombatLockdown = function() return false end,
    }), function()
        seedActiveNote("Alpha", VALID_NOTE_TEXT)
        frameSpy = PRT.NotesFrame
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastClear()
        assertTrue(ok, "solo clear must succeed as a clear-to-self")
        assertNil(reason)
        assertNil((Notes:GetActiveNote()), "solo clear must deactivate locally")
        assertEquals(frameSpy.hideCount, 1, "solo clear must hide the frame")
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "solo clear must never touch the wire")
end

tests["BroadcastClear sends msgType 'clear' with empty data on the happy path"] = function()
    resetNotes()

    local captured = {}
    withGlobals({
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return false end,
        UnitName = function(unit) return unit, nil end,
    }, function()
        Comms.sendFunc = function(encoded, channel)
            captured.encoded = encoded
            captured.channel = channel
        end
        local ok, reason = Notes:BroadcastClear()
        assertTrue(ok, "BroadcastClear needs no active note")
        assertNil(reason)
    end)
    Comms.sendFunc = nil

    assertEquals(type(captured.encoded), "string")
    assertEquals(captured.channel, "RAID")

    local ok, decoded = Comms:Decode(captured.encoded)
    assertTrue(ok)
    assertEquals(decoded.type, "clear")
    assertNotNil(decoded.data, "clear payload carries an (empty) data table")
    assertNil(next(decoded.data), "clear data table must be empty")
end

tests["BroadcastClear refuses in combat and NEVER sends"] = function()
    resetNotes()

    local sent = false
    withGlobals({
        IsInGroup = function() return true end,
        IsInRaid = function() return false end,
        UnitIsGroupLeader = function() return true end,
        UnitIsGroupAssistant = function() return false end,
        InCombatLockdown = function() return true end,
        UnitName = function(unit) return unit, nil end,
    }, function()
        Comms.sendFunc = function() sent = true end
        local ok, reason = Notes:BroadcastClear()
        assertFalse(ok, "clear must also honor the combat ban")
        assertEquals(reason, REASON_COMBAT)
    end)
    Comms.sendFunc = nil
    assertFalse(sent, "the combat ban must refuse the clear before any send")
end

--------------------------------------------------------------------------------
-- Receive wiring: driven through Comms:Dispatch with real encoded payloads
--
-- The receive path activates a note, which runs Notes:OnActiveNoteChanged ->
-- BuildPlayerCtx. BuildPlayerCtx reads UnitGroupRolesAssigned("player"), which
-- wow_stubs does not provide, so we stub it (and the privilege APIs) per test.
--------------------------------------------------------------------------------

local RECEIVE_GLOBALS = merge(CTX_GLOBALS, {
    IsInRaid = function() return true end,
    IsInGroup = function() return true end,
    UnitIsGroupLeader = function() return true end,
    UnitIsGroupAssistant = function() return false end,
    UnitName = function(unit) return unit, nil end,
})

local function unprivilegedGlobals()
    return merge(CTX_GLOBALS, {
        IsInRaid = function() return true end,
        IsInGroup = function() return true end,
        UnitIsGroupLeader = function() return false end,
        UnitIsGroupAssistant = function() return false end,
        UnitName = function(unit) return unit, nil end,
    })
end

tests["receive: privileged sender + valid note stores, activates, and Shows"] = function()
    local capturedPrint = {}
    withGlobals(RECEIVE_GLOBALS, function()
        local savedPrint = _G.print
        _G.print = function(msg) capturedPrint[#capturedPrint + 1] = msg end
        local frameSpy = installReceiveHarness()
        frameSpy.showCount = 0  -- ignore any Show from OnEnable itself

        local encoded = encode("note", { name = "Alpha", text = VALID_NOTE_TEXT })
        Comms:Dispatch(encoded, "Niv-Illidan")

        _G.print = savedPrint

        local store = PRT.Profiles.current.notes
        assertNotNil(store.savedNotes["Alpha"], "note must be stored")
        assertEquals(store.savedNotes["Alpha"].text, VALID_NOTE_TEXT)
        assertEquals(store.activeNote, "Alpha", "received note must be activated")
        assertTrue(frameSpy.showCount >= 1, "frame must be Shown for a received note")
    end)
end

tests["receive: unprivileged sender is ignored entirely (no store, no activate, no Show)"] = function()
    withGlobals(unprivilegedGlobals(), function()
        local frameSpy = installReceiveHarness()
        frameSpy.showCount = 0

        local encoded = encode("note", { name = "Alpha", text = VALID_NOTE_TEXT })
        Comms:Dispatch(encoded, "Randouser-Area52")

        local store = PRT.Profiles.current.notes
        assertNil(store.savedNotes["Alpha"], "unprivileged note must not be stored")
        assertNil(store.activeNote, "unprivileged note must not be activated")
        assertEquals(frameSpy.showCount, 0, "unprivileged note must never Show the frame")
    end)
end

tests["receive: privileged sender + invalid note is silently rejected (no store, no Show, no print)"] = function()
    local capturedPrint = {}
    withGlobals(RECEIVE_GLOBALS, function()
        local savedPrint = _G.print
        _G.print = function(msg) capturedPrint[#capturedPrint + 1] = msg end
        local frameSpy = installReceiveHarness()
        frameSpy.showCount = 0

        local encoded = encode("note", { name = "Alpha", text = INVALID_NOTE_TEXT })
        Comms:Dispatch(encoded, "Niv-Illidan")

        _G.print = savedPrint

        local store = PRT.Profiles.current.notes
        assertNil(store.savedNotes["Alpha"], "an invalid note must not be stored")
        assertNil(store.activeNote, "an invalid note must not be activated")
        assertEquals(frameSpy.showCount, 0, "an invalid note must never Show the frame")
        assertEquals(#capturedPrint, 0, "an invalid note must produce no chat notification")
    end)
end

tests["receive: clear from a privileged sender clears activeNote and Hides"] = function()
    withGlobals(RECEIVE_GLOBALS, function()
        local frameSpy = installReceiveHarness()

        Notes:SaveNote("Alpha", VALID_NOTE_TEXT)
        Notes:ActivateNote("Alpha")
        assertEquals(PRT.Profiles.current.notes.activeNote, "Alpha")
        frameSpy.hideCount = 0

        local encoded = encode("clear", {})
        Comms:Dispatch(encoded, "Niv-Illidan")

        assertNil(PRT.Profiles.current.notes.activeNote, "clear must deactivate")
        assertTrue(frameSpy.hideCount >= 1, "clear must Hide the frame")
    end)
end

tests["receive: clear from an unprivileged sender is ignored (no deactivate, no Hide)"] = function()
    withGlobals(unprivilegedGlobals(), function()
        local frameSpy = installReceiveHarness()

        Notes:SaveNote("Alpha", VALID_NOTE_TEXT)
        Notes:ActivateNote("Alpha")
        assertEquals(PRT.Profiles.current.notes.activeNote, "Alpha")
        frameSpy.hideCount = 0

        local encoded = encode("clear", {})
        Comms:Dispatch(encoded, "Randouser-Area52")

        assertEquals(PRT.Profiles.current.notes.activeNote, "Alpha",
            "an unprivileged clear must not deactivate")
        assertEquals(frameSpy.hideCount, 0, "an unprivileged clear must not Hide the frame")
    end)
end

return tests
