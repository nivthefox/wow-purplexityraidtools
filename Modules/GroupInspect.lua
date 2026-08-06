-- Always-on module exposing a shared data table and listener mechanism so
-- multiple consumers can react to changes without duplicating the inspect crawl.
local PRT = PurplexityRaidTools
local GroupInspect = {}
PRT.GroupInspect = GroupInspect
PRT:RegisterModule("groupInspect", GroupInspect)

--- Per-player data, keyed by GUID.
--- Each entry: { name, class, specId (nil until inspect), talents (nil until inspect),
---               addonVersion (nil until a version response arrives) }
GroupInspect.members = {}

local listeners = {}

--- Register a callback to be notified when the data table changes.
--- Callbacks fire synchronously in registration order with no payload.
function GroupInspect:Listen(callback)
    table.insert(listeners, callback)
end

local function NotifyListeners()
    for i = 1, #listeners do
        listeners[i]()
    end
end

local priorityQueue = {}
local sweepQueue = {}
local inspectPending = nil
local inCombat = false

local inspectTicker = nil
local sweepTicker = nil

local INSPECT_TICK_SECONDS = 1
local SWEEP_INTERVAL_SECONDS = 60

local ADDON_NAME = "PurplexityRaidTools"
local VERSION_QUERY_MSG_TYPE = "versionQuery"
local VERSION_RESPONSE_MSG_TYPE = "versionResponse"

