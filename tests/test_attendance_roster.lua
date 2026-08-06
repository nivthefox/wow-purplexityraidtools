-- tests/test_attendance_roster.lua
-- Exercises the officer-maintained roster (spec 2026-08-05-attendance-tracking:
-- "Roster Management", "Edge Cases -> Roster").
--
-- The class and specialization APIs are stubbed at their real signatures, but
-- the data behind them deliberately disagrees with the live game: Priest's third
-- specialization is a spec no client has ever shipped, and Shaman reports none at
-- all. A module that hardcodes class and spec data instead of reading the API can
-- therefore never satisfy this suite, which is the constraint the spec states and
-- nothing else here can enforce.
--
-- The two specialization calls live behind different doors, which is surprising
-- enough to be worth stating. The count is namespaced as
-- C_SpecializationInfo.GetNumSpecializationsForClassID (the bare form was
-- deprecated in 11.0.5), while the info call is the bare global
-- GetSpecializationInfoForClassID; no namespaced form of it exists on 12.x and
-- it must never be reached for. Each door the client lacks is left undefined
-- here, so a module knocking on the wrong one fails on every spec test rather
-- than in-game.
--
-- The group source fixture mirrors what GroupInspect stores after Phase 0 --
-- records keyed by GUID, each carrying a full "Name-Realm" and a class token --
-- so the seam these tests pin is the one the wiring layer will hand the module.

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals
--------------------------------------------------------------------------------

local CLASSES_BY_ID = {
    { className = "Warrior", classFile = "WARRIOR" },
    { className = "Paladin", classFile = "PALADIN" },
    { className = "Hunter", classFile = "HUNTER" },
    { className = "Rogue", classFile = "ROGUE" },
    { className = "Priest", classFile = "PRIEST" },
    { className = "Death Knight", classFile = "DEATHKNIGHT" },
    { className = "Shaman", classFile = "SHAMAN" },
    { className = "Mage", classFile = "MAGE" },
    { className = "Warlock", classFile = "WARLOCK" },
    { className = "Monk", classFile = "MONK" },
    { className = "Druid", classFile = "DRUID" },
    { className = "Demon Hunter", classFile = "DEMONHUNTER" },
    { className = "Evoker", classFile = "EVOKER" },
}

local ARMS, FURY, PROTECTION = 71, 72, 73
local ASSASSINATION, OUTLAW, SUBTLETY = 259, 260, 261
local DISCIPLINE, HOLY, UMBRAL = 256, 257, 9001
local ARCANE, FIRE, FROST = 62, 63, 64
local BALANCE, FERAL, GUARDIAN, RESTORATION = 102, 103, 104, 105
local HAVOC, VENGEANCE = 577, 581

local SPECS_BY_CLASS_ID = {
    [1] = {
        { id = ARMS, name = "Arms" },
        { id = FURY, name = "Fury" },
        { id = PROTECTION, name = "Protection" },
    },
    [4] = {
        { id = ASSASSINATION, name = "Assassination" },
        { id = OUTLAW, name = "Outlaw" },
        { id = SUBTLETY, name = "Subtlety" },
    },
    [5] = {
        { id = DISCIPLINE, name = "Discipline" },
        { id = HOLY, name = "Holy" },
        { id = UMBRAL, name = "Umbral" },
    },
    [8] = {
        { id = ARCANE, name = "Arcane" },
        { id = FIRE, name = "Fire" },
        { id = FROST, name = "Frost" },
    },
    [11] = {
        { id = BALANCE, name = "Balance" },
        { id = FERAL, name = "Feral" },
        { id = GUARDIAN, name = "Guardian" },
        { id = RESTORATION, name = "Restoration" },
    },
    [12] = {
        { id = HAVOC, name = "Havoc" },
        { id = VENGEANCE, name = "Vengeance" },
    },
}

if GetNumClasses == nil then
    function GetNumClasses()
        return #CLASSES_BY_ID
    end
end

if C_CreatureInfo == nil then
    C_CreatureInfo = {
        GetClassInfo = function(classID)
            local class = CLASSES_BY_ID[classID]
            if not class then
                return nil
            end
            return {
                className = class.className,
                classFile = class.classFile,
                classID = classID,
            }
        end,
    }
end

if C_SpecializationInfo == nil then
    C_SpecializationInfo = {}
end

