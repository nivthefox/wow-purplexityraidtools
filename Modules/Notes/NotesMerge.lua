local PRT = PurplexityRaidTools
local NotesMerge = {}
PRT.NotesMerge = NotesMerge

local function deepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function reminderKey(reminder)
    return tostring(reminder.phase) .. "\0" .. tostring(reminder.time) .. "\0" .. tostring(reminder.text)
end

local function hasReminders(note)
    if not note then
        return false
    end
    for _, bucket in pairs(note.reminders) do
        if #bucket > 0 then
            return true
        end
    end
    return false
end

local function sortBucketByTime(bucket)
    table.sort(bucket, function(a, b)
        return a.time < b.time
    end)
end

local function reminderComesBefore(a, b)
    local aPhase = tonumber(a.phase) or 1
    local bPhase = tonumber(b.phase) or 1
    if aPhase ~= bPhase then
        return aPhase < bPhase
    end
    return (a.time or 0) < (b.time or 0)
end

local function insertReminderLineChronologically(lines, reminder)
    local insertAt = #lines + 1
    for i, entry in ipairs(lines) do
        if entry.type == "reminder" and reminderComesBefore(reminder, entry.reminder) then
            insertAt = i
            break
        end
    end
    table.insert(lines, insertAt, { type = "reminder", reminder = reminder })
end

local OVERRIDE_FIELDS = { "displayType", "sound", "tts", "ttsTimer", "countdown" }

function NotesMerge:Merge(canonicalNote, annotationNote)
    if not hasReminders(annotationNote) then
        return deepCopy(canonicalNote), {}
    end

    local merged = deepCopy(canonicalNote)
    local orphans = {}
    local overridden = {}

    for _, bucket in pairs(annotationNote.reminders) do
        for _, annReminder in ipairs(bucket) do
            local key = reminderKey(annReminder)
            local matched = false

            local canonBucket = merged.reminders[annReminder.phaseKey]
            if canonBucket then
                for i, canonReminder in ipairs(canonBucket) do
                    local canonKey = reminderKey(canonReminder)
                    if canonKey == key and not overridden[canonBucket[i]] then
                        for _, field in ipairs(OVERRIDE_FIELDS) do
                            if annReminder[field] ~= nil then
                                canonReminder[field] = annReminder[field]
                            end
                        end
                        canonReminder.isAnnotated = true
                        overridden[canonBucket[i]] = true
                        matched = true
                        break
                    end
                end
            end

            if not matched then
                local personal = deepCopy(annReminder)
                personal.isPersonal = true

                local phaseBucket = merged.reminders[personal.phaseKey]
                if not phaseBucket then
                    phaseBucket = {}
                    merged.reminders[personal.phaseKey] = phaseBucket
                end
                phaseBucket[#phaseBucket + 1] = personal
                sortBucketByTime(phaseBucket)

                insertReminderLineChronologically(merged.lines, personal)
            end
        end
    end

    return merged, orphans
end
