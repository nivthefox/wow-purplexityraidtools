local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("BossData/Registry.lua")
dofile("Modules/EncounterPhases/Planning.lua")

local BossData = PRT.BossData
local EncounterPhases = PRT.EncounterPhases
local fixture = dofile("tests/fixtures/encounter_phases.lua")

local function installDefinition(encounterID)
    local candidate = {
        timings = {
            [16] = {
                [1] = {
                    { spellID = 20, time = 5 },
                    { spellID = 30, time = 5 },
                },
                [2] = {
                    { spellID = 10, time = 1 },
                },
                [3] = {},
            },
        },
        events = {},
        GetPhases = function()
            return EncounterPhases.CopyPhases(fixture.phases)
        end,
        Begin = function()
            return {}
        end,
        Observe = function()
        end,
    }
    assertTrue(BossData:Register(encounterID, candidate))
end

tests["planning copies stored abilities into the closed sorted contract"] = function()
    installDefinition(9301)
    local stored = BossData.encounters[9301].timings[16]

    local model = EncounterPhases:GetPlanningModel(9301, 16)
    assertTableEquals(model, {
        encounterID = 9301,
        difficultyID = 16,
        phases = fixture.phases,
        occurrences = {
            { phase = 1, time = 5, spellID = 20 },
            { phase = 1, time = 5, spellID = 30 },
            { phase = 2, time = 1, spellID = 10 },
        },
    })
    assertTableEquals(stored, {
        [1] = {
            { spellID = 20, time = 5 },
            { spellID = 30, time = 5 },
        },
        [2] = {
            { spellID = 10, time = 1 },
        },
        [3] = {},
    })
    assertTableEquals(EncounterPhases:GetPlanningModel(9301, 16), model)
end

tests["a known definition with no stored difficulty returns empty occurrences"] = function()
    installDefinition(9302)
    local model = EncounterPhases:GetPlanningModel(9302, 14)
    assertTableEquals(model.phases, fixture.phases)
    assertEquals(#model.occurrences, 0)
end

tests["an encounter without a completed definition has no planning model"] = function()
    BossData.encounters[9303] = {}
    EncounterPhases:RegisterDraft(9303, function()
    end)
    assertNil(EncounterPhases:GetPlanningModel(9303, 16))
end

tests["mutated timing phases fail closed"] = function()
    installDefinition(9304)
    BossData.encounters[9304].timings[16][3] = nil

    local model, err = EncounterPhases:GetPlanningModel(9304, 16)
    assertNil(model)
    assertEquals(err, "Stored ability timings do not match the encounter phase model.")
end

tests["invalid stored occurrences fail without leaking data fields"] = function()
    installDefinition(9305)
    BossData.encounters[9305].timings[16][1][1].time = -1

    local model, err = EncounterPhases:GetPlanningModel(9305, 16)
    assertNil(model)
    assertEquals(err, "Stored occurrence is invalid.")
end

return tests
