local PRT = PurplexityRaidTools
local EncounterPhases = PRT.EncounterPhases

local function normalizeOccurrence(phaseID, occurrence, sourceOrder)
    if type(occurrence) ~= "table"
        or not EncounterPhases.IsInteger(occurrence.spellID)
        or occurrence.spellID < 1
        or not EncounterPhases.IsInteger(occurrence.time)
        or occurrence.time < 0
    then
        return nil, "Stored occurrence is invalid."
    end

    return {
        phase = phaseID,
        time = occurrence.time,
        spellID = occurrence.spellID,
        sourceOrder = sourceOrder,
    }
end

local function storedPhasesMatch(phases, storedPhases)
    if not EncounterPhases.IsArray(storedPhases, false) or #storedPhases ~= #phases then
        return false
    end
    for index, storedPhase in ipairs(storedPhases) do
        local phase = phases[index]
        if type(storedPhase) ~= "table"
            or storedPhase.phaseID ~= phase.id
            or storedPhase.name ~= phase.name
            or type(storedPhase.isIntermission) ~= "boolean"
            or not EncounterPhases.IsArray(storedPhase.occurrences, true)
        then
            return false
        end
    end
    return true
end

local function occurrenceSort(left, right)
    if left.phase ~= right.phase then
        return left.phase < right.phase
    end
    if left.time ~= right.time then
        return left.time < right.time
    end
    if left.spellID ~= right.spellID then
        return left.spellID < right.spellID
    end
    return left.sourceOrder < right.sourceOrder
end

function EncounterPhases:GetPlanningModel(encounterID, difficultyID)
    local definition = self:GetDefinition(encounterID)
    if not definition then
        return nil
    end

    local phases = self:GetPhases(encounterID, difficultyID)
    if not phases then
        return nil, "Encounter phase model is invalid."
    end

    local occurrences = {}
    local sourceOrder = 0
    local database = PRT.BossTimelineDatabase
    local encounter = database and database.encounters and database.encounters[encounterID]
    local difficulty = encounter
        and encounter.difficulties
        and encounter.difficulties[difficultyID]
    if difficulty then
        if type(difficulty) ~= "table" or not storedPhasesMatch(phases, difficulty.phases) then
            return nil, "Stored phases do not match the encounter phase model."
        end
        for _, phase in ipairs(difficulty.phases) do
            for _, occurrence in ipairs(phase.occurrences) do
                sourceOrder = sourceOrder + 1
                local normalized, err = normalizeOccurrence(
                    phase.phaseID,
                    occurrence,
                    sourceOrder
                )
                if not normalized then
                    return nil, err
                end
                occurrences[#occurrences + 1] = normalized
            end
        end
    end

    table.sort(occurrences, occurrenceSort)
    for _, occurrence in ipairs(occurrences) do
        occurrence.sourceOrder = nil
    end

    return {
        encounterID = encounterID,
        difficultyID = difficultyID,
        phases = phases,
        occurrences = occurrences,
    }
end
