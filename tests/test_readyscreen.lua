local tests = {}

if not PurplexityRaidTools.ReadyScreen then
    dofile("Modules/ReadyScreen.lua")
end

local ReadyScreen = PurplexityRaidTools.ReadyScreen

tests["FormatItemLevel: unavailable values display as an em dash"] = function()
    assertEquals(ReadyScreen.FormatItemLevel(nil), "\226\128\148")
    assertEquals(ReadyScreen.FormatItemLevel(0), "\226\128\148")
end

tests["FormatItemLevel: whole and fractional values remain distinguishable"] = function()
    assertEquals(ReadyScreen.FormatItemLevel(712), "712")
    assertEquals(ReadyScreen.FormatItemLevel(712.5), "712.5")
end

tests["GetDisplayedState: offline member shows offline regardless of dead or response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(true, false, "ready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, true, "ready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, true, "notready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, false, "pending"), "offline")
end

tests["GetDisplayedState: dead non-offline member shows dead regardless of response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "ready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "notready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "pending"), "dead")
end

tests["GetDisplayedState: alive connected member shows response state"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "pending"), "pending")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "ready"), "ready")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "notready"), "notready")
end

tests["GetDisplayedState: dead clears to recorded response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "ready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "ready"), "ready")
end

tests["FinalizeResponse: pending becomes notready at check completion"] = function()
    assertEquals(ReadyScreen.FinalizeResponse("pending"), "notready")
    assertEquals(ReadyScreen.FinalizeResponse("ready"), "ready")
    assertEquals(ReadyScreen.FinalizeResponse("notready"), "notready")
end

tests["GetDisplayedState after FinalizeResponse: condition overrides finalized response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, ReadyScreen.FinalizeResponse("pending")), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(true, false, ReadyScreen.FinalizeResponse("pending")), "offline")
end

tests["SortRoster: produces alphabetical order by name"] = function()
    local roster = {
        { name = "Zed" },
        { name = "Alice" },
        { name = "Moe" },
    }
    local result = ReadyScreen.SortRoster(roster)
    assertNotNil(result, "SortRoster must return the table")
    assertEquals(result, roster, "SortRoster must return the same table reference")
    assertEquals(roster[1].name, "Alice")
    assertEquals(roster[2].name, "Moe")
    assertEquals(roster[3].name, "Zed")
end

tests["ClassifyVersion: member version below RL is outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1000000, 1001003), "outdated")
end

tests["ClassifyVersion: member version equal to RL is current"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1001003, 1001003), "current")
    assertEquals(ReadyScreen.ClassifyVersion(1001004, 1001003), "current",
        "member running a newer version than RL is still current")
end

tests["ClassifyVersion: nil member version is missing not outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(nil, 1001003), "missing")
end

tests["SortRoster: nil names sort last without error"] = function()
    local roster = {
        { name = "Zed" },
        { name = nil },
        { name = "Alice" },
    }
    local result = ReadyScreen.SortRoster(roster)
    assertNotNil(result, "SortRoster must not crash on nil names")
    assertEquals(roster[1].name, "Alice")
    assertEquals(roster[2].name, "Zed")
    assertNil(roster[3].name, "nil-name members must sort last")
end

tests["ClassifyVersion: nil RL version means nobody is outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1000000, nil), "current")
    assertEquals(ReadyScreen.ClassifyVersion(999, nil), "current")
    assertEquals(ReadyScreen.ClassifyVersion(nil, nil), "missing",
        "nil member with nil RL is still missing, not outdated")
end

tests["GetPersonalBuffKey: recognizes food from the standard Well Fed icon"] = function()
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 999999, icon = 136000 }), "wellFed")
end

tests["GetPersonalBuffKey: recognizes current and previous expansion flasks"] = function()
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 1236763, icon = 1 }), "flask")
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 431971, icon = 1 }), "flask")
end

tests["GetPersonalBuffKey: recognizes augment runes"] = function()
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 1234969, icon = 1 }), "augmentRune")
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 1242347, icon = 1 }), "augmentRune")
    assertEquals(ReadyScreen.GetPersonalBuffKey({ spellId = 1264426, icon = 1 }), "augmentRune")
end

