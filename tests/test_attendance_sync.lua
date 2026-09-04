-- tests/test_attendance_sync.lua
-- Exercises attendance and roster sharing (spec 2026-08-05-attendance-tracking:
-- "Sharing Attendance Records", "Roster sync", "Edge Cases -> Sync").
--
-- Every message crosses the real Comms pipeline: payloads are encoded, handed to
-- Comms:Dispatch, and replies are captured off the injected Comms.sendFunc. A
-- module that answers on a message type nothing sends, or emits a payload the
-- decoder rejects, therefore fails here rather than in a raid.
--
-- Reads and writes are separated by the fixture rather than by assertion: every
-- read-path test runs under globals that report the sender as a plain raid
-- member, so an implementation that gates reads behind the privilege check fails
-- them all. Write-path tests install leader or assistant globals explicitly.
--
-- The incoming day record shares exactly one character with the local record and
-- carries a WORSE status for it (local Absent, incoming Missing), and the
-- incoming roster re-nicknames a character the local roster already owns. A merge
-- of any kind -- union, max-status-wins, or last-writer-wins per cell -- leaves
-- traces those fixtures detect; only wholesale replacement passes.
--
-- Three tests assert that AttendanceStore and Roster THROW or misbehave on input
-- this module is required to reject. They document why each validation rule
-- exists by executing the damage rather than describing it. If either module
-- later defends its own invariants, those tests fail and the rule they justify
-- should be re-decided rather than quietly kept.

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals and module loads
--
-- LibStub and the two pure libraries reference the WoW string alias strmatch,
-- which wow_stubs.lua does not provide. Each dependency is loaded defensively so
-- this file also runs standalone, mirroring test_wiring.lua's convention; in a
-- full run this file is the first to reach Comms.lua, and test_comms.lua reloads
-- it afterwards onto a fresh handler table.
--------------------------------------------------------------------------------

if strmatch == nil then
    strmatch = string.match
end

if not PurplexityRaidTools.Comms then
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/LibSerialize/LibSerialize.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
    dofile("Comms.lua")
end

if not PurplexityRaidTools.AttendanceStore then
    dofile("Modules/Attendance/AttendanceStore.lua")
end

if not PurplexityRaidTools.Roster then
    pcall(dofile, "Modules/Attendance/RosterValidation.lua")
    dofile("Modules/Attendance/Roster.lua")
end

--- The sync module is loaded with the sibling modules and the settings reader
--- taken away, so a load-time upvalue capture of any of them takes nil, or a
--- stub that throws, along with it. Removing them again inside a test only
--- falsifies a lookup made at call time, and by then an early capture is holding
--- the real thing. Reordering these loads would not do it: in a full run the
--- earlier attendance suites have already loaded both siblings.
local hiddenDuringLoad = {
    AttendanceStore = PurplexityRaidTools.AttendanceStore,
    Roster = PurplexityRaidTools.Roster,
    AttendanceReport = PurplexityRaidTools.AttendanceReport,
    GetSetting = PurplexityRaidTools.GetSetting,
}

PurplexityRaidTools.AttendanceStore = nil
PurplexityRaidTools.Roster = nil
PurplexityRaidTools.AttendanceReport = nil
PurplexityRaidTools.GetSetting = function()
    error("the sync module must never read PRT:GetSetting, at load or at any other time", 0)
end

--- Restored before the load error is re-raised: until the module exists this
--- file is expected to fail, and a failure that left the settings reader stubbed
--- out would take every later suite in the run down with it.
local loaded, loadError = pcall(dofile, "Modules/Attendance/AttendanceSync.lua")

PurplexityRaidTools.AttendanceStore = hiddenDuringLoad.AttendanceStore
PurplexityRaidTools.Roster = hiddenDuringLoad.Roster
PurplexityRaidTools.AttendanceReport = hiddenDuringLoad.AttendanceReport
PurplexityRaidTools.GetSetting = hiddenDuringLoad.GetSetting

if not loaded then
    error(loadError, 0)
end

local PRT = PurplexityRaidTools
local Comms = PRT.Comms
local Store = PRT.AttendanceStore
local Roster = PRT.Roster
local Sync = PRT.AttendanceSync

local INVENTORY_REQUEST = "attInventoryRequest"
local INVENTORY_RESPONSE = "attInventoryResponse"
local PULL_REQUEST = "attPullRequest"
local PULL_RESPONSE = "attPullResponse"
local PULL_MISSING = "attPullMissing"
local DAY_PUSH = "attDayPush"
local ROSTER_PUSH = "attRosterPush"
local ROSTER_REQUEST = "attRosterRequest"

local SYNC_MESSAGE_TYPES = {
    INVENTORY_REQUEST, INVENTORY_RESPONSE, PULL_REQUEST, PULL_RESPONSE,
    PULL_MISSING, DAY_PUSH, ROSTER_PUSH, ROSTER_REQUEST,
}

--- Captured before any test runs so the load-contract test can prove the module
--- registered nothing on the way in.
local handlerTypesAtLoad = {}
for msgType in pairs(Comms.handlers) do
    handlerTypesAtLoad[msgType] = true
end

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local MISSING, ABSENT, LATE, PRESENT, STANDBY = 0, 1, 2, 3, 4

local AUG_05 = "2026-08-05"
local AUG_03 = "2026-08-03"
local JUL_31 = "2026-07-31"
local JUL_29 = "2026-07-29"

local AUGUST_5_2026_AT_2000 = 1785888000 + 20 * 3600
local THIRTY_DAYS = 30 * 86400

local OMNIVICENT = "Omnivicent-Proudmoore"
local NIVEN = "Niven-Proudmoore"
local ELSIE = "Elsie-Proudmoore"
local GRIMGRACE = "Grimgrace-Proudmoore"
local RANDOPUG = "Randopug-Stormrage"
local ZULJIN = "Zuljin-Stormrage"

local LEADER = "Omnivicent-Proudmoore"
local ASSISTANT = "Grimgrace-Proudmoore"
local PLAIN_MEMBER = "Randopug-Stormrage"
local OTHER_MEMBER = "Sasjah-Stormrage"

local DISCIPLINE = 256

