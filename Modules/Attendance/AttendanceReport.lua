-- AttendanceReport: read-time rollup of attendance records into player rows.
-- A player's status for a day is the best one across the characters on their
-- roster entry, resolved afresh on every read rather than stored: adding a
-- character to an entry attributes the records already written under its name,
-- and removing the entry drops its characters back to standing alone.
--
-- The attendance database and the roster entries arrive as parameters and leave
-- untouched. Nothing here reads a SavedVariable or another PRT module: the
-- lowest attended status below is the report's own, not the store's enum.

local PRT = PurplexityRaidTools
local AttendanceReport = {}
PRT.AttendanceReport = AttendanceReport

local MISSING, ABSENT, LATE, PRESENT, STANDBY = 0, 1, 2, 3, 4
local LOWEST_ATTENDED_STATUS = LATE
local STATUS_PRIORITY = {
    [MISSING] = 0,
    [ABSENT] = 1,
    [LATE] = 2,
    [STANDBY] = 3,
    [PRESENT] = 4,
}

local function RecordStatus(record)
    if type(record) == "table" then
        return record.status
    end
    return record
end

local function BestRecordedStatus(dayRecord, characters)
    local resolved
    for i = 1, #characters do
        local status = RecordStatus(dayRecord[characters[i]])
        if status ~= nil and (resolved == nil
                or STATUS_PRIORITY[status] > STATUS_PRIORITY[resolved]) then
            resolved = status
        end
    end
    return resolved
end

local function ResolvedStatuses(db, days, characters)
    local statuses = {}
    for i = 1, #days do
        local dayRecord = db[days[i]]
        if dayRecord then
            statuses[days[i]] = BestRecordedStatus(dayRecord, characters)
        end
    end
    return statuses
end

local function PercentageOf(statuses)
    local recorded, attended = 0, 0
    for _, status in pairs(statuses) do
        recorded = recorded + 1
        if status >= LOWEST_ATTENDED_STATUS then
            attended = attended + 1
        end
    end

    if recorded == 0 then
        return nil
    end
    return math.floor(attended / recorded * 100 + 0.5)
end

local function RecordedDaysNewestFirst(db)
    local days = {}
    for day in pairs(db) do
        days[#days + 1] = day
    end

    table.sort(days, function(a, b)
        return a > b
    end)
    return days
end

local function CopyCharacters(characters)
    local copy = {}
    for index = 1, #characters do
        copy[index] = characters[index]
    end
    return copy
end

local function UnrosteredCharacters(db, entries)
    local rostered = {}
    for _, entry in ipairs(entries) do
        for _, character in ipairs(entry.characters) do
            rostered[character] = true
        end
    end

    local collected, names = {}, {}
    for _, dayRecord in pairs(db) do
        for character in pairs(dayRecord) do
            if not rostered[character] and not collected[character] then
                collected[character] = true
                names[#names + 1] = character
            end
        end
    end

    table.sort(names)
    return names
end

function AttendanceReport:ResolveStatus(db, day, characters)
    local dayRecord = db[day]
    if not dayRecord then
        return nil
    end
    return BestRecordedStatus(dayRecord, characters)
end

function AttendanceReport:GetPercentage(db, days, characters)
    return PercentageOf(ResolvedStatuses(db, days, characters))
end

function AttendanceReport:Build(db, entries)
    local days = RecordedDaysNewestFirst(db)

    local players = {}
    for _, entry in ipairs(entries) do
        local statuses = ResolvedStatuses(db, days, entry.characters)
        local percentage = PercentageOf(statuses)
        if percentage ~= nil then
            players[#players + 1] = {
                name = entry.nickname,
                characters = CopyCharacters(entry.characters),
                statuses = statuses,
                percentage = percentage,
            }
        end
    end

    local unrostered = {}
    for index, character in ipairs(UnrosteredCharacters(db, entries)) do
        local characters = { character }
        unrostered[index] = {
            name = character,
            characters = characters,
            statuses = ResolvedStatuses(db, days, characters),
        }
    end

    return { days = days, players = players, unrostered = unrostered }
end
