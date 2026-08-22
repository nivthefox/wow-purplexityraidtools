local PRT = PurplexityRaidTools

local ROOT_FIELDS = { schemaVersion = true, encounters = true }
local ENCOUNTER_FIELDS = { difficulties = true }
local DIFFICULTY_FIELDS = { phases = true }
local PHASE_FIELDS = { phaseID = true, name = true, isIntermission = true, occurrences = true }
local OCCURRENCE_FIELDS = { spellID = true, time = true, observations = true }
local DIFFICULTIES = { [14] = true, [15] = true, [16] = true, [17] = true }

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

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

local function isArray(value, allowEmpty)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if not isInteger(key) or key < 1 then
            return false
        end
        count = count + 1
    end
    if not allowEmpty and count == 0 then
        return false
    end
    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end
    return true
end

local function validateOccurrence(occurrence)
    if not hasExactFields(occurrence, OCCURRENCE_FIELDS) then
        return false
    end
    if not isInteger(occurrence.spellID) or occurrence.spellID < 1 then
        return false
    end
    if not isInteger(occurrence.time) or occurrence.time < 0 then
        return false
    end
    return isInteger(occurrence.observations)
        and occurrence.observations >= 3
        and occurrence.observations <= 30
end

local function validateOccurrences(occurrences)
    if not isArray(occurrences, true) then
        return false
    end
    local previous
    for _, occurrence in ipairs(occurrences) do
        if not validateOccurrence(occurrence) then
            return false
        end
        if previous and (occurrence.time < previous.time
            or (occurrence.time == previous.time and occurrence.spellID < previous.spellID)) then
            return false
        end
        previous = occurrence
    end
    return true
end

local function validatePhase(phase)
    if not hasExactFields(phase, PHASE_FIELDS) then
        return false
    end
    if not isInteger(phase.phaseID) or phase.phaseID < 1 then
        return false
    end
    if type(phase.name) ~= "string" or phase.name == "" then
        return false
    end
    if type(phase.isIntermission) ~= "boolean" then
        return false
    end
    return validateOccurrences(phase.occurrences)
end

local function validateDifficulty(difficulty)
    if not hasExactFields(difficulty, DIFFICULTY_FIELDS) or not isArray(difficulty.phases, false) then
        return false
    end
    for _, phase in ipairs(difficulty.phases) do
        if not validatePhase(phase) then
            return false
        end
    end
    return true
end

local function validateEncounter(encounter)
    if not hasExactFields(encounter, ENCOUNTER_FIELDS) or type(encounter.difficulties) ~= "table" then
        return false
    end
    local count = 0
    for difficultyID, difficulty in pairs(encounter.difficulties) do
        if not DIFFICULTIES[difficultyID] or not validateDifficulty(difficulty) then
            return false
        end
        count = count + 1
    end
    return count > 0
end

local function validateDatabase(database)
    if not hasExactFields(database, ROOT_FIELDS) or database.schemaVersion ~= 1 then
        return false
    end
    if type(database.encounters) ~= "table" then
        return false
    end
    for encounterID, encounter in pairs(database.encounters) do
        if not isInteger(encounterID) or encounterID < 1 or not validateEncounter(encounter) then
            return false
        end
    end
    return true
end

if validateDatabase(PRT.BossTimelineData) then
    PRT.BossTimelineDatabase = PRT.BossTimelineData
    PRT.BossTimelineDatabaseError = nil
else
    PRT.BossTimelineDatabase = nil
    PRT.BossTimelineDatabaseError = "Unsupported or invalid boss timeline database."
end

