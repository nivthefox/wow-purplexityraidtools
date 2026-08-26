local PRT = PurplexityRaidTools

local NotesBossTimeline = {}
PRT.NotesBossTimeline = NotesBossTimeline

local function clearReminder(reminder)
    reminder.bossDuration = nil
    reminder.bossTicks = nil
end

local function occurrenceKey(phase, time, spellID)
    return tostring(phase) .. "\0" .. tostring(time) .. "\0" .. tostring(spellID)
end

local function copyTicks(ticks)
    local result = {}
    for index, tick in ipairs(ticks) do
        result[index] = { time = tick.time }
    end
    return result
end

function NotesBossTimeline.Apply(_, note, planningModel)
    if type(note) ~= "table" or type(note.reminders) ~= "table" then
        return
    end

    local compound = {}
    local occurrences = type(planningModel) == "table" and planningModel.occurrences
    if type(occurrences) == "table" then
        for _, occurrence in ipairs(occurrences) do
            if type(occurrence.ticks) == "table" and #occurrence.ticks > 0 then
                compound[occurrenceKey(
                    occurrence.phase,
                    occurrence.time,
                    occurrence.spellID
                )] = occurrence
            end
        end
    end

    for phaseKey, reminders in pairs(note.reminders) do
        if type(reminders) == "table" then
            for _, reminder in ipairs(reminders) do
                clearReminder(reminder)
                local occurrence = compound[occurrenceKey(
                    tonumber(phaseKey),
                    reminder.time,
                    reminder.bossSpell
                )]
                if occurrence then
                    reminder.bossDuration = occurrence.duration
                    reminder.bossTicks = copyTicks(occurrence.ticks)
                end
            end
        end
    end
end

function NotesBossTimeline.GetBarTimeline(_, reminder)
    if type(reminder) ~= "table"
        or reminder.displayType ~= "Bar"
        or type(reminder.duration) ~= "number"
        or type(reminder.bossTicks) ~= "table"
        or #reminder.bossTicks == 0
    then
        return nil
    end

    local lastTick = reminder.bossTicks[#reminder.bossTicks]
    if type(lastTick) ~= "table" or type(lastTick.time) ~= "number" then
        return nil
    end

    local totalDuration = reminder.duration + lastTick.time
    if totalDuration <= 0 then
        return nil
    end

    local ticks = {}
    for index, tick in ipairs(reminder.bossTicks) do
        ticks[index] = {
            time = tick.time,
            progress = (reminder.duration + tick.time) / totalDuration,
        }
    end

    return {
        duration = totalDuration,
        postDuration = lastTick.time,
        ticks = ticks,
    }
end
