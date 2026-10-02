local tests = {}

local function withEditor(body)
    local objects, named = {}, {}
    local methods = {}
    local function object(kind, parent, name)
        local value = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, points = {} },
            { __index = methods })
        objects[#objects + 1] = value
        if name then named[name] = value end
        return value
    end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:HookScript(event, fn)
        local original = self.scripts[event]
        self.scripts[event] = function(...)
            if original then original(...) end
            fn(...)
        end
    end
    function methods:Show() self.shown = true end
    function methods:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:IsShown() return self.shown end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:SetText(value)
        self.text = value
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function methods:GetText() return self.text or "" end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:GetWidth() return self.width or 620 end
    function methods:GetHeight() return self.height or 825 end
    function methods:SetPoint(point, ...) self.points[point] = { point, ... } end
    function methods:ClearAllPoints() self.points = {} end
    function methods:GetTop() return 1000 end
    function methods:GetLeft() return 0 end
    function methods:GetEffectiveScale() return 1 end
    function methods:SetFrameLevel(level) self.level = level end
    function methods:GetFrameLevel() return self.level or 1 end
    function methods:GetVerticalScroll() return self.scroll or 0 end
    function methods:SetVerticalScroll(value)
        self.scroll = value
        if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self) end
    end
    function methods:SetBackdropBorderColor(...) self.border = { ... } end
    function methods:SetTextColor(...) self.color = { ... } end
    function methods:SetColorTexture(...) self.color = { ... } end
    function methods:CreateTexture() return object("Texture", self) end
    function methods:CreateFontString() return object("FontString", self) end
    function methods:StartMoving() self.moving = true end
    function methods:StopMovingOrSizing() self.moving = false end
    function methods:GetFont() return "font", 12 end
    function methods:IsMouseOver() return false end
    for _, name in ipairs({
        "SetAllPoints", "EnableMouse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetTexture",
        "SetJustifyH", "SetWordWrap", "SetBackdrop", "SetBackdropColor", "SetMovable", "SetResizable",
        "SetClampedToScreen", "RegisterForDrag", "SetUserPlaced", "SetTitle", "SetFrameStrata",
        "SetToplevel", "SetAutoFocus", "SetFocus", "ClearFocus", "HighlightText", "SetEnabled", "SetChecked",
        "SetNumeric", "SetClipsChildren", "SetScrollChild", "UpdateScrollChildRect", "RegisterEvent",
        "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetAlpha", "SetResizeBounds",
        "SetupMenu", "GenerateMenu", "Enable", "Disable", "SetFont", "SetMaxLetters",
        "SetNormalAtlas", "SetHighlightAtlas", "SetPushedAtlas",
    }) do
        methods[name] = function() end
    end

    local profile = { notes = { savedNotes = {}, annotations = {} } }
    local prt = {
        Profiles = { GetCurrent = function() return profile end },
        GetSetting = function() return profile.notes end,
        SpellData = { [105] = { class = "DRUID", abilities = {
            [100] = { name = "Tranquility", spellId = 100, cooldown = 180, charges = 1,
                talents = { [999] = { cooldown = -60 } } },
            [101] = { name = "Barkskin", spellId = 101, cooldown = 60, charges = 1 },
        } } },
        GroupInspect = { members = {
            PLAYER = { name = "Aster-Realm", specId = 105, class = "DRUID", talents = {} },
            OTHER = { name = "Ember-Realm", specId = 105, class = "DRUID", talents = {} },
        } },
    }
    local writes = 0
    prt.Notes = {
        GetAnnotation = function(_, name) return profile.notes.annotations[name] end,
        SaveNote = function(_, name, text) profile.notes.savedNotes[name] = text; writes = writes + 1 end,
        SaveAnnotation = function(_, name, text) profile.notes.annotations[name] = text; writes = writes + 1 end,
    }
    local cursorTime = 90
    local overrides = {
        PurplexityRaidTools = prt, UIParent = object("Frame"), UISpecialFrames = {},
        CreateFrame = function(kind, name, parent, template)
            local value = object(kind, parent, name)
            if template == "ButtonFrameTemplate" then value.Inset = object("Frame", value) end
            return value
        end,
        ButtonFrameTemplate_HidePortrait = function() end,
        ButtonFrameTemplate_HideButtonBar = function() end,
        UnitName = function() return "Aster" end,
        UnitGUID = function() return "PLAYER" end,
        UnitClass = function() return "Druid", "DRUID", 11 end,
        UnitGroupRolesAssigned = function() return "HEALER" end,
        IsInGroup = function() return true end, IsInRaid = function() return false end,
        Ambiguate = function(name) return name:match("^[^%-]+") end,
        C_SpecializationInfo = { GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return 105 end },
        C_Spell = { GetSpellTexture = function() return 123 end },
        GetCursorPosition = function() return 0, 1000 - (cursorTime * 8 + 20) end,
        RAID_CLASS_COLORS = {},
    }
    local saved = {}
    for key, value in pairs(overrides) do saved[key] = _G[key]; _G[key] = value end
    local ok, err = pcall(function()
        for _, module in ipairs({ "NotesParser", "NotesSerializer", "NotesMerge", "NotesTags",
            "NotesPlanner", "NotesCooldowns", "NotesEditor" }) do
            dofile("Modules/Notes/" .. module .. ".lua")
        end
        local function reminder(time)
            return { phase = 1, phaseKey = "1", time = time, tag = "Aster", text = "Tranquility",
                spellID = 100, duration = 5 }
        end
        local a, b = reminder(30), reminder(90)
        local note = { encounterID = 999, reminders = { ["1"] = { a, b } }, lines = {
            { type = "reminder", reminder = a }, { type = "reminder", reminder = b },
        } }
        profile.notes.savedNotes.Test = prt.NotesSerializer:Serialize(note)
        prt.NotesEditor:Open("Test", profile.notes.savedNotes.Test, "edit")
        local ui = { prt = prt, objects = objects, named = named, profile = profile }
        function ui:block(time)
            for _, value in ipairs(objects) do
                if value.shown and value.reminder and value.reminder.time == time then return value end
            end
            error("No block at " .. time)
        end
        function ui:field(labelText)
            for _, label in ipairs(objects) do
                if label.text == labelText and label.shown then
                    local labelPoint = label.points.TOPLEFT
                    for _, value in ipairs(objects) do
                        local point = value.points.TOPLEFT
                        if value.parent == label.parent and point and point[2] == 4
                            and point[3] == labelPoint[3] - 14 and value.kind ~= "FontString" then
                            return value
                        end
                    end
                end
            end
            error("No field " .. labelText)
        end
        function ui:status()
            local ability = self:field("ABILITY")
            for _, value in ipairs(objects) do
                local point = value.points.TOPLEFT
                if value.kind == "FontString" and point and point[2] == ability then return value end
            end
            error("No ability status")
        end
        function ui:dash()
            for _, value in ipairs(objects) do
                if value.shown and value.kind == "Texture" and value.color
                    and value.color[1] == 0.3 and value.color[2] == 0.9 then return value end
            end
        end
        function ui:drag(time) cursorTime = time end
        function ui:writes() return writes end
        body(ui, prt.NotesEditor)
    end)
    for key in pairs(overrides) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

