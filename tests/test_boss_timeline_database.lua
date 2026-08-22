local tests = {}

local modulePath = "Modules/BossTimelineDatabase.lua"

local function load(database)
    PurplexityRaidTools.BossTimelineData = database
    PurplexityRaidTools.BossTimelineDatabase = nil
    PurplexityRaidTools.BossTimelineDatabaseError = nil
    dofile(modulePath)
end

local function validDatabase()
    return {
        schemaVersion = 1,
        encounters = {
            [5001] = {
                difficulties = {
                    [16] = {
                        phases = {
                            {
                                phaseID = 1,
                                name = "One",
                                isIntermission = false,
                                occurrences = {
                                    { spellID = 7001, time = 12, observations = 3 },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

tests["supported bundled database loads without external dependencies"] = function()
    local database = validDatabase()
    load(database)
    assertEquals(PurplexityRaidTools.BossTimelineDatabase, database)
    assertNil(PurplexityRaidTools.BossTimelineDatabaseError)
end

tests["unsupported schema is rejected instead of interpreted as version one"] = function()
    local database = validDatabase()
    database.schemaVersion = 2
    load(database)
    assertNil(PurplexityRaidTools.BossTimelineDatabase)
    assertNotNil(PurplexityRaidTools.BossTimelineDatabaseError)
end

tests["unknown fields and invalid nested values are rejected"] = function()
    local database = validDatabase()
    database.encounters[5001].difficulties[16].phases[1].provenance = {}
    load(database)
    assertNil(PurplexityRaidTools.BossTimelineDatabase)

    database = validDatabase()
    database.encounters[5001].difficulties[16].phases[1].occurrences[1].observations = 2
    load(database)
    assertNil(PurplexityRaidTools.BossTimelineDatabase)
end

tests["empty phase occurrence arrays remain valid"] = function()
    local database = validDatabase()
    database.encounters[5001].difficulties[16].phases[1].occurrences = {}
    load(database)
    assertEquals(PurplexityRaidTools.BossTimelineDatabase, database)
end

return tests
