-- tests/test_groupinspect.lua
-- Addon version detection in Modules/GroupInspect.lua: EncodeVersion,
-- group-channel discovery, and the addonVersion field on member records.
-- The inspect loop runs on file-local C_Timer tickers, so this suite captures
-- the ticker callbacks (1s drains the inspect queues, 60s refills the sweep)
-- and fires them by hand.

local tests = {}

if not PurplexityRaidTools.GearAudit then
    dofile("Modules/GearAudit.lua")
end

if not PurplexityRaidTools.Comms then
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/LibSerialize/LibSerialize.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")
    dofile("Comms.lua")
end

if not PurplexityRaidTools.GroupInspect then
    dofile("Modules/GroupInspect.lua")
end

local PRT = PurplexityRaidTools
local GroupInspect = PRT.GroupInspect
local Comms = PRT.Comms

local onEventHandler
GroupInspect.eventFrame = {
    RegisterEvent = function() end,
    UnregisterAllEvents = function() end,
    SetScript = function(_, _, handler) onEventHandler = handler end,
}
GroupInspect:Initialize()

-- Deliberately NOT the real .toc version, and encoding to a value no other test
-- expects: a GetLocalVersion() that hardcodes a number instead of reading
-- C_AddOns metadata cannot pass the local-player and responder tests.
local LOCAL_VERSION_STRING = "3.7.2-beta-1"
local LOCAL_ENCODED_VERSION = 3007002
local SPEC_ID = 71
local LOCAL_EQUIPPED_ITEM_LEVEL = 712.5
local REMOTE_EQUIPPED_ITEM_LEVEL = 706.25
local LOCAL_REALM = "Illidan"
local UNKNOWN_UNIT_NAME = "Unknown"

local UNITS = {
    raid1 = { guid = "GUID-NIV", name = "Niv", isPlayer = true },
    raid2 = { guid = "GUID-BOB", name = "Bob" },
    raid3 = { guid = "GUID-ZED", name = "Zed", realm = "Area52" },
    raid4 = { guid = "GUID-MAE", name = "Mae", offline = true },
    raid5 = { guid = "GUID-TEK", name = "Tek", realm = "" },
    raid6 = { guid = "CREATURE-FOLLOWER", name = "Follower", isNPC = true },
}

local function unitNameWithServer(unit)
    if not unit.realm or unit.realm == "" then
        return unit.name
    end
    return unit.name .. "-" .. unit.realm
end

local SENDER_GUIDS = {
    ["Bob-Illidan"] = "GUID-BOB",
    ["Zed-Area52"] = "GUID-ZED",
}

local sim

local function newSim()
    return {
        units = {},
        unitsAwaitingNameData = {},
        unitsAwaitingGuid = {},
        localRealm = LOCAL_REALM,
        scheduledCallbacks = {},
        inspectedUnits = {},
        inspectChecks = {},
        uninspectableUnits = {},
        sentMessages = {},
        groupChannel = "RAID",
    }
end

local tickerFns = {}

local function flushTimers()
    local i = 1
    while i <= #sim.scheduledCallbacks do
        sim.scheduledCallbacks[i]()
        i = i + 1
    end
    sim.scheduledCallbacks = {}
end

local function driveInspectTick()
    assertNotNil(tickerFns.inspect, "inspect ticker must have been started by ScanRoster")
    tickerFns.inspect()
end

local function driveSweepTick()
    assertNotNil(tickerFns.sweep, "sweep ticker must have been started by ScanRoster")
    tickerFns.sweep()
end

local function sentOfType(msgType)
    local matches = {}
    for _, msg in ipairs(sim.sentMessages) do
        if msg.type == msgType then
            table.insert(matches, msg)
        end
    end
    return matches
end

local function countMembers()
    local count = 0
    for _ in pairs(GroupInspect.members) do
        count = count + 1
    end
    return count
end

local function nameDataUnavailable(unitToken)
    return sim.unitsAwaitingNameData[unitToken] == true
end

