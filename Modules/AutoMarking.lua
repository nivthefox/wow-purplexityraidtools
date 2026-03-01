-- AutoMarking: Periodically re-applies raid target icons to configured players
local PRT = PurplexityRaidTools
local AutoMarking = {}
PRT.AutoMarking = AutoMarking

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.autoMarking = {
    enabled = true,
    marks = {
        [1] = "", [2] = "", [3] = "", [4] = "",
        [5] = "", [6] = "", [7] = "", [8] = "",
    },
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MARK_NAMES = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull",
}

--------------------------------------------------------------------------------
-- Application Loop
--------------------------------------------------------------------------------

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

local function FindUnitByName(targetName)
    local lowerTarget = string.lower(targetName)
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local name = GetRaidRosterInfo(i)
        if name then
            local lowerName = string.lower(name)
            -- Match full name or just the character part before the server
            if lowerName == lowerTarget or string.match(lowerName, "^([^-]+)") == lowerTarget then
                return "raid" .. i
            end
        end
    end
    return nil
end

local function ApplyMarks()
    local settings = PRT:GetSetting("autoMarking")
    if not settings or not settings.enabled then
        return
    end

    if not IsInRaid() then
        return
    end

    if InCombatLockdown() then
        return
    end

    if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        return
    end

    for markIndex = 1, 8 do
        local nameString = settings.marks[markIndex]
        if nameString and nameString ~= "" then
            local names = SplitNames(nameString)
            for _, name in ipairs(names) do
                local unit = FindUnitByName(name)
                if unit then
                    local currentMark = GetRaidTargetIndex(unit)
                    if currentMark ~= markIndex then
                        SetRaidTargetIcon(unit, markIndex)
                    end
                    break
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Auto-Marking", function(parent)
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
        return PRT:GetSetting("autoMarking")
    end

    local function GetProfile()
        return PRT.Profiles:GetCurrent()
    end

    local function EnsureSettingsTable()
        local profile = GetProfile()
        if not profile.autoMarking then
            profile.autoMarking = {
                enabled = PRT.defaults.autoMarking.enabled,
                marks = {},
            }
            for i = 1, 8 do
                profile.autoMarking.marks[i] = PRT.defaults.autoMarking.marks[i]
            end
        end
        return profile.autoMarking
    end

    -- General Section
    local generalHeader = PRT.Components.GetHeader(scrollChild, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enable Auto-Marking", function(value)
        EnsureSettingsTable().enabled = value
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    -- Mark Assignments Section
    yOffset = yOffset - 10
    local marksHeader = PRT.Components.GetHeader(scrollChild, "Mark Assignments")
    marksHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    for markIndex = 1, 8 do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 20, yOffset)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 0, 0)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. markIndex)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetWidth(60)
        label:SetJustifyH("LEFT")
        label:SetText(MARK_NAMES[markIndex])

        local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        editBox:SetHeight(20)
        editBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
        editBox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        editBox:SetAutoFocus(false)
        editBox:SetText(GetSettings().marks[markIndex] or "")

        local idx = markIndex
        editBox:SetScript("OnEnterPressed", function(self)
            local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
            EnsureSettingsTable().marks[idx] = text
            self:SetText(text)
            self:ClearFocus()
        end)

        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        editBox:SetScript("OnEditFocusLost", function(self)
            local text = string.match(self:GetText(), "^%s*(.-)%s*$") or ""
            EnsureSettingsTable().marks[idx] = text
            self:SetText(text)
        end)

        yOffset = yOffset - ROW_HEIGHT
    end

    -- Actions Section
    yOffset = yOffset - 10
    local actionsHeader = PRT.Components.GetHeader(scrollChild, "Actions")
    actionsHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local clearButton = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    clearButton:SetSize(140, 22)
    clearButton:SetPoint("TOPLEFT", 20, yOffset)
    clearButton:SetText("Clear All Marks")
    clearButton:SetScript("OnClick", function()
        if not IsInRaid() then
            return
        end
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = "raid" .. i
            if GetRaidTargetIndex(unit) then
                SetRaidTargetIcon(unit, 0)
            end
        end
    end)

    return container
end)

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function AutoMarking:Initialize()
    C_Timer.NewTicker(2, ApplyMarks)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        AutoMarking:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
