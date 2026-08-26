local PRT = PurplexityRaidTools

dofile("Modules/Notes/NotesBossTimeline.lua")

local BossTimeline = PRT.NotesBossTimeline
local tests = {}

local function reminder(overrides)
    local result = {
        time = 71,
        phase = 1,
        phaseKey = "1",
        duration = 5,
        displayType = "Bar",
        bossSpell = 1290516,
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

local function model()
    return {
        occurrences = {
            {
                phase = 1,
                time = 71,
                spellID = 1290516,
                duration = 4.25,
                ticks = {
                    { time = 1.25 },
                    { time = 2.25 },
                    { time = 3.25 },
                },
            },
        },
    }
end

tests["matching boss spell attaches a private copy of compound timing"] = function()
    local matched = reminder()
    local note = { reminders = { ["1"] = { matched } } }
    local planningModel = model()

    BossTimeline:Apply(note, planningModel)

    assertEquals(matched.bossDuration, 4.25)
    assertTableEquals(matched.bossTicks, {
        { time = 1.25 },
        { time = 2.25 },
        { time = 3.25 },
    })
    matched.bossTicks[1].time = 99
    assertEquals(planningModel.occurrences[1].ticks[1].time, 1.25)
end

tests["compound bar spans warning lead and final tick"] = function()
    local matched = reminder()
    BossTimeline:Apply({ reminders = { ["1"] = { matched } } }, model())

    local timeline = BossTimeline:GetBarTimeline(matched)

    assertEquals(timeline.duration, 8.25)
    assertEquals(timeline.postDuration, 3.25)
    assertNear(timeline.ticks[1].progress, 6.25 / 8.25, 1e-9)
    assertNear(timeline.ticks[2].progress, 7.25 / 8.25, 1e-9)
    assertEquals(timeline.ticks[3].progress, 1)
end

tests["changing dur moves only the start of a compound bar"] = function()
    local matched = reminder({ duration = 8 })
    BossTimeline:Apply({ reminders = { ["1"] = { matched } } }, model())

    local timeline = BossTimeline:GetBarTimeline(matched)

    assertEquals(timeline.duration, 11.25)
    assertEquals(timeline.postDuration, 3.25)
    assertEquals(matched.bossTicks[3].time, 3.25)
end

tests["non-bars and unmatched reminders receive no extended timeline"] = function()
    local text = reminder({ displayType = "Text" })
    local wrongSpell = reminder({ bossSpell = 1 })
    local note = { reminders = { ["1"] = { text, wrongSpell } } }

    BossTimeline:Apply(note, model())

    assertNil(BossTimeline:GetBarTimeline(text))
    assertNil(wrongSpell.bossTicks)
    assertNil(BossTimeline:GetBarTimeline(wrongSpell))
end

tests["reapplying without a model clears stale compound timing"] = function()
    local matched = reminder()
    local note = { reminders = { ["1"] = { matched } } }
    BossTimeline:Apply(note, model())
    BossTimeline:Apply(note, nil)

    assertNil(matched.bossDuration)
    assertNil(matched.bossTicks)
end

return tests
