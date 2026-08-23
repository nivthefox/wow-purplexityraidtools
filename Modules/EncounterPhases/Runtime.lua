local PRT = PurplexityRaidTools
local EncounterPhases = PRT.EncounterPhases

local function containsSecret(value, isSecret, seen)
    if not isSecret then
        return false
    end
    if isSecret(value) then
        return true
    end
    if type(value) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[value] then
        return false
    end
    seen[value] = true
    for key, nested in pairs(value) do
        if containsSecret(key, isSecret, seen) or containsSecret(nested, isSecret, seen) then
            return true
        end
    end
    return false
end

local function cancelHandle(handle)
    if type(handle) == "function" then
        handle()
    elseif type(handle) == "table" and type(handle.Cancel) == "function" then
        handle:Cancel()
    end
end

local function cancelTimers(attempt)
    for _, timer in ipairs(attempt.timers) do
        cancelHandle(timer.handle)
    end
    attempt.timers = {}
end

local function eventIsDeclared(attempt, event)
    return attempt.eventSet[event] == true
end

local function argumentsContainSecret(attempt, ...)
    local seen = {}
    for index = 1, select("#", ...) do
        if containsSecret(select(index, ...), attempt.callbacks.isSecret, seen) then
            return true
        end
    end
    return false
end

local evaluate

local function scheduleObservation(attempt, delay, event, ...)
    if not attempt.active or type(attempt.callbacks.schedule) ~= "function" then
        return false
    end
    if type(delay) ~= "number" or delay < 0 or type(event) ~= "string" or event == "" then
        return false
    end

    local phase = attempt.activePhase
    local generation = attempt.generation
    local args = { n = select("#", ...), ... }
    local handle = attempt.callbacks.schedule(delay, function()
        if not attempt.active
            or attempt.activePhase ~= phase
            or attempt.generation ~= generation
        then
            return
        end
        evaluate(attempt, event, true, unpack(args, 1, args.n))
    end)
    attempt.timers[#attempt.timers + 1] = { handle = handle }
    return true
end

evaluate = function(attempt, event, scheduled, ...)
    if not attempt or not attempt.active then
        return false
    end
    if not scheduled and not eventIsDeclared(attempt, event) then
        return false
    end
    if argumentsContainSecret(attempt, ...) then
        return false
    end

    local ok, nextPhase = pcall(attempt.definition.Observe, attempt.state, event, ...)
    if not ok then
        return false, nextPhase
    end
    if nextPhase == nil then
        return false
    end
    if not EncounterPhases.IsInteger(nextPhase) or not attempt.phaseIDs[nextPhase] then
        return false, "Encounter definition returned an invalid phase."
    end
    if nextPhase <= attempt.activePhase then
        return false
    end

    attempt.activePhase = nextPhase
    attempt.generation = attempt.generation + 1
    cancelTimers(attempt)
    attempt.callbacks.activate(nextPhase, attempt.callbacks.now())
    return true
end

function EncounterPhases:BeginAttempt(encounterID, difficultyID, callbacks)
    local definition = self:GetDefinition(encounterID)
    if not definition then
        return nil
    end
    if type(callbacks) ~= "table"
        or type(callbacks.now) ~= "function"
        or type(callbacks.activate) ~= "function"
    then
        return nil, "Encounter phase callbacks are invalid."
    end

    local phases = self:GetPhases(encounterID, difficultyID)
    if not phases then
        return nil, "Encounter phase model is invalid."
    end

    local attempt = {
        active = true,
        activePhase = 1,
        callbacks = callbacks,
        definition = definition,
        events = {},
        eventSet = {},
        generation = 1,
        phaseIDs = {},
        timers = {},
    }
    for _, phase in ipairs(phases) do
        attempt.phaseIDs[phase.id] = true
    end
    for index, declaration in ipairs(definition.events) do
        local event = declaration
        if type(declaration) == "table" then
            event = declaration.event
            attempt.events[index] = { event = declaration.event, unit = declaration.unit }
        else
            attempt.events[index] = declaration
        end
        attempt.eventSet[event] = true
    end

    local ok, state = pcall(
        definition.Begin,
        difficultyID,
        function(delay, event, ...)
            return scheduleObservation(attempt, delay, event, ...)
        end,
        callbacks.now
    )
    if not ok or type(state) ~= "table" then
        attempt.active = false
        cancelTimers(attempt)
        return nil, ok and "Encounter definition returned invalid state." or state
    end
    attempt.state = state
    return attempt
end

function EncounterPhases:ObserveAttempt(attempt, event, ...)
    return evaluate(attempt, event, false, ...)
end

function EncounterPhases:EndAttempt(attempt)
    if not attempt or not attempt.active then
        return false
    end
    attempt.active = false
    attempt.generation = attempt.generation + 1
    cancelTimers(attempt)
    attempt.state = nil
    return true
end

function EncounterPhases:GetAttemptEvents(attempt)
    if not attempt or not attempt.active then
        return {}
    end
    local events = {}
    for index, declaration in ipairs(attempt.events) do
        if type(declaration) == "table" then
            events[index] = { event = declaration.event, unit = declaration.unit }
        else
            events[index] = declaration
        end
    end
    return events
end
