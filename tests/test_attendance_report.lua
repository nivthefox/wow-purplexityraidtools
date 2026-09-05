-- tests/test_attendance_report.lua
-- Exercises read-time resolution and report assembly (spec
-- 2026-08-05-attendance-tracking: "Resolution and Reporting", plus the
-- "player swaps characters mid-raid", "character renamed or transferred" and
-- "player removed from the roster" edge cases).
--
-- This suite installs no globals at file scope, deliberately. Test files load in
-- sorted order and this one sorts ahead of the roster and store suites, whose
-- class, specialization and clock fixtures are all installed behind "if X == nil"
-- guards; anything defined here would be silently adopted by them in place of
-- their own. The one test that drives the store installs the store's globals for
-- its duration and puts them back.
--
-- Fixture nicknames share no substring with the characters they own, and entries
-- list their characters out of alphabetical order. A report assembled from
-- character names, or from the arbitrary order of the per-character data map,
-- therefore cannot pass: the roster has to actually be read.

local tests = {}

dofile("Modules/Attendance/AttendanceReport.lua")
dofile("Modules/Attendance/AttendanceStore.lua")

local PRT = PurplexityRaidTools
local Report = PRT.AttendanceReport
local Store = PRT.AttendanceStore

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local MISSING, ABSENT, LATE, PRESENT, STANDBY = 0, 1, 2, 3, 4

local AUG_05 = "2026-08-05"
local AUG_03 = "2026-08-03"
local JUL_31 = "2026-07-31"
local JUL_29 = "2026-07-29"
local JUL_27 = "2026-07-27"
local JUL_24 = "2026-07-24"
local JUL_22 = "2026-07-22"
local JUL_20 = "2026-07-20"

local EIGHT_DAYS = { AUG_05, AUG_03, JUL_31, JUL_29, JUL_27, JUL_24, JUL_22, JUL_20 }

local OMNIVICENT = "Omnivicent-Proudmoore"
local NIVEN = "Niven-Proudmoore"
local ELSIE = "Elsie-Proudmoore"
local GRIMGRACE = "Grimgrace-Proudmoore"
local ZEPHYRA = "Zephyra-Proudmoore"
local AELIN = "Aelin-Proudmoore"
local RANDOPUG = "Randopug-Stormrage"
local BENCHWARMER = "Benchwarmer-Stormrage"
local ALTERAC = "Alterac-Stormrage"
local ZULJIN = "Zuljin-Stormrage"

local HURRICANE = "Hurricane"
local TEMPEST = "Tempest"
local CINDER = "Cinder"

local AUGUST_5_2026_AT_2000 = 1785888000 + 20 * 3600

local function entry(nickname, ...)
    local characters = { ... }
    local characterData = {}
    for _, character in ipairs(characters) do
        characterData[character] = { class = "PRIEST", offSpecs = {} }
    end
    return { nickname = nickname, characters = characters, characterData = characterData }
end

--- Both orders here are the officer's arrangement, and both are deliberately
--- unsorted. The nicknames match neither ascending nor descending order, the
--- resolved percentages (100, 67, 100) are monotonic in neither direction, and
--- Cinder's characters are reverse alphabetical, so a sort on any of the three
--- fails rather than reproducing the fixture by luck.
local function reportRoster()
    return {
        entry(HURRICANE, OMNIVICENT, NIVEN),
        entry(TEMPEST, ELSIE),
        entry(CINDER, ZEPHYRA, AELIN),
    }
end

local function rosterBeforeRemoval()
    return { entry(HURRICANE, OMNIVICENT, NIVEN), entry(TEMPEST, ELSIE) }
end

