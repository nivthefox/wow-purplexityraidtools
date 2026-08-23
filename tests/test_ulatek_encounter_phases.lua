local tests = {}
local PRT = PurplexityRaidTools

PRT.BossTimelineDatabase = {
    encounters = {
        [3379] = { difficulties = {} },
        [3420] = { difficulties = {} },
        [3421] = { difficulties = {} },
        [3429] = { difficulties = {} },
        [3445] = { difficulties = {} },
        [3455] = { difficulties = {} },
        [3470] = { difficulties = {} },
        [3492] = {
            difficulties = {
                [16] = {
                    phases = {
                        {
                            phaseID = 1,
                            name = "Stage One: Fury of the Serpent Mother",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1298367, time = 10, observations = 3 },
                            },
                        },
                        {
                            phaseID = 2,
                            name = "Stage Two: Children of the Doomscale",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1290779, time = 10, observations = 3 },
                            },
                        },
                        {
                            phaseID = 3,
                            name = "Intermission: The Shattering",
                            isIntermission = true,
                            occurrences = {
                                { spellID = 1299010, time = 10, observations = 3 },
                            },
                        },
                        {
                            phaseID = 4,
                            name = "Stage Three: Ula'tek's Ascension",
                            isIntermission = false,
                            occurrences = {
                                { spellID = 1300751, time = 5, observations = 3 },
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
local encounterID = 3492
local difficulties = { 17, 14, 15, 16 }
local expectedPhases = {
    { id = 1, name = "Stage One: Fury of the Serpent Mother" },
    { id = 2, name = "Stage Two: Children of the Doomscale" },
    { id = 3, name = "Intermission: The Shattering" },
    { id = 4, name = "Stage Three: Ula'tek's Ascension" },
}

local function harness(difficultyID)
    local activations = {}
    local eventStates = {}
    local now = 0
    local attackable = true
    C_EncounterTimeline = {
        GetEventState = function(eventID)
            return eventStates[eventID]
        end,
    }
    UnitCanAttack = function(_, unit)
        return unit == "boss1" and attackable
    end
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
    })
    assertNotNil(attempt, err)
    return {
        activations = activations,
        attempt = attempt,
        addTimeline = function(id, duration, source)
            return EncounterPhases:ObserveAttempt(attempt, "ENCOUNTER_TIMELINE_EVENT_ADDED", {
                id = id,
                duration = duration,
                source = source or 0,
            })
        end,
        finishTimeline = function(id)
            eventStates[id] = 2
            return EncounterPhases:ObserveAttempt(attempt, "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", id)
        end,
        removeTimeline = function(id)
            return EncounterPhases:ObserveAttempt(attempt, "ENCOUNTER_TIMELINE_EVENT_REMOVED", id)
        end,
        setAttackable = function(value)
            attackable = value
        end,
        setNow = function(value)
            now = value
        end,
        targetabilityChanged = function(unit)
            return EncounterPhases:ObserveAttempt(attempt, "UNIT_TARGETABLE_CHANGED", unit or "boss1")
        end,
    }
end

local function activateStageTwo(context)
    context.addTimeline(1, 130)
    context.finishTimeline(1)
    context.setAttackable(false)
    context.setNow(136.5)
    context.targetabilityChanged()
end

tests["Ula'tek exposes stable phases for every raid difficulty"] = function()
    for _, difficultyID in ipairs(difficulties) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
    local compatibility = dofile("tests/fixtures/encounter_phase_compatibility.lua")
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {}))
end

tests["Ula'tek declares only the targetability and timeline observations used by BigWigs"] = function()
    local context = harness()
    assertTableEquals(EncounterPhases:GetAttemptEvents(context.attempt), {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_TARGETABLE_CHANGED", unit = "boss1" },
    })
end

tests["Rage targetability and timeline additions activate all four phases"] = function()
    local context = harness()
    activateStageTwo(context)
    context.setNow(310)
    context.addTimeline(2, 10)
    context.setNow(363)
    context.addTimeline(3, 230)
    assertTableEquals(context.activations, {
        { phase = 2, time = 136.5 },
        { phase = 3, time = 310 },
        { phase = 4, time = 363 },
    })
end

tests["the next Rage timer backs up targetability and Heroic Fury activates stage three"] = function()
    local context = harness(15)
    context.addTimeline(1, 129)
    context.finishTimeline(1)
    context.setNow(165)
    context.addTimeline(2, 118)
    context.setNow(310)
    context.addTimeline(3, 10)
    context.setNow(363)
    context.addTimeline(4, 235)
    assertTableEquals(context.activations, {
        { phase = 2, time = 165 },
        { phase = 3, time = 310 },
        { phase = 4, time = 363 },
    })
end

tests["unrelated, removed, and premature signals cannot advance Ula'tek"] = function()
    local context = harness()
    context.addTimeline(1, 130, 1)
    context.finishTimeline(1)
    context.addTimeline(2, 130)
    context.removeTimeline(2)
    context.finishTimeline(2)
    context.setAttackable(false)
    context.targetabilityChanged("boss2")
    context.addTimeline(3, 10)
    context.addTimeline(4, 230)
    assertEquals(#context.activations, 0)
end

tests["Ula'tek planning preserves stored phase-relative occurrences"] = function()
    local model = EncounterPhases:GetPlanningModel(encounterID, 16)
    assertTableEquals(model.phases, expectedPhases)
    assertTableEquals(model.occurrences, {
        { phase = 1, time = 10, spellID = 1298367 },
        { phase = 2, time = 10, spellID = 1290779 },
        { phase = 3, time = 10, spellID = 1299010 },
        { phase = 4, time = 5, spellID = 1300751 },
    })
end

return tests