local function makeStubs()
    return {
        GetInventoryItemLink = function(unit, slot)
            if sim.onReadEquipment then sim.onReadEquipment(unit, slot) end
            return sim.equipment and sim.equipment[unit] and sim.equipment[unit][slot]
        end,
        C_Item = {
            IsItemDataCachedByID = function() return sim.itemCached ~= false end,
            RequestLoadItemDataByID = function()
                sim.itemRequests = (sim.itemRequests or 0) + 1
            end,
            GetItemInfoInstant = function() return 100, nil, nil, "INVTYPE_WEAPON" end,
            GetItemStats = function() return {} end,
            GetItemGemID = function() return nil end,
        },
        UnitGUID = function(unitOrSender)
            local unit = UNITS[unitOrSender]
            if unit then
                if sim.unitsAwaitingGuid[unitOrSender] then
                    return nil
                end
                return unit.guid
            end
            return SENDER_GUIDS[unitOrSender]
        end,
        UnitName = function(unitToken)
            local unit = UNITS[unitToken]
            if not unit then
                return unitToken
            end
            if nameDataUnavailable(unitToken) then
                return UNKNOWN_UNIT_NAME, nil
            end
            return unit.name, unit.realm
        end,
        GetNormalizedRealmName = function()
            return sim.localRealm
        end,
        UNKNOWNOBJECT = UNKNOWN_UNIT_NAME,
        UnitClass = function()
            return "Warrior", "WARRIOR"
        end,
        GetUnitName = function(unitToken, showServerName)
            local unit = UNITS[unitToken]
            if not unit then
                return unitToken
            end
            if nameDataUnavailable(unitToken) then
                return UNKNOWN_UNIT_NAME
            end
            if showServerName then
                return unitNameWithServer(unit)
            end
            return unit.name
        end,
        UnitIsUnit = function(unitA, unitB)
            if unitB ~= "player" then
                return unitA == unitB
            end
            local unit = UNITS[unitA]
            if not unit then
                return false
            end
            return unit.isPlayer == true
        end,
        UnitIsConnected = function(unitToken)
            local unit = UNITS[unitToken]
            if not unit then
                return false
            end
            return not unit.offline
        end,
        UnitIsPlayer = function(unitToken)
            local unit = UNITS[unitToken]
            return unit ~= nil and not unit.isNPC
        end,
        UnitExists = function(unitToken)
            for i = 1, #sim.units do
                if sim.units[i] == unitToken then
                    return true
                end
            end
            return false
        end,
        CanInspect = function(unitToken, showError)
            table.insert(sim.inspectChecks, { unit = unitToken, showError = showError })
            local unit = UNITS[unitToken]
            return unit ~= nil and not unit.offline
                and not sim.uninspectableUnits[unitToken]
        end,
        UnitAffectingCombat = function() return false end,
        LE_PARTY_CATEGORY_HOME = 1,
        LE_PARTY_CATEGORY_INSTANCE = 2,
        IsInGroup = function(category)
            if category == 2 then
                return #sim.units > 0 and sim.groupChannel == "INSTANCE_CHAT"
            end
            if category == 1 then
                return #sim.units > 0 and sim.groupChannel ~= "INSTANCE_CHAT"
            end
            return #sim.units > 0
        end,
        IsInRaid = function(category)
            if category == 2 then
                return false
            end
            return #sim.units > 0 and sim.groupChannel == "RAID"
        end,
        IsInInstance = function()
            return sim.groupChannel == "INSTANCE_CHAT"
        end,
        NotifyInspect = function(unitToken)
            table.insert(sim.inspectedUnits, unitToken)
        end,
        ClearInspectPlayer = function() end,
        Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } },
        C_Traits = { GetConfigInfo = function() return nil end },
        GetInspectSpecialization = function() return SPEC_ID end,
        GetAverageItemLevel = function()
            return 730, LOCAL_EQUIPPED_ITEM_LEVEL
        end,
        C_PaperDollInfo = {
            GetInspectItemLevel = function()
                return REMOTE_EQUIPPED_ITEM_LEVEL
            end,
        },
        C_SpecializationInfo = {
            GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return SPEC_ID end,
        },
        C_ClassTalents = {
            GetActiveConfigID = function() return nil end,
        },
        C_AddOns = {
            GetAddOnMetadata = function() return LOCAL_VERSION_STRING end,
        },
        C_Timer = {
            After = function(_, fn)
                table.insert(sim.scheduledCallbacks, fn)
            end,
            NewTicker = function(interval, fn)
                if interval == 1 then
                    tickerFns.inspect = fn
                elseif interval == 60 then
                    tickerFns.sweep = fn
                end
                return { Cancel = function() end }
            end,
        },
    }
