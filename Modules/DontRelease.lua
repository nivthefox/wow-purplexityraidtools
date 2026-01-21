-- DontRelease: Prevents accidental spirit releases in configurable content
local PRT = PurplexityRaidTools
local DontRelease = {}
PRT.DontRelease = DontRelease

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.dontRelease = {
    enabled = true,
    delay = 2,
    requireModifier = false,
    randomizeModifier = false,
    contentTypes = {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = true, mythicPlus = true },
        raid = { lfr = false, normal = false, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local deathPopupShownTime = 0
local requiredModifier = nil
local isBlocking = false
local originalButtonText = nil

--------------------------------------------------------------------------------
-- Modifier Keys
--------------------------------------------------------------------------------

local MODIFIERS = {
    { name = "Ctrl", check = IsControlKeyDown },
    { name = "Alt", check = IsAltKeyDown },
    { name = "Shift", check = IsShiftKeyDown },
}

--------------------------------------------------------------------------------
-- Content Detection
--------------------------------------------------------------------------------

local function GetCurrentContentType()
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

function DontRelease:IsBlockingEnabled()
    local settings = PRT:GetSetting("dontRelease")
    if not settings or not settings.enabled then
        return false
    end

    local contentType, subType = GetCurrentContentType()
    if not contentType then
        return false
    end

    if contentType == "openWorld" then
        return settings.contentTypes.openWorld == true
    end

    local contentSettings = settings.contentTypes[contentType]
    if not contentSettings then
        return false
    end

    if subType then
        return contentSettings[subType] == true
    end

    return false
end

--------------------------------------------------------------------------------
-- Delay and Modifier Logic
--------------------------------------------------------------------------------

function DontRelease:GetDelayRemaining()
    local settings = PRT:GetSetting("dontRelease")
    local elapsed = GetTime() - deathPopupShownTime
    return math.max(0, settings.delay - elapsed)
end

function DontRelease:IsModifierSatisfied()
    local settings = PRT:GetSetting("dontRelease")
    if not settings.requireModifier then
        return true
    end
    if not requiredModifier then
        return true
    end

    local heldCount = 0
    local correctHeld = false

    for _, mod in ipairs(MODIFIERS) do
        if mod.check() then
            heldCount = heldCount + 1
            if mod.name == requiredModifier then
                correctHeld = true
            end
        end
    end

    return heldCount == 1 and correctHeld
end

function DontRelease:ShouldBlockRelease()
    if not self:IsBlockingEnabled() then
        return false
    end
    if self:GetDelayRemaining() > 0 then
        return true
    end
    if not self:IsModifierSatisfied() then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Hook Handlers
--------------------------------------------------------------------------------

function DontRelease:OnDeathPopupShow(dialog)
    if not self:IsBlockingEnabled() then
        isBlocking = false
        return
    end

    deathPopupShownTime = GetTime()
    isBlocking = true

    local settings = PRT:GetSetting("dontRelease")
    if settings.requireModifier then
        if settings.randomizeModifier then
            requiredModifier = MODIFIERS[math.random(#MODIFIERS)].name
        else
            requiredModifier = "Ctrl"
        end
    else
        requiredModifier = nil
    end

    local button1 = dialog:GetButton1()
    if button1 then
        originalButtonText = button1:GetText()
    end
end

function DontRelease:OnDeathPopupUpdate(dialog, elapsed)
    if not isBlocking then
        return false
    end
    if not self:IsBlockingEnabled() then
        isBlocking = false
        return false
    end

    local button1 = dialog:GetButton1()
    if not button1 then
        return false
    end

    local delayRemaining = self:GetDelayRemaining()
    local settings = PRT:GetSetting("dontRelease")

    if delayRemaining > 0 then
        button1:Disable()
        button1:SetText(string.format("%.1f", delayRemaining))
        return true
    elseif settings.requireModifier and not self:IsModifierSatisfied() then
        button1:Disable()
        button1:SetText(string.format("Hold [%s]", requiredModifier))
        return true
    else
        button1:Enable()
        if originalButtonText then
            button1:SetText(originalButtonText)
        end
        isBlocking = false
        return false
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

function DontRelease:Initialize()
    local deathDialog = StaticPopupDialogs["DEATH"]
    if not deathDialog then
        return
    end

    local originalOnShow = deathDialog.OnShow
    local originalOnUpdate = deathDialog.OnUpdate
    local originalOnButton1 = deathDialog.OnButton1

    deathDialog.OnShow = function(dialog, data)
        DontRelease:OnDeathPopupShow(dialog)
        if originalOnShow then
            return originalOnShow(dialog, data)
        end
    end

    deathDialog.OnUpdate = function(dialog, elapsed)
        local handled = DontRelease:OnDeathPopupUpdate(dialog, elapsed)
        if not handled and originalOnUpdate then
            return originalOnUpdate(dialog, elapsed)
        end
    end

    deathDialog.OnButton1 = function(dialog, data)
        if DontRelease:ShouldBlockRelease() then
            return true
        end
        if originalOnButton1 then
            return originalOnButton1(dialog, data)
        end
    end
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Don't Release", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -60)
    container:SetPoint("BOTTOMRIGHT", -8, 8)
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(container:GetWidth() - 40)
    scrollChild:SetHeight(600)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0
    local ROW_HEIGHT = 32

    local function GetSettings()
        return PRT:GetSetting("dontRelease")
    end

    local function GetProfile()
        return PRT.Profiles:GetCurrent()
    end

    local function EnsureSettingsTable()
        local profile = GetProfile()
        if not profile.dontRelease then
            profile.dontRelease = {}
            for k, v in pairs(PRT.defaults.dontRelease) do
                if type(v) == "table" then
                    profile.dontRelease[k] = {}
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" then
                            profile.dontRelease[k][k2] = {}
                            for k3, v3 in pairs(v2) do
                                profile.dontRelease[k][k2][k3] = v3
                            end
                        else
                            profile.dontRelease[k][k2] = v2
                        end
                    end
                else
                    profile.dontRelease[k] = v
                end
            end
        end
        return profile.dontRelease
    end

    -- General Section
    local generalHeader = PRT.Components.GetHeader(scrollChild, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enable Don't Release", function(value)
        EnsureSettingsTable().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local delaySlider = PRT.Components.GetSliderWithInput(scrollChild, "Release Delay (seconds)", 1, 10, 1, false, function(value)
        EnsureSettingsTable().delay = value
    end)
    delaySlider:SetPoint("TOPLEFT", 0, yOffset)
    delaySlider:SetValue(GetSettings().delay)
    yOffset = yOffset - ROW_HEIGHT

    -- Content Types Section
    yOffset = yOffset - 10
    local contentHeader = PRT.Components.GetHeader(scrollChild, "Block Release In")
    contentHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local openWorldCheckbox = PRT.Components.GetCheckbox(scrollChild, "Open World", function(value)
        EnsureSettingsTable().contentTypes.openWorld = value
    end)
    openWorldCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    openWorldCheckbox:SetValue(GetSettings().contentTypes.openWorld)
    yOffset = yOffset - ROW_HEIGHT

    -- Dungeon sub-header
    local dungeonLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dungeonLabel:SetPoint("TOPLEFT", 20, yOffset - 6)
    dungeonLabel:SetText("Dungeons:")
    yOffset = yOffset - 24

    local dungeonNormalCheckbox = PRT.Components.GetCheckbox(scrollChild, "Normal", function(value)
        EnsureSettingsTable().contentTypes.dungeon.normal = value
    end)
    dungeonNormalCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    dungeonNormalCheckbox:SetValue(GetSettings().contentTypes.dungeon.normal)
    yOffset = yOffset - ROW_HEIGHT

    local dungeonHeroicCheckbox = PRT.Components.GetCheckbox(scrollChild, "Heroic", function(value)
        EnsureSettingsTable().contentTypes.dungeon.heroic = value
    end)
    dungeonHeroicCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    dungeonHeroicCheckbox:SetValue(GetSettings().contentTypes.dungeon.heroic)
    yOffset = yOffset - ROW_HEIGHT

    local dungeonMythicCheckbox = PRT.Components.GetCheckbox(scrollChild, "Mythic", function(value)
        EnsureSettingsTable().contentTypes.dungeon.mythic = value
    end)
    dungeonMythicCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    dungeonMythicCheckbox:SetValue(GetSettings().contentTypes.dungeon.mythic)
    yOffset = yOffset - ROW_HEIGHT

    local dungeonMythicPlusCheckbox = PRT.Components.GetCheckbox(scrollChild, "Mythic+", function(value)
        EnsureSettingsTable().contentTypes.dungeon.mythicPlus = value
    end)
    dungeonMythicPlusCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    dungeonMythicPlusCheckbox:SetValue(GetSettings().contentTypes.dungeon.mythicPlus)
    yOffset = yOffset - ROW_HEIGHT

    -- Raid sub-header
    local raidLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 20, yOffset - 6)
    raidLabel:SetText("Raids:")
    yOffset = yOffset - 24

    local raidLFRCheckbox = PRT.Components.GetCheckbox(scrollChild, "LFR", function(value)
        EnsureSettingsTable().contentTypes.raid.lfr = value
    end)
    raidLFRCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    raidLFRCheckbox:SetValue(GetSettings().contentTypes.raid.lfr)
    yOffset = yOffset - ROW_HEIGHT

    local raidNormalCheckbox = PRT.Components.GetCheckbox(scrollChild, "Normal", function(value)
        EnsureSettingsTable().contentTypes.raid.normal = value
    end)
    raidNormalCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    raidNormalCheckbox:SetValue(GetSettings().contentTypes.raid.normal)
    yOffset = yOffset - ROW_HEIGHT

    local raidHeroicCheckbox = PRT.Components.GetCheckbox(scrollChild, "Heroic", function(value)
        EnsureSettingsTable().contentTypes.raid.heroic = value
    end)
    raidHeroicCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    raidHeroicCheckbox:SetValue(GetSettings().contentTypes.raid.heroic)
    yOffset = yOffset - ROW_HEIGHT

    local raidMythicCheckbox = PRT.Components.GetCheckbox(scrollChild, "Mythic", function(value)
        EnsureSettingsTable().contentTypes.raid.mythic = value
    end)
    raidMythicCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    raidMythicCheckbox:SetValue(GetSettings().contentTypes.raid.mythic)
    yOffset = yOffset - ROW_HEIGHT

    -- Scenario sub-header
    local scenarioLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scenarioLabel:SetPoint("TOPLEFT", 20, yOffset - 6)
    scenarioLabel:SetText("Scenarios:")
    yOffset = yOffset - 24

    local scenarioNormalCheckbox = PRT.Components.GetCheckbox(scrollChild, "Normal", function(value)
        EnsureSettingsTable().contentTypes.scenario.normal = value
    end)
    scenarioNormalCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    scenarioNormalCheckbox:SetValue(GetSettings().contentTypes.scenario.normal)
    yOffset = yOffset - ROW_HEIGHT

    local scenarioHeroicCheckbox = PRT.Components.GetCheckbox(scrollChild, "Heroic", function(value)
        EnsureSettingsTable().contentTypes.scenario.heroic = value
    end)
    scenarioHeroicCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    scenarioHeroicCheckbox:SetValue(GetSettings().contentTypes.scenario.heroic)
    yOffset = yOffset - ROW_HEIGHT

    -- Modifier Key Section
    yOffset = yOffset - 10
    local modifierHeader = PRT.Components.GetHeader(scrollChild, "Modifier Key")
    modifierHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local randomizeCheckbox
    local requireModifierCheckbox = PRT.Components.GetCheckbox(scrollChild, "Require modifier key to release", function(value)
        EnsureSettingsTable().requireModifier = value
        if randomizeCheckbox then
            if value then
                randomizeCheckbox:SetAlpha(1)
                randomizeCheckbox:EnableMouse(true)
            else
                randomizeCheckbox:SetAlpha(0.5)
                randomizeCheckbox:EnableMouse(false)
            end
        end
    end)
    requireModifierCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    requireModifierCheckbox:SetValue(GetSettings().requireModifier)
    yOffset = yOffset - ROW_HEIGHT

    randomizeCheckbox = PRT.Components.GetCheckbox(scrollChild, "Randomize modifier (Ctrl/Alt/Shift)", function(value)
        EnsureSettingsTable().randomizeModifier = value
    end)
    randomizeCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    randomizeCheckbox:SetValue(GetSettings().randomizeModifier)
    if not GetSettings().requireModifier then
        randomizeCheckbox:SetAlpha(0.5)
        randomizeCheckbox:EnableMouse(false)
    end
    yOffset = yOffset - ROW_HEIGHT

    -- Profile Section
    yOffset = yOffset - 10
    local profileHeader = PRT.Components.GetHeader(scrollChild, "Profile")
    profileHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local profileDropdown = PRT.Components.GetBasicDropdown(
        scrollChild,
        "Active Profile:",
        function()
            local items = {}
            for _, name in ipairs(PRT.Profiles:GetNames()) do
                table.insert(items, { name = name, value = name })
            end
            return items
        end,
        function(value)
            return PRT.Profiles:GetCurrentName() == value
        end,
        function(value)
            PRT.Profiles:Switch(value)
        end
    )
    profileDropdown:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - ROW_HEIGHT

    -- Create/Clone/Delete buttons
    local buttonHolder = CreateFrame("Frame", nil, scrollChild)
    buttonHolder:SetPoint("TOPLEFT", 20, yOffset)
    buttonHolder:SetSize(400, 30)

    local createButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    createButton:SetSize(80, 22)
    createButton:SetPoint("LEFT", 0, 0)
    createButton:SetText("New")
    createButton:SetScript("OnClick", function()
        StaticPopup_Show("PRT_CREATE_PROFILE")
    end)

    local cloneButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    cloneButton:SetSize(80, 22)
    cloneButton:SetPoint("LEFT", createButton, "RIGHT", 5, 0)
    cloneButton:SetText("Clone")
    cloneButton:SetScript("OnClick", function()
        StaticPopup_Show("PRT_CLONE_PROFILE")
    end)

    local deleteButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    deleteButton:SetSize(80, 22)
    deleteButton:SetPoint("LEFT", cloneButton, "RIGHT", 5, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function()
        local currentName = PRT.Profiles:GetCurrentName()
        if currentName == "Default" then
            print("|cFFFF0000PurplexityRaidTools:|r Cannot delete the Default profile.")
            return
        end
        StaticPopup_Show("PRT_DELETE_PROFILE", currentName)
    end)

    return container
end)

--------------------------------------------------------------------------------
-- Profile Dialogs
--------------------------------------------------------------------------------

StaticPopupDialogs["PRT_CREATE_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if name and name ~= "" then
            if PRT.Profiles:Create(name) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Created and switched to profile: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            if PRT.Profiles:Create(name) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Created and switched to profile: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PRT_CLONE_PROFILE"] = {
    text = "Enter a name for the cloned profile:",
    button1 = "Clone",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        local currentName = PRT.Profiles:GetCurrentName()
        if name and name ~= "" then
            if PRT.Profiles:Create(name, currentName) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Cloned profile to: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        local currentName = PRT.Profiles:GetCurrentName()
        if name and name ~= "" then
            if PRT.Profiles:Create(name, currentName) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Cloned profile to: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PRT_DELETE_PROFILE"] = {
    text = "Are you sure you want to delete the profile '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local currentName = PRT.Profiles:GetCurrentName()
        PRT.Profiles:Switch("Default")
        if PRT.Profiles:Delete(currentName) then
            print("|cFF00FF00PurplexityRaidTools:|r Deleted profile: " .. currentName)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        DontRelease:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
