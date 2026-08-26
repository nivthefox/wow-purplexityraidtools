local PRT = PurplexityRaidTools
local EncounterPhases = PRT.EncounterPhases

local BossData = {
    encounters = {},
}
PRT.BossData = BossData

local SUPPORTED_DIFFICULTIES = { [14] = true, [15] = true, [16] = true, [17] = true }
local DEFINITION_FIELDS = {
    timings = true,
    events = true,
    GetPhases = true,
    Begin = true,
    Observe = true,
}
local OCCURRENCE_FIELDS = { spellID = true, time = true }
local COMPOUND_OCCURRENCE_FIELDS = {
    spellID = true,
    time = true,
    duration = true,
    ticks = true,
}
local TICK_FIELDS = { time = true }

local function hasExactFields(value, fields)
    if type(value) ~= "table" then
        return false
    end
    for field in pairs(value) do
        if not fields[field] then
            return false
        end
    end
    for field in pairs(fields) do
        if value[field] == nil then
            return false
        end
    end
    return true
end

local function validateOccurrence(occurrence)
    local simple = hasExactFields(occurrence, OCCURRENCE_FIELDS)
    local compound = hasExactFields(occurrence, COMPOUND_OCCURRENCE_FIELDS)
    if not simple and not compound then
        return false
    end
    if not EncounterPhases.IsInteger(occurrence.spellID) or occurrence.spellID <= 0 then
        return false
    end
    if not EncounterPhases.IsInteger(occurrence.time) or occurrence.time < 0 then
        return false
    end
    if simple then
        return true
    end
    if type(occurrence.duration) ~= "number" or occurrence.duration <= 0
        or not EncounterPhases.IsArray(occurrence.ticks, false)
    then
        return false
    end

    local previousTime = 0
    for _, tick in ipairs(occurrence.ticks) do
        if not hasExactFields(tick, TICK_FIELDS)
            or type(tick.time) ~= "number"
            or tick.time <= previousTime
        then
            return false
        end
        previousTime = tick.time
    end
    return true
end

local function validateOccurrences(occurrences)
    if not EncounterPhases.IsArray(occurrences, true) then
        return false
    end

    local previous
    for _, occurrence in ipairs(occurrences) do
        if not validateOccurrence(occurrence) then
            return false
        end
        if previous and (occurrence.time < previous.time
            or (occurrence.time == previous.time and occurrence.spellID < previous.spellID))
        then
            return false
        end
        previous = occurrence
    end
    return true
end

local function getPhases(definition, difficultyID)
    local ok, phases = pcall(definition.GetPhases, difficultyID)
    if not ok or not EncounterPhases.ValidatePhaseModel(phases) then
        return nil
    end
    return phases
end

local function validateTimings(definition)
    if type(definition.timings) ~= "table" then
        return false
    end

    local count = 0
    for difficultyID, phaseTimings in pairs(definition.timings) do
        local phases = SUPPORTED_DIFFICULTIES[difficultyID]
            and getPhases(definition, difficultyID)
        if not phases
            or not EncounterPhases.IsArray(phaseTimings, false)
            or #phaseTimings ~= #phases
        then
            return false
        end
        for _, occurrences in ipairs(phaseTimings) do
            if not validateOccurrences(occurrences) then
                return false
            end
        end
        count = count + 1
    end
    return count > 0
end

function BossData:Register(encounterID, definition)
    if not EncounterPhases.IsInteger(encounterID) or encounterID < 1 then
        return false, "Encounter ID must be a positive integer."
    end
    if self.encounters[encounterID] or EncounterPhases:GetDefinition(encounterID) then
        return false, "Encounter is already registered."
    end
    if not hasExactFields(definition, DEFINITION_FIELDS) then
        return false, "Boss definition has an invalid contract."
    end
    if type(definition.GetPhases) ~= "function"
        or type(definition.Begin) ~= "function"
        or type(definition.Observe) ~= "function"
    then
        return false, "Boss definition methods must be functions."
    end
    if not validateTimings(definition) then
        return false, "Boss definition has invalid ability timings."
    end

    self.encounters[encounterID] = definition
    local ok, err = EncounterPhases:Register(encounterID, {
        events = definition.events,
        GetPhases = definition.GetPhases,
        Begin = definition.Begin,
        Observe = definition.Observe,
    })
    if not ok then
        self.encounters[encounterID] = nil
        return false, err
    end
    return true
end
