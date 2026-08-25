local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("BossData/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("BossData/TheVenomousAbyss/TheCoiledAltar.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3429
local expectedPhases = {
    { id = 1, name = "Stage One: Serpent's Bargain" },
    { id = 2, name = "Stage Two: Usurper's Reprisal" },
    { id = 3, name = "Intermission: The Claimed Vessel" },
    { id = 4, name = "Stage Three: Coiled Union" },
}

local function harness(difficultyID)
    local activations = {}
    local eventStates = {}
    local now = 0
    C_EncounterTimeline = {
        GetEventState = function(eventID)
            return eventStates[eventID]
        end,
    }
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, difficultyID, {
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
        cancelTimeline = function(id)
            eventStates[id] = 3
            return EncounterPhases:ObserveAttempt(attempt, "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", id)
        end,
        observe = function(event, value)
            return EncounterPhases:ObserveAttempt(attempt, event, value)
        end,
        setNow = function(value)
            now = value
        end,
    }
end

tests["The Coiled Altar declares its phase topology for every raid difficulty"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15, 16 }) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
end

tests["The Coiled Altar declares only the observations used by its phase detector"] = function()
    local context = harness(14)
    assertTableEquals(EncounterPhases:GetAttemptEvents(context.attempt), {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "boss2" },
    })
end

tests["a completed Fangs cycle does not masquerade as Zuljan dying"] = function()
    local context = harness(14)
    context.addTimeline(1, 12)
    context.addTimeline(2, 85)
    context.addTimeline(3, 12)
    context.cancelTimeline(2)
    assertEquals(#context.activations, 0)

    context.addTimeline(4, 85)
    context.setNow(100)
    context.cancelTimeline(4)
    assertTableEquals(context.activations, { { phase = 2, time = 100 } })
end

tests["timeline cancellations and the boss2 channel stop activate all phases"] = function()
    local context = harness(15)
    context.addTimeline(1, 12)
    context.addTimeline(2, 85)
    context.setNow(100)
    context.cancelTimeline(2)

    context.addTimeline(3, 70)
    context.setNow(200)
    context.cancelTimeline(3)

    context.setNow(234)
    context.observe("UNIT_SPELLCAST_CHANNEL_STOP", "boss1")
    context.observe("UNIT_SPELLCAST_CHANNEL_STOP", "boss2")
    assertTableEquals(context.activations, {
        { phase = 2, time = 100 },
        { phase = 3, time = 200 },
        { phase = 4, time = 234 },
    })
end

tests["unrelated and removed timeline events cannot advance the encounter"] = function()
    local context = harness(16)
    context.addTimeline(1, 85, 1)
    context.cancelTimeline(1)

    context.addTimeline(2, 84)
    context.cancelTimeline(2)

    context.addTimeline(3, 85)
    context.observe("ENCOUNTER_TIMELINE_EVENT_REMOVED", 3)
    context.cancelTimeline(3)
    assertEquals(#context.activations, 0)
end

return tests
