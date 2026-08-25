local PRT = PurplexityRaidTools
local BossData = PRT.BossData

local PHASES = {
    { id = 1, name = "Vashnik the Malignant" },
}

local TIMINGS = {
    [14] = {
        [1] = {
            { spellID = 1280935, time = 8 },
            { spellID = 1281910, time = 13 },
            { spellID = 1284663, time = 24 },
            { spellID = 1280935, time = 26 },
            { spellID = 1282117, time = 32 },
            { spellID = 1281910, time = 34 },
            { spellID = 1280935, time = 59 },
            { spellID = 1282117, time = 64 },
            { spellID = 1281910, time = 70 },
            { spellID = 1280935, time = 89 },
            { spellID = 1281910, time = 96 },
            { spellID = 1284663, time = 108 },
            { spellID = 1280935, time = 110 },
            { spellID = 1282117, time = 117 },
            { spellID = 1281910, time = 118 },
            { spellID = 1280935, time = 143 },
            { spellID = 1282117, time = 149 },
            { spellID = 1281910, time = 154 },
            { spellID = 1280935, time = 173 },
            { spellID = 1281910, time = 180 },
            { spellID = 1284663, time = 192 },
            { spellID = 1280935, time = 194 },
            { spellID = 1282117, time = 201 },
            { spellID = 1281910, time = 202 },
            { spellID = 1280935, time = 227 },
            { spellID = 1282117, time = 232 },
            { spellID = 1281910, time = 238 },
            { spellID = 1280935, time = 257 },
            { spellID = 1281910, time = 264 },
            { spellID = 1284663, time = 276 },
            { spellID = 1280935, time = 278 },
            { spellID = 1282117, time = 284 },
            { spellID = 1281910, time = 286 },
            { spellID = 1280935, time = 311 },
            { spellID = 1282117, time = 317 },
            { spellID = 1281910, time = 322 },
            { spellID = 1280935, time = 341 },
            { spellID = 1281910, time = 348 },
        },
    },
    [15] = {
        [1] = {
            { spellID = 1280935, time = 8 },
            { spellID = 1281910, time = 13 },
            { spellID = 1284663, time = 24 },
            { spellID = 1282509, time = 30 },
            { spellID = 1280935, time = 37 },
            { spellID = 1282117, time = 42 },
            { spellID = 1281910, time = 54 },
            { spellID = 1280935, time = 64 },
            { spellID = 1282509, time = 69 },
            { spellID = 1281910, time = 87 },
            { spellID = 1280935, time = 92 },
            { spellID = 1282117, time = 94 },
            { spellID = 1284663, time = 108 },
            { spellID = 1282509, time = 114 },
            { spellID = 1280935, time = 121 },
            { spellID = 1282117, time = 127 },
            { spellID = 1281910, time = 138 },
            { spellID = 1280935, time = 148 },
            { spellID = 1282509, time = 153 },
            { spellID = 1281910, time = 171 },
            { spellID = 1280935, time = 176 },
            { spellID = 1282117, time = 178 },
            { spellID = 1284663, time = 192 },
            { spellID = 1282509, time = 198 },
            { spellID = 1280935, time = 205 },
            { spellID = 1282117, time = 211 },
            { spellID = 1281910, time = 222 },
            { spellID = 1280935, time = 232 },
            { spellID = 1282509, time = 237 },
            { spellID = 1281910, time = 255 },
            { spellID = 1280935, time = 260 },
            { spellID = 1282117, time = 263 },
            { spellID = 1284663, time = 276 },
            { spellID = 1282509, time = 282 },
            { spellID = 1280935, time = 289 },
            { spellID = 1282117, time = 294 },
            { spellID = 1281910, time = 306 },
            { spellID = 1280935, time = 316 },
            { spellID = 1282509, time = 321 },
            { spellID = 1281910, time = 339 },
            { spellID = 1280935, time = 344 },
            { spellID = 1282117, time = 346 },
            { spellID = 1284663, time = 360 },
            { spellID = 1282509, time = 366 },
            { spellID = 1280935, time = 373 },
            { spellID = 1282117, time = 379 },
            { spellID = 1281910, time = 390 },
            { spellID = 1280935, time = 400 },
            { spellID = 1282509, time = 405 },
            { spellID = 1281910, time = 423 },
            { spellID = 1280935, time = 428 },
            { spellID = 1282117, time = 431 },
            { spellID = 1284663, time = 444 },
            { spellID = 1282117, time = 463 },
            { spellID = 1281910, time = 474 },
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
