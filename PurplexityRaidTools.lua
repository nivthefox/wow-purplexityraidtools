-- PurplexityRaidTools: Core namespace and shared configuration
-- This file loads first and sets up the global namespace

PurplexityRaidTools = PurplexityRaidTools or {}
local PRT = PurplexityRaidTools

-- Saved variables (initialized on ADDON_LOADED)
PurplexityRaidToolsDB = PurplexityRaidToolsDB or {}

-- Default settings
PRT.defaults = {
    -- Add module defaults here as they're created
}

-- Registry for apply callbacks (modules register here, config calls them)
PRT.applyCallbacks = {}

-- Module registry (ordered by TOC load order)
PRT.modules = {}
PRT.modulesByName = {}

function PRT:RegisterModule(name, moduleTable)
    moduleTable.eventFrame = CreateFrame("Frame")
    moduleTable.active = false
    table.insert(self.modules, { name = name, module = moduleTable })
    self.modulesByName[name] = moduleTable
end

function PRT:RegisterApplyCallback(name, callback)
    self.applyCallbacks[name] = callback
end

function PRT:ApplySettings(settingName)
    if settingName then
        local callback = self.applyCallbacks[settingName]
        if callback then callback() end
    else
        for _, callback in pairs(self.applyCallbacks) do
            callback()
        end
    end
    self:EvaluateAllModules()
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function PRT:EvaluateModule(entry)
    local name = entry.name
    local module = entry.module

    -- Modules without OnEnable/OnDisable are "always on" after Initialize
    if not module.OnEnable and not module.OnDisable then
        return
    end

    -- Check enabled setting
    local enabled
    if module.GetEnabledSetting then
        enabled = module:GetEnabledSetting()
    else
        local settings = self:GetSetting(name)
        enabled = settings and (settings.enabled ~= false)
    end

    -- Check activatable
    local activatable = enabled
    if activatable and module.IsActivatable then
        activatable = module:IsActivatable()
    end

    -- Transition
    if activatable and not module.active then
        module.active = true
        if module.OnEnable then
            module:OnEnable()
        end
    elseif not activatable and module.active then
        if module.OnDisable then
            module:OnDisable()
        end
        module.active = false
    end
end

function PRT:EvaluateAllModules()
    for _, entry in ipairs(self.modules) do
        self:EvaluateModule(entry)
    end
end

--------------------------------------------------------------------------------
-- Profile System
--------------------------------------------------------------------------------

PRT.Profiles = {}

-- Deep copy a table
local function DeepCopy(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Deep merge defaults into target (missing keys are deep-copied; existing values win)
local function DeepMerge(defaults, target)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            DeepMerge(v, target[k])
        end
    end
end

-- Get the current profile's data table
function PRT.Profiles:GetCurrent()
    local db = PurplexityRaidToolsDB
    local profileName = db.currentProfile or "Default"
    return db.profiles and db.profiles[profileName] or {}
end

-- Get array of all profile names
function PRT.Profiles:GetNames()
    local names = {}
    local db = PurplexityRaidToolsDB
    if db.profiles then
        for name in pairs(db.profiles) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

-- Get the current profile name
function PRT.Profiles:GetCurrentName()
    return PurplexityRaidToolsDB.currentProfile or "Default"
end

-- Switch to a different profile
function PRT.Profiles:Switch(name)
    local db = PurplexityRaidToolsDB
    if not db.profiles or not db.profiles[name] then return false end
    db.currentProfile = name
    PRT:MergeDefaults()
    PRT:ApplySettings()
    return true
end

-- Create a new profile (optionally clone from another)
function PRT.Profiles:Create(name, cloneFrom)
    local db = PurplexityRaidToolsDB
    if not db.profiles then db.profiles = {} end
    if db.profiles[name] then return false end

    if cloneFrom and db.profiles[cloneFrom] then
        db.profiles[name] = DeepCopy(db.profiles[cloneFrom])
    else
        db.profiles[name] = {}
    end

    return true
end

-- Delete a profile (cannot delete Default or current)
function PRT.Profiles:Delete(name)
    local db = PurplexityRaidToolsDB
    if name == "Default" then return false end
    if name == db.currentProfile then return false end
    if not db.profiles or not db.profiles[name] then return false end

    db.profiles[name] = nil
    return true
end

-- Rename a profile
function PRT.Profiles:Rename(oldName, newName)
    local db = PurplexityRaidToolsDB
    if not newName or newName == "" then return false end
    if not db.profiles or not db.profiles[oldName] then return false end
    if db.profiles[newName] then return false end

    db.profiles[newName] = db.profiles[oldName]
    db.profiles[oldName] = nil

    if db.currentProfile == oldName then
        db.currentProfile = newName
    end

    return true
end

-- Helper to get a saved value with fallback to default (profile-aware)
function PRT:GetSetting(key)
    local profile = self.Profiles:GetCurrent()
    if profile[key] ~= nil then
        return profile[key]
    end
    return self.defaults[key]
end

-- Merge defaults into the current profile (recursive, non-destructive)
function PRT:MergeDefaults()
    local profile = self.Profiles:GetCurrent()
    DeepMerge(self.defaults, profile)
end

-- Initialize saved variables with profile structure
function PRT:InitializeDB()
    local db = PurplexityRaidToolsDB

    -- Ensure profile structure exists
    if not db.profiles then
        db.profiles = {}
    end
    if not db.profiles["Default"] then
        db.profiles["Default"] = {}
    end
    if not db.currentProfile then
        db.currentProfile = "Default"
    end

    -- Import defaults into current profile
    self:MergeDefaults()
end

-- Event frame for initialization and lifecycle
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        PRT:InitializeDB()
        for _, entry in ipairs(PRT.modules) do
            if entry.module.Initialize then
                entry.module:Initialize()
            end
        end
        -- Register lifecycle events
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        -- Initial module evaluation
        PRT:EvaluateAllModules()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
        or event == "ZONE_CHANGED_NEW_AREA" then
        PRT:EvaluateAllModules()
    end
end)