--- Record counts of 2, 1 and 4 are distinct from each other and from the number
--- of days, so an inventory that reports the wrong day's count, the day count, or
--- a table length (# over a string-keyed record is 0) cannot pass by coincidence.
local function localDatabase()
    return {
        [AUG_05] = { [ELSIE] = PRESENT, [NIVEN] = ABSENT },
        [AUG_03] = { [ELSIE] = PRESENT },
        [JUL_31] = {
            [ELSIE] = LATE,
            [NIVEN] = PRESENT,
            [ZULJIN] = MISSING,
            [GRIMGRACE] = PRESENT,
        },
    }
end

--- Three records against the local day's two, overlapping only on Niven and
--- LOWERING that status from Absent to Missing. A union keeps Elsie, a
--- max-status merge keeps Niven at Absent, and either is visible.
local function incomingRecord()
    return { [NIVEN] = MISSING, [ZULJIN] = PRESENT, [RANDOPUG] = LATE }
end

local function rosterEntry(nickname, ...)
    local characters = { ... }
    local characterData = {}
    for _, character in ipairs(characters) do
        characterData[character] = {
            class = "PRIEST",
            mainSpec = DISCIPLINE,
            offSpecs = {},
        }
    end
    return { nickname = nickname, characters = characters, characterData = characterData }
end

local function localRoster()
    return { rosterEntry("Tempest", ELSIE), rosterEntry("Hurricane", OMNIVICENT, NIVEN) }
end

--- Three entries against the local two, and Elsie arrives under a different
--- nickname than the local roster files her under. Merging the two rosters would
--- own Elsie twice, which the roster's own save validation forbids.
---
--- Officers arrange the roster themselves and the grid presents that
--- arrangement, so entry order is data. Neither roster is in alphabetical or
--- reverse-alphabetical nickname order, and neither is ordered by character
--- count, so a sync that sorted on the way through could not reproduce either.
local function incomingRoster()
    return {
        rosterEntry("Cinder", GRIMGRACE),
        rosterEntry("Squall", RANDOPUG, ZULJIN),
        rosterEntry("Ember", ELSIE),
    }
end

local GROUP_GLOBALS = {
    IsInRaid = function() return true end,
    IsInGroup = function() return true end,
}

local LEADER_GLOBALS = {
    IsInRaid = function() return true end,
    IsInGroup = function() return true end,
    UnitIsGroupLeader = function() return true end,
    UnitIsGroupAssistant = function() return false end,
}

local ASSISTANT_GLOBALS = {
    IsInRaid = function() return true end,
    IsInGroup = function() return true end,
    UnitIsGroupLeader = function() return false end,
    UnitIsGroupAssistant = function() return true end,
}

local UNPRIVILEGED_GLOBALS = {
    IsInRaid = function() return true end,
    IsInGroup = function() return true end,
    UnitIsGroupLeader = function() return false end,
    UnitIsGroupAssistant = function() return false end,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function withGlobals(overrides, body)
    local saved = {}
    for key, value in pairs(overrides) do
        saved[key] = _G[key]
        _G[key] = value
    end
    local ok, err = pcall(body)
    for key in pairs(overrides) do
        _G[key] = saved[key]
    end
    if not ok then
        error(err, 0)
    end
end

local function withDatabases(attendance, roster, body)
    local savedAttendance = rawget(_G, "PurplexityRaidToolsAttendanceDB")
    local savedRoster = rawget(_G, "PurplexityRaidToolsRosterDB")

    _G.PurplexityRaidToolsAttendanceDB = attendance
    _G.PurplexityRaidToolsRosterDB = roster

    local ok, err = pcall(body)

    _G.PurplexityRaidToolsAttendanceDB = savedAttendance
    _G.PurplexityRaidToolsRosterDB = savedRoster

    if not ok then
        error(err, 0)
    end
end

--- The store reads its clock through realm CalendarTime APIs. They are installed
--- only here so suites loaded afterward retain their own guarded fixtures.
local function atServerTime(timestamp, body)
    local savedDateAndTime = rawget(_G, "C_DateAndTime")

    local function calendarTimeAt(value)
        local result = os.date("!*t", value)
        return {
            year = result.year,
            month = result.month,
            monthDay = result.day,
            weekday = result.wday,
            hour = result.hour,
            minute = result.min,
        }
    end

    _G.C_DateAndTime = {
        GetCurrentCalendarTime = function()
            return calendarTimeAt(timestamp)
        end,
        AdjustTimeByDays = function(_, days)
            return calendarTimeAt(timestamp + days * 86400)
        end,
    }

    local ok, err = pcall(body)

    _G.C_DateAndTime = savedDateAndTime

    if not ok then
        error(err, 0)
    end
end

--- Class sources persist on the module across test files; clearing them keeps
--- class resolution out of the sync tests entirely.
local function withoutClassSources(body)
    local savedGroup, savedGuild = Roster.groupSource, Roster.guildSource
    Roster.groupSource, Roster.guildSource = nil, nil
    local ok, err = pcall(body)
    Roster.groupSource, Roster.guildSource = savedGroup, savedGuild
    if not ok then
        error(err, 0)
    end
end

local function withCapturedSends(body)
    local sent = {}
    local savedSend = Comms.sendFunc

    Comms.sendFunc = function(encoded, channel, target)
        local ok, decoded = Comms:Decode(encoded)
        if not ok then
            error("the sync module emitted a payload Comms cannot decode", 0)
        end
        sent[#sent + 1] = {
            type = decoded.type,
            data = decoded.data,
            channel = channel,
            target = target,
            encoded = encoded,
        }
    end

    local ok, err = pcall(body, sent)
    Comms.sendFunc = savedSend

    if not ok then
        error(err, 0)
    end
    return sent
end

local function withCapturedPrint(body)
    local messages = {}
    local savedPrint = _G.print

    _G.print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do
            parts[index] = tostring((select(index, ...)))
        end
        messages[#messages + 1] = table.concat(parts, " ")
    end

    local ok, err = pcall(body)
    _G.print = savedPrint

    if not ok then
        error(err, 0)
    end
    return messages
end

local function dispatch(msgType, data, sender)
    Comms:Dispatch(Comms:Encode({ type = msgType, data = data }), sender)
end

--- Registration is an explicit call rather than a load side effect, so every
--- test has to make it, and none may inherit the last one's pending or cache.
local function freshSync()
    Sync:RegisterHandlers()
    Sync:DeclinePendingDay()
    Sync:DeclinePendingRoster()
    Sync.confirmBeforeSyncing = nil
    wipe(Sync:GetInventory())
end

local function sentOfType(sent, msgType)
    for _, message in ipairs(sent) do
        if message.type == msgType then
            return message
        end
    end
    return nil
end

--- Serves the tests that assert what the module never reaches for, which are
--- only as good as the surface they cover.
local function exerciseEveryEntryPoint()
    Sync:RequestInventory()
    Sync:RequestDay(PLAIN_MEMBER, AUG_05)
    Sync:PushDay(AUG_05)
    Sync:PushRoster()
    Sync:OnReadyCheck(LEADER, true)
    Sync:OnReadyCheck(LEADER, false)
    Sync:GetInventory()

    dispatch(INVENTORY_REQUEST, {}, PLAIN_MEMBER)
    dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 2 } }, PLAIN_MEMBER)
    dispatch(PULL_REQUEST, { day = AUG_05 }, PLAIN_MEMBER)
    dispatch(PULL_MISSING, { day = AUG_05 }, PLAIN_MEMBER)
    dispatch(ROSTER_REQUEST, {}, PLAIN_MEMBER)
    dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, LEADER)

    Sync:GetPendingDay()
    Sync:AcceptPendingDay()
    Sync:DeclinePendingDay()

    dispatch(DAY_PUSH, { day = AUG_03, records = incomingRecord() }, LEADER)
    Sync:DeclinePendingDay()

    dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
    Sync:GetPendingRoster()
    Sync:AcceptPendingRoster()
    Sync:DeclinePendingRoster()
end

--------------------------------------------------------------------------------
-- Load contract
--------------------------------------------------------------------------------

tests["the sync module loads headless with no frame or timer API available"] = function()
    assertNil(rawget(_G, "CreateFrame"),
        "wow_stubs must not provide CreateFrame, so a frame dependency fails loudly")
    assertNil(rawget(_G, "C_Timer"),
        "wow_stubs must not provide C_Timer, so a timer dependency fails loudly")
    assertNotNil(Sync, "PurplexityRaidTools.AttendanceSync must exist after load")
end

tests["loading the module registers no comms handlers of its own"] = function()
    for _, msgType in ipairs(SYNC_MESSAGE_TYPES) do
        assertNil(handlerTypesAtLoad[msgType],
            msgType .. " must be registered by RegisterHandlers, never as a load side effect")
    end
end

tests["registering the sync handlers leaves another module's handlers alone"] = function()
    local foreignCalls = 0
    Comms:RegisterHandler("noteBroadcastFixture", function()
        foreignCalls = foreignCalls + 1
    end)

    Sync:RegisterHandlers()
    Sync:RegisterHandlers()
    dispatch("noteBroadcastFixture", {}, LEADER)

    Comms.handlers["noteBroadcastFixture"] = nil
    assertEquals(foreignCalls, 1,
        "registration must add handlers rather than replace the shared handler table")
end

tests["no sync operation reads addon settings"] = function()
    local savedGetSetting = PRT.GetSetting
    PRT.GetSetting = function()
        error("the sync module must take settings as parameters or injected fields, "
            .. "never read PRT:GetSetting", 0)
    end

    local ok, err = pcall(function()
        withDatabases(localDatabase(), localRoster(), function()
            freshSync()
            withCapturedSends(function()
                withGlobals(LEADER_GLOBALS, exerciseEveryEntryPoint)
            end)
        end)
    end)

    PRT.GetSetting = savedGetSetting
    assertTrue(ok, tostring(err))
end

tests["no sync operation reaches for the store, roster or report modules"] = function()
    local saved = { PRT.AttendanceStore, PRT.Roster, PRT.AttendanceReport }
    PRT.AttendanceStore, PRT.Roster, PRT.AttendanceReport = nil, nil, nil

    local ok, err = pcall(function()
        withDatabases(localDatabase(), localRoster(), function()
            freshSync()
            withCapturedSends(function()
                withGlobals(LEADER_GLOBALS, exerciseEveryEntryPoint)
            end)
        end)
    end)

    PRT.AttendanceStore, PRT.Roster, PRT.AttendanceReport = saved[1], saved[2], saved[3]
    assertTrue(ok, tostring(err))
end

--------------------------------------------------------------------------------
-- Incoming attendance push: privilege gate and the pending replacement
--------------------------------------------------------------------------------

tests["a push from the raid leader pends a replacement carrying the sender and both counts"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        local pending = Sync:GetPendingDay()
        assertNotNil(pending, "a privileged push must offer a replacement")
        assertEquals(pending.sender, LEADER, "the modal names whose copy is on offer")
        assertEquals(pending.day, AUG_05)
        assertEquals(pending.localCount, 2, "the receiver's own record count for that day")
        assertEquals(pending.incomingCount, 3, "the count of the records actually offered")
    end)

    assertTableEquals(db, before, "an unaccepted push must not touch the database")
end

tests["a push from a raid assistant pends a replacement"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(ASSISTANT_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, ASSISTANT)
        end)

        local pending = Sync:GetPendingDay()
        assertNotNil(pending, "assistants push on the same footing as the leader")
        assertEquals(pending.sender, ASSISTANT)
    end)
end

tests["a push from an unprivileged sender is ignored without a pending, a change or a reply"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        local sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
            end)
        end)

        assertNil(Sync:GetPendingDay(), "an unprivileged push must not reach the officer at all")
        assertEquals(#sent, 0, "an ignored push is answered with silence, not a refusal")
    end)

    assertTableEquals(db, before)
end