end

local function resetModuleState()
    sim.units = {}
    GroupInspect:ScanRoster()
    flushTimers()
    if tickerFns.inspect then
        tickerFns.inspect()
    end
end

-- test_autoinvite.lua leaks its own PRT:IterateGroup monkeypatch at file scope
-- and sorts ahead of this file, so the sim installs its iterator per test and
-- puts back whatever it found.
local function runSim(body)
    sim = newSim()

    local savedIterate = PRT.IterateGroup
    PRT.IterateGroup = function()
        local i = 0
        return function()
            i = i + 1
            return sim.units[i]
        end
    end

    Comms.sendFunc = function(encoded, channel, target)
        local ok, payload = Comms:Decode(encoded)
        assertTrue(ok, "everything GroupInspect sends must decode")
        table.insert(sim.sentMessages, {
            type = payload.type,
            data = payload.data,
            channel = channel,
            target = target,
        })
    end

    local overrides = makeStubs()
    local savedGlobals = {}
    for k, v in pairs(overrides) do
        savedGlobals[k] = _G[k]
        _G[k] = v
    end

    local ok, err = pcall(body)
    local cleanupOk, cleanupErr = pcall(resetModuleState)

    for k in pairs(overrides) do
        _G[k] = savedGlobals[k]
    end
    PRT.IterateGroup = savedIterate
    Comms.sendFunc = nil

    if not ok then
        error(err, 0)
    end
    if not cleanupOk then
        error(cleanupErr, 0)
    end
end

local function encode(msgType, data)
    return Comms:Encode({ type = msgType, data = data })
end

local function addMemberWhileNameUnresolved()
    sim.unitsAwaitingNameData["raid2"] = true
    sim.localRealm = nil
    assertEquals(UnitName("raid2"), UNKNOWNOBJECT,
        "the fixture must actually present this member's name as unresolved")
    assertNil(GetNormalizedRealmName(),
        "the fixture must actually present the local realm as unresolved")

    sim.units = { "raid1", "raid2" }
    GroupInspect:ScanRoster()
end

local function resolveNameData()
    sim.unitsAwaitingNameData["raid2"] = nil
    sim.localRealm = LOCAL_REALM
end

tests["EncodeVersion: 1.0.0 encodes to 1000000"] = function()
    assertEquals(GroupInspect.EncodeVersion("1.0.0"), 1000000)
end

tests["EncodeVersion: 1.1.3 encodes to 1001003"] = function()
    assertEquals(GroupInspect.EncodeVersion("1.1.3"), 1001003)
end

tests["EncodeVersion: 2.15.7 encodes to 2015007"] = function()
    assertEquals(GroupInspect.EncodeVersion("2.15.7"), 2015007)
end

tests["EncodeVersion: prerelease suffix is stripped before encoding"] = function()
    assertEquals(GroupInspect.EncodeVersion("1.0.0-beta-2"), 1000000)
    assertEquals(GroupInspect.EncodeVersion("2.15.7-alpha"), 2015007)
end

tests["EncodeVersion: unparseable version strings encode to 0"] = function()
    assertEquals(GroupInspect.EncodeVersion(""), 0, "empty string")
    assertEquals(GroupInspect.EncodeVersion(nil), 0, "nil")
    assertEquals(GroupInspect.EncodeVersion("abc"), 0, "non-numeric")
    assertEquals(GroupInspect.EncodeVersion("1.0"), 0, "missing component")
    assertEquals(GroupInspect.EncodeVersion("1.0.5.2"), 0, "extra component")
    assertEquals(GroupInspect.EncodeVersion(123), 0, "non-string")
end

tests["EncodeVersion: encoded versions sort in version order"] = function()
    assertTrue(GroupInspect.EncodeVersion("1.0.1") > GroupInspect.EncodeVersion("1.0.0"),
        "patch bump must encode strictly greater")
    assertTrue(GroupInspect.EncodeVersion("1.1.0") > GroupInspect.EncodeVersion("1.0.9"),
        "minor bump must outrank a higher patch")
    assertTrue(GroupInspect.EncodeVersion("2.0.0") > GroupInspect.EncodeVersion("1.9.9"),
        "major bump must outrank higher minor and patch")
