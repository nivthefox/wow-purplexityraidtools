local PRT = PurplexityRaidTools
local BattleResCounter = {}
PRT.BattleResCounter = BattleResCounter
PRT:RegisterModule("battleResCounter", BattleResCounter)

PRT.defaults.battleResCounter = {
    widgetEnabled = true,
    widgetScale = 100,
    widgetPosition = nil,
    zeroChargeOverlay = true,
    rosterRowEnabled = true,
    lockFrames = true,
}

local REBIRTH_SPELL_ID = 20484

local charges = 0
local maxCharges = 0
local started = 0
local duration = 0
local inEncounter = false
local pollTicker = nil
local widgetFrame = nil

local function FormatTimer()
    if charges >= maxCharges or duration == 0 then return "" end
    local remaining = math.max(0, duration - (GetTime() - started))
    return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
end

local function ReadCharges()
    local info = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
    if not info or not info.maxCharges or info.maxCharges == 0 then
        return nil
    end
    return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
end

function BattleResCounter:GetChargeState()
    return charges, inEncounter
end

function BattleResCounter:GetTimerText()
    return FormatTimer()
end

local function CreateWidget()
    local frame = CreateFrame("Frame", "PRT_BattleResWidget", UIParent)
    frame:SetSize(64, 64)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(C_Spell.GetSpellTexture(REBIRTH_SPELL_ID))
    frame.icon = icon

    local desatOverlay = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    desatOverlay:SetAllPoints()
    desatOverlay:SetTexture(C_Spell.GetSpellTexture(REBIRTH_SPELL_ID))
    desatOverlay:SetDesaturated(true)
    desatOverlay:SetVertexColor(0.4, 0.4, 0.4)
    desatOverlay:Hide()
    frame.desatOverlay = desatOverlay

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    local regions = { cooldown:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
            region:SetTexture(nil)
            region:Hide()
        end
    end
    frame.cooldown = cooldown

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countText:SetPoint("BOTTOMRIGHT", -2, 2)
    countText:Hide()
    frame.countText = countText

    local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("CENTER", 0, 0)
    timerText:Hide()
    frame.timerText = timerText

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(REBIRTH_SPELL_ID)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return frame
end

local function ShowEncounterState()
    widgetFrame.countText:SetText(charges)
    widgetFrame.countText:Show()

    local timerStr = FormatTimer()
    if timerStr ~= "" then
        widgetFrame.timerText:SetText(timerStr)
        widgetFrame.timerText:Show()
    else
        widgetFrame.timerText:Hide()
    end

    if charges < maxCharges and duration > 0 then
        widgetFrame.cooldown:SetCooldown(started, duration)
    else
        widgetFrame.cooldown:Clear()
    end

    local settings = PRT:GetSetting("battleResCounter")
    if charges == 0 and settings and settings.zeroChargeOverlay then
        widgetFrame.icon:Hide()
        widgetFrame.desatOverlay:Show()
    else
        widgetFrame.icon:Show()
        widgetFrame.desatOverlay:Hide()
    end
end

local function ShowIdleState()
    widgetFrame.icon:Show()
    widgetFrame.desatOverlay:Hide()
    widgetFrame.countText:Hide()
    widgetFrame.timerText:Hide()
    widgetFrame.cooldown:Clear()
end

local function UpdateWidget()
    if not widgetFrame then return end

    local settings = PRT:GetSetting("battleResCounter")
    if not settings or not settings.widgetEnabled or not IsInRaid() then
        widgetFrame:Hide()
        return
    end

    widgetFrame:SetScale((settings.widgetScale or 100) / 100)

    if inEncounter then
        ShowEncounterState()
    else
        ShowIdleState()
    end

    widgetFrame:Show()
end

local function SaveWidgetPosition()
    if not widgetFrame then return end

    local profile = PRT.Profiles:GetCurrent()
    if not profile.battleResCounter then
        profile.battleResCounter = {}
    end

    profile.battleResCounter.widgetPosition = {
        point = "TOPLEFT",
        x = widgetFrame:GetLeft(),
        y = widgetFrame:GetTop() - UIParent:GetTop(),
    }
end

local function RestoreWidgetPosition()
    if not widgetFrame then return end

    local settings = PRT:GetSetting("battleResCounter")
    widgetFrame:ClearAllPoints()

    local pos = settings and settings.widgetPosition
    if pos then
        widgetFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
        return
    end

    widgetFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
end

local function SetupWidgetDragging()
    if not widgetFrame then return end

    local settings = PRT:GetSetting("battleResCounter")
    local unlocked = not (settings and settings.lockFrames)

    widgetFrame:SetMovable(unlocked)
    widgetFrame:EnableMouse(true)

    if unlocked then
        widgetFrame:RegisterForDrag("LeftButton")
    else
        widgetFrame:RegisterForDrag()
    end

    widgetFrame:SetScript("OnDragStart", function(self)
        if not self:IsMovable() then return end
        self:StartMoving()
    end)

    widgetFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWidgetPosition()
    end)