tests["the push handler asks Comms about the raw sender rather than repeating the leader check"] = function()
    local askedAbout = {}
    local savedCheck = Comms.IsSenderPrivileged
    Comms.IsSenderPrivileged = function(_, sender)
        askedAbout[#askedAbout + 1] = sender
        return true
    end

    local ok, err = pcall(function()
        withDatabases(localDatabase(), {}, function()
            freshSync()
            withGlobals({
                IsInRaid = function() error("the privilege gate lives in Comms, not here", 0) end,
                IsInGroup = function() error("the privilege gate lives in Comms, not here", 0) end,
                UnitIsGroupLeader = function() error("the privilege gate lives in Comms, not here", 0) end,
                UnitIsGroupAssistant = function() error("the privilege gate lives in Comms, not here", 0) end,
            }, function()
                dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
            end)
        end)
    end)

    Comms.IsSenderPrivileged = savedCheck
    assertTrue(ok, tostring(err))
    assertTableEquals(askedAbout, { LEADER },
        "the unambiguated sender goes to Comms:IsSenderPrivileged exactly once")
end

--------------------------------------------------------------------------------
-- Accepting and declining an attendance replacement
--------------------------------------------------------------------------------

tests["accepting a pending replacement swaps the day wholesale rather than merging"] = function()
    local db = localDatabase()

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        assertTrue(Sync:AcceptPendingDay(), "accepting an offered replacement must report success")

        assertTableEquals(db[AUG_05], {
            [NIVEN] = { status = MISSING },
            [ZULJIN] = { status = PRESENT },
            [RANDOPUG] = { status = LATE },
        }, "the incoming record replaces the local one entirely: Elsie is gone and Niven drops to Missing")
        assertNil(Sync:GetPendingDay(), "an accepted replacement is no longer pending")
    end)
end

tests["accepting a pending replacement preserves Standby"] = function()
    local db = localDatabase()

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = { [ELSIE] = STANDBY } }, LEADER)
        end)

        assertTrue(Sync:AcceptPendingDay())
        assertTableEquals(db[AUG_05][ELSIE], { status = STANDBY })
    end)
end

tests["accepting a pending replacement preserves recorded item levels"] = function()
    local db = localDatabase()
    local incoming = {
        [ELSIE] = { status = PRESENT, itemLevel = 712.5 },
        [NIVEN] = { status = LATE },
    }

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incoming }, LEADER)
        end)

        assertTrue(Sync:AcceptPendingDay())
        assertTableEquals(db[AUG_05], incoming)
    end)
end

tests["accepting a replacement leaves every other day deep-equal"] = function()
    local db = localDatabase()
    local untouched = {
        [AUG_03] = CopyTable(db[AUG_03]),
        [JUL_31] = CopyTable(db[JUL_31]),
    }

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)
        Sync:AcceptPendingDay()
    end)

    assertTableEquals(db[AUG_03], untouched[AUG_03])
    assertTableEquals(db[JUL_31], untouched[JUL_31])
end

tests["declining a pending replacement leaves the local record untouched"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        Sync:DeclinePendingDay()
        assertNil(Sync:GetPendingDay(), "a declined replacement is no longer pending")
    end)

    assertTableEquals(db, before, "declining is not a partial accept")
end

tests["a second push replaces the offer, and accepting applies the newer one"] = function()
    local db = localDatabase()
    local second = { [OMNIVICENT] = { status = PRESENT } }

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
            dispatch(DAY_PUSH, { day = AUG_05, records = second }, ASSISTANT)
        end)

        local pending = Sync:GetPendingDay()
        assertEquals(pending.sender, ASSISTANT, "the offer on the table is the most recent one")
        assertEquals(pending.incomingCount, 1)

        Sync:AcceptPendingDay()
        assertTableEquals(db[AUG_05], second,
            "competing versions are not reconciled; the accepted one is what the receiver keeps")
    end)
end

tests["accepting with nothing pending reports failure and changes nothing"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        assertFalse(Sync:AcceptPendingDay())
        assertFalse(Sync:AcceptPendingRoster())
    end)

    assertTableEquals(db, before)
end

tests["declining with nothing pending is a no-op"] = function()
    withDatabases(localDatabase(), localRoster(), function()
        freshSync()
        Sync:DeclinePendingDay()
        Sync:DeclinePendingRoster()
        assertNil(Sync:GetPendingDay())
        assertNil(Sync:GetPendingRoster())
    end)
end

tests["accepting a replacement for a day with no local record creates it, ready for manual edits"] = function()
    local db = localDatabase()

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = JUL_29, records = incomingRecord() }, LEADER)
        end)

        local pending = Sync:GetPendingDay()
        assertEquals(pending.localCount, 0, "the receiver's side of the modal reads zero records")

        Sync:AcceptPendingDay()
        assertTableEquals(db[JUL_29], {
            [NIVEN] = { status = MISSING },
            [ZULJIN] = { status = PRESENT },
            [RANDOPUG] = { status = LATE },
        }, "accepting creates the day locally")

        local ok, err = Store:SetStatus(JUL_29, OMNIVICENT, ABSENT)
        assertTrue(ok, "a synced day behaves like any recorded day: " .. tostring(err))
        assertTableEquals(db[JUL_29][OMNIVICENT], { status = ABSENT })
    end)
end

tests["accepting a replacement creates the attendance SavedVariable when it is nil"] = function()
    withDatabases(nil, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)
        Sync:AcceptPendingDay()

        local created = rawget(_G, "PurplexityRaidToolsAttendanceDB")
        assertNotNil(created, "a fresh install has no database until something writes one")
        assertTableEquals(created[AUG_05], {
            [NIVEN] = { status = MISSING },
            [ZULJIN] = { status = PRESENT },
            [RANDOPUG] = { status = LATE },
        })
    end)
end

--------------------------------------------------------------------------------
-- Inventory
--------------------------------------------------------------------------------

tests["invoking the inventory routine broadcasts a request to the raid"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            Sync:RequestInventory()
        end)
    end)

    assertEquals(#sent, 1, "one request goes out per invocation")
    assertEquals(sent[1].type, INVENTORY_REQUEST)
    assertEquals(sent[1].channel, "RAID", "the inventory question is asked of everyone at once")
    assertNil(sent[1].target, "a broadcast is not addressed to anyone in particular")
end

tests["Refresh asks the raid again rather than reusing the last round"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            Sync:RequestInventory()
            Sync:RequestInventory()
        end)
    end)

    assertEquals(#sent, 2,
        "opening the list asks and the Refresh control asks again; holdings change mid-raid")
    assertEquals(sent[2].type, INVENTORY_REQUEST)
    assertEquals(sent[2].channel, "RAID")
end

tests["an inventory request from a plain raid member is answered with every local day and count"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(INVENTORY_REQUEST, {}, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "reads are open: every addon user answers an inventory request")
    assertEquals(sent[1].type, INVENTORY_RESPONSE)
    assertEquals(sent[1].channel, "WHISPER", "the answer goes back to whoever asked")
    assertEquals(sent[1].target, PLAIN_MEMBER)
    assertTableEquals(sent[1].data.days, { [AUG_05] = 2, [AUG_03] = 1, [JUL_31] = 4 })
end

tests["an inventory request against an empty database is still answered"] = function()
    local sent
    withDatabases({}, {}, function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(INVENTORY_REQUEST, {}, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "silence is indistinguishable from an addon-less client")
    assertTableEquals(sent[1].data.days, {})
end

tests["an inventory request against a nil database is answered without throwing"] = function()
    local sent
    withDatabases(nil, nil, function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(INVENTORY_REQUEST, {}, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "a member who has never recorded a pull still answers")
    assertTableEquals(sent[1].data.days, {})
end

tests["an incoming inventory response replaces that sender's cache and no one else's"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5, [AUG_03] = 6 } }, PLAIN_MEMBER)
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 9 } }, OTHER_MEMBER)
            dispatch(INVENTORY_RESPONSE, { days = { [JUL_31] = 1 } }, PLAIN_MEMBER)
        end)

        local inventory = Sync:GetInventory()
        assertTableEquals(inventory[PLAIN_MEMBER], { [JUL_31] = 1 },
            "a fresh response is the sender's whole inventory, not an addition to it")
        assertTableEquals(inventory[OTHER_MEMBER], { [AUG_05] = 9 },
            "one member's response says nothing about another's holdings")
    end)
end

tests["the inventory getter hands back the live cache rather than a snapshot"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        local inventory = Sync:GetInventory()

        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
        end)

        assertTableEquals(inventory[PLAIN_MEMBER], { [AUG_05] = 5 },
            "the view holds this table across refreshes and must see responses land in it")
    end)
end

--------------------------------------------------------------------------------
-- Pulling a day
--------------------------------------------------------------------------------

