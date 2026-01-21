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
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = false, normal = false, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local delayAccumulated = 0
local requiredModifier = nil
local overlayButton = nil
local blockingActive = false

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
    return math.max(0, settings.delay - delayAccumulated)
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
-- Overlay Button
--------------------------------------------------------------------------------

local function CreateOverlayButton()
    local button = CreateFrame("Button", "PRT_DontReleaseOverlay", UIParent, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetFrameStrata("DIALOG")
    button:SetFrameLevel(100)
    button:Hide()

    button:SetScript("OnClick", function()
        -- Absorb click - do nothing
    end)

    button:SetScript("OnUpdate", function(self, elapsed)
        if not blockingActive then return end

        local settings = PRT:GetSetting("dontRelease")
        local modifierRequired = settings.requireModifier
        local modifierHeld = not modifierRequired or DontRelease:IsModifierSatisfied()

        if modifierRequired then
            if modifierHeld then
                delayAccumulated = delayAccumulated + elapsed
            else
                delayAccumulated = 0
            end
        else
            delayAccumulated = delayAccumulated + elapsed
        end

        local delayRemaining = settings.delay - delayAccumulated

        if delayRemaining > 0 then
            if modifierRequired and not modifierHeld then
                self:SetText(string.format("Hold [%s]", requiredModifier))
            else
                self:SetText(string.format("%.1f", delayRemaining))
            end
            self:EnableMouse(true)
            self:SetAlpha(1)
        elseif modifierRequired and not modifierHeld then
            delayAccumulated = 0
            self:SetText(string.format("Hold [%s]", requiredModifier))
            self:EnableMouse(true)
            self:SetAlpha(1)
        else
            self:EnableMouse(false)
            self:SetAlpha(0)
        end
    end)

    return button
end

local function PositionOverlay(dialog)
    if not overlayButton then
        overlayButton = CreateOverlayButton()
    end

    local button1 = dialog:GetButton1()
    if not button1 then return end

    overlayButton:ClearAllPoints()
    overlayButton:SetPoint("CENTER", button1, "CENTER", 0, 0)
    overlayButton:SetSize(button1:GetSize())
end

--------------------------------------------------------------------------------
-- Hook Handlers
--------------------------------------------------------------------------------

function DontRelease:OnDeathPopupShow(dialog)
    if not self:IsBlockingEnabled() then
        blockingActive = false
        if overlayButton then
            overlayButton:Hide()
        end
        return
    end

    delayAccumulated = 0
    blockingActive = true

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

    PositionOverlay(dialog)

    if settings.requireModifier then
        overlayButton:SetText(string.format("Hold [%s]", requiredModifier))
    else
        overlayButton:SetText(string.format("%.1f", settings.delay))
    end
    overlayButton:EnableMouse(true)
    overlayButton:SetAlpha(1)
    overlayButton:Show()
end

function DontRelease:OnDeathPopupHide(dialog)
    blockingActive = false
    delayAccumulated = 0
    if overlayButton then
        overlayButton:Hide()
        overlayButton:EnableMouse(true)
        overlayButton:SetAlpha(1)
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
    local originalOnHide = deathDialog.OnHide

    deathDialog.OnShow = function(dialog, data)
        if originalOnShow then
            originalOnShow(dialog, data)
        end
        DontRelease:OnDeathPopupShow(dialog)
    end

    deathDialog.OnHide = function(dialog, data)
        DontRelease:OnDeathPopupHide(dialog)
        if originalOnHide then
            originalOnHide(dialog, data)
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

    -- Flat list of all content types
    local contentCheckboxes = {
        { label = "Open World", path = {"contentTypes", "openWorld"} },
        { label = "Dungeon (Normal)", path = {"contentTypes", "dungeon", "normal"} },
        { label = "Dungeon (Heroic)", path = {"contentTypes", "dungeon", "heroic"} },
        { label = "Dungeon (Mythic)", path = {"contentTypes", "dungeon", "mythic"} },
        { label = "Dungeon (Mythic+)", path = {"contentTypes", "dungeon", "mythicPlus"} },
        { label = "Raid (LFR)", path = {"contentTypes", "raid", "lfr"} },
        { label = "Raid (Normal)", path = {"contentTypes", "raid", "normal"} },
        { label = "Raid (Heroic)", path = {"contentTypes", "raid", "heroic"} },
        { label = "Raid (Mythic)", path = {"contentTypes", "raid", "mythic"} },
        { label = "Scenario (Normal)", path = {"contentTypes", "scenario", "normal"} },
        { label = "Scenario (Heroic)", path = {"contentTypes", "scenario", "heroic"} },
    }

    for _, info in ipairs(contentCheckboxes) do
        local checkbox = PRT.Components.GetCheckbox(scrollChild, info.label, function(value)
            local settings = EnsureSettingsTable()
            if #info.path == 2 then
                settings[info.path[1]][info.path[2]] = value
            else
                settings[info.path[1]][info.path[2]][info.path[3]] = value
            end
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)

        local settings = GetSettings()
        local currentValue
        if #info.path == 2 then
            currentValue = settings[info.path[1]][info.path[2]]
        else
            currentValue = settings[info.path[1]][info.path[2]][info.path[3]]
        end
        checkbox:SetValue(currentValue)

        yOffset = yOffset - ROW_HEIGHT
    end

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

    local renameButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    renameButton:SetSize(80, 22)
    renameButton:SetPoint("LEFT", deleteButton, "RIGHT", 5, 0)
    renameButton:SetText("Rename")
    renameButton:SetScript("OnClick", function()
        local currentName = PRT.Profiles:GetCurrentName()
        StaticPopup_Show("PRT_RENAME_PROFILE", currentName)
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

StaticPopupDialogs["PRT_RENAME_PROFILE"] = {
    text = "Enter a new name for profile '%s':",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local newName = self.editBox:GetText()
        local oldName = PRT.Profiles:GetCurrentName()
        if newName and newName ~= "" then
            if PRT.Profiles:Rename(oldName, newName) then
                print("|cFF00FF00PurplexityRaidTools:|r Renamed profile to: " .. newName)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Could not rename profile. Name may already exist.")
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local newName = self:GetText()
        local oldName = PRT.Profiles:GetCurrentName()
        if newName and newName ~= "" then
            if PRT.Profiles:Rename(oldName, newName) then
                print("|cFF00FF00PurplexityRaidTools:|r Renamed profile to: " .. newName)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Could not rename profile. Name may already exist.")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
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
