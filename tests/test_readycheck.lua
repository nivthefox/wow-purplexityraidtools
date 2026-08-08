local tests = {}

local PRT = PurplexityRaidTools

if not PRT.GroupInspect then
    PRT.GroupInspect = { members = {} }
end
if not PRT.ReadyCheck then
    dofile("Modules/ReadyCheck.lua")
end

local ReadyCheck = PRT.ReadyCheck

local PLAYER_GUID = "GUID-PLAYER"
local PLAYER_NAME = "Niv-Illidan"
local LOCAL_VERSION = 1002000
local MISSING_MESSAGE = "Your raid leader is using PurplexityRaidTools for coordination. Please make sure you have it installed."

local function baseSettings()
    return {
        enabled = true,
        snarkyMessages = false,
        checkSoulstones = false,
        checkDead = false,
        whisperMissingAddon = "off",
        whisperOutdatedAddon = "off",
        arcaneIntellect = false,
        battleShout = false,
        blessingOfTheBronze = false,
        markOfTheWild = false,
        powerWordFortitude = false,
        skyfury = false,
    }
end

local function member(name, version, specId)
    local resolvedSpecId = specId
    if specId == nil then
        resolvedSpecId = 65
    elseif specId == false then
        resolvedSpecId = nil
    end

    return {
        name = name,
        class = "PALADIN",
        specId = resolvedSpecId,
        addonVersion = version,
    }
end

