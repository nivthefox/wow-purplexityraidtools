-- CooldownTracker: Tracks raid cooldown availability via UNIT_AURA detection
local PRT = PurplexityRaidTools
local CooldownTracker = {}
PRT.CooldownTracker = CooldownTracker

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local STATE_AVAILABLE = "available"
local STATE_ACTIVE = "active"
local STATE_ON_COOLDOWN = "onCooldown"

-- Export states for display module
CooldownTracker.STATE_AVAILABLE = STATE_AVAILABLE
CooldownTracker.STATE_ACTIVE = STATE_ACTIVE
CooldownTracker.STATE_ON_COOLDOWN = STATE_ON_COOLDOWN

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local eventFrame = nil
local initialized = false
local enabled = false

-- Tracked cooldowns keyed by "playerName:spellId"
-- Each entry: { playerName, spellData, state, stateStartTime, auraInstanceID,
--               buffDuration, expirationTime, cooldownTimer, classToken }
local trackedCooldowns = {}

-- Inspection state
local inspectionQueue = {}       -- array of unit IDs pending spec inspection
local inspectedSpecs = {}        -- playerGUID -> specId
local inspectTicker = nil        -- C_Timer ticker for processing queue
local currentInspectUnit = nil   -- unit currently being inspected

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetCooldownKey(playerName, spellId)
    return playerName .. ":" .. spellId
end

local function IsInGroupContent()
    return IsInGroup() or IsInRaid()
end

local function GetSettings()
    return PRT:GetSetting("cooldownTracker")
end

local function IsCategoryEnabled(category)
    local settings = GetSettings()
    if not settings or not settings.categories then
        return true
    end
    return settings.categories[category] ~= false
end

--------------------------------------------------------------------------------
-- State Transitions
--------------------------------------------------------------------------------

local function TransitionToAvailable(entry)
    entry.state = STATE_AVAILABLE
    entry.stateStartTime = GetTime()
    entry.auraInstanceID = nil
    entry.buffDuration = nil
    entry.expirationTime = nil
    if entry.cooldownTimer then
        entry.cooldownTimer:Cancel()
        entry.cooldownTimer = nil
    end
end

local function TransitionToActive(entry, auraInstanceID, duration, expirationTime)
    if entry.cooldownTimer then
        entry.cooldownTimer:Cancel()
        entry.cooldownTimer = nil
    end
    entry.state = STATE_ACTIVE
    entry.stateStartTime = GetTime()
    entry.auraInstanceID = auraInstanceID
    entry.buffDuration = duration
    entry.expirationTime = expirationTime
end

local function TransitionToOnCooldown(entry)
    local buffDuration = entry.buffDuration or 0
    local baseCooldown = entry.spellData.cooldown
    local remaining = baseCooldown - buffDuration
    if remaining <= 0 then
        TransitionToAvailable(entry)
        return
    end

    entry.state = STATE_ON_COOLDOWN
    entry.stateStartTime = GetTime()
    entry.auraInstanceID = nil
    entry.expirationTime = GetTime() + remaining
    -- Preserve buffDuration for display's cooldown progress calculation

    entry.cooldownTimer = C_Timer.NewTimer(remaining, function()
        entry.cooldownTimer = nil
        TransitionToAvailable(entry)
        if PRT.CooldownTrackerDisplay then
            PRT.CooldownTrackerDisplay:OnStateChanged()
        end
    end)
end

--------------------------------------------------------------------------------
-- Composition Scanning
--------------------------------------------------------------------------------