end

tests["a roster scan stores every member's name as a full Name-Realm"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2", "raid3" }
        GroupInspect:ScanRoster()

        assertEquals(GroupInspect.members["GUID-NIV"].name, "Niv-Illidan",
            "the local player's name arrives bare and must gain the local realm")
        assertEquals(GroupInspect.members["GUID-BOB"].name, "Bob-Illidan",
            "a same-realm member's name arrives bare and must gain the local realm")
        assertEquals(GroupInspect.members["GUID-ZED"].name, "Zed-Area52",
            "a cross-realm member must keep their own realm, not be given the local one")
    end)
end

tests["an offline member is stored and retained exactly like an online one"] = function()
    runSim(function()
        sim.units = { "raid1", "raid4" }
        assertFalse(UnitIsConnected("raid4"),
            "the fixture must actually present this member as disconnected")

        GroupInspect:ScanRoster()

        local record = GroupInspect.members["GUID-MAE"]
        assertNotNil(record, "a disconnected member must still get a member record")
        assertEquals(record.name, "Mae-Illidan",
            "a disconnected member's name must be stored as a full Name-Realm")
        assertEquals(record.class, "WARRIOR",
            "a disconnected member must get the same record fields as a connected one")

        GroupInspect:ScanRoster()
        assertNotNil(GroupInspect.members["GUID-MAE"],
            "a rescan must not prune a member who is offline but still in the group")
        assertEquals(GroupInspect.members["GUID-MAE"].name, "Mae-Illidan",
            "a rescan must not degrade a retained member's stored name")
    end)
end

tests["a same-realm member whose realm resolves to an empty string still gets the local realm"] = function()
    runSim(function()
        sim.units = { "raid1", "raid5" }
        local _, realm = UnitName("raid5")
        assertEquals(realm, "", "the fixture must actually return an empty realm for this member")

        GroupInspect:ScanRoster()

        assertEquals(GroupInspect.members["GUID-TEK"].name, "Tek-Illidan",
            "an empty realm means same realm, not a realm named ''")
    end)
end

tests["a name unresolved at add time is repaired by the retry timer, with no further scan"] = function()
    runSim(function()
        addMemberWhileNameUnresolved()
        resolveNameData()

        flushTimers()

        assertEquals(GroupInspect.members["GUID-BOB"].name, "Bob-Illidan",
            "the retry scheduled at add time must re-resolve the name; no further roster event may come")
    end)
end

tests["a name unresolved at add time is repaired by a later scan, with no retry timer"] = function()
    runSim(function()
        addMemberWhileNameUnresolved()
        resolveNameData()

        GroupInspect:ScanRoster()

        assertEquals(GroupInspect.members["GUID-BOB"].name, "Bob-Illidan",
            "a later scan must repair the name as a backstop, even if no retry timer fires")
    end)
end

