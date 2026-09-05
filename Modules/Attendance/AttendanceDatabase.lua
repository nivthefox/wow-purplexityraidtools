local PRT = PurplexityRaidTools
local AttendanceDatabase = {}
PRT.AttendanceDatabase = AttendanceDatabase

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local FORMAT_PREFIX = "PRTATTENDANCE:"
local FORMAT_VERSION = 2
local ISO_DAY_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

AttendanceDatabase.FORMAT_VERSION = FORMAT_VERSION

local function ClearTable(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CopyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copied = {}
    for key, child in pairs(value) do
        copied[key] = CopyTable(child)
    end
    return copied
end

local function IsValidDay(day)
    local year, month, dayOfMonth = day:match(ISO_DAY_PATTERN)
    year, month, dayOfMonth = tonumber(year), tonumber(month), tonumber(dayOfMonth)
    if not year or year < 1 or month < 1 or month > 12 then
        return false
    end

    local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and (year % 400 == 0 or year % 4 == 0 and year % 100 ~= 0) then
        daysInMonth[2] = 29
    end
    return dayOfMonth >= 1 and dayOfMonth <= daysInMonth[month]
end

local function PrepareAttendance(history)
    if type(history) ~= "table" then
        return nil, "The attendance history must be a table."
    end

    local prepared = {}
    local dayCount, recordCount = 0, 0
    for day, records in pairs(history) do
        if type(day) ~= "string" or not IsValidDay(day) then
            return nil, "The attendance history contains an invalid day."
        end
        if type(records) ~= "table" or next(records) == nil then
            return nil, "Attendance for " .. day .. " must contain at least one record."
        end

        local preparedRecords = {}
        for character, record in pairs(records) do
            if type(character) ~= "string" or character == "" then
                return nil, "Attendance for " .. day .. " contains an invalid character name."
            end
            local preparedRecord = PRT.AttendanceStore.PrepareRecord(record)
            if not preparedRecord then
                return nil, "Attendance for " .. day .. " contains an invalid record."
            end
            preparedRecords[character] = preparedRecord
            recordCount = recordCount + 1
        end
        prepared[day] = preparedRecords
        dayCount = dayCount + 1
    end

    return prepared, nil, dayCount, recordCount
end

local function CountRosterCharacters(entries)
    local count = 0
    for _, entry in ipairs(entries) do
        count = count + #entry.characters
    end
    return count
end

local function PreparePayload(payload)
    if type(payload) ~= "table" then
        return nil, "The attendance database payload is malformed."
    end
    for key in pairs(payload) do
        if key ~= "attendance" and key ~= "roster" then
            return nil, "The attendance database payload contains an unknown field."
        end
    end

    local attendance, attendanceError, dayCount, recordCount =
        PrepareAttendance(payload.attendance)
    if not attendance then
        return nil, attendanceError
    end

    local roster, rosterError = PRT.Roster:PrepareReplacement(payload.roster)
    if not roster then
        return nil, rosterError
    end

    return {
        attendance = attendance,
        roster = roster,
        summary = {
            days = dayCount,
            attendanceRecords = recordCount,
            rosterEntries = #roster,
            rosterCharacters = CountRosterCharacters(roster),
        },
    }
end

function AttendanceDatabase:Export()
    local serialized = LibSerialize:Serialize({
        attendance = PurplexityRaidToolsAttendanceDB or {},
        roster = PurplexityRaidToolsRosterDB or {},
    })
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return FORMAT_PREFIX .. FORMAT_VERSION .. ":" .. encoded
end

function AttendanceDatabase:PrepareImport(text)
    if type(text) ~= "string" then
        return nil, "Paste an attendance database export first."
    end

    local trimmed = text:match("^%s*(.-)%s*$")
    local versionText, encoded = trimmed:match("^" .. FORMAT_PREFIX .. "(%d+):(.+)$")
    if not versionText then
        return nil, "This is not a PurplexityRaidTools attendance database export."
    end

    local version = tonumber(versionText)
    if version ~= FORMAT_VERSION then
        return nil, "Attendance database format version " .. versionText .. " is not supported."
    end

    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, "The attendance database export could not be decoded."
    end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "The attendance database export could not be decompressed."
    end

    local ok, payload = LibSerialize:Deserialize(serialized)
    if not ok then
        return nil, "The attendance database export could not be read."
    end
    return PreparePayload(payload)
end

function AttendanceDatabase:ApplyPrepared(prepared)
    if type(prepared) ~= "table" then
        return false, "No attendance database import is ready."
    end

    local checked, err = PreparePayload({
        attendance = prepared.attendance,
        roster = prepared.roster,
    })
    if not checked then
        return false, err
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "The attendance database cannot be imported during combat."
    end

    local attendanceDB = PurplexityRaidToolsAttendanceDB or {}
    local rosterDB = PurplexityRaidToolsRosterDB or {}
    PurplexityRaidToolsAttendanceDB = attendanceDB
    PurplexityRaidToolsRosterDB = rosterDB

    ClearTable(attendanceDB)
    for day, records in pairs(checked.attendance) do
        attendanceDB[day] = CopyTable(records)
    end

    ClearTable(rosterDB)
    for index, entry in ipairs(checked.roster) do
        rosterDB[index] = entry
    end

    PRT.Roster:NotifyDatabaseReplaced()
    return true, checked.summary
end
