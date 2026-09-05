local PRT = PurplexityRaidTools
local AttendanceDetailsUI = {}
PRT.AttendanceDetailsUI = AttendanceDetailsUI

local PAGE_SIZE = 10
local PLOT_HEIGHT = 155
local GOLD = { 0.84, 0.72, 0.47 }
local SERIES = {
    { field = "itemLevel", label = "Equipped item level", color = GOLD, offset = 0 },
    { field = "missingEnchants", label = "Missing enchants", color = { 0.2, 0.6, 1 }, offset = 1 },
    { field = "missingGems", label = "Missing gems", color = { 1, 0.25, 0.25 }, offset = 2 },
}

local function Label(parent, template, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", template)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then
        label:SetWidth(width)
    end
    return label
end

local function Button(parent, text, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function ItemLevel(value)
    return value and string.format("%.1f", value) or "-"
end

local function MissingText(missing)
    if not missing then
        return "None recorded"
    end
    local slots = {}
    for slot in pairs(missing) do
        slots[#slots + 1] = slot
    end
    table.sort(slots)
    local names = {}
    for _, slot in ipairs(slots) do
        local name = PRT.GearAudit.GetSlotName(slot) or tostring(slot)
        if missing[slot] > 1 then
            name = name .. " (" .. missing[slot] .. ")"
        end
        names[#names + 1] = name
    end
    return #names > 0 and table.concat(names, ", ") or "0"
end

local function SeriesValue(observation, field)
    local value = observation[field]
    if field == "itemLevel" or value == nil then
        return value
    end
    local count = 0
    for _, missing in pairs(value) do
        count = count + missing
    end
    return count
end

local function RenderObservation(view)
    local selected
    for _, observation in ipairs(view.history.observations) do
        if observation.day == view.selectedDay then
            selected = observation
            break
        end
    end
    if not selected then
        selected = view.history.observations[math.max(1, #view.history.observations - view.pageOffset)]
        view.selectedDay = selected and selected.day
    end
    view.edit:SetEnabled(selected ~= nil)
    if not selected then
        view.observation:SetText("No attendance records remain for this player.")
        view.enchants:SetText("")
        view.gems:SetText("")
        return
    end
    local levelLabel = selected.gearSnapshotTaken and "Arrival equipped ilvl: " or "Recorded equipped ilvl: "
    view.observation:SetText(view.format.Date(selected.day) .. "   "
        .. view.format.Status(selected.status) .. "   " .. levelLabel
        .. ItemLevel(selected.itemLevel))
    view.enchants:SetText("Missing enchants: " .. MissingText(selected.missingEnchants))
    view.gems:SetText("Missing gems: " .. MissingText(selected.missingGems))
    for _, column in ipairs(view.columns) do
        column.selection:SetShown(column.day == view.selectedDay)
    end
end

local function DrawSeries(view, series, x, y, previous)
    series.marker:Hide()
    series.line:Hide()
    if y == nil then
        return nil
    end
    series.marker:ClearAllPoints()
    series.marker:SetPoint("CENTER", view.plot, "TOPLEFT", x, -y)
    series.marker:Show()
    if previous then
        series.line:SetStartPoint("TOPLEFT", view.plot, previous.x, -previous.y)
        series.line:SetEndPoint("TOPLEFT", view.plot, x, -y)
        series.line:Show()
    end
    return { x = x, y = y }
end

local function DrawColumn(view, column, observation, x)
    column.day = observation.day
    column:ClearAllPoints()
    column:SetPoint("TOPLEFT", view.plot, "TOPLEFT", x - 22, 0)
    column:SetSize(44, PLOT_HEIGHT + 63)
    column.date:SetText(view.format.Date(observation.day))
    column.status:SetText(view.format.Status(observation.status))
    column:Show()
end

local function ChartBounds(observations, first, last)
    local low, high, countHigh
    for index = first, last do
        local observation = observations[index]
        local level = observation and observation.itemLevel
        if level then
            low = low and math.min(low, level) or level
            high = high and math.max(high, level) or level
        end
        if observation then
            for _, field in ipairs({ "missingEnchants", "missingGems" }) do
                local count = SeriesValue(observation, field)
                if count ~= nil then
                    countHigh = math.max(countHigh or 0, count)
                end
            end
        end
    end
    return low, high, countHigh
end

local function RenderChart(view)
    local observations = view.history.observations
    local last = math.max(1, #observations - view.pageOffset)
    local first = math.max(1, last - PAGE_SIZE + 1)
    local low, high, countHigh = ChartBounds(observations, first, last)
    local hasLevels, hasCounts = low ~= nil, countHigh ~= nil
    view.empty:SetShown(not hasLevels and not hasCounts)
    low, high = math.floor((low or 0) - 2), math.ceil((high or 0) + 2)
    countHigh = math.max(2, math.ceil((countHigh or 0) / 2) * 2)
    local width = math.max(1, view.plot:GetWidth())
    view.countTitle:SetShown(hasCounts)
    for index, axis in ipairs(view.axes) do
        local fraction = (index - 1) / 2
        axis.label:SetText(ItemLevel(high - (high - low) * fraction))
        axis.label:SetShown(hasLevels)
        axis.count:SetText(string.format("%d", countHigh * (1 - fraction)))
        axis.count:SetShown(hasCounts)
        axis.line:SetStartPoint("TOPLEFT", view.plot, 0, -fraction * PLOT_HEIGHT)
        axis.line:SetEndPoint("TOPLEFT", view.plot, width, -fraction * PLOT_HEIGHT)
    end
    local previous = {}
    for order, column in ipairs(view.columns) do
        local observation = order <= last - first + 1 and observations[first + order - 1]
        if observation then
            local x = width * (order - 0.5) / (last - first + 1)
            DrawColumn(view, column, observation, x)
            for _, definition in ipairs(SERIES) do
                local field = definition.field
                local value = SeriesValue(observation, field)
                local y
                if value ~= nil then
                    if field == "itemLevel" then
                        y = (high - value) / (high - low) * PLOT_HEIGHT
                    else
                        y = (countHigh - value) / countHigh * PLOT_HEIGHT
                    end
                    y = y - definition.offset
                end
                previous[field] = DrawSeries(view, column.series[field], x, y, previous[field])
            end
        else
            column:Hide()
            for _, series in pairs(column.series) do
                series.marker:Hide()
                series.line:Hide()
            end
        end
    end
    view.older:SetEnabled(first > 1)
    view.newer:SetEnabled(view.pageOffset > 0)
    view.range:SetText(observations[first] and (view.format.Date(observations[first].day)
        .. "–" .. view.format.Date(observations[last].day)) or "")
    RenderObservation(view)
end

local function Render(view)
    view.history = PRT.AttendanceReport:GetCharacterHistory(
        PurplexityRaidToolsAttendanceDB or {}, view.days, view.character)
    view.title:SetText(view.entry.name .. " · Raider details")
    local attended, recorded = PRT.AttendanceReport:GetAttendanceCounts(view.entry.statuses)
    view.attendance:SetText(view.format.Percentage(view.entry.percentage) .. " attendance   "
        .. attended .. "/" .. recorded .. " recorded days across all characters")
    local first, last = view.history.first, view.history.last
    view.latest:SetText("Latest recorded ilvl\n" .. ItemLevel(last and last.itemLevel)
        .. "\n" .. (last and view.format.Date(last.day) or "No measurement"))
    view.first:SetText("First recorded ilvl\n" .. ItemLevel(first and first.itemLevel)
        .. "\n" .. (first and view.format.Date(first.day) or "No measurement"))
    local change = view.history.change
    view.change:SetText("Period change\n" .. (change and string.format("%+.1f", change) or "-")
        .. "\n" .. view.history.measuredDays .. " measured days")
    view.characterName:SetText(view.character)
    view.dropdown:SetShown(#view.entry.characters > 1)
    view.characterName:SetShown(#view.entry.characters == 1)
    view.dropdown:GenerateMenu()
    view.pageOffset = math.min(view.pageOffset, math.max(0, #view.history.observations - 1))
    RenderChart(view)
end

local function CreateColumn(view)
    local column = CreateFrame("Button", nil, view.plot)
    column.selection = column:CreateTexture(nil, "BACKGROUND")
    column.selection:SetColorTexture(0.84, 0.72, 0.47, 0.15)
    column.selection:SetPoint("TOPLEFT", 1, -(PLOT_HEIGHT + 30))
    column.selection:SetPoint("BOTTOMRIGHT", -1, 0)
    column.date = Label(column, "GameFontDisableSmall", 0, -(PLOT_HEIGHT + 9), 44)
    column.date:SetJustifyH("CENTER")
    column.status = Label(column, "GameFontHighlightSmall", 0, -(PLOT_HEIGHT + 39), 44)
    column.status:SetJustifyH("CENTER")
    column.series = {}
    for layer, definition in ipairs(SERIES) do
        local marker = column:CreateTexture(nil, "OVERLAY", nil, layer)
        marker:SetSize(4, 4)
        marker:SetColorTexture(unpack(definition.color))
        local line = view.plot:CreateLine(nil, "ARTWORK", nil, layer)
        line:SetColorTexture(unpack(definition.color))
        line:SetThickness(1)
        column.series[definition.field] = { marker = marker, line = line }
    end
    column:SetScript("OnClick", function()
        view.selectedDay = column.day
        RenderObservation(view)
    end)
    return column
end

function AttendanceDetailsUI:Build(parent, callbacks)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    view.format = callbacks
    view.pageOffset = 0
    view.back = Button(view, "Back to attendance", 140, callbacks.Back)
    view.back:SetPoint("TOPLEFT", 20, -8)
    view.title = Label(view, "GameFontNormalLarge", 20, -43, 650)
    view.dropdown = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    view.dropdown:SetSize(280, 24)
    view.dropdown:SetPoint("TOPLEFT", 20, -70)
    view.dropdown:SetupMenu(function(_, menu)
        if not view.entry then
            return
        end
        for _, character in ipairs(view.entry.characters) do
            menu:CreateRadio(character, function() return view.character == character end, function()
                view.character = character
                view.pageOffset = 0
                view.selectedDay = nil
                Render(view)
            end)
        end
    end)
    view.characterName = Label(view, "GameFontHighlight", 20, -76, 650)
    view.attendance = Label(view, "GameFontHighlightSmall", 20, -110, 650)
    view.latest = Label(view, "GameFontHighlight", 20, -137, 150)
    view.first = Label(view, "GameFontHighlight", 185, -137, 150)
    view.change = Label(view, "GameFontHighlight", 350, -137, 150)
    for index, definition in ipairs(SERIES) do
        local legend = Label(view, "GameFontNormal", 64 + (index - 1) * 175, -202)
        legend:SetText(definition.label)
        legend:SetTextColor(unpack(definition.color))
    end
    view.plot = CreateFrame("Frame", nil, view)
    view.plot:SetPoint("TOPLEFT", 64, -226)
    view.plot:SetPoint("RIGHT", view, "RIGHT", -70, 0)
    view.plot:SetHeight(PLOT_HEIGHT)
    view.countTitle = Label(view.plot, "GameFontDisableSmall", 0, 0)
    view.countTitle:ClearAllPoints()
    view.countTitle:SetPoint("TOPLEFT", view.plot, "TOPRIGHT", 8, 24)
    view.countTitle:SetText("Count")
    view.axes = {}
    for index = 1, 3 do
        local label = Label(view.plot, "GameFontDisableSmall", -44, 5 - (index - 1) * PLOT_HEIGHT / 2, 36)
        label:SetJustifyH("RIGHT")
        local count = Label(view.plot, "GameFontDisableSmall", 0, 0, 36)
        count:ClearAllPoints()
        count:SetPoint("TOPLEFT", view.plot, "TOPRIGHT", 8, 5 - (index - 1) * PLOT_HEIGHT / 2)
        local line = view.plot:CreateLine(nil, "BACKGROUND")
        line:SetColorTexture(0.35, 0.35, 0.35, 0.6)
        line:SetThickness(1)
        view.axes[index] = { label = label, count = count, line = line }
    end
    view.empty = Label(view.plot, "GameFontDisableSmall", 0, -65)
    view.empty:SetPoint("RIGHT", 0, 0)
    view.empty:SetJustifyH("CENTER")
    view.empty:SetText("No gear measurements were recorded in these raid days.")
    view.columns = {}
    for index = 1, PAGE_SIZE do
        view.columns[index] = CreateColumn(view)
    end
    view.older = Button(view, "Older", 65, function()
        view.pageOffset = view.pageOffset + PAGE_SIZE
        view.selectedDay = nil
        Render(view)
    end)
    view.older:SetPoint("TOPLEFT", 20, -457)
    view.newer = Button(view, "Newer", 65, function()
        view.pageOffset = math.max(0, view.pageOffset - PAGE_SIZE)
        view.selectedDay = nil
        Render(view)
    end)
    view.newer:SetPoint("LEFT", view.older, "RIGHT", 6, 0)
    view.range = Label(view, "GameFontDisableSmall", 170, -462)
    view.observation = Label(view, "GameFontHighlight", 20, -498, 510)
    view.edit = Button(view, "Edit attendance", 130, function()
        if view.selectedDay then
            callbacks.Edit(view.entry, view.selectedDay, callbacks.Date(view.selectedDay))
        end
    end)
    view.edit:SetPoint("TOPRIGHT", -25, -491)
    view.enchants = Label(view, "GameFontHighlightSmall", 20, -526)
    view.enchants:SetTextColor(unpack(SERIES[2].color))
    view.enchants:SetPoint("RIGHT", -25, 0)
    view.gems = Label(view, "GameFontHighlightSmall", 20, -555)
    view.gems:SetTextColor(unpack(SERIES[3].color))
    view.gems:ClearAllPoints()
    view.gems:SetPoint("TOPLEFT", view.enchants, "BOTTOMLEFT", 0, -10)
    view.gems:SetPoint("RIGHT", -25, 0)
    local note = Label(view, "GameFontDisableSmall", 20, -590)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", view.gems, "BOTTOMLEFT", 0, -14)
    note:SetPoint("RIGHT", -25, 0)
    note:SetText("Missing counts reflect arrival snapshots and can exclude uninspected slots. "
        .. "Zero means none missing; unrecorded values leave gaps.")
    view:SetScript("OnSizeChanged", function()
        if view.history and view:IsShown() then
            RenderChart(view)
        end
    end)
    function view.SetEntry(target, entry, days, character)
        target.entry, target.days = entry, days
        local _, latestCharacter = PRT.AttendanceReport:GetLatestItemLevel(
            PurplexityRaidToolsAttendanceDB or {}, days, entry.characters)
        target.character = character or latestCharacter or entry.characters[1]
        Render(target)
    end
    function view.Open(target, entry, days)
        target.pageOffset = 0
        target.selectedDay = nil
        target:SetEntry(entry, days)
        target:Show()
        RenderChart(target)
    end
    return view
end