tests["Editor keeps status space and selection on Cancel without changing the saved note"] = function()
    withEditor(function(ui, editor)
        local block = ui:block(90)
        block.scripts.OnClick(block)
        assertTrue(ui:status().text:find("Not ready until 3:30.", 1, true) ~= nil)
        local field = ui:field("DISPLAY TEXT (OPTIONAL)")
        local fieldY = field.points.TOPLEFT[3]
        local markerY = ui:dash().points.TOPLEFT[5]
        ui:field("TIME (PHASE-RELATIVE)"):SetText("3:30")
        assertEquals(ui:status().text, "Ready")
        assertEquals(ui:status().color[1], 0.5)
        assertEquals(field.points.TOPLEFT[3], fieldY)
        ui.named.PRT_NotesEditPanel:Hide()
        assertEquals(ui:dash().points.TOPLEFT[5], markerY)
        local canvas = ui:dash().parent.parent.parent
        assertTrue(canvas.height > -markerY)
        canvas.parent:SetVerticalScroll(600)
        assertEquals(ui:dash().points.TOPLEFT[5], markerY)
        assertEquals(ui:block(90).reminder.time, 90)
        assertEquals(ui:writes(), 0)
        editor:OpenEditPanel(ui:block(30).reminder)
        assertEquals(ui:status().text, "Ready")
        assertEquals(ui:dash().points.TOPLEFT[5], -(210 * 8 + 20))
    end)
end

tests["Editor saves a valid draft then keeps its new recovery guide after reload"] = function()
    withEditor(function(ui, editor)
        editor:OpenEditPanel(ui:block(90).reminder)
        ui:field("TIME (PHASE-RELATIVE)"):SetText("3:30")
        editor:SaveFromPanel()
        assertEquals(ui:writes(), 1)
        assertTrue(ui:block(210).cooldownStatus.ready)
        assertEquals(ui:dash().points.TOPLEFT[5], -(390 * 8 + 20))
        editor:ReloadNote()
        editor:Render()
        assertEquals(ui:dash().points.TOPLEFT[5], -(390 * 8 + 20))
        editor:OpenEditPanel(ui:block(210).reminder)
        editor:DeleteFromPanel()
        assertNil(ui:dash())
    end)
