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
    function methods:GetStringHeight()
        local _, lines = self:GetText():gsub("\n", "")
        return (lines + 1) * 12
    end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:IsMouseOver() return false end
    for _, name in ipairs({
        "SetAllPoints", "EnableMouse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetTexture",
        "SetJustifyH", "SetWordWrap", "SetBackdrop", "SetBackdropColor", "SetMovable", "SetResizable",
        "SetClampedToScreen", "RegisterForDrag", "SetUserPlaced", "SetTitle", "SetFrameStrata",
        "SetToplevel", "SetAutoFocus", "SetFocus", "ClearFocus", "HighlightText", "SetEnabled", "SetChecked",
        "SetNumeric", "SetClipsChildren", "UpdateScrollChildRect", "RegisterEvent",
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
            value.template = template
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
        function ui:findField(labelText)
            for _, label in ipairs(objects) do
                if label.text == labelText and label.shown then
                    local labelPoint = label.points.TOPLEFT
                    for _, value in ipairs(objects) do
                        local point = value.points.TOPLEFT
                        if value.parent == label.parent and point and point[2] == labelPoint[2]
                            and point[3] == labelPoint[3] - 14 and value.kind ~= "FontString" then
                            return value
                        end
                    end
                end
            end
        end
        function ui:field(labelText)
            return self:findField(labelText) or error("No field " .. labelText)
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
        ui:field("TIME IN PHASE"):SetText("3:30")
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
        ui:field("TIME IN PHASE"):SetText("3:30")
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
        ui:field("TIME IN PHASE"):SetText("3:30")
        editor:SaveFromPanel()
        assertTrue(ui:block(210).reminder.isPersonal)
        assertEquals(ui:dash().points.TOPLEFT[5], -(390 * 8 + 20))
    end)
end

tests["Assignment editor groups timing and retains the native controls"] = function()
    withEditor(function(ui, editor)
        editor:OpenEditPanel(ui:block(90).reminder)
        local panel = ui.named.PRT_NotesEditPanel
        local phase = ui:field("PHASE")
        local time = ui:field("TIME IN PHASE")
        local duration = ui:field("DURATION (SEC)")
        assertEquals(phase.points.TOPLEFT[3], time.points.TOPLEFT[3])
        assertEquals(time.points.TOPLEFT[3], duration.points.TOPLEFT[3])
        assertTrue(phase.points.TOPLEFT[2] + phase.width < time.points.TOPLEFT[2])
        assertTrue(time.points.TOPLEFT[2] + time.width < duration.points.TOPLEFT[2])
        assertEquals(panel.template, "ButtonFrameTemplate")
        assertEquals(time.template, "InputBoxTemplate")
        assertEquals(ui:field("ABILITY").template, "WowStyle1DropdownTemplate")
        assertEquals(panel.saveBtn.template, "UIPanelButtonTemplate")
        assertTrue(panel.height < 500)
        assertNil(ui:findField("BOSS SPELL ID"))
        assertNil(ui:findField("SOUND"))
    end)
end

tests["More options preserve hidden values and reset for a new assignment"] = function()
    withEditor(function(ui, editor)
        local reminder = ui:block(90).reminder
        reminder.bossSpell = 12345
        reminder.colors = "1 0.5 0 1"
        editor:OpenEditPanel(reminder)
        local panel = ui.named.PRT_NotesEditPanel
        assertTrue(panel.moreOptionsExpanded)
        assertEquals(ui:field("BOSS SPELL ID"):GetText(), "12345")
        panel.moreOptionsBtn.scripts.OnClick()
        assertNil(ui:findField("BOSS SPELL ID"))
        editor:SaveFromPanel()
        local saved = ui.prt.NotesParser:Parse(ui.profile.notes.savedNotes.Test)
        assertEquals(saved.reminders["1"][2].bossSpell, 12345)
        assertEquals(saved.reminders["1"][2].colors, "1 0.5 0 1")
        editor:OpenAddPanel(120, 1)
        assertFalse(panel.moreOptionsExpanded)
        panel.moreOptionsBtn.scripts.OnClick()
        assertEquals(ui:field("BOSS SPELL ID"):GetText(), "")
        assertEquals(ui:field("COLORS (RGBA)"):GetText(), "")
    end)
end

tests["Annotation controls only save alert overrides and Cancel discards drafts"] = function()
    withEditor(function(ui, editor)
        local original = ui.profile.notes.savedNotes.Test
        editor:Open("Test", original, "annotate")
        editor:OpenEditPanel(ui:block(90).reminder)
        local panel = ui.named.PRT_NotesEditPanel
        for _, label in ipairs({ "WHO", "ABILITY", "PHASE", "TIME IN PHASE", "DURATION (SEC)", "BOSS SPELL ID" }) do
            assertNil(ui:findField(label), label)
        end
        assertFalse(panel.deleteBtn.shown)
        assertFalse(panel.moreOptionsBtn.shown)
        assertTrue(panel.originalInfo.shown)
        assertTrue(panel.originalInfo:GetText():find("Phase 1", 1, true) ~= nil)
        ui:field("SOUND"):SetValue("Bell")
        panel:Hide()
        assertEquals(ui:writes(), 0)
        editor:OpenEditPanel(ui:block(90).reminder)
        assertNil(ui:field("SOUND"):GetValue())
        ui:field("SOUND"):SetValue("Bell")
        ui:field("COUNTDOWN"):SetValue("3")
        editor:SaveAnnotationFromPanel()
        assertEquals(ui.profile.notes.savedNotes.Test, original)
        local saved = ui.prt.NotesParser:Parse(ui.profile.notes.annotations.Test)
        assertEquals(saved.reminders["1"][1].sound, "Bell")
        assertEquals(saved.reminders["1"][1].countdown, 3)
        assertEquals(saved.reminders["1"][1].time, 90)
    end)
end

tests["Personal form shares alert controls and keeps all reminder fields on save"] = function()
    withEditor(function(ui, editor)
        editor:Open("Test", ui.profile.notes.savedNotes.Test, "annotate")
        editor:OpenAddPanel(120, 1)
        local panel = ui.named.PRT_NotesEditPanel
        assertNil(ui:findField("WHO"))
        ui:field("DISPLAY TEXT (OPTIONAL)"):SetText("Move now")
        ui:field("DURATION (SEC)"):SetText("7")
        local speech = ui:field("TEXT TO SPEECH")
        local compactHeight = panel.height
        speech:SetValue("custom")
        speech.onSelect("custom")
        assertTrue(panel.height > compactHeight)
        ui:field("SPOKEN TEXT"):SetText("Use a defensive")
        ui:field("SOUND"):SetValue("Bell")
        ui:field("COUNTDOWN"):SetValue("3")
        ui:field("AUDIO LEAD (SEC)"):SetText("2")
        panel.moreOptionsBtn.scripts.OnClick()
        ui:field("BOSS SPELL ID"):SetText("12345")
        ui:field("COLORS (RGBA)"):SetText("1 0.5 0 1")
        editor:SaveFromPanel()
        local saved = ui.prt.NotesParser:Parse(ui.profile.notes.annotations.Test)
        local reminder = saved.reminders["1"][1]
        assertEquals(reminder.duration, 7)
        assertEquals(reminder.tts, "Use a defensive")
        assertEquals(reminder.sound, "Bell")
        assertEquals(reminder.countdown, 3)
        assertEquals(reminder.ttsTimer, 2)
        assertEquals(reminder.bossSpell, 12345)
        assertEquals(reminder.colors, "1 0.5 0 1")
    end)
end

tests["Editor bounds long forms to the screen and clears scroll when switching forms"] = function()
    withEditor(function(ui, editor)
        UIParent:SetHeight(460)
        editor:Open("Test", ui.profile.notes.savedNotes.Test, "annotate")
        editor:OpenAddPanel(120, 1)
        local panel = ui.named.PRT_NotesEditPanel
        local speech = ui:field("TEXT TO SPEECH")
        speech:SetValue("custom")
        speech.onSelect("custom")
        panel.moreOptionsBtn.scripts.OnClick()
        assertTrue(panel.height <= UIParent:GetHeight() - 40)
        assertTrue(panel.scrollFrame.scrollChild.height > panel.height)
        panel.scrollFrame:SetVerticalScroll(120)
        editor:OpenEditPanel(ui:block(90).reminder)
        assertEquals(panel.scrollFrame:GetVerticalScroll(), 0)
        assertNil(ui:findField("SPOKEN TEXT"))
        assertFalse(panel.moreOptionsBtn.shown)
    end)
end

return tests
