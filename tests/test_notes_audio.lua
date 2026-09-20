local tests = {}

local function MakeHarness(settings, rejectSharedMedia)
    local played = {}
    local sharedPath = "Interface\\AddOns\\SharedMedia\\alert.ogg"
    local prt = {
        defaults = {},
        RegisterModule = function() end,
        GetSetting = function() return settings end,
    }
    local media = {
        Fetch = function(_, _, name)
            if name == "Alert" then return sharedPath end
        end,
        List = function() return { "Alert" } end,
    }
    local env = setmetatable({
        PurplexityRaidTools = prt,
        LibStub = function() return media end,
        PlaySoundFile = function(path, channel)
            played[#played + 1] = { path = path, channel = channel }
            return not (rejectSharedMedia and path == sharedPath)
        end,
    }, { __index = _G })

    setfenv(assert(loadfile("Modules/Notes/Notes.lua")), env)()
    setfenv(assert(loadfile("Modules/Notes/NotesPopups.lua")), env)()
    return prt.NotesPopups, played, prt
end

tests["new profiles default reminder audio to Master"] = function()
    local _, _, prt = MakeHarness()
    assertEquals(prt.defaults.notes.popups.soundChannel, "Master")
end

tests["reminders previews and countdowns use every supported sound channel"] = function()
    for _, channel in ipairs({ "Master", "SFX", "Music", "Ambience", "Dialog" }) do
        local popups, played = MakeHarness({ popups = { soundChannel = channel } })

        assertTrue(popups:PreviewSound("Alert"))
        popups:PlayAudio({ sound = "Alert" })
        popups:AnnounceCountdown(3)

        assertEquals(#played, 3)
        assertEquals(played[1].path, "Interface\\AddOns\\SharedMedia\\alert.ogg")
        assertEquals(played[2].path, played[1].path)
        assertEquals(played[3].path, "Interface\\AddOns\\BigWigs\\Media\\Sounds\\Amy\\3.ogg")
        for _, sound in ipairs(played) do
            assertEquals(sound.channel, channel)
        end
    end
end

tests["missing settings and invalid channels retain Master playback"] = function()
    local cases = {
        false,
        {},
        { popups = {} },
        { popups = { soundChannel = "Unknown" } },
        { popups = { soundChannel = "" } },
        { popups = { soundChannel = 12 } },
    }
    for _, settings in ipairs(cases) do
        local popups, played = MakeHarness(settings or nil)
        popups:PlayAudio({ sound = "Alert" })
        popups:AnnounceCountdown(1)

        assertEquals(#played, 2)
        assertEquals(played[1].channel, "Master")
        assertEquals(played[2].channel, "Master")
    end
end

tests["direct sound paths and failed shared media use the selected channel"] = function()
    local popups, played = MakeHarness({ popups = { soundChannel = "Dialog" } }, true)
    local directPath = "Interface\\AddOns\\CustomSounds\\alarm.ogg"

    assertTrue(popups:PreviewSound(directPath))
    assertTrue(popups:PreviewSound("Alert"))

    assertEquals(#played, 3)
    assertEquals(played[1].path, directPath)
    assertEquals(played[2].path, "Interface\\AddOns\\SharedMedia\\alert.ogg")
    assertEquals(played[3].path, "Alert")
    for _, sound in ipairs(played) do
        assertEquals(sound.channel, "Dialog")
    end
end

tests["channel changes take effect on the next sound and countdown"] = function()
    local settings = { popups = { soundChannel = "Music" } }
    local popups, played = MakeHarness(settings)

    popups:PlayAudio({ sound = "Alert" })
    settings.popups = { soundChannel = "SFX" }
    popups:PlayAudio({ sound = "Alert" })
    popups:AnnounceCountdown(2)

    assertEquals(#played, 3)
    assertEquals(played[1].channel, "Music")
    assertEquals(played[2].channel, "SFX")
    assertEquals(played[3].channel, "SFX")
end

tests["selecting a channel preserves the reminder sounds toggle"] = function()
    local popups, played = MakeHarness({ popups = { soundChannel = "Dialog", soundsEnabled = false } })

    popups:PlayAudio({ sound = "Alert" })
    assertEquals(#played, 0)
    assertTrue(popups:PreviewSound("Alert"))
    assertEquals(#played, 1)
    assertEquals(played[1].channel, "Dialog")
end

return tests
