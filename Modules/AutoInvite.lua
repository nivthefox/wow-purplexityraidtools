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
-- True once we have requested a party-to-raid conversion and are waiting for it
-- to complete. GROUP_ROSTER_UPDATE keeps retrying the conversion while set, and
-- queued invites are held until it clears (i.e. until IsInRaid() is true).
local convertPending = false

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
    if not IsInRaid() and (convertPending or GetNumGroupMembers() >= 4) then
        -- A full party would overflow, or a conversion is already in flight.
        -- Request the conversion (once) and hold the invite until we are a raid.
        if not convertPending then
            convertPending = true
            C_PartyInfo.ConvertToRaid()
        end
        table.insert(pendingInvites, { name = name, inviteFunc = inviteFunc })
    else
        inviteFunc()
    end
end

-- Send an invite to a named character on a short stagger so a burst of invites
-- does not trip the client's invite throttle.
local function StaggerInvite(index, name)
    C_Timer.After(index * 0.2, function()
        if not IsPlayerInGroup(name) then
            C_PartyInfo.InviteUnit(name)
        end
    end)
end

local function ProcessInviteQueue()
    if not IsInRaid() then
        return
    end
    local queue = pendingInvites
    pendingInvites = {}
    for index, entry in ipairs(queue) do
        C_Timer.After(index * 0.2, entry.inviteFunc)
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
    -- Drive the party-to-raid conversion. Once we are a raid, clear the flag and
    -- flush any invites that were queued while waiting. While still a party with
    -- a pending conversion, keep asking to convert until it takes effect.
    if IsInRaid() then
        convertPending = false
        ProcessInviteQueue()
    elseif convertPending then
        C_PartyInfo.ConvertToRaid()
    end

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

    -- Collect every online guild member of a selected rank who is not already in
    -- the group or waiting on an invite.
    local candidates = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and ranks[rankIndex] and not IsPlayerInGroup(name) and not IsInPendingQueue(name) then
            table.insert(candidates, name)
        end
    end

    if #candidates == 0 then
        print("|cFF00FF00PurplexityRaidTools:|r No matching guild members found to invite.")
        return
    end

    print(string.format("|cFF00FF00PurplexityRaidTools:|r Inviting %d guild members.", #candidates))

    -- GetNumGroupMembers() reports 0 when solo; count yourself so the party-size
    -- math lines up with the 5-player party cap.
    local groupSize = GetNumGroupMembers()
    if groupSize == 0 then
        groupSize = 1
    end

    if IsInRaid() or (groupSize + #candidates) <= 5 then
        -- Already a raid, or everyone fits in a party: just invite them all.
        for index, name in ipairs(candidates) do
            StaggerInvite(index, name)
        end
    else
        -- More people than a party holds. Invite enough to fill the party, then
        -- convert to a raid and queue the rest to go out once the conversion
        -- completes (GROUP_ROSTER_UPDATE flushes the queue). This mirrors MRT's
        -- InviteTool behaviour and avoids invites bouncing off a full party.
        local partySlots = 5 - groupSize
        for index, name in ipairs(candidates) do
            if index <= partySlots then
                StaggerInvite(index, name)
            else
                local inviteName = name
                table.insert(pendingInvites, {
                    name = inviteName,
                    inviteFunc = function()
                        C_PartyInfo.InviteUnit(inviteName)
                    end,
                })
            end
        end

        convertPending = true
        -- If we are already in a party, kick off the conversion now. When solo,
        -- there is no group to convert yet; the first invitee to accept triggers
        -- GROUP_ROSTER_UPDATE, which converts and then flushes the queue.
        if IsInGroup() then
            C_PartyInfo.ConvertToRaid()
        end
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
    local ROW_HEIGHT = 32
    local LABEL_WIDTH = 200

    local function GetSettings()
        return PRT:GetSetting("autoInvite")
    end

    --------------------------------------------------------------------
    -- Sub-tab: Whispers
    --------------------------------------------------------------------

    local function SetupWhispers(panel)
        local yOffset = -10

        local whisperEnabledCB = PRT.Components.GetCheckbox(panel, "Enabled", function(value)
            GetSettings().whisperInviteEnabled = value
        end)
        whisperEnabledCB:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        -- Keywords edit box
        local keywordsRow = CreateFrame("Frame", nil, panel)
        keywordsRow:SetHeight(ROW_HEIGHT)
        keywordsRow:SetPoint("TOPLEFT", 0, yOffset)
        keywordsRow:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        local keywordsLabel = keywordsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        keywordsLabel:SetPoint("LEFT", 20, 0)
        keywordsLabel:SetPoint("RIGHT", keywordsRow, "LEFT", LABEL_WIDTH - 30, 0)
        keywordsLabel:SetJustifyH("RIGHT")
        keywordsLabel:SetText("Keywords")

        local keywordsEditBox = CreateFrame("EditBox", nil, keywordsRow, "InputBoxTemplate")
        keywordsEditBox:SetHeight(20)
        keywordsEditBox:SetPoint("LEFT", keywordsRow, "LEFT", LABEL_WIDTH - 15, 0)
        keywordsEditBox:SetPoint("RIGHT", keywordsRow, "RIGHT", -20, 0)
        keywordsEditBox:SetAutoFocus(false)

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

        local guildOnlyCB = PRT.Components.GetCheckbox(panel, "Guild Members Only", function(value)
            GetSettings().guildOnly = value
        end)
        guildOnlyCB:SetPoint("TOPLEFT", 0, yOffset)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            whisperEnabledCB:SetValue(settings.whisperInviteEnabled)
            keywordsEditBox:SetText(settings.keywords)
            guildOnlyCB:SetValue(settings.guildOnly)
        end)
    end

    --------------------------------------------------------------------
    -- Sub-tab: Guild
    --------------------------------------------------------------------

    local function SetupGuild(panel)
        local infoLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        infoLabel:SetPoint("TOPLEFT", 20, -10)
        infoLabel:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
        infoLabel:SetJustifyH("LEFT")
        infoLabel:SetText("Select ranks below, then press the button to invite all online members of those ranks.")

        -- Track dynamic rank checkboxes for cleanup
        local rankCheckboxes = {}

        local inviteButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        inviteButton:SetSize(140, 22)
        inviteButton:SetText("Invite by Rank")

        inviteButton:SetScript("OnClick", function()
            AutoInvite:InviteByRank()
        end)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()

            -- Hide old rank checkboxes
            for _, cb in ipairs(rankCheckboxes) do
                cb:Hide()
            end
            rankCheckboxes = {}

            local dynY = -34
            local numRanks = GuildControlGetNumRanks()

            for rankIdx = 1, numRanks do
                local rankName = GuildControlGetRankName(rankIdx)
                local storedIndex = rankIdx - 1

                local cb = PRT.Components.GetCheckbox(panel, rankName, function(value)
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
        end)
    end

    --------------------------------------------------------------------
    -- Sub-tab: Auto Promote
    --------------------------------------------------------------------

    local function SetupAutoPromote(panel)
        local yOffset = -10

        local promoteEnabledCB = PRT.Components.GetCheckbox(panel, "Enabled", function(value)
            GetSettings().promoteEnabled = value
        end)
        promoteEnabledCB:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        -- Promote names edit box
        local promoteRow = CreateFrame("Frame", nil, panel)
        promoteRow:SetHeight(ROW_HEIGHT)
        promoteRow:SetPoint("TOPLEFT", 0, yOffset)
        promoteRow:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        local promoteLabel = promoteRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        promoteLabel:SetPoint("LEFT", 20, 0)
        promoteLabel:SetPoint("RIGHT", promoteRow, "LEFT", LABEL_WIDTH - 30, 0)
        promoteLabel:SetJustifyH("RIGHT")
        promoteLabel:SetText("Player Names")

        local promoteEditBox = CreateFrame("EditBox", nil, promoteRow, "InputBoxTemplate")
        promoteEditBox:SetHeight(20)
        promoteEditBox:SetPoint("LEFT", promoteRow, "LEFT", LABEL_WIDTH - 15, 0)
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

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            promoteEnabledCB:SetValue(settings.promoteEnabled)
            promoteEditBox:SetText(settings.promoteNames)
        end)
    end

    return PRT.Components.GetSubTabGroup(parent, {
        { name = "Whisper Invites", setup = SetupWhispers },
        { name = "Guild", setup = SetupGuild },
        { name = "Auto Promote", setup = SetupAutoPromote },
    })
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

