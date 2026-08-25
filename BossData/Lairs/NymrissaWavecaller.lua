local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Nymrissa Wavecaller" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1260837, time = 8 },
            { spellID = 1257717, time = 18 },
            { spellID = 1282937, time = 27 },
            { spellID = 1313393, time = 35 },
            { spellID = 1260837, time = 41 },
            { spellID = 1282937, time = 49 },
            { spellID = 1282937, time = 71 },
            { spellID = 1313393, time = 79 },
            { spellID = 1260837, time = 85 },
            { spellID = 1282937, time = 93 },
            { spellID = 1257717, time = 128 },
            { spellID = 1282937, time = 137 },
            { spellID = 1313393, time = 145 },
            { spellID = 1260837, time = 151 },
            { spellID = 1282937, time = 159 },
            { spellID = 1282937, time = 181 },
            { spellID = 1313393, time = 189 },
            { spellID = 1260837, time = 195 },
            { spellID = 1282937, time = 203 },
            { spellID = 1257717, time = 238 },
            { spellID = 1282937, time = 247 },
            { spellID = 1313393, time = 255 },
            { spellID = 1260837, time = 261 },
            { spellID = 1282937, time = 269 },
            { spellID = 1282937, time = 291 },
            { spellID = 1313393, time = 299 },
            { spellID = 1260837, time = 305 },
            { spellID = 1282937, time = 313 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1260837, time = 8 },
            { spellID = 1257717, time = 18 },
            { spellID = 1282937, time = 27 },
            { spellID = 1313393, time = 35 },
            { spellID = 1260837, time = 41 },
            { spellID = 1282937, time = 49 },
            { spellID = 1282937, time = 71 },
            { spellID = 1313393, time = 79 },
            { spellID = 1260837, time = 85 },
            { spellID = 1282937, time = 93 },
            { spellID = 1257717, time = 128 },
            { spellID = 1282937, time = 137 },
            { spellID = 1313393, time = 145 },
            { spellID = 1260837, time = 151 },
            { spellID = 1282937, time = 159 },
            { spellID = 1282937, time = 181 },
            { spellID = 1313393, time = 189 },
            { spellID = 1260837, time = 195 },
            { spellID = 1282937, time = 203 },
            { spellID = 1257717, time = 238 },
            { spellID = 1282937, time = 247 },
            { spellID = 1313393, time = 255 },
            { spellID = 1260837, time = 261 },
            { spellID = 1282937, time = 269 },
            { spellID = 1282937, time = 291 },
            { spellID = 1313393, time = 299 },
            { spellID = 1260837, time = 305 },
            { spellID = 1282937, time = 313 },
            { spellID = 1257717, time = 348 },
            { spellID = 1282937, time = 357 },
            { spellID = 1313393, time = 365 },
            { spellID = 1260837, time = 371 },
            { spellID = 1282937, time = 379 },
            { spellID = 1282937, time = 401 },
            { spellID = 1313393, time = 409 },
            { spellID = 1260837, time = 415 },
            { spellID = 1282937, time = 423 },
        },
    },
    [17] = {
        [1] = {
            { spellID = 1260837, time = 8 },
            { spellID = 1257717, time = 18 },
            { spellID = 1282937, time = 27 },
            { spellID = 1313393, time = 35 },
            { spellID = 1260837, time = 41 },
            { spellID = 1282937, time = 49 },
            { spellID = 1282937, time = 71 },
            { spellID = 1313393, time = 79 },
            { spellID = 1260837, time = 85 },
            { spellID = 1282937, time = 93 },
            { spellID = 1257717, time = 128 },
            { spellID = 1282937, time = 137 },
            { spellID = 1313393, time = 145 },
            { spellID = 1260837, time = 151 },
            { spellID = 1282937, time = 159 },
            { spellID = 1282937, time = 181 },
            { spellID = 1313393, time = 189 },
            { spellID = 1260837, time = 195 },
            { spellID = 1282937, time = 203 },
            { spellID = 1257717, time = 238 },
            { spellID = 1282937, time = 247 },
        },
    },
}

local function GetPhases()
    return PHASES
end

local function Begin()
    return {}
end

local function Observe()
end

assert(BossData:Register(3379, {
    timings = TIMINGS,
    events = {},
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
