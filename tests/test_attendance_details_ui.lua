local tests = {}

if not PurplexityRaidTools.AttendanceStore then dofile("Modules/Attendance/AttendanceStore.lua") end
if not PurplexityRaidTools.AttendanceReport then dofile("Modules/Attendance/AttendanceReport.lua") end
if not PurplexityRaidTools.GearAudit then dofile("Modules/GearAudit.lua") end

local function WithAttendanceFrames(body)
    local objects, tabSetup, grid = {}, nil, nil
    local popups = {}
    local function Object(parent)
        local object = { parent = parent, shown = true, scripts = {} }
        function object:SetText(text) self.text = text end
        function object:SetWidth(width) self.width = width end
        function object:SetHeight(height) self.height = height end
        function object:SetSize(width, height) self.width, self.height = width, height end
        function object:GetWidth()
            return rawget(self, "width") or (rawget(self, "parent") and self.parent:GetWidth()) or 730
        end
        function object:GetHeight() return rawget(self, "height") or 640 end
        function object:SetScript(event, callback) self.scripts[event] = callback end
        function object:Show() self.shown = true end
        function object:Hide() self.shown = false end
        function object:SetShown(shown) self.shown = shown end
        function object:IsShown() return self.shown end
        function object:IsVisible() return self.shown and (not rawget(self, "parent") or self.parent:IsVisible()) end
        function object:CreateTexture() return Object(self) end
        function object:CreateFontString() return Object(self) end
        function object:CreateLine() return Object(self) end
        function object:SetEnabled(enabled) self.enabled = enabled end
        function object:SetupMenu(callback) self.menu = callback end
        function object:SetStartPoint(...) self.start = { ... } end
        function object:SetEndPoint(...) self.finish = { ... } end
        function object:SetPoint(...) self.point = { ... } end
        function object:SetColorTexture(...) self.color = { ... } end
        setmetatable(object, { __index = function() return function() end end })
        objects[#objects + 1] = object
        return object
    end
    local originalPRT = PurplexityRaidTools
    local db = {
        ["2026-09-01"] = { ["Aster-Realm"] = { status = 3, itemLevel = 100 } },
        ["2026-09-02"] = { ["Astris-Realm"] = { status = 3, itemLevel = 900 } },
        ["2026-09-03"] = { ["Aster-Realm"] = { status = 2, itemLevel = 110,
            missingEnchants = { [11] = 1 }, missingGems = { [2] = 2 } } },
    }
    local roster = { { nickname = "Aster", characters = { "Aster-Realm", "Astris-Realm" } } }
    local prt = {
        AttendanceStore = originalPRT.AttendanceStore,
        AttendanceReport = originalPRT.AttendanceReport,
        GearAudit = originalPRT.GearAudit,
        Roster = { GetEntries = function() return roster end, GetCharacterClass = function() end },
        RegisterTab = function(_, _, setup) tabSetup = setup end,
        Components = { GetSubTabGroup = function(parent, definitions)
            grid = Object(parent)
            definitions[1].setup(grid)
            return grid
        end },
    }
    local tooltip = Object()
    function tooltip:SetText(text, _, _, _, alpha, wrap)
        assertTrue(alpha == nil or type(alpha) == "number", "tooltip alpha must be numeric")
        self.text, self.wrap = text, wrap
    end
    function tooltip:AddLine(text, _, _, _, wrap)
        self.text, self.wrap = text, wrap
    end
    local overrides = {
        PurplexityRaidTools = prt,
        PurplexityRaidToolsAttendanceDB = db,
        CreateFrame = function(_, _, parent, template)
            local frame = Object(parent)
            if template == "ButtonFrameTemplate" then frame.Inset = Object(frame) end
            return frame
        end,
        ButtonFrameTemplate_HidePortrait = function() end,
        ButtonFrameTemplate_HideButtonBar = function() end,
        UIParent = Object(), UISpecialFrames = {}, RAID_CLASS_COLORS = {}, GameTooltip = tooltip,
        StaticPopupDialogs = {},
        StaticPopup_Show = function(which, text, _, data)
            local dialog = StaticPopupDialogs[which]
            local popup = { dialog = dialog, text = string.format(dialog.text, text), data = data }
            function popup:Accept() self.dialog.OnAccept(self, self.data) end
            function popup:Cancel()
                if self.dialog.OnCancel then self.dialog.OnCancel(self, self.data) end
            end
            popups[#popups + 1] = popup
            return popup
        end,
        Ambiguate = function(name) return name:match("^[^-]+") end,
        strcmputf8i = function(a, b)
            a, b = a:lower(), b:lower()
            return a < b and -1 or a > b and 1 or 0
        end,
    }
    local saved = {}
    for key, value in pairs(overrides) do saved[key] = _G[key]; _G[key] = value end
    local ok, err = pcall(function()
        dofile("Modules/Attendance/AttendanceDetailsUI.lua")
        dofile("Modules/Attendance/AttendanceUI.lua")
        tabSetup(Object())
        grid.scripts.OnShow()
        local row, detail
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") then row = object end
            if rawget(object, "columns") then detail = object end
        end
        body(prt, row, detail, objects, db, roster, popups)
    end)
    for key in pairs(overrides) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

local function SortingRecords(db, roster)
    wipe(db)
    wipe(roster)
    local names = { "Zulu", "Alpha", "bravo", "Charlie", "Delta", "Echo" }
    local statuses = { 3, 4, 2, 1, 0 }
    local levels = { 110, 100, 110, false, 90 }
    db["2026-09-03"] = {}
    db["2026-09-02"] = {}
    for index, name in ipairs(names) do
        local character = name .. "-Realm"
        roster[index] = { nickname = name, characters = { character } }
        if statuses[index] then
            db["2026-09-03"][character] = { status = statuses[index], itemLevel = levels[index] or nil }
        end
        db["2026-09-02"][character] = { status = 1 }
    end
    db["2026-09-02"]["Alpha-Realm"].status = 3
    db["2026-09-02"]["Charlie-Realm"].status = 0
    db["2026-09-02"]["Echo-Realm"] = { status = 3, itemLevel = 120 }
    db["2026-09-03"]["GuestA-Realm"] = { status = 1, itemLevel = 90 }
    db["2026-09-03"]["GuestZ-Realm"] = { status = 3, itemLevel = 100 }
end

local function GridRows(objects)
    local rows = {}
    for _, object in ipairs(objects) do
        if rawget(object, "nameButton") and object:IsVisible() then
            rows[#rows + 1] = object
        end
    end
    return rows
end

local function GridNames(objects)
    local names = {}
    for _, row in ipairs(GridRows(objects)) do
        names[#names + 1] = row.name.text
    end
    return names
end

local function SortHeading(objects, key)
    for _, object in ipairs(objects) do
        if rawget(object, "sortKey") == key then
            return object
        end
    end
    error("No sort heading for " .. key)
end

tests["attendance hover tooltips wrap without invalid alpha arguments"] = function()
    WithAttendanceFrames(function(prt, _, _, objects, db, roster)
        for _, key in ipairs({ "player", "percentage", "itemLevel" }) do
            local heading = SortHeading(objects, key)
            heading.scripts.OnEnter(heading)
            assertEquals(GameTooltip.text, "Click to sort. Click again to reverse the order.")
            assertTrue(GameTooltip.wrap)
            assertTrue(GameTooltip:IsShown())
            heading.scripts.OnLeave(heading)
            assertFalse(GameTooltip:IsShown())
        end
        SortingRecords(db, roster)
        prt.AttendanceUI:Refresh()
        local deleteButton = GridRows(objects)[7].delete
        deleteButton.scripts.OnEnter(deleteButton)
        assertEquals(GameTooltip.text, "Delete all attendance records for GuestA-Realm.")
        assertTrue(GameTooltip.wrap)
        assertTrue(GameTooltip:IsShown())
        deleteButton.scripts.OnLeave(deleteButton)
        assertFalse(GameTooltip:IsShown())
    end)
end

tests["grid headings sort names and numeric columns both ways without changing saved records"] = function()
    WithAttendanceFrames(function(prt, _, _, objects, db, roster)
        SortingRecords(db, roster)
        local savedDB, savedRoster = CopyTable(db), CopyTable(roster)
        prt.AttendanceUI:Refresh()
        assertTableEquals(GridNames(objects), {
            "Alpha", "bravo", "Charlie", "Delta", "Echo", "Zulu", "GuestA-Realm", "GuestZ-Realm",
        })
        SortHeading(objects, "player").scripts.OnClick()
        assertTableEquals(GridNames(objects), {
            "Zulu", "Echo", "Delta", "Charlie", "bravo", "Alpha", "GuestA-Realm", "GuestZ-Realm",
        })
        SortHeading(objects, "player").scripts.OnClick()
        assertEquals(GridNames(objects)[1], "Alpha")

        SortHeading(objects, "percentage").scripts.OnClick()
        assertTableEquals(GridNames(objects), {
            "Alpha", "Echo", "bravo", "Zulu", "Charlie", "Delta", "GuestA-Realm", "GuestZ-Realm",
        })
        SortHeading(objects, "percentage").scripts.OnClick()
        assertTableEquals(GridNames(objects), {
            "Charlie", "Delta", "bravo", "Zulu", "Alpha", "Echo", "GuestA-Realm", "GuestZ-Realm",
        })

        SortHeading(objects, "itemLevel").scripts.OnClick()
        assertTableEquals(GridNames(objects), {
            "Echo", "bravo", "Zulu", "Alpha", "Delta", "Charlie", "GuestA-Realm", "GuestZ-Realm",
        })
        SortHeading(objects, "itemLevel").scripts.OnClick()
        assertTableEquals(GridNames(objects), {
            "Delta", "Alpha", "bravo", "Zulu", "Echo", "Charlie", "GuestA-Realm", "GuestZ-Realm",
        })
        assertTableEquals(db, savedDB)
        assertTableEquals(roster, savedRoster)
    end)
end

tests["sorting survives refresh and detail navigation while row actions follow the displayed player"] = function()
    WithAttendanceFrames(function(prt, _, detail, objects, db, roster)
        SortingRecords(db, roster)
        prt.AttendanceUI:Refresh()
        local heading = SortHeading(objects, "itemLevel")
        heading.scripts.OnClick()
        assertTrue(heading.arrow:IsShown())
        assertFalse(SortHeading(objects, "player").arrow:IsShown())
        local row = GridRows(objects)[1]
        assertEquals(row.name.text, "Echo")
        row.nameButton.scripts.OnClick()
        assertEquals(detail.character, "Echo-Realm")
        detail.back.scripts.OnClick()
        assertEquals(GridNames(objects)[1], "Echo")
        db["2026-09-03"]["Delta-Realm"].itemLevel = 130
        prt.AttendanceUI:Refresh()
        assertEquals(row.name.text, "Delta")
        assertEquals(row.itemLevel.text, "130.0")
        row.cells[1].scripts.OnClick()
        local modal
        for _, object in ipairs(objects) do
            if rawget(object, "characterRows") then modal = object end
        end
        assertEquals(modal.characterRows[1].character, "Delta-Realm")
    end)
end

tests["names navigate to character history while attendance cells still edit the original records"] = function()
    WithAttendanceFrames(function(prt, row, detail, objects, db)
        assertEquals(row.itemLevel.text, "110.0")
        row.nameButton.scripts.OnClick()
        assertTrue(detail:IsShown())
        assertFalse(row:IsVisible())
        assertEquals(detail.character, "Aster-Realm")
        assertEquals(detail.history.change, 10)
        assertFalse(detail.columns[2].series.itemLevel.marker:IsShown())
        assertFalse(detail.columns[3].series.itemLevel.line:IsShown(),
            "the graph must not connect across an unmeasured day")
        assertEquals(detail.gems.text, "Missing gems: Neck (2)")
        detail.back.scripts.OnClick()
        assertFalse(detail:IsShown())
        assertTrue(row:IsVisible())
        assertTrue(row.selection:IsShown())
        row.cells[1].scripts.OnClick()
        local modal
        for _, object in ipairs(objects) do
            if rawget(object, "characterRows") then modal = object end
        end
        assertTrue(modal:IsShown())
        modal.characterRows[1].buttons[2].scripts.OnClick()
        assertEquals(db["2026-09-03"]["Aster-Realm"].status, 4)
        assertEquals(db["2026-09-03"]["Aster-Realm"].itemLevel, 110)
        assertTableEquals(db["2026-09-03"]["Aster-Realm"].missingGems, { [2] = 2 })
        prt.AttendanceUI:Refresh()
        assertEquals(row.itemLevel.text, "110.0")
    end)
end

tests["gear chart totals missing slots on a count axis and includes zero arrival counts without item levels"] = function()
    WithAttendanceFrames(function(_, row, detail, _, db)
        db["2026-09-01"]["Aster-Realm"] = { status = 3, gearSnapshotTaken = true,
            missingEnchants = { [11] = 1, [12] = 1 }, missingGems = { [2] = 3, [11] = 2 } }
        db["2026-09-02"] = { ["Aster-Realm"] = { status = 3, gearSnapshotTaken = true,
            missingEnchants = {}, missingGems = {} } }
        db["2026-09-03"]["Aster-Realm"].itemLevel = nil
        row.nameButton.scripts.OnClick()

        assertFalse(detail.empty:IsShown())
        assertFalse(detail.axes[1].label:IsShown())
        assertEquals(detail.axes[1].count.text, "6")
        assertEquals(detail.axes[2].count.text, "3")
        assertEquals(detail.axes[3].count.text, "0")
        local first = detail.columns[1].series
        assertTrue(first.missingEnchants.marker:IsShown())
        assertTrue(first.missingGems.marker:IsShown())
        assertFalse(first.itemLevel.marker:IsShown())
        assertNear(first.missingEnchants.marker.point[5], -155 * 4 / 6 + 1, 0.001)
        assertNear(first.missingGems.marker.point[5], -155 / 6 + 2, 0.001)
        assertTableEquals(first.missingEnchants.line.color, { 0.2, 0.6, 1 })
        assertTableEquals(first.missingGems.line.color, { 1, 0.25, 0.25 })
        local second = detail.columns[2].series
        assertTrue(second.missingEnchants.line:IsShown())
        assertTrue(second.missingGems.line:IsShown())
        assertEquals(second.missingEnchants.marker.point[5], -155 + 1)
        assertEquals(second.missingGems.marker.point[5], -155 + 2)
        detail.columns[2].scripts.OnClick()
        assertEquals(detail.enchants.text, "Missing enchants: 0")
        assertEquals(detail.gems.text, "Missing gems: 0")
        assertTrue(detail.columns[3].series.missingEnchants.line:IsShown())
        assertTrue(detail.columns[3].series.missingGems.line:IsShown())
    end)
end

tests["gear chart leaves independent gaps for unrecorded missing counts"] = function()
    WithAttendanceFrames(function(_, row, detail, _, db)
        db["2026-09-01"]["Aster-Realm"].missingEnchants = { [11] = 1 }
        db["2026-09-02"]["Aster-Realm"] = { status = 3, itemLevel = 105,
            gearSnapshotTaken = true, missingGems = { [2] = 2 } }
        row.nameButton.scripts.OnClick()

        local first, second, third = detail.columns[1].series, detail.columns[2].series, detail.columns[3].series
        assertTrue(first.missingEnchants.marker:IsShown())
        assertFalse(first.missingGems.marker:IsShown())
        assertFalse(second.missingEnchants.marker:IsShown())
        assertTrue(second.missingGems.marker:IsShown())
        assertFalse(second.missingGems.line:IsShown())
        assertFalse(third.missingEnchants.line:IsShown())
        assertTrue(third.missingGems.line:IsShown())
        assertTrue(third.itemLevel.line:IsShown())
        detail.columns[2].scripts.OnClick()
        assertEquals(detail.enchants.text, "Missing enchants: None recorded")

        local choices = {}
        detail.dropdown.menu(nil, { CreateRadio = function(_, name, _, callback) choices[name] = callback end })
        choices["Astris-Realm"]()
        assertFalse(detail.axes[1].count:IsShown())
        for _, column in ipairs(detail.columns) do
            assertFalse(column.series.missingEnchants.marker:IsShown())
            assertFalse(column.series.missingEnchants.line:IsShown())
            assertFalse(column.series.missingGems.marker:IsShown())
            assertFalse(column.series.missingGems.line:IsShown())
        end
    end)
end

tests["overview and initial history follow the most recently recorded character"] = function()
    WithAttendanceFrames(function(prt, row, detail, _, db)
        db["2026-09-04"] = { ["Astris-Realm"] = { status = 3, itemLevel = 910 },
            ["Aster-Realm"] = { status = 0 } }
        prt.AttendanceUI:Refresh()
        assertEquals(row.itemLevel.text, "910.0")
        row.nameButton.scripts.OnClick()
        assertEquals(detail.character, "Astris-Realm")
        assertEquals(detail.history.last.itemLevel, 910)
        assertEquals(detail.history.change, 10)
        detail.back.scripts.OnClick()
        db["2026-09-05"] = { ["Aster-Realm"] = { status = 3, gearSnapshotTaken = true } }
        prt.AttendanceUI:Refresh()
        assertEquals(row.itemLevel.text, "910.0")
        row.nameButton.scripts.OnClick()
        assertEquals(detail.character, "Astris-Realm")
    end)
end

tests["detail character selection and data refresh keep independent gear histories"] = function()
    WithAttendanceFrames(function(prt, row, detail, _, db, roster)
        row.nameButton.scripts.OnClick()
        local choices = {}
        detail.dropdown.menu(nil, { CreateRadio = function(_, name, _, callback) choices[name] = callback end })
        choices["Astris-Realm"]()
        assertEquals(detail.history.last.itemLevel, 900)
        assertNil(detail.history.change)
        assertEquals(detail.character, "Astris-Realm")
        roster[1].nickname = "Renamed"
        prt.AttendanceUI:Refresh()
        assertEquals(detail.entry.name, "Renamed")
        assertEquals(detail.character, "Astris-Realm")
        db["2026-09-02"] = nil
        prt.AttendanceUI:Refresh()
        assertEquals(detail.history.measuredDays, 0)
        assertTrue(detail.empty:IsShown())
    end)
end

tests["older chart pages select a day from that page and can open its attendance editor"] = function()
    WithAttendanceFrames(function(_, row, detail, _, db)
        for index = 4, 20 do
            db[string.format("2026-09-%02d", index)] = { ["Aster-Realm"] = { status = 3, itemLevel = 100 + index } }
        end
        detail:Open({ name = "Aster", characters = { "Aster-Realm" }, statuses = {}, percentage = 100 },
            PurplexityRaidTools.AttendanceReport:Build(db, {}).days)
        assertEquals(detail.selectedDay, "2026-09-20")
        detail.older.scripts.OnClick()
        assertEquals(detail.selectedDay, "2026-09-10")
        assertEquals(detail.columns[1].day, "2026-09-01")
        detail.newer.scripts.OnClick()
        assertEquals(detail.selectedDay, "2026-09-20")
        row.nameButton.scripts.OnClick()
    end)
end

tests["the unrostered delete button removes every day including history outside the visible columns"] = function()
    WithAttendanceFrames(function(prt, rosterRow, _, objects, db, _, popups)
        local original = CopyTable(db)
        for index = 4, 20 do
            db[string.format("2026-09-%02d", index)] = { ["Guest-Realm"] = { status = 3, itemLevel = 100 } }
        end
        db["2026-09-01"]["Guest-Realm"] = { status = 0 }
        db["2026-09-01"]["Guest-OtherRealm"] = { status = 3 }
        original["2026-09-01"]["Guest-OtherRealm"] = { status = 3 }
        prt.AttendanceUI:Refresh()

        assertFalse(rosterRow.delete:IsShown())
        local guestRow
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") and object.name.text == "Guest-Realm" then guestRow = object end
        end
        assertNotNil(guestRow)
        assertTrue(guestRow.delete:IsShown())
        assertEquals(guestRow.delete.text, "|cFFFF0000x|r")
        local beforeConfirmation = CopyTable(db)
        guestRow.delete.scripts.OnClick()
        assertTableEquals(db, beforeConfirmation)
        assertEquals(#popups, 1)
        assertEquals(popups[1].data, "Guest-Realm")
        assertEquals(popups[1].text, "Are you sure you want to delete all attendance and recorded gear history for "
            .. "Guest-Realm across all saved days?")
        assertEquals(popups[1].dialog.button1, "Delete")
        assertEquals(popups[1].dialog.button2, "Cancel")
        popups[1]:Accept()

        assertTableEquals(db, original)
        assertFalse(guestRow:IsShown())
        assertTrue(rosterRow:IsShown())
        assertEquals(rosterRow.itemLevel.text, "110.0")
    end)
end

tests["deleting the last unrostered row closes its editor and hides the empty section"] = function()
    WithAttendanceFrames(function(prt, _, _, objects, db, _, popups)
        db["2026-09-03"]["Guest-Realm"] = { status = 3 }
        prt.AttendanceUI:Refresh()
        local guestRow, section
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") and object.name.text == "Guest-Realm" then guestRow = object end
            if rawget(object, "text") == "Not on roster" then section = object end
        end
        guestRow.cells[1].scripts.OnClick()
        local modal
        for _, object in ipairs(objects) do
            if rawget(object, "characterRows") then modal = object end
        end
        assertTrue(modal:IsShown())
        assertTrue(section:IsShown())

        guestRow.delete.scripts.OnClick()
        popups[1]:Accept()

        assertFalse(guestRow:IsShown())
        assertFalse(modal:IsShown())
        assertFalse(section:IsShown())
    end)
end

tests["a reused unrostered row loses its delete action when the player joins the roster"] = function()
    WithAttendanceFrames(function(prt, rosterRow, _, objects, db, roster)
        db["2026-09-03"]["Guest-Realm"] = { status = 3 }
        prt.AttendanceUI:Refresh()
        local guestRow
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") and object.name.text == "Guest-Realm" then guestRow = object end
        end
        assertTrue(guestRow.delete:IsShown())
        assertTrue(guestRow.nameButton.width < rosterRow.nameButton.width)
        roster[#roster + 1] = { nickname = "Guest", characters = { "Guest-Realm" } }

        prt.AttendanceUI:Refresh()

        assertEquals(guestRow.name.text, "Guest")
        assertFalse(guestRow.delete:IsShown())
        assertEquals(guestRow.nameButton.width, rosterRow.nameButton.width)
        guestRow.delete.scripts.OnClick()
        assertTableEquals(db["2026-09-03"]["Guest-Realm"], { status = 3 })
    end)
end

tests["cancelling character deletion preserves attendance gear and the visible row"] = function()
    WithAttendanceFrames(function(prt, _, _, objects, db, _, popups)
        db["2026-09-03"]["Guest-Realm"] = { status = 3, itemLevel = 110, missingGems = { [2] = 1 } }
        prt.AttendanceUI:Refresh()
        local guestRow
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") and object.name.text == "Guest-Realm" then guestRow = object end
        end
        local original = CopyTable(db)
        guestRow.delete.scripts.OnClick()
        assertEquals(#popups, 1)
        assertTrue(popups[1].dialog.hideOnEscape)
        popups[1]:Cancel()

        assertTableEquals(db, original)
        assertTrue(guestRow:IsShown())
    end)
end

tests["a deletion confirmation retains its character when the grid reuses the row"] = function()
    WithAttendanceFrames(function(prt, _, _, objects, db, _, popups)
        db["2026-09-03"]["Guest-Realm"] = { status = 3 }
        prt.AttendanceUI:Refresh()
        local guestRow
        for _, object in ipairs(objects) do
            if rawget(object, "nameButton") and object.name.text == "Guest-Realm" then guestRow = object end
        end
        guestRow.delete.scripts.OnClick()
        db["2026-09-03"]["Earlier-Realm"] = { status = 2, itemLevel = 105 }
        prt.AttendanceUI:Refresh()
        assertEquals(guestRow.name.text, "Earlier-Realm")

        popups[1]:Accept()

        assertNil(db["2026-09-03"]["Guest-Realm"])
        assertTableEquals(db["2026-09-03"]["Earlier-Realm"], { status = 2, itemLevel = 105 })
    end)
end

return tests
