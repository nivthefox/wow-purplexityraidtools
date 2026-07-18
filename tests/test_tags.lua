-- tests/test_tags.lua
-- Exercises the NotesTags module's tag-matching logic (spec 5).
--
-- Public API under test (implementer must conform):
--   PRT.NotesTags.Matches(tagString, playerCtx) -> bool
--     playerCtx = { name, role, classID, specID, subgroup, isMelee }
--     role is "TANK" | "HEALER" | "DAMAGER". Pure function, no WoW API calls.
--   PRT.NotesTags.MarkRelevance(note, playerCtx)
--     takes a single parsed note { encounterID, name, difficulty,
--     reminders = { [phaseKey] = array }, lines } and sets reminder.relevant
--     on every reminder across all of that note's phase buckets.
--   PRT.NotesTags.IsMeleeSpec(specID) -> bool
--     spec-ID -> melee classification, mirroring NSRT's meleetable
--     (DPS/healer specs only; tank melee-classification is applied when the
--      caller builds playerCtx.isMelee, not here).
--
-- Matching rules (spec 5):
--   * Space-separated identifiers; ANY match makes the reminder relevant.
--   * Case-insensitive throughout.
--   * Player name, role (tank/healer/damager), class ID (1-13), spec ID (>=62),
--     group1-group8, melee/ranged (via isMelee), everyone (always).
--   * Numeric 14-61 is a dead zone that matches nothing.

local tests = {}

dofile("Modules/Notes/NotesTags.lua")

local PRT = PurplexityRaidTools
local Tags = PRT.NotesTags

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

-- Default context: a Retribution Paladin named "Bubbles" in group3, DAMAGER,
-- classID 2 (Paladin), specID 70 (Ret), classified melee.
local function ctx(overrides)
    local base = {
        name     = "Bubbles",
        role     = "DAMAGER",
        classID  = 2,
        specID   = 70,
        subgroup = 3,
        isMelee  = true,
    }
    if overrides then
        for k, v in pairs(overrides) do
            base[k] = v
        end
    end
    return base
end

--------------------------------------------------------------------------------
-- Player-name matching (case-insensitive)
--------------------------------------------------------------------------------

tests["name matches exactly"] = function()
    assertTrue(Tags.Matches("Bubbles", ctx()))
end

tests["name matches case-insensitively (tag lowercased)"] = function()
    assertTrue(Tags.Matches("bubbles", ctx()))
end

tests["name matches case-insensitively (mixed case tag)"] = function()
    assertTrue(Tags.Matches("BuBBleS", ctx()))
end

tests["name matches when player name has different case"] = function()
    assertTrue(Tags.Matches("bubbles", ctx({ name = "BUBBLES" })))
end

tests["a different name does not match"] = function()
    assertFalse(Tags.Matches("Sparkles", ctx()))
end

tests["name is not a substring match"] = function()
    -- "Bubble" is a prefix of "Bubbles" but must not match.
    assertFalse(Tags.Matches("Bubble", ctx()))
end

--------------------------------------------------------------------------------
-- Role tags: tank / healer / damager
--------------------------------------------------------------------------------

tests["role tag damager matches DAMAGER"] = function()
    assertTrue(Tags.Matches("damager", ctx({ role = "DAMAGER" })))
end

tests["role tag tank matches TANK"] = function()
    assertTrue(Tags.Matches("tank", ctx({ role = "TANK" })))
end

tests["role tag healer matches HEALER"] = function()
    assertTrue(Tags.Matches("healer", ctx({ role = "HEALER" })))
end

tests["role tag is case-insensitive"] = function()
    assertTrue(Tags.Matches("HEALER", ctx({ role = "HEALER" })))
end

tests["role tag does not match a different role"] = function()
    assertFalse(Tags.Matches("tank", ctx({ role = "DAMAGER" })))
end

tests["healer tag does not match a damager"] = function()
    assertFalse(Tags.Matches("healer", ctx({ role = "DAMAGER" })))
end

--------------------------------------------------------------------------------
-- Class tags: numeric 1-13 -> classID
--------------------------------------------------------------------------------

tests["class ID matches"] = function()
    -- classID 2 = Paladin.
    assertTrue(Tags.Matches("2", ctx({ classID = 2 })))
end

tests["class ID 1 (lower boundary) matches"] = function()
    assertTrue(Tags.Matches("1", ctx({ classID = 1 })))
end