local function reportDB()
    return {
        [AUG_03] = {
            [OMNIVICENT] = PRESENT,
            [ELSIE] = ABSENT,
            [ZEPHYRA] = PRESENT,
            [BENCHWARMER] = PRESENT,
        },
        [JUL_20] = { [RANDOPUG] = PRESENT },
        [AUG_05] = {
            [NIVEN] = LATE,
            [OMNIVICENT] = MISSING,
            [ELSIE] = PRESENT,
            [RANDOPUG] = PRESENT,
            [ALTERAC] = PRESENT,
        },
        [JUL_31] = { [AELIN] = PRESENT, [ELSIE] = PRESENT, [ZULJIN] = LATE },
    }
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Everything the attendance store reads out of the environment, installed for
--- the duration of body and then put back: this file loads before the store's
--- own suite, whose guarded fixtures would otherwise never be installed.
local function withAttendanceStore(timestamp, body)
    local savedDateAndTime = rawget(_G, "C_DateAndTime")
    local savedAttendance = rawget(_G, "PurplexityRaidToolsAttendanceDB")
    local savedRoster = rawget(_G, "PurplexityRaidToolsRosterDB")

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
    _G.PurplexityRaidToolsAttendanceDB = {}
    _G.PurplexityRaidToolsRosterDB = {}

    local ok, err = pcall(body)

    _G.C_DateAndTime = savedDateAndTime
    _G.PurplexityRaidToolsAttendanceDB = savedAttendance
    _G.PurplexityRaidToolsRosterDB = savedRoster

    if not ok then
        error(err, 0)
    end
end

local function withSavedVariables(attendance, roster, body)
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

local function dayRecords(character, statusesByDay)
    local db = {}
    for day, status in pairs(statusesByDay) do
        db[day] = { [character] = status }
    end
    return db
end

local function entryNamed(entries, nickname)
    for _, candidate in ipairs(entries) do
        if candidate.nickname == nickname then
            return candidate
        end
    end
    return nil
end

local function rowNamed(rows, name)
    for _, row in ipairs(rows) do
        if row.name == name then
            return row
        end
    end
    return nil
end

local function namesOf(rows)
    local names = {}
    for index, row in ipairs(rows) do
        names[index] = row.name
    end
    return names
end

--------------------------------------------------------------------------------
-- Load contract
--------------------------------------------------------------------------------

tests["the report loads headless with no frame or timer API available"] = function()
    assertNil(rawget(_G, "CreateFrame"),
        "wow_stubs must not provide CreateFrame, so a frame dependency fails loudly")
    assertNil(rawget(_G, "C_Timer"),
        "wow_stubs must not provide C_Timer, so a timer dependency fails loudly")
    assertNotNil(Report, "PurplexityRaidTools.AttendanceReport must exist after load")
end

tests["no report operation reads addon settings"] = function()
    local savedGetSetting = PRT.GetSetting
    PRT.GetSetting = function()
        error("the report must take its inputs as parameters, never read PRT:GetSetting", 0)
    end

    local ok, err = pcall(function()
        Report:ResolveStatus(reportDB(), AUG_05, { OMNIVICENT, NIVEN })
        Report:GetPercentage(reportDB(), EIGHT_DAYS, { OMNIVICENT, NIVEN })
        Report:Build(reportDB(), reportRoster())
    end)

    PRT.GetSetting = savedGetSetting
    assertTrue(ok, tostring(err))
end

tests["the report reads the arguments it is handed, never the saved variables"] = function()
    withSavedVariables({}, {}, function()
        local report = Report:Build(reportDB(), reportRoster())

        assertEquals(#report.days, 4,
            "the days must come from the database argument, not the empty SavedVariable")
        assertEquals(#report.players, 3,
            "the rows must come from the entries argument, not the empty SavedVariable")
    end)
end

--------------------------------------------------------------------------------
-- Resolution: a player's status for a day is the best across their characters
--------------------------------------------------------------------------------

tests["two characters recorded 0 and 2 on one day resolve to 2"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = MISSING, [NIVEN] = LATE } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), LATE)
end

tests["a player who swaps characters mid-raid resolves to the better status"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = PRESENT, [NIVEN] = LATE } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), PRESENT,
        "Present on the main and Late on the alt displays as Present")
    assertEquals(Report:ResolveStatus(db, AUG_05, { NIVEN, OMNIVICENT }), PRESENT,
        "the resolved status does not depend on the order the characters are listed in")
end

