local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Planning.lua")

local EncounterPhases = PRT.EncounterPhases
local fixture = dofile("tests/fixtures/encounter_phases.lua")

local function sourceDifficulty()
    return {
        phases = {
            {
                phaseID = 7,
                name = "Raw One",
                isIntermission = false,
                occurrences = {
                    { spellID = 30, time = 5, observations = 3 },
                    { spellID = 20, time = 5, observations = 4 },
                },
            },
            {
                phaseID = 7,
                name = "Raw One Again",
                isIntermission = false,
                occurrences = {
                    { spellID = 10, time = 1, observations = 5 },
                },
            },
        },
    }
end

local function installDefinition(encounterID, project)
    PRT.BossTimelineDatabase = {
        encounters = {
            [encounterID] = {
                difficulties = { [16] = sourceDifficulty() },
            },
        },
    }
    local candidate = {
        events = {},
        GetPhases = function()
            return EncounterPhases.CopyPhases(fixture.phases)
        end,
        Begin = function()
            return {}
        end,
        Observe = function()
        end,
        ProjectWCL = project,
    }
    assertTrue(EncounterPhases:Register(encounterID, candidate))
end

tests["planning projection closes and canonically sorts the consumer contract"] = function()
    installDefinition(9301, function(_, phaseIndex, _, occurrence)
        if phaseIndex == 1 then
            return { phase = 2, time = occurrence.time + 10 }
        end
        return { phase = 1, time = occurrence.time + 2 }
    end)
    local before = CopyTable(PRT.BossTimelineDatabase)

    local model = EncounterPhases:GetPlanningModel(9301, 16)
    assertTableEquals(model, {
        encounterID = 9301,
        difficultyID = 16,
        phases = fixture.phases,
        occurrences = {
            { phase = 1, time = 3, spellID = 10 },
            { phase = 2, time = 15, spellID = 20 },
            { phase = 2, time = 15, spellID = 30 },
        },
    })
    assertTableEquals(PRT.BossTimelineDatabase, before)
    assertTableEquals(EncounterPhases:GetPlanningModel(9301, 16), model)
end

tests["a known definition with no stored difficulty returns empty occurrences"] = function()
    installDefinition(9302, function(_, phaseIndex, _, occurrence)
        return { phase = phaseIndex, time = occurrence.time }
    end)
    local model = EncounterPhases:GetPlanningModel(9302, 14)
    assertTableEquals(model.phases, fixture.phases)
    assertEquals(#model.occurrences, 0)
end

tests["an encounter without a completed definition has no planning model"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9303] = {} } }
    EncounterPhases:RegisterDraft(9303, function()
    end)
    assertNil(EncounterPhases:GetPlanningModel(9303, 16))
end

tests["invalid projection output fails instead of inventing a phase"] = function()
    installDefinition(9304, function()
        return { phase = 99, time = -1 }
    end)
    local model, err = EncounterPhases:GetPlanningModel(9304, 16)
    assertNil(model)
    assertNotNil(err)
end

return tests
