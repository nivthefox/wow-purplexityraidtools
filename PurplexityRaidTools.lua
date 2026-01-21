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

-- Helper to get a saved value with fallback to default
function PRT:GetSetting(key)
    local db = PurplexityRaidToolsDB
    if db[key] ~= nil then
        return db[key]
    end
    return self.defaults[key]
end

-- Initialize saved variables with defaults (call on ADDON_LOADED)
function PRT:InitializeDB()
    for k, v in pairs(self.defaults) do
        if PurplexityRaidToolsDB[k] == nil then
            if type(v) == "table" then
                PurplexityRaidToolsDB[k] = {}
                for k2, v2 in pairs(v) do
                    if type(v2) == "table" then
                        PurplexityRaidToolsDB[k][k2] = {}
                        for k3, v3 in pairs(v2) do
                            PurplexityRaidToolsDB[k][k2][k3] = v3
                        end
                    else
                        PurplexityRaidToolsDB[k][k2] = v2
                    end
                end
            else
                PurplexityRaidToolsDB[k] = v
            end
        end
    end
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
