-- AttendanceUI: the Attendance sidebar tab. Owns the Grid, Records, and Settings
-- tabs, the audit grid itself, and the per-character status modal a cell click
-- opens. The Records tab's content belongs to RecordsUI.
--
-- The grid is rebuilt only on a data change -- the panel being shown, an edit,
-- or an accepted sync. AttendanceReport:Build walks the un-rostered characters
-- once per day, so rebuilding it per frame or per keystroke would be felt.
--
-- Statuses are edited per character rather than per player: a displayed status
-- is resolved across a player's characters, so a player-level edit could not
-- lower one without silently choosing which record underneath to rewrite.

local PRT = PurplexityRaidTools
local AttendanceUI = {}
PRT.AttendanceUI = AttendanceUI

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local SECTION_HEIGHT = 22
local GRID_HEIGHT = 380
local NAME_WIDTH = 116
local PCT_WIDTH = 46
local ITEM_LEVEL_WIDTH = 82
local SUMMARY_WIDTH = NAME_WIDTH + PCT_WIDTH + ITEM_LEVEL_WIDTH
local CELL_WIDTH = 42

local MODAL_WIDTH = 488
local MODAL_CHARACTER_HEIGHT = 52
local MODAL_HEADER_HEIGHT = 66
local MODAL_FOOTER_HEIGHT = 40
local STATUS_BUTTON_WIDTH = 72

local MISSING, ABSENT, LATE, PRESENT, STANDBY = 0, 1, 2, 3, 4
local STATUS_OPTIONS = {
    { status = PRESENT, name = "Present", letter = "P" },
    { status = STANDBY, name = "Standby", letter = "S" },
    { status = LATE, name = "Late", letter = "L" },
    { status = ABSENT, name = "Absent", letter = "A" },
    { status = MISSING, name = "Missing", letter = "M" },
}

local STATUS_OPTIONS_BY_VALUE = {}
for _, option in ipairs(STATUS_OPTIONS) do
    STATUS_OPTIONS_BY_VALUE[option.status] = option
end

local STATUS_COLORS = {
    [MISSING] = "FFF44336",
    [ABSENT] = "FF9E9E9E",
    [LATE] = "FFFF9800",
    [PRESENT] = "FF4CAF50",
    [STANDBY] = "FF2196F3",
}

local MUTED_COLOR = "FF808080"
local HIGH_PERCENTAGE_COLOR = "FF4CAF50"
local MID_PERCENTAGE_COLOR = "FFFF9800"
local LOW_PERCENTAGE_COLOR = "FFF44336"

local HIGH_PERCENTAGE, MID_PERCENTAGE = 90, 75

local ISO_DAY_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

local CONTENT_CHECKBOXES = {
    { label = "Open World",        path = { "contentTypes", "openWorld" } },
    { label = "Dungeon (Normal)",  path = { "contentTypes", "dungeon", "normal" } },
    { label = "Dungeon (Heroic)",  path = { "contentTypes", "dungeon", "heroic" } },
    { label = "Dungeon (Mythic)",  path = { "contentTypes", "dungeon", "mythic" } },
    { label = "Dungeon (Mythic+)", path = { "contentTypes", "dungeon", "mythicPlus" } },
    { label = "Raid (LFR)",        path = { "contentTypes", "raid", "lfr" } },
    { label = "Raid (Normal)",     path = { "contentTypes", "raid", "normal" } },
    { label = "Raid (Heroic)",     path = { "contentTypes", "raid", "heroic" } },
    { label = "Raid (Mythic)",     path = { "contentTypes", "raid", "mythic" } },
    { label = "Scenario (Normal)", path = { "contentTypes", "scenario", "normal" } },
    { label = "Scenario (Heroic)", path = { "contentTypes", "scenario", "heroic" } },
}

local RefreshGrid
local gridPanel
local detailPanel
local OpenDetails
local lastViewedCharacter
local editModal
local editState

function AttendanceUI:GetStatusOptions()
    local options = {}
    for index, option in ipairs(STATUS_OPTIONS) do
        options[index] = {
            status = option.status,
            name = option.name,
            letter = option.letter,
        }
    end
    return options
end

local function AttendanceSettings()
    return PRT:GetSetting("attendance")
