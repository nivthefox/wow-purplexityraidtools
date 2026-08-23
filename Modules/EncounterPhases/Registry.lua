local PRT = PurplexityRaidTools

local EncounterPhases = {
    definitions = {},
    drafts = {},
}
PRT.EncounterPhases = EncounterPhases

local DIFFICULTIES = { 17, 14, 15, 16 }
local DEFINITION_FIELDS = {
    events = true,
    GetPhases = true,
    Begin = true,
    Observe = true,
}
local PHASE_FIELDS = { id = true, name = true }
local UNIT_EVENT_FIELDS = { event = true, unit = true }
local RESERVED_EVENTS = {
    ADDON_LOADED = true,
    ENCOUNTER_END = true,
    ENCOUNTER_START = true,
    GROUP_ROSTER_UPDATE = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
}

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
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
    if count == 0 and not allowEmpty then
        return false
    end
    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end
    return true
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

local function validateEvents(events)
    if not isArray(events, true) then
        return false
    end

    local seen = {}
    for _, declaration in ipairs(events) do
        local event = declaration
        if type(declaration) == "table" then
            if not hasExactFields(declaration, UNIT_EVENT_FIELDS)
                or type(declaration.event) ~= "string"
                or type(declaration.unit) ~= "string"
                or not declaration.unit:match("^boss[1-5]$")
            then
                return false
            end
            event = declaration.event
        end
        if type(event) ~= "string" or event == "" or seen[event] or RESERVED_EVENTS[event] then
            return false
        end
        seen[event] = true
    end
    return true
end

local function validatePhaseModel(phases)
    if not isArray(phases, false) then
        return false
    end
    for index, phase in ipairs(phases) do
        if not hasExactFields(phase, PHASE_FIELDS) then
            return false
        end
        if phase.id ~= index then
            return false
        end
        if type(phase.name) ~= "string" or phase.name == "" then
            return false
        end
    end
    return true
end

local function copyPhases(phases)
    local copy = {}
    for index, phase in ipairs(phases) do
        copy[index] = { id = phase.id, name = phase.name }
    end
    return copy
end

local function getPhases(definition, difficultyID)
    local ok, phases = pcall(definition.GetPhases, difficultyID)
    if not ok or not validatePhaseModel(phases) then
        return nil
    end
    return phases
end

local function encounterExists(encounterID)
    local database = PRT.BossTimelineDatabase
    return database
        and type(database.encounters) == "table"
        and database.encounters[encounterID] ~= nil
end

local function hasMigration(migrations, encounterID, difficultyID)
    return type(migrations) == "table"
        and type(migrations[encounterID]) == "table"
        and migrations[encounterID][difficultyID] == true
end

local function phasesEqual(left, right)
    if #left ~= #right then
        return false
    end
    for index, phase in ipairs(left) do
        local expected = right[index]
        if type(expected) ~= "table"
            or phase.id ~= expected.id
            or phase.name ~= expected.name
        then
            return false
        end
    end
    return true
end

function EncounterPhases:RegisterDraft(encounterID, identifyPhase)
    if not isInteger(encounterID) or encounterID < 1 or type(identifyPhase) ~= "function" then
        return false
    end
    self.drafts[encounterID] = identifyPhase
    return true
end

function EncounterPhases:GetDraftPhaseIdentifier(encounterID)
    return self.drafts[encounterID]
end

function EncounterPhases:Register(encounterID, definition)
    if not isInteger(encounterID) or encounterID < 1 then
        return false, "Encounter ID must be a positive integer."
    end
    if not encounterExists(encounterID) then
        return false, "Encounter is absent from the boss timeline database."
    end
    if not hasExactFields(definition, DEFINITION_FIELDS) then
        return false, "Encounter definition has an invalid contract."
    end
    if not validateEvents(definition.events) then
        return false, "Encounter definition has invalid events."
    end
    if type(definition.GetPhases) ~= "function"
        or type(definition.Begin) ~= "function"
        or type(definition.Observe) ~= "function"
    then
        return false, "Encounter definition methods must be functions."
    end
    for _, difficultyID in ipairs(DIFFICULTIES) do
        if not getPhases(definition, difficultyID) then
            return false, "Encounter definition has an invalid phase model."
        end
    end

    self.definitions[encounterID] = definition
    self.drafts[encounterID] = nil
    return true
end

function EncounterPhases:GetDefinition(encounterID)
    return self.definitions[encounterID]
end

function EncounterPhases:GetPhases(encounterID, difficultyID)
    local definition = self:GetDefinition(encounterID)
    if not definition then
        return nil
    end
    local phases = getPhases(definition, difficultyID)
    if not phases then
        return nil
    end
    return copyPhases(phases)
end

function EncounterPhases:ValidateCompatibility(compatibility, migrations)
    if type(compatibility) ~= "table" then
        return false, "Compatibility fixture must be a table."
    end

    for encounterID, difficulties in pairs(compatibility) do
        if type(difficulties) ~= "table" then
            return false, "Compatibility fixture has invalid difficulties."
        end
        local definition = self:GetDefinition(encounterID)
        for difficultyID, expected in pairs(difficulties) do
            if not hasMigration(migrations, encounterID, difficultyID) then
                local phases = definition and getPhases(definition, difficultyID)
                if not phases or not validatePhaseModel(expected) or not phasesEqual(phases, expected) then
                    return false, "Published phase identities changed without a note migration."
                end
            end
        end
    end
    return true
end

EncounterPhases.DIFFICULTIES = DIFFICULTIES
EncounterPhases.IsInteger = isInteger
EncounterPhases.IsArray = isArray
EncounterPhases.HasExactFields = hasExactFields
EncounterPhases.ValidatePhaseModel = validatePhaseModel
EncounterPhases.CopyPhases = copyPhases
