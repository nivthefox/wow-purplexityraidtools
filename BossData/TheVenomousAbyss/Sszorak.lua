local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Sszorak" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1277025, time = 9 },
            { spellID = 1305959, time = 36 },
            { spellID = 1285425, time = 50 },
            { spellID = 1277025, time = 68 },
            { spellID = 1305959, time = 95 },
            { spellID = 1285425, time = 108 },
            { spellID = 1277025, time = 161 },
            { spellID = 1305959, time = 188 },
            { spellID = 1285425, time = 202 },
            { spellID = 1277025, time = 220 },
            { spellID = 1305959, time = 247 },
            { spellID = 1285425, time = 260 },
            { spellID = 1277025, time = 313 },
            { spellID = 1305959, time = 340 },
            { spellID = 1285425, time = 354 },
            { spellID = 1277025, time = 372 },
            { spellID = 1305959, time = 399 },
            { spellID = 1285425, time = 412 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1277025, time = 9 },
            { spellID = 1305959, time = 32 },
            { spellID = 1285425, time = 44 },
            { spellID = 1277025, time = 61 },
            { spellID = 1305959, time = 84 },
            { spellID = 1285425, time = 96 },
            { spellID = 1277025, time = 147 },
            { spellID = 1305959, time = 170 },
            { spellID = 1285425, time = 182 },
            { spellID = 1277025, time = 199 },
            { spellID = 1305959, time = 223 },
            { spellID = 1285425, time = 234 },
            { spellID = 1277025, time = 285 },
            { spellID = 1305959, time = 308 },
            { spellID = 1285425, time = 320 },
            { spellID = 1277025, time = 337 },
            { spellID = 1305959, time = 361 },
            { spellID = 1285425, time = 373 },
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

assert(BossData:Register(3420, {
    timings = TIMINGS,
    events = {},
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