tests["an unresolved name is still stored as a non-nil string"] = function()
    runSim(function()
        addMemberWhileNameUnresolved()

        local unresolved = GroupInspect.members["GUID-BOB"]
        assertNotNil(unresolved, "a member whose name has not loaded yet must still be tracked")
        assertEquals(type(unresolved.name), "string",
            "a nil name silently drops the player from every consumer that table.inserts it")
        assertTrue(#unresolved.name > 0, "an empty name drops them from display just as quietly")

        local localPlayer = GroupInspect.members["GUID-NIV"]
        assertEquals(type(localPlayer.name), "string",
            "an unresolvable local realm must not nil out the local player's own name")
        assertTrue(#localPlayer.name > 0, "the local player must not be left with an empty name")
    end)
end

tests["a unit whose GUID has not resolved is skipped and picked up by a later scan"] = function()
    runSim(function()
        sim.unitsAwaitingGuid["raid2"] = true
        sim.units = { "raid1", "raid2" }
        assertNil(UnitGUID("raid2"), "the fixture must actually present this unit without a GUID")

        GroupInspect:ScanRoster()
        assertNil(GroupInspect.members["GUID-BOB"],
            "a unit with no GUID cannot be keyed into the members table")

        sim.unitsAwaitingGuid["raid2"] = nil
        GroupInspect:ScanRoster()

        assertEquals(GroupInspect.members["GUID-BOB"].name, "Bob-Illidan",
            "the member must be added with a full name once their GUID resolves")
    end)
end

tests["roster scan writes and broadcasts the local player's version"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()

        local record = GroupInspect.members["GUID-NIV"]
        assertNotNil(record, "the local player must have a member record")
        assertEquals(record.addonVersion, LOCAL_ENCODED_VERSION,
            "the local encoded version must be written during roster scan")
        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1, "a changed roster must advertise the local version once")
        assertEquals(responses[1].channel, "RAID")
        assertNil(responses[1].target)
        assertEquals(responses[1].data.version, LOCAL_ENCODED_VERSION)
    end)
end

tests["a roster scan stores the local player's equipped item level"] = function()
    runSim(function()
        sim.units = { "raid1" }
        GroupInspect:ScanRoster()

        assertEquals(GroupInspect.members["GUID-NIV"].itemLevel, LOCAL_EQUIPPED_ITEM_LEVEL,
            "the bags-inclusive first result must not be recorded")
    end)
end

tests["a version response stores the sender's encoded version on their member record"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        assertEquals(#sentOfType("versionResponse"), 1,
            "the roster scan must advertise the local version")

        Comms:Dispatch(encode("versionResponse", { version = 1001003 }), "Bob-Illidan")

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the responding member must have a record")
        assertEquals(record.addonVersion, 1001003)
    end)
end

tests["no remote version advertisement leaves the member's version nil"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        assertEquals(#sentOfType("versionResponse"), 1,
            "the local advertisement must not populate a remote member")
        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the queried member must have a record")
        assertNil(record.addonVersion,
            "a member who never responds must keep a nil version")
    end)
end

tests["a newer version response overwrites the stored version"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the responding member must have a record")

        Comms:Dispatch(encode("versionResponse", { version = 1000000 }), "Bob-Illidan")
        assertEquals(record.addonVersion, 1000000)

        Comms:Dispatch(encode("versionResponse", { version = 1001003 }), "Bob-Illidan")
        assertEquals(record.addonVersion, 1001003,
            "a later response must overwrite the stored version")
    end)
end

tests["a re-inspect with no response keeps the stored version"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        assertEquals(#sentOfType("versionResponse"), 1)

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the queried member must have a record")

        Comms:Dispatch(encode("versionResponse", { version = 1001003 }), "Bob-Illidan")
        -- BeginInspect's 2s timeout still holds inspectPending; run it out or the
        -- sweep inspect below is silently skipped.
        flushTimers()

        driveSweepTick()
        driveInspectTick()
        assertEquals(#sentOfType("versionResponse"), 1,
            "the inspect sweep must not add periodic version traffic")

        assertEquals(record.addonVersion, 1001003,
            "a missing response on re-inspect must not clear the stored version")
    end)
end

tests["a version response from outside the group is ignored"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        local memberCountBefore = countMembers()

        local outsiderSharingBobsShortName = "Bob-Stormrage"
        Comms:Dispatch(encode("versionResponse", { version = 2015007 }),
            outsiderSharingBobsShortName)

        assertNil(GroupInspect.members["GUID-BOB"].addonVersion,
            "a response from a non-member must not land on a same-named member")
        assertEquals(countMembers(), memberCountBefore,
            "an unknown sender must not create a member record")
    end)
end

tests["a malformed version response is ignored"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()

        Comms:Dispatch(encode("versionResponse", { version = "abc" }), "Bob-Illidan")
        Comms:Dispatch(encode("versionResponse", "not a table"), "Bob-Illidan")

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the sending member must have a record")
        assertNil(record.addonVersion, "a malformed payload must not be stored")
    end)
end

-- Pre-existing ScanRoster behavior, retested here as the harness canary: if this
-- fails, the sim plumbing is broken and every other failure in the file is suspect.
tests["a departed player's member record is removed by the next roster scan"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        assertNotNil(GroupInspect.members["GUID-BOB"])

        sim.units = { "raid1" }
        GroupInspect:ScanRoster()
        assertNil(GroupInspect.members["GUID-BOB"],
            "leaving the group must remove the entire member record")
    end)
end

tests["a priority-queue inspect does not add per-player version traffic"] = function()
    runSim(function()
        sim.units = { "raid1", "raid3" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        assertEquals(#sim.inspectedUnits, 1, "the new member must be inspected")
        assertEquals(sim.inspectedUnits[1], "raid3")

        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1,
            "the roster advertisement must be the only version traffic")
        assertEquals(responses[1].channel, "RAID")
        assertNil(responses[1].target)
    end)
end

tests["initial group entry queries every PRT client over the group channel"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        onEventHandler(nil, "PLAYER_ENTERING_WORLD")

        local queries = sentOfType("versionQuery")
        assertEquals(#queries, 1, "initial group entry must request the existing versions once")
        assertEquals(queries[1].channel, "RAID")
        assertNil(queries[1].target)
        assertEquals(queries[1].data.version, LOCAL_ENCODED_VERSION,
            "the query must advertise the sender so receivers learn it without another message")

        sim.sentMessages = {}
        onEventHandler(nil, "PLAYER_ENTERING_WORLD")
        assertEquals(#sentOfType("versionQuery"), 0,
            "zoning with an already populated roster must not repeat initial discovery")
    end)
end

tests["simultaneous version queries are coalesced into one response"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2", "raid3" }
        GroupInspect:ScanRoster()
        sim.sentMessages = {}

        Comms:Dispatch(encode("versionQuery", { version = 1001003 }), "Bob-Illidan")
        Comms:Dispatch(encode("versionQuery", { version = 2015007 }), "Zed-Area52")

        assertEquals(GroupInspect.members["GUID-BOB"].addonVersion, 1001003,
            "the query must identify its sender immediately")
        assertEquals(GroupInspect.members["GUID-ZED"].addonVersion, 2015007,
            "coalescing replies must not discard another query sender's version")
        assertEquals(#sentOfType("versionResponse"), 0,
            "the coalesced response must wait for its jitter timer")

        flushTimers()

        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1, "a query burst must schedule one local response")
        assertEquals(responses[1].channel, "RAID")
        assertNil(responses[1].target)
        assertEquals(responses[1].data.version, LOCAL_ENCODED_VERSION)
    end)
end

tests["background inspection never sends player-targeted addon whispers"] = function()
    runSim(function()
        sim.units = { "raid1", "raid3" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        for _, message in ipairs(sim.sentMessages) do
            assertFalse(message.channel == "WHISPER",
                "inspection comms must use a group channel so an unroutable player name cannot spam chat")
            assertNil(message.target,
                "group-channel inspection comms must not carry a player-name target")
        end
    end)
end

tests["an NPC-only home group sends no version advertisement"] = function()
    runSim(function()
        sim.groupChannel = "PARTY"
        sim.units = { "raid1", "raid6" }
        GroupInspect:ScanRoster()

        assertEquals(#sentOfType("versionResponse"), 0,
            "a follower group with no other player must not send to PARTY")
    end)
end

tests["follower NPCs are excluded from player inspection data and queues"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2", "raid6" }
        GroupInspect:ScanRoster()

        assertEquals(countMembers(), 2, "only player characters belong in GroupInspect")
        assertNil(GroupInspect.members["CREATURE-FOLLOWER"],
            "an NPC party member must not receive a player record")

        driveInspectTick()
        flushTimers()
        driveSweepTick()
        driveInspectTick()

        assertEquals(#sim.inspectedUnits, 2,
            "the real player must remain inspectable through priority and sweep queues")
        assertEquals(sim.inspectedUnits[1], "raid2")
        assertEquals(sim.inspectedUnits[2], "raid2")
        assertEquals(#sim.inspectChecks, 2,
            "the NPC must never reach Blizzard's inspectability predicate")
        assertEquals(sim.inspectChecks[1].unit, "raid2")
        assertEquals(sim.inspectChecks[2].unit, "raid2")
        assertEquals(#sentOfType("versionResponse"), 1,
            "only the roster change may broadcast a version advertisement")
    end)
end

tests["an offline priority target is skipped before the next available member"] = function()
    runSim(function()
        sim.units = { "raid1", "raid4", "raid3" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        assertEquals(#sim.inspectedUnits, 1,
            "an offline member must not consume the inspect attempt")
        assertEquals(sim.inspectedUnits[1], "raid3",
            "the same tick must continue to the next available member")
        assertEquals(#sim.inspectChecks, 2,
            "both priority targets must be checked before inspection")
        assertEquals(sim.inspectChecks[1].unit, "raid4")
        assertFalse(sim.inspectChecks[1].showError,
            "background availability checks must not show Blizzard errors")
        assertEquals(sim.inspectChecks[2].unit, "raid3")
    end)
end

tests["a sweep adds no version traffic"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        GroupInspect.members["GUID-BOB"].specId = SPEC_ID
        GroupInspect.members["GUID-BOB"].itemLevel = REMOTE_EQUIPPED_ITEM_LEVEL

        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 0,
            "the priority queue must skip a member whose spec is already known")
        assertEquals(#sentOfType("versionResponse"), 1,
            "the roster scan must advertise once before the sweep")

        driveSweepTick()
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 1, "the sweep must re-inspect the member")
        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1,
            "the 60-second inspect sweep must not act as a version heartbeat")
    end)
end

tests["the sweep skips a member Blizzard reports cannot be inspected"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        sim.uninspectableUnits["raid2"] = true
        GroupInspect:ScanRoster()

        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 0,
            "the priority drain must skip the unavailable member")

        sim.inspectChecks = {}
        driveSweepTick()
        driveInspectTick()

        assertEquals(#sim.inspectedUnits, 0,
            "the sweep must not call NotifyInspect for an unavailable member")
        assertEquals(#sentOfType("versionResponse"), 1,
            "the inspect sweep must send no version traffic even when a target is unavailable")
        assertEquals(#sim.inspectChecks, 1,
            "the sweep target must be checked exactly once")
        assertEquals(sim.inspectChecks[1].unit, "raid2")
        assertFalse(sim.inspectChecks[1].showError,
            "background availability checks must not show Blizzard errors")
    end)
end

tests["a party roster advertises the local version over PARTY"] = function()
    runSim(function()
        sim.groupChannel = "PARTY"
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()

        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1)
        assertEquals(responses[1].channel, "PARTY")
        assertNil(responses[1].target)
        assertEquals(responses[1].data.version, LOCAL_ENCODED_VERSION)
    end)
