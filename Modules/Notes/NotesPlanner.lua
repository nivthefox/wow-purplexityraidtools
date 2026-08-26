local PRT = PurplexityRaidTools

local NotesPlanner = {}
PRT.NotesPlanner = NotesPlanner

local PHASE_PAD = 10
local DEFAULT_SCALE = 8
local DEFAULT_TOP_PAD = 6
local DEFAULT_ABILITY_HEIGHT = 30
local DEFAULT_GAP = 4
local DEFAULT_GENERIC_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local DIFFICULTY_OPTIONS = {
    { name = "Normal", value = "Normal", difficultyID = 14 },
    { name = "Heroic", value = "Heroic", difficultyID = 15 },
    { name = "Mythic", value = "Mythic", difficultyID = 16 },
    { name = "LFR", value = "LFR", difficultyID = 17 },
}

local DIFFICULTY_IDS = {
    Normal = 14,
    Heroic = 15,
    Mythic = 16,
    LFR = 17,
}

local function copyTable(value)
    local result = {}
    for key, item in pairs(value) do
        result[key] = item
    end
    return result
end

local function hasReminders(note)
    if type(note) ~= "table" or type(note.reminders) ~= "table" then
        return false
    end
    for _, bucket in pairs(note.reminders) do
        if type(bucket) == "table" and next(bucket) ~= nil then
            return true
        end
    end
    return false
end

local function collectReminderTimes(note)
    local times = {}
    if type(note) ~= "table" or type(note.reminders) ~= "table" then
        return times
    end
    for phaseKey, bucket in pairs(note.reminders) do
        local phase = tonumber(phaseKey)
        if phase and type(bucket) == "table" then
            for _, reminder in ipairs(bucket) do
                local time = type(reminder) == "table" and reminder.time
                if type(time) == "number" and time >= 0 then
                    times[phase] = math.max(times[phase] or 0, time)
                end
            end
        end
    end
    return times
end

local function collectOccurrenceTimes(planningModel)
    local times = {}
    if type(planningModel) ~= "table" or type(planningModel.occurrences) ~= "table" then
        return times
    end
    for _, occurrence in ipairs(planningModel.occurrences) do
        if type(occurrence) == "table"
            and type(occurrence.phase) == "number"
            and type(occurrence.time) == "number"
            and occurrence.time >= 0
        then
            times[occurrence.phase] = math.max(
                times[occurrence.phase] or 0,
                occurrence.time
            )
        end
    end
    return times
end

local function addPhase(phases, known, phaseID, name)
    phases[#phases + 1] = {
        num = phaseID,
        name = name,
    }
    known[phaseID] = true
end

function NotesPlanner:GetDifficultyOptions()
    local result = {}
    for index, option in ipairs(DIFFICULTY_OPTIONS) do
        result[index] = copyTable(option)
    end
    return result
end

function NotesPlanner:GetDifficultyID(difficulty)
    return DIFFICULTY_IDS[difficulty]
end

function NotesPlanner:FormatPhaseTabLabel(index)
    if not index then
        return "All Phases"
    end
    return "Phase " .. index
end

local function hasJournalOrder(choice)
    return type(choice.instanceName) == "string"
        and choice.instanceName ~= ""
        and type(choice.instanceOrder) == "number"
        and type(choice.encounterOrder) == "number"
end

local function sortEncounterChoices(left, right)
    local leftHasJournalOrder = hasJournalOrder(left)
    local rightHasJournalOrder = hasJournalOrder(right)
    if leftHasJournalOrder ~= rightHasJournalOrder then
        return leftHasJournalOrder
    end
    if leftHasJournalOrder then
        if left.instanceOrder ~= right.instanceOrder then
            return left.instanceOrder < right.instanceOrder
        end
        if left.encounterOrder ~= right.encounterOrder then
            return left.encounterOrder < right.encounterOrder
        end
    end
    if left.encounterName ~= right.encounterName then
        return left.encounterName < right.encounterName
    end
    return left.value < right.value
end