--------------------------------------------------------------------------------
-- Content Type Detection (shared by DontRelease, CooldownRoster, etc.)
--------------------------------------------------------------------------------

function PRT.GetCurrentContentType()
    local _, instanceType, difficultyID = GetInstanceInfo()

    if instanceType == "none" then
        return "openWorld", nil
    end

    local _, _, isHeroic, isChallengeMode, _, displayMythic, _, isLFR = GetDifficultyInfo(difficultyID)

    if instanceType == "party" then
        if isChallengeMode then
            return "dungeon", "mythicPlus"
        elseif displayMythic then
            return "dungeon", "mythic"
        elseif isHeroic then
            return "dungeon", "heroic"
        else
            return "dungeon", "normal"
        end
    end

    if instanceType == "raid" then
        if isLFR then
            return "raid", "lfr"
        elseif displayMythic then
            return "raid", "mythic"
        elseif isHeroic then
            return "raid", "heroic"
        else
            return "raid", "normal"
        end
    end

    if instanceType == "scenario" then
        if isHeroic then
            return "scenario", "heroic"
        else
            return "scenario", "normal"
        end
    end

    return nil, nil
end

function PRT.IsContentTypeEnabled(contentTypes)
    if not contentTypes then
        return false
    end

    local contentType, subType = PRT.GetCurrentContentType()
    if not contentType then
        return false
    end

    if contentType == "openWorld" then
        return contentTypes.openWorld == true
    end

    local contentSettings = contentTypes[contentType]
    if not contentSettings then
        return false
    end

    if subType then
        return contentSettings[subType] == true
    end

    return false
end

--------------------------------------------------------------------------------
-- Group Iteration
--------------------------------------------------------------------------------

function PRT:IterateGroup()
    if IsInRaid() then
        local count = GetNumGroupMembers()
        local i = 0
        return function()
            i = i + 1
            if i <= count then
                return "raid" .. i
            end
        end
    elseif IsInGroup() then
        local count = GetNumGroupMembers() - 1
        local i = 0
        local sentPlayer = false
        return function()
            i = i + 1
            if i <= count then
                return "party" .. i
            elseif not sentPlayer then
                sentPlayer = true
                return "player"
            end
        end
    else
        local done = false
        return function()
            if not done then
                done = true
                return "player"
            end
        end
    end
end

-- Slash command
SLASH_PURPLEXITYRAIDTOOLS1 = "/prt"
SLASH_PURPLEXITYRAIDTOOLS2 = "/purplexity"
SlashCmdList["PURPLEXITYRAIDTOOLS"] = function(msg)
    local cmd = string.lower(string.match(msg or "", "^%s*(%S+)") or "")

    if cmd == "inv" or cmd == "invite" then
        PRT.AutoInvite:InviteByRank()
        return
    end

    if PurplexityRaidToolsConfigFrame then
        if PurplexityRaidToolsConfigFrame:IsShown() then
            PurplexityRaidToolsConfigFrame:Hide()
        else
            PurplexityRaidToolsConfigFrame:Show()
        end
    end
end
