-- AttendanceSync: sharing attendance days and the roster over PRT.Comms.
--
-- Replacement is wholesale rather than merged: an accepted day or roster
-- overwrites the local one entirely. A cell-by-cell merge taking the higher
-- status can never lower a value, which makes corrections impossible to
-- propagate, so the spec rules it out.
--
-- This module is the validation seam. AttendanceStore keys the first-pull
-- decision on a day KEY's presence and compares day keys as strings during
-- expiry; Roster scans every entry's characters on every save and reads
-- characterData for each listed name. Neither defends those invariants, so an
-- incoming record or roster is checked here, all-or-nothing, or never.
--
-- Headless-load safety: no frame, timer or event API is touched at load, and
-- registration is an explicit RegisterHandlers call rather than a load side
-- effect. The two sync settings arrive as the injected confirmBeforeSyncing
-- field and an OnReadyCheck parameter, so nothing here reads PRT:GetSetting.

local PRT = PurplexityRaidTools
local AttendanceSync = {}
PRT.AttendanceSync = AttendanceSync

local INVENTORY_REQUEST = "attInventoryRequest"
local INVENTORY_RESPONSE = "attInventoryResponse"
local PULL_REQUEST = "attPullRequest"
local PULL_RESPONSE = "attPullResponse"
local PULL_MISSING = "attPullMissing"
local DAY_PUSH = "attDayPush"
local ROSTER_PUSH = "attRosterPush"
local ROSTER_REQUEST = "attRosterRequest"

local ISO_DAY_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"

local MISSING, ABSENT, LATE, PRESENT = 0, 1, 2, 3
local VALID_STATUSES = { [MISSING] = true, [ABSENT] = true, [LATE] = true, [PRESENT] = true }

AttendanceSync.inventory = {}

local listeners = {}

--- Register a callback to be notified when the sync state changes: a pending
--- replacement appearing or being resolved, a roster replaced outright, or the
--- inventory moving. Callbacks fire synchronously in registration order with no
--- payload.
function AttendanceSync:Listen(callback)
    table.insert(listeners, callback)
end

local function NotifyListeners()
    for i = 1, #listeners do
        listeners[i]()
    end
end

--- A RAID broadcast is delivered back to its sender, so without this an officer
--- pushing a day is offered their own records. The bare-name compare cannot
--- tell a same-named character on a connected realm from the local player; that
--- fails safe, since the cost is ignoring one push.
local function IsOwnBroadcast(sender)
    return Ambiguate(sender, "short") == UnitName("player")
end

local function EnsureAttendanceDB()
    PurplexityRaidToolsAttendanceDB = PurplexityRaidToolsAttendanceDB or {}
    return PurplexityRaidToolsAttendanceDB
end

local function EnsureRosterDB()
    PurplexityRaidToolsRosterDB = PurplexityRaidToolsRosterDB or {}
    return PurplexityRaidToolsRosterDB
end

local function LocalRosterEntries()
    return PurplexityRaidToolsRosterDB or {}
end

local function CountRecords(dayRecord)
    local count = 0
    for _ in pairs(dayRecord) do
        count = count + 1
    end
    return count
end

local function LocalRecordCount(day)
    local db = PurplexityRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord then
        return 0
    end
    return CountRecords(dayRecord)
end

local function LocalInventory()
    local days = {}
    local db = PurplexityRaidToolsAttendanceDB
    if not db then
        return days
    end

    for day, dayRecord in pairs(db) do
        days[day] = CountRecords(dayRecord)
    end
    return days
end

local function IsSoundInventory(days)
    if type(days) ~= "table" then
        return false
    end

    for day, count in pairs(days) do
        if type(day) ~= "string" or not day:match(ISO_DAY_PATTERN) then
            return false
        end
        if type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
            return false
        end
    end

    return true
end

