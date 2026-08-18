local tests = {}

local PRT = PurplexityRaidTools

local featureLoaded, featureLoadError = pcall(function()
    if not PRT.RosterValidation then
        dofile("Modules/Attendance/RosterValidation.lua")
    end
    if not PRT.Roster then
        dofile("Modules/Attendance/Roster.lua")
    end
    dofile("Modules/RosterNicknames/RosterNicknames.lua")
    dofile("Modules/RosterNicknames/Blizzard.lua")
    dofile("Modules/RosterNicknames/NivUI.lua")
    dofile("Modules/RosterNicknames/ElvUI.lua")
end)

local function requireFeature()
    assertTrue(featureLoaded, tostring(featureLoadError))
end

local function withGlobals(overrides, body)
    local saved = {}
    for key, value in pairs(overrides) do
        saved[key] = rawget(_G, key)
        _G[key] = value
    end

    local ok, err = pcall(body)
    for key in pairs(overrides) do
        _G[key] = saved[key]
    end
    if not ok then
        error(err, 0)
    end
end

local function rosterEntry(nickname, ...)
    local characters = { ... }
    local characterData = {}
    for _, character in ipairs(characters) do
        characterData[character] = {}
    end
    return { nickname = nickname, characters = characters, characterData = characterData }
end

local function withEnabledFeature(body)
    local savedGetSetting = PRT.GetSetting
    PRT.GetSetting = function(_, key)
        if key == "rosterNicknames" then
            return { enabled = true }
        end
        return PRT.defaults[key]
    end
    local ok, err = pcall(body)
    PRT.GetSetting = savedGetSetting
    if not ok then
        error(err, 0)
    end
end

tests["roster nickname feature modules load without provider addons"] = function()
    requireFeature()
    assertNotNil(PRT.RosterNicknames)
    assertNotNil(PRT.RosterNicknameAdapters.Blizzard)
    assertNotNil(PRT.RosterNicknameAdapters.NivUI)
    assertNotNil(PRT.RosterNicknameAdapters.ElvUI)
end

tests["a new profile defaults roster nicknames to disabled"] = function()
    requireFeature()
    assertFalse(PRT.defaults.rosterNicknames.enabled)
end

tests["unit lookup completes a missing same-realm name"] = function()
    requireFeature()
    PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }

    withGlobals({
        UnitIsPlayer = function() return true end,
        UnitFullName = function() return "Aster", nil end,
        GetNormalizedRealmName = function() return "MoonGuard" end,
        issecretvalue = function() return false end,
    }, function()
        withEnabledFeature(function()
            assertEquals(PRT.RosterNicknames:ResolveUnit("party1"), "Starcaller")
        end)
    end)
end

tests["unit lookup refuses non-player and secret identities"] = function()
    requireFeature()
    PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }
    local secret = {}

    withGlobals({
        UnitIsPlayer = function(unit) return unit ~= "pet" end,
        UnitFullName = function(unit)
            if unit == "secret" then
                return secret, "MoonGuard"
            end
            return "Aster", "MoonGuard"
        end,
        GetNormalizedRealmName = function() return "MoonGuard" end,
        issecretvalue = function(value) return value == secret end,
    }, function()
        assertNil(PRT.RosterNicknames:ResolveUnit("pet"))
        assertNil(PRT.RosterNicknames:ResolveUnit("secret"))
    end)
end

tests["setting changes are rejected during combat without changing the profile"] = function()
    requireFeature()
    local profile = { rosterNicknames = { enabled = false } }
    local savedProfile = PRT.Profiles.current
    PRT.Profiles.current = profile

    withGlobals({ InCombatLockdown = function() return true end }, function()
        local ok, err = PRT.RosterNicknames:SetEnabled(true)
        assertFalse(ok)
        assertEquals(type(err), "string")
        assertFalse(profile.rosterNicknames.enabled)
    end)

    PRT.Profiles.current = savedProfile
end

tests["live nickname lookup remains available during combat"] = function()
    requireFeature()
    PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }

    withEnabledFeature(function()
        withGlobals({ InCombatLockdown = function() return true end }, function()
            assertEquals(PRT.RosterNicknames:ResolveIdentity("Aster-MoonGuard"), "Starcaller")
        end)
    end)
end

tests["setting changes refresh every loaded provider"] = function()
    requireFeature()
    local savedProfile = PRT.Profiles.current
    local profile = { rosterNicknames = { enabled = false } }
    local first, second = 0, 0
    PRT.Profiles.current = profile
    PRT.RosterNicknameAdapters.TestRefreshOne = {
        Refresh = function() first = first + 1 end,
    }
    PRT.RosterNicknameAdapters.TestRefreshTwo = {
        Refresh = function() second = second + 1 end,
    }

    assertTrue(PRT.RosterNicknames:SetEnabled(true))
    assertTrue(profile.rosterNicknames.enabled)
    assertTrue(PRT.RosterNicknames:SetEnabled(false))
    assertFalse(profile.rosterNicknames.enabled)
    assertEquals(first, 2)
    assertEquals(second, 2)

    PRT.RosterNicknameAdapters.TestRefreshOne = nil
    PRT.RosterNicknameAdapters.TestRefreshTwo = nil
    PRT.Profiles.current = savedProfile
