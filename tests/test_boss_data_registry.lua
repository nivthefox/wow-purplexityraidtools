local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("BossData/Registry.lua")

local BossData = PRT.BossData
local EncounterPhases = PRT.EncounterPhases

local function definition()
    return {
        timings = {
            [16] = {
                [1] = {
                    { spellID = 7001, time = 12 },
                },
            },
        },
        events = {},
        GetPhases = function()
            return { { id = 1, name = "Opening" } }
        end,
        Begin = function()
            return {}
        end,
        Observe = function()
        end,
    }
end

tests["registration publishes timings and behavior together"] = function()
    local candidate = definition()
    local ok, err = BossData:Register(5001, candidate)
    assertTrue(ok)
    assertNil(err)
    assertEquals(BossData.encounters[5001], candidate)
    assertNotNil(EncounterPhases:GetDefinition(5001))
end

tests["registration rejects generator-only occurrence fields"] = function()
    local candidate = definition()
    candidate.timings[16][1][1].observations = 3
    local ok = BossData:Register(5002, candidate)
    assertFalse(ok)
    assertNil(BossData.encounters[5002])
    assertNil(EncounterPhases:GetDefinition(5002))
end

tests["registration accepts compound occurrences with ordered tick offsets"] = function()
    local candidate = definition()
    candidate.timings[16][1][1] = {
        spellID = 7001,
        time = 12,
        duration = 4.25,
        ticks = {
            { time = 1.25 },
            { time = 2.25 },
            { time = 3.25 },
        },
    }
    assertTrue(BossData:Register(5007, candidate))
end

tests["registration rejects incomplete or unordered compound occurrences"] = function()
    local missingTicks = definition()
    missingTicks.timings[16][1][1].duration = 4.25
    assertFalse(BossData:Register(5008, missingTicks))

    local unordered = definition()
    unordered.timings[16][1][1] = {
        spellID = 7001,
        time = 12,
        duration = 4.25,
        ticks = { { time = 2 }, { time = 1 } },
    }
    assertFalse(BossData:Register(5009, unordered))

    local extraTickField = definition()
    extraTickField.timings[16][1][1] = {
        spellID = 7001,
        time = 12,
        duration = 4.25,
        ticks = { { time = 1, label = "hit" } },
    }
    assertFalse(BossData:Register(5010, extraTickField))
end

tests["registration rejects unsorted ability timings"] = function()
    local candidate = definition()
    candidate.timings[16][1] = {
        { spellID = 7002, time = 12 },
        { spellID = 7001, time = 12 },
    }
    local ok = BossData:Register(5003, candidate)
    assertFalse(ok)
    assertNil(BossData.encounters[5003])
end

tests["registration rejects timing phases that do not match the phase model"] = function()
    local candidate = definition()
    candidate.timings[16][2] = {}
    local ok = BossData:Register(5004, candidate)
    assertFalse(ok)
    assertNil(BossData.encounters[5004])
end

tests["registration rolls back timings when behavior is invalid"] = function()
    local candidate = definition()
    candidate.events = { { event = "UNIT_SPELLCAST_START", unit = "player" } }
    local ok = BossData:Register(5005, candidate)
    assertFalse(ok)
    assertNil(BossData.encounters[5005])
    assertNil(EncounterPhases:GetDefinition(5005))
end

tests["registration rejects duplicate encounters without replacing the first"] = function()
    local original = definition()
    assertTrue(BossData:Register(5006, original))
    assertFalse(BossData:Register(5006, definition()))
    assertEquals(BossData.encounters[5006], original)
end

return tests