local function IsSoundDayRecord(data)
    if type(data) ~= "table" then
        return false
    end
    if type(data.day) ~= "string" or not data.day:match(ISO_DAY_PATTERN) then
        return false
    end
    if type(data.records) ~= "table" then
        return false
    end

    local recorded = 0
    for character, status in pairs(data.records) do
        if type(character) ~= "string" or character == "" then
            return false
        end
        if not VALID_STATUSES[status] then
            return false
        end
        recorded = recorded + 1
    end

    return recorded > 0
end

local function IsSoundCharacterRecord(record)
    if type(record) ~= "table" then
        return false
    end
    if record.class ~= nil and type(record.class) ~= "string" then
        return false
    end
    if record.mainSpec ~= nil and type(record.mainSpec) ~= "number" then
        return false
    end
    if record.offSpecs ~= nil and type(record.offSpecs) ~= "table" then
        return false
    end
    return true
end

local function IsSoundRosterEntry(entry)
    if type(entry) ~= "table" then
        return false
    end
    if type(entry.nickname) ~= "string" or entry.nickname == "" then
        return false
    end
    if type(entry.characters) ~= "table" or #entry.characters == 0 then
        return false
    end
    if type(entry.characterData) ~= "table" then
        return false
    end

    for _, character in ipairs(entry.characters) do
        if type(character) ~= "string" or character == "" then
            return false
        end
        if not IsSoundCharacterRecord(entry.characterData[character]) then
            return false
        end
    end

    return true
end

--- Officers arrange the roster by hand and the grid presents that arrangement,
--- so the entry list is an ordered array; a nickname-keyed table would survive
--- an ipairs scan by looking empty.
local function IsSoundRoster(entries)
    if type(entries) ~= "table" then
        return false
    end

    local keys = 0
    for _ in pairs(entries) do
        keys = keys + 1
    end
    if keys ~= #entries then
        return false
    end

    local claimedNicknames, claimedCharacters = {}, {}
    for _, entry in ipairs(entries) do
        if not IsSoundRosterEntry(entry) then
            return false
        end
        if claimedNicknames[entry.nickname] then
            return false
        end
        claimedNicknames[entry.nickname] = true

        for _, character in ipairs(entry.characters) do
            if claimedCharacters[character] then
                return false
            end
            claimedCharacters[character] = true
        end
    end

    return true
end

--- Refilled in place rather than reassigned: Roster:GetEntries hands out the
--- live table, so swapping it strands every reference already taken.
local function ReplaceRoster(entries)
    local db = EnsureRosterDB()
    wipe(db)
    for index, entry in ipairs(entries) do
        db[index] = entry
    end
end

local function OnInventoryRequest(_, sender)
    PRT.Comms:Send(INVENTORY_RESPONSE, { days = LocalInventory() }, "WHISPER", sender)
end

local function OnInventoryResponse(data, sender)
    if type(data) ~= "table" or not IsSoundInventory(data.days) then
        return
    end
    AttendanceSync.inventory[sender] = data.days
    NotifyListeners()
end

local function OnPullRequest(data, sender)
    if type(data) ~= "table" or type(data.day) ~= "string" then
        return
    end

    local db = PurplexityRaidToolsAttendanceDB
    local dayRecord = db and db[data.day]
    if not dayRecord then
        PRT.Comms:Send(PULL_MISSING, { day = data.day }, "WHISPER", sender)
        return
    end

    PRT.Comms:Send(PULL_RESPONSE, { day = data.day, records = dayRecord }, "WHISPER", sender)
end

--- The day reaches the officer's chat frame, where escape codes render as
--- markup, so it is held to the full ISO shape rather than merely to a string:
--- anyone in the raid can send this, and a day that is not ISO names no record
--- worth reporting anyway.
local function OnPullMissing(data, sender)
    if type(data) ~= "table" or type(data.day) ~= "string"
        or not data.day:match(ISO_DAY_PATTERN) then
        return
    end

    local held = AttendanceSync.inventory[sender]
    if held and held[data.day] ~= nil then
        held[data.day] = nil
        NotifyListeners()
    end

    print("|cFF00FF00PurplexityRaidTools:|r " .. sender
        .. " no longer has an attendance record for " .. data.day .. ".")
end

