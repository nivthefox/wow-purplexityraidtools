-- tests/test_attendance_store.lua
-- Exercises the attendance store (spec 2026-08-05-attendance-tracking:
-- "Automatic Recording", "Manual Recording", "Expiration").

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals
--
-- The spec requires every client to agree on which day a pull belongs to, so the
-- store reads the realm CalendarTime rather than the client's local clock.
--------------------------------------------------------------------------------

if date == nil then
    date = os.date
end

local HOUR = 3600
local DAY = 86400

local AUGUST_5_2026 = 1785888000
local JANUARY_1_2026 = 1767225600
local AUGUST_1_2026 = AUGUST_5_2026 - 4 * DAY

local PULL_TIME = AUGUST_5_2026 + 20 * HOUR
local PULL_DAY = "2026-08-05"

local EXPIRY_MIDDAY = AUGUST_5_2026 + 12 * HOUR
local EXPIRY_BEFORE_ROLLOVER = AUGUST_5_2026 + 3 * HOUR
local EXACTLY_90_DAYS_OLD = "2026-05-07"
local NINETY_ONE_DAYS_OLD = "2026-05-06"

local function calendarTimeAt(timestamp)
    local value = os.date("!*t", timestamp)
    return {
        year = value.year,
        month = value.month,
        monthDay = value.day,
        weekday = value.wday,
        hour = value.hour,
        minute = value.min,
    }
end

if C_DateAndTime == nil then
    C_DateAndTime = {}
end

if C_DateAndTime.GetCurrentCalendarTime == nil then
    C_DateAndTime.GetCurrentCalendarTime = function()
        return calendarTimeAt(PULL_TIME)
    end
end

if C_DateAndTime.AdjustTimeByDays == nil then
    C_DateAndTime.AdjustTimeByDays = function(_, days)
        return calendarTimeAt(PULL_TIME + days * DAY)
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
    local savedCurrent = C_DateAndTime.GetCurrentCalendarTime
    local savedAdjust = C_DateAndTime.AdjustTimeByDays
    C_DateAndTime.GetCurrentCalendarTime = function()
        return calendarTimeAt(timestamp)
    end
    C_DateAndTime.AdjustTimeByDays = function(_, days)
        return calendarTimeAt(timestamp + days * DAY)
    end
    local ok, err = pcall(body)
    C_DateAndTime.GetCurrentCalendarTime = savedCurrent
    C_DateAndTime.AdjustTimeByDays = savedAdjust
    if not ok then
        error(err, 0)
    end
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
    assertEquals(Store.STATUS.STANDBY, 4)
end

tests["the fixture epochs are the UTC instants they are named for"] = function()
    assertEquals(date("!%Y-%m-%d %H:%M:%S", AUGUST_5_2026), "2026-08-05 00:00:00")
    assertEquals(date("!%Y-%m-%d %H:%M:%S", AUGUST_1_2026), "2026-08-01 00:00:00")
    assertEquals(date("!%Y-%m-%d %H:%M:%S", JANUARY_1_2026), "2026-01-01 00:00:00")
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
        Store:DeleteStatus(PULL_DAY, "Elsie-Proudmoore")
        Store:ExpireOldDays(90, 6)
        Store:DeleteDay(PULL_DAY)
    end)

    PRT.GetSetting = savedGetSetting
    assertTrue(ok, tostring(err))
end

tests["no store operation reads the client-frame GetServerTime"] = function()
    resetDB()

    local ok, err = pcall(function()
        withGlobals({
            GetServerTime = function()
                error("the store must read realm CalendarTime, not GetServerTime()", 0)
            end,
        }, function()
            Store:GetRaidDay(6)
            Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6)
            Store:ExpireOldDays(90, 6)
        end)
    end)

    assertTrue(ok, tostring(err))
end

tests["the raid day key is derived in the server frame, not the client's timezone"] = function()
    atServerTime(AUGUST_5_2026 + 5 * HOUR + 30 * 60, function()
        assertEquals(Store:GetRaidDay(6), "2026-08-04",
            "05:30 server time is before the rollover hour wherever the client sits")
    end)
    atServerTime(AUGUST_5_2026 + 6 * HOUR + 30 * 60, function()
        assertEquals(Store:GetRaidDay(6), "2026-08-05",
            "06:30 server time is after the rollover hour wherever the client sits")
    end)