tests["class ID 13 (upper boundary) matches"] = function()
    assertTrue(Tags.Matches("13", ctx({ classID = 13 })))
end

tests["wrong class ID does not match"] = function()
    assertFalse(Tags.Matches("5", ctx({ classID = 2 })))
end

tests["class ID does not match against specID field"] = function()
    -- Tag "2" is a class ID; a player whose specID is 2 (impossible in-game,
    -- but guards the disjoint-range logic) must not match on the spec side.
    assertFalse(Tags.Matches("2", ctx({ classID = 11, specID = 2 })))
end

--------------------------------------------------------------------------------
-- Spec tags: numeric >= 62 -> specID
--------------------------------------------------------------------------------

tests["spec ID matches"] = function()
    -- specID 70 = Retribution Paladin.
    assertTrue(Tags.Matches("70", ctx({ specID = 70 })))
end

tests["spec ID 62 (lower boundary) matches"] = function()
    -- specID 62 = Arcane Mage.
    assertTrue(Tags.Matches("62", ctx({ classID = 8, specID = 62 })))
end

tests["spec ID 65 (Holy Paladin) matches"] = function()
    assertTrue(Tags.Matches("65", ctx({ role = "HEALER", classID = 2, specID = 65 })))
end

tests["wrong spec ID does not match"] = function()
    assertFalse(Tags.Matches("65", ctx({ specID = 70 })))
end

tests["spec ID does not match against classID field"] = function()
    -- A high number is a spec ID; it must not accidentally match a class ID.
    assertFalse(Tags.Matches("70", ctx({ classID = 70, specID = 62 })))
end

--------------------------------------------------------------------------------
-- Dead zone: numeric 14-61 matches nothing
--------------------------------------------------------------------------------

tests["dead-zone number 14 (lower) matches nothing"] = function()
    assertFalse(Tags.Matches("14", ctx({ classID = 14, specID = 14 })))
end

tests["dead-zone number 40 matches nothing"] = function()
    assertFalse(Tags.Matches("40", ctx({ classID = 40, specID = 40 })))
end

tests["dead-zone number 61 (upper) matches nothing"] = function()
    assertFalse(Tags.Matches("61", ctx({ classID = 61, specID = 61 })))
end

--------------------------------------------------------------------------------
-- Group tags: group1 - group8 -> subgroup
--------------------------------------------------------------------------------

tests["group tag matches subgroup"] = function()
    assertTrue(Tags.Matches("group3", ctx({ subgroup = 3 })))
end

tests["group1 (lower boundary) matches"] = function()
    assertTrue(Tags.Matches("group1", ctx({ subgroup = 1 })))
end

tests["group8 (upper boundary) matches"] = function()
    assertTrue(Tags.Matches("group8", ctx({ subgroup = 8 })))
end

tests["group tag is case-insensitive"] = function()
    assertTrue(Tags.Matches("GROUP3", ctx({ subgroup = 3 })))
end

tests["wrong group does not match"] = function()
    assertFalse(Tags.Matches("group5", ctx({ subgroup = 3 })))
end

tests["bare group number without prefix does not match"] = function()
    -- "3" is a class ID (Hunter), not a subgroup selector.
    assertFalse(Tags.Matches("group3", ctx({ subgroup = 5 })))
end

--------------------------------------------------------------------------------
-- Position tags: melee / ranged via isMelee
--------------------------------------------------------------------------------

tests["melee tag matches when isMelee is true"] = function()
    assertTrue(Tags.Matches("melee", ctx({ isMelee = true })))
end

tests["melee tag does not match when isMelee is false"] = function()
    assertFalse(Tags.Matches("melee", ctx({ isMelee = false })))
end

tests["ranged tag matches when isMelee is false"] = function()
    assertTrue(Tags.Matches("ranged", ctx({ isMelee = false })))
end

tests["ranged tag does not match when isMelee is true"] = function()
    assertFalse(Tags.Matches("ranged", ctx({ isMelee = true })))
end

tests["melee tag is case-insensitive"] = function()
    assertTrue(Tags.Matches("MELEE", ctx({ isMelee = true })))
end

