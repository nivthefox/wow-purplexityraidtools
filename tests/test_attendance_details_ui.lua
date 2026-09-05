local tests = {}

if not PurplexityRaidTools.AttendanceStore then dofile("Modules/Attendance/AttendanceStore.lua") end
if not PurplexityRaidTools.AttendanceReport then dofile("Modules/Attendance/AttendanceReport.lua") end
if not PurplexityRaidTools.GearAudit then dofile("Modules/GearAudit.lua") end

local function WithAttendanceFrames(body)
    local objects, tabSetup, grid = {}, nil, nil
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
        UIParent = Object(), UISpecialFrames = {}, RAID_CLASS_COLORS = {},
        Ambiguate = function(name) return name:match("^[^-]+") end,
        strcmputf8i = function(a, b) return a < b and -1 or a > b and 1 or 0 end,
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
        body(prt, row, detail, objects, db, roster)
    end)
    for key in pairs(overrides) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

tests["names navigate to character history while attendance cells still edit the original records"] = function()
    WithAttendanceFrames(function(prt, row, detail, objects, db)
        assertEquals(row.itemLevel.text, "110.0")
        row.nameButton.scripts.OnClick()
        assertTrue(detail:IsShown())
        assertFalse(row:IsVisible())
        assertEquals(detail.character, "Aster-Realm")
        assertEquals(detail.history.change, 10)
        assertFalse(detail.columns[2].marker:IsShown())
        assertFalse(detail.columns[3].line:IsShown(), "the graph must not connect across an unmeasured day")
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

return tests
