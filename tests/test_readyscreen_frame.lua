local tests = {}

local function withFrame(body)
    local objects = {}
    local function newObject()
        local object = { shown = true, scripts = {} }
        function object:SetText(text) self.text = text end
        function object:SetTextColor(...) self.color = { ... } end
        function object:SetWidth(width) self.width = width end
        function object:SetScript(event, callback) self.scripts[event] = callback end
        function object:Show() self.shown = true end
        function object:Hide() self.shown = false end
        function object:IsShown() return self.shown end
        function object:CreateTexture() return newObject() end
        function object:CreateFontString() return newObject() end
        setmetatable(object, { __index = function() return function() end end })
        objects[#objects + 1] = object
        return object
    end
    local complete = { status = "complete", missing = {}, unknown = {} }
    local missing = { status = "missing", missing = { { slot = 11, count = 2 } }, unknown = {} }
    local members = {
        A = { name = "Alice", class = "WARRIOR", itemLevel = 100,
            gearAudit = { enchants = complete, gems = missing } },
        B = { name = "Bob", class = "WARRIOR" },
    }
    local tooltip = { lines = {} }
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Show() end
    function tooltip:Hide() self.owner = nil end
    function tooltip:IsOwned(owner) return self.owner == owner end
    local prt = {
        Components = {
            GetTab = function(_, label)
                local tab = newObject()
                tab:SetText(label)
                return tab
            end,
        },
        GearAudit = PurplexityRaidTools.GearAudit,
        GroupInspect = { members = members },
        IterateGroup = function() return function() end end,
        GetSetting = function() return {} end,
        RAID_BUFFS = {}, SOULSTONE_BUFF_NAME = "Soulstone", SOULSTONE_SPELL_ID = 1,
        ReadyScreen = {
            GetPreviewRoster = function() return nil end,
            GetMode = function() return "gear" end,
            GetResponses = function() return {} end,
            GetPersonalBuffColumns = function() return {} end,
            SortRoster = function(roster) table.sort(roster, function(a, b) return a.name < b.name end) end,
            FormatItemLevel = function(level) return level and tostring(level) or "?" end,
            IsItemLevelAvailable = function(level) return level ~= nil end,
        },
    }
    local overrides = {
        PurplexityRaidTools = prt,
        CreateFrame = function() return newObject() end,
        PanelTemplates_SelectTab = function(tab) tab.selected = true end,
        PanelTemplates_DeselectTab = function(tab) tab.selected = false end,
        PanelTemplates_TabResize = function() end,
        UIParent = {}, GameTooltip = tooltip, RAID_CLASS_COLORS = {},
        Ambiguate = function(name) return name end,
        GetNormalizedRealmName = function() return "Realm" end,
    }
    local saved = {}
    for key, value in pairs(overrides) do saved[key] = _G[key]; _G[key] = value end
    local ok, err = pcall(function()
        dofile("Modules/ReadyScreenFrame.lua")
        prt.ReadyScreenFrame:Show("gear")
        local rows, header = {}, nil
        for _, object in ipairs(objects) do
            if rawget(object, "nameText") then rows[#rows + 1] = object end
            if rawget(object, "nameLabel") then header = object end
        end
        body(prt.ReadyScreenFrame, rows, header, members, tooltip, complete)
    end)
    for key in pairs(overrides) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

tests["Gear renders cached and unknown statuses and exposes missing slots on hover"] = function()
    withFrame(function(_, rows, header, _, tooltip)
        assertEquals(header.buffLabels[1].text, "Enchants")
        assertEquals(header.buffLabels[2].text, "Gems")
        assertEquals(rows[1].buffTexts[1].text, "Complete")
        assertEquals(rows[1].buffTexts[2].text, "Missing")
        assertEquals(rows[2].buffTexts[1].text, "Unknown")
        assertEquals(rows[2].buffTexts[2].text, "Unknown")
        rows[1].scripts.OnEnter(rows[1])
        assertEquals(tooltip.lines[4], "Missing: Ring 1 (2).")
    end)
end

tests["Gear refresh replaces displayed results and Readiness hides audit labels"] = function()
    withFrame(function(frame, rows, header, members, _, complete)
        members.A.gearAudit.gems = complete
        frame:Refresh()
        assertEquals(rows[1].buffTexts[2].text, "Complete")
        frame:Show("readiness")
        assertFalse(header.buffLabels[1].shown)
        assertFalse(header.buffLabels[2].shown)
        assertFalse(rows[1].buffTexts[1].shown)
        assertFalse(rows[1].buffTexts[2].shown)
    end)
end

return tests