--- Pack "major.minor.patch" into a single comparable integer, dropping any
--- prerelease suffix. Anything unparseable encodes to 0 ("installed, version
--- indeterminate"), never nil.
function GroupInspect.EncodeVersion(versionString)
    if type(versionString) ~= "string" then
        return 0
    end

    local prereleaseStart = versionString:find("-", 1, true)
    if prereleaseStart then
        versionString = versionString:sub(1, prereleaseStart - 1)
    end

    local major, minor, patch = versionString:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then
        return 0
    end

    return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
end

local function GetLocalVersion()
    return GroupInspect.EncodeVersion(C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
end

--- Whisper a version query to the unit being inspected. Members running PRT
--- answer; silence means the addon is missing. The target must carry the realm
--- for cross-realm members, and is nil for a unit that just left the group.
local function SendVersionQuery(unit)
    local target = GetUnitName(unit, true)
    if not target then
        return
    end
    PRT.Comms:Send(VERSION_QUERY_MSG_TYPE, {}, "WHISPER", target)
end

local function OnVersionQuery(_, sender)
    PRT.Comms:Send(VERSION_RESPONSE_MSG_TYPE, { version = GetLocalVersion() }, "WHISPER", sender)
end

local function OnVersionResponse(data, sender)
    if type(data) ~= "table" or type(data.version) ~= "number" then
        return
    end

    local guid = UnitGUID(sender)
    if not guid then
        return
    end

    local member = GroupInspect.members[guid]
    if not member then
        return
    end

    member.addonVersion = data.version
end

local function GetPlayerSpecId()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then
        return nil
    end
    return C_SpecializationInfo.GetSpecializationInfo(specIndex)
end

-- TODO: C_SpecializationInfo should have a namespaced replacement for
-- GetInspectSpecialization, but we haven't found it yet. Fall back to the
-- global until the C_ equivalent is identified.
local function GetInspectSpecId(unit)
    local fn = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization)
        or GetInspectSpecialization
    if not fn then
        return nil
    end
    return fn(unit)
end

local function UnitForGUID(guid)
    for unit in PRT:IterateGroup() do
        if UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

local function BeginInspect(unit)
    inspectPending = unit
    NotifyInspect(unit)
    C_Timer.After(2, function()
        if inspectPending == unit then
            inspectPending = nil
        end
    end)
    SendVersionQuery(unit)
end

--- Return true if the Blizzard inspect window is open. Inspecting while it is
--- shown hijacks the single inspect slot and breaks the player's gear tooltips.
local function IsInspectFrameOpen()
    return (InspectFrame and InspectFrame:IsShown()) or false
end

--- Return true if anyone in the group is in combat. We never inspect mid-fight,
--- and the player's own PLAYER_REGEN flag misses cases like dying mid-pull, so we
--- scan the whole group.
local function GroupInCombat()
    if inCombat then
        return true
    end
    for unit in PRT:IterateGroup() do
        if UnitAffectingCombat(unit) then
            return true
        end
    end
    return false
end

local function IsSubTreeSelectionNode(node)
    return Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection
        and node.type == Enum.TraitNodeType.SubTreeSelection
end

local function ActiveNodeSpellId(configId, node)
    if not node or node.ID == 0 or not node.activeEntry then
        return nil
    end
    -- Hero talent subtree selection nodes are not talents.
    if IsSubTreeSelectionNode(node) then
        return nil
    end
    if not node.currentRank or node.currentRank == 0 then
        return nil
    end
    if node.subTreeID and not node.subTreeActive then
        return nil
    end

    local entry = C_Traits.GetEntryInfo(configId, node.activeEntry.entryID)
    if not entry or not entry.definitionID then
        return nil
    end

    local defInfo = C_Traits.GetDefinitionInfo(entry.definitionID)
    if not defInfo then
        return nil
    end
    return defInfo.spellID
end

--- Walk a trait config and return a set of active talent spell IDs
--- (spellId -> true). Returns nil if the API data is unavailable.
local function ReadTalentsFromConfig(configId)
    local config = C_Traits.GetConfigInfo(configId)
    if not config or not config.treeIDs then
        return nil
    end

    local treeID = config.treeIDs[1]
    if not treeID then
        return nil
    end

    local nodes = C_Traits.GetTreeNodes(treeID)
    if not nodes then
        return nil
    end

    local talents = {}
    for i = 1, #nodes do
        local node = C_Traits.GetNodeInfo(configId, nodes[i])
        local spellId = ActiveNodeSpellId(configId, node)
        if spellId then
            talents[spellId] = true
        end
    end

    return talents
end

local function ReadPlayerTalents()
    if not C_ClassTalents or not C_ClassTalents.GetActiveConfigID then
        return nil
    end
    local configId = C_ClassTalents.GetActiveConfigID()
    if not configId then
        return nil
    end
    return ReadTalentsFromConfig(configId)
end

local function ReadInspectTalents()
    return ReadTalentsFromConfig(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
end

--- Rebuild the full-raid sweep queue. Runs on a fixed interval as a backstop for
--- spec/talent changes we failed to catch via events. Skips while the previous
--- sweep is still draining so a slow sweep cannot starve itself.
local function RefillSweepQueue()
    if #sweepQueue > 0 then
        return
    end
    for unit in PRT:IterateGroup() do
        if not UnitIsUnit(unit, "player") then
            local guid = UnitGUID(unit)
            if guid then
                table.insert(sweepQueue, guid)
            end
        end
    end
end

local function ProcessNextInspect()
    if GroupInCombat() or inspectPending or IsInspectFrameOpen() then
        return
    end

    while #priorityQueue > 0 do
        local guid = table.remove(priorityQueue, 1)
        local unit = UnitForGUID(guid)
        local member = GroupInspect.members[guid]
        if unit and member and not member.specId then
            BeginInspect(unit)
            return
        end
    end

    while #sweepQueue > 0 do
        local guid = table.remove(sweepQueue, 1)
        local unit = UnitForGUID(guid)
        if unit and UnitExists(unit) then
            BeginInspect(unit)
            return
        end
    end
end

local function StartTickers()
    if not inspectTicker then
        inspectTicker = C_Timer.NewTicker(INSPECT_TICK_SECONDS, ProcessNextInspect)
    end
    if not sweepTicker then
        sweepTicker = C_Timer.NewTicker(SWEEP_INTERVAL_SECONDS, RefillSweepQueue)
    end
end

local function StopTickers()
    if inspectTicker then
        inspectTicker:Cancel()
        inspectTicker = nil
    end
    if sweepTicker then
        sweepTicker:Cancel()
        sweepTicker = nil
    end
end

--- A group member coming online becomes inspectable. Push them onto the
--- priority queue so the next drain tick picks them up instead of waiting on
--- the 60-second sweep. The drain gate skips members that already have spec
--- data, so a reconnect with cached data costs nothing.
function GroupInspect:OnUnitConnected(unit)
    local guid = UnitGUID(unit)
    if not guid or not self.members[guid] then
        return
    end
    if UnitIsUnit(unit, "player") then
        return
    end
    for i = 1, #priorityQueue do
        if priorityQueue[i] == guid then
            return
        end
    end
    table.insert(priorityQueue, guid)
end

local function ReadLocalPlayer(guid)
    local member = GroupInspect.members[guid]
    if not member then
        return
    end

    local specId = GetPlayerSpecId()
    if specId and specId > 0 then
        member.specId = specId
    end

    local talents = ReadPlayerTalents()
    if talents then
        member.talents = talents
    end
end

local function AddNewMember(unit, guid)
    local _, classToken = UnitClass(unit)
    GroupInspect.members[guid] = {
        name = UnitName(unit),
        class = classToken,
        specId = nil,
        talents = nil,
        addonVersion = nil,
    }

    if not UnitIsUnit(unit, "player") then
        table.insert(priorityQueue, guid)
        return
    end

    local member = GroupInspect.members[guid]
    ReadLocalPlayer(guid)
    member.addonVersion = GetLocalVersion()

    -- The talent system may not be ready on the first frame after login; retry once.
    if not member.specId or not member.talents then
        C_Timer.After(1, function()
            if GroupInspect.members[guid] then
                ReadLocalPlayer(guid)
                NotifyListeners()
            end
        end)
    end
end

function GroupInspect:ScanRoster()
    local activeGUIDs = {}
    local changed = false

    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            activeGUIDs[guid] = true
            if not self.members[guid] then
                AddNewMember(unit, guid)
                changed = true
            end
        end
    end

    for guid in pairs(self.members) do
        if not activeGUIDs[guid] then
            self.members[guid] = nil
            changed = true
        end
    end

    if IsInGroup() or IsInRaid() then
        StartTickers()
    else
        StopTickers()
        for guid in pairs(self.members) do
            self.members[guid] = nil
        end
        changed = true
    end

    if changed then
        NotifyListeners()
    end
end

local function TalentSetsDiffer(oldTalents, newTalents)
    if not oldTalents then
        return true
    end
    for spellId in pairs(newTalents) do
        if not oldTalents[spellId] then
            return true
        end
    end
    for spellId in pairs(oldTalents) do
        if not newTalents[spellId] then
            return true
        end
    end
    return false
end

local function OnInspectReady(eventGUID)
    if not inspectPending then
        return
    end

    -- Verify the event GUID matches the unit we actually requested. Another
    -- addon may have triggered an inspect for a different target.
    local pendingGUID = UnitGUID(inspectPending)
    if not pendingGUID or eventGUID ~= pendingGUID then
        return
    end

    local specId = GetInspectSpecId(inspectPending)
    local talents = ReadInspectTalents()
    inspectPending = nil

    -- Release the single inspect slot so we stop squatting on it between sweeps.
    -- Never clear while the player's inspect window is open, or we would yank the
    -- data out from under their gear tooltips.
    if not IsInspectFrameOpen() then
        ClearInspectPlayer()
    end

    local member = GroupInspect.members[pendingGUID]
    if not member then
        return
    end

    local changed = false

    if specId and specId > 0 and member.specId ~= specId then
        member.specId = specId
        changed = true
    end

    if talents and TalentSetsDiffer(member.talents, talents) then
        member.talents = talents
        changed = true
    end

    if changed then
        NotifyListeners()
    end
end

local function OnEvent(_, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        GroupInspect:ScanRoster()

    elseif event == "UNIT_CONNECTION" then
        local unit, isConnected = ...
        if isConnected then
            GroupInspect:OnUnitConnected(unit)
        end

    elseif event == "INSPECT_READY" then
        OnInspectReady(...)

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
end

function GroupInspect:Initialize()
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("UNIT_CONNECTION")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    PRT.Comms:RegisterHandler(VERSION_QUERY_MSG_TYPE, OnVersionQuery)
    PRT.Comms:RegisterHandler(VERSION_RESPONSE_MSG_TYPE, OnVersionResponse)
end
