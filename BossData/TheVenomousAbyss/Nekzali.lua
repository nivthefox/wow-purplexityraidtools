local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Stage One: Soulcoiler Initiation" },
    { id = 2, name = "Intermission: Ritual of Awakening" },
    { id = 3, name = "Stage Two: Uncoiling" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1285681, time = 3 },
            { spellID = 1284103, time = 28 },
            { spellID = 1287533, time = 53 },
            { spellID = 1287533, time = 54 },
            { spellID = 1287533, time = 55 },
            { spellID = 1284103, time = 64 },
            { spellID = 1285681, time = 77 },
            { spellID = 1284103, time = 99 },
            { spellID = 1287533, time = 121 },
            { spellID = 1287533, time = 122 },
            { spellID = 1287533, time = 124 },
            { spellID = 1284103, time = 135 },
        },
        [2] = {
            { spellID = 1287533, time = 58 },
            { spellID = 1287533, time = 59 },
            { spellID = 1287533, time = 60 },
            { spellID = 1287533, time = 98 },
            { spellID = 1287533, time = 100 },
            { spellID = 1287533, time = 106 },
            { spellID = 1287533, time = 113 },
            { spellID = 1287533, time = 114 },
        },
        [3] = {
            { spellID = 1299673, time = 13 },
            { spellID = 1287533, time = 35 },
            { spellID = 1287533, time = 36 },
            { spellID = 1287533, time = 38 },
            { spellID = 1284103, time = 45 },
            { spellID = 1299673, time = 61 },
            { spellID = 1284103, time = 73 },
            { spellID = 1287533, time = 75 },
            { spellID = 1287533, time = 76 },
            { spellID = 1287533, time = 78 },
            { spellID = 1299673, time = 93 },
            { spellID = 1287533, time = 115 },
            { spellID = 1287533, time = 116 },
            { spellID = 1287533, time = 117 },
            { spellID = 1284103, time = 125 },
            { spellID = 1299673, time = 141 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1285681, time = 3 },
            { spellID = 1284103, time = 28 },
            { spellID = 1287533, time = 53 },
            { spellID = 1287533, time = 54 },
            { spellID = 1287533, time = 55 },
            { spellID = 1284103, time = 64 },
            { spellID = 1285681, time = 78 },
            { spellID = 1284103, time = 99 },
            { spellID = 1287533, time = 121 },
            { spellID = 1287533, time = 122 },
            { spellID = 1287533, time = 124 },
            { spellID = 1284103, time = 135 },
            { spellID = 1285681, time = 148 },
            { spellID = 1284103, time = 170 },
            { spellID = 1287533, time = 193 },
            { spellID = 1287533, time = 195 },
        },
        [2] = {
            { spellID = 1287533, time = 58 },
            { spellID = 1287533, time = 59 },
            { spellID = 1287533, time = 60 },
            { spellID = 1287533, time = 114 },
            { spellID = 1287533, time = 117 },
            { spellID = 1287533, time = 120 },
            { spellID = 1287533, time = 122 },
            { spellID = 1287533, time = 130 },
            { spellID = 1287533, time = 133 },
            { spellID = 1287533, time = 144 },
            { spellID = 1287533, time = 145 },
            { spellID = 1287533, time = 146 },
        },
        [3] = {
            { spellID = 1299673, time = 13 },
            { spellID = 1287533, time = 35 },
            { spellID = 1287533, time = 36 },
            { spellID = 1287533, time = 38 },
            { spellID = 1284103, time = 45 },
            { spellID = 1299673, time = 61 },
            { spellID = 1284103, time = 73 },
            { spellID = 1287533, time = 75 },
            { spellID = 1287533, time = 76 },
            { spellID = 1287533, time = 78 },
            { spellID = 1299673, time = 93 },
            { spellID = 1287533, time = 115 },
            { spellID = 1287533, time = 116 },
            { spellID = 1287533, time = 118 },
            { spellID = 1284103, time = 125 },
            { spellID = 1299673, time = 141 },
            { spellID = 1284103, time = 153 },
            { spellID = 1287533, time = 155 },
            { spellID = 1287533, time = 156 },
            { spellID = 1287533, time = 157 },
            { spellID = 1287533, time = 158 },
            { spellID = 1287533, time = 158 },
            { spellID = 1299673, time = 173 },
        },
    },
    [16] = {
        [1] = {
            { spellID = 1285681, time = 3 },
            { spellID = 1284103, time = 28 },
            { spellID = 1287533, time = 53 },
            { spellID = 1287533, time = 55 },
            { spellID = 1284103, time = 64 },
            { spellID = 1285681, time = 78 },
            { spellID = 1284103, time = 99 },
            { spellID = 1287533, time = 121 },
            { spellID = 1287533, time = 122 },
            { spellID = 1287533, time = 124 },
            { spellID = 1284103, time = 135 },
            { spellID = 1285681, time = 149 },
            { spellID = 1287533, time = 158 },
            { spellID = 1284103, time = 170 },
            { spellID = 1287533, time = 193 },
            { spellID = 1287533, time = 195 },
        },
        [2] = {
            { spellID = 1287533, time = 53 },
            { spellID = 1287533, time = 54 },
            { spellID = 1287533, time = 55 },
            { spellID = 1287533, time = 88 },
            { spellID = 1287533, time = 89 },
            { spellID = 1287533, time = 90 },
            { spellID = 1287533, time = 127 },
            { spellID = 1287533, time = 128 },
            { spellID = 1287533, time = 145 },
            { spellID = 1287533, time = 160 },
            { spellID = 1287533, time = 163 },
        },
        [3] = {
            { spellID = 1299673, time = 13 },
            { spellID = 1287533, time = 35 },
            { spellID = 1287533, time = 36 },
            { spellID = 1287533, time = 38 },
            { spellID = 1284103, time = 45 },
            { spellID = 1299673, time = 61 },
            { spellID = 1284103, time = 73 },
            { spellID = 1287533, time = 75 },
            { spellID = 1287533, time = 76 },
            { spellID = 1287533, time = 78 },
            { spellID = 1299673, time = 93 },
            { spellID = 1287533, time = 115 },
            { spellID = 1287533, time = 116 },
            { spellID = 1287533, time = 118 },
            { spellID = 1284103, time = 125 },
            { spellID = 1299673, time = 141 },
            { spellID = 1284103, time = 153 },
            { spellID = 1287533, time = 155 },
            { spellID = 1287533, time = 156 },
            { spellID = 1287533, time = 158 },
            { spellID = 1287533, time = 158 },
            { spellID = 1299673, time = 173 },
        },
    },
    [17] = {
        [1] = {
            { spellID = 1285681, time = 3 },
            { spellID = 1284103, time = 28 },
            { spellID = 1287533, time = 53 },
            { spellID = 1287533, time = 54 },
            { spellID = 1287533, time = 55 },
            { spellID = 1284103, time = 64 },
            { spellID = 1285681, time = 78 },
            { spellID = 1284103, time = 99 },
        },
        [2] = {
            { spellID = 1287533, time = 58 },
            { spellID = 1287533, time = 59 },
            { spellID = 1287533, time = 60 },
            { spellID = 1287533, time = 103 },
            { spellID = 1287533, time = 107 },
            { spellID = 1287533, time = 107 },
        },
        [3] = {
            { spellID = 1299673, time = 13 },
            { spellID = 1287533, time = 35 },
            { spellID = 1287533, time = 36 },
            { spellID = 1287533, time = 38 },
            { spellID = 1284103, time = 45 },
            { spellID = 1299673, time = 61 },
            { spellID = 1284103, time = 73 },
            { spellID = 1287533, time = 75 },
            { spellID = 1287533, time = 76 },
            { spellID = 1287533, time = 76 },
            { spellID = 1287533, time = 76 },
            { spellID = 1299673, time = 93 },
        },
    },
}

