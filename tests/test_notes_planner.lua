local PRT = PurplexityRaidTools

if not PRT.NotesPlanner then
    dofile("Modules/Notes/NotesPlanner.lua")
end

local Planner = PRT.NotesPlanner
local tests = {}

local function makeNote(reminders)
    return {
        encounterID = 9001,
        difficulty = "Mythic",
        reminders = reminders or {},
        lines = {},
    }
end

tests["encounter choices are grouped by raid in journal order"] = function()
    local database = {
        encounters = {
            [9003] = {},
            [9001] = {},
            [9002] = {},
            [9004] = {},
        },
    }
    local metadata = {
        [9001] = {
            name = "Third Boss",
            instanceName = "First Raid",
            instanceOrder = 1,
            encounterOrder = 3,
        },
        [9002] = {
            name = "First Boss",
            instanceName = "First Raid",
            instanceOrder = 1,
            encounterOrder = 1,
        },
        [9003] = {
            name = "Only Boss",
            instanceName = "Second Raid",
            instanceOrder = 2,
            encounterOrder = 1,
        },
    }

    local choices = Planner:BuildEncounterChoices(database, nil, function(encounterID)
        return metadata[encounterID]
    end)

    assertTableEquals(choices, {
        { name = "First Raid", header = true },
        { name = "First Boss", value = 9002, encounterName = "First Boss" },
        { name = "Third Boss", value = 9001, encounterName = "Third Boss" },
        { name = "Second Raid", header = true },
        { name = "Only Boss", value = 9003, encounterName = "Only Boss" },
        { name = "Other Encounters", header = true },
        {
            name = "Unknown Encounter (9004)",
            value = 9004,
            encounterName = "Unknown Encounter (9004)",
        },
    })
end

tests["duplicate encounter names remain distinguishable across raid groups"] = function()
    local database = { encounters = { [9001] = {}, [9002] = {} } }
    local metadata = {
        [9001] = {
            name = "Shared",
            instanceName = "First Raid",
            instanceOrder = 1,
            encounterOrder = 1,
        },
        [9002] = {
            name = "Shared",
            instanceName = "Second Raid",
            instanceOrder = 2,
            encounterOrder = 1,
        },
    }

    local choices = Planner:BuildEncounterChoices(database, nil, function(encounterID)
        return metadata[encounterID]
    end)

    assertTableEquals(choices, {
        { name = "First Raid", header = true },
        { name = "Shared (9001)", value = 9001, encounterName = "Shared" },
        { name = "Second Raid", header = true },
        { name = "Shared (9002)", value = 9002, encounterName = "Shared" },
    })
end

tests["an unknown current encounter is preserved beside database choices"] = function()
    local database = { encounters = { [9001] = {} } }
    local choices = Planner:BuildEncounterChoices(database, 9999, function(encounterID)
        if encounterID == 9001 then
            return {
                name = "Known",
                instanceName = "Known Raid",
                instanceOrder = 1,
                encounterOrder = 1,
            }
        end
    end)

    assertTableEquals(choices, {
        { name = "Known Raid", header = true },
        { name = "Known", value = 9001, encounterName = "Known" },
        { name = "Other Encounters", header = true },
        {
            name = "Unknown Encounter (9999)",
            value = 9999,
            encounterName = "Unknown Encounter (9999)",
            currentOnly = true,
        },
    })
end

tests["difficulty choices always map the four raid difficulties"] = function()
    assertTableEquals(Planner:GetDifficultyOptions(), {
        { name = "Normal", value = "Normal", difficultyID = 14 },
        { name = "Heroic", value = "Heroic", difficultyID = 15 },
        { name = "Mythic", value = "Mythic", difficultyID = 16 },
        { name = "LFR", value = "LFR", difficultyID = 17 },
    })
    assertEquals(Planner:GetDifficultyID("LFR"), 17)
    assertNil(Planner:GetDifficultyID(nil))
end

tests["phase tabs use stable navigation labels instead of canonical names"] = function()
    assertEquals(Planner:FormatPhaseTabLabel(), "All Phases")
    assertEquals(Planner:FormatPhaseTabLabel(1), "Phase 1")
    assertEquals(Planner:FormatPhaseTabLabel(4), "Phase 4")
end

