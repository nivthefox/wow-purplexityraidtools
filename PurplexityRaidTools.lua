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
    PRT:ImportDefaultsToProfile()
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

-- Rename a profile (cannot rename Default)
function PRT.Profiles:Rename(oldName, newName)
    local db = PurplexityRaidToolsDB
    if oldName == "Default" then return false end
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

-- Import defaults into the current profile (non-destructive)
function PRT:ImportDefaultsToProfile()
    local profile = self.Profiles:GetCurrent()
    for k, v in pairs(self.defaults) do
        if profile[k] == nil then
            profile[k] = DeepCopy(v)
        end
    end
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
    self:ImportDefaultsToProfile()
end

-- Event frame for initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        PRT:InitializeDB()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Slash command
SLASH_PURPLEXITYRAIDTOOLS1 = "/prt"
SLASH_PURPLEXITYRAIDTOOLS2 = "/purplexity"
SlashCmdList["PURPLEXITYRAIDTOOLS"] = function(msg)
    if PurplexityRaidToolsConfigFrame then
        if PurplexityRaidToolsConfigFrame:IsShown() then
            PurplexityRaidToolsConfigFrame:Hide()
        else
            PurplexityRaidToolsConfigFrame:Show()
        end
    end
end
