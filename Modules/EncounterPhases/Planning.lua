local PRT = PurplexityRaidTools
local EncounterPhases = PRT.EncounterPhases

local MAPPING_FIELDS = { phase = true, time = true }

local function projectOccurrence(definition, difficultyID, phaseIndex, phase, occurrence, phaseIDs, sourceOrder)
    if type(occurrence) ~= "table"
        or not EncounterPhases.IsInteger(occurrence.spellID)
        or occurrence.spellID < 1
    then
        return nil, "Stored occurrence is invalid."
    end

    local ok, mapping = pcall(
        definition.ProjectWCL,
        difficultyID,
        phaseIndex,
        phase,
        occurrence
    )
    if not ok
        or not EncounterPhases.HasExactFields(mapping, MAPPING_FIELDS)
        or not EncounterPhases.IsInteger(mapping.phase)
        or not phaseIDs[mapping.phase]
        or type(mapping.time) ~= "number"
        or mapping.time < 0
    then
        return nil, "Stored occurrence could not be projected."
    end

    return {
        phase = mapping.phase,
        time = mapping.time,
        spellID = occurrence.spellID,
        sourceOrder = sourceOrder,
    }
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

    local phaseIDs = {}
    for _, phase in ipairs(phases) do
        phaseIDs[phase.id] = true
    end

    local occurrences = {}
    local sourceOrder = 0
    local database = PRT.BossTimelineDatabase
    local encounter = database and database.encounters and database.encounters[encounterID]
    local difficulty = encounter
        and encounter.difficulties
        and encounter.difficulties[difficultyID]
    if difficulty then
        for phaseIndex, phase in ipairs(difficulty.phases) do
            for _, occurrence in ipairs(phase.occurrences) do
                sourceOrder = sourceOrder + 1
                local projected, err = projectOccurrence(
                    definition,
                    difficultyID,
                    phaseIndex,
                    phase,
                    occurrence,
                    phaseIDs,
                    sourceOrder
                )
                if not projected then
                    return nil, err
                end
                occurrences[#occurrences + 1] = projected
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
