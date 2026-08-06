-- Roster: the officer-maintained player roster, stored as
-- PurplexityRaidToolsRosterDB[index] = { nickname, characters, characterData }.
-- characters is the ordered array of "Name-Realm" the attendance store reads,
-- its first entry the primary; characterData maps each of those names to the
-- class observed for it and its spec assignments.
--
-- The count call is namespaced and the info call is a bare global because
-- neither has a working twin on the other door (C_SpecializationInfo has no
-- info-by-class function on 12.x). Making the pair symmetric breaks one of them.
--
-- Headless-load safety: no frame, timer, or event API is touched at load, so the
-- roster loads under the test harness. The wiring layer supplies the class
-- sources through Roster.groupSource and Roster.guildSource.

local PRT = PurplexityRaidTools
local Roster = {}
PRT.Roster = Roster

local classIDsByToken

local function Trim(str)
    if type(str) ~= "string" then
        return ""
    end
    return string.match(str, "^%s*(.-)%s*$")
end

local function EnsureDB()
    PurplexityRaidToolsRosterDB = PurplexityRaidToolsRosterDB or {}
    return PurplexityRaidToolsRosterDB
end

local function ClassIDForToken(classToken)
    if not classIDsByToken then
        classIDsByToken = {}
        for classID = 1, GetNumClasses() do
            local info = C_CreatureInfo.GetClassInfo(classID)
            if info then
                classIDsByToken[info.classFile] = classID
            end
        end
    end
    return classIDsByToken[classToken]
end

local function SpecInfoForClass(classID, specIndex)
    return GetSpecializationInfoForClassID(classID, specIndex)
end

