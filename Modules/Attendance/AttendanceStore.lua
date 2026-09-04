-- AttendanceStore: pull-driven attendance records, stored as
-- PurplexityRaidToolsAttendanceDB[raidDay]["Name-Realm"] = { status, itemLevel }.
--
-- Every day key is derived from the realm's CalendarTime. This keeps one raid
-- night on the same day for players in different client timezones.
--
-- Headless-load safety: no frame, timer, or event API is touched at load, so the
-- store loads under the test harness; the wiring layer owns the countdown events.
-- The rollover hour and expiry threshold arrive as parameters rather than through
-- PRT:GetSetting, keeping account-wide records independent of the profile system.

local PRT = PurplexityRaidTools
local AttendanceStore = {}
PRT.AttendanceStore = AttendanceStore

local STATUS = {
    MISSING = 0,
    ABSENT = 1,
    LATE = 2,
    PRESENT = 3,
    STANDBY = 4,
}
AttendanceStore.STATUS = STATUS

local SCHEMA_VERSION = 2
AttendanceStore.SCHEMA_VERSION = SCHEMA_VERSION

local VALID_STATUSES = {}
for _, status in pairs(STATUS) do
    VALID_STATUSES[status] = true
end

local DEFAULT_ROLLOVER_HOUR = 6
local DEFAULT_EXPIRY_DAYS = 90

local function RaidDayCalendarTime(rolloverHour, previousDays)
    local current = C_DateAndTime.GetCurrentCalendarTime()
    local dayOffset = -(previousDays or 0)
    if current.hour < rolloverHour then
        dayOffset = dayOffset - 1
    end
    if dayOffset == 0 then
        return current
    end

    return C_DateAndTime.AdjustTimeByDays(current, dayOffset)
end

local function CalendarDayKey(calendarTime)
    return string.format("%04d-%02d-%02d",
        calendarTime.year, calendarTime.month, calendarTime.monthDay)
end

local function EnsureDB()
    PurplexityRaidToolsAttendanceDB = PurplexityRaidToolsAttendanceDB or {}
    return PurplexityRaidToolsAttendanceDB
end

local function IsItemLevel(itemLevel)
    return type(itemLevel) == "number" and itemLevel == itemLevel
        and itemLevel > 0 and itemLevel < math.huge
end

local function NewRecord(status, itemLevel)
    local record = { status = status }
    if IsItemLevel(itemLevel) then
        record.itemLevel = itemLevel
    end
    return record
end

function AttendanceStore.GetStatus(record)
    if type(record) == "table" then
        return record.status
    end
    return record
end

function AttendanceStore.GetItemLevel(record)
    if type(record) == "table" and IsItemLevel(record.itemLevel) then
        return record.itemLevel
    end
    return nil
end

local function UpdateItemLevel(record, itemLevel)
    if type(record) == "table" and IsItemLevel(itemLevel) then
        record.itemLevel = itemLevel
    end
end

function AttendanceStore:MigrateDatabase()
    PurplexityRaidToolsDB = PurplexityRaidToolsDB or {}
    local version = PurplexityRaidToolsDB.attendanceSchemaVersion
    if version == SCHEMA_VERSION or type(version) == "number" and version > SCHEMA_VERSION then
        return false
    end

    local db = EnsureDB()
    for _, dayRecord in pairs(db) do
        if type(dayRecord) == "table" then
            for character, record in pairs(dayRecord) do
                if type(record) == "number" then
                    dayRecord[character] = NewRecord(record)
                end
            end
        end
    end

    PurplexityRaidToolsDB.attendanceSchemaVersion = SCHEMA_VERSION
    return true
end

local function AnyCharacterRecorded(dayRecord, characters)
    for i = 1, #characters do
        if dayRecord[characters[i]] ~= nil then
            return true
        end
    end
    return false
end

function AttendanceStore:GetRaidDay(rolloverHour)
    local raidDay = RaidDayCalendarTime(rolloverHour or DEFAULT_ROLLOVER_HOUR)
    return CalendarDayKey(raidDay)
end

function AttendanceStore:OnCountdownStart(group, roster, rolloverHour, itemLevels)
    local db = EnsureDB()
    local day = self:GetRaidDay(rolloverHour)

    local dayRecord = db[day]
    local isFirstPull = dayRecord == nil
    if isFirstPull then
        dayRecord = {}
        db[day] = dayRecord
    end

    local arrivalStatus = isFirstPull and STATUS.PRESENT or STATUS.LATE
    for i = 1, #group do
        local character = group[i]
        local recorded = dayRecord[character]
        if recorded == nil then
            recorded = NewRecord(arrivalStatus, itemLevels and itemLevels[character])
            dayRecord[character] = recorded
        elseif self.GetStatus(recorded) == STATUS.MISSING then
            if type(recorded) == "table" then
                recorded.status = STATUS.LATE
            else
                recorded = NewRecord(STATUS.LATE)
                dayRecord[character] = recorded
            end
        end
        UpdateItemLevel(recorded, itemLevels and itemLevels[character])
    end

    if not roster then
        return
    end

    for i = 1, #roster do
        local characters = roster[i].characters
        local primary = characters and characters[1]
        if primary and not AnyCharacterRecorded(dayRecord, characters) then
            dayRecord[primary] = NewRecord(STATUS.MISSING)
        end
    end
end

--- A cancelled countdown still counts as a pull: the snapshot was taken when the
--- countdown started, and cancelling is not an undo.
function AttendanceStore:OnCountdownCancel()
end

function AttendanceStore:SetStatus(day, character, status)
    if not VALID_STATUSES[status] then
        return false,
            "Attendance status must be 0, 1, 2, 3, or 4; got " .. tostring(status) .. "."
    end

    local db = PurplexityRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord then
        return false, "No attendance record exists for " .. tostring(day) .. "."
    end

    local record = dayRecord[character]
    if type(record) == "table" then
        record.status = status
    else
        dayRecord[character] = NewRecord(status)
    end
    return true
end

function AttendanceStore:DeleteStatus(day, character)
    local db = PurplexityRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord or dayRecord[character] == nil then
        return false, "No attendance record exists for " .. tostring(character)
            .. " on " .. tostring(day) .. "."
    end

    dayRecord[character] = nil
    if next(dayRecord) == nil then
        db[day] = nil
    end
    return true
end

function AttendanceStore:ExpireOldDays(thresholdDays, rolloverHour)
    local db = PurplexityRaidToolsAttendanceDB
    if not db then
        return
    end

    local oldestRetained = RaidDayCalendarTime(
        rolloverHour or DEFAULT_ROLLOVER_HOUR,
        thresholdDays or DEFAULT_EXPIRY_DAYS)
    local oldestRetainedDay = CalendarDayKey(oldestRetained)

    for day in pairs(db) do
        if day < oldestRetainedDay then
            db[day] = nil
        end
    end
end

function AttendanceStore:DeleteDay(day)
    local db = PurplexityRaidToolsAttendanceDB
    if not db or not db[day] then
        return false
    end

    db[day] = nil
    return true
end
