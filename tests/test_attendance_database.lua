local PRT = PurplexityRaidTools

if not LibStub then
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/LibSerialize/LibSerialize.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
end

if not PRT.RosterValidation then
    dofile("Modules/Attendance/RosterValidation.lua")
end
if not PRT.Roster then
    dofile("Modules/Attendance/Roster.lua")
end
dofile("Modules/Attendance/AttendanceDatabase.lua")

local Database = PRT.AttendanceDatabase
local tests = {}

local function RichAttendance()
    return {
        ["2026-08-25"] = {
            ["Aster-MoonGuard"] = { status = 3, itemLevel = 712.5 },
            ["Cinder-Illidan"] = { status = 4 },
        },
        ["2026-08-26"] = {
            ["Aster-MoonGuard"] = { status = 2, itemLevel = 713 },
            ["Cinder-Illidan"] = { status = 1 },
            ["Zephyra-Area52"] = { status = 0 },
        },
    }
end

local function RichRoster()
    return {
        {
            nickname = "Starcaller",
            characters = { "Aster-MoonGuard", "Zephyra-Area52" },
            characterData = {
                ["Aster-MoonGuard"] = {
                    class = "PRIEST",
                    mainSpec = 256,
                    offSpecs = { 257, 258 },
                },
                ["Zephyra-Area52"] = {
                    class = "MAGE",
                    mainSpec = 63,
                    offSpecs = { 62 },
                },
            },
        },
        {
            nickname = "Cinder",
            characters = { "Cinder-Illidan" },
            characterData = {
                ["Cinder-Illidan"] = {
                    class = "PALADIN",
                    mainSpec = 65,
                    offSpecs = { 70, 66 },
                },
            },
        },
    }
end

local function WithDatabases(attendance, roster, callback)
    local savedAttendance = PurplexityRaidToolsAttendanceDB
    local savedRoster = PurplexityRaidToolsRosterDB
    PurplexityRaidToolsAttendanceDB = attendance
    PurplexityRaidToolsRosterDB = roster

    local ok, err = pcall(callback)

    PurplexityRaidToolsAttendanceDB = savedAttendance
    PurplexityRaidToolsRosterDB = savedRoster
    if not ok then
        error(err, 0)
    end
end

local function EncodePayload(payload, version)
    local serialize = LibStub("LibSerialize")
    local deflate = LibStub("LibDeflate")
    local serialized = serialize:Serialize(payload)
    local encoded = deflate:EncodeForPrint(deflate:CompressDeflate(serialized))
    return "PRTATTENDANCE:" .. (version or Database.FORMAT_VERSION) .. ":" .. encoded
end

tests["export and import preserve the complete attendance database"] = function()
    local attendance = RichAttendance()
    local roster = RichRoster()
    local expectedAttendance = CopyTable(attendance)
    local expectedRoster = CopyTable(roster)

    WithDatabases(attendance, roster, function()
        local exported = Database:Export()
        PurplexityRaidToolsAttendanceDB = { ["2026-09-01"] = { ["Other-Realm"] = 3 } }
        PurplexityRaidToolsRosterDB = {}

        local prepared, err = Database:PrepareImport(exported)
        assertNotNil(prepared, tostring(err))
        assertTableEquals(prepared.summary, {
            days = 2,
            attendanceRecords = 5,
            rosterEntries = 2,
            rosterCharacters = 3,
        })
        assertTableEquals(PurplexityRaidToolsAttendanceDB,
            { ["2026-09-01"] = { ["Other-Realm"] = 3 } },
            "reviewing the import must not change attendance")
        assertTableEquals(PurplexityRaidToolsRosterDB, {},
            "reviewing the import must not change the roster")

        local ok, summary = Database:ApplyPrepared(prepared)
        assertTrue(ok, tostring(summary))
        assertTableEquals(PurplexityRaidToolsAttendanceDB, expectedAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, expectedRoster)
    end)
end

tests["a confirmed import refills both live tables before notifying roster listeners"] = function()
    local incomingAttendance = RichAttendance()
    local incomingRoster = RichRoster()
    local incomingText
    WithDatabases(incomingAttendance, incomingRoster, function()
        incomingText = Database:Export()
    end)

    local attendance = { ["2026-09-01"] = { ["Other-Realm"] = 3 } }
    local roster = {}
    local observing = false
    local notifications = 0
    PRT.Roster:Listen(function()
        if not observing then
            return
        end
        notifications = notifications + 1
        assertTableEquals(PurplexityRaidToolsAttendanceDB, incomingAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, incomingRoster)
    end)

    WithDatabases(attendance, roster, function()
        local prepared = assert(Database:PrepareImport(incomingText))
        observing = true
        local ok, err = Database:ApplyPrepared(prepared)
        observing = false

        assertTrue(ok, tostring(err))
        assertEquals(notifications, 1)
        assertEquals(PurplexityRaidToolsAttendanceDB, attendance,
            "attendance consumers must keep their live table reference")
        assertEquals(PurplexityRaidToolsRosterDB, roster,
            "roster consumers must keep their live table reference")
    end)
    observing = false