local function ScanComposition()
    local spellsByClass = PRT.CooldownTrackerSpellsByClass
    if not spellsByClass then
        return
    end

    local settings = GetSettings()
    if not settings then
        return
    end

    -- Track which keys are still valid
    local validKeys = {}

    local numMembers = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and numMembers or (numMembers - 1)

    -- Include player in party mode
    local units = {}
    if not IsInRaid() and numMembers > 0 then
        table.insert(units, "player")
    end
    for i = 1, count do
        table.insert(units, prefix .. i)
    end

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, classToken = UnitClass(unit)
            local guid = UnitGUID(unit)

            if name and classToken and spellsByClass[classToken] then
                local knownSpec = guid and inspectedSpecs[guid]

                for _, spellData in ipairs(spellsByClass[classToken]) do
                    -- Filter by category setting
                    if IsCategoryEnabled(spellData.category) then
                        -- Filter by spec if we have spec data
                        local showSpell = true
                        if spellData.specId and knownSpec then
                            showSpell = (spellData.specId == knownSpec)
                        end

                        if showSpell then
                            local key = GetCooldownKey(name, spellData.spellId)
                            validKeys[key] = true

                            if not trackedCooldowns[key] then
                                trackedCooldowns[key] = {
                                    playerName = name,
                                    spellData = spellData,
                                    state = STATE_AVAILABLE,
                                    stateStartTime = GetTime(),
                                    auraInstanceID = nil,
                                    buffDuration = nil,
                                    expirationTime = nil,
                                    cooldownTimer = nil,
                                    classToken = classToken,
                                }
                            end
                        end
                    end
                end

                -- Queue for inspection if we do not have spec data yet
                if guid and not inspectedSpecs[guid] then
                    local alreadyQueued = false
                    for _, queuedUnit in ipairs(inspectionQueue) do
                        if queuedUnit == unit then
                            alreadyQueued = true
                            break
                        end
                    end
                    if not alreadyQueued then
                        table.insert(inspectionQueue, unit)
                    end
                end
            end
        end
    end

    -- Remove entries for players no longer in the group
    for key, entry in pairs(trackedCooldowns) do
        if not validKeys[key] then
            if entry.cooldownTimer then
                entry.cooldownTimer:Cancel()
            end
            trackedCooldowns[key] = nil
        end
    end

    if PRT.CooldownTrackerDisplay then
        PRT.CooldownTrackerDisplay:OnStateChanged()
    end
end

--------------------------------------------------------------------------------
-- Inspection Queue Processing
--------------------------------------------------------------------------------

local function ProcessNextInspection()
    if InCombatLockdown() then
        return
    end

    if currentInspectUnit then
        return
    end

    while #inspectionQueue > 0 do
        local unit = table.remove(inspectionQueue, 1)
        if UnitExists(unit) and UnitIsConnected(unit) and CanInspect(unit) then
            currentInspectUnit = unit
            NotifyInspect(unit)
            return
        end
    end
end

local function OnInspectReady(inspectedUnit)
    if not currentInspectUnit then
        return
    end

    -- The INSPECT_READY event passes a GUID; match against our current inspect target
    local guid = UnitGUID(currentInspectUnit)
    if guid and guid == inspectedUnit then
        local specId = GetInspectSpecialization(currentInspectUnit)
        if specId and specId > 0 then
            inspectedSpecs[guid] = specId
        end
        ClearInspectPlayer()
        currentInspectUnit = nil
        ScanComposition()
    end
end

local function StartInspectionTicker()
    if inspectTicker then
        return
    end
    inspectTicker = C_Timer.NewTicker(0.5, ProcessNextInspection)
end

local function StopInspectionTicker()
    if inspectTicker then
        inspectTicker:Cancel()
        inspectTicker = nil
    end
    currentInspectUnit = nil
end

--------------------------------------------------------------------------------
-- Aura Handling
--------------------------------------------------------------------------------

-- Find the first tracked entry matching a spell ID, regardless of source.
-- Used as a fallback when sourceUnit is unavailable (combat restrictions).
local function FindEntryBySpellId(spellId)
    for _, entry in pairs(trackedCooldowns) do
        if entry.spellData.spellId == spellId then
            return entry
        end
    end
    return nil
end

local function OnUnitAura(unit, updateInfo)
    if unit ~= "player" then
        return
    end

    if not updateInfo then
        return
    end

    local spells = PRT.CooldownTrackerSpells

    -- Check added auras
    if updateInfo.addedAuras then
        for _, auraData in ipairs(updateInfo.addedAuras) do
            local spellId = auraData.spellId
            if spellId and spells[spellId] then
                local spellData = spells[spellId]
                if IsCategoryEnabled(spellData.category) then
                    -- Try to identify the source
                    local sourceName
                    local ok, sourceUnit = pcall(function() return auraData.sourceUnit end)
                    if ok and sourceUnit then
                        sourceName = UnitName(sourceUnit)
                    end

                    local entry
                    if sourceName then
                        -- Source known: match by player+spell key
                        local key = GetCooldownKey(sourceName, spellId)
                        entry = trackedCooldowns[key]

                        -- Dynamic discovery: source not in pre-scan
                        if not entry then
                            local _, classToken
                            if sourceUnit then
                                _, classToken = UnitClass(sourceUnit)
                            end
                            entry = {
                                playerName = sourceName,
                                spellData = spellData,
                                state = STATE_AVAILABLE,
                                stateStartTime = GetTime(),
                                auraInstanceID = nil,
                                buffDuration = nil,
                                expirationTime = nil,
                                cooldownTimer = nil,
                                classToken = classToken or spellData.class,
                            }
                            trackedCooldowns[key] = entry
                        end
                    else
                        -- Source unknown (combat restriction): match any
                        -- tracked entry for this spell ID
                        entry = FindEntryBySpellId(spellId)
                    end

                    if entry then
                        TransitionToActive(entry, auraData.auraInstanceID, auraData.duration, auraData.expirationTime)
                    end
                end
            end
        end
    end

    -- Check removed auras
    if updateInfo.removedAuraInstanceIDs then
        for _, removedID in ipairs(updateInfo.removedAuraInstanceIDs) do
            for _, entry in pairs(trackedCooldowns) do
                if entry.auraInstanceID == removedID and entry.state == STATE_ACTIVE then
                    TransitionToOnCooldown(entry)
                    break
                end
            end
        end
    end

    if PRT.CooldownTrackerDisplay then
        PRT.CooldownTrackerDisplay:OnStateChanged()
    end