end

local function PollCharges()
    local c, mc, s, d = ReadCharges()
    if c then
        charges, maxCharges, started, duration = c, mc, s, d
        inEncounter = true
    else
        charges, maxCharges, started, duration = 0, 0, 0, 0
        inEncounter = false
    end
    UpdateWidget()
end

local function OnEvent(_, event)
    if event == "ENCOUNTER_START" then
        inEncounter = true
        PollCharges()
        return
    end

    if event == "ENCOUNTER_END" then
        inEncounter = false
        charges, maxCharges, started, duration = 0, 0, 0, 0
        UpdateWidget()
    end
end

local function NotifyCooldownRoster()
    if not PRT.CooldownRoster or not PRT.CooldownRoster.active then return end
    PRT.CooldownRoster:RebuildRoster()
    PRT.CooldownRoster:UpdateDisplay()
end

function BattleResCounter:GetEnabledSetting()
    local settings = PRT:GetSetting("battleResCounter")
    if not settings then return false end
    return settings.widgetEnabled or settings.rosterRowEnabled
end

function BattleResCounter:IsActivatable()
    return IsInRaid()
end

function BattleResCounter:Initialize()
    widgetFrame = CreateWidget()
    RestoreWidgetPosition()
    SetupWidgetDragging()
end

function BattleResCounter:OnEnable()
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    PollCharges()
    pollTicker = C_Timer.NewTicker(1, PollCharges)

    UpdateWidget()
    NotifyCooldownRoster()
end

function BattleResCounter:OnDisable()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end

    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)

    inEncounter = false
    charges, maxCharges, started, duration = 0, 0, 0, 0

    if widgetFrame then
        widgetFrame:Hide()
    end

    NotifyCooldownRoster()
end

PRT:RegisterTab("Battle Res", function(parent)
    local function GetSettings()
        return PRT:GetSetting("battleResCounter")
    end

    local ROW_HEIGHT = 24

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(parent:GetWidth() - 40)
    scrollChild:SetHeight(400)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0

    local widgetHeader = PRT.Components.GetHeader(scrollChild, "Standalone Widget")
    widgetHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local widgetEnabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enabled", function(value)
        GetSettings().widgetEnabled = value
        PRT:ApplySettings("battleResCounter")
    end)
    widgetEnabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    widgetEnabledCheckbox:SetValue(GetSettings().widgetEnabled)
    yOffset = yOffset - ROW_HEIGHT

    local lockCheckbox = PRT.Components.GetCheckbox(scrollChild, "Locked", function(value)
        GetSettings().lockFrames = value
        SetupWidgetDragging()
    end)
    lockCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    lockCheckbox:SetValue(GetSettings().lockFrames)
    yOffset = yOffset - ROW_HEIGHT

    local scaleSlider = PRT.Components.GetSliderWithInput(scrollChild, "Scale", 50, 200, 5, false, function(value)
        GetSettings().widgetScale = value
        PRT:ApplySettings("battleResCounter")
    end)
    scaleSlider:SetPoint("TOPLEFT", 0, yOffset)
    scaleSlider:SetValue(GetSettings().widgetScale or 100)
    yOffset = yOffset - ROW_HEIGHT - 10

    local overlayCheckbox = PRT.Components.GetCheckbox(scrollChild, "Zero Charge Overlay", function(value)
        GetSettings().zeroChargeOverlay = value
        PRT:ApplySettings("battleResCounter")
    end)
    overlayCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    overlayCheckbox:SetValue(GetSettings().zeroChargeOverlay)
    yOffset = yOffset - ROW_HEIGHT

    yOffset = yOffset - 10
    local rosterHeader = PRT.Components.GetHeader(scrollChild, "Cooldown Roster Row")
    rosterHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local rosterEnabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enabled", function(value)
        GetSettings().rosterRowEnabled = value
        PRT:ApplySettings("battleResCounter")
    end)
    rosterEnabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    rosterEnabledCheckbox:SetValue(GetSettings().rosterRowEnabled)
    yOffset = yOffset - ROW_HEIGHT

    scrollChild:GetParent():GetParent():SetScript("OnShow", function()
        local settings = GetSettings()
        widgetEnabledCheckbox:SetValue(settings.widgetEnabled)
        lockCheckbox:SetValue(settings.lockFrames)
        scaleSlider:SetValue(settings.widgetScale or 100)
        overlayCheckbox:SetValue(settings.zeroChargeOverlay)
        rosterEnabledCheckbox:SetValue(settings.rosterRowEnabled)
    end)

    return scrollFrame
end)

PRT:RegisterApplyCallback("battleResCounter", function()
    UpdateWidget()
    SetupWidgetDragging()
    NotifyCooldownRoster()
end)