end

tests["an instance-group roster advertises the local version over INSTANCE_CHAT"] = function()
    runSim(function()
        sim.groupChannel = "INSTANCE_CHAT"
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()

        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1)
        assertEquals(responses[1].channel, "INSTANCE_CHAT")
        assertNil(responses[1].target)
        assertEquals(responses[1].data.version, LOCAL_ENCODED_VERSION)
    end)
end

tests["a member logging in is priority-queued and inspected on the next tick"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 1, "the join inspect fires first")
        flushTimers() -- expire the pending-inspect timeout; no INSPECT_READY ever arrived

        GroupInspect:OnUnitConnected("raid2")
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 2,
            "a login must re-inspect a member whose spec never resolved, not wait for the sweep")
        assertEquals(sim.inspectedUnits[2], "raid2")
    end)
end

tests["duplicate login events queue a member once"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        flushTimers()

        GroupInspect:OnUnitConnected("raid2")
        GroupInspect:OnUnitConnected("raid2")
        driveInspectTick()
        flushTimers()
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 2,
            "the second connection event must not queue a second inspect")
    end)
end

tests["a login with cached inspection data does not trigger an inspect"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        GroupInspect.members["GUID-BOB"].specId = SPEC_ID
        GroupInspect.members["GUID-BOB"].itemLevel = REMOTE_EQUIPPED_ITEM_LEVEL

        GroupInspect:OnUnitConnected("raid2")
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 0,
            "the drain gate must skip a reconnect that kept its inspection data")
    end)