end

tests["Dragging a conflict keeps its guide visible through the boundary until the drop"] = function()
    withEditor(function(ui)
        local block = ui:block(90)
        block.scripts.OnDragStart(block)
        assertTrue(block.moving)
        for _, time in ipairs({ 209, 210, 215 }) do
            ui:drag(time)
            block.scripts.OnUpdate(block, 0.1)
            assertEquals(ui:dash().points.TOPLEFT[5], -(210 * 8 + 20))
            assertTrue(ui:dash().parent.level > block.level)
            assertEquals(block.cooldownStatus.ready, time >= 210)
            assertEquals(block.cooldownWarning.shown, time < 210)
            assertEquals(block.reminder.time, 90)
            assertEquals(ui:writes(), 0)
        end
        block.scripts.OnDragStop(block)
        assertEquals(ui:writes(), 1)
        assertFalse(block.moving)
        assertNil(block.scripts.OnUpdate)
        assertEquals(ui:block(215).reminder.time, 215)
        assertEquals(ui:dash().points.TOPLEFT[5], -(395 * 8 + 20))
    end)
end

tests["Ability and player changes recompute warnings without putting status in the picker"] = function()
    withEditor(function(ui, editor)
        editor:OpenEditPanel(ui:block(90).reminder)
        local ability = ui:field("ABILITY")
        for _, item in ipairs(ability.getItems()) do
            assertNil(item.name:find("Ready", 1, true))
            assertNil(item.name:find("Not ready", 1, true))
        end
        ability.onSelect("Barkskin")
        assertEquals(ui:status().text, "Ready")
        ability.onSelect("Tranquility")
        assertTrue(ui:status().text:find("Not ready", 1, true) ~= nil)
        ui:field("WHO"):SetText("Ember")
        assertEquals(ui:status().text, "Ready")
        ui:field("WHO"):SetText("healers")
        assertEquals(ui:status().text, "")
        assertEquals(ui:writes(), 0)
    end)
end

tests["Resolver applies inspected talents and joins short and full player names"] = function()
    withEditor(function(ui, editor)
        ui.prt.GroupInspect.members.PLAYER.talents[999] = true
        local short = editor.ResolveCooldown({ tag = "Aster", spellID = 100 })
        local full = editor.ResolveCooldown({ tag = "Aster-Realm", spellID = 100 })
        assertEquals(short.caster, full.caster)
        assertEquals(short.cooldown, 120)
        assertEquals(full.cooldown, 120)
        assertNil(editor.ResolveCooldown({ tag = "Unknown", spellID = 100 }))
        assertNil(editor.ResolveCooldown({ tag = "druid", spellID = 100 }))
        assertNil(editor.ResolveCooldown({ tag = "Aster", spellID = 9999 }))
    end)
end

tests["Cooldown warnings remain advisory when saving an assignment"] = function()
    withEditor(function(ui, editor)
        editor:OpenEditPanel(ui:block(90).reminder)
        editor:SaveFromPanel()
        assertEquals(ui:writes(), 1)
        assertFalse(ui:block(90).cooldownStatus.ready)
        assertTrue(ui:block(90).cooldownWarning.shown)
    end)
end

tests["Beginning a drag preserves earlier phase spacing from the previous selection"] = function()
    withEditor(function(ui, editor)
        local text = ui.profile.notes.savedNotes.Test
            .. "\ntime:10;tag:Ember;spellid:100;text:Tranquility;ph:2;dur:5"
        editor:Open("Test", text, "edit")
        editor:OpenEditPanel(ui:block(30).reminder)
        local block = ui:block(10)
        local beforeY = block.points.TOPLEFT[5]
        block.scripts.OnDragStart(block)
        assertEquals(block.points.TOPLEFT[5], beforeY)
        editor:Close()
        assertFalse(block.moving)
        assertNil(block.scripts.OnUpdate)
    end)
end

tests["Personal reminder edits retain their selection after annotation merge"] = function()
    withEditor(function(ui, editor)
        ui.profile.notes.annotations.Test = "EncounterID:999\ntime:60;tag:Aster;spellid:100;text:Tranquility;ph:1;dur:5"
        editor:Open("Test", ui.profile.notes.savedNotes.Test, "annotate")
        assertTrue(ui:block(60).reminder.isPersonal)
        editor:OpenEditPanel(ui:block(60).reminder)
        ui:field("TIME (PHASE-RELATIVE)"):SetText("3:30")
        editor:SaveFromPanel()
        assertTrue(ui:block(210).reminder.isPersonal)
        assertEquals(ui:dash().points.TOPLEFT[5], -(390 * 8 + 20))
    end)
end

return tests
