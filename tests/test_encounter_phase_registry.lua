local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("BossData/Registry.lua")
dofile("BossData/Lairs/NymrissaWavecaller.lua")
dofile("BossData/TheVenomousAbyss/Sszorak.lua")
dofile("BossData/TheVenomousAbyss/TheTwinFangs.lua")
dofile("BossData/TheVenomousAbyss/TheCoiledAltar.lua")
dofile("BossData/TheVenomousAbyss/EntombedSentinels.lua")
dofile("BossData/TheVenomousAbyss/VashnikTheMalignant.lua")
dofile("BossData/TheVenomousAbyss/Nekzali.lua")
dofile("BossData/TheVenomousAbyss/Ulatek.lua")
dofile("BossData/TheVenomousAbyss/TheLostExplorers.lua")

local EncounterPhases = PRT.EncounterPhases
local fixture = dofile("tests/fixtures/encounter_phases.lua")

local function copyPhases()
    return EncounterPhases.CopyPhases(fixture.phases)
end

local function definition(getPhases)
    return {
        events = { "FAKE_EVENT" },
        GetPhases = getPhases or copyPhases,
        Begin = function()
            return {}
        end,
        Observe = function()
        end,
    }
end

tests["every shipped boss file registers through the combined contract"] = function()
    local expected = {
        [3379] = true,
        [3420] = true,
        [3421] = true,
        [3429] = true,
        [3445] = true,
        [3455] = true,
        [3470] = true,
        [3492] = true,
        [3497] = true,
    }
    local count = 0
    for encounterID in pairs(PRT.BossData.encounters) do
        assertTrue(expected[encounterID])
        assertNotNil(EncounterPhases:GetDefinition(encounterID))
        count = count + 1
    end
    assertEquals(count, 9)
end

tests["registration requires an encounter in boss data"] = function()
    PRT.BossData = { encounters = {} }
    local ok = EncounterPhases:Register(9101, definition())
    assertFalse(ok)
end

tests["registration accepts a complete definition for all raid difficulties"] = function()
    PRT.BossData = { encounters = { [9102] = {} } }
    local candidate = definition()
    local ok, err = EncounterPhases:Register(9102, candidate)
    assertTrue(ok)
    assertNil(err)
    assertEquals(EncounterPhases:GetDefinition(9102), candidate)
    assertTableEquals(EncounterPhases:GetPhases(9102, 16), fixture.phases)
end

tests["registration accepts only narrow boss unit event declarations"] = function()
    PRT.BossData = { encounters = { [9107] = {}, [9108] = {} } }
    local candidate = definition()
    candidate.events = { { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "boss2" } }
    assertTrue(EncounterPhases:Register(9107, candidate))

    local invalid = definition()
    invalid.events = { { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "player" } }
    assertFalse(EncounterPhases:Register(9108, invalid))
end

tests["registration rejects fields outside the behavior contract"] = function()
    PRT.BossData = { encounters = { [9106] = {} } }
    local candidate = definition()
    candidate.ExtraMethod = function()
    end
    assertFalse(EncounterPhases:Register(9106, candidate))
end

tests["registration rejects a missing or non-contiguous difficulty phase model"] = function()
    PRT.BossData = { encounters = { [9103] = {}, [9104] = {} } }

    local missing = definition(function(difficultyID)
        if difficultyID == 17 then
            return nil
        end
        return copyPhases()
    end)
    assertFalse(EncounterPhases:Register(9103, missing))

    local nonContiguous = definition(function()
        return {
            { id = 1, name = "Opening" },
            { id = 3, name = "Finale" },
        }
    end)
    assertFalse(EncounterPhases:Register(9104, nonContiguous))
end

tests["published identities require an explicit migration before they change"] = function()
    PRT.BossData = { encounters = { [9105] = {} } }
    assertTrue(EncounterPhases:Register(9105, definition()))

    local compatibility = {
        [9105] = {
            [16] = {
                { id = 1, name = "Opening" },
                { id = 2, name = "Old Intermission" },
                { id = 3, name = "Finale" },
            },
        },
    }
    assertFalse(EncounterPhases:ValidateCompatibility(compatibility, {}))
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {
        [9105] = { [16] = true },
    }))
end

return tests