end

tests["logins for the local player or a non-member are ignored"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        flushTimers()

        GroupInspect:OnUnitConnected("raid1") -- local player: read directly, never inspected
        GroupInspect:OnUnitConnected("raid3") -- exists as a unit, but not in this group
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 1,
            "neither the local player nor a stranger may be queued by a login")
    end)
end

tests["INSPECT_READY updates the member specId"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        local record = GroupInspect.members["GUID-BOB"]
        assertNil(record.specId, "specId must be nil before inspect resolves")

        -- Fire INSPECT_READY with the GUID of the unit we inspected.
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")

        assertEquals(record.specId, SPEC_ID,
            "INSPECT_READY must populate the member specId")
    end)
end

tests["INSPECT_READY stores the inspected member's equipped item level"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        local record = GroupInspect.members["GUID-BOB"]
        assertNil(record.itemLevel)

        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")

        assertEquals(record.itemLevel, REMOTE_EQUIPPED_ITEM_LEVEL)
    end)
end

tests["equipment is captured only for a matched inspection and before release"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        sim.equipment = { raid2 = { [1] = "item:100:5:0:0:0:0:" } }
        GroupInspect:ScanRoster()
        driveInspectTick()
        local record = GroupInspect.members["GUID-BOB"]
        onEventHandler(nil, "INSPECT_READY", "GUID-ZED")
        assertNil(record.equipment)
        local savedClear = ClearInspectPlayer
        ClearInspectPlayer = function()
            assertEquals(record.equipment[1], "item:100:5:0:0:0:0:")
            sim.equipment = nil
        end
        local ok, err = pcall(onEventHandler, nil, "INSPECT_READY", "GUID-BOB")
        ClearInspectPlayer = savedClear
        assertTrue(ok, err)
        assertEquals(record.equipment[1], "item:100:5:0:0:0:0:")
    end)
