-- AutoInvite: Whisper-keyword invites, guild rank mass invites, auto-promote
local PRT = PurplexityRaidTools
local AutoInvite = {}
PRT.AutoInvite = AutoInvite
PRT:RegisterModule("autoInvite", AutoInvite)

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.autoInvite = {
    whisperInviteEnabled = true,
    keywords = "inv invite 123",
    guildOnly = false,
    inviteRanks = {},
    promoteEnabled = true,
    promoteNames = "",
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local pendingInvites = {}
local knownMembers = {}
local pendingMassInvite = false
local massInviteRanks = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function ParseKeywords(str)
    local keywords = {}
    for word in string.gmatch(str, "%S+") do
        keywords[string.lower(word)] = true
    end
    return keywords
end

local function SplitNames(str)
    local names = {}
    for name in string.gmatch(str, "[^,]+") do
        local trimmed = string.match(name, "^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(names, trimmed)
        end
    end
    return names
end

local function ShortName(name)
    return string.match(string.lower(name), "^([^-]+)")
end

local function IsPlayerInGroup(name)
    local lowerShort = ShortName(name)
    for unit in PRT:IterateGroup() do
        local unitName = UnitName(unit)
        if unitName and ShortName(unitName) == lowerShort then
            return true
        end
    end
    return false
end

local function IsInPendingQueue(name)
    local lowerShort = ShortName(name)
    for _, entry in ipairs(pendingInvites) do
        if ShortName(entry.name) == lowerShort then
            return true
        end
    end
    return false
end

local function UnitInGuild(name)
    local lowerShort = ShortName(name)
    for i = 1, GetNumGuildMembers() do
        local guildName = GetGuildRosterInfo(i)
        if guildName and ShortName(guildName) == lowerShort then
            return true
        end
    end
    return false
end

local function QueueOrInvite(name, inviteFunc)
    local numMembers = GetNumGroupMembers()
    if numMembers >= 4 and not IsInRaid() then
        C_PartyInfo.ConvertToRaid()
        table.insert(pendingInvites, { name = name, inviteFunc = inviteFunc })
    else
        inviteFunc()
    end
end

local function ProcessInviteQueue()
    if not IsInRaid() then
        return
    end
    local queue = pendingInvites
    pendingInvites = {}
    for _, entry in ipairs(queue) do
        entry.inviteFunc()
    end
end

local function FindBNetGameAccount(bnSenderID)
    local _, numOnline = BNGetNumFriends()
    for i = 1, numOnline do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.bnetAccountID == bnSenderID then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.clientProgram == "WoW" and gameInfo.isOnline
                    and gameInfo.isInCurrentRegion
                    and gameInfo.wowProjectID == WOW_PROJECT_MAINLINE then
                    return gameInfo.gameAccountID, gameInfo.characterName
                end
            end
            return nil, nil
        end
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function AutoInvite:OnWhisper(message, senderName)
    local settings = PRT:GetSetting("autoInvite")
    if not settings or not settings.whisperInviteEnabled then
        return
    end

    local trimmed = string.match(message, "^%s*(.-)%s*$")
    if not trimmed then
        return
    end

    local keywords = ParseKeywords(settings.keywords)
    if not keywords[string.lower(trimmed)] then
        return
    end

    if IsPlayerInGroup(senderName) then
        return
    end

    if IsInPendingQueue(senderName) then
        return
    end

    if settings.guildOnly and not UnitInGuild(senderName) then
        return
    end

    QueueOrInvite(senderName, function()
        C_PartyInfo.InviteUnit(senderName)
    end)
end

function AutoInvite:OnBNetWhisper(message, senderName, bnSenderID)
    local settings = PRT:GetSetting("autoInvite")
    if not settings or not settings.whisperInviteEnabled then
        return
    end

    local trimmed = string.match(message, "^%s*(.-)%s*$")
    if not trimmed then
        return
    end

    local keywords = ParseKeywords(settings.keywords)
    if not keywords[string.lower(trimmed)] then
        return
    end

    local gameAccountID, characterName = FindBNetGameAccount(bnSenderID)
    if not gameAccountID or not characterName then
        return
    end

    if IsPlayerInGroup(characterName) then
        return
    end

    if IsInPendingQueue(characterName) then
        return
    end

    if settings.guildOnly and not UnitInGuild(characterName) then
        return
    end

    QueueOrInvite(characterName, function()
        BNInviteFriend(gameAccountID)
    end)
end

function AutoInvite:OnGroupRosterUpdate()
    ProcessInviteQueue()

    -- Build current roster snapshot
    local currentRoster = {}
    if IsInRaid() then
        for unit in PRT:IterateGroup() do
            local name = UnitName(unit)
            if name then
                currentRoster[ShortName(name)] = true
            end
        end
    end

    -- Determine new members (in current but not in knownMembers)
    local newMemberSet = {}
    local hasNew = false
    for short in pairs(currentRoster) do
        if not knownMembers[short] then
            newMemberSet[short] = true
            hasNew = true
        end
    end

    -- Promote only new members
    if hasNew then
        local settings = PRT:GetSetting("autoInvite")
        if settings and settings.promoteEnabled and IsInRaid() and UnitIsGroupLeader("player") then
            local promoteSet = {}
            for _, name in ipairs(SplitNames(settings.promoteNames)) do
                promoteSet[ShortName(name)] = true
            end

            for unit in PRT:IterateGroup() do
                local name = UnitName(unit)
                if name then
                    local short = ShortName(name)
                    if newMemberSet[short] and promoteSet[short] then
                        PromoteToAssistant(unit)
                    end
                end
            end
        end
    end

    -- Update snapshot
    knownMembers = currentRoster
end

function AutoInvite:OnGuildRosterUpdate()
    if not pendingMassInvite then
        return
    end
    pendingMassInvite = false

    local ranks = massInviteRanks
    massInviteRanks = {}

    local count = 0
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and ranks[rankIndex] and not IsPlayerInGroup(name) and not IsInPendingQueue(name) then
            count = count + 1
            local inviteName = name
            local delay = count * 0.2
            C_Timer.After(delay, function()
                QueueOrInvite(inviteName, function()
                    C_PartyInfo.InviteUnit(inviteName)
                end)
            end)
        end
    end

    if count > 0 then
        print(string.format("|cFF00FF00PurplexityRaidTools:|r Inviting %d guild members.", count))
    else
        print("|cFF00FF00PurplexityRaidTools:|r No matching guild members found to invite.")
    end
end

--------------------------------------------------------------------------------
-- Public Actions
--------------------------------------------------------------------------------

function AutoInvite:InviteByRank()
    local settings = PRT:GetSetting("autoInvite")
    if not settings then
        return
    end

    massInviteRanks = {}
    local hasRanks = false
    for rankIndex, enabled in pairs(settings.inviteRanks) do
        if enabled then
            massInviteRanks[rankIndex] = true
            hasRanks = true
        end
    end

    if not hasRanks then
        print("|cFFFF0000PurplexityRaidTools:|r No ranks selected for mass invite.")
        return
    end

    pendingMassInvite = true
    C_GuildInfo.GuildRoster()
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Auto-Invite", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -60)
    container:SetPoint("BOTTOMRIGHT", -8, 8)
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(container:GetWidth() - 40)
    scrollChild:SetHeight(900)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0
    local ROW_HEIGHT = 32

    local function GetSettings()
        return PRT:GetSetting("autoInvite")
    end


    --------------------------------------------------------------------
    -- Section 1: Whisper Invite
    --------------------------------------------------------------------

    local whisperHeader = PRT.Components.GetHeader(scrollChild, "Whisper Invite")
    whisperHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local whisperEnabledCB = PRT.Components.GetCheckbox(scrollChild, "Enable Whisper Invites", function(value)
        GetSettings().whisperInviteEnabled = value
    end)
    whisperEnabledCB:SetPoint("TOPLEFT", 0, yOffset)
    whisperEnabledCB:SetValue(GetSettings().whisperInviteEnabled)
    yOffset = yOffset - ROW_HEIGHT

    -- Keywords edit box
    local keywordsRow = CreateFrame("Frame", nil, scrollChild)
    keywordsRow:SetHeight(ROW_HEIGHT)
    keywordsRow:SetPoint("TOPLEFT", 0, yOffset)
    keywordsRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    local keywordsLabel = keywordsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keywordsLabel:SetPoint("LEFT", 20, 0)
    keywordsLabel:SetPoint("RIGHT", keywordsRow, "CENTER", -30, 0)
    keywordsLabel:SetJustifyH("RIGHT")
    keywordsLabel:SetText("Keywords")

    local keywordsEditBox = CreateFrame("EditBox", nil, keywordsRow, "InputBoxTemplate")
    keywordsEditBox:SetHeight(20)
    keywordsEditBox:SetPoint("LEFT", keywordsRow, "CENTER", -15, 0)
    keywordsEditBox:SetPoint("RIGHT", keywordsRow, "RIGHT", -20, 0)
    keywordsEditBox:SetAutoFocus(false)
    keywordsEditBox:SetText(GetSettings().keywords)

    keywordsEditBox:SetScript("OnEnterPressed", function(self)
        local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
        GetSettings().keywords = text
        self:SetText(text)
        self:ClearFocus()
    end)

    keywordsEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    keywordsEditBox:SetScript("OnEditFocusLost", function(self)
        local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
        GetSettings().keywords = text
        self:SetText(text)
    end)

    yOffset = yOffset - ROW_HEIGHT

    local guildOnlyCB = PRT.Components.GetCheckbox(scrollChild, "Guild Members Only", function(value)
        GetSettings().guildOnly = value
    end)
    guildOnlyCB:SetPoint("TOPLEFT", 0, yOffset)
    guildOnlyCB:SetValue(GetSettings().guildOnly)
    yOffset = yOffset - ROW_HEIGHT

    --------------------------------------------------------------------
    -- Section 2: Guild Invite
    --------------------------------------------------------------------

    yOffset = yOffset - 10

    local guildHeader = PRT.Components.GetHeader(scrollChild, "Guild Invite")
    guildHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local infoLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    infoLabel:SetPoint("TOPLEFT", 20, yOffset)
    infoLabel:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
    infoLabel:SetJustifyH("LEFT")
    infoLabel:SetText("Select ranks below, then press the button to invite all online members of those ranks.")
    yOffset = yOffset - 20

    -- Save where dynamic rank content begins
    local rankStartY = yOffset

    -- Track dynamic rank checkboxes for cleanup
    local rankCheckboxes = {}

    -- Elements positioned dynamically after ranks
    local inviteButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    inviteButton:SetSize(140, 22)
    inviteButton:SetText("Invite by Rank")

    inviteButton:SetScript("OnClick", function()
        AutoInvite:InviteByRank()
    end)

    --------------------------------------------------------------------
    -- Section 3: Auto-Promote
    --------------------------------------------------------------------

    local promoteHeader = PRT.Components.GetHeader(scrollChild, "Auto-Promote")

    local promoteEnabledCB = PRT.Components.GetCheckbox(scrollChild, "Enable Auto-Promote", function(value)
        GetSettings().promoteEnabled = value
    end)

    -- Promote names edit box
    local promoteRow = CreateFrame("Frame", nil, scrollChild)
    promoteRow:SetHeight(ROW_HEIGHT)

    local promoteLabel = promoteRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    promoteLabel:SetPoint("LEFT", 20, 0)
    promoteLabel:SetPoint("RIGHT", promoteRow, "CENTER", -30, 0)
    promoteLabel:SetJustifyH("RIGHT")
    promoteLabel:SetText("Player Names")

    local promoteEditBox = CreateFrame("EditBox", nil, promoteRow, "InputBoxTemplate")
    promoteEditBox:SetHeight(20)
    promoteEditBox:SetPoint("LEFT", promoteRow, "CENTER", -15, 0)
    promoteEditBox:SetPoint("RIGHT", promoteRow, "RIGHT", -20, 0)
    promoteEditBox:SetAutoFocus(false)

    promoteEditBox:SetScript("OnEnterPressed", function(self)
        local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
        GetSettings().promoteNames = text
        self:SetText(text)
        self:ClearFocus()
    end)

    promoteEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    promoteEditBox:SetScript("OnEditFocusLost", function(self)
        local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
        GetSettings().promoteNames = text
        self:SetText(text)
    end)

    --------------------------------------------------------------------
    -- Dynamic Layout (refreshed on show)
    --------------------------------------------------------------------

    container:SetScript("OnShow", function()
        -- Refresh whisper invite widgets from saved settings
        local settings = GetSettings()
        whisperEnabledCB:SetValue(settings.whisperInviteEnabled)
        keywordsEditBox:SetText(settings.keywords)
        guildOnlyCB:SetValue(settings.guildOnly)

        -- Hide old rank checkboxes
        for _, cb in ipairs(rankCheckboxes) do
            cb:Hide()
        end
        rankCheckboxes = {}

        local dynY = rankStartY
        local numRanks = GuildControlGetNumRanks()

        for rankIdx = 1, numRanks do
            local rankName = GuildControlGetRankName(rankIdx)
            local storedIndex = rankIdx - 1

            local cb = PRT.Components.GetCheckbox(scrollChild, rankName, function(value)
                GetSettings().inviteRanks[storedIndex] = value
            end)
            cb:SetPoint("TOPLEFT", 0, dynY)
            cb:SetValue(settings.inviteRanks[storedIndex] or false)
            table.insert(rankCheckboxes, cb)
            dynY = dynY - ROW_HEIGHT
        end

        -- Position invite button below ranks
        inviteButton:ClearAllPoints()
        inviteButton:SetPoint("TOPLEFT", 20, dynY - 4)
        dynY = dynY - 32

        -- Position promote section
        dynY = dynY - 10

        promoteHeader:ClearAllPoints()
        promoteHeader:SetPoint("TOPLEFT", 10, dynY)
        promoteHeader:SetPoint("RIGHT", scrollChild, "RIGHT", -10, 0)
        dynY = dynY - 28

        promoteEnabledCB:ClearAllPoints()
        promoteEnabledCB:SetPoint("TOPLEFT", 0, dynY)
        promoteEnabledCB:SetValue(settings.promoteEnabled)
        dynY = dynY - ROW_HEIGHT

        promoteRow:ClearAllPoints()
        promoteRow:SetPoint("TOPLEFT", 0, dynY)
        promoteRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        promoteEditBox:SetText(settings.promoteNames)
        dynY = dynY - ROW_HEIGHT

        scrollChild:SetHeight(math.abs(dynY) + 20)
    end)

    return container
end)

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function AutoInvite:GetEnabledSetting()
    local settings = PRT:GetSetting("autoInvite")
    return settings and (settings.whisperInviteEnabled or settings.promoteEnabled)
end

function AutoInvite:OnEnable()
    -- Pre-populate knownMembers so existing group members
    -- aren't treated as "new joins" on first roster update
    knownMembers = {}
    if IsInRaid() then
        for unit in PRT:IterateGroup() do
            local name = UnitName(unit)
            if name then
                knownMembers[ShortName(name)] = true
            end
        end
    end

    self.eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
    self.eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_WHISPER" then
            local message, senderName = ...
            AutoInvite:OnWhisper(message, senderName)
        elseif event == "CHAT_MSG_BN_WHISPER" then
            local message, senderName, _, _, _, _, _, _, _, _, _, _, bnSenderID = ...
            AutoInvite:OnBNetWhisper(message, senderName, bnSenderID)
        elseif event == "GROUP_ROSTER_UPDATE" then
            AutoInvite:OnGroupRosterUpdate()
        elseif event == "GUILD_ROSTER_UPDATE" then
            AutoInvite:OnGuildRosterUpdate()
        end
    end)
end

function AutoInvite:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
end