tests["an Absent record resolves against a Present one on another character"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = ABSENT, [NIVEN] = PRESENT } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), PRESENT,
        "an excused player who raided anyway counts as having raided")
end

tests["Present resolves ahead of Standby regardless of character order"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = STANDBY, [NIVEN] = PRESENT } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), PRESENT)
    assertEquals(Report:ResolveStatus(db, AUG_05, { NIVEN, OMNIVICENT }), PRESENT)
end

tests["Standby resolves ahead of Late"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = STANDBY, [NIVEN] = LATE } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), STANDBY)
end

tests["a day no character has a record for resolves to nil rather than Missing"] = function()
    local db = { [AUG_05] = { [ELSIE] = PRESENT } }

    assertNil(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }),
        "no record is distinct from Missing (0)")
end

tests["a day absent from the database resolves to nil"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = PRESENT } }

    assertNil(Report:ResolveStatus(db, JUL_20, { OMNIVICENT }))
end

tests["a Missing record resolves to Missing when the player's other characters have none"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = MISSING } }

    assertEquals(Report:ResolveStatus(db, AUG_05, { OMNIVICENT, NIVEN }), MISSING,
        "an unrecorded sibling character must not suppress a real Missing record")
end

tests["records belonging to characters outside the list never resolve into the status"] = function()
    local db = { [AUG_05] = { [ELSIE] = PRESENT, [GRIMGRACE] = PRESENT } }

    assertNil(Report:ResolveStatus(db, AUG_05, { OMNIVICENT }),
        "resolution reads the player's own characters, not the whole day's record")
end

--------------------------------------------------------------------------------
-- Percentage
--------------------------------------------------------------------------------

tests["a player Present or Late on 6 of 8 recorded days scores 75"] = function()
    local db = dayRecords(ELSIE, {
        [AUG_05] = PRESENT,
        [AUG_03] = PRESENT,
        [JUL_31] = LATE,
        [JUL_29] = PRESENT,
        [JUL_27] = PRESENT,
        [JUL_24] = PRESENT,
        [JUL_22] = ABSENT,
        [JUL_20] = MISSING,
    })

    assertEquals(Report:GetPercentage(db, EIGHT_DAYS, { ELSIE }), 75)
end

tests["Standby provides the same attendance credit as Present"] = function()
    local db = dayRecords(ELSIE, {
        [AUG_05] = STANDBY,
        [AUG_03] = PRESENT,
        [JUL_31] = MISSING,
    })

    assertEquals(Report:GetPercentage(db, { AUG_05, AUG_03, JUL_31 }, { ELSIE }), 67)
end

tests["the percentage is a whole number rounded half up"] = function()
    local twoOfThree = dayRecords(ELSIE, {
        [AUG_05] = PRESENT,
        [AUG_03] = PRESENT,
        [JUL_31] = MISSING,
    })
    assertEquals(Report:GetPercentage(twoOfThree, { AUG_05, AUG_03, JUL_31 }, { ELSIE }), 67,
        "66.67 rounds to 67, and the function returns whole percents rather than a ratio")

    local oneOfEight = dayRecords(ELSIE, {
        [AUG_05] = PRESENT,
        [AUG_03] = MISSING,
        [JUL_31] = MISSING,
        [JUL_29] = MISSING,
        [JUL_27] = MISSING,
        [JUL_24] = MISSING,
        [JUL_22] = MISSING,
        [JUL_20] = MISSING,
    })
    assertEquals(Report:GetPercentage(oneOfEight, EIGHT_DAYS, { ELSIE }), 13,
        "an exact 12.5 rounds up")
end

tests["recorded days the player has no record for are excluded from the percentage"] = function()
    local db = {
        [AUG_05] = { [ELSIE] = PRESENT },
        [AUG_03] = { [ELSIE] = PRESENT },
        [JUL_31] = { [ELSIE] = LATE },
        [JUL_29] = { [ELSIE] = PRESENT },
        [JUL_27] = { [ELSIE] = MISSING },
        [JUL_24] = { [GRIMGRACE] = PRESENT },
        [JUL_22] = { [GRIMGRACE] = PRESENT },
        [JUL_20] = { [GRIMGRACE] = PRESENT },
    }

    assertEquals(Report:GetPercentage(db, EIGHT_DAYS, { ELSIE }), 80,
        "4 good of the player's 5 recorded days; the 3 days they were untracked do not count")
