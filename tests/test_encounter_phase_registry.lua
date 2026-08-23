local tests = {}
local PRT = PurplexityRaidTools

dofile("Modules/EncounterPhases/Registry.lua")
PRT.BossTimelineDatabase = { encounters = { [3445] = {}, [3470] = {} } }
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
        ProjectWCL = function(_, phaseIndex, _, occurrence)
            return { phase = phaseIndex, time = occurrence.time }
        end,
    }
end

tests["each unfinished Venomous Abyss encounter has an inert phase-identification draft"] = function()
    local encounterIDs = { 3420, 3429, 3492, 3497 }
    for _, encounterID in ipairs(encounterIDs) do
        local identify = EncounterPhases:GetDraftPhaseIdentifier(encounterID)
        assertEquals(type(identify), "function")
        assertNil(identify({}, "ANY_EVENT"))
        assertNil(EncounterPhases:GetDefinition(encounterID))
    end
end

tests["Entombed Sentinels has a completed one-phase definition"] = function()
    assertNil(EncounterPhases:GetDraftPhaseIdentifier(3445))
    assertNotNil(EncounterPhases:GetDefinition(3445))
    assertTableEquals(EncounterPhases:GetPhases(3445, 16), {
        { id = 1, name = "Entombed Sentinels" },
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