tests["encounter context is editable only for an empty note in Edit mode"] = function()
    local empty = makeNote()
    local canonical = makeNote({ ["1"] = { { time = 5 } } })
    local personal = makeNote({ ["2"] = { { time = 7 } } })

    assertFalse(Planner:IsContextLocked("edit", empty, nil))
    assertTrue(Planner:IsContextLocked("edit", canonical, nil))
    assertTrue(Planner:IsContextLocked("edit", empty, personal))
    assertTrue(Planner:IsContextLocked("annotate", empty, nil))

    canonical.reminders["1"] = nil
    personal.reminders["2"] = nil
    assertFalse(Planner:IsContextLocked("edit", canonical, personal))
end

tests["locked imports reject context changes without mutating either note"] = function()
    local current = makeNote({ ["1"] = { { time = 5 } } })
    local imported = makeNote({ ["1"] = { { time = 8 } } })
    local currentBefore = CopyTable(current)
    local importedBefore = CopyTable(imported)

    imported.encounterID = 9002
    local valid, err = Planner:ValidateImportedContext(current, nil, imported, "edit")

    assertFalse(valid)
    assertNotNil(err)
    assertTableEquals(current, currentBefore)
    assertEquals(imported.encounterID, 9002)
    imported.encounterID = 9001
    imported.difficulty = "Heroic"
    assertFalse((Planner:ValidateImportedContext(current, nil, imported, "edit")))
    imported.difficulty = "Mythic"
    assertTrue((Planner:ValidateImportedContext(current, nil, imported, "edit")))
    imported.encounterID = importedBefore.encounterID
end

tests["canonical phases include empty phases and preserve unknown reminder phases"] = function()
    local note = makeNote({
        ["1"] = { { time = 20, phase = 1 } },
        ["4"] = { { time = 7, phase = 4 } },
    })
    local model = {
        encounterID = 9001,
        difficultyID = 16,
        phases = {
            { id = 1, name = "Opening" },
            { id = 2, name = "Intermission" },
            { id = 3, name = "Finale" },
        },
        occurrences = {
            { phase = 1, time = 30, spellID = 101 },
            { phase = 2, time = 5, spellID = 102 },
        },
    }

    local phases = Planner:BuildPhases(note, model)

    assertTableEquals(phases, {
        { num = 1, name = "Opening", start = 0, duration = 40 },
        { num = 2, name = "Intermission", start = 40, duration = 15 },
        { num = 3, name = "Finale", start = 55, duration = 10 },
        { num = 4, name = "Unknown Phase 4", start = 65, duration = 17 },
    })
end

tests["an absent planning model uses reminder phases or Phase 1"] = function()
    assertTableEquals(Planner:BuildPhases(makeNote(), nil), {
        { num = 1, name = "Phase 1", start = 0, duration = 10 },
    })
    assertTableEquals(Planner:BuildPhases(makeNote({
        ["3"] = { { time = 12, phase = 3 } },
        ["5"] = { { time = 2, phase = 5 } },
    }), nil), {
        { num = 3, name = "Phase 3", start = 0, duration = 22 },
        { num = 5, name = "Phase 5", start = 22, duration = 12 },
    })
end

tests["timeline coordinates share phase selection and reset individual phases"] = function()
    local phases = {
        { num = 1, name = "One", start = 0, duration = 30 },
        { num = 2, name = "Two", start = 30, duration = 40 },
    }

    assertEquals(Planner:TimeToY(5, 2, phases, "all", 8, 6), 286)
    assertEquals(Planner:TimeToY(5, 2, phases, 2, 8, 6), 46)
    assertEquals(Planner:TotalDuration(phases, "all"), 70)
    assertEquals(Planner:TotalDuration(phases, 2), 40)

    local time, phase = Planner:YToTimeAndPhase(286, phases, "all", 8, 6)
    assertEquals(time, 5)
    assertEquals(phase, 2)
    time, phase = Planner:YToTimeAndPhase(46, phases, 2, 8, 6)
    assertEquals(time, 5)
    assertEquals(phase, 2)
end

tests["overlap layout scopes deterministic columns to each collision group"] = function()
    local entries = {
        { y = 6, height = 34, sourceOrder = 1 },
        { y = 20, height = 30, sourceOrder = 2 },
        { y = 44, height = 30, sourceOrder = 3 },
        { y = 90, height = 30, sourceOrder = 4 },
    }

    local laidOut, columnCount = Planner:AllocateColumns(entries, 4)

    assertEquals(columnCount, 2)
    assertEquals(laidOut[1].column, 0)
    assertEquals(laidOut[2].column, 1)
    assertEquals(laidOut[3].column, 0)
    assertEquals(laidOut[1].columnCount, 2)
    assertEquals(laidOut[3].columnCount, 2)
    assertEquals(laidOut[4].column, 0)
    assertEquals(laidOut[4].columnCount, 1)
    assertNil(entries[1].column)
