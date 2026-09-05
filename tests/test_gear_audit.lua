local tests = {}
dofile("Modules/GearAudit.lua")
local Audit = PurplexityRaidTools.GearAudit

local function withItems(body)
    local saved = C_Item
    local items = {}
    local function item(link)
        return items[tonumber(link:match("item:(%d+):"))]
    end
    C_Item = {
        IsItemDataCachedByID = function(id) return items[id] and items[id].cached ~= false end,
        GetItemInfoInstant = function(link) return 1, nil, nil, item(link).equipLoc end,
        GetItemStats = function(link) return item(link).stats end,
        GetItemGemID = function(link, index) return item(link).gems[index] end,
    }
    local equipment = {}
    for slot = 1, 17 do
        equipment[slot] = "item:" .. slot .. ":123:0:0:0:0:"
        items[slot] = { equipLoc = "INVTYPE_WEAPON", stats = {}, gems = {} }
    end
    local ok, err = pcall(body, equipment, items)
    C_Item = saved
    if not ok then error(err, 0) end
end

tests["all required enhancements present produces complete results"] = function()
    withItems(function(equipment)
        local audit = Audit.Evaluate(equipment)
        assertEquals(audit.enchants.status, "complete")
        assertEquals(audit.gems.status, "complete")
    end)
end

tests["Midnight audit includes head shoulders legs rings and both weapons"] = function()
    withItems(function(equipment)
        for slot = 1, 17 do equipment[slot] = "item:" .. slot .. ":0:0:0:0:0:" end
        local audit = Audit.Evaluate(equipment)
        assertEquals(audit.enchants.status, "missing")
        local slots = {}
        for _, missing in ipairs(audit.enchants.missing) do slots[#slots + 1] = missing.slot end
        assertTableEquals(slots, { 1, 3, 5, 7, 8, 11, 12, 16, 17 })
    end)
end

tests["shields held offhands and empty offhands do not require weapon enchants"] = function()
    withItems(function(equipment, items)
        equipment[17] = "item:17:0:0:0:0:0:"
        for _, equipLoc in ipairs({ "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }) do
            items[17].equipLoc = equipLoc
            assertEquals(Audit.Evaluate(equipment).enchants.status, "complete")
        end
        equipment[17] = false
        assertEquals(Audit.Evaluate(equipment).enchants.status, "complete")
    end)
end

tests["two handed ranged and dual wield weapons require enhancement presence"] = function()
    withItems(function(equipment, items)
        equipment[16] = "item:16::0:0:0:0:"
        equipment[17] = false
        for _, equipLoc in ipairs({ "INVTYPE_2HWEAPON", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
            "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" }) do
            items[16].equipLoc = equipLoc
            local audit = Audit.Evaluate(equipment)
            assertEquals(audit.enchants.status, "missing")
            assertEquals(audit.enchants.missing[1].slot, 16)
        end
    end)
end

tests["all socket types and empty positions are counted independently of inserted gems"] = function()
    withItems(function(equipment, items)
        items[2].stats = { EMPTY_SOCKET_PRISMATIC = 2, EMPTY_SOCKET_META = 1 }
        items[2].gems = { [2] = 999 }
        items[9].stats = { EMPTY_SOCKET_PRISMATIC = 1 }
        local audit = Audit.Evaluate(equipment)
        assertEquals(audit.gems.status, "missing")
        assertTableEquals(audit.gems.missing, { { slot = 2, count = 2 }, { slot = 9, count = 1 } })
        assertEquals(Audit.GetDetails(audit.gems), "Missing: Neck (2), Wrists.")
        items[2].gems = { 1, 2, 3 }
        items[9].gems = { 4 }
        assertEquals(Audit.Evaluate(equipment).gems.status, "complete")
    end)
end

tests["one missing enchant and gem on the second ring leaves the first ring complete"] = function()
    withItems(function(equipment, items)
        equipment[12] = "item:12:0:0:0:0:0:"
        items[11].stats = { EMPTY_SOCKET_PRISMATIC = 1 }
        items[11].gems = { 999 }
        items[12].stats = { EMPTY_SOCKET_PRISMATIC = 1 }

        local audit = Audit.Evaluate(equipment)
        assertTableEquals(audit.enchants.missing, { { slot = 12, count = 1 } })
        assertTableEquals(audit.gems.missing, { { slot = 12, count = 1 } })
        assertEquals(Audit.GetDetails(audit.enchants), "Missing: Ring 2.")
        assertEquals(Audit.GetDetails(audit.gems), "Missing: Ring 2.")
    end)
end

tests["socketless rings and neck do not imply missing sockets"] = function()
    withItems(function(equipment)
        assertEquals(Audit.Evaluate(equipment).gems.status, "complete")
    end)
end

tests["uncached and incomplete item data remain unknown with bounded retry inputs"] = function()
    withItems(function(equipment, items)
        items[1].cached = false
        items[2].stats = nil
        local audit, pending = Audit.Evaluate(equipment)
        assertEquals(audit.enchants.status, "unknown")
        assertEquals(audit.gems.status, "unknown")
        assertTableEquals(pending, { [1] = true, [2] = true })
        assertEquals(#audit.enchants.missing, 0)
        assertEquals(#audit.gems.missing, 0)
    end)
end

tests["incomplete inspection preserves confirmed missing details under unknown status"] = function()
    withItems(function(equipment)
        equipment[1] = nil
        equipment[3] = "item:3:0:0:0:0:0:"
        local audit = Audit.Evaluate(equipment)
        assertEquals(audit.enchants.status, "unknown")
        assertEquals(Audit.GetDetails(audit.enchants), "Missing: Shoulders.\nUnknown: Head.")
        assertEquals(audit.gems.status, "unknown")
        assertEquals(Audit.Evaluate(nil).enchants.status, "unknown")
    end)
end

tests["unresolved weapon type and malformed enchant fields are unknown"] = function()
    withItems(function(equipment, items)
        equipment[1] = "item:1"
        items[16].equipLoc = nil
        local audit = Audit.Evaluate(equipment)
        assertEquals(audit.enchants.status, "unknown")
        assertTableEquals(audit.enchants.unknown, { 1, 16 })
    end)
end

tests["capture distinguishes unloaded links from an empty offhand"] = function()
    local savedLink, savedID = GetInventoryItemLink, GetInventoryItemID
    local savedTexture, savedUnit = GetInventoryItemTexture, UnitIsUnit
    GetInventoryItemLink = function() return nil end
    GetInventoryItemID = function(_, slot) if slot == 1 then return 100 end end
    GetInventoryItemTexture = function(_, slot) if slot == 1 then return 1234 end end
    UnitIsUnit = function(unit) return unit == "player" end
    local remote = Audit.Capture("raid2")
    local player = Audit.Capture("player")
    GetInventoryItemLink, GetInventoryItemID = savedLink, savedID
    GetInventoryItemTexture, UnitIsUnit = savedTexture, savedUnit
    assertNil(remote[1])
    assertNil(remote[5])
    assertEquals(remote[17], false)
    assertNil(player[1])
    assertEquals(player[5], false)
end

return tests
