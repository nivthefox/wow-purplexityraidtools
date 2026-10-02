local PRT = PurplexityRaidTools

local NotesCooldowns = {}
PRT.NotesCooldowns = NotesCooldowns

function NotesCooldowns:GetAbility(ability, talents)
    if not ability or not ability.cooldown or ability.cooldown <= 0 then
        return nil
    end

    local cooldown = ability.cooldown
    local charges = ability.charges or 1
    local cooldownFactor, chargesFactor = 1, 1
    for spellID, modifier in pairs(ability.talents or {}) do
        if talents and talents[spellID] then
            cooldown = cooldown + (modifier.cooldown or 0)
            charges = charges + (modifier.charges or 0)
            cooldownFactor = cooldownFactor * (1 + (modifier.cooldown_pct or 0))
            chargesFactor = chargesFactor * (1 + (modifier.charges_pct or 0))
        end
    end
    cooldown = cooldown * cooldownFactor
    if cooldown <= 0 then
        return nil
    end
    return {
        cooldown = cooldown,
        charges = math.max(1, math.floor(charges * chargesFactor)),
    }
end

-- Phase offsets in the editor are display positions, not elapsed encounter time.
-- A use in an earlier phase makes the entering charge state unknown.
function NotesCooldowns:Evaluate(note, resolve, excluded, candidate)
    local entries, phaseKeys = {}, {}
    for key in pairs(note and note.reminders or {}) do
        phaseKeys[#phaseKeys + 1] = key
    end
    table.sort(phaseKeys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)

    local candidateAdded = false
    local function add(reminder, phase)
        local info = resolve(reminder)
        if not info or not info.caster or not info.spellID
            or not info.cooldown or info.cooldown <= 0
            or type(reminder.time) ~= "number" or reminder.time < 0 or not phase then
            return
        end
        entries[#entries + 1] = {
            reminder = reminder, info = info, phase = phase, order = #entries + 1,
        }
    end
    for _, key in ipairs(phaseKeys) do
        for _, reminder in ipairs(note.reminders[key]) do
            if reminder == excluded then
                if candidate then
                    add(candidate, tonumber(candidate.phase or candidate.phaseKey))
                    candidateAdded = true
                end
            else
                add(reminder, tonumber(reminder.phase or key))
            end
        end
    end
    if candidate and not candidateAdded then
        add(candidate, tonumber(candidate.phase or candidate.phaseKey))
    end
    table.sort(entries, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        if a.reminder.time ~= b.reminder.time then return a.reminder.time < b.reminder.time end
        return a.order < b.order
    end)

    local schedules, statuses = {}, {}
    for _, entry in ipairs(entries) do
        local reminder, info = entry.reminder, entry.info
        local key = info.caster:lower() .. ":" .. info.spellID
        local schedule = schedules[key]
        if not schedule then
            schedule = { phase = entry.phase, queue = {} }
            schedules[key] = schedule
        end
        if schedule.phase ~= entry.phase then
            statuses[reminder] = { uncertain = true }
        else
            local queue, time = schedule.queue, reminder.time
            while queue[1] and queue[1].finish <= time do
                table.remove(queue, 1)
            end
            local status = { ready = #queue < (info.charges or 1), phase = entry.phase }
            if status.ready then
                local start = queue[#queue] and queue[#queue].finish or time
                queue[#queue + 1] = { start = time, finish = start + info.cooldown }
                if #queue >= (info.charges or 1) then
                    status.spanStart = time
                    status.recoveryAt = queue[1].finish
                end
            else
                status.readyAt = queue[1].finish
                status.spanStart = queue[1].start
                status.recoveryAt = queue[1].finish
            end
            statuses[reminder] = status
        end
    end
    return statuses
end

function NotesCooldowns:GetGuide(status)
    if not status or not status.recoveryAt then
        return nil
    end
    return { phase = status.phase, start = status.spanStart, finish = status.recoveryAt }
end

function NotesCooldowns:ExtendPhases(phases, guide)
    local start = 0
    for _, phase in ipairs(phases) do
        if guide and phase.num == guide.phase then
            phase.duration = math.max(phase.duration, math.ceil(guide.finish) + 10)
        end
        phase.start = start
        start = start + phase.duration
    end
    return phases
end

return NotesCooldowns
