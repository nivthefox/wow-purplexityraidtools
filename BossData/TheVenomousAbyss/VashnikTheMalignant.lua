local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Vashnik the Malignant" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1280935, time = 8 },
            { spellID = 1280935, time = 26 },
            { spellID = 1280935, time = 59 },
            { spellID = 1280935, time = 89 },
            { spellID = 1280935, time = 110 },
            { spellID = 1280935, time = 143 },
            { spellID = 1280935, time = 173 },
            { spellID = 1280935, time = 194 },
            { spellID = 1280935, time = 227 },
            { spellID = 1280935, time = 257 },
            { spellID = 1280935, time = 278 },
            { spellID = 1280935, time = 311 },
            { spellID = 1280935, time = 341 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1280935, time = 8 },
            { spellID = 1282509, time = 30 },
            { spellID = 1280935, time = 37 },
            { spellID = 1280935, time = 64 },
            { spellID = 1282509, time = 69 },
            { spellID = 1280935, time = 92 },
            { spellID = 1282509, time = 114 },
            { spellID = 1280935, time = 121 },
            { spellID = 1280935, time = 148 },
            { spellID = 1282509, time = 153 },
            { spellID = 1280935, time = 176 },
            { spellID = 1282509, time = 198 },
            { spellID = 1280935, time = 205 },
            { spellID = 1280935, time = 232 },
            { spellID = 1282509, time = 237 },
            { spellID = 1280935, time = 260 },
            { spellID = 1282509, time = 282 },
            { spellID = 1280935, time = 289 },
            { spellID = 1280935, time = 316 },
            { spellID = 1282509, time = 321 },
            { spellID = 1280935, time = 344 },
            { spellID = 1282509, time = 366 },
            { spellID = 1280935, time = 373 },
            { spellID = 1280935, time = 400 },
            { spellID = 1282509, time = 405 },
            { spellID = 1280935, time = 428 },
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

assert(BossData:Register(3455, {
    timings = TIMINGS,
    events = {},
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
