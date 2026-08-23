local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
PRT.BossTimelineDatabase = { encounters = { [3379] = {}, [3420] = {}, [3421] = {}, [3429] = {}, [3445] = {}, [3455] = {}, [3470] = {}, [3492] = {}, [3497] = {} } }
dofile("Modules/EncounterPhases/TheVenomousAbyss.lua")

local EncounterPhases = PRT.EncounterPhases
local fixture = dofile("tests/fixtures/encounter_phases.lua")

local function copyPhases()
    return EncounterPhases.CopyPhases(fixture.phases)
end

local function definition(getPhases)
    return {
        events = { "FAKE_EVENT" },
        GetPhases = getPhases or copyPhases,
        Begin = function()
            return {}
        end,
        Observe = function()
        end,
    }
end

tests["The Coiled Altar has a completed four-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3429))
    assertNotNil(EncounterPhases:GetDefinition(3429))
    assertTableEquals(EncounterPhases:GetPhases(3429, 16), {
        { id = 1, name = "Stage One: Serpent's Bargain" },
        { id = 2, name = "Stage Two: Usurper's Reprisal" },
        { id = 3, name = "Intermission: The Claimed Vessel" },
        { id = 4, name = "Stage Three: Coiled Union" },
    })
end

tests["Nymrissa has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3379))
    assertNotNil(EncounterPhases:GetDefinition(3379))
    assertTableEquals(EncounterPhases:GetPhases(3379, 16), {
        { id = 1, name = "Nymrissa Wavecaller" },
    })
end

tests["Ula'tek has a completed four-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3492))
    assertNotNil(EncounterPhases:GetDefinition(3492))
    assertTableEquals(EncounterPhases:GetPhases(3492, 16), {
        { id = 1, name = "Stage One: Fury of the Serpent Mother" },
        { id = 2, name = "Stage Two: Children of the Doomscale" },
        { id = 3, name = "Intermission: The Shattering" },
        { id = 4, name = "Stage Three: Ula'tek's Ascension" },
    })
end

tests["Entombed Sentinels has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3445))
    assertNotNil(EncounterPhases:GetDefinition(3445))
    assertTableEquals(EncounterPhases:GetPhases(3445, 16), {
        { id = 1, name = "Entombed Sentinels" },
    })
end

tests["Sszorak has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3420))
    assertNotNil(EncounterPhases:GetDefinition(3420))
    assertTableEquals(EncounterPhases:GetPhases(3420, 16), {
        { id = 1, name = "Sszorak" },
    })
end

tests["The Twin Fangs has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3421))
    assertNotNil(EncounterPhases:GetDefinition(3421))
    assertTableEquals(EncounterPhases:GetPhases(3421, 16), {
        { id = 1, name = "The Twin Fangs" },
    })
end

tests["Vashnik has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3455))
    assertNotNil(EncounterPhases:GetDefinition(3455))
    assertTableEquals(EncounterPhases:GetPhases(3455, 16), {
        { id = 1, name = "Vashnik the Malignant" },
    })
end

tests["Nekzali has a completed three-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3470))
    assertNotNil(EncounterPhases:GetDefinition(3470))
    assertTableEquals(EncounterPhases:GetPhases(3470, 16), {
        { id = 1, name = "Stage One: Soulcoiler Initiation" },
        { id = 2, name = "Intermission: Ritual of Awakening" },
        { id = 3, name = "Stage Two: Uncoiling" },
    })
end

tests["The Lost Explorers has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3497))
    assertNotNil(EncounterPhases:GetDefinition(3497))
    assertTableEquals(EncounterPhases:GetPhases(3497, 16), {
        { id = 1, name = "The Lost Explorers" },
    })
end

tests["registration requires an encounter in the bundled timeline database"] = function()
    PRT.BossTimelineDatabase = { encounters = {} }
    local ok = EncounterPhases:Register(9101, definition())
    assertFalse(ok)
end

tests["registration accepts a complete definition for all raid difficulties"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9102] = {} } }
    local candidate = definition()
    local ok, err = EncounterPhases:Register(9102, candidate)
    assertTrue(ok)
    assertNil(err)
    assertEquals(EncounterPhases:GetDefinition(9102), candidate)
    assertTableEquals(EncounterPhases:GetPhases(9102, 16), fixture.phases)
end

tests["registration accepts only narrow boss unit event declarations"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9107] = {}, [9108] = {} } }
    local candidate = definition()
    candidate.events = { { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "boss2" } }
    assertTrue(EncounterPhases:Register(9107, candidate))

    local invalid = definition()
    invalid.events = { { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "player" } }
    assertFalse(EncounterPhases:Register(9108, invalid))
end

tests["registration rejects the obsolete WCL projection field"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9106] = {} } }
    local candidate = definition()
    candidate.ProjectWCL = function()
    end
    assertFalse(EncounterPhases:Register(9106, candidate))
end

tests["registration rejects a missing or non-contiguous difficulty phase model"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9103] = {}, [9104] = {} } }

    local missing = definition(function(difficultyID)
        if difficultyID == 17 then
            return nil
        end
        return copyPhases()
    end)
    assertFalse(EncounterPhases:Register(9103, missing))

    local nonContiguous = definition(function()
        return {
            { id = 1, name = "Opening" },
            { id = 3, name = "Finale" },
        }
    end)
    assertFalse(EncounterPhases:Register(9104, nonContiguous))
end

tests["published identities require an explicit migration before they change"] = function()
    PRT.BossTimelineDatabase = { encounters = { [9105] = {} } }
    assertTrue(EncounterPhases:Register(9105, definition()))

    local compatibility = {
        [9105] = {
            [16] = {
                { id = 1, name = "Opening" },
                { id = 2, name = "Old Intermission" },
                { id = 3, name = "Finale" },
            },
        },
    }
    assertFalse(EncounterPhases:ValidateCompatibility(compatibility, {}))
    assertTrue(EncounterPhases:ValidateCompatibility(compatibility, {
        [9105] = { [16] = true },
    }))
end

return tests
