local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Stage One: Fury of the Serpent Mother" },
    { id = 2, name = "Stage Two: Children of the Doomscale" },
    { id = 3, name = "Intermission: The Shattering" },
    { id = 4, name = "Stage Three: Ula'tek's Ascension" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1298367, time = 10 },
            { spellID = 1296301, time = 35 },
            { spellID = 1298367, time = 72 },
            { spellID = 1296301, time = 76 },
            { spellID = 1286860, time = 130 },
        },
        [2] = {
            { spellID = 1286860, time = 114 },
        },
        [3] = {
        },
        [4] = {
            { spellID = 1300751, time = 5 },
            { spellID = 1298367, time = 10 },
            { spellID = 1295905, time = 25 },
        },
    },
}

local function GetPhases()
    return PHASES
end

local function Begin()
    return {
        phase = 1,
        checkStage = false,
        rageEvents = {},
    }
end

local function RoundTimelineDuration(duration)
    return math.floor(duration + 0.5)
end

local function RememberTimelineEvent(state, eventInfo)
    if type(eventInfo) ~= "table"
        or eventInfo.source ~= 0
        or type(eventInfo.id) ~= "number"
        or type(eventInfo.duration) ~= "number"
    then
        return
    end

    local duration = RoundTimelineDuration(eventInfo.duration)
    if state.phase == 1 then
        if state.checkStage and duration == 118 then
            state.phase = 2
            return 2
        end
        if duration == 129 or duration == 130 then
            state.rageEvents[eventInfo.id] = true
        end
        return
    end
    if state.phase == 2 and duration == 10 then
        state.phase = 3
        return 3
    end
    if state.phase == 3 and (duration == 230 or duration == 235) then
        state.phase = 4
        return 4
    end
end

local function ChangedTimelineEvent(state, eventID)
    if not state.rageEvents[eventID]
        or not C_EncounterTimeline
        or type(C_EncounterTimeline.GetEventState) ~= "function"
    then
        return
    end

    local eventState = C_EncounterTimeline.GetEventState(eventID)
    if eventState == 3 then
        state.rageEvents[eventID] = nil
        return
    end
    if eventState ~= 2 then
        return
    end

    state.rageEvents[eventID] = nil
    state.checkStage = true
end

local function TargetabilityChanged(state, unit)
    if state.phase ~= 1
        or not state.checkStage
        or unit ~= "boss1"
        or type(UnitCanAttack) ~= "function"
        or UnitCanAttack("player", unit)
    then
        return
    end

    state.phase = 2
    state.checkStage = false
    return 2
end

local function Observe(state, event, value)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        return RememberTimelineEvent(state, value)
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        state.rageEvents[value] = nil
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        return ChangedTimelineEvent(state, value)
    end
    if event == "UNIT_TARGETABLE_CHANGED" then
        return TargetabilityChanged(state, value)
    end
end

assert(BossData:Register(3492, {
    timings = TIMINGS,
    events = {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_TARGETABLE_CHANGED", unit = "boss1" },
    },
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
