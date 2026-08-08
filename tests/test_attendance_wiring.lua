-- tests/test_attendance_wiring.lua
-- Exercises the wiring layer (spec 2026-08-05-attendance-tracking: "Automatic
-- Recording", "Expiration", "Roster sync"), which is the only file in the feature
-- permitted to read PRT:GetSetting and the only consumer of GroupInspect.members.
--
-- Frames are absent from the harness by design, so the surface under test stops
-- at them: the snapshot handed to the store, the values pulled out of the
-- settings table, the events subscribed to, and the script those events land in.
-- The event frame is a spy, which is what makes dispatch testable without
-- CreateFrame; the UI files that own real frames are Niv's in-game validation.
--
-- Sibling modules are swapped for spies on PRT rather than injected, so every
-- call the wiring makes has to be a fresh lookup. They are hidden while
-- AttendanceWiring.lua loads to force that: a file that captures
-- PRT.AttendanceStore into an upvalue takes nil instead and dies on the first
-- pull. PRT:GetSetting throws over the same window because saved settings do not
-- exist until ADDON_LOADED -- a value read at load time is the shipped default,
-- never the officer's.
--
-- Fixture values are chosen to be wrong-answer-proof rather than realistic. The
-- rollover hour under test is 2, so a handler that hardcodes the store's default
-- of 6 keys the record to the previous day; the roster the store must receive is
-- a sentinel table that is NOT PurplexityRaidToolsRosterDB, so reading the saved
-- variable directly fails the identity check; the leader is on another realm, so
-- a bare-name whisper target fails.

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals and module loads
--
-- Each dependency is loaded defensively so this file also runs standalone,
-- mirroring test_wiring.lua's convention. In a full run every attendance suite
-- sorts ahead of this one and has already loaded them.
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
    dofile("Modules/Attendance/Roster.lua")
end

if not PurplexityRaidTools.AttendanceSync then
    dofile("Modules/Attendance/AttendanceSync.lua")
end

local hiddenDuringLoad = {
    AttendanceStore = PurplexityRaidTools.AttendanceStore,
    Roster = PurplexityRaidTools.Roster,
    AttendanceSync = PurplexityRaidTools.AttendanceSync,
    AttendanceReport = PurplexityRaidTools.AttendanceReport,
    GroupInspect = PurplexityRaidTools.GroupInspect,
    Comms = PurplexityRaidTools.Comms,
    GetSetting = PurplexityRaidTools.GetSetting,
}

PurplexityRaidTools.AttendanceStore = nil
PurplexityRaidTools.Roster = nil
PurplexityRaidTools.AttendanceSync = nil
PurplexityRaidTools.AttendanceReport = nil
PurplexityRaidTools.GroupInspect = nil
PurplexityRaidTools.Comms = nil
PurplexityRaidTools.GetSetting = function()
    error("the wiring module must not read a setting at load: the saved values "
        .. "arrive with ADDON_LOADED, and Initialize runs after they do", 0)
end

--- Restored before the load error is re-raised: until the module exists this
--- file is expected to fail, and a failure that left PRT gutted would take every
--- later suite in the run down with it.
local loaded, loadError = pcall(dofile, "Modules/Attendance/AttendanceWiring.lua")

for field, value in pairs(hiddenDuringLoad) do
    PurplexityRaidTools[field] = value
end

if not loaded then
    error(loadError, 0)
end

local PRT = PurplexityRaidTools
local AttendanceWiring = PRT.AttendanceWiring
local Roster = PRT.Roster
local Sync = PRT.AttendanceSync

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local MISSING, PRESENT = 0, 3

local NIV = "Niv-Illidan"
local BOB = "Bob-Illidan"
local ZED = "Zed-Area52"
local MAE = "Mae-Illidan"
local SASJAH = "Sasjah-Stormrage"

local AUGUST_5_2026_AT_0300 = 1785888000 + 3 * 3600
local AUG_04 = "2026-08-04"
local AUG_05 = "2026-08-05"

local COUNTDOWN_START_EVENT = "START_PLAYER_COUNTDOWN"
local COUNTDOWN_CANCEL_EVENT = "CANCEL_PLAYER_COUNTDOWN"
local READY_CHECK_EVENT = "READY_CHECK"

--- The payloads warcraft.wiki.gg documents for the two countdown events, sent by
--- somebody else: a handler that filters on the initiator records nothing when
--- the raid leader pulls.
local COUNTDOWN_START_PAYLOAD = { "Player-1234-DEADBEEF", 10, 10, true, "Sasjah" }
local COUNTDOWN_CANCEL_PAYLOAD = { "Player-1234-DEADBEEF", true, "Sasjah" }
local READY_CHECK_PAYLOAD = { "Sasjah", 30 }

--- Handed to the store as the roster argument. Identity is the whole point: it
--- is reachable only through Roster:GetEntries, never through the saved variable.
local ROSTER_ENTRIES = { "the table Roster:GetEntries returned" }

--- GroupInspect keys members by GUID and nothing downstream reads the key, so
--- these are synthesised.
local function groupData(entries)
    local members = {}
    for index, entry in ipairs(entries) do
        members["GUID-" .. index] = entry
    end
    return members
end

local function rosterEntry(nickname, ...)
    local entry = { nickname = nickname, characters = { ... }, characterData = {} }
    for _, character in ipairs(entry.characters) do
        entry.characterData[character] = { class = "WARRIOR" }
    end
    return entry
end

local function settingsWith(overrides)
    local settings = {
        rolloverHour = 6,
        expiryDays = 90,
        autoSyncFromLeader = false,
        confirmBeforeSyncing = true,
        contentTypes = {
            openWorld = false,
            dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
            raid = { lfr = true, normal = true, heroic = true, mythic = true },
            scenario = { normal = false, heroic = false },
        },
    }
    for key, value in pairs(overrides or {}) do
        settings[key] = value
    end
    return settings
end

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

--- Swaps fields on the PRT table -- sibling modules, the group iterator -- and
--- puts back exactly what was there, including nothing at all.
local function withPRT(replacements, body)
    local saved = {}
    for field, value in pairs(replacements) do
        saved[field] = PRT[field]
        PRT[field] = value
    end
    local ok, err = pcall(body)
    for field in pairs(replacements) do
        PRT[field] = saved[field]
    end
    if not ok then
        error(err, 0)
    end
end

--- Counts settings reads as well as answering them. wow_stubs' GetSetting reads
--- PRT.defaults, so the table under test goes in there and comes back out.
local function withSettings(settings, body, contentEnabled)
    local savedDefaults = PRT.defaults.attendance
    local savedReader = PRT.GetSetting
    local savedContentChecker = PRT.IsContentTypeEnabled
    local reads = { count = 0, keys = {}, contentTypes = {} }

    PRT.defaults.attendance = settings
    PRT.GetSetting = function(self, key)
        reads.count = reads.count + 1
        reads.keys[#reads.keys + 1] = key
        return savedReader(self, key)
    end
    PRT.IsContentTypeEnabled = function(contentTypes)
        reads.contentTypes[#reads.contentTypes + 1] = contentTypes
        return contentEnabled ~= false
    end

    local ok, err = pcall(body, reads)

    PRT.defaults.attendance = savedDefaults
    PRT.GetSetting = savedReader
    PRT.IsContentTypeEnabled = savedContentChecker

    if not ok then
        error(err, 0)
    end
    return reads
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

--- The store reads its clock through C_DateAndTime.GetServerTimeLocal and
--- decomposes it with date(); neither is installed at file scope here, so the
--- suites that load after this one keep their own guarded fixtures.
local function atServerTime(timestamp, body)
    local savedDate = rawget(_G, "date")
    local savedDateAndTime = rawget(_G, "C_DateAndTime")

    _G.date = os.date
    _G.C_DateAndTime = {
        GetServerTimeLocal = function()
            return timestamp
        end,
    }

    local ok, err = pcall(body)

    _G.date = savedDate
    _G.C_DateAndTime = savedDateAndTime

    if not ok then
        error(err, 0)
    end
end

--- Class sources persist on the Roster module across test files.
local function withRosterSources(body)
    local savedGroup, savedGuild = Roster.groupSource, Roster.guildSource
    local ok, err = pcall(body)
    Roster.groupSource, Roster.guildSource = savedGroup, savedGuild
    if not ok then
        error(err, 0)
    end
end

local function withSyncSettings(body)
    local saved = Sync.confirmBeforeSyncing
    local ok, err = pcall(body)
    Sync.confirmBeforeSyncing = saved
    if not ok then
        error(err, 0)
    end
end

--- Stands in for the frame PRT:RegisterModule supplies in-game, recording what
--- the module subscribes to and holding on to the script it installs.
local function withEventFrame(body)
    local frame = { events = {}, scripts = {} }

    function frame:RegisterEvent(event)
        self.events[#self.events + 1] = event
    end

    function frame:SetScript(scriptName, handler)
        self.scripts[scriptName] = handler
    end

    local saved = AttendanceWiring.eventFrame
    AttendanceWiring.eventFrame = frame

    local ok, err = pcall(body, frame)
    AttendanceWiring.eventFrame = saved

    if not ok then
        error(err, 0)
    end
end

local function fire(frame, event, payload)
    local script = frame.scripts.OnEvent
    assertNotNil(script, "Initialize must install an OnEvent script")
    script(frame, event, unpack(payload or {}))
end

local function storeSpy()
    local spy = { starts = {}, cancels = 0, expiries = {} }

    function spy:OnCountdownStart(group, roster, rolloverHour)
        self.starts[#self.starts + 1] = {
            group = group,
            roster = roster,
            rolloverHour = rolloverHour,
        }
    end

    function spy:OnCountdownCancel()
        self.cancels = self.cancels + 1
    end

    function spy:ExpireOldDays(thresholdDays, rolloverHour)
        self.expiries[#self.expiries + 1] = {
            thresholdDays = thresholdDays,
            rolloverHour = rolloverHour,
        }
    end

    return spy
end

local function syncSpy()
    local spy = { readyChecks = {}, registrations = 0 }

    function spy:RegisterHandlers()
        self.registrations = self.registrations + 1
    end

    function spy:OnReadyCheck(leaderName, autoSyncEnabled)
        self.readyChecks[#self.readyChecks + 1] = {
            leaderName = leaderName,
            autoSyncEnabled = autoSyncEnabled,
        }
    end

    return spy
end

local function rosterSpy()
    local spy = { refreshes = 0 }

    function spy.GetEntries()
        return ROSTER_ENTRIES
    end

    function spy:RefreshClasses()
        self.refreshes = self.refreshes + 1
    end

    return spy
end

local function groupInspectFake(members)
    return {
        members = members,
        listeners = {},
        Listen = function(self, callback)
            self.listeners[#self.listeners + 1] = callback
        end,
    }
end

--- Every collaborator Initialize reaches for, in one place. The body receives
--- them as a context table.
local function withInitialized(settings, body)
    local context = {
        store = storeSpy(),
        sync = syncSpy(),
        roster = rosterSpy(),
        groupInspect = groupInspectFake(groupData({ { name = NIV, class = "MAGE" } })),
    }

    withPRT({
        AttendanceStore = context.store,
        AttendanceSync = context.sync,
        Roster = context.roster,
        GroupInspect = context.groupInspect,
    }, function()
        withSettings(settings or settingsWith(), function(reads)
            context.reads = reads
            withEventFrame(function(frame)
                context.frame = frame
                AttendanceWiring:Initialize()
                body(context)
            end)
        end)
    end)
end

--- Installs a group whose members carry a unit token, a full name, and their
--- rank. GetUnitName without the server flag returns the bare name, so a whisper
--- target built the lazy way fails the cross-realm assertions. "player" resolves
--- to whichever member is flagged as the local one, so asking about the player
--- directly and asking about their raid token give the same answer.
local function withRaid(units, body)
    local byToken, tokens = {}, {}
    for index, member in ipairs(units) do
        local token = "raid" .. index
        byToken[token] = member
        tokens[index] = token
        if member.isPlayer then
            byToken.player = member
        end
    end

    withPRT({
        IterateGroup = function()
            local index = 0
            return function()
                index = index + 1
                return tokens[index]
            end
        end,
    }, function()
        withGlobals({
            IsInGroup = function() return #tokens > 0 end,
            IsInRaid = function() return #tokens > 0 end,
            UnitIsGroupLeader = function(token)
                return byToken[token] ~= nil and byToken[token].leader == true
            end,
            UnitIsUnit = function(token, other)
                if other ~= "player" then
                    return token == other
                end
                return byToken[token] ~= nil and byToken[token].isPlayer == true
            end,
            GetUnitName = function(token, showServerName)
                local member = byToken[token]
                if not member then
                    return nil
                end
                if showServerName then
                    return member.name
                end
                return (member.name:match("^([^%-]+)"))
            end,
        }, body)
    end)
end

--- Both plausible gate implementations end up asking about "player": a unit-token
--- read directly, or the receive-side Comms:IsSenderPrivileged fed the player's
--- own name, which wow_stubs' UnitName returns as the token it was handed.
local function withPlayerRank(rank, body)
    withGlobals({
        IsInGroup = function() return rank.inGroup == true end,
        IsInRaid = function() return rank.inRaid == true end,
        UnitIsGroupLeader = function(unit)
            return unit == "player" and rank.leader == true
        end,
        UnitIsGroupAssistant = function(unit)
            return unit == "player" and rank.assistant == true
        end,
    }, body)
end

local function guildOf(members)
    return {
        GetNumGuildMembers = function()
            return #members
        end,
        GetGuildRosterInfo = function(index)
            local member = members[index]
            if not member then
                return nil
            end
            return member.name, "Raider", 3, 80, "Mage", "Orgrimmar", "", "", true, 0, member.class
        end,
    }
end

--- The store writes the snapshot into a keyed record and never sees an order, so
--- comparing as a set keeps these tests off whatever order pairs() happened to
--- produce. Duplicates and extras still fail.
local function assertSameCharacters(actual, expected, msg)
    local label = msg or "snapshot"
    assertEquals(#actual, #expected, label .. ": wrong number of characters")

    local seen = {}
    for _, name in ipairs(actual) do
        assertFalse(seen[name], label .. ": " .. tostring(name) .. " appears twice")
        seen[name] = true
    end
    for _, name in ipairs(expected) do
        assertTrue(seen[name], label .. ": " .. tostring(name) .. " is missing")
    end
end

local function contains(list, value)
    for _, entry in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Snapshot building
--------------------------------------------------------------------------------

tests["BuildSnapshot returns the full name-realm of every member"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE" },
        { name = BOB, class = "WARRIOR" },
        { name = ZED, class = "ROGUE" },
    }))

    assertSameCharacters(snapshot, { NIV, BOB, ZED })
end

tests["BuildSnapshot includes a member marked offline with no class or inspect data"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE", specId = 62 },
        { name = MAE, class = nil, specId = nil, talents = nil, online = false },
    }))

    assertSameCharacters(snapshot, { NIV, MAE },
        "group membership is what counts, never connectivity or inspect state")
end

tests["BuildSnapshot skips a name still showing the Unknown placeholder"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE" },
        { name = "Unknown", class = nil },
    }))

    assertSameCharacters(snapshot, { NIV })