if C_SpecializationInfo.GetNumSpecializationsForClassID == nil then
    C_SpecializationInfo.GetNumSpecializationsForClassID = function(classID)
        local specs = SPECS_BY_CLASS_ID[classID]
        if not specs then
            return 0
        end
        return #specs
    end
end

if GetSpecializationInfoForClassID == nil then
    function GetSpecializationInfoForClassID(classID, specIndex)
        local specs = SPECS_BY_CLASS_ID[classID]
        local spec = specs and specs[specIndex]
        if not spec then
            return nil
        end
        local description, icon, role = "", 1000 + spec.id, "DAMAGER"
        local recommended, allowedForBoost = false, true
        return spec.id, spec.name, description, icon, role, recommended, allowedForBoost
    end
end

dofile("Modules/Attendance/Roster.lua")

local PRT = PurplexityRaidTools
local Roster = PRT.Roster

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local OMNIVICENT = "Omnivicent-Proudmoore"
local NIVEN = "Niven-Proudmoore"
local ELSIE = "Elsie-Proudmoore"
local GRIMGRACE = "Grimgrace-Proudmoore"
local DYMLOS = "Dymlos-Proudmoore"
local RANDOPUG = "Randopug-Stormrage"
local SASJAH = "Sasjah-Proudmoore"

local function member(name, class)
    return { name = name, class = class }
end

local function groupOf(members)
    local byGUID = {}
    for i, entry in ipairs(members) do
        byGUID["Player-1084-0000000" .. i] = entry
    end
    return function()
        return byGUID
    end
end

local function guildOf(members)
    return function()
        return members
    end
end

local function noSource()
    return {}
end

local RAID_GROUP = groupOf({
    member(OMNIVICENT, "PRIEST"),
    member(NIVEN, "MAGE"),
    member(ELSIE, "ROGUE"),
    member(GRIMGRACE, "WARRIOR"),
    member(DYMLOS, "DRUID"),
    member(RANDOPUG, "DEMONHUNTER"),
    member(SASJAH, "SHAMAN"),
})

Roster.groupSource = noSource
Roster.guildSource = noSource

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function withSources(group, guild, body)
    local savedGroup, savedGuild = Roster.groupSource, Roster.guildSource
    Roster.groupSource = group
    Roster.guildSource = guild
    local ok, err = pcall(body)
    Roster.groupSource, Roster.guildSource = savedGroup, savedGuild
    if not ok then
        error(err, 0)
    end
end

local function resetDB()
    PurplexityRaidToolsRosterDB = {}
    return PurplexityRaidToolsRosterDB
end

local function snapshot()
    return CopyTable(PurplexityRaidToolsRosterDB)
end

local function withGroupRoster(saves, body)
    withSources(RAID_GROUP, noSource, function()
        resetDB()
        for _, save in ipairs(saves) do
            local ok, err = Roster:AddEntry(save[1], save[2])
            assertTrue(ok, "test setup save failed: " .. tostring(err))
        end
        body()
    end)
end

local function entryNamed(nickname)
    for _, entry in ipairs(PurplexityRaidToolsRosterDB) do
        if entry.nickname == nickname then
            return entry
        end
    end
    return nil
end

local function dataFor(nickname, character)
    local entry = entryNamed(nickname)
    assertNotNil(entry, "no entry nicknamed " .. tostring(nickname))
    assertNotNil(entry.characterData, "the entry carries no per-character data")
    return entry.characterData[character]
end

local function asSet(list)
    local set = {}
    for _, value in ipairs(list) do
        set[value] = true
    end
    return set
end

--------------------------------------------------------------------------------
-- Load contract
--------------------------------------------------------------------------------

tests["the roster module loads headless with no frame or timer API available"] = function()
    assertNil(rawget(_G, "CreateFrame"),
        "wow_stubs must not provide CreateFrame, so a frame dependency fails loudly")
    assertNil(rawget(_G, "C_Timer"),
        "wow_stubs must not provide C_Timer, so a timer dependency fails loudly")
    assertNotNil(Roster, "PurplexityRaidTools.Roster must exist after load")
end

