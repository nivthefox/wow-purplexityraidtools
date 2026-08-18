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
local listeners = {}
local Validation = PRT.RosterValidation

local function EnsureDB()
    PurplexityRaidToolsRosterDB = PurplexityRaidToolsRosterDB or {}
    return PurplexityRaidToolsRosterDB
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function RejectCombat()
    return false, "The roster cannot be changed during combat."
end

local function NotifyListeners()
    for index = 1, #listeners do
        listeners[index]()
    end
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
    local normalizedCharacter = Validation:NormalizeIdentity(character)
    for _, entry in ipairs(db) do
        for _, owned in ipairs(entry.characters) do
            if normalizedCharacter and Validation:IdentitiesEqual(owned, normalizedCharacter) then
                return entry
            end
            if not normalizedCharacter and owned == character then
                return entry
            end
        end
    end
    return nil
end

local function ValidateSubmission(db, nickname, characters, ownEntry)
    local normalizedNickname, nicknameError = Validation:ValidateNickname(nickname, false)
    if not normalizedNickname then
        return false, nicknameError
    end
    if not characters or #characters == 0 then
        return false, "A roster entry needs at least one character."
    end

    local named = FindEntryByNickname(db, normalizedNickname)
    if named and named ~= ownEntry then
        return false, "A roster entry named " .. normalizedNickname .. " already exists."
    end

    local seen = {}
    for _, character in ipairs(characters) do
        if type(character) ~= "string" or character == "" then
            return false, "A roster character needs a name."
        end
        local normalizedCharacter = Validation:NormalizeIdentity(character)
        for _, seenCharacter in ipairs(seen) do
            local duplicate = normalizedCharacter
                and Validation:IdentitiesEqual(normalizedCharacter, seenCharacter)
                or not normalizedCharacter and character == seenCharacter
            if duplicate then
                return false, character .. " is listed twice on the same entry."
            end
        end
        seen[#seen + 1] = normalizedCharacter or character

        local owner = FindEntryOwningCharacter(db, character)
        if owner and owner ~= ownEntry then
            return false, character .. " already belongs to " .. owner.nickname .. "."
        end
    end

    return true, nil, normalizedNickname
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

function Roster:Listen(callback)
    listeners[#listeners + 1] = callback
end

function Roster:ResolveNickname(identity)
    local normalized = Validation:NormalizeIdentity(identity)
    if not normalized then
        return nil
    end

    for _, entry in ipairs(EnsureDB()) do
        for _, character in ipairs(entry.characters) do
            if Validation:IdentitiesEqual(character, normalized) then
                return entry.nickname
            end
        end
    end
    return nil
end

function Roster:PrepareReplacement(entries)
    return Validation:PrepareEntries(entries)
end

function Roster:ReplaceEntries(entries)
    if InCombat() then
        return RejectCombat()
    end

    local prepared, err = self:PrepareReplacement(entries)
    if not prepared then
        return false, err
    end

    local db = EnsureDB()
    wipe(db)
    for index, entry in ipairs(prepared) do
        db[index] = entry
    end
    NotifyListeners()
    return true
end

function Roster:NormalizeStoredEntries()
    local prepared, err = self:PrepareReplacement(EnsureDB())
    if not prepared then
        return false, err
    end

    local db = EnsureDB()
    wipe(db)
    for index, entry in ipairs(prepared) do
        db[index] = entry
    end
    return true
end

function Roster:ResolveClass(character)
    local fromGroup = ClassFromSource(self.groupSource, character)
    if fromGroup then
        return fromGroup
    end
    return ClassFromSource(self.guildSource, character)
end

function Roster:AddEntry(nickname, characters)
    if InCombat() then
        return RejectCombat()
    end

    local db = EnsureDB()

    local valid, err, normalizedNickname = ValidateSubmission(db, nickname, characters, nil)
    if not valid then
        return false, err
    end

    local entry = { nickname = normalizedNickname, characters = {}, characterData = {} }
    for index, character in ipairs(characters) do
        entry.characters[index] = character
        entry.characterData[character] = { class = self:ResolveClass(character) }
    end

    db[#db + 1] = entry
    NotifyListeners()
    return true
end

function Roster:UpdateEntry(target, nickname, characters)
    if InCombat() then
        return RejectCombat()
    end

    local db = EnsureDB()
    local entry = FindEntryByNickname(db, target)
    if not entry then
        return false, "No roster entry named " .. tostring(target) .. "."
    end

    local valid, err, normalizedNickname = ValidateSubmission(db, nickname, characters, entry)
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

    entry.nickname = normalizedNickname
    entry.characters = updatedCharacters
    entry.characterData = updatedData
    NotifyListeners()
    return true
end

function Roster:RemoveEntry(nickname)
    if InCombat() then
        return RejectCombat()
    end

    local db = EnsureDB()
    for index, entry in ipairs(db) do
        if entry.nickname == nickname then
            table.remove(db, index)
            NotifyListeners()
            return true
        end
    end
    return false
end

function Roster:ImportFromRecord(dayRecord)
    if InCombat() then
        return RejectCombat()
    end

    local db = EnsureDB()
    local added, skipped = {}, {}

    for character in pairs(dayRecord) do
        if not FindEntryOwningCharacter(db, character) then
            local nickname = Validation:ValidateNickname(character, true)
            local valid = nickname and ValidateSubmission(db, nickname, { character }, nil)
            if valid then
                local entry = {
                    nickname = nickname,
                    characters = { character },
                    characterData = { [character] = { class = self:ResolveClass(character) } },
                }
                db[#db + 1] = entry
                added[#added + 1] = character
            else
                skipped[#skipped + 1] = character
            end
        end
    end

    if #added > 0 then
        NotifyListeners()
    end
    return { added = added, skipped = skipped }
end

function Roster:RefreshClasses()
    if InCombat() then
        return RejectCombat()
    end

    local changed = false
    for _, entry in ipairs(EnsureDB()) do
        for _, character in ipairs(entry.characters) do
            local record = entry.characterData[character]
            if not record.class then
                record.class = self:ResolveClass(character)
                changed = changed or record.class ~= nil
            end
        end
    end
    if changed then
        NotifyListeners()
    end
    return true
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
    if InCombat() then
        return RejectCombat()
    end

    local record, err = AssignableRecord(EnsureDB(), character)
    if not record then
        return false, err
    end

    if specID == nil then
        local changed = record.mainSpec ~= nil
        record.mainSpec = nil
        if changed then
            NotifyListeners()
        end
        return true
    end

    if not IsSpecOfClass(record.class, specID) then
        return false, "Specialization " .. tostring(specID)
            .. " is not available to a " .. record.class .. "."
    end

    record.mainSpec = specID
    RemoveSpec(record.offSpecs, specID)
    NotifyListeners()
    return true
end

function Roster:AddOffSpec(character, specID)
    if InCombat() then
        return RejectCombat()
    end

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
    NotifyListeners()
    return true
end

function Roster:RemoveOffSpec(character, specID)
    if InCombat() then
        return RejectCombat()
    end

    local record, err = AssignableRecord(EnsureDB(), character)
    if not record then
        return false, err
    end

    local hadSpec = HasSpec(record.offSpecs, specID)
    RemoveSpec(record.offSpecs, specID)
    if hadSpec then
        NotifyListeners()
    end
    return true
end

function Roster:MoveCharacter(character, sourceNickname, destNickname)
    if InCombat() then
        return RejectCombat()
    end

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

    NotifyListeners()
    return true
end