local function GetPhases()
    return PHASES
end

local function Begin(_, _, now)
    return {
        phase = 1,
        now = now,
        ritualCastStartedAt = nil,
        ritualChannelReady = false,
        lastChannelStartedAt = nil,
    }
end

local function Observe(state, event, unit)
    if unit ~= "boss1" or state.phase == 3 then
        return
    end

    local now = state.now()
    if event == "UNIT_SPELLCAST_START" then
        if state.phase == 1 and not state.ritualChannelReady then
            state.ritualCastStartedAt = now
        end
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if state.phase ~= 1 or state.ritualChannelReady or not state.ritualCastStartedAt then
            return
        end
        local castDuration = now - state.ritualCastStartedAt
        state.ritualCastStartedAt = nil
        state.ritualChannelReady = castDuration >= 0 and castDuration < 2
        return
    end

    if event ~= "UNIT_SPELLCAST_CHANNEL_START" then
        return
    end

    if state.phase == 1 then
        if not state.ritualChannelReady then
            return
        end
        state.phase = 2
        state.ritualChannelReady = false
        state.lastChannelStartedAt = now
        return 2
    end

    if now == state.lastChannelStartedAt then
        return
    end
    state.phase = 3
    state.lastChannelStartedAt = now
    return 3
end

assert(BossData:Register(3470, {
    timings = TIMINGS,
    events = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_CHANNEL_START",
    },
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
