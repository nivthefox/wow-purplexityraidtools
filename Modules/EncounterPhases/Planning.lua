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
    local bossData = PRT.BossData
    local encounter = bossData and bossData.encounters and bossData.encounters[encounterID]
    local difficulty = encounter and encounter.timings and encounter.timings[difficultyID]
    if difficulty then
        if not EncounterPhases.IsArray(difficulty, false) or #difficulty ~= #phases then
            return nil, "Stored ability timings do not match the encounter phase model."
        end
        for phaseID, phaseOccurrences in ipairs(difficulty) do
            if not EncounterPhases.IsArray(phaseOccurrences, true) then
                return nil, "Stored ability timings are invalid."
            end
            for _, occurrence in ipairs(phaseOccurrences) do
                sourceOrder = sourceOrder + 1
                local normalized, err = normalizeOccurrence(
                    phaseID,
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
