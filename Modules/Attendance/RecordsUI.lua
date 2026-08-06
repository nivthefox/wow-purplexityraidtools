-- RecordsUI: the Records top tab. Lists the union of the days recorded locally
-- and the days other raid members report holding, and owns the pull/push/delete
-- controls, the two expiry settings, and the confirmation prompts for an
-- incoming replacement.
--
-- The list is rebuilt only when the data behind it changes -- the panel being
-- shown, Refresh, a local edit, or a message arriving -- never on a timer and
-- never per keystroke.

local PRT = PurplexityRaidTools
local RecordsUI = {}
PRT.RecordsUI = RecordsUI

local ROW_HEIGHT = 24
local HEADER_HEIGHT = 20
local LIST_HEIGHT = 320
local SELECTOR_WIDTH = 140

local COLUMN_DATE = 0
local COLUMN_RECORDS = 150
local COLUMN_COPIES = 250
local COLUMN_ACTIONS = 450

local MIN_EXPIRY_DAYS, MAX_EXPIRY_DAYS = 1, 365
local MIN_ROLLOVER_HOUR, MAX_ROLLOVER_HOUR = 0, 12

local ISO_DAY_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local MONTH_ABBREVIATIONS = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

local listPanel
local listRows = {}
local RefreshList

--- Survives a rebuild so refreshing the list does not throw away whichever copy
--- the officer picked.
local selectedSenderByDay = {}

local promptedDay
local promptedRoster

local function PrintMessage(message)
    print("|cFF00FF00PurplexityRaidTools:|r " .. message)
end

local function PrintError(message)
    print("|cFFFF0000PurplexityRaidTools:|r " .. message)
end

--- Day keys are parsed rather than run back through date(): they were derived in
--- the server frame, and re-reading them through the client's clock would relabel
--- a record whose officer sits in another timezone.
local function ParseDay(day)
    local year, month, dayOfMonth = tostring(day):match(ISO_DAY_PATTERN)
    if not year then
        return nil
    end
    return tonumber(year), tonumber(month), tonumber(dayOfMonth)
end

local function LongDate(day)
    local year, month, dayOfMonth = ParseDay(day)
    if not year or not MONTH_NAMES[month] then
        return tostring(day)
    end
    return MONTH_NAMES[month] .. " " .. dayOfMonth .. ", " .. year
end

local function ShortDate(day)
    local _, month, dayOfMonth = ParseDay(day)
    if not month or not MONTH_ABBREVIATIONS[month] then
        return tostring(day)
    end
    return MONTH_ABBREVIATIONS[month] .. " " .. dayOfMonth
end

local function AttendanceSettings()
    return PRT:GetSetting("attendance")
end

local function LocalDays()
    return PurplexityRaidToolsAttendanceDB or {}
end

local function CountRecords(dayRecord)
    local count = 0
    for _ in pairs(dayRecord) do
        count = count + 1
    end
    return count
end

local function SenderLabel(sender)
    return Ambiguate(sender, "short")
end

--- An inventory request broadcast to the raid is delivered back to its sender,
--- so the officer's own response can return to them. Their own records are
--- already the local column, and offering to pull them from themselves is not a
--- copy of anything.
---
--- The bare-name compare cannot tell a same-named character on a connected realm
--- from the local player, and here that mistake costs more than it does in
--- AttendanceSync: there an indistinguishable sender means one push ignored,
--- while here it hides a real raider's copy from the Copies column. Comparing
--- full name-realm instead would need the local realm on a name that arrives
--- realm-qualified only sometimes, which is the trade this leaves standing.
local function IsLocalPlayer(sender)
    return Ambiguate(sender, "short") == UnitName("player")
end

--- One row per day the officer could act on, newest first: every day recorded
--- locally, plus every day somebody else reported holding.
local function BuildRows()
    local counts, copies = {}, {}

    for day, dayRecord in pairs(LocalDays()) do
        counts[day] = CountRecords(dayRecord)
    end

    for sender, days in pairs(PRT.AttendanceSync:GetInventory()) do
        if not IsLocalPlayer(sender) then
            for day, count in pairs(days) do
                copies[day] = copies[day] or {}
                table.insert(copies[day], { sender = sender, count = count })
            end
        end
    end

    local rows, seen = {}, {}
    local function Collect(day)
        if seen[day] then
            return
        end
        seen[day] = true
        rows[#rows + 1] = {
            day = day,
            localCount = counts[day],
            copies = copies[day] or {},
        }
    end

    for day in pairs(counts) do
        Collect(day)
    end
    for day in pairs(copies) do
        Collect(day)
    end

    table.sort(rows, function(a, b)
        return a.day > b.day
    end)

    for _, row in ipairs(rows) do
        table.sort(row.copies, function(a, b)
            return a.sender < b.sender
        end)
    end

    return rows
end

local function SelectedCopy(row)
    if #row.copies == 0 then
        return nil
    end

    local chosen = selectedSenderByDay[row.day]
    for _, copy in ipairs(row.copies) do
        if copy.sender == chosen then
            return copy
        end
    end
    return row.copies[1]