end

tests["late provider activation refreshes it and isolates provider errors"] = function()
    requireFeature()
    local manager = PRT.RosterNicknames
    local savedInitialized = manager.initialized
    local good = { initialized = 0, refreshed = 0 }
    function good:Initialize()
        self.initialized = self.initialized + 1
        return true
    end
    function good:Refresh()
        self.refreshed = self.refreshed + 1
    end
    local broken = {}
    function broken:Initialize()
        error("provider failure")
    end

    manager.initialized = true
    manager:RegisterAdapter("TestBroken", broken)
    manager:RegisterAdapter("TestGood", good)

    assertEquals(good.initialized, 1)
    assertEquals(good.refreshed, 1)
    PRT.RosterNicknameAdapters.TestBroken = nil
    PRT.RosterNicknameAdapters.TestGood = nil
    manager.initialized = savedInitialized
end

tests["refresh errors in one provider do not block another provider"] = function()
    requireFeature()
    local refreshed = 0
    PRT.RosterNicknameAdapters.TestBrokenRefresh = {
        Refresh = function() error("refresh failure") end,
    }
    PRT.RosterNicknameAdapters.TestGoodRefresh = {
        Refresh = function() refreshed = refreshed + 1 end,
    }

    PRT.RosterNicknames:RefreshAll()

    assertEquals(refreshed, 1)
    PRT.RosterNicknameAdapters.TestBrokenRefresh = nil
    PRT.RosterNicknameAdapters.TestGoodRefresh = nil
end

tests["Blizzard adapter changes only a supported frame name"] = function()
    requireFeature()
    local setTextCalls = 0
    local nameText = {
        value = "Aster",
        SetText = function(self, value)
            self.value = value
            setTextCalls = setTextCalls + 1
        end,
    }
    local frame = {
        unit = "target",
        name = nameText,
        secureAttribute = "target",
        style = "sentinel",
        status = "healthy",
    }

    withEnabledFeature(function()
        withGlobals({
            PlayerFrame = {},
            TargetFrame = frame,
            TargetFrameToT = {},
            FocusFrame = {},
            UnitIsPlayer = function() return true end,
            UnitFullName = function() return "Aster", "MoonGuard" end,
            issecretvalue = function() return false end,
        }, function()
            PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }
            PRT.RosterNicknameAdapters.Blizzard:ApplyUnitFrame(frame)
        end)
    end)

    assertEquals(nameText.value, "Starcaller")
    assertEquals(setTextCalls, 1)
    assertEquals(frame.unit, "target")
    assertEquals(frame.secureAttribute, "target")
    assertEquals(frame.style, "sentinel")
    assertEquals(frame.status, "healthy")
end

tests["Blizzard adapter leaves unsupported compact frames unchanged"] = function()
    requireFeature()
    local nameText = {
        value = "Boss",
        SetText = function(self, value) self.value = value end,
    }
    local frame = { unit = "boss1", name = nameText }

    withEnabledFeature(function()
        PRT.RosterNicknameAdapters.Blizzard:ApplyCompactFrame(frame)
    end)

    assertEquals(nameText.value, "Boss")
end

tests["Blizzard adapter renames pooled standard party frames"] = function()
    requireFeature()
    local nameText = {
        value = "Aster",
        SetText = function(self, value) self.value = value end,
    }
    local frame = {
        unit = "party1",
        name = nameText,
        GetUnit = function(self) return self.unit end,
    }
    local pool = {
        EnumerateActive = function()
            local pending = frame
            return function()
                local active = pending
                pending = nil
                return active
            end
        end,
    }

    withGlobals({
        PlayerFrame = {},
        TargetFrame = {},
        TargetFrameToT = {},
        FocusFrame = {},
        PartyFrame = { PartyMemberFramePool = pool },
        UnitIsPlayer = function() return true end,
        UnitFullName = function() return "Aster", "MoonGuard" end,
        issecretvalue = function() return false end,
    }, function()
        PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }
        withEnabledFeature(function()
            PRT.RosterNicknameAdapters.Blizzard:ApplyUnitFrame(frame)
        end)
    end)

    assertEquals(nameText.value, "Starcaller")
end

tests["Blizzard adapter preserves the normal name while disabled or unmatched"] = function()
    requireFeature()
    local nameText = {
        value = "Aster",
        SetText = function(self, value) self.value = value end,
    }
    local frame = { name = nameText }

    withGlobals({
        PlayerFrame = {},
        TargetFrame = frame,
        TargetFrameToT = {},
        FocusFrame = {},
        UnitIsPlayer = function() return true end,
        UnitFullName = function() return "Aster", "MoonGuard" end,
        issecretvalue = function() return false end,
    }, function()
        PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }
        PRT.RosterNicknameAdapters.Blizzard:ApplyUnitFrame(frame)
        assertEquals(nameText.value, "Aster")

        withEnabledFeature(function()
            PurplexityRaidToolsRosterDB = { rosterEntry("Ember", "Someone-MoonGuard") }
            PRT.RosterNicknameAdapters.Blizzard:ApplyUnitFrame(frame)
            assertEquals(nameText.value, "Aster")
        end)
    end)
