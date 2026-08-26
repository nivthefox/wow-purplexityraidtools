local PRT = PurplexityRaidTools

dofile("Modules/Notes/NotesPopups.lua")

local Popups = PRT.NotesPopups
local tests = {}

tests["legacy disabled master toggle migrates every popup type to disabled"] = function()
    local settings = {
        enabled = false,
        enabledTypes = {
            Icon = true,
            Bar = true,
            Text = true,
            Circle = true,
        },
    }

    Popups:MigrateSettings(settings)

    assertNil(settings.enabled)
    assertTrue(settings.typeEnablementMigrated)
    assertFalse(settings.enabledTypes.Icon)
    assertFalse(settings.enabledTypes.Bar)
    assertFalse(settings.enabledTypes.Text)
    assertFalse(settings.enabledTypes.Circle)
end

tests["legacy enabled master toggle migrates every popup type to enabled"] = function()
    local settings = { enabled = true }

    Popups:MigrateSettings(settings)

    assertTrue(settings.enabledTypes.Icon)
    assertTrue(settings.enabledTypes.Bar)
    assertTrue(settings.enabledTypes.Text)
    assertTrue(settings.enabledTypes.Circle)
end

tests["completed migration preserves independent popup choices"] = function()
    local settings = {
        typeEnablementMigrated = true,
        enabledTypes = {
            Icon = false,
            Bar = true,
            Text = false,
            Circle = true,
        },
    }

    Popups:MigrateSettings(settings)

    assertFalse(Popups:IsTypeEnabled("Icon", settings))
    assertTrue(Popups:IsTypeEnabled("Bar", settings))
    assertFalse(Popups:IsTypeEnabled("Text", settings))
    assertTrue(Popups:IsTypeEnabled("Circle", settings))
end

tests["bar style uses saved dimensions and shared media texture"] = function()
    local style = Popups:GetBarStyle({
        barWidth = 480,
        barHeight = 36,
        barTexture = "Smooth",
    }, function(name)
        if name == "Smooth" then
            return "Interface\\AddOns\\SharedMedia\\smooth.tga"
        end
    end)

    assertTableEquals(style, {
        width = 480,
        height = 36,
        texture = "Smooth",
        texturePath = "Interface\\AddOns\\SharedMedia\\smooth.tga",
    })
end

tests["bar style clamps corrupt dimensions and falls back to Blizzard"] = function()
    local style = Popups:GetBarStyle({
        barWidth = 5000,
        barHeight = -5,
        barTexture = "Missing",
    }, function()
        return nil
    end)

    assertEquals(style.width, 1000)
    assertEquals(style.height, 10)
    assertEquals(style.texture, "Missing")
    assertEquals(style.texturePath, "Interface\\TargetingFrame\\UI-StatusBar")
end

tests["bar style retains the existing appearance by default"] = function()
    local style = Popups:GetBarStyle({}, function(name)
        assertEquals(name, "Blizzard")
        return nil
    end)

    assertEquals(style.width, 220)
    assertEquals(style.height, 24)
    assertEquals(style.texture, "Blizzard")
end

tests["test popup timers expire each distinct sample"] = function()
    local shown = {}
    local expired = {}
    local scheduled = {}
    local samples = {
        { duration = 8, text = "Icon" },
        { duration = 8, text = "Bar" },
        { duration = 8, text = "Text" },
        { duration = 8, text = "Circle" },
    }
    local harness = {
        Show = function(_, reminder, duration)
            shown[#shown + 1] = { reminder = reminder, duration = duration }
        end,
        Expire = function(_, reminder)
            expired[#expired + 1] = reminder
        end,
    }
    setmetatable(harness, { __index = Popups })

    harness:ShowTestSamples(samples, function(delay, callback)
        scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end)

    assertEquals(#shown, 4)
    assertEquals(#scheduled, 4)
    for index, timer in ipairs(scheduled) do
        assertEquals(timer.delay, 8)
        timer.callback()
        assertEquals(shown[index].reminder, samples[index])
        assertEquals(shown[index].duration, 8)
        assertEquals(expired[index], samples[index])
    end
end

return tests
