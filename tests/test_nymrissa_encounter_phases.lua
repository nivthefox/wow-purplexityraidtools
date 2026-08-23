local tests = {}
local PRT = PurplexityRaidTools

PRT.BossTimelineDatabase = {
    encounters = {
        [3379] = {
            difficulties = {
                [16] = {
                    phases = {
                        {
                            phaseID = 1,
                            name = "Nymrissa Wavecaller",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1260837, time = 11, observations = 3 },
                            },
                        },
                    },
                },
            },
        },
    },
}
dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("Modules/EncounterPhases/Planning.lua")
dofile("Modules/EncounterPhases/Lairs.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3379
local expectedPhases = {
    { id = 1, name = "Nymrissa Wavecaller" },
}

local function harness()
    local activations = {}
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, 16, {
        activate = function(phase, activationTime)
            activations[#activations + 1] = { phase = phase, time = activationTime }
        end,
        isSecret = function()
            return false
        end,
        now = function()
            return 100
        end,
    })
    assertNotNil(attempt, err)
    return attempt, activations
end

tests["Nymrissa exposes one stable phase for every supported difficulty"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15, 16 }) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
    local compatibility = dofile("tests/fixtures/encounter_phase_compatibility.lua")
    assertTrue(EncounterPhases:ValidateCompatibility({ [encounterID] = compatibility[encounterID] }, {}))
end

tests["Nymrissa declares no runtime transition observations"] = function()
    local attempt, activations = harness()
    assertTableEquals(EncounterPhases:GetAttemptEvents(attempt), {})
    assertFalse(EncounterPhases:ObserveAttempt(attempt, "ENCOUNTER_TIMELINE_EVENT_ADDED", {}))
    assertEquals(attempt.activePhase, 1)
    assertEquals(#activations, 0)
end

tests["Nymrissa planning preserves canonical stored occurrences"] = function()
    local model = EncounterPhases:GetPlanningModel(encounterID, 16)
    assertTableEquals(model, {
        encounterID = encounterID,
        difficultyID = 16,
        phases = expectedPhases,
        occurrences = {
            { phase = 1, time = 11, spellID = 1260837 },
        },
    })
end

tests["Nymrissa returns empty planning occurrences without stored difficulty data"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15 }) do
        local model = EncounterPhases:GetPlanningModel(encounterID, difficultyID)
        assertTableEquals(model.phases, expectedPhases)
        assertEquals(#model.occurrences, 0)
    end
end

return tests