end

tests["day keys do not depend on the global date formatter"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    withGlobals({
        date = function()
            error("attendance day keys must not call date()", 0)
        end,
    }, function()
        Store:GetRaidDay(6)
        Store:ExpireOldDays(90, 6)
    end)
end

tests["day calculation and expiry do not depend on date returning a string"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }
    db[EXACTLY_90_DAYS_OLD] = { ["Grimgrace-Proudmoore"] = 3 }

    withGlobals({
        date = function()
            return nil
        end,
        C_DateAndTime = {
            GetCurrentCalendarTime = function()
                return { year = 2026, month = 8, monthDay = 5, hour = 12, minute = 0 }
            end,
            AdjustTimeByDays = function(_, days)
                if days == 0 then
                    return { year = 2026, month = 8, monthDay = 5, hour = 12, minute = 0 }
                end
                if days == -90 then
                    return { year = 2026, month = 5, monthDay = 7, hour = 12, minute = 0 }
                end
                error("unexpected day adjustment: " .. tostring(days), 0)
            end,
        },
    }, function()
        Store:ExpireOldDays(90, 6)
        assertEquals(Store:GetRaidDay(6), PULL_DAY)
    end)

    assertNil(db[NINETY_ONE_DAYS_OLD])
    assertNotNil(db[EXACTLY_90_DAYS_OLD])
end

tests["a server time before the rollover hour resolves to the previous calendar date"] = function()
    atServerTime(AUGUST_5_2026 + 3 * HOUR, function()
        assertEquals(Store:GetRaidDay(6), "2026-08-04")
    end)
end

tests["a server time exactly at the rollover hour resolves to the current calendar date"] = function()
    atServerTime(AUGUST_5_2026 + 6 * HOUR, function()
        assertEquals(Store:GetRaidDay(6), "2026-08-05")
    end)
end

tests["a server time after the rollover hour resolves to the current calendar date"] = function()
    atServerTime(AUGUST_5_2026 + 23 * HOUR, function()
        assertEquals(Store:GetRaidDay(6), "2026-08-05")
    end)
end

tests["a pre-rollover server time steps back across a month boundary"] = function()
    atServerTime(AUGUST_1_2026, function()
        assertEquals(Store:GetRaidDay(6), "2026-07-31")
    end)
end

tests["a pre-rollover server time steps back across a year boundary"] = function()
    atServerTime(JANUARY_1_2026 + 2 * HOUR, function()
        assertEquals(Store:GetRaidDay(6), "2025-12-31")
    end)
end

tests["the rollover hour parameter is honoured rather than fixed at 6"] = function()
    atServerTime(AUGUST_5_2026 + 5 * HOUR, function()
        assertEquals(Store:GetRaidDay(4), "2026-08-05",
            "05:00 is after a rollover hour of 4, so the pull belongs to the current date")
        assertEquals(Store:GetRaidDay(6), "2026-08-04",
            "the same timestamp is before a rollover hour of 6")
    end)
end

tests["the rollover hour defaults to 6 when none is supplied"] = function()
    atServerTime(AUGUST_5_2026 + 5 * HOUR, function()
        assertEquals(Store:GetRaidDay(), "2026-08-04")
    end)
    atServerTime(AUGUST_5_2026 + 6 * HOUR, function()
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
        ["Omnivicent-Proudmoore"] = { status = 3, gearSnapshotTaken = true },
        ["Elsie-Proudmoore"] = { status = 3, gearSnapshotTaken = true },
        ["Grimgrace-Proudmoore"] = { status = 3, gearSnapshotTaken = true },
    })
end

tests["a first pull creates the database when the SavedVariable is nil"] = function()
    PurplexityRaidToolsAttendanceDB = nil

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6)

    local created = PurplexityRaidToolsAttendanceDB
    resetDB()

    assertNotNil(created, "the store must create the SavedVariable table on first use")
    assertTableEquals(created[PULL_DAY]["Elsie-Proudmoore"], { status = 3, gearSnapshotTaken = true })
end

tests["a later pull records a group character with no record for the day as Late"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Grimgrace-Proudmoore"]), 2,
        "a character arriving after the first pull is Late")
    assertEquals(Store.GetStatus(db[PULL_DAY]["Elsie-Proudmoore"]), 3)
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

