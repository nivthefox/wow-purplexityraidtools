local tests = {}

local function WithConfigFrame(body)
    local objects = {}
    local function Object(parent)
        local object = { parent = parent, scripts = {}, events = {}, shown = true }
        objects[#objects + 1] = object
        function object:SetSize(width, height) self.width, self.height = width, height end
        function object:GetWidth() return self.width end
        function object:GetHeight() return self.height end
        function object:SetPoint(point, relative, relativePoint, x, y)
            if point == "CENTER" and type(relative) == "table" then
                self.left = (relative:GetWidth() - self:GetWidth()) / 2 + x
                self.top = (relative:GetHeight() + self:GetHeight()) / 2 + y
            elseif point == "TOPLEFT" and relativePoint == "BOTTOMLEFT" then
                self.left, self.top = x, y
            end
        end
        function object:GetLeft() return self.left end
        function object:GetTop() return self.top end
        function object.GetFrameLevel() return 1 end
        function object:SetScript(event, callback) self.scripts[event] = callback end
        function object:HookScript(event, callback)
            local previous = self.scripts[event]
            self.scripts[event] = function(...)
                if previous then previous(...) end
                callback(...)
            end
        end
        function object:RegisterEvent(event) self.events[event] = true end
        function object:SetResizeBounds(...) self.bounds = { ... } end
        function object:SetResizable(value) self.resizable = value end
        function object:StartSizing(point) self.sizing = point end
        function object:StopMovingOrSizing() self.sizing = nil end
        function object:SetUserPlaced(value) self.userPlaced = value end
        function object:Show()
            self.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function object:Hide()
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function object:CreateTexture() return Object(self) end
        function object:CreateFontString() return Object(self) end
        setmetatable(object, { __index = function() return function() end end })
        return object
    end

    local uiParent = Object()
    uiParent:SetSize(1920, 1080)
    local frame
    local overrides = {
        PurplexityRaidTools = {}, UIParent = uiParent, UISpecialFrames = {},
        C_AddOns = { GetAddOnMetadata = function() return "test" end },
        ButtonFrameTemplate_HidePortrait = function() end,
        ButtonFrameTemplate_HideButtonBar = function() end,
        CreateFrame = function(_, name, parent, template)
            local object = Object(parent)
            if template == "ButtonFrameTemplate" then object.Inset = Object(object) end
            if name == "PurplexityRaidToolsConfigFrame" then frame = object end
            return object
        end,
    }
    local saved = {}
    for key, value in pairs(overrides) do saved[key] = _G[key]; _G[key] = value end
    local ok, err = pcall(function()
        dofile("ConfigFrame.lua")
        frame:Show()
        local handle
        for _, object in ipairs(objects) do
            if object.parent == frame and object.scripts.OnMouseDown then handle = object end
        end
        body(frame, handle, uiParent)
    end)
    for key in pairs(overrides) do _G[key] = saved[key] end
    if not ok then error(err, 0) end
end

local function AssertFitsViewport(frame, viewport)
    assertTrue(frame:GetLeft() >= 0)
    assertTrue(frame:GetTop() <= viewport:GetHeight())
    assertTrue(frame:GetLeft() + frame:GetWidth() <= viewport:GetWidth())
    assertTrue(frame:GetTop() - frame:GetHeight() >= 0)
    assertTrue(frame:GetLeft() + frame.bounds[3] <= viewport:GetWidth())
    assertTrue(frame:GetTop() - frame.bounds[4] >= 0)
end

tests["config resize bounds preserve the default minimum and stop at the viewport edges"] = function()
    WithConfigFrame(function(frame, handle, viewport)
        handle.scripts.OnMouseDown(handle, "LeftButton")
        assertTrue(frame.resizable)
        assertEquals(frame.sizing, "BOTTOMRIGHT")
        assertEquals(frame.bounds[1], 880)
        assertEquals(frame.bounds[2], 725)
        AssertFitsViewport(frame, viewport)
        frame:SetSize(frame.bounds[3], frame.bounds[4])
        handle.scripts.OnMouseUp(handle, "LeftButton")
        assertNil(rawget(frame, "sizing"))
        assertFalse(frame.userPlaced)
        AssertFitsViewport(frame, viewport)
    end)
end

tests["moving the config window changes the available resize space"] = function()
    WithConfigFrame(function(frame, handle, viewport)
        frame.left, frame.top = 900, 800
        frame.scripts.OnDragStop(frame)
        handle.scripts.OnMouseDown(handle, "LeftButton")
        assertEquals(frame.bounds[3], 1020)
        assertEquals(frame.bounds[4], 800)
        AssertFitsViewport(frame, viewport)
    end)
end

tests["display and UI scale changes shrink and reposition an oversized config window"] = function()
    WithConfigFrame(function(frame, _, viewport)
        for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
            assertTrue(frame.events[event])
            frame:SetSize(1600, 1000)
            frame.left, frame.top = 300, 1050
            viewport:SetSize(1280, 800)
            frame.scripts.OnEvent(frame, event)
            assertEquals(frame:GetWidth(), 1280)
            assertEquals(frame:GetHeight(), 800)
            assertEquals(frame.bounds[1], 880)
            assertEquals(frame.bounds[2], 725)
            AssertFitsViewport(frame, viewport)
        end
    end)
end

tests["a viewport smaller than the default still contains the entire config window"] = function()
    WithConfigFrame(function(frame, _, viewport)
        viewport:SetSize(800, 600)
        frame.scripts.OnEvent(frame, "UI_SCALE_CHANGED")
        assertEquals(frame:GetWidth(), 800)
        assertEquals(frame:GetHeight(), 600)
        assertEquals(frame.bounds[1], 800)
        assertEquals(frame.bounds[2], 600)
        AssertFitsViewport(frame, viewport)
    end)
end

tests["closing the config window stops an active resize"] = function()
    WithConfigFrame(function(frame, handle)
        handle.scripts.OnMouseDown(handle, "RightButton")
        assertNil(rawget(frame, "sizing"))
        handle.scripts.OnMouseDown(handle, "LeftButton")
        frame:Hide()
        assertNil(rawget(frame, "sizing"))
        assertFalse(frame.userPlaced)
    end)
end

return tests
