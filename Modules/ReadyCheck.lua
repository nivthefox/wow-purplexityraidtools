-- ReadyCheck: Monitors ready checks and reminds Warlocks to soulstone healers
local PRT = PurplexityRaidTools
local ReadyCheck = {}
PRT.ReadyCheck = ReadyCheck

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.readyCheck = {
    enabled = true,
    checkSoulstones = true,
}

--------------------------------------------------------------------------------
-- Raid Scanning
--------------------------------------------------------------------------------

local function GetWarlocks()
    local warlocks = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return warlocks
    end

    for i = 1, numMembers do
        local name, _, _, _, _, fileName, _, online = GetRaidRosterInfo(i)
        if name and fileName == "WARLOCK" and online then
            table.insert(warlocks, name)
        end
    end
    return warlocks
end

local function GetHealers()
    local healers = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return healers
    end

    for i = 1, numMembers do
        local name = GetRaidRosterInfo(i)
        if name then
            local role = UnitGroupRolesAssigned("raid" .. i)
            if role == "HEALER" then
                table.insert(healers, { name = name, unit = "raid" .. i })
            end
        end
    end
    return healers
end

local function HasSoulstone(unit)
    local auraName = AuraUtil.FindAuraByName("Soulstone", unit, "HELPFUL")
    return auraName ~= nil
end

local function AnyHealerHasSoulstone(healers)
    for _, healer in ipairs(healers) do
        if HasSoulstone(healer.unit) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

local MESSAGE = "No healer has a soulstone. Could you please soulstone a healer?"

local function SendWhisper(playerName, message)
    local success, err = pcall(function()
        C_ChatInfo.SendChatMessage(message, "WHISPER", nil, playerName)
    end)
    return success
end

local function SendRaidMessage(message)
    pcall(function()
        C_ChatInfo.SendChatMessage(message, "RAID")
    end)
end

local function NotifyWarlocks(warlocks)
    local whisperFailed = false

    for _, name in ipairs(warlocks) do
        if not SendWhisper(name, MESSAGE) then
            whisperFailed = true
            break
        end
    end

    if whisperFailed then
        SendRaidMessage(MESSAGE)
    end
end

--------------------------------------------------------------------------------
-- Ready Check Handler
--------------------------------------------------------------------------------

function ReadyCheck:OnReadyCheck()
    local settings = PRT:GetSetting("readyCheck")
    if not settings or not settings.enabled then
        return
    end

    if not settings.checkSoulstones then
        return
    end

    if not IsInRaid() then
        return
    end

    local warlocks = GetWarlocks()
    if #warlocks == 0 then
        return
    end

    local healers = GetHealers()
    if #healers == 0 then
        return
    end

    if AnyHealerHasSoulstone(healers) then
        return
    end

    NotifyWarlocks(warlocks)
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Ready Check", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -60)
    container:SetPoint("BOTTOMRIGHT", -8, 8)
    container:Hide()

    local yOffset = 0
    local ROW_HEIGHT = 24

    local function GetSettings()
        return PRT:GetSetting("readyCheck")
    end

    local function GetProfile()
        return PRT.Profiles:GetCurrent()
    end

    local function EnsureSettingsTable()
        local profile = GetProfile()
        if not profile.readyCheck then
            profile.readyCheck = {}
            for k, v in pairs(PRT.defaults.readyCheck) do
                profile.readyCheck[k] = v
            end
        end
        return profile.readyCheck
    end

    -- Soulstone Section
    local soulstoneHeader = PRT.Components.GetHeader(container, "Soulstone Reminder")
    soulstoneHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(container, "Enable Ready Check Features", function(value)
        EnsureSettingsTable().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local soulstoneCheckbox = PRT.Components.GetCheckbox(container, "Check Soul Stones", function(value)
        EnsureSettingsTable().checkSoulstones = value
    end)
    soulstoneCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    soulstoneCheckbox:SetValue(GetSettings().checkSoulstones)
    yOffset = yOffset - ROW_HEIGHT

    return container
end)

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function ReadyCheck:Initialize()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "READY_CHECK" then
            ReadyCheck:OnReadyCheck()
        end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        ReadyCheck:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