tests["a later pull leaves a manually assigned Standby status unchanged"] = function()
    local db = resetDB()
    db[PULL_DAY] = {
        ["Elsie-Proudmoore"] = 3,
        ["Benchwarmer-Proudmoore"] = 4,
    }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Benchwarmer-Proudmoore" }, {}, 6)

    assertEquals(db[PULL_DAY]["Benchwarmer-Proudmoore"], 4)
end

tests["automated pull recording never assigns Standby"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {
        rosterEntry("Niv", "Elsie-Proudmoore"),
        rosterEntry("Benchwarmer", "Benchwarmer-Proudmoore"),
    }, 6)
    Store:OnCountdownStart({ "Elsie-Proudmoore", "Latecomer-Proudmoore" }, {}, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Elsie-Proudmoore"]), 3)
    assertEquals(Store.GetStatus(db[PULL_DAY]["Benchwarmer-Proudmoore"]), 0)
    assertEquals(Store.GetStatus(db[PULL_DAY]["Latecomer-Proudmoore"]), 2)
    for _, record in pairs(db[PULL_DAY]) do
        assertFalse(Store.GetStatus(record) == 4, "pull recording must not create Standby")
    end
end

tests["a later pull upgrades a group character's Missing record to Late"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3, ["Grimgrace-Proudmoore"] = 0 }

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Grimgrace-Proudmoore"]), 2,
        "presence at a pull outranks a Missing record")
end

tests["a Missing written manually is upgraded to Late by a later pull"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok = Store:SetStatus(PULL_DAY, "Grimgrace-Proudmoore", 0)
    assertTrue(ok, "the manual Missing write must succeed on an existing day")

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Grimgrace-Proudmoore"]), 2,
        "a Missing is upgraded regardless of how it was written")
end

tests["a pull records Missing against the first character of an unrecorded roster member"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {
        rosterEntry("Elsie", "Elsie-Proudmoore"),
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
    }, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Omnivicent-Proudmoore"]), 0,
        "the absent roster member is Missing-filled on their primary character")
    assertNil(db[PULL_DAY]["Niven-Proudmoore"],
        "only the first-listed character receives the Missing fill")
    assertEquals(Store.GetStatus(db[PULL_DAY]["Elsie-Proudmoore"]), 3,
        "a roster member who is in the group is not Missing-filled")
end