end

tests["BuildSnapshot skips a bare name whose realm never resolved"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE" },
        { name = "Bob", class = "WARRIOR" },
    }))

    assertSameCharacters(snapshot, { NIV },
        "a resolved character name with no realm is still not an identity")
end

tests["BuildSnapshot skips a name carrying an empty realm"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE" },
        { name = "Bob-", class = "WARRIOR" },
    }))

    assertSameCharacters(snapshot, { NIV },
        "some name APIs answer with an empty realm rather than nil")
end

tests["BuildSnapshot skips an entry whose name is not a string"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({
        { name = NIV, class = "MAGE" },
        { class = "WARRIOR" },
    }))

    assertSameCharacters(snapshot, { NIV },
        "a pull is the worst moment for the snapshot builder to throw")
end

tests["BuildSnapshot returns an empty array for an empty group"] = function()
    local snapshot = AttendanceWiring:BuildSnapshot(groupData({}))

    assertNotNil(snapshot, "callers measure the result with #, so it is never nil")
    assertEquals(#snapshot, 0)
end

--------------------------------------------------------------------------------
-- Countdown start
--------------------------------------------------------------------------------

tests["a countdown start hands the store the snapshot, the roster entries, and the rollover hour"] = function()
    local store, roster = storeSpy(), rosterSpy()
    local groupInspect = groupInspectFake(groupData({
        { name = NIV, class = "MAGE" },
        { name = ZED, class = "ROGUE" },
    }))

    withPRT({ AttendanceStore = store, Roster = roster, GroupInspect = groupInspect }, function()
        withDatabases(nil, { rosterEntry("Decoy", SASJAH) }, function()
            withSettings(settingsWith({ rolloverHour = 2 }), function()
                AttendanceWiring:OnCountdownStart()
            end)
        end)
    end)

    assertEquals(#store.starts, 1, "a countdown start is a pull")
    local recorded = store.starts[1]
    assertSameCharacters(recorded.group, { NIV, ZED }, "recorded group")
    assertEquals(recorded.roster, ROSTER_ENTRIES,
        "the roster comes from Roster:GetEntries, which creates the table on a fresh install")
    assertEquals(recorded.rolloverHour, 2,
        "the rollover hour is the officer's setting, not the store's default")
end

tests["a countdown start reads the attendance settings exactly once"] = function()
    local groupInspect = groupInspectFake(groupData({ { name = NIV, class = "MAGE" } }))
    local settings = settingsWith()
    local reads

    withPRT({ AttendanceStore = storeSpy(), Roster = rosterSpy(), GroupInspect = groupInspect }, function()
        reads = withSettings(settings, function()
            AttendanceWiring:OnCountdownStart()
        end)
    end)

    assertEquals(reads.count, 1)
    assertEquals(reads.keys[1], "attendance",
        "the wiring reads its own settings table and nobody else's")
    assertEquals(#reads.contentTypes, 1)
    assertEquals(reads.contentTypes[1], settings.contentTypes,
        "the shared content-type gate receives the attendance content settings")
end

tests["a countdown start outside an enabled content type records nothing"] = function()
    local store = storeSpy()
    local groupInspect = groupInspectFake(groupData({ { name = NIV, class = "MAGE" } }))
    local settings = settingsWith()
    local reads

    withPRT({ AttendanceStore = store, Roster = rosterSpy(), GroupInspect = groupInspect }, function()
        reads = withSettings(settings, function()
            AttendanceWiring:OnCountdownStart()
        end, false)
    end)

    assertEquals(#store.starts, 0, "a Mythic+ pull must not create raid attendance")
    assertEquals(reads.count, 1)
    assertEquals(#reads.contentTypes, 1)
    assertEquals(reads.contentTypes[1], settings.contentTypes)
end

tests["a countdown start keeps placeholder-named members out of what the store records"] = function()
    local store = storeSpy()
    local groupInspect = groupInspectFake(groupData({
        { name = NIV, class = "MAGE" },
        { name = "Unknown", class = nil },
        { name = BOB, class = "WARRIOR" },
    }))

    withPRT({ AttendanceStore = store, Roster = rosterSpy(), GroupInspect = groupInspect }, function()
        withSettings(settingsWith(), function()
            AttendanceWiring:OnCountdownStart()
        end)
    end)

    assertEquals(#store.starts, 1)
    assertSameCharacters(store.starts[1].group, { NIV, BOB }, "recorded group")
end

tests["a countdown start with an empty group records nothing at all"] = function()
    local store = storeSpy()
    local groupInspect = groupInspectFake(groupData({}))

    withPRT({ AttendanceStore = store, Roster = rosterSpy(), GroupInspect = groupInspect }, function()
        withSettings(settingsWith(), function()
            AttendanceWiring:OnCountdownStart()
        end)
    end)

    assertEquals(#store.starts, 0,
        "an empty day would be Missing-fills only, and would cost the next real pull its Present records")
end

tests["a countdown start where every name is a placeholder records nothing at all"] = function()
    local store = storeSpy()
    local groupInspect = groupInspectFake(groupData({
        { name = "Unknown", class = nil },
        { name = "Bob-", class = "WARRIOR" },
    }))

    withPRT({ AttendanceStore = store, Roster = rosterSpy(), GroupInspect = groupInspect }, function()
        withSettings(settingsWith(), function()
            AttendanceWiring:OnCountdownStart()
        end)
    end)

    assertEquals(#store.starts, 0,
        "a group the client has not resolved yet is not a group of nobody")
end

tests["a countdown start records Present for the group and Missing for the absent roster entry"] = function()
    local attendance = {}
    local groupInspect = groupInspectFake(groupData({
        { name = NIV, class = "MAGE" },
        { name = BOB, class = "WARRIOR" },
        { name = "Unknown", class = nil },
    }))

    withPRT({ GroupInspect = groupInspect }, function()
        withDatabases(attendance, { rosterEntry("Sasjah", SASJAH) }, function()
            atServerTime(AUGUST_5_2026_AT_0300, function()
                withSettings(settingsWith({ rolloverHour = 2 }), function()
                    AttendanceWiring:OnCountdownStart()
                end)
            end)
        end)
    end)

    assertNil(attendance[AUG_04],
        "03:00 with a rollover hour of 2 belongs to the new day, not the night before")
    assertTableEquals(attendance[AUG_05], {
        [NIV] = PRESENT,
        [BOB] = PRESENT,
        [SASJAH] = MISSING,
    }, "the placeholder must reach neither the record nor the database")
end

--------------------------------------------------------------------------------
-- Countdown cancel
--------------------------------------------------------------------------------

tests["a cancelled countdown calls the store's cancel and records nothing"] = function()
    local store, roster = storeSpy(), rosterSpy()
    local groupInspect = groupInspectFake(groupData({ { name = NIV, class = "MAGE" } }))
    local reads

    withPRT({ AttendanceStore = store, Roster = roster, GroupInspect = groupInspect }, function()
        reads = withSettings(settingsWith(), function()
            AttendanceWiring:OnCountdownCancel()
        end)
    end)

    assertEquals(store.cancels, 1)
    assertEquals(#store.starts, 0, "cancelling is not an undo, and it is not a second pull either")
    assertEquals(reads.count, 0, "a cancel needs no setting")
end

tests["a cancelled countdown leaves the attendance database byte for byte alone"] = function()
    local attendance = { [AUG_05] = { [NIV] = PRESENT, [SASJAH] = MISSING } }
    local groupInspect = groupInspectFake(groupData({ { name = BOB, class = "WARRIOR" } }))

    withPRT({ GroupInspect = groupInspect }, function()
        withDatabases(attendance, { rosterEntry("Sasjah", SASJAH) }, function()
            atServerTime(AUGUST_5_2026_AT_0300, function()
                withSettings(settingsWith({ rolloverHour = 2 }), function()
                    AttendanceWiring:OnCountdownCancel()
                end)
            end)
        end)
    end)

    assertTableEquals(attendance, {
        [AUG_05] = { [NIV] = PRESENT, [SASJAH] = MISSING },
    })
end

--------------------------------------------------------------------------------
-- Ready check
--------------------------------------------------------------------------------

tests["a ready check asks the raid leader for their roster under their full name-realm"] = function()
    local sync = syncSpy()

    withPRT({ AttendanceSync = sync }, function()
        withRaid({
            { name = NIV, isPlayer = true },
            { name = SASJAH, leader = true },
        }, function()
            withSettings(settingsWith({ autoSyncFromLeader = true }), function()
                AttendanceWiring:OnReadyCheck()
            end)
        end)
    end)

    assertEquals(#sync.readyChecks, 1)
    assertEquals(sync.readyChecks[1].leaderName, SASJAH,
        "a bare name whispers a stranger on the player's own realm")
    assertEquals(sync.readyChecks[1].autoSyncEnabled, true)
end

tests["a ready check passes the auto-sync setting through rather than gating on it"] = function()
    local sync = syncSpy()

    withPRT({ AttendanceSync = sync }, function()
        withRaid({
            { name = NIV, isPlayer = true },
            { name = SASJAH, leader = true },
        }, function()
            withSettings(settingsWith({ autoSyncFromLeader = false }), function()
                AttendanceWiring:OnReadyCheck()
            end)
        end)
    end)

    assertEquals(#sync.readyChecks, 1,
        "the auto-sync gate lives in AttendanceSync, which is already tested for it")
    assertEquals(sync.readyChecks[1].autoSyncEnabled, false)
end

tests["a ready check run by the raid leader themselves asks nobody"] = function()
    local sync = syncSpy()

    withPRT({ AttendanceSync = sync }, function()
        withRaid({
            { name = NIV, isPlayer = true, leader = true },
            { name = SASJAH },
        }, function()
            withSettings(settingsWith({ autoSyncFromLeader = true }), function()
                AttendanceWiring:OnReadyCheck()
            end)
        end)
    end)

    assertEquals(#sync.readyChecks, 0,
        "the leader whispering themselves burns a message per ready check and offers a self-sync")
end

tests["a ready check in a group with no leader asks nobody"] = function()
    local sync = syncSpy()

    withPRT({ AttendanceSync = sync }, function()
        withRaid({
            { name = NIV, isPlayer = true },
            { name = SASJAH },
        }, function()
            withSettings(settingsWith({ autoSyncFromLeader = true }), function()
                AttendanceWiring:OnReadyCheck()
            end)
        end)
    end)

    assertEquals(#sync.readyChecks, 0)
end

tests["a ready check reads the attendance settings exactly once"] = function()
    local reads

    withPRT({ AttendanceSync = syncSpy() }, function()
        withRaid({
            { name = NIV, isPlayer = true },
            { name = SASJAH, leader = true },
        }, function()
            reads = withSettings(settingsWith({ autoSyncFromLeader = true }), function()
                AttendanceWiring:OnReadyCheck()
            end)
        end)
    end)

    assertEquals(reads.count, 1)
    assertEquals(reads.keys[1], "attendance")
end

--------------------------------------------------------------------------------
-- Expiry pass
--------------------------------------------------------------------------------

tests["the expiry pass hands the store both the threshold and the rollover hour"] = function()
    local store = storeSpy()

    withPRT({ AttendanceStore = store }, function()
        withSettings(settingsWith({ expiryDays = 45, rolloverHour = 2 }), function()
            AttendanceWiring:RunExpiryPass()
        end)
    end)

    assertEquals(#store.expiries, 1)
    assertEquals(store.expiries[1].thresholdDays, 45)
    assertEquals(store.expiries[1].rolloverHour, 2,
        "expiry and recording must agree on where a day starts or the boundary day is decided twice")
end

tests["the expiry pass reads the attendance settings exactly once"] = function()
    local reads

    withPRT({ AttendanceStore = storeSpy() }, function()
        reads = withSettings(settingsWith(), function()
            AttendanceWiring:RunExpiryPass()
        end)
    end)

    assertEquals(reads.count, 1)
    assertEquals(reads.keys[1], "attendance")
end

--------------------------------------------------------------------------------
-- Settings plumbing
--------------------------------------------------------------------------------

tests["the shipped attendance defaults match the spec"] = function()
    local defaults = PRT.defaults.attendance

    assertNotNil(defaults, "the wiring layer owns the attendance settings")
    assertEquals(defaults.rolloverHour, 6)
    assertEquals(defaults.expiryDays, 90)
    assertEquals(defaults.autoSyncFromLeader, false, "Automatically Sync From Leader is opt-in")
    assertEquals(defaults.confirmBeforeSyncing, true, "Confirm Before Syncing is on by default")
    assertTableEquals(defaults.contentTypes, {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = true, normal = true, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    }, "attendance defaults to raid instances only")
end

tests["applying settings injects Confirm Before Syncing into the sync module"] = function()
    withSyncSettings(function()
        Sync.confirmBeforeSyncing = nil
        withSettings(settingsWith({ confirmBeforeSyncing = false }), function()
            AttendanceWiring:ApplySettings()
        end)
        assertEquals(Sync.confirmBeforeSyncing, false)

        withSettings(settingsWith({ confirmBeforeSyncing = true }), function()
            AttendanceWiring:ApplySettings()
        end)
        assertEquals(Sync.confirmBeforeSyncing, true,
            "the officer can turn confirmation back on without a reload")
    end)
end

tests["Initialize registers an apply callback that re-injects a changed confirm setting"] = function()
    local registered = {}
    local savedRegister = PRT.RegisterApplyCallback

    PRT.RegisterApplyCallback = function(_, name, callback)
        registered[name] = callback
    end

    local ok, err = pcall(function()
        withSyncSettings(function()
            withInitialized(settingsWith({ confirmBeforeSyncing = true }), function() end)
            Sync.confirmBeforeSyncing = nil

            local callback = registered.attendance
            assertNotNil(callback, "a setting changed after load must still reach the sync module")

            withSettings(settingsWith({ confirmBeforeSyncing = false }), function()
                callback()
            end)
            assertEquals(Sync.confirmBeforeSyncing, false,
                "confirmBeforeSyncing is an injected field, not a setting the sync module reads")
        end)
    end)

    PRT.RegisterApplyCallback = savedRegister

    if not ok then
        error(err, 0)
    end
end

tests["Initialize injects Confirm Before Syncing without waiting for a settings change"] = function()
    withSyncSettings(function()
        Sync.confirmBeforeSyncing = nil

        withPRT({
            AttendanceStore = storeSpy(),
            Roster = rosterSpy(),
            GroupInspect = groupInspectFake(groupData({})),
        }, function()
            withSettings(settingsWith({ confirmBeforeSyncing = false }), function()
                withEventFrame(function()
                    AttendanceWiring:Initialize()
                end)
            end)
        end)

        assertEquals(Sync.confirmBeforeSyncing, false,
            "a roster push landing before the first settings change must honour the saved value")
    end)
end

--------------------------------------------------------------------------------
-- The raid-broadcast gate behind Push and Sync Roster
--------------------------------------------------------------------------------

tests["the raid-broadcast gate opens for a raid leader"] = function()
    withPlayerRank({ inGroup = true, inRaid = true, leader = true }, function()
        assertTrue(AttendanceWiring:CanPushToRaid())
    end)
end

tests["the raid-broadcast gate opens for a raid assistant"] = function()
    withPlayerRank({ inGroup = true, inRaid = true, assistant = true }, function()
        assertTrue(AttendanceWiring:CanPushToRaid())
    end)
end

tests["the raid-broadcast gate closes for a plain raid member"] = function()
    withPlayerRank({ inGroup = true, inRaid = true }, function()
        assertFalse(AttendanceWiring:CanPushToRaid(),
            "every receiver discards this push, so offering the button lies about what it does")
    end)
end

tests["the raid-broadcast gate opens for a party leader"] = function()
    withPlayerRank({ inGroup = true, leader = true }, function()
        assertTrue(AttendanceWiring:CanPushToRaid())
    end)
end

tests["the raid-broadcast gate closes for a party member who is only an assistant"] = function()
    withPlayerRank({ inGroup = true, assistant = true }, function()
        assertFalse(AttendanceWiring:CanPushToRaid(),
            "assistants exist in raids; outside one the receive-side check asks only about the leader")
    end)
end

tests["the raid-broadcast gate closes when the player is alone"] = function()
    withPlayerRank({ leader = true }, function()
        assertFalse(AttendanceWiring:CanPushToRaid())
    end)
end

--------------------------------------------------------------------------------
-- Initialize and event dispatch
--------------------------------------------------------------------------------

tests["the wiring module registers itself so the addon initializes it at load"] = function()
    local found = false
    for _, registered in pairs(PRT.modules) do
        if registered == AttendanceWiring then
            found = true
        end
    end

    assertTrue(found, "an unregistered module never has Initialize called and wires nothing")
end

tests["Initialize subscribes to exactly the countdown and ready-check events"] = function()
    withInitialized(nil, function(context)
        assertEquals(#context.frame.events, 3, "registered events: "
            .. table.concat(context.frame.events, ", "))
        assertTrue(contains(context.frame.events, COUNTDOWN_START_EVENT))
        assertTrue(contains(context.frame.events, COUNTDOWN_CANCEL_EVENT))
        assertTrue(contains(context.frame.events, READY_CHECK_EVENT),
            "auto-sync from the leader is triggered by a ready check")
    end)
end

tests["a countdown-start event reaches the countdown-start handler"] = function()
    withInitialized(settingsWith({ rolloverHour = 2 }), function(context)
        fire(context.frame, COUNTDOWN_START_EVENT, COUNTDOWN_START_PAYLOAD)

        assertEquals(#context.store.starts, 1,
            "any countdown is a pull, whoever started it")
        assertSameCharacters(context.store.starts[1].group, { NIV }, "recorded group")
        assertEquals(context.store.starts[1].rolloverHour, 2)
    end)
end

tests["a countdown-cancel event reaches the countdown-cancel handler"] = function()
    withInitialized(nil, function(context)
        fire(context.frame, COUNTDOWN_CANCEL_EVENT, COUNTDOWN_CANCEL_PAYLOAD)

        assertEquals(context.store.cancels, 1)
        assertEquals(#context.store.starts, 0)
    end)
end

tests["a ready-check event reaches the ready-check handler"] = function()
    withInitialized(settingsWith({ autoSyncFromLeader = true }), function(context)
        withRaid({
            { name = NIV, isPlayer = true },
            { name = SASJAH, leader = true },
        }, function()
            fire(context.frame, READY_CHECK_EVENT, READY_CHECK_PAYLOAD)
        end)

        assertEquals(#context.sync.readyChecks, 1)
        assertEquals(context.sync.readyChecks[1].leaderName, SASJAH)
    end)
end

tests["an event the module never registered does nothing"] = function()
    withInitialized(nil, function(context)
        local expiriesAfterInitialize = #context.store.expiries

        fire(context.frame, "PLAYER_REGEN_DISABLED", {})

        assertEquals(#context.store.starts, 0)
        assertEquals(context.store.cancels, 0)
        assertEquals(#context.sync.readyChecks, 0)
        assertEquals(#context.store.expiries, expiriesAfterInitialize)
    end)
end

--- Under 12.x chat-messaging lockdown the countdown payload arrives as secret
--- values, and a secret cannot be boolean-tested, compared with ==, or used as a
--- table key -- the three operations a metatable cannot trap. Nothing can stand
--- in for one in a fixture, so the pin is structural: a script that never
--- declares a way to receive the payload cannot reach it.
tests["the OnEvent script declares no parameter able to hold the countdown payload"] = function()
    withInitialized(nil, function(context)
        local info = debug.getinfo(context.frame.scripts.OnEvent, "u")

        assertEquals(info.nparams, 2,
            "the OnEvent script may declare only the frame and the event name")
        assertFalse(info.isvararg,
            "a vararg script can still reach the payload lockdown makes secret")
    end)
end

tests["Initialize registers the sync module's comms handlers"] = function()
    withInitialized(nil, function(context)
        assertEquals(context.sync.registrations, 1,
            "registration is an explicit call, so somebody has to make it")
    end)
end

tests["Initialize runs the expiry pass once, with the saved settings"] = function()
    withInitialized(settingsWith({ expiryDays = 45, rolloverHour = 2 }), function(context)
        assertEquals(#context.store.expiries, 1,
            "the spec runs the pruning pass once when the addon loads")
        assertEquals(context.store.expiries[1].thresholdDays, 45)
        assertEquals(context.store.expiries[1].rolloverHour, 2)
    end)
end

tests["Initialize subscribes to group scans so unknown roster classes get backfilled"] = function()
    withInitialized(nil, function(context)
        assertEquals(#context.groupInspect.listeners, 1,
            "a character whose class was unknown at import stays unknown without this")
        assertEquals(context.roster.refreshes, 0, "nothing to backfill until a scan happens")

        context.groupInspect.listeners[1]()

        assertEquals(context.roster.refreshes, 1)
    end)
end

tests["after Initialize the roster resolves classes from GroupInspect, not a fresh group crawl"] = function()
    local groupInspect = groupInspectFake(groupData({
        { name = NIV, class = "MAGE" },
    }))

    withRosterSources(function()
        withPRT({
            AttendanceStore = storeSpy(),
            AttendanceSync = syncSpy(),
            Roster = Roster,
            GroupInspect = groupInspect,
            IterateGroup = function()
                error("GroupInspect already owns the group crawl; the wiring reads its members", 0)
            end,
        }, function()
            withSettings(settingsWith(), function()
                withEventFrame(function()
                    AttendanceWiring:Initialize()
                end)
            end)

            assertEquals(Roster:ResolveClass(NIV), "MAGE")
        end)
    end)
end

tests["after Initialize the roster falls back to the guild for a character outside the group"] = function()
    local groupInspect = groupInspectFake(groupData({
        { name = NIV, class = "MAGE" },
    }))

    withRosterSources(function()
        withPRT({
            AttendanceStore = storeSpy(),
            AttendanceSync = syncSpy(),
            Roster = Roster,
            GroupInspect = groupInspect,
        }, function()
            withGlobals(guildOf({
                { name = ZED, class = "ROGUE" },
                { name = NIV, class = "PRIEST" },
            }), function()
                withSettings(settingsWith(), function()
                    withEventFrame(function()
                        AttendanceWiring:Initialize()
                    end)
                end)

                assertEquals(Roster:ResolveClass(ZED), "ROGUE")
                assertEquals(Roster:ResolveClass(NIV), "MAGE",
                    "the group source answers first, and it is the one that is current")
                assertNil(Roster:ResolveClass(SASJAH))
            end)
        end)
    end)
end

return tests
