-- tests/test_attendance_store.lua
-- Exercises the attendance store (spec 2026-08-05-attendance-tracking:
-- "Automatic Recording", "Manual Recording", "Expiration").

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals
--
-- WoW's Lua environment has no os library, so the implementation must call the
-- globals date() and time(). Alias them here (never into wow_stubs.lua),
-- mirroring how test_comms.lua supplies strmatch.
--------------------------------------------------------------------------------

if date == nil then
    date = os.date
end

if time == nil then
    time = os.time
end

-- os.time reads the table as local time and os.date converts back to local
-- time, so fixtures round-trip identically in any timezone.
local function serverTimeAt(year, month, day, hour)
    return os.time({ year = year, month = month, day = day, hour = hour, min = 0, sec = 0 })
end

local PULL_TIME = serverTimeAt(2026, 8, 5, 20)
local PULL_DAY = "2026-08-05"

local EXPIRY_NOON = serverTimeAt(2026, 8, 5, 12)
local EXACTLY_90_DAYS_OLD = "2026-05-07"
local NINETY_ONE_DAYS_OLD = "2026-05-06"

if GetServerTime == nil then
    GetServerTime = function()
        return PULL_TIME
    end
end

dofile("Modules/Attendance/AttendanceStore.lua")

local PRT = PurplexityRaidTools
local Store = PRT.AttendanceStore

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

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

local function atServerTime(timestamp, body)
    withGlobals({ GetServerTime = function() return timestamp end }, body)
end

local function resetDB()
    PurplexityRaidToolsAttendanceDB = {}
    return PurplexityRaidToolsAttendanceDB
end

local function rosterEntry(nickname, ...)
    return { nickname = nickname, characters = { ... } }
end

--------------------------------------------------------------------------------
-- Load contract
--------------------------------------------------------------------------------

tests["the store loads headless with no frame or timer API available"] = function()
    assertNil(rawget(_G, "CreateFrame"),
        "wow_stubs must not provide CreateFrame, so a frame dependency fails loudly")
    assertNil(rawget(_G, "C_Timer"),
        "wow_stubs must not provide C_Timer, so a timer dependency fails loudly")
    assertNotNil(Store, "PurplexityRaidTools.AttendanceStore must exist after load")
end

tests["the status enum exposes the spec's integer values"] = function()
    assertEquals(Store.STATUS.MISSING, 0)
    assertEquals(Store.STATUS.ABSENT, 1)
    assertEquals(Store.STATUS.LATE, 2)
    assertEquals(Store.STATUS.PRESENT, 3)
end

tests["no store operation reads addon settings"] = function()
    resetDB()
    local savedGetSetting = PRT.GetSetting
    PRT.GetSetting = function()
        error("the attendance store must take settings as parameters, never read PRT:GetSetting", 0)
    end

    local ok, err = pcall(function()
        Store:GetRaidDay(6)
        Store:OnCountdownStart({ "Elsie-Proudmoore" },
            { rosterEntry("Niv", "Omnivicent-Proudmoore") }, 6)
        Store:OnCountdownCancel({ "Elsie-Proudmoore" }, {}, 6)
        Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", 1)
        Store:ExpireOldDays(90)
        Store:DeleteDay(PULL_DAY)
    end)

    PRT.GetSetting = savedGetSetting
    assertTrue(ok, tostring(err))
end

tests["a server time before the rollover hour resolves to the previous calendar date"] = function()
    atServerTime(serverTimeAt(2026, 8, 5, 3), function()
        assertEquals(Store:GetRaidDay(6), "2026-08-04")
    end)
end

tests["a server time exactly at the rollover hour resolves to the current calendar date"] = function()
    atServerTime(serverTimeAt(2026, 8, 5, 6), function()
        assertEquals(Store:GetRaidDay(6), "2026-08-05")
    end)
end

tests["a server time after the rollover hour resolves to the current calendar date"] = function()
    atServerTime(serverTimeAt(2026, 8, 5, 23), function()
        assertEquals(Store:GetRaidDay(6), "2026-08-05")
    end)
end

tests["a pre-rollover server time steps back across a month boundary"] = function()
    atServerTime(serverTimeAt(2026, 8, 1, 0), function()
        assertEquals(Store:GetRaidDay(6), "2026-07-31")
    end)
end

tests["a pre-rollover server time steps back across a year boundary"] = function()
    atServerTime(serverTimeAt(2026, 1, 1, 2), function()
        assertEquals(Store:GetRaidDay(6), "2025-12-31")
    end)
end

tests["the rollover hour parameter is honoured rather than fixed at 6"] = function()
    atServerTime(serverTimeAt(2026, 8, 5, 5), function()
        assertEquals(Store:GetRaidDay(4), "2026-08-05",
            "05:00 is after a rollover hour of 4, so the pull belongs to the current date")
        assertEquals(Store:GetRaidDay(6), "2026-08-04",
            "the same timestamp is before a rollover hour of 6")
    end)
end