function NotesPlanner:BuildEncounterChoices(database, currentEncounterID, resolveEncounter)
    local encounters = type(database) == "table" and database.encounters
    local choices = {}
    local nameCounts = {}

    if type(encounters) == "table" then
        for encounterID in pairs(encounters) do
            if type(encounterID) == "number" then
                local metadata = resolveEncounter and resolveEncounter(encounterID)
                local encounterName = type(metadata) == "table" and metadata.name
                if type(encounterName) ~= "string" or encounterName == "" then
                    encounterName = "Unknown Encounter (" .. encounterID .. ")"
                end
                choices[#choices + 1] = {
                    value = encounterID,
                    encounterName = encounterName,
                    instanceName = type(metadata) == "table" and metadata.instanceName,
                    instanceOrder = type(metadata) == "table" and metadata.instanceOrder,
                    encounterOrder = type(metadata) == "table" and metadata.encounterOrder,
                }
                nameCounts[encounterName] = (nameCounts[encounterName] or 0) + 1
            end
        end
    end

    table.sort(choices, sortEncounterChoices)

    local result = {}
    local currentFound = false
    local currentInstanceOrder
    local hasFallbackHeader = false
    for _, choice in ipairs(choices) do
        if hasJournalOrder(choice) and choice.instanceOrder ~= currentInstanceOrder then
            result[#result + 1] = {
                name = choice.instanceName,
                header = true,
            }
            currentInstanceOrder = choice.instanceOrder
        elseif not hasJournalOrder(choice) and not hasFallbackHeader then
            result[#result + 1] = {
                name = "Other Encounters",
                header = true,
            }
            hasFallbackHeader = true
        end

        local name = choice.encounterName
        if nameCounts[choice.encounterName] > 1 then
            name = choice.encounterName .. " (" .. choice.value .. ")"
        end
        result[#result + 1] = {
            name = name,
            value = choice.value,
            encounterName = choice.encounterName,
        }
        if choice.value == currentEncounterID then
            currentFound = true
        end
    end

    if currentEncounterID and not currentFound then
        if not hasFallbackHeader then
            result[#result + 1] = {
                name = "Other Encounters",
                header = true,
            }
        end
        local name = "Unknown Encounter (" .. currentEncounterID .. ")"
        result[#result + 1] = {
            name = name,
            value = currentEncounterID,
            encounterName = name,
            currentOnly = true,
        }
    end

    return result
end

function NotesPlanner:HasReminders(note)
    return hasReminders(note)
end

function NotesPlanner:IsContextLocked(mode, note, annotationNote)
    if mode == "annotate" then
        return true
    end
    return hasReminders(note) or hasReminders(annotationNote)
end

function NotesPlanner:ValidateImportedContext(currentNote, annotationNote, importedNote, mode)
    if not self:IsContextLocked(mode, currentNote, annotationNote) then
        return true
    end
    if type(currentNote) ~= "table" or type(importedNote) ~= "table" then
        return false, "Encounter cannot change while reminders exist."
    end
    if currentNote.encounterID ~= importedNote.encounterID then
        return false, "Encounter cannot change while reminders exist."
    end
    if mode == "annotate" and currentNote.difficulty ~= importedNote.difficulty then
        return false, "Difficulty cannot change while annotating."
    end
    return true
end