tests["no roster operation reads addon settings"] = function()
    resetDB()
    local savedGetSetting = PRT.GetSetting
    PRT.GetSetting = function()
        error("the roster must take its inputs as parameters, never read PRT:GetSetting", 0)
    end

    local ok, err = pcall(function()
        withSources(RAID_GROUP, noSource, function()
            Roster:GetEntries()
            Roster:AddEntry("Niv", { OMNIVICENT })
            Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT, NIVEN })
            Roster:ResolveClass(OMNIVICENT)
            Roster:RefreshClasses()
            Roster:GetCharacterClass(OMNIVICENT)
            Roster:GetSpecsForCharacter(OMNIVICENT)
            Roster:SetMainSpec(OMNIVICENT, UMBRAL)
            Roster:AddOffSpec(OMNIVICENT, HOLY)
            Roster:RemoveOffSpec(OMNIVICENT, HOLY)
            Roster:ImportFromRecord({ [ELSIE] = 3 })
            Roster:RemoveEntry("Niv")
        end)
    end)

    PRT.GetSetting = savedGetSetting
    assertTrue(ok, tostring(err))
end

tests["the roster database is read from the global on every call"] = function()
    resetDB()
    Roster:AddEntry("Elsie", { ELSIE })

    local replacement = {}
    PurplexityRaidToolsRosterDB = replacement
    Roster:AddEntry("Niv", { OMNIVICENT })

    assertEquals(#replacement, 1, "the save must land in the table the global points at now")
    assertEquals(replacement[1].nickname, "Niv",
        "a database captured at load time never sees the replacement")
end

tests["the first save creates the database when the SavedVariable is nil"] = function()
    PurplexityRaidToolsRosterDB = nil

    local ok = Roster:AddEntry("Niv", { OMNIVICENT })

    local created = PurplexityRaidToolsRosterDB
    resetDB()

    assertTrue(ok)
    assertNotNil(created, "the module must create the SavedVariable table on first use")
    assertEquals(created[1].nickname, "Niv")
end

tests["the entry list is the array the attendance store consumes"] = function()
    local db = resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })

    local entries = Roster:GetEntries()

    assertEquals(entries, db, "GetEntries must hand back the live database, not a copy")
    assertEquals(#entries, 1)
    assertEquals(entries[1].nickname, "Niv")
    assertTableEquals(entries[1].characters, { OMNIVICENT, NIVEN },
        "the attendance store reads entry.characters as an ordered array of name-realms")
end

--------------------------------------------------------------------------------
-- Stub fidelity
--------------------------------------------------------------------------------

tests["the stubbed class API separates a class token from its localized name"] = function()
    local priest = C_CreatureInfo.GetClassInfo(5)

    assertEquals(priest.classFile, "PRIEST")
    assertEquals(priest.className, "Priest",
        "matching on the localized name instead of the token must be able to fail")
    assertEquals(GetNumClasses(), #CLASSES_BY_ID)
end

tests["the stubbed specialization data is unreachable by a hardcoded spec table"] = function()
    assertEquals(C_SpecializationInfo.GetNumSpecializationsForClassID(7), 0,
        "Shaman is a real class the stub gives no specs, so hardcoded spec data cannot agree")

    local id, name = GetSpecializationInfoForClassID(5, 3)
    assertEquals(id, UMBRAL)
    assertEquals(name, "Umbral",
        "a specialization no live client ships, so hardcoded spec data cannot produce it")
end

tests["the specialization stubs match the doors and signature the client provides"] = function()
    assertNotNil(C_SpecializationInfo.GetNumSpecializationsForClassID,
        "the count is namespaced; the bare form was deprecated in 11.0.5")
    assertNil(C_SpecializationInfo.GetSpecializationInfoForClassID,
        "this function does not exist on 12.x, so reaching for it must fail here too")

    assertNotNil(rawget(_G, "GetSpecializationInfoForClassID"),
        "the info call is a bare global and is the only door to spec details")
    assertNil(rawget(_G, "GetNumSpecializationsForClassID"),
        "the deprecated bare count global must stay undefined")

    local _, _, _, _, role, recommended = GetSpecializationInfoForClassID(5, 1)
    assertEquals(role, "DAMAGER", "position 5 is the role string")
    assertEquals(type(recommended), "boolean",
        "position 6 is the recommended flag, not the primaryStat number of a different function")
end

--------------------------------------------------------------------------------
-- Save validation
--------------------------------------------------------------------------------

tests["a saved entry persists its nickname and its characters in the order given"] = function()
    resetDB()

    local ok, err = Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })

    assertTrue(ok)
    assertNil(err)
    local entry = entryNamed("Niv")
    assertNotNil(entry)
    assertTableEquals(entry.characters, { OMNIVICENT, NIVEN },
        "the first character listed is the primary, so order is data")
