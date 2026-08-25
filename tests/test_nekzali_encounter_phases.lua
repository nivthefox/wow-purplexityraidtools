local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
dofile("BossData/Registry.lua")
dofile("Modules/EncounterPhases/Runtime.lua")
dofile("BossData/TheVenomousAbyss/Nekzali.lua")

local EncounterPhases = PRT.EncounterPhases
local encounterID = 3470
local expectedPhases = {
    { id = 1, name = "Stage One: Soulcoiler Initiation" },
    { id = 2, name = "Intermission: Ritual of Awakening" },
    { id = 3, name = "Stage Two: Uncoiling" },
}

local function harness(difficultyID)
    local activations = {}
    local now = 0
    local attempt, err = EncounterPhases:BeginAttempt(encounterID, difficultyID, {
        activate = function(phase, activationTime)
            activations[#activations + 1] = { phase = phase, time = activationTime }
        end,
        isSecret = function()
            return false
        end,
        now = function()
            return now
        end,
        schedule = function()
        end,
    })
    assertNotNil(attempt, err)
    return {
        activations = activations,
        attempt = attempt,
        observe = function(event, unit)
            return EncounterPhases:ObserveAttempt(attempt, event, unit or "boss1")
        end,
        setNow = function(value)
            now = value
        end,
    }
end

local function beginRitual(context)
    context.setNow(10)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(11.5)
    context.observe("UNIT_SPELLCAST_SUCCEEDED")
    context.setNow(12.5)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
end

tests["Nekzali declares its phase topology for every raid difficulty"] = function()
    for _, difficultyID in ipairs({ 17, 14, 15, 16 }) do
        assertTableEquals(EncounterPhases:GetPhases(encounterID, difficultyID), expectedPhases)
    end
end

tests["Nekzali declares only the boss casts used by its phase detector"] = function()
    local context = harness(14)
    assertTableEquals(EncounterPhases:GetAttemptEvents(context.attempt), {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_CHANNEL_START",
    })
end

tests["Ritual of Awakening and Uncoiling activate the canonical phases"] = function()
    local context = harness(16)
    beginRitual(context)
    context.setNow(40)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, {
        { phase = 2, time = 12.5 },
        { phase = 3, time = 40 },
    })
end

tests["incomplete or unrelated boss casts do not activate the intermission"] = function()
    local context = harness(17)

    context.setNow(1)
    context.observe("UNIT_SPELLCAST_START", "boss2")
    context.setNow(2.5)
    context.observe("UNIT_SPELLCAST_SUCCEEDED", "boss2")
    context.setNow(3.5)
    context.observe("UNIT_SPELLCAST_CHANNEL_START", "boss2")

    context.setNow(10)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(12)
    context.observe("UNIT_SPELLCAST_SUCCEEDED")
    context.setNow(13)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")

    context.setNow(20)
    context.observe("UNIT_SPELLCAST_START")
    context.setNow(21)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")

    assertEquals(#context.activations, 0)
end

tests["duplicate channel delivery does not skip from intermission to stage two"] = function()
    local context = harness(15)
    beginRitual(context)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, { { phase = 2, time = 12.5 } })

    context.setNow(35)
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    context.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertTableEquals(context.activations, {
        { phase = 2, time = 12.5 },
        { phase = 3, time = 35 },
    })
end

tests["fresh Nekzali attempts do not inherit cast recognition state"] = function()
    local first = harness(14)
    first.setNow(10)
    first.observe("UNIT_SPELLCAST_START")
    first.setNow(11.5)
    first.observe("UNIT_SPELLCAST_SUCCEEDED")
    EncounterPhases:EndAttempt(first.attempt)

    local second = harness(14)
    second.setNow(12.5)
    second.observe("UNIT_SPELLCAST_CHANNEL_START")
    assertEquals(#second.activations, 0)
end

return tests
