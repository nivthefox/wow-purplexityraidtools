local PRT = PurplexityRaidTools
local Validation = {}
PRT.RosterValidation = Validation

Validation.MAX_NICKNAME_LENGTH = 12

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function Trim(value)
    if type(value) ~= "string" or IsSecret(value) then
        return nil
    end
    return string.match(value, "^%s*(.-)%s*$")
end

local function DecodeLength(value, index)
    local first = string.byte(value, index)
    if not first then
        return nil
    end
    if first <= 0x7F then
        return 1, first
    end

    local second = string.byte(value, index + 1)
    if first >= 0xC2 and first <= 0xDF
        and second and second >= 0x80 and second <= 0xBF then
        return 2, (first - 0xC0) * 0x40 + second - 0x80
    end

    local third = string.byte(value, index + 2)
    if first >= 0xE0 and first <= 0xEF
        and second and second >= 0x80 and second <= 0xBF
        and third and third >= 0x80 and third <= 0xBF
        and not (first == 0xE0 and second < 0xA0)
        and not (first == 0xED and second >= 0xA0) then
        return 3, (first - 0xE0) * 0x1000
            + (second - 0x80) * 0x40 + third - 0x80
    end

    local fourth = string.byte(value, index + 3)
    if first >= 0xF0 and first <= 0xF4
        and second and second >= 0x80 and second <= 0xBF
        and third and third >= 0x80 and third <= 0xBF
        and fourth and fourth >= 0x80 and fourth <= 0xBF
        and not (first == 0xF0 and second < 0x90)
        and not (first == 0xF4 and second >= 0x90) then
        return 4, (first - 0xF0) * 0x40000
            + (second - 0x80) * 0x1000
            + (third - 0x80) * 0x40 + fourth - 0x80
    end

    return nil
end

local function ValidateUTF8(value)
    local index, count = 1, 0
    while index <= #value do
        local length, codepoint = DecodeLength(value, index)
        if not length then
            return nil
        end
        if codepoint <= 0x1F or codepoint == 0x7F
            or codepoint >= 0x80 and codepoint <= 0x9F then
            return nil, true
        end
        index = index + length
        count = count + 1
    end
    return count, false
end

function Validation:TruncateUTF8(value, maximum)
    if type(value) ~= "string" or IsSecret(value) then
        return nil
    end

    local index, count = 1, 0
    while index <= #value do
        local length = DecodeLength(value, index)
        if not length then
            return nil
        end
        if count == maximum then
            return string.sub(value, 1, index - 1)
        end
        index = index + length
        count = count + 1
    end
    return value
end

function Validation:ValidateNickname(value, shorten)
    local nickname = Trim(value)
    if not nickname or nickname == "" then
        return nil, "A roster entry needs a nickname."
    end
    if string.find(nickname, "|") then
        return nil, "Roster nicknames cannot contain control characters or WoW formatting escapes."
    end

    local length, hasControl = ValidateUTF8(nickname)
    if not length then
        if hasControl then
            return nil, "Roster nicknames cannot contain control characters or WoW formatting escapes."
        end
        return nil, "Roster nicknames must contain valid UTF-8 text."
    end
    if length > self.MAX_NICKNAME_LENGTH and not shorten then
        return nil, "Roster nicknames can contain at most 12 characters."
    end
    if length > self.MAX_NICKNAME_LENGTH then
        return self:TruncateUTF8(nickname, self.MAX_NICKNAME_LENGTH)
    end
    return nickname
end

function Validation:NormalizeIdentity(value)
    local identity = Trim(value)
    local length, hasControl
    if identity then
        length, hasControl = ValidateUTF8(identity)
    end
    if not identity or identity == "" or not length or hasControl or string.find(identity, "|") then
        return nil
    end

    local name, realm = string.match(identity, "^([^-]+)%-(.+)$")
    name = Trim(name)
    realm = Trim(realm)
    if not name or name == "" or not realm or realm == "" then
        return nil
    end
    return string.lower(name .. "-" .. realm)
end

function Validation:IdentitiesEqual(first, second)
    local normalizedFirst = self:NormalizeIdentity(first)
    local normalizedSecond = self:NormalizeIdentity(second)
    if not normalizedFirst or not normalizedSecond then
        return false
    end
    if type(strcmputf8i) == "function" then
        return strcmputf8i(normalizedFirst, normalizedSecond) == 0
    end
    return normalizedFirst == normalizedSecond
end

local function Copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copied = {}
    seen[value] = copied
    for key, child in pairs(value) do
        copied[Copy(key, seen)] = Copy(child, seen)
    end
    return copied
end

local function IsSoundCharacterRecord(record)
    if type(record) ~= "table" then
        return false
    end
    if record.class ~= nil and type(record.class) ~= "string" then
        return false
    end
    if record.mainSpec ~= nil and type(record.mainSpec) ~= "number" then
        return false
    end
    if record.offSpecs ~= nil and type(record.offSpecs) ~= "table" then
        return false
    end
    if record.offSpecs then
        for _, specID in ipairs(record.offSpecs) do
            if type(specID) ~= "number" then
                return false
            end
        end
    end
    return true
end

function Validation:PrepareEntries(entries)
    if type(entries) ~= "table" then
        return nil, "A roster must be an ordered list."
    end

    local keyCount = 0
    for _ in pairs(entries) do
        keyCount = keyCount + 1
    end
    if keyCount ~= #entries then
        return nil, "A roster must be an ordered list."
    end

    local prepared = {}
    local claimedNicknames, claimedCharacters = {}, {}
    for index, source in ipairs(entries) do
        if type(source) ~= "table" or type(source.characters) ~= "table"
            or #source.characters == 0 or type(source.characterData) ~= "table" then
            return nil, "Roster entry " .. index .. " is incomplete."
        end

        local nickname, nicknameError = self:ValidateNickname(source.nickname, true)
        if not nickname then
            return nil, nicknameError
        end
        if claimedNicknames[nickname] then
            return nil, "A roster entry named " .. nickname .. " already exists."
        end
        claimedNicknames[nickname] = true

        local entry = { nickname = nickname, characters = {}, characterData = {} }
        local characterKeyCount = 0
        for _ in pairs(source.characters) do
            characterKeyCount = characterKeyCount + 1
        end
        if characterKeyCount ~= #source.characters then
            return nil, "Roster entry " .. nickname .. " has an invalid character list."
        end

        local exactCharacters = {}
        for characterIndex, character in ipairs(source.characters) do
            local trimmed = Trim(character)
            if not trimmed or trimmed == "" or string.find(trimmed, "[%c|]") then
                return nil, "Roster entry " .. nickname .. " has an invalid character name."
            end
            if exactCharacters[trimmed] then
                return nil, trimmed .. " is listed twice on the same entry."
            end
            exactCharacters[trimmed] = true

            local normalized = self:NormalizeIdentity(trimmed)
            if normalized then
                for _, claim in ipairs(claimedCharacters) do
                    if self:IdentitiesEqual(normalized, claim.identity) then
                        return nil, trimmed .. " already belongs to " .. claim.nickname .. "."
                    end
                end
                claimedCharacters[#claimedCharacters + 1] = {
                    identity = normalized,
                    nickname = nickname,
                }
            end

            local record = source.characterData[character]
            if not IsSoundCharacterRecord(record) then
                return nil, "Roster entry " .. nickname .. " has invalid character data for " .. trimmed .. "."
            end
            entry.characters[characterIndex] = trimmed
            entry.characterData[trimmed] = Copy(record)
        end
        prepared[index] = entry
    end
    return prepared
end