end

tests["requesting equipment refresh preserves cached results and reinspects complete members"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        local record = GroupInspect.members["GUID-BOB"]
        local cached = record.gearAudit
        GroupInspect:RequestEquipmentRefresh()
        assertEquals(record.gearAudit, cached)
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 2)
        assertEquals(sim.inspectedUnits[2], "raid2")
    end)
end

tests["item retries use captured links and stop after three requests"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        sim.equipment = { raid2 = { [1] = "item:100:0:0:0:0:0:" } }
        sim.itemCached = false
        GroupInspect:ScanRoster()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        sim.onReadEquipment = function(unit)
            if unit == "raid2" then error("must not reread released inspection data") end
        end
        flushTimers()
        assertEquals(sim.itemRequests, 3)
        assertEquals(GroupInspect.members["GUID-BOB"].gearAudit.enchants.status, "unknown")
    end)
end

tests["loaded item data updates the captured audit on retry"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        sim.equipment = { raid2 = { [1] = "item:100:0:0:0:0:0:" } }
        sim.itemCached = false
        GroupInspect:ScanRoster()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        sim.itemCached = true
        flushTimers()
        local result = GroupInspect.members["GUID-BOB"].gearAudit.enchants
        assertEquals(result.missing[1].slot, 1)
        assertEquals(sim.itemRequests, 1)
    end)
end

tests["reopening Gear retries an unavailable member without dropping its refresh request"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        sim.uninspectableUnits.raid2 = true
        GroupInspect:RequestEquipmentRefresh()
        driveInspectTick()
        sim.uninspectableUnits.raid2 = nil
        GroupInspect:RequestEquipmentRefresh()
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 2)
    end)
end

tests["an older item retry cannot overwrite a newer equipment snapshot"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        sim.equipment = { raid2 = { [1] = "item:100:0:0:0:0:0:" } }
        sim.itemCached = false
        GroupInspect:ScanRoster()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        sim.equipment.raid2[1] = "item:100:123:0:0:0:0:"
        sim.itemCached = true
        GroupInspect:RequestEquipmentRefresh()
        driveInspectTick()
        onEventHandler(nil, "INSPECT_READY", "GUID-BOB")
        local record = GroupInspect.members["GUID-BOB"]
        local audit = record.gearAudit
        flushTimers()
        assertEquals(record.gearAudit, audit)
        assertEquals(#audit.enchants.missing, 0)
    end)
end

tests["roster token reassignment cannot attribute an inspection to another member"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2", "raid3" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        local savedGUID = UnitGUID
        UnitGUID = function(unit)
            if unit == "raid2" then return "GUID-ZED" end
            return savedGUID(unit)
        end
        onEventHandler(nil, "INSPECT_READY", "GUID-ZED")
        UnitGUID = savedGUID
        assertNil(GroupInspect.members["GUID-ZED"].equipment)
        assertNil(GroupInspect.members["GUID-BOB"].equipment)
    end)
end

return tests