tests["requesting a pull whispers the day to the chosen member"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            Sync:RequestDay(PLAIN_MEMBER, JUL_31)
        end)
    end)

    assertEquals(#sent, 1)
    assertEquals(sent[1].type, PULL_REQUEST)
    assertEquals(sent[1].channel, "WHISPER", "a pull asks one member, not the raid")
    assertEquals(sent[1].target, PLAIN_MEMBER)
    assertEquals(sent[1].data.day, JUL_31)
    assertNil(Sync:GetPendingDay(),
        "asking is not receiving; nothing is on offer until an answer arrives")
end

tests["a pull whose target never answers leaves no pending and no trace"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        withCapturedSends(function()
            Sync:RequestDay(PLAIN_MEMBER, JUL_31)
            Sync:RequestDay(PLAIN_MEMBER, JUL_29)
        end)

        assertNil(Sync:GetPendingDay(),
            "a target who logs off before answering leaves no timeout and no error state")
        assertNil(Sync:GetPendingRoster())
    end)

    assertTableEquals(db, before,
        "the officer simply pulls again from someone else, with their record intact")
end

tests["a pull request from a plain raid member is answered with the day's records"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(PULL_REQUEST, { day = JUL_31 }, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "reads are open: any addon user's client answers a pull request")
    assertEquals(sent[1].type, PULL_RESPONSE)
    assertEquals(sent[1].channel, "WHISPER")
    assertEquals(sent[1].target, PLAIN_MEMBER)
    assertEquals(sent[1].data.day, JUL_31)
    assertTableEquals(sent[1].data.records, localDatabase()[JUL_31])
end

tests["a pull request for a day deleted since the inventory is answered as missing"] = function()
    local db = localDatabase()
    local before = CopyTable(db)
    local sent

    withDatabases(db, {}, function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(PULL_REQUEST, { day = JUL_29 }, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "the requester learns the record is gone rather than waiting forever")
    assertEquals(sent[1].type, PULL_MISSING)
    assertEquals(sent[1].target, PLAIN_MEMBER)
    assertEquals(sent[1].data.day, JUL_29)
    assertTableEquals(db, before)
end

tests["a pulled record pends exactly the replacement a push does"] = function()
    local pushed, pulled

    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
            pushed = CopyTable(Sync:GetPendingDay())
            Sync:DeclinePendingDay()

            dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, LEADER)
            pulled = CopyTable(Sync:GetPendingDay())
        end)
    end)

    assertNotNil(pulled, "a pulled record must reach the same confirmation the push does")
    assertTableEquals(pulled, pushed,
        "pull and push differ in how the record was asked for, not in what is offered")
end

tests["a pulled record pends even from an unprivileged sender, unlike a push"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
        end)

        local pending = Sync:GetPendingDay()
        assertNotNil(pending,
            "the officer chose this member to pull from, so their answer is expected")
        assertEquals(pending.sender, PLAIN_MEMBER)
    end)
end

tests["a pull response arriving thirty days later still pends a replacement"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        atServerTime(AUGUST_5_2026_AT_2000, function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                Sync:RequestDay(PLAIN_MEMBER, AUG_05)
            end)
        end)

        atServerTime(AUGUST_5_2026_AT_2000 + THIRTY_DAYS, function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
            end)
        end)

        assertNotNil(Sync:GetPendingDay(),
            "there is no timeout and no error state; a late answer is handled normally")
    end)
end

tests["the pull path consults no clock, so no request can grow stale"] = function()
    local function refuse()
        error("a pull that reads a clock has invented the timeout the spec rules out", 0)
    end

    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals({
            date = refuse,
            time = refuse,
            GetTime = refuse,
            GetServerTime = refuse,
            C_DateAndTime = {
                GetCurrentCalendarTime = refuse,
                AdjustTimeByDays = refuse,
            },
        }, function()
            withCapturedSends(function()
                withGlobals(UNPRIVILEGED_GLOBALS, function()
                    Sync:RequestDay(PLAIN_MEMBER, AUG_05)
                    dispatch(PULL_REQUEST, { day = AUG_05 }, PLAIN_MEMBER)
                    dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
                end)
            end)
        end)

        assertNotNil(Sync:GetPendingDay())
    end)
end

tests["a missing-record answer drops that inventory entry and leaves the records alone"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        local messages = withCapturedPrint(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(INVENTORY_RESPONSE,
                    { days = { [AUG_05] = 5, [JUL_29] = 7 } }, PLAIN_MEMBER)
                dispatch(INVENTORY_RESPONSE, { days = { [JUL_29] = 7 } }, OTHER_MEMBER)
                dispatch(PULL_MISSING, { day = JUL_29 }, PLAIN_MEMBER)
            end)
        end)

        local inventory = Sync:GetInventory()
        assertTableEquals(inventory[PLAIN_MEMBER], { [AUG_05] = 5 },
            "the day they no longer hold stops being offered for pull")
        assertTableEquals(inventory[OTHER_MEMBER], { [JUL_29] = 7 },
            "another member's copy of that day is still pullable")
        assertNil(Sync:GetPendingDay(), "nothing arrived, so nothing is on offer")

        assertEquals(#messages, 1, "the officer is told the pull found nothing")
        assertNotNil(messages[1]:find(JUL_29, 1, true), "the notice names the day that is gone")
        assertNotNil(messages[1]:find(PLAIN_MEMBER, 1, true), "and who no longer holds it")
    end)

    assertTableEquals(db, before, "a failed pull never touches the local record")
end

--------------------------------------------------------------------------------
-- Sending a day and the local roster
--
-- Nothing here gates PushDay or PushRoster on the sender's own privilege, which
-- is the plan's division of labour rather than an omission: the Sync Roster
-- button is leader-and-assist-only in the Phase 5 UI, and receivers ignore an
-- unprivileged push regardless of what the sender's client chose to emit.
--------------------------------------------------------------------------------

tests["pushing a day broadcasts the local record for it"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            assertTrue(Sync:PushDay(JUL_31))
        end)
    end)

    assertEquals(#sent, 1)
    assertEquals(sent[1].type, DAY_PUSH)
    assertEquals(sent[1].channel, "RAID")
    assertEquals(sent[1].data.day, JUL_31)
    assertTableEquals(sent[1].data.records, localDatabase()[JUL_31])
end

tests["pushing a day with no local record emits nothing"] = function()
    local sent
    withDatabases(localDatabase(), {}, function()
        freshSync()
        sent = withCapturedSends(function()
            assertFalse(Sync:PushDay(JUL_29), "there is nothing local to offer")
        end)
    end)

    assertEquals(#sent, 0)
end

tests["pushing the roster broadcasts the local entries"] = function()
    local sent
    withDatabases({}, localRoster(), function()
        freshSync()
        sent = withCapturedSends(function()
            Sync:PushRoster()
        end)
    end)

    assertEquals(#sent, 1)
    assertEquals(sent[1].type, ROSTER_PUSH)
    assertEquals(sent[1].channel, "RAID")
    assertTableEquals(sent[1].data.entries, localRoster())
end

--------------------------------------------------------------------------------
-- Roster sync: confirmation setting and the privilege gate
--------------------------------------------------------------------------------

tests["a roster push with confirmation enabled pends a replacement and changes nothing"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        local pending = Sync:GetPendingRoster()
        assertNotNil(pending, "confirmation means the officer decides")
        assertEquals(pending.sender, LEADER)
        assertEquals(pending.localCount, 2, "the officer's own entry count")
        assertEquals(pending.incomingCount, 3)
    end)

    assertTableEquals(roster, before, "the roster is unchanged until the officer accepts")
end

tests["accepting a pending roster replacement refills the SavedVariable in place"] = function()
    local roster = localRoster()

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        assertTrue(Sync:AcceptPendingRoster())
        assertTrue(rawget(_G, "PurplexityRaidToolsRosterDB") == roster,
            "Roster:GetEntries hands out the live table, so replacing it strands cached references")
        assertTableEquals(roster, incomingRoster(),
            "the incoming roster replaces the local one entirely; Hurricane and Tempest are gone")
        assertNil(Sync:GetPendingRoster())
    end)
end

tests["declining a pending roster replacement leaves the roster untouched"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        Sync:DeclinePendingRoster()
        assertNil(Sync:GetPendingRoster())
    end)

    assertTableEquals(roster, before)
end

tests["a roster push with confirmation disabled replaces the roster immediately"] = function()
    local roster = localRoster()

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        assertNil(Sync:GetPendingRoster(),
            "disabling confirmation is consenting in advance, so nothing waits on the officer")
        assertTableEquals(roster, incomingRoster())
    end)
end

tests["an unconfigured confirmation setting is treated as enabled"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        assertNil(Sync.confirmBeforeSyncing, "the fixture leaves the setting unset on purpose")
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        assertNotNil(Sync:GetPendingRoster(),
            "the spec's default is on; an unset field must not silently overwrite the roster")
    end)

    assertTableEquals(roster, before)
end

tests["a roster push from an unprivileged sender is ignored even with confirmation disabled"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        local sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(ROSTER_PUSH, { entries = incomingRoster() }, PLAIN_MEMBER)
            end)
        end)

        assertNil(Sync:GetPendingRoster(), "receivers ignore roster pushes from anyone else")
        assertEquals(#sent, 0)
    end)

    assertTableEquals(roster, before,
        "the privilege gate is checked before the confirmation setting, not after")
end

tests["accepting a roster replacement creates the roster SavedVariable when it is nil"] = function()
    withDatabases({}, nil, function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        assertEquals(Sync:GetPendingRoster().localCount, 0)
        Sync:AcceptPendingRoster()

        local created = rawget(_G, "PurplexityRaidToolsRosterDB")
        assertNotNil(created, "a fresh install has no roster until something writes one")
        assertTableEquals(created, incomingRoster())
    end)
end

tests["an accepted roster leaves every roster operation working"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)

        withoutClassSources(function()
            assertEquals(#Roster:GetEntries(), 3)
            assertEquals(Roster:GetCharacterClass(GRIMGRACE), "PRIEST")
            assertTrue(Roster:AddEntry("Gale", { OMNIVICENT }),
                "a synced roster must accept new entries like a hand-built one")

            local ok, err = Roster:AddEntry("Squall", { NIVEN })
            assertFalse(ok, "and must still enforce unique nicknames")
            assertEquals(type(err), "string")
        end)
    end)
