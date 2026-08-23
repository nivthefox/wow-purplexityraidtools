local tests = {}
local PRT = PurplexityRaidTools

dofile("BossTimelineData.lua")
dofile("Modules/BossTimelineDatabase.lua")
dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("Modules/EncounterPhases/Planning.lua")
dofile("Modules/EncounterPhases/TheVenomousAbyss.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3445
local difficulties = { 17, 14, 15, 16 }
local expectedPhases = {
    { id = 1, name = "Entombed Sentinels" },
}
local phaseOffsets = { 0, 46, 74, 165, 193, 284, 312, 403, 431, 522, 550 }

local function harness(difficultyID)
    local activations = {}
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, difficultyID or 14, {
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

local function expectedOccurrences(difficulty)
    local occurrences = {}
    for phaseIndex, phase in ipairs(difficulty.phases) do
        for _, occurrence in ipairs(phase.occurrences) do
            occurrences[#occurrences + 1] = {
                phase = 1,
                time = phaseOffsets[phaseIndex] + occurrence.time,
                spellID = occurrence.spellID,
            }
        end
    end
    table.sort(occurrences, function(left, right)
        if left.time ~= right.time then
            return left.time < right.time
        end
        return left.spellID < right.spellID
    end)
    return occurrences
end

tests["Entombed Sentinels exposes one stable phase for every raid difficulty"] = function()
    for _, difficultyID in ipairs(difficulties) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
    local compatibility = dofile("tests/fixtures/encounter_phase_compatibility.lua")
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {}))
end

tests["Entombed Sentinels declares no runtime transition observations"] = function()
    local attempt, activations = harness()
    assertTableEquals(EncounterPhases:GetAttemptEvents(attempt), {})
    assertFalse(EncounterPhases:ObserveAttempt(attempt, "UNIT_POWER_UPDATE", "boss1"))
    assertEquals(attempt.activePhase, 1)
    assertEquals(#activations, 0)
end

tests["Entombed Sentinels flattens every stored section into pull-relative time"] = function()
    local encounter = PRT.BossTimelineDatabase.encounters[encounterID]

    for _, difficultyID in ipairs({ 14, 15 }) do
        local model = EncounterPhases:GetPlanningModel(encounterID, difficultyID)
        assertTableEquals(model.phases, expectedPhases)
        assertTableEquals(model.occurrences, expectedOccurrences(encounter.difficulties[difficultyID]))
        for index = 2, #model.occurrences do
            assertTrue(model.occurrences[index].time >= model.occurrences[index - 1].time)
        end
    end
end

tests["Entombed Sentinels rejects an unexpected stored phase sequence"] = function()
    local definition = EncounterPhases:GetDefinition(encounterID)
    assertNil(definition.ProjectWCL(14, 2, {
        phaseID = 1,
        name = "Unexpected Active Section",
        isIntermission = false,
        occurrences = {},
    }, {
        spellID = 1284588,
        time = 0,
        observations = 3,
    }))
end

tests["Entombed Sentinels returns empty planning occurrences without stored difficulty data"] = function()
    for _, difficultyID in ipairs({ 17, 16 }) do
        local model = EncounterPhases:GetPlanningModel(encounterID, difficultyID)
        assertTableEquals(model.phases, expectedPhases)
        assertEquals(#model.occurrences, 0)
    end
end

return tests
