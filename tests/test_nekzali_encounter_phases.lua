local tests = {}
local PRT = PurplexityRaidTools

PRT.BossTimelineDatabase = {
    encounters = {
        [3445] = { difficulties = {} },
        [3455] = { difficulties = {} },
        [3470] = {
            difficulties = {
                [16] = {
                    phases = {
                        {
                            phaseID = 1,
                            name = "Stage One: Soulcoiler Initiation",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1295124, time = 20, observations = 3 },
                            },
                        },
                        {
                            phaseID = 2,
                            name = "Intermission: Ritual of Awakening",
                            isIntermission = true,
                            occurrences = {
                                { spellID = 1292315, time = 8, observations = 3 },
                            },
                        },
                        {
                            phaseID = 3,
                            name = "Stage Two: Uncoiling",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1289696, time = 12, observations = 3 },
                            },
                        },
                    },
                },
            },
        },
        [3497] = { difficulties = {} },
    },
}
dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("Modules/EncounterPhases/Planning.lua")
dofile("Modules/EncounterPhases/TheVenomousAbyss.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3470
local difficulties = { 17, 14, 15, 16 }
local expectedPhases = {
    { id = 1, name = "Stage One: Soulcoiler Initiation" },
    { id = 2, name = "Intermission: Ritual of Awakening" },
    { id = 3, name = "Stage Two: Uncoiling" },
}

local function harness(difficultyID)
    local activations = {}
    local now = 0
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, difficultyID or 14, {
        activate = function(phase, activationTime)
            activations[#activations + 1] = { phase = phase, time = activationTime }
        end,
        isSecret = function()
            return false
        end,
        now = function()
            return now
        end,
        schedule = function()
        end,
    })
    assertNotNil(attempt, err)
    return {
        activations = activations,
        attempt = attempt,
        observe = function(event, unit)
            return EncounterPhases:ObserveAttempt(attempt, event, unit or "boss1")
        end,
        setNow = function(value)
            now = value
        end,
    }
end

local function expectedOccurrences(difficulty)
    local occurrences = {}
    for phaseIndex, phase in ipairs(difficulty.phases) do
        for _, occurrence in ipairs(phase.occurrences) do
            occurrences[#occurrences + 1] = {
                phase = phaseIndex,
                time = occurrence.time,
                spellID = occurrence.spellID,
            }
        end
    end
    table.sort(occurrences, function(left, right)
        if left.phase ~= right.phase then
            return left.phase < right.phase
        end
        if left.time ~= right.time then
            return left.time < right.time
        end
        return left.spellID < right.spellID
    end)
    return occurrences
end

local function beginRitual(context)
    context.setNow(10)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(11.5)
    context.observe("UNIT_SPELLCAST_SUCCEEDED")
    context.setNow(12.5)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
end

tests["Nekzali exposes stable phases for every raid difficulty"] = function()
    for _, difficultyID in ipairs(difficulties) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
    local compatibility = dofile("tests/fixtures/encounter_phase_compatibility.lua")
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {}))
end

tests["Nekzali declares only the boss cast observations used by its detector"] = function()
    local context = harness()
    assertTableEquals(EncounterPhases:GetAttemptEvents(context.attempt), {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_CHANNEL_START",
    })
end

tests["Ritual of Awakening and Uncoiling activate the canonical phases"] = function()
    local context = harness()
    beginRitual(context)
    context.setNow(40)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, {
        { phase = 2, time = 12.5 },
        { phase = 3, time = 40 },
    })
end

tests["incomplete or unrelated boss casts do not activate the intermission"] = function()
    local context = harness()

    context.setNow(1)
    context.observe("UNIT_SPELLCAST_START", "boss2")
    context.setNow(2.5)
    context.observe("UNIT_SPELLCAST_SUCCEEDED", "boss2")
    context.setNow(3.5)
    context.observe("UNIT_SPELLCAST_CHANNEL_START", "boss2")

    context.setNow(10)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(12)
    context.observe("UNIT_SPELLCAST_SUCCEEDED")
    context.setNow(13)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")

    context.setNow(20)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(21)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")

    assertEquals(#context.activations, 0)
end

tests["duplicate channel delivery does not skip from intermission to stage two"] = function()
    local context = harness()
    beginRitual(context)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, { { phase = 2, time = 12.5 } })

    context.setNow(35)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, {
        { phase = 2, time = 12.5 },
        { phase = 3, time = 35 },
    })
end

tests["fresh Nekzali attempts do not inherit cast recognition state"] = function()
    local first = harness()
    first.setNow(10)
    first.observe("UNIT_SPELLCAST_START")
    first.setNow(11.5)
    first.observe("UNIT_SPELLCAST_SUCCEEDED")
    EncounterPhases:EndAttempt(first.attempt)

    local second = harness()
    second.setNow(12.5)
    second.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertEquals(#second.activations, 0)
end

tests["Nekzali planning preserves stored phase-relative occurrences"] = function()
    local encounter = PRT.BossTimelineDatabase.encounters[encounterID]
    for _, difficultyID in ipairs(difficulties) do
        local model = EncounterPhases:GetPlanningModel(encounterID, difficultyID)
        assertTableEquals(model.phases, expectedPhases)
        local storedDifficulty = encounter.difficulties[difficultyID]
        if storedDifficulty then
            assertTableEquals(model.occurrences, expectedOccurrences(storedDifficulty))
        else
            assertEquals(#model.occurrences, 0)
        end
    end
end

return tests