end

tests["a day replacement and a roster replacement can be pending at the same time"] = function()
    local function offerADay()
        dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
    end
    local function offerARoster()
        dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
    end

    local orders = {
        { name = "the day arriving first", first = offerADay, second = offerARoster },
        { name = "the roster arriving first", first = offerARoster, second = offerADay },
    }

    for _, order in ipairs(orders) do
        withDatabases(localDatabase(), localRoster(), function()
            freshSync()
            Sync.confirmBeforeSyncing = true
            withGlobals(LEADER_GLOBALS, function()
                order.first()
                order.second()
            end)

            assertEquals(Sync:GetPendingDay().day, AUG_05,
                order.name .. ": the two offers are separate decisions, and neither displaces the other")
            assertEquals(Sync:GetPendingRoster().incomingCount, 3, order.name)

            Sync:AcceptPendingDay()
            assertEquals(Sync:GetPendingRoster().incomingCount, 3,
                order.name .. ": answering one offer must not discard the other")
        end)
    end
end

--------------------------------------------------------------------------------
-- Automatic roster sync from the leader
--------------------------------------------------------------------------------

tests["with automatic sync enabled the ready check requests the roster from the leader"] = function()
    local sent
    withDatabases({}, localRoster(), function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(GROUP_GLOBALS, function()
                Sync:OnReadyCheck(LEADER, true)
            end)
        end)
    end)

    assertEquals(#sent, 1)
    assertEquals(sent[1].type, ROSTER_REQUEST)
    assertEquals(sent[1].channel, "WHISPER", "only the leader is asked")
    assertEquals(sent[1].target, LEADER)
end

tests["with automatic sync disabled the ready check emits nothing"] = function()
    local sent
    withDatabases({}, localRoster(), function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(GROUP_GLOBALS, function()
                Sync:OnReadyCheck(LEADER, false)
            end)
        end)
    end)

    assertEquals(#sent, 0, "the setting is off by default and off means silent")
end

tests["with automatic sync enabled and no known leader the ready check emits nothing"] = function()
    local sent
    withDatabases({}, localRoster(), function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(GROUP_GLOBALS, function()
                Sync:OnReadyCheck(nil, true)
            end)
        end)
    end)

    assertEquals(#sent, 0, "there is nobody to address the request to")
end

tests["a roster request is answered with a roster push carrying the local entries"] = function()
    local sent
    withDatabases({}, localRoster(), function()
        freshSync()
        sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(ROSTER_REQUEST, {}, PLAIN_MEMBER)
            end)
        end)
    end)

    assertEquals(#sent, 1, "reads are open, so the roster is handed to whoever asks")
    assertEquals(sent[1].type, ROSTER_PUSH,
        "an answer travels as a push so the receiver cannot treat it more leniently")
    assertEquals(sent[1].channel, "WHISPER")
    assertEquals(sent[1].target, PLAIN_MEMBER)
    assertTableEquals(sent[1].data.entries, localRoster())
end

tests["the roster answering an auto-sync request takes the same privilege path as a push"] = function()
    local answer
    withDatabases({}, incomingRoster(), function()
        freshSync()
        local sent = withCapturedSends(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(ROSTER_REQUEST, {}, PLAIN_MEMBER)
            end)
        end)
        answer = sentOfType(sent, ROSTER_PUSH).encoded
    end)

    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            Comms:Dispatch(answer, PLAIN_MEMBER)
        end)
        assertTableEquals(roster, before,
            "an answer from an unprivileged member is ignored exactly as their push would be")

        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            Comms:Dispatch(answer, LEADER)
        end)
        assertNotNil(Sync:GetPendingRoster(),
            "and from the leader it still honours Confirm Before Syncing")
        assertTableEquals(roster, before)
    end)
end

--------------------------------------------------------------------------------
-- Validating incoming attendance records
--
-- Phase 1's store treats a day KEY's presence as the first-pull signal and
-- compares day keys as strings during expiry, and the report resolves statuses by
-- fixed priority. Nothing downstream re-checks any of that, so a record that
-- crosses the wire is checked here or never.
--------------------------------------------------------------------------------

local VALID_RECORDS = { [ELSIE] = PRESENT, [NIVEN] = LATE }

local MALFORMED_DAY_PAYLOADS = {
    { name = "a payload with no record table", payload = { day = AUG_05 } },
    { name = "a record table that is a string", payload = { day = AUG_05, records = "records" } },
    { name = "an empty record table", payload = { day = AUG_05, records = {} } },
    { name = "a payload with no day", payload = { records = VALID_RECORDS } },
    { name = "a numeric day key", payload = { day = 20260805, records = VALID_RECORDS } },
    { name = "a day key that is not a date", payload = { day = "yesterday", records = VALID_RECORDS } },
    { name = "an unpadded day key", payload = { day = "2026-8-5", records = VALID_RECORDS } },
    { name = "a day key carrying a time", payload = { day = "2026-08-05T20:00", records = VALID_RECORDS } },
    { name = "a numeric character key", payload = { day = AUG_05, records = { [1] = PRESENT } } },
    { name = "an empty character key", payload = { day = AUG_05, records = { [""] = PRESENT } } },
    { name = "a status above the enum", payload = { day = AUG_05, records = { [ELSIE] = 5 } } },
    { name = "a negative status", payload = { day = AUG_05, records = { [ELSIE] = -1 } } },
    { name = "a fractional status", payload = { day = AUG_05, records = { [ELSIE] = 1.5 } } },
    { name = "a status written as a string", payload = { day = AUG_05, records = { [ELSIE] = "3" } } },
    { name = "a boolean status", payload = { day = AUG_05, records = { [ELSIE] = true } } },
    { name = "a table status", payload = { day = AUG_05, records = { [ELSIE] = {} } } },
    {
        name = "an unavailable item level",
        payload = { day = AUG_05, records = { [ELSIE] = { status = PRESENT, itemLevel = 0 } } },
    },
    {
        name = "an unknown record field",
        payload = { day = AUG_05, records = { [ELSIE] = { status = PRESENT, gear = 712 } } },
    },
    {
        name = "one bad status among good ones",
        payload = { day = AUG_05, records = { [ELSIE] = PRESENT, [NIVEN] = LATE, [ZULJIN] = 9 } },
    },
}

tests["a malformed incoming day record is rejected at both doors without a pending or a change"] = function()
    for _, door in ipairs({ DAY_PUSH, PULL_RESPONSE }) do
        for _, case in ipairs(MALFORMED_DAY_PAYLOADS) do
            local db = localDatabase()
            local before = CopyTable(db)

            withDatabases(db, {}, function()
                freshSync()
                local sent = withCapturedSends(function()
                    withGlobals(LEADER_GLOBALS, function()
                        dispatch(door, case.payload, LEADER)
                    end)
                end)

                assertNil(Sync:GetPendingDay(),
                    door .. " must not offer " .. case.name)
                assertEquals(#sent, 0,
                    door .. " must answer " .. case.name .. " with silence")
            end)

            assertTableEquals(db, before,
                door .. " must leave the database deep-equal given " .. case.name)
        end
    end
end

tests["a malformed record is rejected before the officer is notified of anything"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        local messages = withCapturedPrint(function()
            withGlobals(LEADER_GLOBALS, function()
                dispatch(DAY_PUSH, { day = AUG_05, records = {} }, LEADER)
            end)
        end)

        assertEquals(#messages, 0,
            "a sender pushing junk must not be able to write to the officer's chat frame")
    end)
end

--- Every other day-record case here is a rejection, so state the boundary from
--- the other side: the seam checks that a key is a usable string, never that it
--- looks like "Name-Realm". A local database can genuinely hold a bare name or a
--- trailing-hyphen "Name-" (the realm APIs return "" as readily as nil), and
--- refusing a whole raid night's record over a cosmetically odd key costs more
--- than letting one through. Only the keys that break something are blocked.
tests["a record keyed by a bare character name is accepted rather than dropped"] = function()
    local db = localDatabase()

    withDatabases(db, {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = { Elsie = PRESENT, ["Niven-"] = LATE } },
                LEADER)
        end)

        assertNotNil(Sync:GetPendingDay(), "an odd-looking name is not a malformed record")
        Sync:AcceptPendingDay()
        assertTableEquals(db[AUG_05], {
            Elsie = { status = PRESENT },
            ["Niven-"] = { status = LATE },
        })
    end)
end

tests["an empty day table would make the next pull record everyone Late, so sync rejects one"] = function()
    withDatabases({ [AUG_05] = {} }, {}, function()
        atServerTime(AUGUST_5_2026_AT_2000, function()
            Store:OnCountdownStart({ ELSIE, NIVEN }, nil, 6)
        end)

        assertEquals(Store.GetStatus(PurplexityRaidToolsAttendanceDB[AUG_05][ELSIE]), LATE,
            "the store reads the day KEY to decide a pull is the first one, not the record count")
    end)
end

tests["a non-string day key would throw during the expiry pass, so sync rejects one"] = function()
    withDatabases({ [AUG_05] = { [ELSIE] = PRESENT }, [20260805] = { [ELSIE] = PRESENT } }, {},
        function()
            atServerTime(AUGUST_5_2026_AT_2000, function()
                assertError(function()
                    Store:ExpireOldDays(90, 6)
                end, "expiry compares day keys as strings and cannot survive a numeric one")
            end)
        end)
