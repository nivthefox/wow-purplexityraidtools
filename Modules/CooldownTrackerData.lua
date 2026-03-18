-- CooldownTrackerData: Spell data table for tracked raid cooldowns
-- Separated from module logic for easy maintenance when patches change values.
--
-- Each entry is keyed by buff spell ID. Where the buff ID differs from the cast
-- ID, the buff ID is used. Entries marked with a comment noting "cast ID" need
-- in-game validation; the cast ID is used as a placeholder until confirmed.
local PRT = PurplexityRaidTools

-- Spec IDs for filtering
local SPEC_RESTORATION_DRUID = 105
local SPEC_PRESERVATION_EVOKER = 1468
local SPEC_MISTWEAVER_MONK = 270
local SPEC_HOLY_PALADIN = 65
local SPEC_DISCIPLINE_PRIEST = 256
local SPEC_HOLY_PRIEST = 257
local SPEC_RESTORATION_SHAMAN = 264

PRT.CooldownTrackerSpells = {
    -- Defensive
    [740]    = { spellId = 740,    name = "Tranquility",        category = "defensive", cooldown = 180, class = "DRUID",        specId = SPEC_RESTORATION_DRUID },   -- cast ID, needs buff ID validation
    [359816] = { spellId = 359816, name = "Dream Flight",       category = "defensive", cooldown = 120, class = "EVOKER",       specId = SPEC_PRESERVATION_EVOKER }, -- cast ID
    [363534] = { spellId = 363534, name = "Rewind",             category = "defensive", cooldown = 240, class = "EVOKER",       specId = SPEC_PRESERVATION_EVOKER }, -- cast ID
    [108280] = { spellId = 108280, name = "Healing Tide Totem", category = "defensive", cooldown = 180, class = "SHAMAN",       specId = SPEC_RESTORATION_SHAMAN },  -- cast ID
    [98008]  = { spellId = 98008,  name = "Spirit Link Totem",  category = "defensive", cooldown = 180, class = "SHAMAN",       specId = SPEC_RESTORATION_SHAMAN },  -- cast ID
    [115310] = { spellId = 115310, name = "Revival",            category = "defensive", cooldown = 180, class = "MONK",         specId = SPEC_MISTWEAVER_MONK },     -- cast ID
    [388615] = { spellId = 388615, name = "Restoral",           category = "defensive", cooldown = 180, class = "MONK",         specId = SPEC_MISTWEAVER_MONK },     -- cast ID
    [31821]  = { spellId = 31821,  name = "Aura Mastery",       category = "defensive", cooldown = 180, class = "PALADIN",      specId = SPEC_HOLY_PALADIN },        -- cast ID
    [62618]  = { spellId = 62618,  name = "Power Word: Barrier",category = "defensive", cooldown = 180, class = "PRIEST",       specId = SPEC_DISCIPLINE_PRIEST },   -- cast ID
    [271466] = { spellId = 271466, name = "Luminous Barrier",   category = "defensive", cooldown = 180, class = "PRIEST",       specId = SPEC_DISCIPLINE_PRIEST },   -- cast ID
    [64843]  = { spellId = 64843,  name = "Divine Hymn",        category = "defensive", cooldown = 180, class = "PRIEST",       specId = SPEC_HOLY_PRIEST },         -- cast ID
    [97463]  = { spellId = 97463,  name = "Rallying Cry",       category = "defensive", cooldown = 180, class = "WARRIOR",      specId = nil },                      -- confirmed buff ID
    [51052]  = { spellId = 51052,  name = "Anti-Magic Zone",    category = "defensive", cooldown = 120, class = "DEATHKNIGHT",  specId = nil },                      -- cast ID
    [196718] = { spellId = 196718, name = "Darkness",           category = "defensive", cooldown = 300, class = "DEMONHUNTER",  specId = nil },                      -- cast ID

    -- Movement
    [106898] = { spellId = 106898, name = "Stampeding Roar",    category = "movement",  cooldown = 120, class = "DRUID",        specId = nil },                      -- cast ID
    [192077] = { spellId = 192077, name = "Wind Rush Totem",    category = "movement",  cooldown = 120, class = "SHAMAN",       specId = nil },                      -- cast ID
    [374968] = { spellId = 374968, name = "Time Spiral",        category = "movement",  cooldown = 120, class = "EVOKER",       specId = nil },                      -- cast ID

    -- External
    [357170] = { spellId = 357170, name = "Time Dilation",      category = "external",  cooldown = 120, class = "EVOKER",       specId = SPEC_PRESERVATION_EVOKER }, -- cast ID
    [33206]  = { spellId = 33206,  name = "Pain Suppression",   category = "external",  cooldown = 120, class = "PRIEST",       specId = SPEC_DISCIPLINE_PRIEST },   -- cast ID
    [102342] = { spellId = 102342, name = "Ironbark",           category = "external",  cooldown = 60,  class = "DRUID",        specId = SPEC_RESTORATION_DRUID },   -- cast ID
    [6940]   = { spellId = 6940,   name = "Blessing of Sacrifice",category = "external",cooldown = 120, class = "PALADIN",      specId = SPEC_HOLY_PALADIN },        -- cast ID
    [255312] = { spellId = 255312, name = "Guardian Spirit",    category = "external",  cooldown = 60,  class = "PRIEST",       specId = SPEC_HOLY_PRIEST },         -- cast ID
}

-- Build a reverse lookup from class token to list of spell data entries
PRT.CooldownTrackerSpellsByClass = {}
for _, spellData in pairs(PRT.CooldownTrackerSpells) do
    local class = spellData.class
    if not PRT.CooldownTrackerSpellsByClass[class] then
        PRT.CooldownTrackerSpellsByClass[class] = {}
    end
    table.insert(PRT.CooldownTrackerSpellsByClass[class], spellData)
end

-- Default settings
PRT.defaults.cooldownTracker = {
    enabled = true,
    categories = {
        defensive = true,
        movement = true,
        external = true,
    },
    lockFrame = false,
    barHeight = 20,
    barWidth = 250,
    showOnlyInCombat = false,
    framePosition = nil,
}
