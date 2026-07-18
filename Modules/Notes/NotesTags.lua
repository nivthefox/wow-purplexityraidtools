-- NotesTags: tag matching against the local player. Pure-logic, no WoW APIs.
--
-- Tag string: space-separated identifiers, ANY-match, case-insensitive.
-- Recognized identifiers:
--   * everyone                -> always relevant
--   * tank / healer / damager -> role
--   * a player name           -> exact-token match (no substring)
--   * numeric 1-13            -> classID
--   * numeric 14-61           -> dead zone (matches nothing)
--   * numeric >= 62           -> specID
--   * group1 - group8         -> subgroup
--   * melee / ranged          -> position (via ctx.isMelee)
local PRT = PurplexityRaidTools
local NotesTags = {}
PRT.NotesTags = NotesTags

--------------------------------------------------------------------------------
-- Melee spec table
--
-- DPS/healer specs only; tank-derived melee classification is applied by the
-- caller when it builds playerCtx.isMelee. Deliberate surprises: 65 Holy Paladin
-- and 270 Mistweaver Monk are classified MELEE.
--------------------------------------------------------------------------------

local MELEE_TABLE = {
    [263] = true, -- Shaman: Enhancement
    [255] = true, -- Hunter: Survival
    [259] = true, -- Rogue: Assassination
    [260] = true, -- Rogue: Outlaw
    [261] = true, -- Rogue: Subtlety
    [71]  = true, -- Warrior: Arms
    [72]  = true, -- Warrior: Fury
    [251] = true, -- Death Knight: Frost
    [252] = true, -- Death Knight: Unholy
    [103] = true, -- Druid: Feral
    [70]  = true, -- Paladin: Retribution
    [269] = true, -- Monk: Windwalker
    [577] = true, -- Demon Hunter: Havoc
    [65]  = true, -- Paladin: Holy
    [270] = true, -- Monk: Mistweaver
}

function NotesTags.IsMeleeSpec(specID)
    return MELEE_TABLE[specID] == true
end

--------------------------------------------------------------------------------
-- Tag matching
--------------------------------------------------------------------------------

local function tokenMatches(token, ctx)
    if token == "everyone" then
        return true
    end

    if token == "tank" then
        return ctx.role == "TANK"
    elseif token == "healer" then
        return ctx.role == "HEALER"
    elseif token == "damager" then
        return ctx.role == "DAMAGER"
    end

    if token == "melee" then
        return ctx.isMelee == true
    elseif token == "ranged" then
        return ctx.isMelee == false
    end

    local groupNum = token:match("^group(%d+)$")
    if groupNum then
        local n = tonumber(groupNum)
        return n ~= nil and n >= 1 and n <= 8 and ctx.subgroup == n
    end

    -- Anchored so "3x"/"70k" are names, not numbers. 1-13 classID, 14-61 dead
    -- zone (no match), >= 62 specID.
    if token:match("^%d+$") then
        local n = tonumber(token)
        if n == nil then
            return false
        end
        if n >= 1 and n <= 13 then
            return ctx.classID == n
        elseif n >= 62 then
            return ctx.specID == n
        end
        return false
    end

    if ctx.name and token == ctx.name:lower() then
        return true
    end

    return false
end

function NotesTags.Matches(tagString, ctx)
    if type(tagString) ~= "string" or tagString == "" then
        return false
    end

    tagString = tagString:lower()
    for token in tagString:gmatch("%S+") do
        if tokenMatches(token, ctx) then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- MarkRelevance
--------------------------------------------------------------------------------

-- Sets reminder.relevant on every per-phase reminder. Freeform lines live in
-- .lines with no reminder entry, so they are never touched.
function NotesTags.MarkRelevance(note, ctx)
    if type(note) ~= "table" then
        return
    end

    local reminders = note.reminders
    if type(reminders) ~= "table" then
        return
    end

    for _, phaseList in pairs(reminders) do
        if type(phaseList) == "table" then
            for _, reminder in ipairs(phaseList) do
                reminder.relevant =
                    NotesTags.Matches(reminder.tag, ctx) and true or false
            end
        end
    end
end
