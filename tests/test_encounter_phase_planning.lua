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
                phaseID = 1,
                name = "Opening",
                isIntermission = false,
                occurrences = {
                    { spellID = 30, time = 5, observations = 3 },
                    { spellID = 20, time = 5, observations = 4 },
                },
            },
            {
                phaseID = 2,
                name = "Intermission",
                isIntermission = true,
                occurrences = {
                    { spellID = 10, time = 1, observations = 5 },
                },
            },
            {
                phaseID = 3,
                name = "Finale",
                isIntermission = false,
                occurrences = {},
            },
        },
    }
end

local function installDefinition(encounterID)
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
    }
    assertTrue(EncounterPhases:Register(encounterID, candidate))
end

tests["planning copies canonical stored occurrences into the closed sorted contract"] = function()
    installDefinition(9301)
    local before = CopyTable(PRT.BossTimelineDatabase)

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
    assertTableEquals(PRT.BossTimelineDatabase, before)
    assertTableEquals(EncounterPhases:GetPlanningModel(9301, 16), model)
end

tests["a known definition with no stored difficulty returns empty occurrences"] = function()
    installDefinition(9302)
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

tests["stored phases must exactly match the canonical phase sequence"] = function()
    installDefinition(9304)
    PRT.BossTimelineDatabase.encounters[9304].difficulties[16].phases[2].name = "Raw WCL Section"

    local model, err = EncounterPhases:GetPlanningModel(9304, 16)
    assertNil(model)
    assertEquals(err, "Stored phases do not match the encounter phase model.")
end

tests["invalid stored occurrences fail without leaking database fields"] = function()
    installDefinition(9305)
    PRT.BossTimelineDatabase.encounters[9305].difficulties[16].phases[1].occurrences[1].time = -1

    local model, err = EncounterPhases:GetPlanningModel(9305, 16)
    assertNil(model)
    assertEquals(err, "Stored occurrence is invalid.")
end

return tests