tests["GetPersonalBuffKey: recognizes localized Vantus prefixes"] = function()
    assertEquals(ReadyScreen.GetPersonalBuffKey({
        spellId = 999999,
        name = "Vantus Rune: Radiant",
        icon = 1,
    }, "Vantus Rune"), "vantusRune")
    assertEquals(ReadyScreen.GetPersonalBuffKey({
        spellId = 999999,
        name = "Rune de Vantus : Radieuse",
        icon = 1,
    }, "Rune de Vantus"), "vantusRune")
end

tests["GetPersonalBuffKey: ignores unrelated helpful auras"] = function()
    assertNil(ReadyScreen.GetPersonalBuffKey({
        spellId = 1459,
        name = "Arcane Intellect",
        icon = 135932,
    }, "Vantus Rune"))
end

tests["GetPersonalBuffKey: ignores inaccessible aura data"] = function()
    local originalCanAccessValue = canaccessvalue
    canaccessvalue = function()
        return false
    end

    local key = ReadyScreen.GetPersonalBuffKey({
        spellId = 1236763,
        name = "Flask",
        icon = 967549,
    }, "Vantus Rune")

    canaccessvalue = originalCanAccessValue
    assertNil(key)
end

tests["GetPersonalBuffColumns: uses MRT icons and a wide durability column"] = function()
    local columns = ReadyScreen.GetPersonalBuffColumns()
    local expected = {
        wellFed = 136000,
        weaponEnhancement = 463543,
        flask = 967549,
        augmentRune = 840006,
        vantusRune = 1058937,
        durability = 132281,
    }

    for _, column in ipairs(columns) do
        assertEquals(column.texture, expected[column.key])
    end
    assertTrue(columns[#columns].width > 24)
    assertEquals(columns[#columns].key, "durability")
end

tests["BuildPersonalBuffStatuses: records the matched aura icon by category"] = function()
    local statuses = ReadyScreen.BuildPersonalBuffStatuses({
        { spellId = 1459, name = "Arcane Intellect", icon = 135932 },
        { spellId = 431971, name = "Flask of Tempered Aggression", icon = 1234 },
        { spellId = 1234969, name = "Soulgorged Augment Rune", icon = 5678 },
    }, "Vantus Rune")

    assertEquals(statuses.flask, 1234)
    assertEquals(statuses.augmentRune, 5678)
    assertNil(statuses.wellFed)
    assertNil(statuses.vantusRune)
end

tests["AnyWeaponEnhanced: either weapon enchant satisfies the combined status"] = function()
    assertTrue(ReadyScreen.AnyWeaponEnhanced(true, false))
    assertTrue(ReadyScreen.AnyWeaponEnhanced(false, true))
    assertFalse(ReadyScreen.AnyWeaponEnhanced(false, false))
end

tests["CalculateDurability: weights equipped items by their maximum durability"] = function()
    local percent = ReadyScreen.CalculateDurability({
        { current = 20, maximum = 100 },
        { current = 50, maximum = 50 },
    })
    assertNear(percent, 70 / 150 * 100, 0.001)
end

tests["CalculateDurability: ignores slots without durability"] = function()
    local percent = ReadyScreen.CalculateDurability({
        { current = nil, maximum = nil },
        { current = 75, maximum = 100 },
    })
    assertEquals(percent, 75)
end

tests["CalculateDurability: an indestructible equipment set reports one hundred"] = function()
    assertEquals(ReadyScreen.CalculateDurability({}), 100)
end

tests["Initialize: status reports from non-leaders resolve through group unit tokens"] = function()
    local originalComms = PurplexityRaidTools.Comms
    local originalGroupInspect = PurplexityRaidTools.GroupInspect
    local originalIterateGroup = PurplexityRaidTools.IterateGroup
    local originalUnitGUID = UnitGUID
    local originalGetUnitName = GetUnitName
    local originalWeaponEnchantInfo = GetWeaponEnchantInfo
    local originalInventoryDurability = GetInventoryItemDurability

    local handlers = {}
    local sent
    PurplexityRaidTools.Comms = {
        RegisterHandler = function(_, messageType, handler)
            handlers[messageType] = handler
        end,
        Send = function(_, messageType, data, channel, target)
            sent = { messageType = messageType, data = data, channel = channel, target = target }
        end,
    }
    PurplexityRaidTools.GroupInspect = {
        members = { ["GUID-ALICE"] = {}, ["GUID-NIV"] = {}, ["GUID-BOB"] = {} },
        Listen = function() end,
    }
    PurplexityRaidTools.IterateGroup = function()
        local units = { "party1", "party2", "player" }
        local index = 0
        return function()
            index = index + 1
            return units[index]
        end
    end
    UnitGUID = function(unit)
        if unit == "party1" then return "GUID-NIV" end
        if unit == "party2" then return "GUID-BOB" end
        if unit == "player" then return "GUID-ALICE" end
        return nil
    end
    GetUnitName = function(unit)
        if unit == "party1" then return "Niv" end
        if unit == "party2" then return "Bob" end
        if unit == "player" then return "Alice" end
        return nil
    end
    GetWeaponEnchantInfo = function()
        return true, 0, 0, 1, false, 0, 0, 0
    end
    GetInventoryItemDurability = function(slotId)
        if slotId == 1 then
            return 50, 100
        end
        return nil, nil
    end

    ReadyScreen:Initialize()
    assertNil(UnitGUID("Niv"), "the fixture must require roster-token resolution")
    handlers.readyStatusQuery({}, "Niv")

    assertEquals(sent.messageType, "readyStatusResponse")
    assertEquals(sent.channel, "WHISPER")
    assertEquals(sent.target, "Niv")
    assertTrue(sent.data.weaponEnhanced)
    assertEquals(sent.data.durability, 50)

    handlers.readyStatusResponse({ weaponEnhanced = false, durability = 42 }, "Bob")
    assertFalse(ReadyScreen:GetWeaponStatus("GUID-BOB"))
    assertEquals(ReadyScreen:GetDurability("GUID-BOB"), 42)

    PurplexityRaidTools.Comms = originalComms
    PurplexityRaidTools.GroupInspect = originalGroupInspect
    PurplexityRaidTools.IterateGroup = originalIterateGroup
    UnitGUID = originalUnitGUID
    GetUnitName = originalGetUnitName
    GetWeaponEnchantInfo = originalWeaponEnchantInfo
    GetInventoryItemDurability = originalInventoryDurability
end

local function withShowHarness(body)
    local PRT = PurplexityRaidTools
    local savedFrame = PRT.ReadyScreenFrame
    local savedGroupInspect = PRT.GroupInspect
    local savedGetSetting = PRT.GetSetting
    local savedRequestStatuses = ReadyScreen.RequestStatuses
    local savedIsInGroup = IsInGroup
    local savedTimer = C_Timer
    local context = { shown = {}, statusRequests = 0 }

    PRT.ReadyScreenFrame = {
        Show = function(_, view)
            context.shown[#context.shown + 1] = view
        end,
        Hide = function() end,
    }
    PRT.GroupInspect = { members = {} }
    PRT.GetSetting = function(_, key)
        assertEquals(key, "readyScreen")
        return { enabled = true }
    end
    ReadyScreen.RequestStatuses = function()
        context.statusRequests = context.statusRequests + 1
    end
    IsInGroup = function()
        return true
    end
    C_Timer = {
        NewTicker = function()
            return { Cancel = function() end }
        end,
    }

    ReadyScreen:Close()
    local ok, err = pcall(body, context)
    ReadyScreen:Close()

    PRT.ReadyScreenFrame = savedFrame
    PRT.GroupInspect = savedGroupInspect
    PRT.GetSetting = savedGetSetting
    ReadyScreen.RequestStatuses = savedRequestStatuses
    IsInGroup = savedIsInGroup
    C_Timer = savedTimer

    if not ok then
        error(err, 0)
    end
end

tests["ShowGear selects Gear without starting a readiness status request"] = function()
    withShowHarness(function(context)
        ReadyScreen:ShowGear()

        assertEquals(ReadyScreen:GetMode(), "gear")
        assertTableEquals(context.shown, { "gear" })
        assertEquals(context.statusRequests, 0)
    end)
end

tests["ShowReadiness selects the manual Readiness view"] = function()
    withShowHarness(function(context)
        ReadyScreen:ShowReadiness()

        assertEquals(ReadyScreen:GetMode(), "audit")
        assertTableEquals(context.shown, { "readiness" })
        assertEquals(context.statusRequests, 1)
    end)
end

tests["a ready check selects Readiness"] = function()
    withShowHarness(function(context)
        ReadyScreen:ShowReadyCheck(nil)

        assertEquals(ReadyScreen:GetMode(), "readycheck")
        assertTableEquals(context.shown, { "readiness" })
    end)
end

return tests