end

--------------------------------------------------------------------------------
-- Confirmation prompts
--------------------------------------------------------------------------------

local function RefreshDependentViews()
    RecordsUI:Refresh()
    if PRT.AttendanceUI then
        PRT.AttendanceUI:Refresh()
    end
    if PRT.RosterUI then
        PRT.RosterUI:Refresh()
    end
end

--- The copy selector runs this from inside its own selection callback, where the
--- menu is still closing. Rebuilding the row calls GenerateMenu on that very
--- dropdown, so the rebuild waits for the next frame instead.
local function RefreshListAfterMenuCloses()
    C_Timer.After(0, function()
        RecordsUI:Refresh()
    end)
end

StaticPopupDialogs["PRT_ATTENDANCE_REPLACE_DAY"] = {
    text = "%s",
    button1 = "Replace",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        PRT.AttendanceSync:AcceptPendingDay()
    end,
    OnCancel = function()
        PRT.AttendanceSync:DeclinePendingDay()
    end,
}

StaticPopupDialogs["PRT_ATTENDANCE_REPLACE_ROSTER"] = {
    text = "%s",
    button1 = "Replace",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        PRT.AttendanceSync:AcceptPendingRoster()
    end,
    OnCancel = function()
        PRT.AttendanceSync:DeclinePendingRoster()
    end,
}

StaticPopupDialogs["PRT_ATTENDANCE_DELETE_DAY"] = {
    text = "%s",
    button1 = "Delete",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, day)
        PRT.AttendanceStore:DeleteDay(day)
        RefreshDependentViews()
    end,
}

local function DayReplacementQuestion(pending)
    return "Replace your attendance for " .. ShortDate(pending.day)
        .. " (" .. pending.localCount .. " records) with "
        .. SenderLabel(pending.sender) .. "'s (" .. pending.incomingCount .. " records)?"
end

local function RosterReplacementQuestion(pending)
    return "Replace your roster (" .. pending.localCount .. " players) with "
        .. SenderLabel(pending.sender) .. "'s (" .. pending.incomingCount .. " players)?"
end

--- Re-shown whenever the pending table itself changes so a second push landing
--- behind the first cannot leave the officer accepting one record while reading
--- the summary of another.
local function PromptPendingReplacements()
    local pendingDay = PRT.AttendanceSync:GetPendingDay()
    if pendingDay ~= promptedDay then
        promptedDay = pendingDay
        if pendingDay then
            StaticPopup_Show("PRT_ATTENDANCE_REPLACE_DAY", DayReplacementQuestion(pendingDay))
        end
    end

    local pendingRoster = PRT.AttendanceSync:GetPendingRoster()
    if pendingRoster ~= promptedRoster then
        promptedRoster = pendingRoster
        if pendingRoster then
            StaticPopup_Show("PRT_ATTENDANCE_REPLACE_ROSTER", RosterReplacementQuestion(pendingRoster))
        end
    end
end

--------------------------------------------------------------------------------
-- Row widgets
--------------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.date = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.date:SetPoint("LEFT", COLUMN_DATE, 0)
    row.date:SetJustifyH("LEFT")

    row.records = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.records:SetPoint("LEFT", COLUMN_RECORDS, 0)
    row.records:SetJustifyH("LEFT")

    row.selector = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    row.selector:SetWidth(SELECTOR_WIDTH)
    row.selector:SetHeight(20)
    row.selector:SetPoint("LEFT", COLUMN_COPIES, 0)
    row.selector:SetupMenu(function(_, rootDescription)
        for _, copy in ipairs(row.copies or {}) do
            rootDescription:CreateRadio(
                SenderLabel(copy.sender) .. " (" .. copy.count .. ")",
                function()
                    local selected = SelectedCopy(row)
                    return selected ~= nil and selected.sender == copy.sender
                end,
                function()
                    selectedSenderByDay[row.day] = copy.sender
                    RefreshListAfterMenuCloses()
                end
            )
        end
    end)

    row.pull = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.pull:SetSize(46, 20)
    row.pull:SetPoint("LEFT", row.selector, "RIGHT", 4, 0)
    row.pull:SetText("Pull")
    row.pull:SetScript("OnClick", function()
        local copy = SelectedCopy(row)
        if not copy then
            return
        end
        PRT.AttendanceSync:RequestDay(copy.sender, row.day)
        PrintMessage("Requested " .. LongDate(row.day) .. " from " .. SenderLabel(copy.sender) .. ".")
    end)

    row.push = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.push:SetSize(52, 20)
    row.push:SetPoint("LEFT", COLUMN_ACTIONS, 0)
    row.push:SetText("Push")
    row.push:SetScript("OnClick", function()
        if not PRT.AttendanceWiring:CanPushToRaid() then
            PrintError("Only a raid leader or assistant can push a record.")
            RecordsUI:Refresh()
            return
        end
        if not PRT.AttendanceSync:PushDay(row.day) then
            return
        end
        PrintMessage("Pushed " .. LongDate(row.day) .. " to the raid.")
    end)

    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetSize(58, 20)
    row.delete:SetPoint("LEFT", row.push, "RIGHT", 4, 0)
    row.delete:SetText("Delete")
    row.delete:SetScript("OnClick", function()
        local question = "Delete your attendance record for " .. LongDate(row.day)
            .. " (" .. (row.localCount or 0) .. " records)?"
        StaticPopup_Show("PRT_ATTENDANCE_DELETE_DAY", question, nil, row.day)
    end)

    return row
