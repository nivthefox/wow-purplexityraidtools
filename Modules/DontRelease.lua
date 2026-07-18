-- DontRelease: Prevents accidental spirit releases in configurable content
local PRT = PurplexityRaidTools
local DontRelease = {}
PRT.DontRelease = DontRelease
PRT:RegisterModule("dontRelease", DontRelease)

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

function DontRelease:IsBlockingEnabled()
    local settings = PRT:GetSetting("dontRelease")
    if not settings or not settings.enabled then
        return false
    end
    return PRT.IsContentTypeEnabled(settings.contentTypes)
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
    button:SetFrameStrata("TOOLTIP")
    button:SetFrameLevel(1000)
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
    local ROW_HEIGHT = 24

    local function GetSettings()
        return PRT:GetSetting("dontRelease")
    end


    -- General Section
    local generalHeader = PRT.Components.GetHeader(scrollChild, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enable Don't Release", function(value)
        GetSettings().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local delaySlider = PRT.Components.GetSliderWithInput(scrollChild, "Release Delay (seconds)", 1, 10, 1, false, function(value)
        GetSettings().delay = value
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

    for i, info in ipairs(contentCheckboxes) do
        local checkbox = PRT.Components.GetCheckbox(scrollChild, info.label, function(value)
            local settings = GetSettings()
            if #info.path == 2 then
                settings[info.path[1]][info.path[2]] = value
            else
                settings[info.path[1]][info.path[2]][info.path[3]] = value
            end
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        contentCheckboxes[i].widget = checkbox

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
        GetSettings().requireModifier = value
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
        GetSettings().randomizeModifier = value
    end)
    randomizeCheckbox:SetPoint("TOPLEFT", 20, yOffset)
    randomizeCheckbox:SetValue(GetSettings().randomizeModifier)
    if not GetSettings().requireModifier then
        randomizeCheckbox:SetAlpha(0.5)
        randomizeCheckbox:EnableMouse(false)
    end
    yOffset = yOffset - ROW_HEIGHT

    -- Refresh all widget values from saved settings on show
    container:SetScript("OnShow", function()
        local settings = GetSettings()
        enabledCheckbox:SetValue(settings.enabled)
        delaySlider:SetValue(settings.delay)
        for _, info in ipairs(contentCheckboxes) do
            local currentValue
            if #info.path == 2 then
                currentValue = settings[info.path[1]][info.path[2]]
            else
                currentValue = settings[info.path[1]][info.path[2]][info.path[3]]
            end
            info.widget:SetValue(currentValue)
        end
        requireModifierCheckbox:SetValue(settings.requireModifier)
        randomizeCheckbox:SetValue(settings.randomizeModifier)
        if settings.requireModifier then
            randomizeCheckbox:SetAlpha(1)
            randomizeCheckbox:EnableMouse(true)
        else
            randomizeCheckbox:SetAlpha(0.5)
            randomizeCheckbox:EnableMouse(false)
        end
    end)

    return container
end)