end

--------------------------------------------------------------------------------
-- Validating incoming rosters
--
-- Roster.lua scans every entry on every save and reads characterData for every
-- listed character, so a single malformed entry takes down operations that have
-- nothing to do with it. It defends none of these invariants itself.
--------------------------------------------------------------------------------

local VALID_DATA = { [GRIMGRACE] = { class = "PRIEST", mainSpec = DISCIPLINE, offSpecs = {} } }

local MALFORMED_ROSTERS = {
    { name = "an entry list that is a string", entries = "roster" },
    { name = "an entry that is a string", entries = { "Cinder" } },
    { name = "an entry that is a number", entries = { 42 } },
    {
        name = "an entry with no nickname",
        entries = { { characters = { GRIMGRACE }, characterData = VALID_DATA } },
    },
    {
        name = "an entry with an empty nickname",
        entries = { { nickname = "", characters = { GRIMGRACE }, characterData = VALID_DATA } },
    },
    {
        name = "an entry with a numeric nickname",
        entries = { { nickname = 7, characters = { GRIMGRACE }, characterData = VALID_DATA } },
    },
    {
        name = "an entry with no character list",
        entries = { { nickname = "Cinder", characterData = VALID_DATA } },
    },
    {
        name = "an entry with an empty character list",
        entries = { { nickname = "Cinder", characters = {}, characterData = VALID_DATA } },
    },
    {
        name = "an entry with a numeric character",
        entries = {
            {
                nickname = "Cinder",
                characters = { 12345 },
                characterData = { [12345] = { class = "PRIEST" } },
            },
        },
    },
    {
        name = "an entry with an empty character name",
        entries = {
            {
                nickname = "Cinder",
                characters = { "" },
                characterData = { [""] = { class = "PRIEST" } },
            },
        },
    },
    {
        name = "an entry with no character data",
        entries = { { nickname = "Cinder", characters = { GRIMGRACE } } },
    },
    {
        name = "a character with no record of its own",
        entries = { { nickname = "Cinder", characters = { GRIMGRACE, ZULJIN }, characterData = VALID_DATA } },
    },
    {
        name = "a character record that is a string",
        entries = {
            { nickname = "Cinder", characters = { GRIMGRACE }, characterData = { [GRIMGRACE] = "PRIEST" } },
        },
    },
    {
        name = "a character record with a numeric class",
        entries = {
            { nickname = "Cinder", characters = { GRIMGRACE }, characterData = { [GRIMGRACE] = { class = 5 } } },
        },
    },
    {
        name = "a character record with a string main spec",
        entries = {
            {
                nickname = "Cinder",
                characters = { GRIMGRACE },
                characterData = { [GRIMGRACE] = { class = "PRIEST", mainSpec = "Discipline" } },
            },
        },
    },
    {
        name = "a character record with a string off-spec list",
        entries = {
            {
                nickname = "Cinder",
                characters = { GRIMGRACE },
                characterData = { [GRIMGRACE] = { class = "PRIEST", offSpecs = "Holy" } },
            },
        },
    },
    {
        name = "two entries claiming the same character",
        entries = {
            { nickname = "Cinder", characters = { GRIMGRACE }, characterData = VALID_DATA },
            { nickname = "Squall", characters = { GRIMGRACE }, characterData = VALID_DATA },
        },
    },
    {
        name = "two entries sharing a nickname",
        entries = {
            { nickname = "Cinder", characters = { GRIMGRACE }, characterData = VALID_DATA },
            {
                nickname = "Cinder",
                characters = { ZULJIN },
                characterData = { [ZULJIN] = { class = "PRIEST" } },
            },
        },
    },
    {
        name = "an entry list keyed by nickname rather than ordered",
        entries = {
            Cinder = { nickname = "Cinder", characters = { GRIMGRACE }, characterData = VALID_DATA },
        },
    },
    {
        name = "one malformed entry among sound ones",
        entries = {
            { nickname = "Cinder", characters = { GRIMGRACE }, characterData = VALID_DATA },
            { nickname = "Squall", characters = { ZULJIN } },
        },
    },
}

tests["a malformed incoming roster is rejected whether or not confirmation is enabled"] = function()
    for _, confirm in ipairs({ true, false }) do
        for _, case in ipairs(MALFORMED_ROSTERS) do
            local roster = localRoster()
            local before = CopyTable(roster)

            withDatabases({}, roster, function()
                freshSync()
                Sync.confirmBeforeSyncing = confirm
                local sent = withCapturedSends(function()
                    withGlobals(LEADER_GLOBALS, function()
                        dispatch(ROSTER_PUSH, { entries = case.entries }, LEADER)
                    end)
                end)

                assertNil(Sync:GetPendingRoster(),
                    "confirm=" .. tostring(confirm) .. " must not offer " .. case.name)
                assertEquals(#sent, 0,
                    "confirm=" .. tostring(confirm) .. " must answer " .. case.name .. " with silence")
            end)

            assertTableEquals(roster, before,
                "confirm=" .. tostring(confirm) .. " must leave the roster deep-equal given " .. case.name)
        end
    end
end

tests["an incoming roster with no entries is sound and replaces the local one"] = function()
    local roster = localRoster()

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = {} }, LEADER)
        end)

        assertTableEquals(roster, {},
            "an officer with an empty roster is syncing an empty roster, not a malformed one")
    end)
end

--- Zephyra carries no realm on purpose. The roster door makes the same bargain
--- the day door does, and the stakes are higher here: one unacceptable character
--- name rejects the officer's whole roster rather than a single night.
tests["an incoming roster with no spec assignments and a realm-less character is sound"] = function()
    local roster = localRoster()
    local bare = {
        {
            nickname = "Cinder",
            characters = { GRIMGRACE, "Zephyra" },
            characterData = { [GRIMGRACE] = {}, Zephyra = {} },
        },
    }

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = bare }, LEADER)
        end)

        assertTableEquals(roster, bare,
            "an unknown class, unassigned specs and a bare name are all a fresh import looks like")
    end)
end

tests["an entry with no character list would break every later roster save, so sync rejects one"] = function()
    withDatabases({}, { { nickname = "Hurricane" } }, function()
        withoutClassSources(function()
            assertError(function()
                Roster:AddEntry("Tempest", { ELSIE })
            end, "the roster scans every entry's characters on save, however unrelated the entry is")
        end)
    end)
end

tests["a character with no record of its own would break class lookup, so sync rejects one"] = function()
    local entries = { { nickname = "Hurricane", characters = { OMNIVICENT }, characterData = {} } }

    withDatabases({}, entries, function()
        withoutClassSources(function()
            assertError(function()
                Roster:GetCharacterClass(OMNIVICENT)
            end, "the roster reads characterData for every listed character without checking it exists")
        end)
    end)
end

--------------------------------------------------------------------------------
-- Payloads on the open read paths
--
-- The two push doors are guarded by privilege, so junk arriving there comes from
-- an officer. These five types are answered for anyone, which makes their
-- payloads the least trustworthy input the module takes, and a throw inside a
-- handler surfaces as a Lua error mid-raid rather than as a dropped message.
--------------------------------------------------------------------------------

--- replies is what the door still owes its sender once the payload has failed to
--- parse: answer when there was nothing you needed to read, drop when you needed
--- to read something and could not. An inventory or roster request names nothing,
--- so junk in its payload changes no part of the answer; a pull request that
--- never names a day has no answer to give.
local MALFORMED_OPEN_PAYLOADS = {
    { name = "an inventory response with no day list", type = INVENTORY_RESPONSE, data = {}, replies = 0 },
    {
        name = "an inventory response whose day list is a string",
        type = INVENTORY_RESPONSE,
        data = { days = "2026-08-05" },
        replies = 0,
    },
    {
        name = "an inventory response carrying a string",
        type = INVENTORY_RESPONSE,
        data = "days",
        replies = 0,
    },
    { name = "a pull request with no day", type = PULL_REQUEST, data = {}, replies = 0 },
    {
        name = "a pull request with a numeric day",
        type = PULL_REQUEST,
        data = { day = 20260805 },
        replies = 0,
    },
    { name = "a pull request carrying a string", type = PULL_REQUEST, data = "day", replies = 0 },
    { name = "a missing-record answer with no day", type = PULL_MISSING, data = {}, replies = 0 },
    {
        name = "a missing-record answer carrying a string",
        type = PULL_MISSING,
        data = "day",
        replies = 0,
    },
    {
        name = "an inventory request carrying a string",
        type = INVENTORY_REQUEST,
        data = "please",
        replies = 1,
    },
    {
        name = "a roster request carrying a string",
        type = ROSTER_REQUEST,
        data = "please",
        replies = 1,
    },
}