tests["a later pull Missing-fills a roster member who still has no record for the day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {
        rosterEntry("Elsie", "Elsie-Proudmoore"),
        rosterEntry("Niv", "Omnivicent-Proudmoore", "Niven-Proudmoore"),
    }, 6)

    assertEquals(Store.GetStatus(db[PULL_DAY]["Omnivicent-Proudmoore"]), 0,
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

    assertEquals(Store.GetStatus(db[PULL_DAY]["Randopug-Stormrage"]), 3,
        "an un-rostered character is recorded under its own full name-realm")
    assertEquals(Store.GetStatus(db[PULL_DAY]["Elsie-Proudmoore"]), 0)
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
    assertEquals(Store.GetStatus(db[PULL_DAY]["Niven-Proudmoore"]), 2,
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
    assertEquals(Store.GetStatus(db[PULL_DAY]["Niven-Proudmoore"]), 2,
        "the arriving character records Late on its own record")
end

tests["a pull with no roster records the group and fills no Missing rows"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, nil, 6)

    assertTableEquals(db[PULL_DAY], { ["Elsie-Proudmoore"] = { status = 3, gearSnapshotTaken = true } })
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
    assertTableEquals(db[PULL_DAY]["Elsie-Proudmoore"], { status = 1 })
end

tests["a manual status write creates a character record within an existing day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:SetStatus(PULL_DAY, "Grimgrace-Proudmoore", 1)

    assertTrue(ok)
    assertNil(err)
    assertTableEquals(db[PULL_DAY], {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = { status = 1 },
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

tests["every status in the enum is accepted by a manual write"] = function()
    local db = resetDB()
    db[PULL_DAY] = {}

    for _, status in ipairs({ 0, 1, 2, 3, 4 }) do
        local ok, err = Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", status)
        assertTrue(ok, "status " .. status .. " is a valid write")
        assertNil(err)
        assertEquals(Store.GetStatus(db[PULL_DAY]["Elsie-Proudmoore"]), status)
    end
end

tests["a manual status write outside the status enum is rejected and changes nothing"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    for _, status in ipairs({ 5, -1, 7, 1.5, "3", true }) do
        local ok, err = Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", status)
        assertFalse(ok, "a status outside the enum must be rejected: " .. tostring(status))
        assertEquals(type(err), "string", "a rejected write must explain itself")
        assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 3,
            "the existing record survives a rejected write")
    end
end

tests["a manual status write of nil is rejected and does not delete the record"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", nil)

    assertFalse(ok, "record deletion must use the dedicated operation")
    assertEquals(type(err), "string", "a rejected write must explain itself")
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], 3,
        "a nil status must never silently erase the character's record")
end

tests["deleting a character status preserves the other entries on that day"] = function()
    local db = resetDB()
    db[PULL_DAY] = {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 2,
    }

    local ok, err = Store:DeleteStatus(PULL_DAY, "Elsie-Proudmoore")

    assertTrue(ok)
    assertNil(err)
    assertTableEquals(db, {
        [PULL_DAY] = { ["Grimgrace-Proudmoore"] = 2 },
    })
end

tests["deleting the final character status removes the empty day"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:DeleteStatus(PULL_DAY, "Elsie-Proudmoore")

    assertTrue(ok)
    assertNil(err)
    assertTableEquals(db, {})
end

tests["deleting a missing character status changes nothing"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    local ok, err = Store:DeleteStatus(PULL_DAY, "Grimgrace-Proudmoore")

    assertFalse(ok)
    assertEquals(type(err), "string")
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = 3 } })
end

tests["deleting a character removes all their history and preserves other characters and gear"] = function()
    local db = resetDB()
    local survivor = { status = 2, itemLevel = 110, missingGems = { [2] = 1 } }
    db[PULL_DAY] = {
        ["Guest-Proudmoore"] = { status = 3, itemLevel = 105 },
        ["Elsie-Proudmoore"] = survivor,
    }
    db["2026-08-03"] = { ["Guest-Proudmoore"] = { status = 0 } }
    db["2026-07-31"] = { ["Guest-Proudmoore"] = 4, ["Guest-OtherRealm"] = { status = 3 } }

    local ok, err = Store:DeleteCharacter("Guest-Proudmoore")

    assertTrue(ok)
    assertNil(err)
    assertTableEquals(db, {
        [PULL_DAY] = { ["Elsie-Proudmoore"] = survivor },
        ["2026-07-31"] = { ["Guest-OtherRealm"] = { status = 3 } },
    })
    assertEquals(db[PULL_DAY]["Elsie-Proudmoore"], survivor)
end

tests["deleting a character with no history leaves the database unchanged"] = function()
    local db = resetDB()
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = { status = 3, itemLevel = 110 } }

    local ok, err = Store:DeleteCharacter("Guest-Proudmoore")

    assertFalse(ok)
    assertEquals(type(err), "string")
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = { status = 3, itemLevel = 110 } } })
end

tests["deleting a character before any attendance is recorded does not create a database"] = function()
    withGlobals({ PurplexityRaidToolsAttendanceDB = false }, function()
        PurplexityRaidToolsAttendanceDB = nil
        local ok, err = Store:DeleteCharacter("Guest-Proudmoore")
        assertFalse(ok)
        assertEquals(type(err), "string")
        assertNil(PurplexityRaidToolsAttendanceDB)
    end)
end

tests["the expiry routine deletes a day older than the threshold"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }
    db[PULL_DAY] = { ["Elsie-Proudmoore"] = 3 }

    atServerTime(EXPIRY_MIDDAY, function()
        Store:ExpireOldDays(90, 6)
    end)

    assertNil(db[NINETY_ONE_DAYS_OLD],
        "a day 91 days old is past a 90-day threshold and is pruned")
    assertTableEquals(db, { [PULL_DAY] = { ["Elsie-Proudmoore"] = 3 } })
end

tests["the expiry routine retains a day exactly at the threshold age"] = function()
    local db = resetDB()
    db[EXACTLY_90_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3, ["Grimgrace-Proudmoore"] = 0 }

    atServerTime(EXPIRY_MIDDAY, function()
        Store:ExpireOldDays(90, 6)
    end)

    assertTableEquals(db[EXACTLY_90_DAYS_OLD], {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 0,
    }, "a day exactly at the threshold age is retained intact")