local function withReadyCheck(options, body)
    options = options or {}
    local settings = options.settings or baseSettings()
    local members = options.members or {}
    members[PLAYER_GUID] = members[PLAYER_GUID] or member(PLAYER_NAME, LOCAL_VERSION)

    local sent = {}
    local guildRoster = options.guildRoster or {}
    local savedGlobals = {}
    local globals = {
        IsInRaid = function() return options.inRaid ~= false end,
        UnitIsGroupLeader = function() return options.isLeader ~= false end,
        UnitGUID = function(unit)
            if unit == "player" then
                return PLAYER_GUID
            end
            return nil
        end,
        UnitIsConnected = function() return true end,
        IsInGuild = function() return options.inGuild ~= false end,
        GetNumGuildMembers = function() return #guildRoster end,
        GetGuildRosterInfo = function(index) return guildRoster[index] end,
        GetNormalizedRealmName = function() return "Illidan" end,
        C_Secrets = { ShouldAurasBeSecret = function() return false end },
        C_ChatInfo = {
            SendChatMessage = options.sendChatMessage or function(messageText, channel, _, target)
                sent[#sent + 1] = { message = messageText, channel = channel, target = target }
            end,
        },
    }

    for name, value in pairs(globals) do
        savedGlobals[name] = _G[name]
        _G[name] = value
    end

    local savedGetSetting = PRT.GetSetting
    local savedIterateGroup = PRT.IterateGroup
    local savedMembers = PRT.GroupInspect.members
    PRT.GetSetting = function(_, key)
        if key == "readyCheck" then
            return settings
        end
        return nil
    end
    PRT.IterateGroup = function()
        return function() return nil end
    end
    PRT.GroupInspect.members = members

    local ok, err = pcall(body, sent, settings, members)

    PRT.GetSetting = savedGetSetting
    PRT.IterateGroup = savedIterateGroup
    PRT.GroupInspect.members = savedMembers
    for name in pairs(globals) do
        _G[name] = savedGlobals[name]
    end

    if not ok then
        error(err, 0)
    end
end

tests["version whisper settings default to guild only"] = function()
    assertEquals(PRT.defaults.readyCheck.whisperMissingAddon, "guild")
    assertEquals(PRT.defaults.readyCheck.whisperOutdatedAddon, "guild")
end

tests["DecodeVersion restores human-readable semantic versions"] = function()
    assertEquals(ReadyCheck.DecodeVersion(1001003), "1.1.3")
    assertEquals(ReadyCheck.DecodeVersion(2015007), "2.15.7")
    assertEquals(ReadyCheck.DecodeVersion(0), "0.0.0")
end

tests["missing addon preference on whispers inspected members"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "on"
    withReadyCheck({
        settings = settings,
        members = { ["GUID-MISSING"] = member("Missing-Illidan", nil) },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 1)
        assertEquals(sent[1].target, "Missing-Illidan")
        assertEquals(sent[1].channel, "WHISPER")
        assertEquals(sent[1].message, MISSING_MESSAGE)
    end)
end

tests["outdated addon preference on whispers decoded versions"] = function()
    local settings = baseSettings()
    settings.whisperOutdatedAddon = "on"
    withReadyCheck({
        settings = settings,
        members = { ["GUID-OLD"] = member("Old-Illidan", 1000000) },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 1)
        assertEquals(sent[1].target, "Old-Illidan")
        assertEquals(
            sent[1].message,
            "Your version of PurplexityRaidTools (1.0.0) is out of date. Please update to 1.2.0."
        )
    end)
end

tests["equal versions and uninspected members are skipped"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "on"
    settings.whisperOutdatedAddon = "on"
    withReadyCheck({
        settings = settings,
        members = {
            ["GUID-EQUAL"] = member("Equal-Illidan", LOCAL_VERSION),
            ["GUID-UNKNOWN"] = member("Unknown-Illidan", nil, false),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 0)
    end)
end

tests["off preferences suppress their matching conditions"] = function()
    withReadyCheck({
        members = {
            ["GUID-MISSING"] = member("Missing-Illidan", nil),
            ["GUID-OLD"] = member("Old-Illidan", 1000000),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 0)
    end)
end

tests["guild-only missing addon preference whispers only guild members"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "guild"
    withReadyCheck({
        settings = settings,
        guildRoster = { "Guildie-Illidan" },
        members = {
            ["GUID-GUILD"] = member("Guildie", nil),
            ["GUID-OUTSIDER"] = member("Outsider-Illidan", nil),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 1)
        assertEquals(sent[1].target, "Guildie")
    end)
end

tests["guild-only outdated addon preference whispers only guild members"] = function()
    local settings = baseSettings()
    settings.whisperOutdatedAddon = "guild"
    withReadyCheck({
        settings = settings,
        guildRoster = { "Guildie-Illidan" },
        members = {
            ["GUID-GUILD"] = member("Guildie-Illidan", 0),
            ["GUID-OUTSIDER"] = member("Outsider-Illidan", 1000000),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 1)
        assertEquals(sent[1].target, "Guildie-Illidan")
        assertTrue(sent[1].message:find("0.0.0", 1, true) ~= nil)
    end)
end

tests["guild-only preferences act as off when the raid leader is unguilded"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "guild"
    settings.whisperOutdatedAddon = "guild"
    withReadyCheck({
        settings = settings,
        inGuild = false,
        guildRoster = { "Missing-Illidan", "Old-Illidan" },
        members = {
            ["GUID-MISSING"] = member("Missing-Illidan", nil),
            ["GUID-OLD"] = member("Old-Illidan", 1000000),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 0)
    end)
end

tests["version whispers repeat on every ready check and never target the local player"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "on"
    withReadyCheck({
        settings = settings,
        members = {
            [PLAYER_GUID] = member(PLAYER_NAME, nil),
            ["GUID-MISSING"] = member("Missing-Illidan", nil),
        },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 2)
        assertEquals(sent[1].target, "Missing-Illidan")
        assertEquals(sent[2].target, "Missing-Illidan")
    end)
end

tests["non-leaders do not send version whispers"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "on"
    withReadyCheck({
        settings = settings,
        isLeader = false,
        members = { ["GUID-MISSING"] = member("Missing-Illidan", nil) },
    }, function(sent)
        ReadyCheck:OnReadyCheck()
        assertEquals(#sent, 0)
    end)
end

tests["one failed whisper does not interrupt later recipients"] = function()
    local settings = baseSettings()
    settings.whisperMissingAddon = "on"
    local attempted = {}
    withReadyCheck({
        settings = settings,
        members = {
            ["GUID-A"] = member("Alpha-Illidan", nil),
            ["GUID-B"] = member("Bravo-Illidan", nil),
            ["GUID-C"] = member("Charlie-Illidan", nil),
        },
        sendChatMessage = function(_, _, _, target)
            attempted[target] = true
            if target == "Bravo-Illidan" then
                error("simulated send failure")
            end
        end,
    }, function()
        ReadyCheck:OnReadyCheck()
        assertTrue(attempted["Alpha-Illidan"])
        assertTrue(attempted["Bravo-Illidan"])
        assertTrue(attempted["Charlie-Illidan"])
    end)
end

return tests