--- Run against both a sender we hold no inventory for and one we do. The second
--- pass is not ceremony: a day key that is nil reaches `held[nil] = nil` on the
--- cached branch, and assigning to a nil key throws where reading one does not.
tests["a malformed payload on an open read path neither throws nor changes anything"] = function()
    for _, cached in ipairs({ "with no inventory cached", "with an inventory cached" }) do
        for _, case in ipairs(MALFORMED_OPEN_PAYLOADS) do
            local label = case.name .. " " .. cached
            local db, roster = localDatabase(), localRoster()
            local dbBefore, rosterBefore = CopyTable(db), CopyTable(roster)

            withDatabases(db, roster, function()
                freshSync()
                if cached == "with an inventory cached" then
                    withGlobals(UNPRIVILEGED_GLOBALS, function()
                        dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
                    end)
                end
                local heldBefore = CopyTable(Sync:GetInventory()[PLAIN_MEMBER] or {})

                local sent
                local notices = withCapturedPrint(function()
                    sent = withCapturedSends(function()
                        withGlobals(UNPRIVILEGED_GLOBALS, function()
                            dispatch(case.type, case.data, PLAIN_MEMBER)
                        end)
                    end)
                end)

                assertNil(Sync:GetPendingDay(), label .. " must offer nothing")
                assertNil(Sync:GetPendingRoster(), label .. " must offer nothing")
                assertEquals(#sent, case.replies, label .. " must emit exactly what it owes")
                assertEquals(#notices, 0, label .. " must not notify the officer")
                assertTableEquals(Sync:GetInventory()[PLAIN_MEMBER] or {}, heldBefore,
                    label .. " must leave the cached inventory as it found it")
            end)

            assertTableEquals(db, dbBefore, label .. " must leave the database deep-equal")
            assertTableEquals(roster, rosterBefore, label .. " must leave the roster deep-equal")
        end
    end
end

tests["a missing-record answer about a member never inventoried is harmless"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        withCapturedPrint(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(PULL_MISSING, { day = JUL_29 }, PLAIN_MEMBER)
            end)
        end)

        assertNil(Sync:GetInventory()[PLAIN_MEMBER],
            "a Refresh between the pull and its answer clears the cache the answer refers to")
    end)

    assertTableEquals(db, before)
end

tests["an inventory or roster request is answered whatever its payload carries"] = function()
    for _, case in ipairs({ INVENTORY_REQUEST, ROSTER_REQUEST }) do
        local sent
        withDatabases(localDatabase(), localRoster(), function()
            freshSync()
            sent = withCapturedSends(function()
                withGlobals(UNPRIVILEGED_GLOBALS, function()
                    dispatch(case, "please", PLAIN_MEMBER)
                end)
            end)
        end)

        assertEquals(#sent, 1,
            case .. " carries nothing worth validating, so it is answered regardless")
        assertEquals(sent[1].target, PLAIN_MEMBER)
    end
end

--------------------------------------------------------------------------------
-- The player's own broadcast coming back to them
--
-- A RAID message is delivered to its sender along with everyone else; Notes.lua
-- depends on exactly that, broadcasting without activating locally and letting
-- the loopback do it. Both push doors are therefore reachable by the officer's
-- own copy, and every fixture above dispatches from a name the player does not
-- answer to, so the whole class is invisible without stubbing the identity.
--------------------------------------------------------------------------------

--- Makes the local player answer to the given character's ambiguated name for
--- the duration of a nested withGlobals. Scoped rather than installed at file
--- scope: UnitName is read by suites that run after this one, and a leaked stub
--- would follow them.
local function playerIs(character)
    return {
        UnitName = function(unit)
            if unit == "player" then
                return Ambiguate(character, "short"), nil
            end
            return unit, nil
        end,
    }
end

tests["a day push the player broadcast themselves is ignored rather than offered back"] = function()
    local db = localDatabase()
    local before = CopyTable(db)

    withDatabases(db, {}, function()
        freshSync()
        local sent = withCapturedSends(function()
            withGlobals(LEADER_GLOBALS, function()
                withGlobals(playerIs(LEADER), function()
                    dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
                end)
            end)
        end)

        assertNil(Sync:GetPendingDay(),
            "the officer who pushed a day already has it; the modal would ask them to replace "
                .. "their own record with itself")
        assertEquals(#sent, 0)
    end)

    assertTableEquals(db, before)
end

tests["a roster push the player broadcast themselves raises no confirmation"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            withGlobals(playerIs(LEADER), function()
                dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
            end)
        end)

        assertNil(Sync:GetPendingRoster(),
            "pressing Sync Roster must not ask the officer to accept their own roster")
    end)

    assertTableEquals(roster, before)
end

--- The entry-identity assertion is the point of this one. With confirmation
--- disabled a self-replace is silent and lands on an equal-looking roster, so
--- deep equality alone reports success while every entry table the grid is
--- holding has been swapped for a decoded copy.
tests["a roster push the player broadcast themselves leaves the live entry tables in place"] = function()
    local roster = localRoster()
    local before = CopyTable(roster)
    local firstEntry, secondEntry = roster[1], roster[2]

    withDatabases({}, roster, function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        withGlobals(LEADER_GLOBALS, function()
            withGlobals(playerIs(LEADER), function()
                dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
            end)
        end)
    end)

    assertTableEquals(roster, before)
    assertTrue(roster[1] == firstEntry and roster[2] == secondEntry,
        "a silent self-replace strands every reference taken from Roster:GetEntries")
end

--------------------------------------------------------------------------------
-- Payloads that reach the chat frame or the pull list
--------------------------------------------------------------------------------

--- Chat escape codes are markup: a hyperlink sequence renders as a clickable
--- player link rather than as its own text.
local NON_ISO_MISSING_DAYS = {
    { name = "a day carrying chat escape codes",
        day = "|cffff0000|Hplayer:Gullible-Proudmoore|h[Click here]|h|r" },
    { name = "a day that is not a date", day = "yesterday" },
    { name = "an unpadded day", day = "2026-8-5" },
    { name = "a day carrying a time", day = "2026-08-05T20:00" },
}

tests["a missing-record answer names its day in the officer's chat, so a non-ISO day is dropped"] =
    function()
        for _, case in ipairs(NON_ISO_MISSING_DAYS) do
            local db = localDatabase()
            local before = CopyTable(db)

            withDatabases(db, {}, function()
                freshSync()
                withGlobals(UNPRIVILEGED_GLOBALS, function()
                    dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
                end)

                local messages = withCapturedPrint(function()
                    withGlobals(UNPRIVILEGED_GLOBALS, function()
                        dispatch(PULL_MISSING, { day = case.day }, PLAIN_MEMBER)
                    end)
                end)

                assertEquals(#messages, 0,
                    case.name .. " must never reach the chat frame")
                assertTableEquals(Sync:GetInventory()[PLAIN_MEMBER], { [AUG_05] = 5 },
                    case.name .. " must drop nothing from the cache")
            end)

            assertTableEquals(db, before, case.name .. " must leave the database deep-equal")
        end
    end

--- An inventory is read back as a list of days to offer for pull, with counts
--- rendered beside them. A day key that is not a date names nothing pullable,
--- and a count that is not a whole number has nothing to render.
local MALFORMED_INVENTORIES = {
    { name = "a numeric day key", days = { [20260805] = 2 } },
    { name = "a day key that is not a date", days = { yesterday = 2 } },
    { name = "a count written as a string", days = { [AUG_05] = "2" } },
    { name = "a negative count", days = { [AUG_05] = -1 } },
    { name = "a fractional count", days = { [AUG_05] = 1.5 } },
}

tests["a malformed inventory response is refused whether or not that sender is cached"] = function()
    for _, cached in ipairs({ "with no inventory cached", "with an inventory cached" }) do
        for _, case in ipairs(MALFORMED_INVENTORIES) do
            local label = case.name .. " " .. cached

            withDatabases(localDatabase(), {}, function()
                freshSync()
                if cached == "with an inventory cached" then
                    withGlobals(UNPRIVILEGED_GLOBALS, function()
                        dispatch(INVENTORY_RESPONSE, { days = { [JUL_31] = 4 } }, PLAIN_MEMBER)
                    end)
                end
                local heldBefore = CopyTable(Sync:GetInventory()[PLAIN_MEMBER] or {})

                local sent = withCapturedSends(function()
                    withGlobals(UNPRIVILEGED_GLOBALS, function()
                        dispatch(INVENTORY_RESPONSE, { days = case.days }, PLAIN_MEMBER)
                    end)
                end)

                assertTableEquals(Sync:GetInventory()[PLAIN_MEMBER] or {}, heldBefore,
                    label .. " must leave the cached inventory as it found it")
                assertEquals(#sent, 0, label .. " must be answered with silence")
            end)
        end
    end
end

tests["one unusable day in an inventory response rejects the whole response"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [JUL_31] = 4 } }, PLAIN_MEMBER)
            dispatch(INVENTORY_RESPONSE,
                { days = { [AUG_05] = 2, [AUG_03] = 1, yesterday = 7 } }, PLAIN_MEMBER)
        end)

        assertTableEquals(Sync:GetInventory()[PLAIN_MEMBER], { [JUL_31] = 4 },
            "the sound days travel with the unusable one; keeping them would offer pulls from "
                .. "an inventory the sender never sent")
    end)
end

tests["an inventory response holding no days is sound and replaces what was cached"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
            dispatch(INVENTORY_RESPONSE, { days = {} }, PLAIN_MEMBER)
        end)

        assertTableEquals(Sync:GetInventory()[PLAIN_MEMBER], {},
            "an empty list is how a member who has deleted every record says so, and it must "
                .. "clear what they previously offered")
    end)
end