end

tests["empty attendance history and roster round trip together"] = function()
    WithDatabases({}, {}, function()
        local prepared, err = Database:PrepareImport(Database:Export())
        assertNotNil(prepared, tostring(err))
        assertTableEquals(prepared.summary, {
            days = 0,
            attendanceRecords = 0,
            rosterEntries = 0,
            rosterCharacters = 0,
        })
        assertTrue(Database:ApplyPrepared(prepared))
        assertTableEquals(PurplexityRaidToolsAttendanceDB, {})
        assertTableEquals(PurplexityRaidToolsRosterDB, {})
    end)
end

tests["pasted exports may have surrounding whitespace"] = function()
    WithDatabases(RichAttendance(), RichRoster(), function()
        local prepared, err = Database:PrepareImport("\n  " .. Database:Export() .. "  \n")
        assertNotNil(prepared, tostring(err))
    end)
end

tests["unreleased version one exports are rejected without changing data"] = function()
    local attendance = RichAttendance()
    local roster = RichRoster()
    local beforeAttendance = CopyTable(attendance)
    local beforeRoster = CopyTable(roster)
    local text = EncodePayload({
        attendance = {
            ["2026-08-25"] = { ["Aster-MoonGuard"] = 3 },
        },
        roster = {},
    }, 1)

    WithDatabases(attendance, roster, function()
        local prepared, err = Database:PrepareImport(text)

        assertNil(prepared)
        assertEquals(type(err), "string")
        assertTableEquals(PurplexityRaidToolsAttendanceDB, beforeAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, beforeRoster)
    end)
end

tests["unsupported format versions are rejected without changing data"] = function()
    local attendance = RichAttendance()
    local roster = RichRoster()
    local beforeAttendance = CopyTable(attendance)
    local beforeRoster = CopyTable(roster)

    WithDatabases(attendance, roster, function()
        local prepared, err = Database:PrepareImport(EncodePayload({
            attendance = {},
            roster = {},
        }, 3))
        assertNil(prepared)
        assertEquals(type(err), "string")
        assertTableEquals(PurplexityRaidToolsAttendanceDB, beforeAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, beforeRoster)
    end)
end

tests["malformed exports are rejected without changing data"] = function()
    local malformed = {
        "not an export",
        "PRTATTENDANCE:2:not-valid-encoded-data",
        EncodePayload({ attendance = {}, roster = {}, extra = true }),
        EncodePayload({ attendance = { ["2026-02-30"] = { Aster = 3 } }, roster = {} }),
        EncodePayload({ attendance = { ["2026-08-25"] = { Aster = 9 } }, roster = {} }),
        EncodePayload({ attendance = {}, roster = { { nickname = "Broken" } } }),
    }

    for _, text in ipairs(malformed) do
        local attendance = RichAttendance()
        local roster = RichRoster()
        local beforeAttendance = CopyTable(attendance)
        local beforeRoster = CopyTable(roster)

        WithDatabases(attendance, roster, function()
            local prepared, err = Database:PrepareImport(text)
            assertNil(prepared)
            assertEquals(type(err), "string")
            assertTableEquals(PurplexityRaidToolsAttendanceDB, beforeAttendance)
            assertTableEquals(PurplexityRaidToolsRosterDB, beforeRoster)
        end)
    end
end

tests["combat blocks a confirmed import atomically"] = function()
    local incomingText
    WithDatabases(RichAttendance(), RichRoster(), function()
        incomingText = Database:Export()
    end)

    local attendance = { ["2026-09-01"] = { ["Other-Realm"] = 3 } }
    local roster = {}
    local beforeAttendance = CopyTable(attendance)
    local beforeRoster = CopyTable(roster)
    local savedCombat = rawget(_G, "InCombatLockdown")

    WithDatabases(attendance, roster, function()
        local prepared = assert(Database:PrepareImport(incomingText))
        InCombatLockdown = function()
            return true
        end

        local ok, err = Database:ApplyPrepared(prepared)
        InCombatLockdown = savedCombat

        assertFalse(ok)
        assertEquals(type(err), "string")
        assertTableEquals(PurplexityRaidToolsAttendanceDB, beforeAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, beforeRoster)
    end)
    InCombatLockdown = savedCombat
end

tests["tampering after review is revalidated before either database changes"] = function()
    local incomingText
    WithDatabases(RichAttendance(), RichRoster(), function()
        incomingText = Database:Export()
    end)

    local attendance = { ["2026-09-01"] = { ["Other-Realm"] = 3 } }
    local roster = {}
    local beforeAttendance = CopyTable(attendance)

    WithDatabases(attendance, roster, function()
        local prepared = assert(Database:PrepareImport(incomingText))
        prepared.roster[1].characters = {}

        local ok, err = Database:ApplyPrepared(prepared)

        assertFalse(ok)
        assertEquals(type(err), "string")
        assertTableEquals(PurplexityRaidToolsAttendanceDB, beforeAttendance)
        assertTableEquals(PurplexityRaidToolsRosterDB, {})
    end)
end

return tests
