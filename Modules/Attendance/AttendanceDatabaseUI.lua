local PRT = PurplexityRaidTools
local AttendanceDatabaseUI = {}
PRT.AttendanceDatabaseUI = AttendanceDatabaseUI

local BACKDROP_INFO = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local statusText

local function SummaryText(summary)
    return summary.days .. " attendance days containing " .. summary.attendanceRecords
        .. " character records, plus " .. summary.rosterEntries .. " roster entries containing "
        .. summary.rosterCharacters .. " characters"
end

local function PrintError(message)
    print("|cFFFF0000PurplexityRaidTools:|r " .. message)
end

local function RefreshViews()
    if PRT.AttendanceUI then
        PRT.AttendanceUI:Refresh()
    end
    if PRT.RecordsUI then
        PRT.RecordsUI:Refresh()
    end
    if PRT.RosterUI then
        PRT.RosterUI:Refresh()
    end
end

StaticPopupDialogs["PRT_ATTENDANCE_IMPORT_DATABASE"] = {
    text = "%s",
    button1 = "Replace Database",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, prepared)
        local ok, result = PRT.AttendanceDatabase:ApplyPrepared(prepared)
        if not ok then
            if statusText then
                statusText:SetText("|cFFFF4D4D" .. result .. "|r")
            end
            PrintError(result)
            return
        end

        if statusText then
            statusText:SetText("|cFF33FF99Imported " .. SummaryText(result) .. ".|r")
        end
        RefreshViews()
        print("|cFF00FF00PurplexityRaidTools:|r Imported the complete attendance database.")
    end,
}

function AttendanceDatabaseUI:Build(panel)
    local header = PRT.Components.GetHeader(panel, "Attendance Database Backup")
    header:SetPoint("TOPLEFT", 0, -10)

    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", 20, -42)
    description:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Export copies every attendance day and roster entry into one text payload. "
        .. "To restore a backup, paste it below and review the import before replacing local data."
    )

    local exportButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportButton:SetSize(100, 22)
    exportButton:SetPoint("TOPLEFT", 20, -82)
    exportButton:SetText("Export")

    local importButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importButton:SetSize(110, 22)
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)
    importButton:SetText("Review Import")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -114)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 54)

    local textBackground = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    textBackground:SetPoint("TOPLEFT", scrollFrame, -4, 4)
    textBackground:SetPoint("BOTTOMRIGHT", scrollFrame, 26, -4)
    textBackground:SetBackdrop(BACKDROP_INFO)
    textBackground:SetBackdropColor(0, 0, 0, 0.5)
    textBackground:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    textBackground:EnableMouse(false)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(math.max(1, panel:GetWidth() - 92))
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    scrollFrame:SetScrollChild(editBox)

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 20, 24)
    statusText:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    statusText:SetJustifyH("LEFT")

    exportButton:SetScript("OnClick", function()
        local payload = PRT.AttendanceDatabase:Export()
        editBox:SetText(payload)
        editBox:SetFocus()
        editBox:HighlightText()
        statusText:SetText("|cFF33FF99The complete database is ready to copy.|r")
    end)

    importButton:SetScript("OnClick", function()
        local prepared, err = PRT.AttendanceDatabase:PrepareImport(editBox:GetText())
        if not prepared then
            statusText:SetText("|cFFFF4D4D" .. err .. "|r")
            return
        end

        local question = "Replace your complete local attendance database with "
            .. SummaryText(prepared.summary) .. "?"
        StaticPopup_Show("PRT_ATTENDANCE_IMPORT_DATABASE", question, nil, prepared)
    end)
end
