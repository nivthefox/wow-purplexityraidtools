-- GroupInspect: Inspects group members to determine spec and talents.
-- Always-on module that exposes a shared data table and listener mechanism
-- so multiple consumers can react to changes without duplicating the crawl.
local PRT = PurplexityRaidTools
local GroupInspect = {}
PRT.GroupInspect = GroupInspect
PRT:RegisterModule("groupInspect", GroupInspect)

--------------------------------------------------------------------------------
-- Data Table
--------------------------------------------------------------------------------

--- Per-player data, keyed by GUID.
--- Each entry: { name, class, specId (nil until inspect), talents (nil until inspect),
---               addonVersion (nil until a version response arrives) }
GroupInspect.members = {}

--------------------------------------------------------------------------------
-- Listener Mechanism
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local priorityQueue = {}    -- array of GUIDs needing immediate inspection (new joins)
local sweepQueue = {}       -- array of GUIDs queued by the periodic full-raid sweep
local inspectPending = nil  -- unit currently being inspected
local inCombat = false

local inspectTicker = nil   -- drains the inspect queues, one member per tick
local sweepTicker = nil     -- refills the full-raid sweep on a fixed interval

local TICK_INTERVAL = 1     -- seconds between inspect-drain attempts
local SWEEP_INTERVAL = 60   -- seconds between full-raid sweeps

--------------------------------------------------------------------------------
-- Addon Version Detection
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetPlayerSpecId()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specId = GetSpecializationInfo(specIndex)
    return specId
end

--- Find the unit token for a GUID by scanning the current group.
local function UnitForGUID(guid)
    for unit in PRT:IterateGroup() do
        if UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

--- Fire off an inspect request for the given unit and set a 2-second timeout.
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

--------------------------------------------------------------------------------
-- Talent Reading
--------------------------------------------------------------------------------

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
        local nodeID = nodes[i]
        local node = C_Traits.GetNodeInfo(configId, nodeID)
        if node and node.ID ~= 0 and node.activeEntry then
            -- Skip hero talent subtree selection nodes.
            if not (Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection
                    and node.type == Enum.TraitNodeType.SubTreeSelection) then
                if node.currentRank and node.currentRank > 0
                        and (not node.subTreeID or node.subTreeActive) then
                    local entryID = node.activeEntry.entryID
                    local entry = C_Traits.GetEntryInfo(configId, entryID)
                    if entry and entry.definitionID then
                        local defInfo = C_Traits.GetDefinitionInfo(entry.definitionID)
                        if defInfo and defInfo.spellID then
                            talents[defInfo.spellID] = true
                        end
                    end
                end
            end
        end
    end

    return talents
end

--- Read the local player's active talents.
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

--- Read the inspected player's active talents via C_Traits and return a set of
--- spell IDs (spellId -> true). Returns nil if the API data is unavailable.
local function ReadInspectTalents()
    return ReadTalentsFromConfig(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
end

--------------------------------------------------------------------------------
-- Inspect Queue
--------------------------------------------------------------------------------

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
    -- Never inspect mid-fight, while an inspect is already pending, or while the
    -- player has the Blizzard inspect window open (doing so breaks gear tooltips).
    if GroupInCombat() or inspectPending or IsInspectFrameOpen() then
        return
    end

    -- Priority queue: new joins with no spec data go first.
    while #priorityQueue > 0 do
        local guid = table.remove(priorityQueue, 1)
        local unit = UnitForGUID(guid)
        local member = GroupInspect.members[guid]
        if unit and member and not member.specId then
            BeginInspect(unit)
            return
        end
    end

    -- Periodic full sweep: drain one queued member per tick.
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
        inspectTicker = C_Timer.NewTicker(TICK_INTERVAL, ProcessNextInspect)
    end
    if not sweepTicker then
        sweepTicker = C_Timer.NewTicker(SWEEP_INTERVAL, RefillSweepQueue)
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

--------------------------------------------------------------------------------
-- Roster Scanning
--------------------------------------------------------------------------------

function GroupInspect:ScanRoster()
    local activeGUIDs = {}
    local changed = false

    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            activeGUIDs[guid] = true

            if not self.members[guid] then
                -- New member
                local _, classToken = UnitClass(unit)
                local playerName = UnitName(unit)
                self.members[guid] = {
                    name = playerName,
                    class = classToken,
                    specId = nil,
                    talents = nil,
                    addonVersion = nil,
                }
                changed = true

                if UnitIsUnit(unit, "player") then
                    -- Local player: read directly, no inspect needed
                    local specId = GetPlayerSpecId()
                    if specId and specId > 0 then
                        self.members[guid].specId = specId
                    end
                    local talents = ReadPlayerTalents()
                    if talents then
                        self.members[guid].talents = talents
                    end
                    self.members[guid].addonVersion = GetLocalVersion()
                    -- If spec or talents are still missing after load, retry shortly.
                    -- The talent system may not be ready on the first frame after login.
                    if not self.members[guid].specId or not self.members[guid].talents then
                        C_Timer.After(1, function()
                            if self.members[guid] then
                                local specId2 = GetPlayerSpecId()
                                if specId2 and specId2 > 0 then
                                    self.members[guid].specId = specId2
                                end
                                local talents2 = ReadPlayerTalents()
                                if talents2 then
                                    self.members[guid].talents = talents2
                                end
                                NotifyListeners()
                            end
                        end)
                    end
                else
                    -- Queue for inspection
                    table.insert(priorityQueue, guid)
                end
            end
        end
    end

    -- Remove departed members
    for guid in pairs(self.members) do
        if not activeGUIDs[guid] then
            self.members[guid] = nil
            changed = true
        end
    end

    -- Start or stop tickers based on group state
    if IsInGroup() or IsInRaid() then
        StartTickers()
    else
        StopTickers()
        -- Clear all data when leaving a group
        for guid in pairs(self.members) do
            self.members[guid] = nil
        end
        changed = true
    end

    if changed then
        NotifyListeners()
    end
end

--------------------------------------------------------------------------------
-- Inspect Result Handling
--------------------------------------------------------------------------------

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

    local specId = GetInspectSpecialization(inspectPending)
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

    if specId and specId > 0 then
        if member.specId ~= specId then
            member.specId = specId
            changed = true
        end
    end

    if talents then
        local oldTalents = member.talents
        -- Compare talent sets: rebuild if the new set differs from the cached one.
        local talentsChanged = not oldTalents
        if not talentsChanged then
            for spellId in pairs(talents) do
                if not oldTalents[spellId] then
                    talentsChanged = true
                    break
                end
            end
        end
        if not talentsChanged then
            for spellId in pairs(oldTalents) do
                if not talents[spellId] then
                    talentsChanged = true
                    break
                end
            end
        end
        if talentsChanged then
            member.talents = talents
            changed = true
        end
    end

    if changed then
        NotifyListeners()
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local function OnEvent(_, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        GroupInspect:ScanRoster()

    elseif event == "INSPECT_READY" then
        OnInspectReady(...)

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function GroupInspect:Initialize()
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    PRT.Comms:RegisterHandler(VERSION_QUERY_MSG_TYPE, OnVersionQuery)
    PRT.Comms:RegisterHandler(VERSION_RESPONSE_MSG_TYPE, OnVersionResponse)
end