tests["the rollover hour defaults to 6 when none is supplied"] = function()
    atServerTime(serverTimeAt(2026, 8, 5, 5), function()
        assertEquals(Store:GetRaidDay(), "2026-08-04")
    end)
    atServerTime(serverTimeAt(2026, 8, 5, 6), function()
        assertEquals(Store:GetRaidDay(), "2026-08-05")
    end)
end

tests["a first pull creates the day and records every group character Present"] = function()
    local db = resetDB()

    Store:OnCountdownStart({
        "Omnivicent-Proudmoore",
        "Elsie-Proudmoore",
        "Grimgrace-Proudmoore",
    }, {}, 6)

    assertNotNil(db[PULL_DAY], "the first pull must create the raid day's record")
    assertTableEquals(db[PULL_DAY], {
        ["Omnivicent-Proudmoore"] = 3,
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 3,
    })
end

tests["a first pull creates the database when the SavedVariable is nil"] = function()
    PurplexityRaidToolsAttendanceDB = nil

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6)

    local created = PurplexityRaidToolsAttendanceDB
    resetDB()

    assertNotNil(created, "the store must create the SavedVariable table on first use")
    assertEquals(created[PULL_DAY]["Elsie-Proudmoore"], 3)
end

tests["a later pull records a group character with no record for the day as Late"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(db[PULL_DAY]["Grimgrace-Proudmoore"], 2,
        "a character arriving after the first pull is Late")
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 3)
end

tests["a later pull leaves existing non-Missing statuses unchanged"] = function()
    local db = resetDB()
    db[PULL_DAY] = {
        ["Absentee-Proudmoore"] = 1,
        ["Latecomer-Proudmoore"] = 2,
        ["Elsie-Proudmoore"] = 3,
    }

    Store:OnCountdownStart({
        "Absentee-Proudmoore",
        "Latecomer-Proudmoore",
        "Elsie-Proudmoore",
    }, {}, 6)

    assertTableEquals(db[PULL_DAY], {
        ["Absentee-Proudmoore"] = 1,
        ["Latecomer-Proudmoore"] = 2,
        ["Elsie-Proudmoore"] = 3,
    })
end

tests["a later pull upgrades a group character's Missing record to Late"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3, ["Grimgrace-Proudmoore"] = 0 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(db[PULL_DAY]["Grimgrace-Proudmoore"], 2,
        "presence at a pull outranks a Missing record")
end

tests["a Missing written manually is upgraded to Late by a later pull"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok = Store:SetStatus(PULL_DAY, "Grimgrace-Proudmoore", 0)
    assertTrue(ok, "the manual Missing write must succeed on an existing day")

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(db[PULL_DAY]["Grimgrace-Proudmoore"], 2,
        "a Missing is upgraded regardless of how it was written")
end

tests["a pull records Missing against the first character of an unrecorded roster member"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {
        rosterEntry("Elsie", "Elsie-Proudmoore"),
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
    }, 6)

    assertEquals(db[PULL_DAY]["Omnivicent-Proudmoore"], 0,
        "the absent roster member is Missing-filled on their primary character")
    assertNil(db[PULL_DAY]["Niven-Proudmoore"],
        "only the first-listed character receives the Missing fill")
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 3,
        "a roster member who is in the group is not Missing-filled")
end

tests["a later pull Missing-fills a roster member who still has no record for the day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {
        rosterEntry("Elsie", "Elsie-Proudmoore"),
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
    }, 6)

    assertEquals(db[PULL_DAY]["Omnivicent-Proudmoore"], 0,
        "the Missing fill runs on every pull, not only the one that creates the day")
    assertNil(db[PULL_DAY]["Niven-Proudmoore"],
        "only the first-listed character receives the Missing fill")
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 3)
end

tests["a roster member recorded on a non-primary character is not Missing-filled"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Niven-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Niven-Proudmoore" }, {
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
    }, 6)

    assertNil(db[PULL_DAY]["Omnivicent-Proudmoore"],
        "a record on any of the entry's characters suppresses the Missing fill")
    assertEquals(db[PULL_DAY]["Niven-Proudmoore"], 3)
end

tests["a group character on no roster entry is recorded under its raw name-realm"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Randopug-Stormrage" }, {
        rosterEntry("Elsie", "Elsie-Proudmoore"),
    }, 6)

    assertEquals(db[PULL_DAY]["Randopug-Stormrage"], 3,
        "an un-rostered character is recorded under its own full name-realm")
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 0)
end

tests["a Missing-filled player arriving on another character records Late and keeps the Missing"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Omnivicent-Proudmoore"] = 0, ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Niven-Proudmoore" }, {
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
        rosterEntry("Elsie", "Elsie-Proudmoore"),
    }, 6)

    assertEquals(db[PULL_DAY]["Omnivicent-Proudmoore"], 0,
        "only a character at the pull is upgraded, never the rest of the player's entry")
    assertEquals(db[PULL_DAY]["Niven-Proudmoore"], 2,
        "the character that showed up records Late on its own record")
end

