local tests = {}
local PRT = PurplexityRaidTools

PRT.BossTimelineDatabase = {
    encounters = {
        [3420] = {
            difficulties = {
                [16] = {
                    phases = {
                        {
                            phaseID = 1,
                            name = "Sszorak",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1285732, time = 35, observations = 3 },
                            },
                        },
                    },
                },
            },
        },
        [3421] = { difficulties = {} },
        [3429] = { difficulties = {} },
        [3445] = { difficulties = {} },
        [3455] = { difficulties = {} },
        [3470] = { difficulties = {} },
        [3497] = { difficulties = {} },
    },
}
dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("Modules/EncounterPhases/Planning.lua")
dofile("Modules/EncounterPhases/TheVenomousAbyss.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3420
local expectedPhases = {
    { id = 1, name = "Sszorak" },
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
        schedule = function()
        end,
    })
    assertNotNil(attempt, err)
    return attempt, activations
end

tests["Sszorak exposes one stable phase for every raid difficulty"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15, 16 }) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
    local compatibility = dofile("tests/fixtures/encounter_phase_compatibility.lua")
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {}))
end

tests["Sszorak declares no runtime transition observations"] = function()
    local attempt, activations = harness()
    assertTableEquals(EncounterPhases:GetAttemptEvents(attempt), {})
    assertFalse(EncounterPhases:ObserveAttempt(attempt, "UNIT_POWER_UPDATE", "boss1"))
    assertEquals(attempt.activePhase, 1)
    assertEquals(#activations, 0)
end

tests["Sszorak planning preserves canonical stored occurrences"] = function()
    local model = EncounterPhases:GetPlanningModel(encounterID, 16)
    assertTableEquals(model, {
        encounterID = encounterID,
        difficultyID = 16,
        phases = expectedPhases,
        occurrences = {
            { phase = 1, time = 35, spellID = 1285732 },
        },
    })
end

tests["Sszorak returns empty planning occurrences without stored difficulty data"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15 }) do
        local model = EncounterPhases:GetPlanningModel(encounterID, difficultyID)
        assertTableEquals(model.phases, expectedPhases)
        assertEquals(#model.occurrences, 0)
    end
end

return tests
