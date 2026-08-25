local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Stage One: Serpent's Bargain" },
    { id = 2, name = "Stage Two: Usurper's Reprisal" },
    { id = 3, name = "Intermission: The Claimed Vessel" },
    { id = 4, name = "Stage Three: Coiled Union" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1282487, time = 0 },
            { spellID = 1299960, time = 2 },
            { spellID = 1283832, time = 12 },
            { spellID = 1299684, time = 23 },
            { spellID = 1299684, time = 40 },
            { spellID = 1283485, time = 42 },
            { spellID = 1283489, time = 42 },
            { spellID = 1299960, time = 44 },
            { spellID = 1299684, time = 61 },
            { spellID = 1299684, time = 77 },
            { spellID = 1282487, time = 85 },
            { spellID = 1299960, time = 87 },
            { spellID = 1283832, time = 97 },
            { spellID = 1299684, time = 108 },
            { spellID = 1299684, time = 125 },
        },
        [2] = {
            { spellID = 1285643, time = 8 },
            { spellID = 1286620, time = 36 },
            { spellID = 1285643, time = 43 },
            { spellID = 1286620, time = 69 },
            { spellID = 1286918, time = 78 },
            { spellID = 1285643, time = 93 },
            { spellID = 1286620, time = 121 },
            { spellID = 1285643, time = 128 },
        },
        [3] = {
        },
        [4] = {
            { spellID = 1298381, time = 3 },
            { spellID = 1299960, time = 5 },
            { spellID = 1307292, time = 35 },
            { spellID = 1286918, time = 37 },
            { spellID = 1299960, time = 46 },
            { spellID = 1285643, time = 58 },
            { spellID = 1307292, time = 63 },
            { spellID = 1307292, time = 93 },
            { spellID = 1298381, time = 95 },
            { spellID = 1299960, time = 96 },
            { spellID = 1286918, time = 124 },
            { spellID = 1307292, time = 126 },
            { spellID = 1299960, time = 133 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1282487, time = 0 },
            { spellID = 1299960, time = 2 },
            { spellID = 1283832, time = 12 },
            { spellID = 1299684, time = 23 },
            { spellID = 1299684, time = 40 },
            { spellID = 1283485, time = 43 },
            { spellID = 1283489, time = 43 },
            { spellID = 1299960, time = 45 },
            { spellID = 1299684, time = 60 },
            { spellID = 1299684, time = 77 },
            { spellID = 1282487, time = 85 },
            { spellID = 1299960, time = 87 },
            { spellID = 1283832, time = 97 },
            { spellID = 1299684, time = 108 },
            { spellID = 1299684, time = 125 },
            { spellID = 1283485, time = 128 },
            { spellID = 1283489, time = 128 },
            { spellID = 1299960, time = 130 },
            { spellID = 1299684, time = 145 },
        },
        [2] = {
            { spellID = 1285643, time = 8 },
            { spellID = 1286441, time = 21 },
            { spellID = 1286620, time = 38 },
            { spellID = 1285643, time = 44 },
            { spellID = 1286441, time = 54 },
            { spellID = 1286620, time = 69 },
            { spellID = 1286918, time = 78 },
            { spellID = 1285643, time = 93 },
            { spellID = 1286441, time = 106 },
            { spellID = 1286620, time = 123 },
        },
        [3] = {
        },
        [4] = {
            { spellID = 1298381, time = 3 },
            { spellID = 1299960, time = 5 },
            { spellID = 1299266, time = 20 },
            { spellID = 1307292, time = 39 },
            { spellID = 1286918, time = 42 },
            { spellID = 1299960, time = 52 },
            { spellID = 1285643, time = 66 },
            { spellID = 1307292, time = 71 },
            { spellID = 1307292, time = 106 },
            { spellID = 1298381, time = 108 },
            { spellID = 1299960, time = 110 },
            { spellID = 1286918, time = 142 },
            { spellID = 1307292, time = 144 },
            { spellID = 1299960, time = 152 },
            { spellID = 1285643, time = 167 },
            { spellID = 1307292, time = 176 },
            { spellID = 1299266, time = 190 },
            { spellID = 1285643, time = 210 },
            { spellID = 1298381, time = 213 },
            { spellID = 1299960, time = 214 },
        },
    },
}

local function GetPhases()
    return PHASES
end

local function Begin()
    return {
        phase = 1,
        axegrinderCount = 1,
        coiledAltarCount = 1,
        timelineEvents = {},
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
        if duration == 12 then
            state.axegrinderCount = state.axegrinderCount + 1
        elseif duration == 85 then
            state.coiledAltarCount = state.coiledAltarCount + 1
            state.timelineEvents[eventInfo.id] = {
                nextPhase = 2,
                cycle = state.coiledAltarCount,
            }
        end
    elseif state.phase == 2 and duration == 70 then
        state.timelineEvents[eventInfo.id] = { nextPhase = 3 }
    end
end

local function CanceledTimelineEvent(state, eventID)
    if not C_EncounterTimeline or type(C_EncounterTimeline.GetEventState) ~= "function" then
        return
    end
    if C_EncounterTimeline.GetEventState(eventID) ~= 3 then
        return
    end

    local timelineEvent = state.timelineEvents[eventID]
    state.timelineEvents[eventID] = nil
    if not timelineEvent or timelineEvent.nextPhase <= state.phase then
        return
    end
    if timelineEvent.nextPhase == 2 and state.axegrinderCount > timelineEvent.cycle then
        return
    end

    state.phase = timelineEvent.nextPhase
    return timelineEvent.nextPhase
end

local function Observe(state, event, value)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        RememberTimelineEvent(state, value)
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        state.timelineEvents[value] = nil
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        return CanceledTimelineEvent(state, value)
    end
    if event ~= "UNIT_SPELLCAST_CHANNEL_STOP" or value ~= "boss2" or state.phase ~= 3 then
        return
    end

    state.phase = 4
    return 4
end

assert(BossData:Register(3429, {
    timings = TIMINGS,
    events = {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "boss2" },
    },
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