end

tests["Blizzard refresh never runs a full unit-frame update"] = function()
    requireFeature()
    local names = {}
    local partyFlags = {}
    local function frame(unit)
        return {
            unit = unit,
            name = {
                SetText = function(_, value)
                    names[unit] = value
                end,
            },
        }
    end
    local player = frame("player")
    local target = frame("target")
    local targetTarget = frame("targettarget")
    local focus = frame("focus")
    local party = frame("party1")
    party.GetUnit = function(self) return self.unit end
    local partyPool = {
        EnumerateActive = function()
            local pending = party
            return function()
                local active = pending
                pending = nil
                return active
            end
        end,
    }

    withGlobals({
        PlayerFrame = player,
        TargetFrame = target,
        TargetFrameToT = targetTarget,
        FocusFrame = focus,
        PartyFrame = { PartyMemberFramePool = partyPool },
        UnitFrame_Update = function()
            error("a name refresh must not update health and power")
        end,
        GetUnitName = function(unit, isParty)
            partyFlags[unit] = isParty
            return "Normal-" .. unit
        end,
    }, function()
        PRT.RosterNicknameAdapters.Blizzard:Refresh()
    end)

    assertEquals(names.player, "Normal-player")
    assertEquals(names.target, "Normal-target")
    assertEquals(names.targettarget, "Normal-targettarget")
    assertEquals(names.focus, "Normal-focus")
    assertEquals(names.party1, "Normal-party1")
    assertFalse(partyFlags.player)
    assertTrue(partyFlags.party1)
end

tests["NivUI adapter registers one live resolver and preserves fallback"] = function()
    requireFeature()
    local registered
    local registrations = 0
    local api = {
        RegisterResolver = function(_, resolver)
            registered = resolver
            registrations = registrations + 1
            return true
        end,
    }

    withGlobals({ NivUI_Nicknames = api }, function()
        local adapter = PRT.RosterNicknameAdapters.NivUI
        adapter.registered = false
        assertTrue(adapter:Initialize())
        assertTrue(adapter:Initialize())
    end)

    assertEquals(registrations, 1)
    assertEquals(type(registered), "function")

    PurplexityRaidToolsRosterDB = { rosterEntry("Starcaller", "Aster-MoonGuard") }
    withEnabledFeature(function()
        assertEquals(registered("aster-moonguard"), "Starcaller")
        PurplexityRaidToolsRosterDB[1].nickname = "Starlight"
        assertEquals(registered("aster-moonguard"), "Starlight")
    end)

    assertNil(registered("Nobody-MoonGuard"))
    assertNil(registered("aster-moonguard"))
end

tests["ElvUI adapter registers full and Unicode-safe shortened tags"] = function()
    requireFeature()
    local tags = {}
    local tagInfo = {}
    local refreshed = 0
    local E = {
        TagFunctions = { UnitName = function() return "Aster" end },
        AddTag = function(_, name, _, callback)
            tags[name] = callback
        end,
        AddTagInfo = function(_, name)
            tagInfo[name] = true
        end,
        GetModule = function()
            return { Update_AllFrames = function() refreshed = refreshed + 1 end }
        end,
    }

    withGlobals({ ElvUI = { E } }, function()
        local adapter = PRT.RosterNicknameAdapters.ElvUI
        adapter.registered = false
        assertTrue(adapter:Initialize())
        adapter:Refresh()
    end)

    assertEquals(type(tags["prt-roster-nickname"]), "function")
    for length = 1, 12 do
        assertEquals(type(tags["prt-roster-nickname:" .. length]), "function")
        assertTrue(tagInfo["prt-roster-nickname:" .. length])
    end
    assertEquals(refreshed, 1)

    PurplexityRaidToolsRosterDB = { rosterEntry("éééé", "Aster-MoonGuard") }
    withEnabledFeature(function()
        withGlobals({
            UnitIsPlayer = function() return true end,
            UnitFullName = function() return "Aster", "MoonGuard" end,
            issecretvalue = function() return false end,
        }, function()
            assertEquals(tags["prt-roster-nickname"]("party1"), "éééé")
            assertEquals(tags["prt-roster-nickname:2"]("party1"), "éé")
        end)
    end)

    withGlobals({
        UnitIsPlayer = function() return true end,
        UnitFullName = function() return "Aster", "MoonGuard" end,
        issecretvalue = function() return false end,
    }, function()
        assertEquals(tags["prt-roster-nickname"]("party1"), "Aster")
    end)
end

return tests