end

--- A day held only by other members has nothing local to broadcast or remove, so
--- it offers Pull alone.
local function FillRow(row, data)
    row.day = data.day
    row.copies = data.copies
    row.localCount = data.localCount

    row.date:SetText(LongDate(data.day))

    if data.localCount then
        row.records:SetText(data.localCount .. " recorded")
        row.push:Show()
        row.delete:Show()
        row.push:SetEnabled(PRT.AttendanceWiring:CanPushToRaid())
    else
        row.records:SetText("|cFF808080--|r")
        row.push:Hide()
        row.delete:Hide()
    end

    local copy = SelectedCopy(row)
    if copy then
        row.selector:Show()
        row.pull:Show()
        row.selector:GenerateMenu()
    else
        row.selector:Hide()
        row.pull:Hide()
    end

    row:Show()
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

local function RequestInventoryFromRaid()
    if not IsInGroup() then
        return
    end
    PRT.AttendanceSync:RequestInventory()
end

function RecordsUI:Build(panel)
    listPanel = panel

    local refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshButton:SetSize(80, 22)
    refreshButton:SetPoint("TOPRIGHT", -26, -8)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        RequestInventoryFromRaid()
        RefreshList()
    end)

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetPoint("RIGHT", panel, "RIGHT", -26, 0)

    local function AddHeading(text, offset)
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", offset, 0)
        label:SetText(text)
    end

    AddHeading("Date", COLUMN_DATE)
    AddHeading("Records", COLUMN_RECORDS)
    AddHeading("Copies", COLUMN_COPIES)
    AddHeading("Actions", COLUMN_ACTIONS)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("RIGHT", panel, "RIGHT", -26, 0)
    scrollFrame:SetHeight(LIST_HEIGHT)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(panel:GetWidth() - 60, LIST_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -4)
    emptyLabel:SetText("No attendance records yet. A pull countdown creates the first one.")

    local settingsTop = -(36 + HEADER_HEIGHT + LIST_HEIGHT + 16)

    local expirySlider = PRT.Components.GetSliderWithInput(
        panel, "Auto-expire after (days):",
        MIN_EXPIRY_DAYS, MAX_EXPIRY_DAYS, 1, false,
        function(value)
            AttendanceSettings().expiryDays = math.floor(value)
        end
    )
    expirySlider:SetPoint("TOPLEFT", 0, settingsTop)

    local rolloverSlider = PRT.Components.GetSliderWithInput(
        panel, "Day rollover hour:",
        MIN_ROLLOVER_HOUR, MAX_ROLLOVER_HOUR, 1, false,
        function(value)
            AttendanceSettings().rolloverHour = math.floor(value)
        end
    )
    rolloverSlider:SetPoint("TOPLEFT", 0, settingsTop - 32)

    local rolloverHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rolloverHint:SetPoint("TOPLEFT", 20, settingsTop - 60)
    rolloverHint:SetText("Pulls before this hour count toward the previous day.")

    RefreshList = function()
        local rows = BuildRows()

        for index, data in ipairs(rows) do
            local row = listRows[index]
            if not row then
                row = CreateRow(scrollChild, index)
                listRows[index] = row
            end
            FillRow(row, data)
        end

        for index = #rows + 1, #listRows do
            listRows[index]:Hide()
        end

        scrollChild:SetHeight(math.max(LIST_HEIGHT, #rows * ROW_HEIGHT))

        if #rows == 0 then
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end

        local settings = AttendanceSettings()
        expirySlider:SetValue(settings.expiryDays)
        rolloverSlider:SetValue(settings.rolloverHour)
    end

    panel:SetScript("OnShow", function()
        RequestInventoryFromRaid()
        RefreshList()
    end)
end

--- A hidden view is refreshed by its own OnShow, so rebuilding it here would be
--- work nobody sees. The Grid and Records panels are two tabs of one frame and
--- Roster is a third, so at most one of them is ever visible: an inventory
--- burst of one response per raid member cannot reach the grid's rebuild.
function RecordsUI:Refresh()
    if not RefreshList or not listPanel or not listPanel:IsVisible() then
        return
    end
    RefreshList()
end

--- The pending state is created by an arriving message rather than by anything
--- the officer did, so it announces itself. A roster replaced outright -- the
--- path with confirmation turned off -- raises no prompt at all, and this is the
--- only thing that tells the roster and grid their entries just changed.
PRT.AttendanceSync:Listen(function()
    PromptPendingReplacements()
    RefreshDependentViews()
end)
