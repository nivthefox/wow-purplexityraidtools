-- AttendanceWiring: the seam between the attendance modules and the running
-- client. This is the only file in the feature that reads PRT:GetSetting and the
-- only consumer of GroupInspect.members; the store, roster, report and sync
-- modules take their settings as arguments so account-wide records stay
-- independent of the profile system.
--
-- Under 12.x chat-messaging lockdown the countdown and ready-check payloads
-- arrive as secret values, which cannot be compared, boolean-tested, or used as
-- a table key. The event handlers therefore declare no parameters and consult no
-- payload: the raid leader is found by crawling units, and a countdown records a
-- pull whoever started it.

local PRT = PurplexityRaidTools
local AttendanceWiring = {}
PRT.AttendanceWiring = AttendanceWiring
PRT:RegisterModule("attendance", AttendanceWiring)

local COUNTDOWN_START_EVENT = "START_PLAYER_COUNTDOWN"
local COUNTDOWN_CANCEL_EVENT = "CANCEL_PLAYER_COUNTDOWN"
local READY_CHECK_EVENT = "READY_CHECK"

local NAME_REALM_PATTERN = "^[^%-]+%-.+$"

PRT.defaults.attendance = {
    rolloverHour = 6,
    expiryDays = 90,
    autoSyncFromLeader = false,
    confirmBeforeSyncing = true,
}

local guildClassCache

local function AttendanceSettings()
    return PRT:GetSetting("attendance")
end

local function IsResolvedCharacterName(name)
    return type(name) == "string" and name:match(NAME_REALM_PATTERN) ~= nil
end

local function GroupClassMembers()
    return PRT.GroupInspect.members
end

--- An empty read means the guild roster has not arrived from the server yet, so
--- it is answered but never cached: caching it would leave every class unknown
--- until the next group scan cleared it.
local function GuildClassMembers()
    if guildClassCache then
        return guildClassCache
    end

    local members = {}
    for index = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, _, _, classToken = GetGuildRosterInfo(index)
        if name then
            members[#members + 1] = { name = name, class = classToken }
        end
    end

    if #members > 0 then
        guildClassCache = members
    end
    return members
end

local function OtherRaidLeaderName()
    for unit in PRT:IterateGroup() do
        if UnitIsGroupLeader(unit) then
            if UnitIsUnit(unit, "player") then
                return nil
            end
            return GetUnitName(unit, true)
        end
    end
    return nil
end

function AttendanceWiring:BuildSnapshot(members)
    local snapshot = {}
    for _, member in pairs(members) do
        if IsResolvedCharacterName(member.name) then
            snapshot[#snapshot + 1] = member.name
        end
    end
    return snapshot
end

--- A group the client has not resolved yet is not a group of nobody: recording
--- it would write a day of Missing-fills and spend the first-pull semantics, so
--- the next real pull would record everybody Late.
function AttendanceWiring:OnCountdownStart()
    local group = self:BuildSnapshot(PRT.GroupInspect.members)
    if #group == 0 then
        return
    end

    local settings = AttendanceSettings()
    PRT.AttendanceStore:OnCountdownStart(group, PRT.Roster:GetEntries(), settings.rolloverHour)
end

function AttendanceWiring:OnCountdownCancel()
    PRT.AttendanceStore:OnCountdownCancel()
end

function AttendanceWiring:OnReadyCheck()
    local leaderName = OtherRaidLeaderName()
    if not leaderName then
        return
    end

    local settings = AttendanceSettings()
    PRT.AttendanceSync:OnReadyCheck(leaderName, settings.autoSyncFromLeader)
end

function AttendanceWiring:RunExpiryPass()
    local settings = AttendanceSettings()
    PRT.AttendanceStore:ExpireOldDays(settings.expiryDays, settings.rolloverHour)
end

function AttendanceWiring:ApplySettings()
    PRT.AttendanceSync.confirmBeforeSyncing = AttendanceSettings().confirmBeforeSyncing
end

--- Gates the Push and Sync Roster buttons. Outside a raid the receive-side check
--- asks only about the leader, so an assistant's push would be discarded by
--- everyone it reached.
function AttendanceWiring:CanPushToRaid()
    if not IsInGroup() then
        return false
    end
    if UnitIsGroupLeader("player") then
        return true
    end
    if not IsInRaid() then
        return false
    end
    return UnitIsGroupAssistant("player") == true
end

local function OnEvent(_, event)
    if event == COUNTDOWN_START_EVENT then
        AttendanceWiring:OnCountdownStart()
    elseif event == COUNTDOWN_CANCEL_EVENT then
        AttendanceWiring:OnCountdownCancel()
    elseif event == READY_CHECK_EVENT then
        AttendanceWiring:OnReadyCheck()
    end
end

local function OnGroupScanned()
    guildClassCache = nil
    PRT.Roster:RefreshClasses()
end

function AttendanceWiring:Initialize()
    PRT.Roster.groupSource = GroupClassMembers
    PRT.Roster.guildSource = GuildClassMembers

    PRT.AttendanceSync:RegisterHandlers()
    self:ApplySettings()
    PRT:RegisterApplyCallback("attendance", function()
        AttendanceWiring:ApplySettings()
    end)

    self:RunExpiryPass()
    PRT.GroupInspect:Listen(OnGroupScanned)

    self.eventFrame:RegisterEvent(COUNTDOWN_START_EVENT)
    self.eventFrame:RegisterEvent(COUNTDOWN_CANCEL_EVENT)
    self.eventFrame:RegisterEvent(READY_CHECK_EVENT)
    self.eventFrame:SetScript("OnEvent", OnEvent)
end