end

--------------------------------------------------------------------------------
-- Combat Reset
--------------------------------------------------------------------------------

local function OnCombatStart()
    for _, entry in pairs(trackedCooldowns) do
        if entry.cooldownTimer then
            entry.cooldownTimer:Cancel()
            entry.cooldownTimer = nil
        end
        entry.state = STATE_AVAILABLE
        entry.stateStartTime = GetTime()
        entry.auraInstanceID = nil
        entry.buffDuration = nil
        entry.expirationTime = nil
    end

    if PRT.CooldownTrackerDisplay then
        PRT.CooldownTrackerDisplay:OnStateChanged()
    end
end

local function OnCombatEnd()
    -- Resume inspections for any un-inspected members
    if #inspectionQueue > 0 or not inspectTicker then
        StartInspectionTicker()
    end
end

--------------------------------------------------------------------------------
-- Enable / Disable
--------------------------------------------------------------------------------

-- GROUP_ROSTER_UPDATE and PLAYER_ENTERING_WORLD are always registered (in
-- Initialize) so we can detect group join/leave regardless of module state.
-- Only the combat, aura, and inspection events are toggled with enable/disable.

local function EnableModule()
    if enabled then
        return
    end
    enabled = true

    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("INSPECT_READY")

    ScanComposition()
    StartInspectionTicker()

    if PRT.CooldownTrackerDisplay then
        PRT.CooldownTrackerDisplay:OnModuleEnabled()
    end
end

local function DisableModule()
    if not enabled then
        return
    end
    enabled = false

    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:UnregisterEvent("INSPECT_READY")

    StopInspectionTicker()

    -- Clear all state
    for key, entry in pairs(trackedCooldowns) do
        if entry.cooldownTimer then
            entry.cooldownTimer:Cancel()
        end
        trackedCooldowns[key] = nil
    end
    inspectionQueue = {}
    inspectedSpecs = {}

    if PRT.CooldownTrackerDisplay then
        PRT.CooldownTrackerDisplay:OnModuleDisabled()
    end
end

--------------------------------------------------------------------------------
-- Public API (for Display module)
--------------------------------------------------------------------------------

function CooldownTracker:GetTrackedCooldowns()
    return trackedCooldowns
end

function CooldownTracker:IsEnabled()
    return enabled
end

--------------------------------------------------------------------------------
-- Settings Apply Callback
--------------------------------------------------------------------------------

local function CheckModuleState()
    -- Guard against being called before Initialize (e.g., config tab slider
    -- triggers ApplySettings at file-load time before ADDON_LOADED fires)
    if not initialized then
        return
    end

    local settings = GetSettings()
    local shouldEnable = settings and settings.enabled and IsInGroupContent()

    if shouldEnable then
        if enabled then
            -- Re-scan in case categories changed
            ScanComposition()
        else
            EnableModule()
        end
    else
        DisableModule()
    end
end

PRT:RegisterApplyCallback("cooldownTracker", CheckModuleState)

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local function OnEvent(_, event, ...)
    if event == "UNIT_AURA" then
        local unit, updateInfo = ...
        OnUnitAura(unit, updateInfo)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        CheckModuleState()
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "INSPECT_READY" then
        local guid = ...
        OnInspectReady(guid)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CooldownTracker:Initialize()
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    initialized = true

    -- These two events stay registered permanently so we detect group
    -- join/leave even when the module is disabled. PLAYER_ENTERING_WORLD
    -- catches the case where party data isn't available at ADDON_LOADED
    -- time (e.g., during /reload while already in a group).
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Check initial state (enables module if already in a group)
    CheckModuleState()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        CooldownTracker:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