end

tests["a save with a nickname already in use is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok, err = Roster:AddEntry("Niv", { ELSIE })

    assertFalse(ok, "nicknames are unique keys")
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected save writes nothing")
end

tests["a save claiming a character owned by another entry names the conflicting entry"] = function()
    resetDB()
    assertNil(OMNIVICENT:find("Niv", 1, true),
        "the nickname must not hide inside the character name, or this assertion proves nothing")

    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok, err = Roster:AddEntry("Elsie", { ELSIE, OMNIVICENT })

    assertFalse(ok)
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertNotNil(err:find("Niv", 1, true),
        "the officer has to be told which entry to remove the character from, got: " .. tostring(err))
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected save writes nothing")
end

tests["a save with no characters is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok, err = Roster:AddEntry("Elsie", {})

    assertFalse(ok, "a player entry requires at least one character")
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

tests["a save with no nickname is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    for _, nickname in ipairs({ "", " " }) do
        local ok, err = Roster:AddEntry(nickname, { ELSIE })
        assertFalse(ok, "a player entry requires a nickname: " .. string.format("%q", nickname))
        assertEquals(type(err), "string", "a rejected save must explain itself")
    end

    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

tests["a save listing the same character twice is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok, err = Roster:AddEntry("Elsie", { ELSIE, ELSIE })

    assertFalse(ok,
        "a character listed twice makes the entry's character array lie about its membership")
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertNotNil(err:find(ELSIE, 1, true),
        "the officer has to be told which character is duplicated, got: " .. tostring(err))
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected save writes nothing")
end

--------------------------------------------------------------------------------
-- Edit semantics
--------------------------------------------------------------------------------

tests["an edit replaces the character list wholesale"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })

    local ok, err = Roster:UpdateEntry("Niv", "Niv", { NIVEN, GRIMGRACE })

    assertTrue(ok, tostring(err))
    assertTableEquals(entryNamed("Niv").characters, { NIVEN, GRIMGRACE },
        "characters are added and removed by submitting the whole list")
end

tests["an edit that removes every character is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })
    local before = snapshot()

    local ok, err = Roster:UpdateEntry("Niv", "Niv", {})

    assertFalse(ok, "an entry with no characters is removed with Remove, never saved empty")
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected edit writes nothing")
end

tests["an edit preserves the spec assignments of retained characters"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT, NIVEN } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)
        Roster:AddOffSpec(OMNIVICENT, DISCIPLINE)
        Roster:SetMainSpec(NIVEN, FROST)

        local ok, err = Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT, GRIMGRACE })

        assertTrue(ok, tostring(err))
        local retained = dataFor("Niv", OMNIVICENT)
        assertEquals(retained.class, "PRIEST")
        assertEquals(retained.mainSpec, UMBRAL)
        assertTableEquals(retained.offSpecs, { DISCIPLINE })
    end)
end

tests["an edit resolves the class of a character it adds"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local ok, err = Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT, GRIMGRACE })

        assertTrue(ok, tostring(err))
        assertEquals(dataFor("Niv", GRIMGRACE).class, "WARRIOR",
            "merging an alt into an entry is an edit, so an edit has to observe its class")
        assertNotNil(Roster:GetSpecsForCharacter(GRIMGRACE),
            "the added character's spec controls unlock immediately")
    end)
end

tests["an edit drops the character data of a removed character"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT, NIVEN } } }, function()
        Roster:SetMainSpec(NIVEN, FROST)

        local ok, err = Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT })

        assertTrue(ok, tostring(err))
        assertNil(dataFor("Niv", NIVEN),
            "a character no longer on the entry leaves no data behind")
    end)
end

tests["an edit keeping the entry's own characters is not a conflict against itself"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })

    local ok, err = Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT, NIVEN, GRIMGRACE })

    assertTrue(ok, "an entry already owns its own characters: " .. tostring(err))
    assertTableEquals(entryNamed("Niv").characters, { OMNIVICENT, NIVEN, GRIMGRACE })
end

