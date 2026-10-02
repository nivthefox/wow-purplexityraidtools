local tests = {}
local Cooldowns = dofile("Modules/Notes/NotesCooldowns.lua")

local function reminder(time, tag, spellID, phase)
    return { time = time, tag = tag or "Aster", spellID = spellID or 100, phase = phase or 1 }
end

local function note(...)
    local result = { reminders = {} }
    for _, value in ipairs({ ... }) do
        local key = tostring(value.phase)
        result.reminders[key] = result.reminders[key] or {}
        table.insert(result.reminders[key], value)
    end
    return result
end

local function resolve(value)
    if not value.spellID then return nil end
    return { caster = value.tag, spellID = value.spellID, cooldown = 180, charges = 1 }
end

tests["Cooldown conflicts end exactly at recovery and impossible uses do not consume charges"] = function()
    local first, bad, boundary = reminder(30), reminder(209), reminder(210)
    local statuses = Cooldowns:Evaluate(note(boundary, bad, first), resolve)
    assertTrue(statuses[first].ready)
    assertFalse(statuses[bad].ready)
    assertEquals(statuses[bad].readyAt, 210)
    assertTrue(statuses[boundary].ready)
    assertEquals(statuses[boundary].recoveryAt, 390)
end

tests["Cooldown schedules separate casters and spells but normalize name casing"] = function()
    local a, b, c, d = reminder(30), reminder(31, "Ember"), reminder(31, nil, 101), reminder(32, "ASTER")
    local statuses = Cooldowns:Evaluate(note(a, b, c, d), resolve)
    assertTrue(statuses[b].ready)
    assertTrue(statuses[c].ready)
    assertFalse(statuses[d].ready)
end

tests["Charges recharge serially and an available spare charge needs no recovery guide"] = function()
    local a, b, c, d, e = reminder(0), reminder(10), reminder(20), reminder(180), reminder(181)
    local statuses = Cooldowns:Evaluate(note(a, b, c, d, e), function(value)
        local info = resolve(value)
        info.charges = 2
        return info
    end)
    assertTrue(statuses[a].ready)
    assertNil(Cooldowns:GetGuide(statuses[a]))
    assertTrue(statuses[b].ready)
    assertEquals(statuses[b].recoveryAt, 180)
    assertEquals(statuses[c].readyAt, 180)
    assertTrue(statuses[d].ready)
    assertEquals(statuses[e].readyAt, 360)
end

tests["Only learned static talent modifiers adjust cooldown and charge count"] = function()
    local ability = { cooldown = 200, charges = 1, talents = {
        [1] = { cooldown = -20 }, [2] = { cooldown_pct = -0.5, charges = 1 },
        [3] = { cooldown = -100 },
    } }
    local result = Cooldowns:GetAbility(ability, { [1] = true, [2] = true })
    assertEquals(result.cooldown, 90)
    assertEquals(result.charges, 2)
    assertEquals(Cooldowns:GetAbility(ability).cooldown, 200)
    assertNil(Cooldowns:GetAbility({ cooldown = 0 }))
end

tests["Draft evaluation replaces its original without mutating saved assignments"] = function()
    local a, b = reminder(30), reminder(90)
    local saved = note(a, b)
    local draft = reminder(210)
    local statuses = Cooldowns:Evaluate(saved, resolve, b, draft)
    assertTrue(statuses[draft].ready)
    assertNil(statuses[b])
    assertEquals(b.time, 90)
    assertFalse(Cooldowns:Evaluate(saved, resolve)[b].ready)
    local sameTimeDraft = reminder(30)
    assertTrue(Cooldowns:Evaluate(saved, resolve, a, sameTimeDraft)[sameTimeDraft].ready)
end

tests["A frozen conflict guide survives a draft crossing recovery and changes after commit"] = function()
    local a, b = reminder(30), reminder(90)
    local saved = note(a, b)
    local guide = Cooldowns:GetGuide(Cooldowns:Evaluate(saved, resolve)[b])
    for _, time in ipairs({ 209, 210, 225 }) do
        local draft = reminder(time)
        local status = Cooldowns:Evaluate(saved, resolve, b, draft)[draft]
        assertEquals(status.ready, time >= 210)
        assertEquals(guide.finish, 210)
        assertEquals(b.time, 90)
    end
    b.time = 225
    assertEquals(Cooldowns:GetGuide(Cooldowns:Evaluate(saved, resolve)[b]).finish, 405)
end

tests["Display phase spacing never confirms availability after an earlier phase use"] = function()
    local a, b, c = reminder(30), reminder(999, nil, nil, 2), reminder(0, "Ember", nil, 2)
    local statuses = Cooldowns:Evaluate(note(a, b, c), resolve)
    assertNil(statuses[b].ready)
    assertTrue(statuses[b].uncertain)
    assertNil(Cooldowns:GetGuide(statuses[b]))
    assertTrue(statuses[c].ready)
end

tests["Unknown spells stay unconfirmed and a selection extends only its display phase"] = function()
    local unknown = reminder(0)
    unknown.spellID = nil
    assertNil(Cooldowns:Evaluate(note(unknown), resolve)[unknown])
    local phases = { { num = 1, duration = 100 }, { num = 2, duration = 60 } }
    Cooldowns:ExtendPhases(phases, { phase = 1, finish = 210 })
    assertEquals(phases[1].duration, 220)
    assertEquals(phases[2].duration, 60)
    assertEquals(phases[2].start, 220)
end

return tests
