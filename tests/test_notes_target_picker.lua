local tests = {}

if not PurplexityRaidTools.NotesPlanner then
    dofile("Modules/Notes/NotesPlanner.lua")
end

if not PurplexityRaidTools.NotesEditor then
    dofile("Modules/Notes/NotesEditor.lua")
end

local PRT = PurplexityRaidTools
local NotesEditor = PRT.NotesEditor

local GROUP_MEMBERS = {
    ["GUID-ASTER"] = { name = "Aster-MoonGuard", class = "WARRIOR", specId = 71 },
    ["GUID-EMBER"] = { name = "Ember-Illidan", class = "PALADIN", specId = 70 },
}

local ROSTER_ENTRIES = {
    {
        nickname = "Starcaller",
        characters = { "Aster-MoonGuard", "Nova-Illidan" },
        characterData = {
            ["Aster-MoonGuard"] = { class = "DRUID", mainSpec = 105 },
            ["Nova-Illidan"] = { class = "MAGE" },
        },
    },
    {
        nickname = "Ember",
        characters = { "Cinder-Area52" },
        characterData = {
            ["Cinder-Area52"] = { class = "MAGE", mainSpec = 63 },
        },
    },
}

local SPELL_DATA = {
    [71] = {
        name = "Arms",
        class = "WARRIOR",
        abilities = {
            [100] = { spellId = 100, name = "Rallying Cry", cooldown = 180 },
            [101] = { spellId = 101, name = "Slam", cooldown = 0 },
        },
    },
    [105] = {
        name = "Restoration",
        class = "DRUID",
        abilities = {
            [200] = { spellId = 200, name = "Tranquility", cooldown = 180 },
        },
    },
    [63] = {
        name = "Fire",
        class = "MAGE",
        abilities = {
            [300] = { spellId = 300, name = "Combustion", cooldown = 120 },
        },
    },
}

local function withTargetContext(isGrouped, body)
    local savedSpellData = PRT.SpellData
    local savedGroupInspect = PRT.GroupInspect
    local savedRoster = PRT.Roster
    local savedIsInGroup = IsInGroup
    local savedUnitName = UnitName
    local savedClassColors = RAID_CLASS_COLORS

    PRT.SpellData = SPELL_DATA
    PRT.GroupInspect = { members = GROUP_MEMBERS }
    PRT.Roster = { GetEntries = function() return ROSTER_ENTRIES end }
    IsInGroup = function() return isGrouped end
    UnitName = function() return "Local" end
    RAID_CLASS_COLORS = {
        DRUID = { r = 1, g = 0.49, b = 0.04 },
        MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    }

    local ok, err = pcall(body)

    PRT.SpellData = savedSpellData
    PRT.GroupInspect = savedGroupInspect
    PRT.Roster = savedRoster
    IsInGroup = savedIsInGroup
    UnitName = savedUnitName
    RAID_CLASS_COLORS = savedClassColors

    if not ok then
        error(err, 0)
    end
end

tests["a group target picker lists current members instead of roster characters"] = function()
    local options = NotesEditor.BuildTargetOptions(true, GROUP_MEMBERS, ROSTER_ENTRIES)

    assertEquals(#options, 2)
    assertEquals(options[1].value, "Aster")
    assertEquals(options[1].specId, 71)
    assertEquals(options[1].class, "WARRIOR")
    assertEquals(options[2].value, "Ember")
    assertEquals(options[2].specId, 70)
    assertEquals(options[2].class, "PALADIN")
end

tests["a solo target picker lists only roster characters with main specs"] = function()
    local options = NotesEditor.BuildTargetOptions(false, GROUP_MEMBERS, ROSTER_ENTRIES)

    assertEquals(#options, 2)
    assertEquals(options[1].value, "Aster")
    assertEquals(options[1].specId, 105)
    assertEquals(options[1].class, "DRUID")
    assertEquals(options[2].value, "Cinder")
    assertEquals(options[2].specId, 63)
    assertEquals(options[2].class, "MAGE")
end

tests["group ability choices use the inspected spec even for a rostered character"] = function()
    withTargetContext(true, function()
        local abilities = NotesEditor.GetAbilitiesForTag("Aster")

        assertEquals(#abilities, 1)
        assertEquals(abilities[1].name, "Rallying Cry")
        assertEquals(abilities[1].spellId, 100)
    end)
end

tests["solo ability choices use the roster main spec"] = function()
    withTargetContext(false, function()
        local abilities = NotesEditor.GetAbilitiesForTag("Aster")

        assertEquals(#abilities, 1)
        assertEquals(abilities[1].name, "Tranquility")
        assertEquals(abilities[1].spellId, 200)
    end)
end

tests["a solo roster character without a main spec has no ability choices"] = function()
    withTargetContext(false, function()
        assertTableEquals(NotesEditor.GetAbilitiesForTag("Nova"), {})
    end)
end

tests["assignment colors follow the active group or solo roster source"] = function()
    withTargetContext(true, function()
        local r, g, b = NotesEditor.GetClassColorForTag("Aster")
        assertNear(r, 0.78, 0.001)
        assertNear(g, 0.61, 0.001)
        assertNear(b, 0.43, 0.001)
    end)

    withTargetContext(false, function()
        local r, g, b = NotesEditor.GetClassColorForTag("Aster")
        assertNear(r, 1, 0.001)
        assertNear(g, 0.49, 0.001)
        assertNear(b, 0.04, 0.001)
    end)
end

tests["a known ability name resolves its spell ID without changing the text"] = function()
    local abilities = {
        { name = "Rallying Cry", spellId = 100 },
        { name = "Shield Wall", spellId = 101 },
    }

    assertEquals(NotesEditor.FindAbilitySpellID("Rallying Cry", abilities), 100)
    assertEquals(NotesEditor.FindAbilitySpellID("Rallying Cry on the tanks", abilities), 100)
    assertNil(NotesEditor.FindAbilitySpellID("Use a defensive", abilities))
end

tests["spell labels add an icon only when the spell texture is known"] = function()
    local savedSpellAPI = C_Spell
    C_Spell = {
        GetSpellTexture = function(spellID)
            return spellID == 100 and 135871 or nil
        end,
    }

    local ok, err = pcall(function()
        assertEquals(
            NotesEditor.FormatSpellLabel("Rallying Cry", 100, 14),
            "|T135871:14:14|t Rallying Cry"
        )
        assertEquals(NotesEditor.FormatSpellLabel("Free text", nil, 14), "Free text")
        assertEquals(NotesEditor.FormatSpellLabel("Unknown", 999, 14), "Unknown")
    end)

    C_Spell = savedSpellAPI
    if not ok then
        error(err, 0)
    end
end

return tests