--------------------------------------------------------------------------------
-- IsMeleeSpec: spec-ID -> melee classification (mirrors NSRT meleetable).
--
-- The implementer must build the same specID table. Melee DPS/healer specs
-- asserted below (from NSRT's meleetable):
--   Shaman   263 Enhancement (melee)
--   Hunter   255 Survival    (melee)
--   Rogue    259 Assassination, 260 Outlaw, 261 Subtlety (melee)
--   Warrior  71 Arms, 72 Fury (melee)
--   DK       251 Frost, 252 Unholy (melee)
--   Druid    103 Feral (melee)
--   Paladin  70 Retribution (melee), 65 Holy (melee per NSRT)
--   Monk     269 Windwalker (melee), 270 Mistweaver (melee per NSRT)
--   DH       577 Havoc (melee)
--
-- Ranged specs asserted (NOT in NSRT's meleetable):
--   Shaman   262 Elemental, 264 Restoration
--   Hunter   253 Beast Mastery, 254 Marksmanship
--   Druid    102 Balance, 105 Restoration
--   Mage     62 Arcane, 63 Fire, 64 Frost
--   Warlock  265 Affliction, 266 Demonology, 267 Destruction
--   Priest   258 Shadow, 256 Discipline, 257 Holy
--   Evoker   1467 Devastation, 1468 Preservation, 1473 Augmentation
--
-- Per-class melee/ranged pairs (classes that have both) are asserted directly:
--   Hunter: 255 melee / 253 ranged
--   Shaman: 263 melee / 262 ranged
--   Druid:  103 melee / 102 ranged
--------------------------------------------------------------------------------

local MELEE_SPECS = {
    263,  -- Shaman: Enhancement
    255,  -- Hunter: Survival
    259,  -- Rogue: Assassination
    260,  -- Rogue: Outlaw
    261,  -- Rogue: Subtlety
    71,   -- Warrior: Arms
    72,   -- Warrior: Fury
    251,  -- Death Knight: Frost
    252,  -- Death Knight: Unholy
    103,  -- Druid: Feral
    70,   -- Paladin: Retribution
    269,  -- Monk: Windwalker
    577,  -- Demon Hunter: Havoc
    65,   -- Paladin: Holy
    270,  -- Monk: Mistweaver
}

local RANGED_SPECS = {
    262,  -- Shaman: Elemental
    264,  -- Shaman: Restoration
    253,  -- Hunter: Beast Mastery
    254,  -- Hunter: Marksmanship
    102,  -- Druid: Balance
    105,  -- Druid: Restoration
    62,   -- Mage: Arcane
    63,   -- Mage: Fire
    64,   -- Mage: Frost
    265,  -- Warlock: Affliction
    266,  -- Warlock: Demonology
    267,  -- Warlock: Destruction
    258,  -- Priest: Shadow
    256,  -- Priest: Discipline
    257,  -- Priest: Holy
    1467, -- Evoker: Devastation
    1468, -- Evoker: Preservation
    1473, -- Evoker: Augmentation
}

tests["IsMeleeSpec: all melee specs classify as melee"] = function()
    for _, specID in ipairs(MELEE_SPECS) do
        assertTrue(Tags.IsMeleeSpec(specID),
            "specID " .. specID .. " should be melee")
    end
end

tests["IsMeleeSpec: all ranged specs classify as not-melee"] = function()
    for _, specID in ipairs(RANGED_SPECS) do
        assertFalse(Tags.IsMeleeSpec(specID),
            "specID " .. specID .. " should be ranged (not melee)")
    end
end

tests["IsMeleeSpec: Hunter melee/ranged pair (255 vs 253)"] = function()
    assertTrue(Tags.IsMeleeSpec(255), "255 Survival is melee")
    assertFalse(Tags.IsMeleeSpec(253), "253 Beast Mastery is ranged")
end

tests["IsMeleeSpec: Shaman melee/ranged pair (263 vs 262)"] = function()
    assertTrue(Tags.IsMeleeSpec(263), "263 Enhancement is melee")
    assertFalse(Tags.IsMeleeSpec(262), "262 Elemental is ranged")
end

tests["IsMeleeSpec: Druid melee/ranged pair (103 vs 102)"] = function()
    assertTrue(Tags.IsMeleeSpec(103), "103 Feral is melee")
    assertFalse(Tags.IsMeleeSpec(102), "102 Balance is ranged")
end

tests["IsMeleeSpec: unknown spec ID is not melee"] = function()
    assertFalse(Tags.IsMeleeSpec(999999))
end

--------------------------------------------------------------------------------
-- everyone: always matches
--------------------------------------------------------------------------------

tests["everyone matches"] = function()
    assertTrue(Tags.Matches("everyone", ctx()))
end

tests["everyone is case-insensitive"] = function()
    assertTrue(Tags.Matches("Everyone", ctx()))
end

tests["everyone matches regardless of context"] = function()
    assertTrue(Tags.Matches("everyone",
        ctx({ role = "TANK", classID = 6, specID = 250, subgroup = 8, isMelee = false })))
end

--------------------------------------------------------------------------------
-- Multi-value tags: ANY-OF semantics
--------------------------------------------------------------------------------

tests["multi-value tag matches on the second identifier"] = function()
    assertTrue(Tags.Matches("Sparkles Bubbles", ctx()))
end

tests["multi-value tag matches on the first identifier"] = function()
    assertTrue(Tags.Matches("Bubbles Sparkles", ctx()))
end

tests["multi-value tag matches on a middle identifier"] = function()
    assertTrue(Tags.Matches("Sparkles healer group3 Twinkle",
        ctx({ subgroup = 3 })))
end

tests["multi-value tag with no matching identifier is false"] = function()
    assertFalse(Tags.Matches("Sparkles Twinkle tank group5",
        ctx({ role = "DAMAGER", subgroup = 3 })))
end

tests["multi-value tag mixing type kinds matches on class ID"] = function()
    assertTrue(Tags.Matches("healer group1 2 ranged",
        ctx({ role = "DAMAGER", classID = 2, subgroup = 3, isMelee = true })))
end

tests["extra whitespace between identifiers is tolerated"] = function()
    assertTrue(Tags.Matches("Sparkles    Bubbles", ctx()))
end

--------------------------------------------------------------------------------
-- Non-matching / garbage tags: false, no crash
--------------------------------------------------------------------------------

tests["empty string matches nothing"] = function()
    assertFalse(Tags.Matches("", ctx()))
end

tests["whitespace-only string matches nothing"] = function()
    assertFalse(Tags.Matches("   ", ctx()))
end

tests["garbage identifier matches nothing and does not crash"] = function()
    assertFalse(Tags.Matches("!!!@#$%", ctx()))
end

tests["garbage number-adjacent tokens do not crash"] = function()
    -- Tokens that look numeric-ish but are not valid identifiers.
    assertFalse(Tags.Matches("3x 70k group99 grouptwo", ctx({
        classID = 2, specID = 70, subgroup = 3,
    })))
end

tests["group with out-of-range number does not match"] = function()
    assertFalse(Tags.Matches("group9", ctx({ subgroup = 3 })))
end

tests["group0 does not match"] = function()
    assertFalse(Tags.Matches("group0", ctx({ subgroup = 3 })))
end

tests["negative and zero numbers do not match"] = function()
    assertFalse(Tags.Matches("0", ctx({ classID = 2, specID = 70 })))
end

--------------------------------------------------------------------------------
-- MarkRelevance: walks every phase bucket of a single note, sets
-- reminder.relevant, leaves freeform lines untouched.
--------------------------------------------------------------------------------

-- Build a single parsed-note fixture matching the frozen data contract (rev 2):
--   note = { encounterID, name, difficulty,
--            reminders = { [phaseKey] = { <reminder>, ... } },
--            lines = { {type=...}, ... } }
local function makeNote()
    local rHealer = { time = 10, tag = "healer",   text = "A", phase = 1, phaseKey = "1" }
    local rMe     = { time = 20, tag = "Bubbles",   text = "B", phase = 1, phaseKey = "1" }
    local rEvery  = { time = 30, tag = "everyone",  text = "C", phase = 2, phaseKey = "2" }
    local rOther  = { time = 40, tag = "Sparkles",  text = "D", phase = 2, phaseKey = "2" }
    local freeform = { type = "freeform", text = "-- section header --" }

    return {
        encounterID = 1000,
        name        = "Boss One",
        difficulty  = nil,
        reminders = {
            ["1"] = { rHealer, rMe },
            ["2"] = { rEvery, rOther },
        },
        lines = {
            { type = "reminder", reminder = rHealer },
            freeform,
            { type = "reminder", reminder = rMe },
            { type = "reminder", reminder = rEvery },
            { type = "reminder", reminder = rOther },
        },
    }, { rHealer = rHealer, rMe = rMe, rEvery = rEvery, rOther = rOther, freeform = freeform }
end

tests["MarkRelevance sets relevant on matching reminders"] = function()
    local note, r = makeNote()
    Tags.MarkRelevance(note, ctx({ name = "Bubbles", role = "DAMAGER" }))
    -- Bubbles (damager) matches the "Bubbles" and "everyone" reminders.
    assertTrue(r.rMe.relevant, "own-name reminder is relevant")
    assertTrue(r.rEvery.relevant, "everyone reminder is relevant")
end

tests["MarkRelevance clears relevant on non-matching reminders"] = function()
    local note, r = makeNote()
    Tags.MarkRelevance(note, ctx({ name = "Bubbles", role = "DAMAGER" }))
    assertFalse(r.rHealer.relevant, "healer reminder is not relevant to a damager")
    assertFalse(r.rOther.relevant, "another player's reminder is not relevant")
end

tests["MarkRelevance sets a boolean on every reminder"] = function()
    local note, r = makeNote()
    Tags.MarkRelevance(note, ctx())
    -- Every reminder must have an explicit boolean, never nil.
    assertEquals(type(r.rHealer.relevant), "boolean")
    assertEquals(type(r.rMe.relevant), "boolean")
    assertEquals(type(r.rEvery.relevant), "boolean")
    assertEquals(type(r.rOther.relevant), "boolean")
end

tests["MarkRelevance walks all phases"] = function()
    local note, r = makeNote()
    -- A healer matches the phase-1 healer reminder and the phase-2 everyone one.
    Tags.MarkRelevance(note, ctx({ name = "Nobody", role = "HEALER" }))
    assertTrue(r.rHealer.relevant, "phase-1 healer reminder marked")
    assertTrue(r.rEvery.relevant, "phase-2 everyone reminder marked")
    assertFalse(r.rMe.relevant, "phase-1 name reminder not marked")
    assertFalse(r.rOther.relevant, "phase-2 name reminder not marked")
end

tests["MarkRelevance covers every phase bucket"] = function()
    -- A note with several phase buckets (including a fractional phaseKey): a
    -- reminder in each bucket must be visited and marked.
    local r1 = { time = 1, tag = "Bubbles",  text = "P1",  phase = 1,   phaseKey = "1" }
    local r2 = { time = 2, tag = "Bubbles",  text = "P2",  phase = 2,   phaseKey = "2" }
    local r3 = { time = 3, tag = "Bubbles",  text = "P25", phase = 2.5, phaseKey = "2.5" }
    local r4 = { time = 4, tag = "Sparkles", text = "P3",  phase = 3,   phaseKey = "3" }
    local note = {
        encounterID = 1234,
        name        = "Multi Phase",
        difficulty  = nil,
        reminders = {
            ["1"]   = { r1 },
            ["2"]   = { r2 },
            ["2.5"] = { r3 },
            ["3"]   = { r4 },
        },
        lines = {
            { type = "reminder", reminder = r1 },
            { type = "reminder", reminder = r2 },
            { type = "reminder", reminder = r3 },
            { type = "reminder", reminder = r4 },
        },
    }
    Tags.MarkRelevance(note, ctx({ name = "Bubbles" }))
    assertTrue(r1.relevant, "phase-1 bucket visited")
    assertTrue(r2.relevant, "phase-2 bucket visited")
    assertTrue(r3.relevant, "phase-2.5 bucket visited")
    assertFalse(r4.relevant, "phase-3 bucket visited (other player, not relevant)")
end

tests["MarkRelevance leaves freeform lines untouched"] = function()
    local note, r = makeNote()
    Tags.MarkRelevance(note, ctx())
    assertNil(r.freeform.relevant, "freeform line must not gain a relevant flag")
    assertNil(r.freeform.tag, "freeform line must not gain a tag")
end

tests["MarkRelevance on a note with empty reminders does not crash"] = function()
    local note = {
        encounterID = 5000,
        name        = "No Reminders",
        difficulty  = "Heroic",
        reminders   = {},
        lines       = {},
    }
    Tags.MarkRelevance(note, ctx())
end

tests["MarkRelevance on an inert note does not crash"] = function()
    -- Inert note: no metadata line, so encounterID is nil and there are no
    -- reminder buckets. Marking relevance must be a harmless no-op.
    local note = {
        encounterID = nil,
        name        = nil,
        difficulty  = nil,
        reminders   = {},
        lines       = { { type = "freeform", text = "just some prose" } },
    }
    Tags.MarkRelevance(note, ctx())
end

return tests