local function SpecsForClass(classToken)
    local classID = ClassIDForToken(classToken)
    if not classID then
        return nil
    end

    local specs = {}
    for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
        local specID, specName, _, specIcon = SpecInfoForClass(classID, specIndex)
        if specID then
            specs[#specs + 1] = { id = specID, name = specName, icon = specIcon }
        end
    end
    return specs
end

local function IsSpecOfClass(classToken, specID)
    local specs = SpecsForClass(classToken)
    if not specs then
        return false
    end

    for _, spec in ipairs(specs) do
        if spec.id == specID then
            return true
        end
    end
    return false
end

local function HasSpec(specs, specID)
    if not specs then
        return false
    end

    for _, existing in ipairs(specs) do
        if existing == specID then
            return true
        end
    end
    return false
end

local function RemoveSpec(specs, specID)
    if not specs then
        return
    end

    for index, existing in ipairs(specs) do
        if existing == specID then
            table.remove(specs, index)
            return
        end
    end
end

local function FindEntryByNickname(db, nickname)
    for _, entry in ipairs(db) do
        if entry.nickname == nickname then
            return entry
        end
    end
    return nil
end

local function FindEntryOwningCharacter(db, character)
    for _, entry in ipairs(db) do
        for _, owned in ipairs(entry.characters) do
            if owned == character then
                return entry
            end
        end
    end
    return nil
end

local function ValidateSubmission(db, nickname, characters, ownEntry)
    if nickname == "" then
        return false, "A roster entry needs a nickname."
    end
    if not characters or #characters == 0 then
        return false, "A roster entry needs at least one character."
    end

    local named = FindEntryByNickname(db, nickname)
    if named and named ~= ownEntry then
        return false, "A roster entry named " .. nickname .. " already exists."
    end

    local seen = {}
    for _, character in ipairs(characters) do
        if seen[character] then
            return false, character .. " is listed twice on the same entry."
        end
        seen[character] = true

        local owner = FindEntryOwningCharacter(db, character)
        if owner and owner ~= ownEntry then
            return false, character .. " already belongs to " .. owner.nickname .. "."
        end
    end

    return true
end

local function AssignableRecord(db, character)
    local entry = FindEntryOwningCharacter(db, character)
    if not entry then
        return nil, "No roster entry owns " .. tostring(character) .. "."
    end

    local record = entry.characterData[character]
    if not record.class then
        return nil,
            "The class of " .. tostring(character) .. " is unknown, so it has no specs to assign."
    end

    return record
end

local function ClassFromSource(source, character)
    if not source then
        return nil
    end

    local members = source()
    if not members then
        return nil
    end

    for _, member in pairs(members) do
        if member.name == character then
            return member.class
        end
    end
    return nil
end

function Roster:GetEntries()
    return EnsureDB()
end

function Roster:ResolveClass(character)
    local fromGroup = ClassFromSource(self.groupSource, character)
    if fromGroup then
        return fromGroup
    end
    return ClassFromSource(self.guildSource, character)
end

function Roster:AddEntry(nickname, characters)
    local db = EnsureDB()
    local trimmedNickname = Trim(nickname)

    local valid, err = ValidateSubmission(db, trimmedNickname, characters, nil)
    if not valid then
        return false, err
    end

    local entry = { nickname = trimmedNickname, characters = {}, characterData = {} }
    for index, character in ipairs(characters) do
        entry.characters[index] = character
        entry.characterData[character] = { class = self:ResolveClass(character) }
    end

    db[#db + 1] = entry
    return true
end

function Roster:UpdateEntry(target, nickname, characters)
    local db = EnsureDB()
    local entry = FindEntryByNickname(db, target)
    if not entry then
        return false, "No roster entry named " .. tostring(target) .. "."
    end

    local trimmedNickname = Trim(nickname)
    local valid, err = ValidateSubmission(db, trimmedNickname, characters, entry)
    if not valid then
        return false, err
    end

    local previousData = entry.characterData
    local updatedCharacters, updatedData = {}, {}
    for index, character in ipairs(characters) do
        updatedCharacters[index] = character
        updatedData[character] = previousData[character]
            or { class = self:ResolveClass(character) }
    end

    entry.nickname = trimmedNickname
    entry.characters = updatedCharacters
    entry.characterData = updatedData
    return true
end

function Roster:RemoveEntry(nickname)
    local db = EnsureDB()
    for index, entry in ipairs(db) do
        if entry.nickname == nickname then
            table.remove(db, index)
            return true
        end
    end
    return false
end

function Roster:ImportFromRecord(dayRecord)
    local db = EnsureDB()
    local added, skipped = {}, {}

    for character in pairs(dayRecord) do
        if not FindEntryOwningCharacter(db, character) then
            if self:AddEntry(character, { character }) then
                added[#added + 1] = character
            else
                skipped[#skipped + 1] = character
            end
        end
    end

    return { added = added, skipped = skipped }
end

function Roster:RefreshClasses()
    for _, entry in ipairs(EnsureDB()) do
        for _, character in ipairs(entry.characters) do
            local record = entry.characterData[character]
            if not record.class then
                record.class = self:ResolveClass(character)
            end
        end
    end
end

function Roster:GetCharacterClass(character)
    local entry = FindEntryOwningCharacter(EnsureDB(), character)
    if not entry then
        return nil
    end
    return entry.characterData[character].class
end

function Roster:GetSpecsForCharacter(character)
    local classToken = self:GetCharacterClass(character)
    if not classToken then
        return nil
    end
    return SpecsForClass(classToken)
end

function Roster:SetMainSpec(character, specID)
    local record, err = AssignableRecord(EnsureDB(), character)
    if not record then
        return false, err
    end

    if specID == nil then
        record.mainSpec = nil
        return true
    end

    if not IsSpecOfClass(record.class, specID) then
        return false, "Specialization " .. tostring(specID)
            .. " is not available to a " .. record.class .. "."
    end

    record.mainSpec = specID
    RemoveSpec(record.offSpecs, specID)
    return true
end

function Roster:AddOffSpec(character, specID)
    local record, err = AssignableRecord(EnsureDB(), character)
    if not record then
        return false, err
    end

    if not IsSpecOfClass(record.class, specID) then
        return false, "Specialization " .. tostring(specID)
            .. " is not available to a " .. record.class .. "."
    end

    if specID == record.mainSpec then
        return true
    end

    local offSpecs = record.offSpecs or {}
    if HasSpec(offSpecs, specID) then
        return true
    end

    offSpecs[#offSpecs + 1] = specID
    record.offSpecs = offSpecs
    return true
end

function Roster:RemoveOffSpec(character, specID)
    local record, err = AssignableRecord(EnsureDB(), character)
    if not record then
        return false, err
    end

    RemoveSpec(record.offSpecs, specID)
    return true
end

function Roster:MoveCharacter(character, sourceNickname, destNickname)
    if sourceNickname == destNickname then
        return true
    end

    local db = EnsureDB()

    local source = FindEntryByNickname(db, sourceNickname)
    if not source then
        return false, "No roster entry named " .. tostring(sourceNickname) .. "."
    end

    local dest = FindEntryByNickname(db, destNickname)
    if not dest then
        return false, "No roster entry named " .. tostring(destNickname) .. "."
    end

    local charIndex
    for i, owned in ipairs(source.characters) do
        if owned == character then
            charIndex = i
            break
        end
    end
    if not charIndex then
        return false, character .. " is not in " .. sourceNickname .. "'s character list."
    end

    for _, owned in ipairs(dest.characters) do
        if owned == character then
            return false
        end
    end

    table.remove(source.characters, charIndex)

    local data = source.characterData[character]
    source.characterData[character] = nil
    dest.characterData[character] = data

    dest.characters[#dest.characters + 1] = character

    if #source.characters == 0 then
        for i, entry in ipairs(db) do
            if entry == source then
                table.remove(db, i)
                break
            end
        end
    end

    return true
end