--------------------------------------------------------------------------------
-- Change notifications
--
-- The pending state is created by an arriving message rather than by anything
-- the officer did, and the UI can neither poll for it nor sit in the path of
-- every addon message, so the module announces its own changes.
--
-- Listen mirrors GroupInspect:Listen and likewise has no removal, so this
-- section registers exactly ONE callback for the whole suite and reads the
-- counter it feeds. A subscriber registered inside a test would outlive it and
-- go on firing for every test that followed.
--------------------------------------------------------------------------------

local notifications = { count = 0, lastArgumentCount = nil }

Sync:Listen(function(...)
    notifications.count = notifications.count + 1
    notifications.lastArgumentCount = select("#", ...)
end)

local function notificationsDuring(body)
    notifications.count = 0
    body()
    return notifications.count
end

tests["a listener is called with no payload, so it must read the module for state"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        notifications.lastArgumentCount = nil

        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        assertEquals(notifications.lastArgumentCount, 0,
            "a payload would let a listener act on state the module had already moved past")
    end)
end

tests["a day push held for confirmation notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withGlobals(LEADER_GLOBALS, function()
                dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
            end)
        end)

        assertEquals(fired, 1, "an unannounced pending day is one the officer never sees")
    end)
end

tests["a pull response notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(PULL_RESPONSE, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
            end)
        end)

        assertEquals(fired, 1,
            "the answer to a Pull the officer just clicked is the one arrival they are waiting on")
    end)
end

tests["accepting a pending day notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        local fired = notificationsDuring(function()
            Sync:AcceptPendingDay()
        end)

        assertEquals(fired, 1, "the accepted records are now the local ones and every view is stale")
    end)
end

tests["declining a pending day notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(LEADER_GLOBALS, function()
            dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, LEADER)
        end)

        local fired = notificationsDuring(function()
            Sync:DeclinePendingDay()
        end)

        assertEquals(fired, 1, "the offer is gone, so anything still presenting it is wrong")
    end)
end

tests["declining a day with nothing pending notifies nobody"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            Sync:DeclinePendingDay()
        end)

        assertEquals(fired, 0, "nothing changed, so nothing needs redrawing")
    end)
end

tests["a roster push held for confirmation notifies listeners"] = function()
    withDatabases({}, localRoster(), function()
        withoutClassSources(function()
            freshSync()
            Sync.confirmBeforeSyncing = true

            local fired = notificationsDuring(function()
                withGlobals(LEADER_GLOBALS, function()
                    dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
                end)
            end)

            assertEquals(fired, 1)
        end)
    end)
end

--- The silent path: with confirmation off the roster is replaced outright and no
--- modal ever appears, so the notification is the only thing that can tell a
--- roster view its entries just became somebody else's.
tests["a roster push applied immediately notifies listeners"] = function()
    withDatabases({}, localRoster(), function()
        withoutClassSources(function()
            freshSync()
            Sync.confirmBeforeSyncing = false

            local fired = notificationsDuring(function()
                withGlobals(LEADER_GLOBALS, function()
                    dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
                end)
            end)

            assertEquals(fired, 1,
                "an unannounced wholesale replacement leaves the roster view showing entries "
                    .. "that are no longer in the database")
        end)
    end)
end

tests["accepting a pending roster notifies listeners"] = function()
    withDatabases({}, localRoster(), function()
        withoutClassSources(function()
            freshSync()
            Sync.confirmBeforeSyncing = true
            withGlobals(LEADER_GLOBALS, function()
                dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
            end)

            local fired = notificationsDuring(function()
                Sync:AcceptPendingRoster()
            end)

            assertEquals(fired, 1)
        end)
    end)
end

tests["declining a pending roster notifies listeners"] = function()
    withDatabases({}, localRoster(), function()
        withoutClassSources(function()
            freshSync()
            Sync.confirmBeforeSyncing = true
            withGlobals(LEADER_GLOBALS, function()
                dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
            end)

            local fired = notificationsDuring(function()
                Sync:DeclinePendingRoster()
            end)

            assertEquals(fired, 1)
        end)
    end)
end

tests["declining a roster with nothing pending notifies nobody"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()

        local fired = notificationsDuring(function()
            Sync:DeclinePendingRoster()
        end)

        assertEquals(fired, 0)
    end)
end

tests["an inventory response notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
            end)
        end)

        assertEquals(fired, 1,
            "responses arrive one per raid member, and each adds a copy the officer can pull")
    end)
end

tests["requesting the inventory notifies listeners, having just emptied it"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
        end)

        local fired = notificationsDuring(function()
            withCapturedSends(function()
                Sync:RequestInventory()
            end)
        end)

        assertEquals(fired, 1,
            "the cached copies are gone before any answer returns, and a view still offering "
                .. "them offers pulls from an inventory nobody claims")
    end)
end

tests["a pull-missing response that drops a held day notifies listeners"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()
        withGlobals(UNPRIVILEGED_GLOBALS, function()
            dispatch(INVENTORY_RESPONSE, { days = { [AUG_05] = 5 } }, PLAIN_MEMBER)
        end)

        local fired = notificationsDuring(function()
            withCapturedPrint(function()
                withGlobals(UNPRIVILEGED_GLOBALS, function()
                    dispatch(PULL_MISSING, { day = AUG_05 }, PLAIN_MEMBER)
                end)
            end)
        end)

        assertEquals(fired, 1, "that copy just stopped existing and must stop being offered")
    end)
end

tests["a pull-missing response for a day nobody offered notifies nobody"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withCapturedPrint(function()
                withGlobals(UNPRIVILEGED_GLOBALS, function()
                    dispatch(PULL_MISSING, { day = JUL_29 }, PLAIN_MEMBER)
                end)
            end)
        end)

        assertEquals(fired, 0, "no cached copy was removed, so no view changed")
    end)
end

tests["a day push from an unprivileged sender notifies nobody"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withGlobals(UNPRIVILEGED_GLOBALS, function()
                dispatch(DAY_PUSH, { day = AUG_05, records = incomingRecord() }, PLAIN_MEMBER)
            end)
        end)

        assertEquals(fired, 0,
            "a push that is ignored must not reach the officer as a prompt about nothing")
    end)
end

tests["a malformed day push notifies nobody"] = function()
    withDatabases(localDatabase(), {}, function()
        freshSync()

        local fired = notificationsDuring(function()
            withGlobals(LEADER_GLOBALS, function()
                dispatch(DAY_PUSH, { day = "yesterday", records = incomingRecord() }, LEADER)
            end)
        end)

        assertEquals(fired, 0, "rejected input creates no pending state to announce")
    end)
end

tests["a rejected roster notifies nobody"] = function()
    withDatabases({}, localRoster(), function()
        withoutClassSources(function()
            freshSync()
            Sync.confirmBeforeSyncing = true

            local fired = notificationsDuring(function()
                withGlobals(LEADER_GLOBALS, function()
                    dispatch(ROSTER_PUSH, { entries = { { nickname = "Broken" } } }, LEADER)
                end)
            end)

            assertEquals(fired, 0)
        end)
    end)
end

tests["a roster received during combat is discarded without pending state or notification"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        local before = CopyTable(PurplexityRaidToolsRosterDB)

        local fired = notificationsDuring(function()
            withGlobals(LEADER_GLOBALS, function()
                withGlobals({ InCombatLockdown = function() return true end }, function()
                    dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
                end)
            end)
        end)

        assertNil(Sync:GetPendingRoster())
        assertEquals(fired, 0)
        assertTableEquals(PurplexityRaidToolsRosterDB, before)
    end)
end

tests["a roster received during combat leaves an older pending offer unchanged"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)
        local pending = Sync:GetPendingRoster()

        withGlobals(LEADER_GLOBALS, function()
            withGlobals({ InCombatLockdown = function() return true end }, function()
                dispatch(ROSTER_PUSH, { entries = { rosterEntry("Other", NIVEN) } }, LEADER)
            end)
        end)

        assertTrue(Sync:GetPendingRoster() == pending)
    end)
end

tests["accepting a pending roster during combat preserves both roster and offer"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()
        Sync.confirmBeforeSyncing = true
        withGlobals(LEADER_GLOBALS, function()
            dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
        end)
        local pending = Sync:GetPendingRoster()
        local before = CopyTable(PurplexityRaidToolsRosterDB)

        withGlobals({ InCombatLockdown = function() return true end }, function()
            assertFalse(Sync:AcceptPendingRoster())
        end)

        assertTrue(Sync:GetPendingRoster() == pending)
        assertTableEquals(PurplexityRaidToolsRosterDB, before)
    end)
end

tests["combat ending does not apply a discarded roster or notify a deferred refresh"] = function()
    withDatabases({}, localRoster(), function()
        freshSync()
        Sync.confirmBeforeSyncing = false
        local before = CopyTable(PurplexityRaidToolsRosterDB)

        local fired = notificationsDuring(function()
            withGlobals(LEADER_GLOBALS, function()
                withGlobals({ InCombatLockdown = function() return true end }, function()
                    dispatch(ROSTER_PUSH, { entries = incomingRoster() }, LEADER)
                end)
                withGlobals({ InCombatLockdown = function() return false end }, function() end)
            end)
        end)

        assertNil(Sync:GetPendingRoster())
        assertEquals(fired, 0)
        assertTableEquals(PurplexityRaidToolsRosterDB, before)
    end)
end

return tests