local function PendDayReplacement(data, sender)
    if not IsSoundDayRecord(data) then
        return
    end

    AttendanceSync.pendingDay = {
        sender = sender,
        day = data.day,
        localCount = LocalRecordCount(data.day),
        incomingCount = CountRecords(data.records),
        records = data.records,
    }
    NotifyListeners()
end

local function OnDayPush(data, sender)
    if IsOwnBroadcast(sender) then
        return
    end
    if not PRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    PendDayReplacement(data, sender)
end

local function OnRosterPush(data, sender)
    if IsOwnBroadcast(sender) then
        return
    end
    if not PRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    if type(data) ~= "table" or not IsSoundRoster(data.entries) then
        return
    end

    if AttendanceSync.confirmBeforeSyncing == false then
        ReplaceRoster(data.entries)
        NotifyListeners()
        return
    end

    AttendanceSync.pendingRoster = {
        sender = sender,
        localCount = #LocalRosterEntries(),
        incomingCount = #data.entries,
        entries = data.entries,
    }
    NotifyListeners()
end

local function OnRosterRequest(_, sender)
    PRT.Comms:Send(ROSTER_PUSH, { entries = LocalRosterEntries() }, "WHISPER", sender)
end

function AttendanceSync:RegisterHandlers()
    PRT.Comms:RegisterHandler(INVENTORY_REQUEST, OnInventoryRequest)
    PRT.Comms:RegisterHandler(INVENTORY_RESPONSE, OnInventoryResponse)
    PRT.Comms:RegisterHandler(PULL_REQUEST, OnPullRequest)
    PRT.Comms:RegisterHandler(PULL_RESPONSE, PendDayReplacement)
    PRT.Comms:RegisterHandler(PULL_MISSING, OnPullMissing)
    PRT.Comms:RegisterHandler(DAY_PUSH, OnDayPush)
    PRT.Comms:RegisterHandler(ROSTER_PUSH, OnRosterPush)
    PRT.Comms:RegisterHandler(ROSTER_REQUEST, OnRosterRequest)
end

function AttendanceSync:RequestInventory()
    wipe(self.inventory)
    PRT.Comms:Send(INVENTORY_REQUEST, {}, "RAID")
    NotifyListeners()
end

function AttendanceSync:GetInventory()
    return self.inventory
end

function AttendanceSync:RequestDay(target, day)
    PRT.Comms:Send(PULL_REQUEST, { day = day }, "WHISPER", target)
end

function AttendanceSync:PushDay(day)
    local db = PurplexityRaidToolsAttendanceDB
    local dayRecord = db and db[day]
    if not dayRecord then
        return false
    end

    PRT.Comms:Send(DAY_PUSH, { day = day, records = dayRecord }, "RAID")
    return true
end

function AttendanceSync:PushRoster()
    PRT.Comms:Send(ROSTER_PUSH, { entries = LocalRosterEntries() }, "RAID")
end

function AttendanceSync:OnReadyCheck(leaderName, autoSyncEnabled)
    if not autoSyncEnabled or not leaderName then
        return
    end
    PRT.Comms:Send(ROSTER_REQUEST, {}, "WHISPER", leaderName)
end

function AttendanceSync:GetPendingDay()
    return self.pendingDay
end

function AttendanceSync:AcceptPendingDay()
    local pending = self.pendingDay
    if not pending then
        return false
    end

    EnsureAttendanceDB()[pending.day] = pending.records
    self.pendingDay = nil
    NotifyListeners()
    return true
end

function AttendanceSync:DeclinePendingDay()
    if not self.pendingDay then
        return
    end
    self.pendingDay = nil
    NotifyListeners()
end

function AttendanceSync:GetPendingRoster()
    return self.pendingRoster
end

function AttendanceSync:AcceptPendingRoster()
    local pending = self.pendingRoster
    if not pending then
        return false
    end

    ReplaceRoster(pending.entries)
    self.pendingRoster = nil
    NotifyListeners()
    return true
end

function AttendanceSync:DeclinePendingRoster()
    if not self.pendingRoster then
        return
    end
    self.pendingRoster = nil
    NotifyListeners()
end
