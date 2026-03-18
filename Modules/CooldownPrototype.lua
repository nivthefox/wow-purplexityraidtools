-- CooldownPrototype: Diagnostic tool for testing UNIT_AURA + C_UnitAuras API
-- feasibility under Midnight's combat log restrictions
local PRT = PurplexityRaidTools
local CooldownPrototype = {}
PRT.CooldownPrototype = CooldownPrototype

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.cooldownPrototype = {
    enabled = false,
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local loggingEnabled = false
local eventFrame = nil

--------------------------------------------------------------------------------
-- Safe Field Reading
--------------------------------------------------------------------------------

-- Wrap every field read in pcall to catch secret-ified values that may error
-- on tostring, comparison, or concatenation.
local function SafeRead(value, fallback)
    local ok, result = pcall(tostring, value)
    if ok and result ~= nil then
        return result
    end
    return fallback or "<error>"
end

-- Check if a value is usable (not secret). Tries to use it as a table key.
local function IsUsable(value)
    if value == nil then
        return false
    end
    local test = {}
    local ok = pcall(function() test[value] = true end)
    return ok
end

--------------------------------------------------------------------------------
-- Chat Output
--------------------------------------------------------------------------------

local PREFIX = "|cFF00CCFFPRT Proto:|r "

local function Print(msg)
    print(PREFIX .. msg)
end

--------------------------------------------------------------------------------
-- Aura Processing
--------------------------------------------------------------------------------

local function IsFromSelf(auraData)
    -- Try sourceUnit first
    if IsUsable(auraData.sourceUnit) and auraData.sourceUnit then
        local ok, result = pcall(UnitIsUnit, auraData.sourceUnit, "player")
        if ok then
            return result
        end
    end
    -- Try isFromPlayerOrPlayerPet
    if IsUsable(auraData.isFromPlayerOrPlayerPet) then
        return auraData.isFromPlayerOrPlayerPet == true
    end
    -- Can't determine source; it's probably secret, so not from self
    return false
end

local function ProcessNewAura(auraData)
    -- Skip self-cast auras to reduce spam
    if IsFromSelf(auraData) then
        return
    end

    local spellId = SafeRead(auraData.spellId, "<secret>")
    local name = SafeRead(auraData.name, "<secret>")
    local sourceUnit = SafeRead(auraData.sourceUnit, "<secret>")
    local duration = SafeRead(auraData.duration, "<secret>")
    local expirationTime = SafeRead(auraData.expirationTime, "<secret>")
    local auraInstanceID = SafeRead(auraData.auraInstanceID, "<secret>")

    local restricted = "<no API>"
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local ok, result = pcall(C_CombatLog.IsCombatLogRestricted)
        if ok then
            restricted = SafeRead(result, "nil")
        else
            restricted = "<error>"
        end
    end

    Print(string.format(
        "SpellID: %s | Name: %s | Source: %s | Duration: %s | InstID: %s | Restricted: %s",
        spellId, name, sourceUnit, duration, auraInstanceID, restricted
    ))
end

local function OnUnitAura(unit, updateInfo)
    if unit ~= "player" then
        return
    end

    if not updateInfo or not updateInfo.addedAuras then
        return
    end

    for _, auraData in ipairs(updateInfo.addedAuras) do
        local ok, err = pcall(ProcessNewAura, auraData)
        if not ok then
            Print("Failed to process aura: " .. SafeRead(err, "unknown error"))
        end
    end
end

--------------------------------------------------------------------------------
-- Group Check
--------------------------------------------------------------------------------

local function IsInGroupContent()
    return IsInGroup() or IsInRaid()
end

--------------------------------------------------------------------------------
-- Enable / Disable Logging
--------------------------------------------------------------------------------

local function EnableLogging()
    if loggingEnabled then
        return
    end
    loggingEnabled = true
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    Print("Logging enabled. Self-cast auras are filtered out.")
end

local function DisableLogging()
    if not loggingEnabled then
        return
    end
    loggingEnabled = false
    eventFrame:UnregisterEvent("UNIT_AURA")
    Print("Logging disabled.")
end

--------------------------------------------------------------------------------
-- Slash Command
--------------------------------------------------------------------------------

SLASH_PRTPROTO1 = "/prtproto"
SlashCmdList["PRTPROTO"] = function()
    if not IsInGroupContent() then
        Print("Not in a group. Logging is only active in party or raid.")
        return
    end

    if loggingEnabled then
        DisableLogging()
    else
        EnableLogging()
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local function OnEvent(_, event, ...)
    if event == "UNIT_AURA" then
        if loggingEnabled and IsInGroupContent() then
            local unit, updateInfo = ...
            OnUnitAura(unit, updateInfo)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if loggingEnabled and not IsInGroupContent() then
            DisableLogging()
            Print("Left group. Logging auto-disabled.")
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CooldownPrototype:Initialize()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:SetScript("OnEvent", OnEvent)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        CooldownPrototype:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
