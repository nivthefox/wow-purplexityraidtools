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
        messages = {
            "It's ironic that the 'smart' class has forgotten the Intellect buff. Again.",
            "Do you even know what Arcane Intellect is?",
            "Big brain class forgot the brain buff. Classic.",
            "Please provide Arcane Intellect. Some of us need all the help we can get.",
            "Arcane Intellect is missing. I'd explain why that's bad, but you wouldn't understand.",
            "No Arcane Intellect? Did you spec out of reading?",
        },
    },
    {
        key = "battleShout",
        name = "Battle Shout",
        spellId = 6673,
        class = "WARRIOR",
        messages = {
            "You have ONE job: yelling at people. Why is Battle Shout missing?",
            "BATTLE SHOUT. DO THE YELLING THING.",
            "The buff where you scream? Do that.",
            "I need you to be angry at the raid. Professionally.",
            "Someone needs Battle Shout. Thinking isn't your strong suit, but try.",
            "You're telling me the class that solves every problem by hitting it forgot to yell?",
        },
    },
    {
        key = "blessingOfTheBronze",
        name = "Blessing of the Bronze",
        spellId = 364342,
        class = "EVOKER",
        messages = {
            "Do I need to get Nozdormu on the phone, or do you think you can find his blessing on your own?",
            "Blessing of the Bronze missing. Did you forget you're a dragon?",
            "Blessing of the Bronze. Yes, you, the fancy lizard.",
            "You have time magic and you still forgot to buff before pull?",
            "Your draconic duties include buffing. Get on it.",
            "The Aspects didn't empower you so you could forget Blessing of the Bronze.",
        },
    },
    {
        key = "markOfTheWild",
        name = "Mark of the Wild",
        spellId = 1126,
        class = "DRUID",
        messages = {
            "Did you forget to pet the raid? Mark of the Wild is missing.",
            "Mark of the Wild missing. Did you shapeshift into someone who doesn't buff?",
            "The raid is feeling distinctly un-Marked and un-Wild.",
            "You can be like six different animals and none of them know how to buff?",
            "One with nature, zero with the buff bar. Mark of the Wild, please.",
            "You have an entire form dedicated to healing and you still forgot to buff the raid.",
        },
    },
    {
        key = "powerWordFortitude",
        name = "Power Word: Fortitude",
        spellId = 21562,
        class = "PRIEST",
        messages = {
            "Power Word: Fortitude. It's right there between Power Word: Shield and Power Word: Disappointment.",
            "The bubble class forgot the stamina buff. Incredible.",
            "No Fort? What's next, life grip the tank off the platform?",
            "Fort is missing. I'm starting to think 'Discipline' is just your spec name, not a personality trait.",
            "You can resurrect the dead but you can't remember to buff them after?",
            "Power Word: Please.",
        },
    },
    {
        key = "skyfury",
        name = "Skyfury",
        spellId = 462854,
        class = "SHAMAN",
        messages = {
            "Skyfury is missing. Did your totems unionize or something?",
            "Skyfury is missing; did you leave it in the Maelstrom?",
            "Hey shaman. Do the windy thing so that we have Skyfury.",
            "Are the elements not responding today, or did you just forget about Skyfury?",
            "Shamans are supposed to master the elements, so why is the Mastery buff the one that's missing?",
            "You commune with the spirits and none of them reminded you about Skyfury?"
        },
    },
}

local SOULSTONE_SPELL_ID = 20707
local SOULSTONE_MESSAGES = {
    "Why have you not soulstoned a healer? What am I even paying you for?",
    "Soulstone a healer. It's the closest you'll get to being useful after you die.",
    "A healer needs a soulstone. You know, for when we inevitably wipe.",
    "No soulstone on a healer? Bold of you to assume we won't need it.",
    "The soulstone exists specifically because we don't trust you. Please put it on a healer.",
    "You enslave demons for a living. Putting a rock on a healer shouldn't be this hard.",
}

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

-- Helper to get a readyCheck setting with fallback to default
local function GetReadyCheckSetting(settings, key)
    if settings[key] ~= nil then
        return settings[key]
    end
    return PRT.defaults.readyCheck[key]
end

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
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, id = UnitBuff(unit, i)
        if not name then
            break
        end
        if id == spellId then
            return true
        end
    end
    return false
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

local function GetRandomMessage(messages)
    return messages[math.random(#messages)]
end

local function SendWhisper(playerName, message)
    local success = pcall(function()
        C_ChatInfo.SendChatMessage(message, "WHISPER", nil, playerName)
    end)
    return success
end

local function NotifyPlayers(players, messages)
    for _, name in ipairs(players) do
        SendWhisper(name, GetRandomMessage(messages))
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
        if GetReadyCheckSetting(settings, buff.key) then
            local providers = GetPlayersByClass(buff.class)
            if #providers > 0 and not EveryoneHasBuff(allMembers, buff.spellId) then
                NotifyPlayers(providers, buff.messages)
            end
        end
    end

    -- Check soulstones (special case: only check healers)
    if GetReadyCheckSetting(settings, "checkSoulstones") then
        local warlocks = GetPlayersByClass("WARLOCK")
        if #warlocks > 0 then
            local healers = GetHealers()
            if #healers > 0 and not AnyoneHasBuff(healers, SOULSTONE_SPELL_ID) then
                NotifyPlayers(warlocks, SOULSTONE_MESSAGES)
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