end

tests["boss entries localize spells fall back safely and expose no actions or observations"] = function()
    local model = {
        phases = { { id = 1, name = "One" } },
        occurrences = {
            { phase = 1, time = 5, spellID = 101 },
            { phase = 1, time = 6, spellID = 102 },
        },
    }
    local phases = Planner:BuildPhases(makeNote(), model)
    local entries = Planner:BuildAbilityEntries(model, phases, "all", function(spellID)
        if spellID == 101 then
            return "Known Spell", 12345
        end
    end, {
        scale = 8,
        topPad = 6,
        height = 30,
        gap = 4,
        genericIcon = "question-mark",
    })

    assertEquals(entries[1].name, "Known Spell")
    assertEquals(entries[1].icon, 12345)
    assertEquals(entries[2].name, "Unknown Spell (102)")
    assertEquals(entries[2].icon, "question-mark")
    assertFalse(entries[1].interactive)
    assertNil(entries[1].observations)
    assertNil(entries[1].actions)
    assertEquals(entries[1].columnCount, 2)

    local refreshed = Planner:BuildAbilityEntries(model, phases, "all", function(spellID)
        return "Loaded " .. spellID, spellID
    end)
    assertEquals(refreshed[2].name, "Loaded 102")
    assertEquals(refreshed[2].icon, 102)
end

tests["boss availability uses only the occurrence array"] = function()
    assertEquals(Planner:GetUnavailableMessage(nil), Planner.UNAVAILABLE_MESSAGE)
    assertEquals(Planner:GetUnavailableMessage({ occurrences = {} }), Planner.UNAVAILABLE_MESSAGE)
    assertNil(Planner:GetUnavailableMessage({
        occurrences = { { phase = 1, time = 1, spellID = 1 } },
    }))
end

tests["editor mode state keeps the boss channel passive and mode-independent"] = function()
    assertTableEquals(Planner:GetEditorModeState("edit", false), {
        bossVisible = true,
        abilityInteractive = false,
        encounterEnabled = true,
        difficultyEnabled = true,
        annotateVisible = true,
        importVisible = true,
        showOnlyMineVisible = false,
        bossAffectedByShowOnlyMine = false,
    })
    assertTableEquals(Planner:GetEditorModeState("annotate", true), {
        bossVisible = true,
        abilityInteractive = false,
        encounterEnabled = false,
        difficultyEnabled = false,
        annotateVisible = false,
        importVisible = false,
        showOnlyMineVisible = true,
        bossAffectedByShowOnlyMine = false,
    })
end

tests["editor mode state applies to fake widgets without creating frames"] = function()
    local function makeWidget()
        return {
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            SetEnabled = function(self, enabled) self.enabled = enabled end,
        }
    end
    local controls = {
        showOnlyMine = makeWidget(),
        showOnlyMineLabel = makeWidget(),
        annotate = makeWidget(),
        import = makeWidget(),
        boss = makeWidget(),
        encounter = makeWidget(),
        difficulty = makeWidget(),
    }

    Planner:ApplyEditorModeState(
        Planner:GetEditorModeState("annotate", true),
        controls
    )

    assertTrue(controls.showOnlyMine.shown)
    assertFalse(controls.annotate.shown)
    assertFalse(controls.import.shown)
    assertTrue(controls.boss.shown)
    assertFalse(controls.encounter.enabled)
    assertFalse(controls.difficulty.enabled)
end

tests["planner construction does not mutate notes or planning models"] = function()
    local note = makeNote({ ["1"] = { { time = 5, phase = 1 } } })
    local model = {
        encounterID = 9001,
        difficultyID = 16,
        phases = { { id = 1, name = "One" } },
        occurrences = { { phase = 1, time = 9, spellID = 101 } },
    }
    local noteBefore = CopyTable(note)
    local modelBefore = CopyTable(model)

    local phases = Planner:BuildPhases(note, model)
    Planner:BuildAbilityEntries(model, phases, "all", function()
        return nil, nil
    end)

    assertTableEquals(note, noteBefore)
    assertTableEquals(model, modelBefore)
end

return tests