tests["an Absent player arriving on another character records Late and keeps the Absent record"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Omnivicent-Proudmoore"] = 1, ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Niven-Proudmoore" }, {
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
        rosterEntry("Elsie", "Elsie-Proudmoore"),
    }, 6)

    assertEquals(db[PULL_DAY]["Omnivicent-Proudmoore"], 1,
        "the Absent record stays on the character it was written against")
    assertEquals(db[PULL_DAY]["Niven-Proudmoore"], 2,
        "the arriving character records Late on its own record")
end

tests["a pull with no roster records the group and fills no Missing rows"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, nil, 6)

    assertTableEquals(db[PULL_DAY], { ["Elsie-Proudmoore"] = 3 })
end

tests["the countdown-cancel handler changes nothing after a countdown start"] = function()
    local db = resetDB()
    local roster = { rosterEntry("Niv", "Omnivicent-Proudmoore") }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, roster, 6)
    local recorded = CopyTable(db)

    Store:OnCountdownCancel({
        "Elsie-Proudmoore",
        "Grimgrace-Proudmoore",
        "Newcomer-Proudmoore",
    }, roster, 6)

    assertNil(db[PULL_DAY]["Newcomer-Proudmoore"],
        "cancelling must not record anyone")
    assertTableEquals(db, recorded,
        "the records written by the countdown start survive the cancellation intact")
end

tests["a countdown cancel with no prior pull creates no day record"] = function()
    local db = resetDB()

    Store:OnCountdownCancel({ "Elsie-Proudmoore" },
        { rosterEntry("Niv", "Omnivicent-Proudmoore") }, 6)

    assertNil(db[PULL_DAY], "a cancellation alone never creates a day")
    assertTableEquals(db, {})
end

tests["a manual status write on an existing day persists the written value"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", 1)

    assertTrue(ok)
    assertNil(err)
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 1)
end

tests["a manual status write creates a character record within an existing day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:SetStatus(PULL_DAY, "Grimgrace-Proudmoore", 1)

    assertTrue(ok)
    assertNil(err)
    assertTableEquals(db[PULL_DAY], {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 1,
    })
end

tests["a manual status write for a day with no record is rejected and creates nothing"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:SetStatus("2026-08-03", "Elsie-Proudmoore", 1)

    assertFalse(ok, "a day record is created only by a first pull")
    assertEquals(type(err), "string", "a rejected write must explain itself")
    assertNil(db["2026-08-03"], "the rejected write must not create the day")
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = 3 } })
end

tests["a manual status write against an empty database creates no day"] = function()
    local db = resetDB()

    local ok = Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", 3)

    assertFalse(ok)
    assertTableEquals(db, {})
end

tests["the expiry routine deletes a day older than the threshold"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    atServerTime(EXPIRY_NOON, function()
        Store:ExpireOldDays(90)
    end)

    assertNil(db[NINETY_ONE_DAYS_OLD],
        "a day 91 days old is past a 90-day threshold and is pruned")
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = 3 } })
end

tests["the expiry routine retains a day exactly at the threshold age"] = function()
    local db = resetDB()
    db[EXACTLY_90_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3, ["Grimgrace-Proudmoore"] = 0 }

    atServerTime(EXPIRY_NOON, function()
        Store:ExpireOldDays(90)
    end)

    assertTableEquals(db[EXACTLY_90_DAYS_OLD], {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 0,
    }, "a day exactly at the threshold age is retained intact")
end

tests["the expiry threshold defaults to 90 days when none is supplied"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }
    db[EXACTLY_90_DAYS_OLD] = { ["Grimgrace-Proudmoore"] = 3 }

    atServerTime(EXPIRY_NOON, function()
        Store:ExpireOldDays()
    end)

    assertNil(db[NINETY_ONE_DAYS_OLD])
    assertNotNil(db[EXACTLY_90_DAYS_OLD])
end

tests["the expiry routine tolerates a nil database"] = function()
    PurplexityRaidToolsAttendanceDB = nil

    local ok, err = pcall(function()
        atServerTime(EXPIRY_NOON, function()
            Store:ExpireOldDays(90)
        end)
    end)
    resetDB()

    assertTrue(ok, tostring(err))
end

tests["a manual delete removes only the named day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3, ["Grimgrace-Proudmoore"] = 2 }
    db["2026-08-03"] = { ["Elsie-Proudmoore"] = 1, ["Omnivicent-Proudmoore"] = 3 }
    db["2026-07-31"] = { ["Omnivicent-Proudmoore"] = 0 }

    local survivors = {
        ["2026-08-03"] = CopyTable(db["2026-08-03"]),
        ["2026-07-31"] = CopyTable(db["2026-07-31"]),
    }

    local ok = Store:DeleteDay(PULL_DAY)

    assertTrue(ok)
    assertNil(db[PULL_DAY])
    assertTableEquals(db, survivors, "every other day is deep-equal to its prior contents")
end

tests["a manual delete of a day with no record returns false and changes nothing"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok = Store:DeleteDay("2026-08-03")

    assertFalse(ok)
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = 3 } })
end

return tests
