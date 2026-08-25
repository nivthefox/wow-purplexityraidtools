local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")

local EncounterPhases = PRT.EncounterPhases
local fixture = dofile("tests/fixtures/encounter_phases.lua")

local function installDefinition(encounterID, observe)
    PRT.BossData = { encounters = { [encounterID] = {} } }
    local candidate = {
        events = { "NOISE", "PHASE_ONE", "PHASE_TWO", "PHASE_THREE", "SCHEDULE" },
        GetPhases = function()
            return EncounterPhases.CopyPhases(fixture.phases)
        end,
        Begin = function(_, schedule)
            return { schedule = schedule, observations = 0 }
        end,
        Observe = observe,
    }
    assertTrue(EncounterPhases:Register(encounterID, candidate))
end

local function harness(encounterID, isSecret)
    local activations = {}
    local scheduled = {}
    local now = 100
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, 16, {
        activate = function(phase, activationTime)
            activations[#activations + 1] = { phase = phase, time = activationTime }
        end,
        isSecret = isSecret,
        now = function()
            return now
        end,
        schedule = function(delay, callback)
            local timer = { delay = delay, callback = callback, cancelled = false }
            function timer:Cancel()
                self.cancelled = true
            end
            scheduled[#scheduled + 1] = timer
            return timer
        end,
    })
    assertNotNil(attempt, err)
    return {
        activations = activations,
        attempt = attempt,
        scheduled = scheduled,
        setNow = function(value)
            now = value
        end,
    }
end

local function observe(state, event)
    state.observations = state.observations + 1
    if event == "PHASE_ONE" then
        return 1
    elseif event == "PHASE_TWO" or event == "TIMER_TWO" then
        return 2
    elseif event == "PHASE_THREE" then
        return 3
    elseif event == "SCHEDULE" then
        state.schedule(5, "TIMER_TWO")
    end
end

tests["ordered observations activate only new later phases at injected times"] = function()
    installDefinition(9201, observe)
    local context = harness(9201)

    for _, observation in ipairs(fixture.observations) do
        context.setNow(100 + #context.activations * 10)
        EncounterPhases:ObserveAttempt(context.attempt, observation.event)
    end

    assertTableEquals(context.activations, {
        { phase = 2, time = 100 },
        { phase = 3, time = 110 },
    })
end

tests["a direct later activation skips intermediate phases"] = function()
    installDefinition(9202, observe)
    local context = harness(9202)
    assertTrue(EncounterPhases:ObserveAttempt(context.attempt, "PHASE_THREE"))
    assertTableEquals(context.activations, { { phase = 3, time = 100 } })
end

tests["scheduled observations expire when their phase or attempt ends"] = function()
    installDefinition(9203, observe)
    local context = harness(9203)

    EncounterPhases:ObserveAttempt(context.attempt, "SCHEDULE")
    assertEquals(#context.scheduled, 1)
    EncounterPhases:ObserveAttempt(context.attempt, "PHASE_THREE")
    assertTrue(context.scheduled[1].cancelled)
    context.scheduled[1].callback()
    assertEquals(#context.activations, 1)

    local second = harness(9203)
    EncounterPhases:ObserveAttempt(second.attempt, "SCHEDULE")
    EncounterPhases:EndAttempt(second.attempt)
    assertTrue(second.scheduled[1].cancelled)
    second.scheduled[1].callback()
    assertEquals(#second.activations, 0)
end

tests["scheduled observations return through the same evaluator"] = function()
    installDefinition(9204, observe)
    local context = harness(9204)
    EncounterPhases:ObserveAttempt(context.attempt, "SCHEDULE")
    context.setNow(105)
    context.scheduled[1].callback()
    assertTableEquals(context.activations, { { phase = 2, time = 105 } })
end

tests["secret values are discarded before the definition receives them"] = function()
    local secret = {}
    installDefinition(9205, function(state, event, value)
        if value == secret then
            error("definition touched a secret")
        end
        return observe(state, event)
    end)
    local context = harness(9205, function(value)
        return value == secret
    end)
    assertFalse(EncounterPhases:ObserveAttempt(context.attempt, "PHASE_TWO", {
        nested = secret,
    }))
    assertEquals(context.attempt.state.observations, 0)
end

tests["fresh attempts never inherit prior state"] = function()
    installDefinition(9206, observe)
    local first = harness(9206)
    EncounterPhases:ObserveAttempt(first.attempt, "PHASE_TWO")
    EncounterPhases:EndAttempt(first.attempt)

    local second = harness(9206)
    assertEquals(second.attempt.activePhase, 1)
    assertEquals(second.attempt.state.observations, 0)
    EncounterPhases:ObserveAttempt(second.attempt, "PHASE_TWO")
    assertTableEquals(second.activations, { { phase = 2, time = 100 } })
end

return tests
