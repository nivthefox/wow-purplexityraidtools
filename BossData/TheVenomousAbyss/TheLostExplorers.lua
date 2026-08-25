local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "The Lost Explorers" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1291933, time = 20 },
            { spellID = 1291933, time = 24 },
            { spellID = 1295854, time = 30 },
            { spellID = 1291933, time = 51 },
            { spellID = 1291933, time = 55 },
            { spellID = 1292779, time = 60 },
            { spellID = 1291933, time = 83 },
            { spellID = 1291933, time = 90 },
            { spellID = 1295854, time = 91 },
            { spellID = 1292104, time = 101 },
            { spellID = 1296249, time = 111 },
            { spellID = 1291933, time = 114 },
            { spellID = 1291933, time = 123 },
            { spellID = 1291933, time = 145 },
            { spellID = 1295854, time = 151 },
            { spellID = 1291933, time = 152 },
            { spellID = 1297022, time = 162 },
            { spellID = 1291933, time = 176 },
            { spellID = 1291933, time = 185 },
            { spellID = 1292104, time = 185 },
            { spellID = 1296249, time = 192 },
            { spellID = 1291933, time = 201 },
            { spellID = 1295854, time = 206 },
            { spellID = 1291933, time = 208 },
            { spellID = 1291933, time = 244 },
            { spellID = 1292779, time = 247 },
            { spellID = 1291933, time = 252 },
            { spellID = 1291933, time = 266 },
            { spellID = 1295854, time = 270 },
            { spellID = 1291933, time = 283 },
            { spellID = 1291933, time = 297 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1291933, time = 20 },
            { spellID = 1291933, time = 24 },
            { spellID = 1295854, time = 30 },
            { spellID = 1291933, time = 51 },
            { spellID = 1291933, time = 55 },
            { spellID = 1292779, time = 61 },
            { spellID = 1291933, time = 83 },
            { spellID = 1291933, time = 87 },
            { spellID = 1295854, time = 93 },
            { spellID = 1292104, time = 102 },
            { spellID = 1296249, time = 112 },
            { spellID = 1291933, time = 114 },
            { spellID = 1291933, time = 118 },
            { spellID = 1291933, time = 145 },
            { spellID = 1291933, time = 149 },
            { spellID = 1295854, time = 153 },
            { spellID = 1291933, time = 176 },
            { spellID = 1291933, time = 180 },
            { spellID = 1297022, time = 181 },
            { spellID = 1291933, time = 202 },
            { spellID = 1291933, time = 207 },
            { spellID = 1295854, time = 213 },
            { spellID = 1291933, time = 233 },
            { spellID = 1291933, time = 238 },
            { spellID = 1291933, time = 267 },
            { spellID = 1291933, time = 272 },
            { spellID = 1295854, time = 273 },
            { spellID = 1291933, time = 298 },
            { spellID = 1292104, time = 299 },
            { spellID = 1296249, time = 301 },
            { spellID = 1291933, time = 303 },
            { spellID = 1292779, time = 303 },
            { spellID = 1295854, time = 332 },
            { spellID = 1291933, time = 333 },
            { spellID = 1291933, time = 349 },
            { spellID = 1291933, time = 397 },
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

assert(BossData:Register(3497, {
    timings = TIMINGS,
    events = {},
    GetPhases = GetPhases,
    Begin = Begin,
    Observe = Observe,
}))
