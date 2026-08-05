-- tests/test_groupinspect.lua
-- Addon version detection in Modules/GroupInspect.lua
-- (docs/spec/2026-08-04-addon-detection.html): EncodeVersion, the versionQuery
-- and versionResponse handshake that rides along with each inspect, and the
-- addonVersion field on member records. The inspect loop runs on file-local
-- C_Timer tickers, so this suite captures the ticker callbacks (1s drains the
-- inspect queues, 60s refills the sweep) and fires them by hand.

local tests = {}

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

GroupInspect.eventFrame = {
    RegisterEvent = function() end,
    UnregisterAllEvents = function() end,
    SetScript = function() end,
}
GroupInspect:Initialize()

-- Deliberately NOT the real .toc version, and encoding to a value no other test
-- expects: a GetLocalVersion() that hardcodes a number instead of reading
-- C_AddOns metadata cannot pass the local-player and responder tests.
local LOCAL_VERSION_STRING = "3.7.2-beta-1"
local LOCAL_ENCODED_VERSION = 3007002
local SPEC_ID = 71

local UNITS = {
    raid1 = { guid = "GUID-NIV", name = "Niv", fullName = "Niv", isPlayer = true },
    raid2 = { guid = "GUID-BOB", name = "Bob", fullName = "Bob" },
    raid3 = { guid = "GUID-ZED", name = "Zed", fullName = "Zed-Area52" },
}

local SENDER_GUIDS = {
    ["Bob-Illidan"] = "GUID-BOB",
    ["Zed-Area52"] = "GUID-ZED",
}

local sim

local function newSim()
    return {
        units = {},
        scheduledCallbacks = {},
        inspectedUnits = {},
        sentMessages = {},
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

local function makeStubs()
    return {
        UnitGUID = function(unitOrSender)
            local unit = UNITS[unitOrSender]
            if unit then
                return unit.guid
            end
            return SENDER_GUIDS[unitOrSender]
        end,
        UnitName = function(unitToken)
            local unit = UNITS[unitToken]
            if not unit then
                return unitToken
            end
            return unit.name
        end,
        UnitClass = function()
            return "Warrior", "WARRIOR"
        end,
        -- Real WoW semantics: without showServerName a cross-realm player's name
        -- comes back bare ("Zed"), which is not a valid whisper target. The stub
        -- must observe the flag, or the cross-realm target assertion passes
        -- against an implementation that is broken in game.
        GetUnitName = function(unitToken, showServerName)
            local unit = UNITS[unitToken]
            if not unit then
                return unitToken
            end
            if showServerName then
                return unit.fullName
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
        UnitExists = function(unitToken)
            for i = 1, #sim.units do
                if sim.units[i] == unitToken then
                    return true
                end
            end
            return false
        end,
        UnitAffectingCombat = function() return false end,
        IsInGroup = function() return #sim.units > 0 end,
        IsInRaid = function() return #sim.units > 0 end,
        NotifyInspect = function(unitToken)
            table.insert(sim.inspectedUnits, unitToken)
        end,
        ClearInspectPlayer = function() end,
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return SPEC_ID end,
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

tests["roster scan writes the local player's version directly and sends no comms"] = function()
    runSim(function()
        sim.units = { "raid1" }
        GroupInspect:ScanRoster()

        local record = GroupInspect.members["GUID-NIV"]
        assertNotNil(record, "the local player must have a member record")
        assertEquals(record.addonVersion, LOCAL_ENCODED_VERSION,
            "the local encoded version must be written during roster scan")
        assertEquals(#sim.sentMessages, 0, "no comms message may be sent for the local player")
    end)
end

tests["a version response stores the sender's encoded version on their member record"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()
        assertEquals(#sentOfType("versionQuery"), 1, "the inspect must have sent a version query")

        Comms:Dispatch(encode("versionResponse", { version = 1001003 }), "Bob-Illidan")

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the responding member must have a record")
        assertEquals(record.addonVersion, 1001003)
    end)
end

tests["no version response leaves the member's version nil"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        assertEquals(#sentOfType("versionQuery"), 1,
            "the query must actually have been sent for silence to mean anything")
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
        assertEquals(#sentOfType("versionQuery"), 1)

        local record = GroupInspect.members["GUID-BOB"]
        assertNotNil(record, "the queried member must have a record")

        Comms:Dispatch(encode("versionResponse", { version = 1001003 }), "Bob-Illidan")
        -- BeginInspect's 2s timeout still holds inspectPending; run it out or the
        -- sweep inspect below is silently skipped.
        flushTimers()

        driveSweepTick()
        driveInspectTick()
        assertEquals(#sentOfType("versionQuery"), 2,
            "the sweep re-inspect must send a second query")

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

tests["a priority-queue inspect sends a version query to the new player"] = function()
    runSim(function()
        sim.units = { "raid1", "raid3" }
        GroupInspect:ScanRoster()
        driveInspectTick()

        assertEquals(#sim.inspectedUnits, 1, "the new member must be inspected")
        assertEquals(sim.inspectedUnits[1], "raid3")

        local queries = sentOfType("versionQuery")
        assertEquals(#queries, 1, "the inspect must send exactly one version query")
        assertEquals(queries[1].channel, "WHISPER")
        assertEquals(queries[1].target, "Zed-Area52",
            "the whisper target must be the fully qualified cross-realm name")
    end)
end

tests["a sweep inspect sends a version query to an already-inspected player"] = function()
    runSim(function()
        sim.units = { "raid1", "raid2" }
        GroupInspect:ScanRoster()
        GroupInspect.members["GUID-BOB"].specId = SPEC_ID

        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 0,
            "the priority queue must skip a member whose spec is already known")
        assertEquals(#sentOfType("versionQuery"), 0,
            "no inspect means no version query; the query must live inside BeginInspect")

        driveSweepTick()
        driveInspectTick()
        assertEquals(#sim.inspectedUnits, 1, "the sweep must re-inspect the member")
        local queries = sentOfType("versionQuery")
        assertEquals(#queries, 1, "the sweep inspect must send a version query")
        assertEquals(queries[1].channel, "WHISPER")
        assertEquals(queries[1].target, "Bob")
    end)
end

tests["a version query is answered with the local encoded version, whispered to the sender"] = function()
    runSim(function()
        Comms:Dispatch(encode("versionQuery", {}), "Rl-Illidan")

        local responses = sentOfType("versionResponse")
        assertEquals(#responses, 1, "a query must be answered unconditionally")
        assertEquals(responses[1].channel, "WHISPER")
        assertEquals(responses[1].target, "Rl-Illidan",
            "the response must go back to the raw sender, realm intact")
        assertEquals(responses[1].data.version, LOCAL_ENCODED_VERSION)
        assertEquals(#sentOfType("versionQuery"), 0,
            "answering a query must not send a query of its own")
    end)
end

return tests
