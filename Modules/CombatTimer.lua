local PRT = PurplexityRaidTools

local CombatTimerCore = {}
CombatTimerCore.__index = CombatTimerCore
PRT.CombatTimerCore = CombatTimerCore

function CombatTimerCore.new(getMode)
    return setmetatable({
        state = "hidden",
        startTime = nil,
        elapsed = 0,
        activeMode = nil,
        getMode = getMode,
    }, CombatTimerCore)
end

function CombatTimerCore.FormatTime(elapsed)
    local total = math.floor(elapsed)
    if total >= 3600 then
        local h = math.floor(total / 3600)
        local m = math.floor((total % 3600) / 60)
        local s = total % 60
        return string.format("%d:%02d:%02d", h, m, s)
    end
    local m = math.floor(total / 60)
    local s = total % 60
    return string.format("%d:%02d", m, s)
end

local function startRunning(self, now)
    self.state = "running"
    self.startTime = now
    self.elapsed = 0
    self.activeMode = self.getMode()
end

local function freeze(self, now)
    self.elapsed = now - self.startTime
    self.state = "frozen"
    self.startTime = nil
end

function CombatTimerCore:OnEncounterStart(now)
    if self.state == "running" then return end
    if self.getMode() ~= "encounter" then return end
    startRunning(self, now)
end

function CombatTimerCore:OnEncounterEnd(now)
    if self.state ~= "running" then return end
    if self.activeMode ~= "encounter" then return end
    freeze(self, now)
end

function CombatTimerCore:OnRegenDisabled(now)
    if self.state == "running" then return end
    if self.getMode() ~= "combat" then return end
    startRunning(self, now)
end

function CombatTimerCore:OnRegenEnabled(now)
    if self.state ~= "running" then return end
    if self.activeMode ~= "combat" then return end
    freeze(self, now)
end

function CombatTimerCore:Tick(now)
    if self.state ~= "running" then return end
    self.elapsed = now - self.startTime
end

function CombatTimerCore:Dismiss()
    if self.state ~= "frozen" then return end
    self.state = "hidden"
end

function CombatTimerCore:Disable()
    self.state = "hidden"
    self.startTime = nil
    self.elapsed = 0
    self.activeMode = nil
end

function CombatTimerCore:GetState()
    return self.state
end

function CombatTimerCore:GetElapsed()
    return self.elapsed
end

-- =========================================================================
-- WoW module glue
-- =========================================================================

local CombatTimer = {}
PRT.CombatTimer = CombatTimer
PRT:RegisterModule("combatTimer", CombatTimer)

PRT.defaults.combatTimer = {
    enabled = true,
    mode = "encounter",
    fontFace = "Friz Quadrata TT",
    fontSize = 16,
    lockFrames = true,
    widgetPosition = nil,
}

local timer = nil
local ticker = nil
local widgetFrame = nil
local closeButton = nil

local function GetSettings()
    return PRT:GetSetting("combatTimer")
end

local function GetMode()
    local settings = GetSettings()
    return settings and settings.mode or "encounter"
end

local function ListFonts()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return {}
    end
    local names = LSM:List("font")
    local items = {}
    for _, name in ipairs(names) do
        table.insert(items, { name = name, value = name })
    end
    return items
end

local function GetFontPath(faceName)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("font", faceName)
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function ResizeToFitText()
    if not widgetFrame then return end
    local textWidth = widgetFrame.timerText:GetStringWidth()
    local textHeight = widgetFrame.timerText:GetStringHeight()
    widgetFrame:SetSize(textWidth + 16, textHeight + 10)
end

local function UpdateWidgetFont()
    if not widgetFrame then return end
    local settings = GetSettings()
    local face = settings and settings.fontFace or "Friz Quadrata TT"
    local size = settings and settings.fontSize or 16
    widgetFrame.timerText:SetFont(GetFontPath(face), size, "OUTLINE")
    ResizeToFitText()
end

local function UpdateCloseButton()
    if not closeButton then return end
    if timer and timer:GetState() == "frozen" then
        closeButton:Show()
    else
        closeButton:Hide()
    end
end

local function UpdateWidgetVisibility()
    if not widgetFrame then return end
    if not timer then return end

    local state = timer:GetState()
    local settings = GetSettings()
    local unlocked = not (not settings or settings.lockFrames)

    if state == "hidden" then
        if unlocked then
            widgetFrame.timerText:SetText(CombatTimerCore.FormatTime(0))
            ResizeToFitText()
            widgetFrame:Show()
        else
            widgetFrame:Hide()
        end
    elseif state == "running" then
        widgetFrame.timerText:SetText(CombatTimerCore.FormatTime(timer:GetElapsed()))
        ResizeToFitText()
        widgetFrame:Show()
    elseif state == "frozen" then
        widgetFrame.timerText:SetText(CombatTimerCore.FormatTime(timer:GetElapsed()))
        ResizeToFitText()
        widgetFrame:Show()
    end

    UpdateCloseButton()
end

