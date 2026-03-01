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

local DEBUG = false

local function DebugPrint(...)
    if DEBUG then
        print("|cFF999999PRT AutoMarking:|r", ...)
    end
end

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

local function NameMatches(fullName, targetName)
    local lowerFull = string.lower(fullName)
    local lowerTarget = string.lower(targetName)
    if lowerFull == lowerTarget then
        return true
    end
    local charName = string.match(lowerFull, "^([^-]+)")
    return charName == lowerTarget
end

local function GetUnitFullName(unit)
    local name, realm = UnitName(unit)
    if not name then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function FindUnitByName(targetName)
    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local name = GetRaidRosterInfo(i)
            if name and NameMatches(name, targetName) then
                return "raid" .. i
            end
        end
    else
        local fullName = GetUnitFullName("player")
        if fullName and NameMatches(fullName, targetName) then
            return "player"
        end
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers - 1 do
            local unit = "party" .. i
            fullName = GetUnitFullName(unit)
            if fullName and NameMatches(fullName, targetName) then
                return unit
            end
        end
    end
    return nil
end

local function ApplyMarks()
    local settings = PRT:GetSetting("autoMarking")
    if not settings or not settings.enabled then
        DebugPrint("Skipped: disabled or no settings")
        return
    end

    if not IsInGroup() then
        DebugPrint("Skipped: not in group")
        return
    end

    if InCombatLockdown() then
        DebugPrint("Skipped: in combat")
        return
    end

    if IsInRaid() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        return
    end

    local appliedAny = false
    for markIndex = 1, 8 do
        local nameString = settings.marks[markIndex]
        if nameString and nameString ~= "" then
            local names = SplitNames(nameString)
            local matched = false
            for _, name in ipairs(names) do
                local unit = FindUnitByName(name)
                if unit then
                    local currentMark = GetRaidTargetIndex(unit)
                    if currentMark ~= markIndex then
                        DebugPrint(string.format(
                            "Setting %s (%d) on %s (%s), had mark %s",
                            MARK_NAMES[markIndex], markIndex, name, unit,
                            tostring(currentMark)
                        ))
                        SetRaidTarget(unit, markIndex)
                        appliedAny = true
                    end
                    matched = true
                    break
                end
            end
            if not matched then
                DebugPrint(string.format(
                    "%s (%d): no match in group for [%s]",
                    MARK_NAMES[markIndex], markIndex, nameString
                ))
            end
        end
    end

    if not appliedAny then
        DebugPrint("Tick: all marks already correct (or no names configured)")
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
        if not IsInGroup() then
            return
        end
        if IsInRaid() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
            return
        end
        if IsInRaid() then
            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers do
                local unit = "raid" .. i
                if GetRaidTargetIndex(unit) then
                    SetRaidTarget(unit, 0)
                end
            end
        else
            if GetRaidTargetIndex("player") then
                SetRaidTarget("player", 0)
            end
            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers - 1 do
                local unit = "party" .. i
                if GetRaidTargetIndex(unit) then
                    SetRaidTarget(unit, 0)
                end
            end
        end
    end)

    return container
end)

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function AutoMarking:Initialize()
    DebugPrint("Initialized, starting 2s ticker")
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