function NotesPlanner:BuildPhases(note, planningModel)
    local reminderTimes = collectReminderTimes(note)
    local occurrenceTimes = collectOccurrenceTimes(planningModel)
    local phases = {}
    local known = {}
    local canonical = type(planningModel) == "table" and planningModel.phases

    if type(canonical) == "table" and #canonical > 0 then
        for _, phase in ipairs(canonical) do
            if type(phase) == "table" and type(phase.id) == "number" then
                addPhase(phases, known, phase.id, phase.name)
            end
        end
    end
    local hasCanonicalPhases = #phases > 0

    local unknown = {}
    for phaseID in pairs(reminderTimes) do
        if not known[phaseID] then
            unknown[#unknown + 1] = phaseID
        end
    end
    table.sort(unknown)

    for _, phaseID in ipairs(unknown) do
        local prefix = hasCanonicalPhases and "Unknown Phase " or "Phase "
        addPhase(phases, known, phaseID, prefix .. phaseID)
    end

    if #phases == 0 then
        addPhase(phases, known, 1, "Phase 1")
    end

    local start = 0
    for _, phase in ipairs(phases) do
        local latest = math.max(
            reminderTimes[phase.num] or 0,
            occurrenceTimes[phase.num] or 0
        )
        phase.start = start
        phase.duration = latest + PHASE_PAD
        start = start + phase.duration
    end

    return phases
end

function NotesPlanner:TimeToY(time, phaseNum, phases, activePhase, scale, topPad)
    scale = scale or DEFAULT_SCALE
    topPad = topPad or DEFAULT_TOP_PAD
    if activePhase == "all" then
        for _, phase in ipairs(phases) do
            if phase.num == phaseNum then
                return (phase.start + time) * scale + topPad
            end
        end
    end
    return time * scale + topPad
end

function NotesPlanner:YToTimeAndPhase(y, phases, activePhase, scale, topPad)
    scale = scale or DEFAULT_SCALE
    topPad = topPad or DEFAULT_TOP_PAD
    local absoluteTime = (y - topPad) / scale
    if activePhase ~= "all" then
        return math.max(0, math.floor(absoluteTime + 0.5)), activePhase
    end
    for index = #phases, 1, -1 do
        local phase = phases[index]
        if absoluteTime >= phase.start then
            return math.max(0, math.floor(absoluteTime - phase.start + 0.5)), phase.num
        end
    end
    return math.max(0, math.floor(absoluteTime + 0.5)), phases[1] and phases[1].num or 1
end

function NotesPlanner:TotalDuration(phases, activePhase)
    if activePhase == "all" then
        local last = phases[#phases]
        if not last then
            return PHASE_PAD
        end
        return last.start + last.duration
    end
    for _, phase in ipairs(phases) do
        if phase.num == activePhase then
            return phase.duration
        end
    end
    return PHASE_PAD
end

function NotesPlanner:AllocateColumns(entries, gap)
    gap = gap or DEFAULT_GAP
    local ordered = {}
    for index, entry in ipairs(entries) do
        ordered[index] = {
            index = index,
            entry = entry,
        }
    end
    table.sort(ordered, function(left, right)
        if left.entry.y ~= right.entry.y then
            return left.entry.y < right.entry.y
        end
        local leftOrder = left.entry.sourceOrder or left.index
        local rightOrder = right.entry.sourceOrder or right.index
        return leftOrder < rightOrder
    end)

    local result = {}
    local columns = {}
    local groupEntries = {}
    local maxColumnCount = 0

    local function FinishGroup()
        local columnCount = #columns
        if columnCount > maxColumnCount then
            maxColumnCount = columnCount
        end
        for _, index in ipairs(groupEntries) do
            result[index].columnCount = columnCount
        end
    end

    for _, item in ipairs(ordered) do
        local entry = copyTable(item.entry)
        local startsNewGroup = #groupEntries > 0
        for _, bottom in ipairs(columns) do
            if entry.y < bottom then
                startsNewGroup = false
                break
            end
        end
        if startsNewGroup then
            FinishGroup()
            columns = {}
            groupEntries = {}
        end

        local column
        for index, bottom in ipairs(columns) do
            if entry.y >= bottom then
                column = index
                break
            end
        end
        if not column then
            column = #columns + 1
        end
        columns[column] = entry.y + entry.height + gap
        entry.column = column - 1
        result[item.index] = entry
        groupEntries[#groupEntries + 1] = item.index
    end

    if #groupEntries > 0 then
        FinishGroup()
    end
    return result, maxColumnCount
end

function NotesPlanner:BuildAbilityEntries(
    planningModel,
    phases,
    activePhase,
    resolveSpell,
    options
)
    options = options or {}
    local scale = options.scale or DEFAULT_SCALE
    local topPad = options.topPad or DEFAULT_TOP_PAD
    local height = options.height or DEFAULT_ABILITY_HEIGHT
    local gap = options.gap or DEFAULT_GAP
    local genericIcon = options.genericIcon or DEFAULT_GENERIC_ICON
    local occurrences = type(planningModel) == "table" and planningModel.occurrences
    local entries = {}

    if type(occurrences) ~= "table" then
        return entries
    end

    for sourceOrder, occurrence in ipairs(occurrences) do
        if activePhase == "all" or occurrence.phase == activePhase then
            local name, icon
            if resolveSpell then
                name, icon = resolveSpell(occurrence.spellID)
            end
            entries[#entries + 1] = {
                phase = occurrence.phase,
                time = occurrence.time,
                spellID = occurrence.spellID,
                name = name or "Unknown Spell (" .. occurrence.spellID .. ")",
                icon = icon or genericIcon,
                y = self:TimeToY(
                    occurrence.time,
                    occurrence.phase,
                    phases,
                    activePhase,
                    scale,
                    topPad
                ),
                height = height,
                sourceOrder = sourceOrder,
                interactive = false,
            }
        end
    end

    return self:AllocateColumns(entries, gap)
end

function NotesPlanner:GetUnavailableMessage(planningModel)
    local occurrences = type(planningModel) == "table" and planningModel.occurrences
    if type(occurrences) == "table" and #occurrences > 0 then
        return nil
    end
    return self.UNAVAILABLE_MESSAGE
end

function NotesPlanner:GetEditorModeState(mode, contextLocked)
    local annotate = mode == "annotate"
    return {
        bossVisible = true,
        abilityInteractive = false,
        encounterEnabled = not annotate and not contextLocked,
        difficultyEnabled = not annotate,
        annotateVisible = not annotate,
        importVisible = not annotate,
        showOnlyMineVisible = annotate,
        bossAffectedByShowOnlyMine = false,
    }
end

local function setVisible(widget, visible)
    if not widget then
        return
    end
    if visible then
        widget:Show()
    else
        widget:Hide()
    end
end

function NotesPlanner:ApplyEditorModeState(modeState, controls)
    setVisible(controls.showOnlyMine, modeState.showOnlyMineVisible)
    setVisible(controls.showOnlyMineLabel, modeState.showOnlyMineVisible)
    setVisible(controls.annotate, modeState.annotateVisible)
    setVisible(controls.import, modeState.importVisible)
    setVisible(controls.boss, modeState.bossVisible)
    controls.encounter:SetEnabled(modeState.encounterEnabled)
    controls.difficulty:SetEnabled(modeState.difficultyEnabled)
end

NotesPlanner.UNAVAILABLE_MESSAGE = "No timeline data is available for this difficulty."
NotesPlanner.PHASE_PAD = PHASE_PAD