end

tests["the expiry routine anchors its threshold on the raid day, not the calendar date"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }

    atServerTime(EXPIRY_BEFORE_ROLLOVER, function()
        Store:ExpireOldDays(90, 6)
    end)

    assertNotNil(db[NINETY_ONE_DAYS_OLD],
        "before the rollover hour the raid day is still the previous date, leaving this day exactly at the threshold")
end

tests["the expiry rollover hour defaults to 6 when none is supplied"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }

    atServerTime(EXPIRY_BEFORE_ROLLOVER, function()
        Store:ExpireOldDays(90)
    end)

    assertNotNil(db[NINETY_ONE_DAYS_OLD],
        "under the default rollover hour 03:00 still belongs to the previous raid day, leaving this day exactly at the threshold")
end

tests["the expiry threshold defaults to 90 days when none is supplied"] = function()
    local db = resetDB()
    db[NINETY_ONE_DAYS_OLD] = { ["Elsie-Proudmoore"] = 3 }
    db[EXACTLY_90_DAYS_OLD] = { ["Grimgrace-Proudmoore"] = 3 }

    atServerTime(EXPIRY_MIDDAY, function()
        Store:ExpireOldDays()
    end)

    assertNil(db[NINETY_ONE_DAYS_OLD])
    assertNotNil(db[EXACTLY_90_DAYS_OLD])
end

tests["the expiry routine tolerates a nil database"] = function()
    PurplexityRaidToolsAttendanceDB = nil

    local ok, err = pcall(function()
        atServerTime(EXPIRY_MIDDAY, function()
            Store:ExpireOldDays(90, 6)
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

tests["the schema migration preserves legacy days characters and statuses"] = function()
    local savedRoot = PurplexityRaidToolsDB
    local db = resetDB()
    PurplexityRaidToolsDB = {}
    db[PULL_DAY] = {
        ["Elsie-Proudmoore"] = 3,
        ["Grimgrace-Proudmoore"] = 0,
    }

    local ok, err = pcall(function()
        Store:MigrateDatabase()

        assertTableEquals(db[PULL_DAY], {
            ["Elsie-Proudmoore"] = { status = 3 },
            ["Grimgrace-Proudmoore"] = { status = 0 },
        })
        assertEquals(PurplexityRaidToolsDB.attendanceSchemaVersion,
            Store.SCHEMA_VERSION)

        local afterFirstMigration = CopyTable(db)
        Store:MigrateDatabase()
        assertTableEquals(db, afterFirstMigration, "the migration must be idempotent")
    end)

    PurplexityRaidToolsDB = savedRoot
    if not ok then
        error(err, 0)
    end
end

tests["the first attended pull snapshots the available item level without requiring one"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore", "Grimgrace-Proudmoore" }, {}, 6, {
        ["Elsie-Proudmoore"] = 712.5,
    })

    assertTableEquals(db[PULL_DAY], {
        ["Elsie-Proudmoore"] = { status = 3, itemLevel = 712.5, gearSnapshotTaken = true },
        ["Grimgrace-Proudmoore"] = { status = 3, gearSnapshotTaken = true },
    })
end

tests["later pulls never replace the arrival item level"] = function()
    local db = resetDB()

    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6, {
        ["Elsie-Proudmoore"] = 710,
    })
    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6, {
        ["Elsie-Proudmoore"] = 712.5,
    })
    Store:OnCountdownStart({ "Elsie-Proudmoore" }, {}, 6, {})

    assertTableEquals(db[PULL_DAY]["Elsie-Proudmoore"], {
        status = 3,
        itemLevel = 710,
        gearSnapshotTaken = true,
    })
end

tests["manual status changes preserve the recorded item level"] = function()
    local db = resetDB()
    db[PULL_DAY] = {
        ["Elsie-Proudmoore"] = { status = 3, itemLevel = 712.5 },
    }

    assertTrue(Store:SetStatus(PULL_DAY, "Elsie-Proudmoore", 1))

    assertTableEquals(db[PULL_DAY]["Elsie-Proudmoore"], {
        status = 1,
        itemLevel = 712.5,
    })
end