local function SaveWidgetPosition()
    if not widgetFrame then return end

    local profile = PRT.Profiles:GetCurrent()
    if not profile.combatTimer then
        profile.combatTimer = {}
    end

    local point, _, relativePoint, x, y = widgetFrame:GetPoint(1)
    profile.combatTimer.widgetPosition = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function RestoreWidgetPosition()
    if not widgetFrame then return end

    local settings = GetSettings()
    widgetFrame:ClearAllPoints()

    local pos = settings and settings.widgetPosition
    if pos then
        widgetFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x or 0, pos.y or 0)
        return
    end

    widgetFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
end

local function SetupWidgetDragging()
    if not widgetFrame then return end

    local settings = GetSettings()
    local unlocked = not (not settings or settings.lockFrames)

    widgetFrame:SetMovable(unlocked)
    widgetFrame:EnableMouse(unlocked)

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

    UpdateWidgetVisibility()
end

local function CreateWidget()
    local frame = CreateFrame("Frame", "PRT_CombatTimerWidget", UIParent)
    frame:SetSize(60, 26)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    frame.bg = bg

    local timerText = frame:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    timerText:SetPoint("CENTER", 0, 0)
    timerText:SetTextColor(1, 1, 1)
    frame.timerText = timerText

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    close:Hide()
    close:SetScript("OnClick", function()
        if timer then
            timer:Dismiss()
            UpdateWidgetVisibility()
        end
    end)
    closeButton = close

    return frame
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        if not timer then return end
        timer:Tick(GetTime())
        UpdateWidgetVisibility()
    end)
end

local function StopTicker()
    if not ticker then return end
    ticker:Cancel()
    ticker = nil
end

local function OnEvent(_, event)
    if not timer then return end
    local now = GetTime()
    local prevState = timer:GetState()

    if event == "ENCOUNTER_START" then
        timer:OnEncounterStart(now)
    elseif event == "ENCOUNTER_END" then
        timer:OnEncounterEnd(now)
    elseif event == "PLAYER_REGEN_DISABLED" then
        timer:OnRegenDisabled(now)
    elseif event == "PLAYER_REGEN_ENABLED" then
        timer:OnRegenEnabled(now)
    end

    local newState = timer:GetState()
    if newState == "running" and prevState ~= "running" then
        StartTicker()
    elseif newState ~= "running" and prevState == "running" then
        StopTicker()
    end

    UpdateWidgetVisibility()
end

function CombatTimer:Initialize()
    widgetFrame = CreateWidget()
    UpdateWidgetFont()
    RestoreWidgetPosition()
    SetupWidgetDragging()
end

function CombatTimer:OnEnable()
    timer = CombatTimerCore.new(GetMode)

    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    UpdateWidgetVisibility()
end

function CombatTimer:OnDisable()
    StopTicker()

    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)

    if timer then
        timer:Disable()
        timer = nil
    end

    if widgetFrame then
        widgetFrame:Hide()
    end

    if closeButton then
        closeButton:Hide()
    end
end

PRT:RegisterTab("Combat Timer", function(parent)
    local ROW_HEIGHT = 24

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(parent:GetWidth() - 40)
    scrollChild:SetHeight(400)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0

    local header = PRT.Components.GetHeader(scrollChild, "Combat Timer")
    header:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enabled", function(value)
        GetSettings().enabled = value
        PRT:ApplySettings("combatTimer")
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local modeDropdown = PRT.Components.GetBasicDropdown(scrollChild, "Timer Mode",
        function()
            return {
                { name = "Encounter only", value = "encounter" },
                { name = "All combat", value = "combat" },
            }
        end,
        function(value) return GetSettings().mode == value end,
        function(value)
            GetSettings().mode = value
            PRT:ApplySettings("combatTimer")
        end)
    modeDropdown:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - ROW_HEIGHT

    local fontDropdown = PRT.Components.GetBasicDropdown(scrollChild, "Font Face",
        ListFonts,
        function(value) return GetSettings().fontFace == value end,
        function(value)
            GetSettings().fontFace = value
            PRT:ApplySettings("combatTimer")
        end)
    fontDropdown:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - ROW_HEIGHT

    local fontSizeInput = PRT.Components.GetIntegerInput(scrollChild, "Font Size", 6, 72, function(value)
        GetSettings().fontSize = value
        PRT:ApplySettings("combatTimer")
    end)
    fontSizeInput:SetPoint("TOPLEFT", 0, yOffset)
    fontSizeInput:SetValue(GetSettings().fontSize)
    yOffset = yOffset - ROW_HEIGHT

    local lockCheckbox = PRT.Components.GetCheckbox(scrollChild, "Locked", function(value)
        GetSettings().lockFrames = value
        SetupWidgetDragging()
    end)
    lockCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    lockCheckbox:SetValue(GetSettings().lockFrames)
    yOffset = yOffset - ROW_HEIGHT

    scrollChild:GetParent():GetParent():SetScript("OnShow", function()
        local settings = GetSettings()
        enabledCheckbox:SetValue(settings.enabled)
        modeDropdown:SetValue()
        fontDropdown:SetValue()
        fontSizeInput:SetValue(settings.fontSize)
        lockCheckbox:SetValue(settings.lockFrames)
    end)

    return scrollFrame
end)

PRT:RegisterApplyCallback("combatTimer", function()
    UpdateWidgetFont()
    UpdateWidgetVisibility()
    SetupWidgetDragging()
end)