end

tests["days absent from the database contribute nothing to the percentage"] = function()
    local db = { [AUG_05] = { [ELSIE] = PRESENT }, [AUG_03] = { [ELSIE] = MISSING } }

    assertEquals(Report:GetPercentage(db, EIGHT_DAYS, { ELSIE }), 50)
end

tests["a player whose only records are Absent and Missing scores 0"] = function()
    local db = dayRecords(ELSIE, {
        [AUG_05] = ABSENT,
        [AUG_03] = MISSING,
        [JUL_31] = ABSENT,
    })

    assertEquals(Report:GetPercentage(db, EIGHT_DAYS, { ELSIE }), 0)
end

tests["an excused Absent lowers the percentage exactly as a Missing does"] = function()
    local excused = dayRecords(ELSIE, { [AUG_05] = PRESENT, [AUG_03] = ABSENT })
    local unexcused = dayRecords(ELSIE, { [AUG_05] = PRESENT, [AUG_03] = MISSING })

    assertEquals(Report:GetPercentage(excused, EIGHT_DAYS, { ELSIE }), 50,
        "an excused absence is displayed as excused but still counts against the number")
    assertEquals(Report:GetPercentage(unexcused, EIGHT_DAYS, { ELSIE }), 50)
end

tests["the percentage counts every character of the player"] = function()
    local db = {
        [AUG_05] = { [OMNIVICENT] = PRESENT },
        [AUG_03] = { [NIVEN] = PRESENT },
        [JUL_31] = { [OMNIVICENT] = MISSING },
    }

    assertEquals(Report:GetPercentage(db, EIGHT_DAYS, { OMNIVICENT, NIVEN }), 67,
        "a day recorded on any of the player's characters is one of the player's days")
end

tests["a player with no records at all has no percentage"] = function()
    local db = { [AUG_05] = { [ELSIE] = PRESENT } }

    assertNil(Report:GetPercentage(db, EIGHT_DAYS, { OMNIVICENT, NIVEN }),
        "no recorded day means there is nothing to take a percentage of")
end

tests["a percentage over an empty day set is nil"] = function()
    assertNil(Report:GetPercentage(reportDB(), {}, { ELSIE }))
end

--------------------------------------------------------------------------------
-- Report assembly
--------------------------------------------------------------------------------