tests["an edit may keep its own nickname"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    Roster:AddEntry("Elsie", { ELSIE })

    local ok, err = Roster:UpdateEntry("Niv", "Niv", { OMNIVICENT, NIVEN })

    assertTrue(ok, "an unchanged nickname is not a duplicate of itself: " .. tostring(err))
end

tests["an edit renames the entry and keeps its character data"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)

        local ok, err = Roster:UpdateEntry("Niv", "Omni", { OMNIVICENT })

        assertTrue(ok, tostring(err))
        assertNil(entryNamed("Niv"), "the old nickname is gone")
        assertEquals(dataFor("Omni", OMNIVICENT).mainSpec, UMBRAL)
    end)
end

tests["an edit renaming onto another entry's nickname is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    Roster:AddEntry("Elsie", { ELSIE })
    local before = snapshot()

    local ok, err = Roster:UpdateEntry("Niv", "Elsie", { OMNIVICENT })

    assertFalse(ok)
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected edit writes nothing")
end

tests["an edit claiming another entry's character is rejected and names that entry"] = function()
    resetDB()
    assertNil(ELSIE:find("Niv", 1, true),
        "the nickname must not hide inside the character name, or this assertion proves nothing")

    Roster:AddEntry("Niv", { ELSIE })
    Roster:AddEntry("Dym", { DYMLOS })
    local before = snapshot()

    local ok, err = Roster:UpdateEntry("Dym", "Dym", { DYMLOS, ELSIE })

    assertFalse(ok)
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertNotNil(err:find("Niv", 1, true),
        "the officer has to be told which entry to remove the character from, got: " .. tostring(err))
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected edit writes nothing")
end

tests["an edit of an unknown nickname is rejected and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok, err = Roster:UpdateEntry("Nobody", "Nobody", { ELSIE })

    assertFalse(ok)
    assertEquals(type(err), "string", "a rejected save must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

--------------------------------------------------------------------------------
-- Removal
--------------------------------------------------------------------------------

tests["removing an entry leaves the surviving entries contiguous and intact"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })
    Roster:AddEntry("Elsie", { ELSIE })
    Roster:AddEntry("Dym", { DYMLOS })

    local ok = Roster:RemoveEntry("Elsie")

    assertTrue(ok)
    local entries = Roster:GetEntries()
    assertEquals(#entries, 2,
        "a hole in the array truncates the roster the attendance store iterates")
    assertEquals(entries[1].nickname, "Niv")
    assertEquals(entries[2].nickname, "Dym")
    assertTableEquals(entries[1].characters, { OMNIVICENT, NIVEN })
end

tests["removing an unknown nickname changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local ok = Roster:RemoveEntry("Nobody")

    assertFalse(ok)
    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

tests["a removed entry's characters are free for another entry to claim"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    Roster:RemoveEntry("Niv")

    local ok, err = Roster:AddEntry("Omni", { OMNIVICENT })

    assertTrue(ok, tostring(err))
    assertTableEquals(entryNamed("Omni").characters, { OMNIVICENT })
end

--------------------------------------------------------------------------------
-- Import from record
--------------------------------------------------------------------------------

tests["an import creates one entry per un-rostered character nicknamed by its name-realm"] = function()
    resetDB()

    local result = Roster:ImportFromRecord({
        [OMNIVICENT] = 3,
        [ELSIE] = 0,
        [RANDOPUG] = 2,
    })

    assertNotNil(result, "the import must report what it did")
    assertTableEquals(asSet(result.added), {
        [OMNIVICENT] = true,
        [ELSIE] = true,
        [RANDOPUG] = true,
    }, "every character in the record is imported regardless of its status")
    assertEquals(#Roster:GetEntries(), 3)
    for _, character in ipairs({ OMNIVICENT, ELSIE, RANDOPUG }) do
        local entry = entryNamed(character)
        assertNotNil(entry, "the default nickname is the character's full name-realm")
        assertTableEquals(entry.characters, { character })
    end
end

tests["an imported entry carries no spec assignments"] = function()
    withSources(RAID_GROUP, noSource, function()
        resetDB()

        Roster:ImportFromRecord({ [OMNIVICENT] = 3 })

        local data = dataFor(OMNIVICENT, OMNIVICENT)
        assertNotNil(data, "the imported character still gets a data record for its class")
        assertNil(data.mainSpec, "an import assigns no main spec")
        assertTableEquals(data.offSpecs or {}, {}, "an import assigns no off-specs")
    end)
end

tests["an import records the class of a character the group source knows"] = function()
    withSources(RAID_GROUP, noSource, function()
        resetDB()

        Roster:ImportFromRecord({ [RANDOPUG] = 3 })

        assertEquals(Roster:GetCharacterClass(RANDOPUG), "DEMONHUNTER")
    end)
end

tests["an import skips a character already owned by an entry"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })

    local result = Roster:ImportFromRecord({
        [OMNIVICENT] = 3,
        [NIVEN] = 2,
        [ELSIE] = 3,
    })

    assertTableEquals(asSet(result.added), { [ELSIE] = true },
        "a character already on the roster is not imported again")
    assertTableEquals(result.skipped, {},
        "an already-rostered character is the normal case, not a reported conflict")
    assertEquals(#Roster:GetEntries(), 2)
end

tests["an import skips a name-realm that collides with an existing nickname and reports it"] = function()
    resetDB()
    Roster:AddEntry(RANDOPUG, { GRIMGRACE })

    local result = Roster:ImportFromRecord({
        [RANDOPUG] = 3,
        [ELSIE] = 3,
    })

    assertTableEquals(asSet(result.skipped), { [RANDOPUG] = true },
        "the officer is told which character was skipped, and the entry holding that nickname")
    assertTableEquals(asSet(result.added), { [ELSIE] = true },
        "the rest of the import proceeds normally")
    assertEquals(#Roster:GetEntries(), 2)
    assertTableEquals(entryNamed(RANDOPUG).characters, { GRIMGRACE },
        "the entry holding the colliding nickname is untouched")
end

tests["an import over a fully rostered record adds nothing and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT, NIVEN })
    Roster:AddEntry("Elsie", { ELSIE })
    local before = snapshot()

    local result = Roster:ImportFromRecord({
        [OMNIVICENT] = 3,
        [NIVEN] = 3,
        [ELSIE] = 3,
    })

    assertTableEquals(result.added, {}, "there is nothing to add")
    assertTableEquals(result.skipped, {})
    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

tests["an import of an empty record adds nothing and changes nothing"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local result = Roster:ImportFromRecord({})

    assertTableEquals(result.added, {})
    assertTableEquals(result.skipped, {})
    assertTableEquals(PurplexityRaidToolsRosterDB, before)
end

--------------------------------------------------------------------------------
-- Class resolution
--------------------------------------------------------------------------------

tests["class resolution returns the class of a character the group source knows"] = function()
    withSources(RAID_GROUP, noSource, function()
        assertEquals(Roster:ResolveClass(OMNIVICENT), "PRIEST")
        assertEquals(Roster:ResolveClass(RANDOPUG), "DEMONHUNTER")
    end)
end

tests["class resolution falls back to the guild source for a character not in the group"] = function()
    local guild = guildOf({ member(DYMLOS, "DRUID") })

    withSources(groupOf({ member(OMNIVICENT, "PRIEST") }), guild, function()
        assertEquals(Roster:ResolveClass(DYMLOS), "DRUID",
            "the guild roster knows offline members the group cannot supply")
    end)
end

tests["the group source takes precedence over the guild source"] = function()
    local group = groupOf({ member(OMNIVICENT, "PRIEST") })
    local guild = guildOf({ member(OMNIVICENT, "WARRIOR") })

    withSources(group, guild, function()
        assertEquals(Roster:ResolveClass(OMNIVICENT), "PRIEST")
    end)
end

tests["class resolution returns nil for a character in neither source"] = function()
    withSources(groupOf({ member(OMNIVICENT, "PRIEST") }), guildOf({ member(DYMLOS, "DRUID") }),
        function()
            assertNil(Roster:ResolveClass(RANDOPUG),
                "a cross-realm character never grouped with has no observable class")
        end)
end

tests["class resolution with no sources configured returns nil"] = function()
    withSources(nil, nil, function()
        assertNil(Roster:ResolveClass(OMNIVICENT))
    end)
end

tests["a character's class is recorded when its entry is saved"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT, NIVEN } } }, function()
        assertEquals(dataFor("Niv", OMNIVICENT).class, "PRIEST")
        assertEquals(dataFor("Niv", NIVEN).class, "MAGE")
    end)
end

tests["no class is recorded for a character neither source knows"] = function()
    resetDB()

    Roster:AddEntry("Niv", { OMNIVICENT })

    assertNil(Roster:GetCharacterClass(OMNIVICENT),
        "an unresolvable character stores no class at all")
end

tests["a class unknown at save time fills in once the character is seen in a group"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    assertNil(Roster:GetCharacterClass(OMNIVICENT), "no source can resolve the character yet")
    assertFalse(Roster:SetMainSpec(OMNIVICENT, UMBRAL),
        "the spec controls stay shut while the class is unknown")

    withSources(RAID_GROUP, noSource, function()
        Roster:RefreshClasses()
    end)

    assertEquals(Roster:GetCharacterClass(OMNIVICENT), "PRIEST")
    assertTrue(Roster:SetMainSpec(OMNIVICENT, UMBRAL),
        "the spec controls unlock once the class resolves")
end

tests["a class refresh leaves an unresolvable character without a class"] = function()
    resetDB()
    Roster:AddEntry("Randy", { RANDOPUG })

    withSources(groupOf({ member(OMNIVICENT, "PRIEST") }), noSource, function()
        Roster:RefreshClasses()
    end)

    assertNil(Roster:GetCharacterClass(RANDOPUG))
end

--------------------------------------------------------------------------------
-- Specializations
--------------------------------------------------------------------------------

tests["the offered specs for a character are exactly its class's specializations"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        assertTableEquals(Roster:GetSpecsForCharacter(OMNIVICENT), {
            { id = DISCIPLINE, name = "Discipline", icon = 1000 + DISCIPLINE },
            { id = HOLY, name = "Holy", icon = 1000 + HOLY },
            { id = UMBRAL, name = "Umbral", icon = 1000 + UMBRAL },
        }, "the specialization API is the only source of the offered set")
    end)
end

tests["the offered spec set follows the character's own class"] = function()
    withGroupRoster({ { "Randy", { RANDOPUG } }, { "Dym", { DYMLOS } } }, function()
        assertTableEquals(Roster:GetSpecsForCharacter(RANDOPUG), {
            { id = HAVOC, name = "Havoc", icon = 1000 + HAVOC },
            { id = VENGEANCE, name = "Vengeance", icon = 1000 + VENGEANCE },
        })
        assertTableEquals(Roster:GetSpecsForCharacter(DYMLOS), {
            { id = BALANCE, name = "Balance", icon = 1000 + BALANCE },
            { id = FERAL, name = "Feral", icon = 1000 + FERAL },
            { id = GUARDIAN, name = "Guardian", icon = 1000 + GUARDIAN },
            { id = RESTORATION, name = "Restoration", icon = 1000 + RESTORATION },
        })
    end)
end

tests["no specs are offered for a class the specialization API reports none for"] = function()
    withGroupRoster({ { "Sasjah", { SASJAH } } }, function()
        assertEquals(Roster:GetCharacterClass(SASJAH), "SHAMAN")
        assertTableEquals(Roster:GetSpecsForCharacter(SASJAH), {},
            "a known class whose specs the API withholds offers an empty set, not a guess")
    end)
end

tests["no specs are offered for a character whose class is unknown"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })

    assertNil(Roster:GetSpecsForCharacter(OMNIVICENT),
        "spec controls are disabled while the class is unknown")
end

tests["spec assignments for a character whose class is unknown are rejected"] = function()
    resetDB()
    Roster:AddEntry("Niv", { OMNIVICENT })
    local before = snapshot()

    local mainOk, mainErr = Roster:SetMainSpec(OMNIVICENT, UMBRAL)
    local offOk, offErr = Roster:AddOffSpec(OMNIVICENT, HOLY)

    assertFalse(mainOk)
    assertEquals(type(mainErr), "string", "a rejected assignment must explain itself")
    assertFalse(offOk)
    assertEquals(type(offErr), "string", "a rejected assignment must explain itself")
    assertTableEquals(PurplexityRaidToolsRosterDB, before, "a rejected assignment writes nothing")
end

tests["a spec assignment for a character on no roster entry is rejected"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local before = snapshot()

        local ok, err = Roster:SetMainSpec(GRIMGRACE, PROTECTION)

        assertFalse(ok, "specs are assigned through the entry that owns the character")
        assertEquals(type(err), "string", "a rejected assignment must explain itself")
        assertTableEquals(PurplexityRaidToolsRosterDB, before)
    end)
end

tests["a main spec assignment persists the chosen spec"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local ok, err = Roster:SetMainSpec(OMNIVICENT, UMBRAL)

        assertTrue(ok, tostring(err))
        assertEquals(dataFor("Niv", OMNIVICENT).mainSpec, UMBRAL)
    end)
end

tests["a second main spec assignment replaces the first"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)
        Roster:SetMainSpec(OMNIVICENT, HOLY)

        assertEquals(dataFor("Niv", OMNIVICENT).mainSpec, HOLY,
            "each character has at most one main spec")
    end)
end

tests["a main spec assignment removes that spec from the off-spec list"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:AddOffSpec(OMNIVICENT, DISCIPLINE)
        Roster:AddOffSpec(OMNIVICENT, HOLY)

        Roster:SetMainSpec(OMNIVICENT, HOLY)

        local data = dataFor("Niv", OMNIVICENT)
        assertEquals(data.mainSpec, HOLY)
        assertTableEquals(data.offSpecs, { DISCIPLINE },
            "a spec is never both the main and an off-spec")
    end)
end

tests["a main spec from another class is rejected"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local ok, err = Roster:SetMainSpec(OMNIVICENT, ARCANE)

        assertFalse(ok, "only specs valid for the character's class are available")
        assertEquals(type(err), "string", "a rejected assignment must explain itself")
        assertNil(dataFor("Niv", OMNIVICENT).mainSpec)
    end)
end

tests["clearing the main spec leaves the off-specs untouched"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)
        Roster:AddOffSpec(OMNIVICENT, HOLY)

        local ok, err = Roster:SetMainSpec(OMNIVICENT, nil)

        assertTrue(ok, tostring(err))
        local data = dataFor("Niv", OMNIVICENT)
        assertNil(data.mainSpec)
        assertTableEquals(data.offSpecs, { HOLY })
    end)
end

tests["an off-spec assignment persists the chosen spec"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local ok, err = Roster:AddOffSpec(OMNIVICENT, DISCIPLINE)

        assertTrue(ok, tostring(err))
        assertTableEquals(dataFor("Niv", OMNIVICENT).offSpecs, { DISCIPLINE })
    end)
end

tests["an off-spec from another class is rejected"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        local ok, err = Roster:AddOffSpec(OMNIVICENT, FROST)

        assertFalse(ok, "only specs valid for the character's class are available")
        assertEquals(type(err), "string", "a rejected assignment must explain itself")
        assertTableEquals(dataFor("Niv", OMNIVICENT).offSpecs or {}, {})
    end)
end

tests["adding the main spec as an off-spec leaves it out of the off-spec list"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)

        Roster:AddOffSpec(OMNIVICENT, UMBRAL)

        local data = dataFor("Niv", OMNIVICENT)
        assertEquals(data.mainSpec, UMBRAL)
        assertTableEquals(data.offSpecs or {}, {},
            "the off-spec picker only ever offers the remaining specs")
    end)
end

tests["adding the same off-spec twice records it once"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:AddOffSpec(OMNIVICENT, HOLY)
        Roster:AddOffSpec(OMNIVICENT, HOLY)

        assertTableEquals(dataFor("Niv", OMNIVICENT).offSpecs, { HOLY })
    end)
end

tests["removing an off-spec drops it from the list"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT } } }, function()
        Roster:AddOffSpec(OMNIVICENT, DISCIPLINE)
        Roster:AddOffSpec(OMNIVICENT, HOLY)

        local ok, err = Roster:RemoveOffSpec(OMNIVICENT, DISCIPLINE)

        assertTrue(ok, tostring(err))
        assertTableEquals(dataFor("Niv", OMNIVICENT).offSpecs, { HOLY })
    end)
end

tests["off-specs are kept per character rather than per entry"] = function()
    withGroupRoster({ { "Niv", { OMNIVICENT, NIVEN } } }, function()
        Roster:SetMainSpec(OMNIVICENT, UMBRAL)
        Roster:AddOffSpec(NIVEN, FIRE)

        assertNil(dataFor("Niv", NIVEN).mainSpec)
        assertTableEquals(dataFor("Niv", NIVEN).offSpecs, { FIRE })
        assertTableEquals(dataFor("Niv", OMNIVICENT).offSpecs or {}, {})
    end)
end

return tests