tests["arrival snapshots store only deficiencies and ignore gear fixed later that night"] = function()
    local db = resetDB()
    local name = "Elsie-Proudmoore"
    local audit = {
        enchants = { status = "unknown", missing = { { slot = 11, count = 1 } }, unknown = { 1 } },
        gems = { status = "missing", missing = { { slot = 2, count = 2 } }, unknown = {} },
    }
    Store:OnCountdownStart({ name }, {}, 6, { [name] = 100 }, { [name] = audit })
    assertTableEquals(db[PULL_DAY][name], { status = 3, itemLevel = 100, gearSnapshotTaken = true,
        missingEnchants = { [11] = 1 }, missingGems = { [2] = 2 } })
    audit.enchants.missing[1].slot = 12
    audit.gems.missing[1].count = 1
    local clean = { enchants = { missing = {}, unknown = {} }, gems = { missing = {}, unknown = {} } }
    Store:OnCountdownStart({ name }, {}, 6, { [name] = 110 }, { [name] = clean })
    assertTableEquals(db[PULL_DAY][name].missingEnchants, { [11] = 1 })
    assertTableEquals(db[PULL_DAY][name].missingGems, { [2] = 2 })
    assertEquals(db[PULL_DAY][name].itemLevel, 100)
end

tests["an unknown arrival snapshot stays unknown after later inspections and a manual Missing edit"] = function()
    local db = resetDB()
    local name = "Elsie-Proudmoore"
    Store:OnCountdownStart({ name }, {}, 6)
    Store:SetStatus(PULL_DAY, name, Store.STATUS.MISSING)
    Store:OnCountdownStart({ name }, {}, 6, { [name] = 123 }, {
        [name] = { enchants = { missing = { { slot = 5, count = 1 } } } },
    })
    assertTableEquals(db[PULL_DAY][name], { status = 2, gearSnapshotTaken = true })
end

tests["late arrivals snapshot their first attended pull and start fresh on the next raid day"] = function()
    local db = resetDB()
    local name = "Elsie-Proudmoore"
    Store:OnCountdownStart({ "Niven-Proudmoore" }, { rosterEntry("Elsie", name) }, 6)
    assertNil(db[PULL_DAY][name].gearSnapshotTaken)
    Store:OnCountdownStart({ name }, {}, 6, { [name] = 100 })
    assertEquals(db[PULL_DAY][name].status, 2)
    assertEquals(db[PULL_DAY][name].itemLevel, 100)
    atServerTime(PULL_TIME + DAY, function()
        Store:OnCountdownStart({ name }, {}, 6, { [name] = 110 })
        assertEquals(db[Store:GetRaidDay(6)][name].itemLevel, 110)
    end)
    assertEquals(db[PULL_DAY][name].itemLevel, 100)
end

tests["reloading the store preserves frozen snapshots including arrivals without measurements"] = function()
    local db = resetDB()
    local name = "Elsie-Proudmoore"
    Store:OnCountdownStart({ name }, {}, 6)
    local savedStore = PRT.AttendanceStore
    local ok, err = pcall(function()
        dofile("Modules/Attendance/AttendanceStore.lua")
        PRT.AttendanceStore:OnCountdownStart({ name }, {}, 6, { [name] = 999 })
        assertNil(db[PULL_DAY][name].itemLevel)
        assertTrue(db[PULL_DAY][name].gearSnapshotTaken)
    end)
    PRT.AttendanceStore = savedStore
    if not ok then error(err, 0) end
end

tests["record validation rejects full equipment and malformed missing-slot maps"] = function()
    local invalid = {
        { status = 3, equipment = {} },
        { status = 3, missingEnchants = { [5] = 2 } },
        { status = 3, missingGems = { [2] = 0 } },
        { status = 3, missingGems = { [4] = 1 } },
        { status = 3, missingGems = { [18] = 1 } },
        { status = 3, missingGems = { neck = 1 } },
        { status = 3, missingGems = { [2] = 0 / 0 } },
        { status = 3, gearSnapshotTaken = false },
    }
    for _, record in ipairs(invalid) do
        assertNil(Store.PrepareRecord(record))
    end
    assertTableEquals(Store.PrepareRecord({ status = 3, missingGems = {}, missingEnchants = {} }), { status = 3 })
end

return tests