end

local function ReadSettingPath(settings, path)
    local value = settings
    for _, key in ipairs(path) do
        value = value[key]
    end
    return value
end

local function WriteSettingPath(settings, path, value)
    local node = settings
    for index = 1, #path - 1 do
        node = node[path[index]]
    end
    node[path[#path]] = value
end

local function Colored(color, text)
    return "|c" .. color .. text .. "|r"
end

local function ColumnDate(day)
    local _, month, dayOfMonth = tostring(day):match(ISO_DAY_PATTERN)
    if not month then
        return tostring(day)
    end
    return tonumber(month) .. "/" .. tonumber(dayOfMonth)
end

local function PercentageText(percentage)
    if not percentage then
        return Colored(MUTED_COLOR, "-")
    end

    local color = LOW_PERCENTAGE_COLOR
    if percentage >= HIGH_PERCENTAGE then
        color = HIGH_PERCENTAGE_COLOR
    elseif percentage >= MID_PERCENTAGE then
        color = MID_PERCENTAGE_COLOR
    end
    return Colored(color, percentage .. "%")
end

local function StatusText(status)
    if status == nil then
        return Colored(MUTED_COLOR, "-")
    end
    return Colored(STATUS_COLORS[status], STATUS_OPTIONS_BY_VALUE[status].letter)
end

local function ClassColoredName(character)
    local classToken = PRT.Roster:GetCharacterClass(character)
    local classColor = classToken and RAID_CLASS_COLORS[classToken]
    if not classColor then
        return character
    end
    return classColor:WrapTextInColorCode(character)
end

--- Sorted at the presentation seam rather than in the roster: GetEntries hands
--- out the live database, whose array order is data that sync preserves.
local function AlphabeticalEntries()
    local entries = {}
    for index, entry in ipairs(PRT.Roster:GetEntries()) do
        entries[index] = entry
    end
    table.sort(entries, function(a, b)
        return strcmputf8i(a.nickname, b.nickname) < 0
    end)
    return entries
end

local function BuildReport()
    return PRT.AttendanceReport:Build(PurplexityRaidToolsAttendanceDB or {}, AlphabeticalEntries())
end

local function HasRecordedCharacter(characters)
    for _, dayRecord in pairs(PurplexityRaidToolsAttendanceDB or {}) do
        for _, character in ipairs(characters) do
            if dayRecord[character] ~= nil then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Per-character status modal
--------------------------------------------------------------------------------

local function RenderEditModal()
    local rows = editModal.characterRows

    for index, character in ipairs(editState.characters) do
        local row = rows[index]
        if not row then
            row = CreateFrame("Frame", nil, editModal)
            row:SetHeight(MODAL_CHARACTER_HEIGHT)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("TOPLEFT", 0, 0)
            row.name:SetJustifyH("LEFT")

            row.buttons = {}
            for order, option in ipairs(STATUS_OPTIONS) do
                local status = option.status
                local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                button:SetSize(STATUS_BUTTON_WIDTH, 22)
                button:SetPoint("TOPLEFT", (order - 1) * (STATUS_BUTTON_WIDTH + 4), -18)
                button:SetText(option.name)
                button:SetScript("OnClick", function()
                    local ok, err = PRT.AttendanceStore:SetStatus(
                        editState.day, row.character, status)
                    if not ok then
                        print("|cFFFF0000PurplexityRaidTools:|r " .. tostring(err))
                        return
                    end
                    AttendanceUI:Refresh()
                end)
                row.buttons[order] = button
            end

            row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delete:SetSize(STATUS_BUTTON_WIDTH, 22)
            row.delete:SetPoint("TOPLEFT", #STATUS_OPTIONS * (STATUS_BUTTON_WIDTH + 4), -18)
            row.delete:SetText("Delete")
            row.delete:SetScript("OnClick", function()
                local ok, err = PRT.AttendanceStore:DeleteStatus(editState.day, row.character)
                if not ok then
                    print("|cFFFF0000PurplexityRaidTools:|r " .. tostring(err))
                    return
                end
                AttendanceUI:Refresh()
            end)

            rows[index] = row
        end

        row.character = character
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", editModal, "TOPLEFT", 16,
            -(MODAL_HEADER_HEIGHT + (index - 1) * MODAL_CHARACTER_HEIGHT))
        row:SetPoint("RIGHT", editModal, "RIGHT", -16, 0)

        local dayRecord = (PurplexityRaidToolsAttendanceDB or {})[editState.day] or {}
        local status = PRT.AttendanceStore.GetStatus(dayRecord[character])

        local label = ClassColoredName(character)
        if status == nil then
            label = label .. " " .. Colored(MUTED_COLOR, "(no record)")
        end
        row.name:SetText(label)

        for order, button in ipairs(row.buttons) do
            button:SetEnabled(STATUS_OPTIONS[order].status ~= status)
        end
        row.delete:SetEnabled(status ~= nil)

        row:Show()
    end

    for index = #editState.characters + 1, #rows do
        rows[index]:Hide()
    end

    editModal.title:SetText(editState.title)
    editModal.subtitle:SetText(editState.dateLabel)
    editModal:SetHeight(MODAL_HEADER_HEIGHT
        + #editState.characters * MODAL_CHARACTER_HEIGHT
        + MODAL_FOOTER_HEIGHT)
end

local function EnsureEditModal()
    if editModal then
        return
    end

    editModal = CreateFrame("Frame", "PRT_AttendanceStatusModal", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(editModal)
    ButtonFrameTemplate_HideButtonBar(editModal)
    editModal.Inset:Hide()
    editModal:SetTitle("Edit Attendance")
    editModal:SetWidth(MODAL_WIDTH)
    editModal:SetPoint("CENTER")
    editModal:SetFrameStrata("DIALOG")
    editModal:SetToplevel(true)
    editModal:SetMovable(true)
    editModal:SetClampedToScreen(true)
    editModal:EnableMouse(true)
    editModal:RegisterForDrag("LeftButton")
    editModal:SetScript("OnDragStart", editModal.StartMoving)
    editModal:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    editModal:Hide()

    table.insert(UISpecialFrames, "PRT_AttendanceStatusModal")

    editModal.title = editModal:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editModal.title:SetPoint("TOPLEFT", 16, -30)

    editModal.subtitle = editModal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editModal.subtitle:SetPoint("TOPLEFT", 16, -46)

    editModal.characterRows = {}

    local closeButton = CreateFrame("Button", nil, editModal, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 22)
    closeButton:SetPoint("BOTTOM", 0, 12)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        editModal:Hide()
    end)
end

--- The modal holds character names and a day key -- never a roster entry table.
--- An incoming roster sync replaces every entry table wholesale, so a captured
--- entry would go on being edited after it stopped being the roster.
local function OpenEditModal(entry, day, dateLabel)
    EnsureEditModal()

    editState = {
        day = day,
        dateLabel = dateLabel,
        title = entry.name,
        characters = entry.characters,
    }

    RenderEditModal()
    editModal:Show()
end

--------------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------------

local function CreateGridRow(parent, cellCount)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(0.84, 0.72, 0.47, 0.12)

    row.nameButton = CreateFrame("Button", nil, row)
    row.nameButton:SetSize(NAME_WIDTH, ROW_HEIGHT)
    row.nameButton:SetPoint("LEFT", 0, 0)
    row.nameButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.percentage = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.percentage:SetPoint("LEFT", NAME_WIDTH, 0)
    row.percentage:SetWidth(PCT_WIDTH)
    row.percentage:SetJustifyH("CENTER")

    row.itemLevel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemLevel:SetPoint("LEFT", NAME_WIDTH + PCT_WIDTH, 0)
    row.itemLevel:SetWidth(ITEM_LEVEL_WIDTH)
    row.itemLevel:SetJustifyH("CENTER")

    row.cells = {}
    for index = 1, cellCount do
        local cell = CreateFrame("Button", nil, row)
        cell:SetSize(CELL_WIDTH, ROW_HEIGHT)
        cell:SetPoint("LEFT", SUMMARY_WIDTH + (index - 1) * CELL_WIDTH, 0)

        cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
        cell.highlight:SetAllPoints()
        cell.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

        cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.text:SetAllPoints()
        cell.text:SetJustifyH("CENTER")

        row.cells[index] = cell
    end

    return row
end

local function FillGridRow(row, entry, days, reportDays)
    local selected = false
    for _, character in ipairs(entry.characters) do
        if character == lastViewedCharacter then
            selected = true
            break
        end
    end
    row.selection:SetShown(selected)
    row.name:SetText(entry.name)
    row.percentage:SetText(PercentageText(entry.percentage))
    row.nameButton:SetScript("OnClick", function() OpenDetails(entry, reportDays) end)
    local level = PRT.AttendanceReport:GetLatestItemLevel(
        PurplexityRaidToolsAttendanceDB or {}, reportDays, entry.characters)
    row.itemLevel:SetText(level and string.format("%.1f", level) or "-")

    for index, cell in ipairs(row.cells) do
        local day = days[index]
        if day then
            cell.text:SetText(StatusText(entry.statuses[day]))
            cell:SetScript("OnClick", function()
                OpenEditModal(entry, day, ColumnDate(day))
            end)
            cell:Show()
        else
            cell:Hide()
        end
    end

    row:Show()
end

PRT:RegisterTab("Attendance", function(parent)
    local function SetupGrid(panel)
        gridPanel = panel
        local overview = CreateFrame("Frame", nil, panel)
        overview:SetAllPoints()
        detailPanel = PRT.AttendanceDetailsUI:Build(panel, {
            Back = function()
                lastViewedCharacter = detailPanel.character
                detailPanel:Hide()
                overview:Show()
                RefreshGrid()
            end,
            Edit = OpenEditModal,
            Date = ColumnDate,
            Status = StatusText,
            Percentage = PercentageText,
        })
        OpenDetails = function(entry, days)
            overview:Hide()
            detailPanel:Open(entry, days)
        end

        local gridRows = {}
        local visibleDayCount = math.max(1,
            math.floor((panel:GetWidth() - 46 - SUMMARY_WIDTH) / CELL_WIDTH))

        local title = overview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -10)
        title:SetText("Attendance & gear")
        local summary = overview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        summary:SetPoint("TOPLEFT", 20, -34)
        summary:SetText("Click a player for gear history. Click a raid-day cell to edit attendance.")
        local header = CreateFrame("Frame", nil, overview)
        header:SetHeight(HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", 20, -60)
        header:SetPoint("RIGHT", panel, "RIGHT", -26, 0)

        local nameHeading = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameHeading:SetPoint("LEFT", 0, 0)
        nameHeading:SetText("Player")

        local pctHeading = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pctHeading:SetPoint("LEFT", NAME_WIDTH, 0)
        pctHeading:SetWidth(PCT_WIDTH)
        pctHeading:SetJustifyH("CENTER")
        pctHeading:SetText("PCT")

        local levelHeading = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelHeading:SetPoint("LEFT", NAME_WIDTH + PCT_WIDTH, 0)
        levelHeading:SetWidth(ITEM_LEVEL_WIDTH)
        levelHeading:SetJustifyH("CENTER")
        levelHeading:SetText("Latest ilvl")

        local dayHeadings = {}
        for index = 1, visibleDayCount do
            local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            heading:SetPoint("LEFT", SUMMARY_WIDTH + (index - 1) * CELL_WIDTH, 0)
            heading:SetWidth(CELL_WIDTH)
            heading:SetJustifyH("CENTER")
            dayHeadings[index] = heading
        end

        local scrollFrame = CreateFrame("ScrollFrame", nil, overview, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 48)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(panel:GetWidth() - 60, GRID_HEIGHT)
        scrollFrame:SetScrollChild(scrollChild)

        local sectionLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sectionLabel:SetJustifyH("LEFT")
        sectionLabel:SetText("Not on roster")
        sectionLabel:Hide()

        local emptyLabel = overview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyLabel:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -4)
        emptyLabel:SetText("No attendance records yet. A pull countdown creates the first one.")

        local truncationNote = overview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        truncationNote:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 4, -8)
        truncationNote:Hide()
        local legend = overview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        legend:SetPoint("BOTTOMLEFT", 20, 8)
        legend:SetText("P Present   S Standby   L Late   A Absent   M Missing   - No record")

        RefreshGrid = function()
            local report = BuildReport()
            if detailPanel:IsShown() then
                for _, rows in ipairs({ report.players, report.unrostered }) do
                    for _, entry in ipairs(rows) do
                        for _, character in ipairs(entry.characters) do
                            if character == detailPanel.character then
                                detailPanel:SetEntry(entry, report.days, character)
                                return
                            end
                        end
                    end
                end
                detailPanel:Hide()
                overview:Show()
            end
            local days = {}
            for index = 1, math.min(visibleDayCount, #report.days) do
                days[index] = report.days[index]
            end

            for index, heading in ipairs(dayHeadings) do
                if days[index] then
                    heading:SetText(ColumnDate(days[index]))
                    heading:Show()
                else
                    heading:Hide()
                end
            end

            local placed, yOffset = 0, 0
            local function PlaceRow(entry)
                placed = placed + 1
                local row = gridRows[placed]
                if not row then
                    row = CreateGridRow(scrollChild, visibleDayCount)
                    gridRows[placed] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -yOffset)
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                FillGridRow(row, entry, days, report.days)
                yOffset = yOffset + ROW_HEIGHT
            end

            for _, entry in ipairs(report.players) do
                PlaceRow(entry)
            end

            if #report.unrostered > 0 then
                sectionLabel:ClearAllPoints()
                sectionLabel:SetPoint("TOPLEFT", 0, -yOffset - 4)
                sectionLabel:Show()
                yOffset = yOffset + SECTION_HEIGHT

                for _, entry in ipairs(report.unrostered) do
                    PlaceRow(entry)
                end
            else
                sectionLabel:Hide()
            end

            for index = placed + 1, #gridRows do
                gridRows[index]:Hide()
            end

            scrollChild:SetHeight(math.max(GRID_HEIGHT, yOffset))

            if placed == 0 then
                emptyLabel:Show()
            else
                emptyLabel:Hide()
            end

            truncationNote:SetText("Showing " .. #days .. " of " .. #report.days
                .. " days. Percentages use all recorded history.")
            truncationNote:Show()
        end

        panel:SetScript("OnShow", function()
            RefreshGrid()
        end)
    end

    local function SetupRecords(panel)
        PRT.RecordsUI:Build(panel)
    end

    local function SetupSettings(panel)
        local contentHeader = PRT.Components.GetHeader(panel, "Take Attendance In")
        contentHeader:SetPoint("TOPLEFT", 0, -10)

        local checkboxes = {}
        local yOffset = -38
        for index, info in ipairs(CONTENT_CHECKBOXES) do
            local checkbox = PRT.Components.GetCheckbox(panel, info.label, function(value)
                WriteSettingPath(AttendanceSettings(), info.path, value)
            end)
            checkbox:SetPoint("TOPLEFT", 0, yOffset)
            checkboxes[index] = checkbox
            yOffset = yOffset - 32
        end

        panel:SetScript("OnShow", function()
            local settings = AttendanceSettings()
            for index, info in ipairs(CONTENT_CHECKBOXES) do
                checkboxes[index]:SetValue(ReadSettingPath(settings, info.path))
            end
        end)
    end

    local function SetupDatabase(panel)
        PRT.AttendanceDatabaseUI:Build(panel)
    end

    return PRT.Components.GetSubTabGroup(parent, {
        { name = "Grid", setup = SetupGrid },
        { name = "Records", setup = SetupRecords },
        { name = "Database", setup = SetupDatabase },
        { name = "Settings", setup = SetupSettings },
    })
end)

--- A hidden grid is rebuilt by its own OnShow, and Build's un-rostered walk is
--- the costly one, so it is never rebuilt out of sight. The modal is a separate
--- top-level frame and answers to its own visibility.
function AttendanceUI:Refresh()
    if RefreshGrid and gridPanel and gridPanel:IsVisible() then
        RefreshGrid()
    end

    if not editModal or not editModal:IsShown() then
        return
    end

    local db = PurplexityRaidToolsAttendanceDB or {}
    if not db[editState.day] then
        editModal:Hide()
        return
    end
    if not HasRecordedCharacter(editState.characters) then
        editModal:Hide()
        return
    end
    RenderEditModal()
end
