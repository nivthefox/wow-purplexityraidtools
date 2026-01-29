-- ReadyCheck: Monitors ready checks and reminds players about missing buffs
local PRT = PurplexityRaidTools
local ReadyCheck = {}
PRT.ReadyCheck = ReadyCheck

--------------------------------------------------------------------------------
-- Buff Definitions
--------------------------------------------------------------------------------

local RAID_BUFFS = {
    {
        key = "arcaneIntellect",
        name = "Arcane Intellect",
        spellId = 1458,
        class = "MAGE",
        message = "Some players are missing Arcane Intellect. Could you please buff the raid?",
    },
    {
        key = "battleShout",
        name = "Battle Shout",
        spellId = 6673,
        class = "WARRIOR",
        message = "Some players are missing Battle Shout. Could you please buff the raid?",
    },
    {
        key = "blessingOfTheBronze",
        name = "Blessing of the Bronze",
        spellId = 364342,
        class = "EVOKER",
        message = "Some players are missing Blessing of the Bronze. Could you please buff the raid?",
    },
    {
        key = "markOfTheWild",
        name = "Mark of the Wild",
        spellId = 1126,
        class = "DRUID",
        message = "Some players are missing Mark of the Wild. Could you please buff the raid?",
    },
    {
        key = "powerWordFortitude",
        name = "Power Word: Fortitude",
        spellId = 21562,
        class = "PRIEST",
        message = "Some players are missing Power Word: Fortitude. Could you please buff the raid?",
    },
    {
        key = "skyfury",
        name = "Skyfury",
        spellId = 462854,
        class = "SHAMAN",
        message = "Some players are missing Skyfury. Could you please buff the raid?",
    },
}

local SOULSTONE_SPELL_ID = 20707

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.readyCheck = {
    enabled = true,
    checkSoulstones = true,
    arcaneIntellect = true,
    battleShout = true,
    blessingOfTheBronze = true,
    markOfTheWild = true,
    powerWordFortitude = true,
    skyfury = true,
}

--------------------------------------------------------------------------------
-- Raid Scanning
--------------------------------------------------------------------------------

local function GetPlayersByClass(className)
    local players = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return players
    end

    for i = 1, numMembers do
        local name, _, _, _, _, fileName, _, online = GetRaidRosterInfo(i)
        if name and fileName == className and online then
            table.insert(players, name)
        end
    end
    return players
end

local function GetAllRaidMembers()
    local members = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return members
    end

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and online then
            table.insert(members, { name = name, unit = "raid" .. i })
        end
    end
    return members
end

local function GetHealers()
    local healers = {}
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then
        return healers
    end

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and online then
            local role = UnitGroupRolesAssigned("raid" .. i)
            if role == "HEALER" then
                table.insert(healers, { name = name, unit = "raid" .. i })
            end
        end
    end
    return healers
end

local function HasBuff(unit, spellId)
    local found = false
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraData)
        if auraData.spellId == spellId then
            found = true
            return true -- stop iteration
        end
    end, true) -- usePackedAura = true
    return found
end

local function AnyoneHasBuff(members, spellId)
    for _, member in ipairs(members) do
        if HasBuff(member.unit, spellId) then
            return true
        end
    end
    return false
end

local function EveryoneHasBuff(members, spellId)
    for _, member in ipairs(members) do
        if not HasBuff(member.unit, spellId) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

local function SendWhisper(playerName, message)
    local success = pcall(function()
        C_ChatInfo.SendChatMessage(message, "WHISPER", nil, playerName)
    end)
    return success
end

local function NotifyPlayers(players, message)
    for _, name in ipairs(players) do
        SendWhisper(name, message)
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

    if not IsInRaid() then
        return
    end

    if not UnitIsGroupLeader("player") then
        return
    end

    local allMembers = GetAllRaidMembers()
    if #allMembers == 0 then
        return
    end

    -- Check raid buffs
    for _, buff in ipairs(RAID_BUFFS) do
        if settings[buff.key] then
            local providers = GetPlayersByClass(buff.class)
            if #providers > 0 and not EveryoneHasBuff(allMembers, buff.spellId) then
                NotifyPlayers(providers, buff.message)
            end
        end
    end

    -- Check soulstones (special case: only check healers)
    if settings.checkSoulstones then
        local warlocks = GetPlayersByClass("WARLOCK")
        if #warlocks > 0 then
            local healers = GetHealers()
            if #healers > 0 and not AnyoneHasBuff(healers, SOULSTONE_SPELL_ID) then
                NotifyPlayers(warlocks, "No healer has a soulstone. Could you please soulstone a healer?")
            end
        end
    end
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

    -- Master toggle
    local enabledCheckbox = PRT.Components.GetCheckbox(container, "Enable Ready Check Features", function(value)
        EnsureSettingsTable().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)

    local raidLeaderNote = enabledCheckbox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    raidLeaderNote:SetPoint("LEFT", enabledCheckbox, "CENTER", 20, 0)
    raidLeaderNote:SetText("(requires Raid Leader)")

    yOffset = yOffset - ROW_HEIGHT

    -- Spacing before buff checks
    yOffset = yOffset - 10

    -- Raid buff checkboxes
    for _, buff in ipairs(RAID_BUFFS) do
        local checkbox = PRT.Components.GetCheckbox(container, "Check " .. buff.name, function(value)
            EnsureSettingsTable()[buff.key] = value
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        checkbox:SetValue(GetSettings()[buff.key])
        yOffset = yOffset - ROW_HEIGHT
    end

    -- Soulstone checkbox
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