tests["the report assembles rows, statuses and percentages for a full grid"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertTableEquals(report, {
        days = { AUG_05, AUG_03, JUL_31, JUL_20 },
        players = {
            {
                name = HURRICANE,
                characters = { OMNIVICENT, NIVEN },
                statuses = { [AUG_05] = LATE, [AUG_03] = PRESENT },
                percentage = 100,
            },
            {
                name = TEMPEST,
                characters = { ELSIE },
                statuses = { [AUG_05] = PRESENT, [AUG_03] = ABSENT, [JUL_31] = PRESENT },
                percentage = 67,
            },
            {
                name = CINDER,
                characters = { ZEPHYRA, AELIN },
                statuses = { [AUG_03] = PRESENT, [JUL_31] = PRESENT },
                percentage = 100,
            },
        },
        unrostered = {
            {
                name = ALTERAC,
                characters = { ALTERAC },
                statuses = { [AUG_05] = PRESENT },
            },
            {
                name = BENCHWARMER,
                characters = { BENCHWARMER },
                statuses = { [AUG_03] = PRESENT },
            },
            {
                name = RANDOPUG,
                characters = { RANDOPUG },
                statuses = { [AUG_05] = PRESENT, [JUL_20] = PRESENT },
            },
            {
                name = ZULJIN,
                characters = { ZULJIN },
                statuses = { [JUL_31] = LATE },
            },
        },
    })
end

tests["the report lists every recorded day newest first"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertTableEquals(report.days, { AUG_05, AUG_03, JUL_31, JUL_20 },
        "a day whose only records belong to un-rostered characters is still a column")
end

tests["rostered rows follow the roster's own order"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertTableEquals(namesOf(report.players), { HURRICANE, TEMPEST, CINDER },
        "the officer arranges the roster; the grid presents that arrangement unsorted")
end

tests["un-rostered rows are ordered by character name"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertTableEquals(namesOf(report.unrostered), { ALTERAC, BENCHWARMER, RANDOPUG, ZULJIN },
        "no officer-controlled order exists off the roster, so these are alphabetical")
end

tests["a player row carries the entry's characters in roster order"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertTableEquals(rowNamed(report.players, CINDER).characters, { ZEPHYRA, AELIN },
        "the primary character stays first; the list is neither sorted nor taken from the data map")
end

tests["a day the player has no record for is absent from their statuses"] = function()
    local report = Report:Build(reportDB(), reportRoster())
    local hurricane = rowNamed(report.players, HURRICANE)

    assertNil(hurricane.statuses[JUL_31], "no record is distinct from Missing (0)")
    assertNil(hurricane.statuses[JUL_20])
end

tests["a rostered player with no records at all is omitted from the report"] = function()
    local db = { [AUG_05] = { [ELSIE] = PRESENT } }
    local entries = { entry(TEMPEST, ELSIE), entry(HURRICANE, OMNIVICENT, NIVEN) }

    local report = Report:Build(db, entries)
    local hurricane = rowNamed(report.players, HURRICANE)

    assertNil(hurricane, "a player with no retained attendance entries must leave the grid")
    assertTableEquals(namesOf(report.players), { TEMPEST })
end

tests["recorded characters on no roster entry are grouped under their raw names"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertNotNil(rowNamed(report.unrostered, RANDOPUG),
        "an un-rostered character is displayed under its own full name-realm")
    assertNil(rowNamed(report.players, RANDOPUG),
        "an un-rostered character is never a rostered row")
    assertTableEquals(rowNamed(report.unrostered, RANDOPUG).characters, { RANDOPUG },
        "the row carries the single character it edits directly")
end

tests["an un-rostered character has no percentage despite having records"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    assertNil(rowNamed(report.unrostered, RANDOPUG).percentage,
        "characters off the roster are displayed without a percentage calculation")
    assertNil(rowNamed(report.unrostered, BENCHWARMER).percentage)
end

tests["a rostered character never appears in the un-rostered group"] = function()
    local report = Report:Build(reportDB(), reportRoster())

    for _, character in ipairs({ OMNIVICENT, NIVEN, ELSIE, ZEPHYRA, AELIN }) do
        assertNil(rowNamed(report.unrostered, character),
            character .. " belongs to a roster entry and must not also stand alone")
    end
end

--------------------------------------------------------------------------------
-- Retroactive attribution and roster removal
--------------------------------------------------------------------------------

tests["records written before a character joined an entry resolve to its nickname"] = function()
    local db = {
        [AUG_05] = { [OMNIVICENT] = PRESENT },
        [AUG_03] = { [NIVEN] = PRESENT },
        [JUL_31] = { [NIVEN] = LATE },
    }
    local entries = { entry(HURRICANE, OMNIVICENT, NIVEN) }

    local report = Report:Build(db, entries)
    local hurricane = rowNamed(report.players, HURRICANE)

    assertTableEquals(hurricane.statuses, {
        [AUG_05] = PRESENT,
        [AUG_03] = PRESENT,
        [JUL_31] = LATE,
    }, "adding the character to the entry attributes its historical days at read time")
    assertEquals(#report.unrostered, 0,
        "the newly claimed character stops standing alone without its records being rewritten")
end

tests["a character transferred under a new name keeps its history through the old one"] = function()
    local db = {
        [AUG_05] = { [ZEPHYRA] = PRESENT },
        [AUG_03] = { [OMNIVICENT] = PRESENT },
    }
    local entries = { entry(HURRICANE, ZEPHYRA, OMNIVICENT) }

    local report = Report:Build(db, entries)

    assertEquals(Report:ResolveStatus(db, AUG_03, entries[1].characters), PRESENT)
    assertEquals(rowNamed(report.players, HURRICANE).percentage, 100,
        "keeping the old name listed preserves the rollup of records written under it")
end

tests["a player removed from the roster reverts to raw character names"] = function()
    local db = {
        [AUG_05] = { [OMNIVICENT] = PRESENT, [ELSIE] = PRESENT },
        [AUG_03] = { [NIVEN] = LATE, [ELSIE] = PRESENT },
    }
    local entries = rosterBeforeRemoval()
    table.remove(entries, 1)

    local report = Report:Build(db, entries)

    assertNil(rowNamed(report.players, HURRICANE), "the removed entry is no longer a row")
    assertTableEquals(namesOf(report.unrostered), { NIVEN, OMNIVICENT },
        "the removed player's characters revert to raw names")
    assertNil(rowNamed(report.unrostered, OMNIVICENT).percentage)
    assertTableEquals(rowNamed(report.unrostered, OMNIVICENT).statuses, { [AUG_05] = PRESENT },
        "their historical records are untouched by the removal")
end

tests["a pull after a roster removal writes no Missing record for the removed player"] = function()
    local entries = rosterBeforeRemoval()
    table.remove(entries, 1)

    withAttendanceStore(AUGUST_5_2026_AT_2000, function()
        PurplexityRaidToolsAttendanceDB[JUL_31] = { [OMNIVICENT] = PRESENT, [ELSIE] = PRESENT }
        PurplexityRaidToolsRosterDB = rosterBeforeRemoval()

        Store:OnCountdownStart({ ELSIE }, entries, 6)

        local day = Store:GetRaidDay(6)
        assertTableEquals(PurplexityRaidToolsAttendanceDB[day],
            { [ELSIE] = { status = PRESENT, gearSnapshotTaken = true } },
            "a removed player is no longer Missing-filled, however much history they have")
        assertTableEquals(PurplexityRaidToolsAttendanceDB[JUL_31],
            { [OMNIVICENT] = PRESENT, [ELSIE] = PRESENT },
            "their historical records survive the removal untouched")
    end)
end

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

tests["building a report leaves the attendance database deep-equal"] = function()
    local db = reportDB()
    local before = CopyTable(db)

    Report:Build(db, reportRoster())

    assertTableEquals(db, before, "resolution happens at read time and persists nothing")
end

tests["building a report leaves the roster entries deep-equal"] = function()
    local entries = reportRoster()
    local before = CopyTable(entries)

    Report:Build(reportDB(), entries)

    assertTableEquals(entries, before)
end

tests["resolving and percentages leave both inputs deep-equal"] = function()
    local db = reportDB()
    local entries = reportRoster()
    local dbBefore, entriesBefore = CopyTable(db), CopyTable(entries)

    Report:ResolveStatus(db, AUG_05, entryNamed(entries, HURRICANE).characters)
    Report:GetPercentage(db, EIGHT_DAYS, entryNamed(entries, HURRICANE).characters)

    assertTableEquals(db, dbBefore)
    assertTableEquals(entries, entriesBefore)
end

tests["a report row carries its own character list, not the roster entry's array"] = function()
    local entries = reportRoster()

    local report = Report:Build(reportDB(), entries)

    assertFalse(rowNamed(report.players, HURRICANE).characters == entryNamed(entries, HURRICANE).characters,
        "a row handed the entry's own array lets the view mutate the roster")
    assertTableEquals(rowNamed(report.players, HURRICANE).characters, { OMNIVICENT, NIVEN })
end

tests["gear history keeps character changes separate and leaves unmeasured days empty"] = function()
    local days = { AUG_05, AUG_03, JUL_31, JUL_29 }
    local db = {
        [JUL_29] = { [OMNIVICENT] = { status = PRESENT, itemLevel = 100 } },
        [JUL_31] = { [NIVEN] = { status = PRESENT, itemLevel = 900 } },
        [AUG_03] = { [OMNIVICENT] = { status = PRESENT } },
        [AUG_05] = { [OMNIVICENT] = { status = LATE, itemLevel = 112.5,
            missingEnchants = { [11] = 1 }, missingGems = { [2] = 2 } } },
    }
    local history = Report:GetCharacterHistory(db, days, OMNIVICENT)
    assertEquals(history.first.day, JUL_29)
    assertEquals(history.last.day, AUG_05)
    assertEquals(history.change, 12.5)
    assertEquals(history.measuredDays, 2)
    assertNil(history.observations[2].itemLevel)
    assertNil(history.observations[2].status)
    assertEquals(history.observations[3].status, PRESENT)
    assertNil(history.observations[3].itemLevel)
    assertTableEquals(history.last.missingGems, { [2] = 2 })
    assertEquals(Report:GetCharacterHistory(db, days, NIVEN).last.itemLevel, 900)
end

tests["gear summary retains the last measured date and does not invent zero changes"] = function()
    local db = { [AUG_03] = { [NIVEN] = { status = PRESENT, itemLevel = 120 } },
        [AUG_05] = { [NIVEN] = { status = ABSENT }, [ELSIE] = { status = PRESENT } } }
    local days = { AUG_05, AUG_03 }
    local history = Report:GetCharacterHistory(db, days, NIVEN)
    assertEquals(history.last.day, AUG_03)
    assertNil(history.change)
    local unknown = Report:GetCharacterHistory(db, days, ELSIE)
    assertNil(unknown.last)
    assertEquals(unknown.measuredDays, 0)
    local attended, recorded = Report:GetAttendanceCounts({ [AUG_03] = PRESENT, [AUG_05] = STANDBY })
    assertEquals(attended, 2)
    assertEquals(recorded, 2)
end

tests["latest item level follows measurement dates across characters instead of roster order"] = function()
    local db = {
        [JUL_29] = { ["Qixt-Realm"] = { status = PRESENT, itemLevel = 120 } },
        [AUG_03] = { ["Qixt-Realm"] = { status = MISSING },
            ["Kixt-Realm"] = { status = LATE, itemLevel = 110 } },
        [AUG_05] = { ["Qixt-Realm"] = { status = PRESENT, gearSnapshotTaken = true } },
    }
    local days = { AUG_05, AUG_03, JUL_29 }
    local before = CopyTable(db)
    for _, characters in ipairs({ { "Qixt-Realm", "Kixt-Realm" }, { "Kixt-Realm", "Qixt-Realm" } }) do
        local level, character = Report:GetLatestItemLevel(db, days, characters)
        assertEquals(level, 110)
        assertEquals(character, "Kixt-Realm")
    end
    assertTableEquals(db, before)
end

tests["latest item level ignores invalid measurements and does not invent missing data"] = function()
    local characters = { OMNIVICENT, NIVEN }
    local db = {
        [AUG_03] = { [NIVEN] = { status = PRESENT, itemLevel = 100 } },
        [AUG_05] = { [OMNIVICENT] = { status = PRESENT, itemLevel = math.huge },
            [NIVEN] = { status = PRESENT, itemLevel = 0 } },
    }
    local days = { AUG_05, AUG_03 }
    local level, character = Report:GetLatestItemLevel(db, days, characters)
    assertEquals(level, 100)
    assertEquals(character, NIVEN)
    db[AUG_03] = nil
    level, character = Report:GetLatestItemLevel(db, days, characters)
    assertNil(level)
    assertNil(character)
end

tests["same-day item-level measurements resolve consistently when roster characters are reordered"] = function()
    local db = { [AUG_05] = { [OMNIVICENT] = { status = PRESENT, itemLevel = 110 },
        [NIVEN] = { status = PRESENT, itemLevel = 100 } } }
    local level, character = Report:GetLatestItemLevel(db, { AUG_05 }, { OMNIVICENT, NIVEN })
    local reorderedLevel, reorderedCharacter = Report:GetLatestItemLevel(db, { AUG_05 }, { NIVEN, OMNIVICENT })
    assertEquals(level, reorderedLevel)
    assertEquals(character, reorderedCharacter)
end

return tests
