-- tests/test_comms.lua
-- Exercises the shared communication layer (spec 10): encode/decode pipeline,
-- payload versioning, handler dispatch, injectable transport, and the
-- privileged-sender check.
--
-- The module under test lives at PurplexityRaidTools.Comms and is built on
-- LibSerialize + LibDeflate (for the encode/decode pipeline) and AceComm (for
-- in-game transport only). AceComm and ChatThrottleLib call CreateFrame at load
-- and cannot run headless, so this suite loads ONLY the three pure libraries and
-- relies on the implementer gating the AceComm embed behind a silent LibStub
-- lookup so Comms.lua loads without it.

local tests = {}

--------------------------------------------------------------------------------
-- Prerequisite globals.
--
-- LibStub/LibSerialize/LibDeflate reference the WoW string alias strmatch. It is
-- a stable alias for string.match and is NOT provided by wow_stubs.lua. Define
-- it as a test-local global here (never edited into wow_stubs.lua) so the pure
-- libs load. This mirrors the sanctioned "set a global before the code under
-- test runs" pattern used elsewhere in the harness.
--------------------------------------------------------------------------------

if strmatch == nil then
    strmatch = string.match
end

--------------------------------------------------------------------------------
-- Load the pure libraries (order matters), then the module under test.
--
-- These three load fine under LuaJIT headless. AceComm/ChatThrottleLib are NOT
-- loaded; Comms.lua must tolerate their absence.
--------------------------------------------------------------------------------

dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibSerialize/LibSerialize.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")

dofile("Comms.lua")

local PRT = PurplexityRaidTools
local Comms = PRT.Comms

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Build a raw ~10KB note string that contains UTF-8 multibyte sequences and the
-- pipe character "|", which WoW uses for color/texture escapes and which the
-- NSRT-format note syntax uses as a field delimiter. The encode pipeline must
-- survive both.
local function makeLargeNote()
    local parts = {}
    -- "héllo|wörld" is 13 bytes: h, é(2), l, l, o, |, w, ö(2), r, l, d.
    local unit = "héllo|wörld {rt1} |cffff0000red|r\n"
    -- Repeat until comfortably over 10 KB.
    for _ = 1, 400 do
        parts[#parts + 1] = unit
    end
    local s = table.concat(parts)
    assertTrue(#s >= 10 * 1024, "large note fixture should exceed 10KB")
    return s
end

-- Snapshot and restore an arbitrary set of globals around a test body so that
-- overriding WoW APIs never leaks between tests (or into wow_stubs.lua).
local function withGlobals(overrides, body)
    local saved = {}
    for k, v in pairs(overrides) do
        saved[k] = _G[k]
        _G[k] = v
    end
    local ok, err = pcall(body)
    for k in pairs(overrides) do
        _G[k] = saved[k]
    end
    if not ok then
        error(err, 0)
    end
end

--------------------------------------------------------------------------------
-- Load safety (AceComm absent)
--------------------------------------------------------------------------------

-- Comms.lua must have loaded above without AceComm-3.0 registered. Prove that
-- LibStub genuinely has no AceComm instance in this environment, so the fact
-- that dofile("Comms.lua") did not throw is meaningful.
tests["Comms loads headless without an AceComm-3.0 instance"] = function()
    assertNil(LibStub("AceComm-3.0", true),
        "test environment must not provide AceComm-3.0")
    assertNotNil(Comms, "PurplexityRaidTools.Comms must exist after load")
    assertNotNil(Comms.Encode)
    assertNotNil(Comms.Decode)
end

--------------------------------------------------------------------------------
-- Encode / Decode round-trip
--------------------------------------------------------------------------------

tests["encode then decode round-trips a table (deep equal)"] = function()
    local payload = {
        type = "note",
        data = { name = "Ulgrax", text = "line one|line two" },
        n = 42,
        flag = true,
    }
    local encoded = Comms:Encode(payload)
    assertEquals(type(encoded), "string", "Encode must return a string")

    local ok, decoded = Comms:Decode(encoded)
    assertTrue(ok, "Decode of a freshly encoded payload must succeed")
    assertTableEquals(decoded, payload)
end

tests["encode produces a WoW-addon-channel-safe string (no embedded NUL)"] = function()
    local encoded = Comms:Encode({ type = "note", data = "abc" })
    assertNil(encoded:find("%z"), "encoded output must not contain NUL bytes")
end

tests["round-trips a large UTF-8 note containing pipe characters"] = function()
    local big = makeLargeNote()
    local encoded = Comms:Encode({ type = "note", data = { text = big } })
    assertEquals(type(encoded), "string")

    local ok, decoded = Comms:Decode(encoded)
    assertTrue(ok, "Decode of the large-note payload must succeed")
    assertEquals(decoded.data.text, big, "large note text must survive the round-trip byte-for-byte")
end

--------------------------------------------------------------------------------
-- Versioning
--------------------------------------------------------------------------------

tests["encoded payload carries version field v = 1"] = function()
    local encoded = Comms:Encode({ type = "note", data = "x" })
    local ok, decoded = Comms:Decode(encoded)
    assertTrue(ok)
    assertEquals(decoded.v, 1, "Encode must stamp a version field v = 1 onto the payload")
end

tests["decode of a payload with the wrong version is rejected"] = function()
    -- Build a payload whose version is not 1, using the same pipeline the
    -- implementer's Encode uses, so this exercises Decode's version gate rather
    -- than a hand-rolled byte stream.
    local LibSerialize = LibStub("LibSerialize")
    local LibDeflate = LibStub("LibDeflate")
    local raw = LibSerialize:Serialize({ v = 999, type = "note", data = "x" })
    local wrongVersion = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(raw))

    local ok, decoded = Comms:Decode(wrongVersion)
    assertFalse(ok, "Decode must reject a payload whose version is not 1")
    -- No throw is implied by reaching this line.
end

--------------------------------------------------------------------------------
-- Malformed input (Decode must never throw)
--------------------------------------------------------------------------------

tests["decode of corrupted input returns ok=false without throwing"] = function()
    local good = Comms:Encode({ type = "note", data = "hello" })
    -- Keep the string length but scramble the tail so decoding/decompression
    -- fails downstream.
    local corrupted = good:sub(1, #good - 4) .. "ZZZZ"
    local ok, decoded = Comms:Decode(corrupted)
    assertFalse(ok)
    assertNil(decoded, "corrupted decode must not return a payload")
end

tests["decode of truncated input returns ok=false without throwing"] = function()
    local good = Comms:Encode({ type = "note", data = "hello world payload" })
    local truncated = good:sub(1, math.max(1, math.floor(#good / 2)))
    local ok = Comms:Decode(truncated)
    assertFalse(ok)
end

tests["decode of empty string returns ok=false without throwing"] = function()
    local ok = Comms:Decode("")
    assertFalse(ok)
end

tests["decode of a non-string returns ok=false without throwing"] = function()
    -- Each of these must be handled without error and yield ok=false.
    for _, bad in ipairs({ { 12345 }, { true }, { {} } }) do
        local value = bad[1]
        local ok = Comms:Decode(value)
        assertFalse(ok, "Decode of a non-string argument must return ok=false")
    end
    -- nil handled separately (cannot live in the array above).
    local okNil = Comms:Decode(nil)
    assertFalse(okNil, "Decode of nil must return ok=false")
end

--------------------------------------------------------------------------------
-- Handler registration and dispatch
--------------------------------------------------------------------------------

-- Decode+dispatch: the implementer decodes an incoming string, then routes the
-- payload to the handler registered for payload.type, calling it with
-- (data, sender). We drive dispatch by feeding an encoded string through the
-- same public Decode used above plus a Dispatch entry point.

tests["registered handler is called with (data, sender) on matching type"] = function()
    local seen = {}
    Comms:RegisterHandler("noteBroadcast", function(data, sender)
        seen.data = data
        seen.sender = sender
        seen.count = (seen.count or 0) + 1
    end)

    local encoded = Comms:Encode({
        type = "noteBroadcast",
        data = { name = "Sikran", text = "swap|now" },
    })
    Comms:Dispatch(encoded, "Niv-Illidan")

    assertEquals(seen.count, 1, "handler must be invoked exactly once")
    assertEquals(seen.sender, "Niv-Illidan")
    assertNotNil(seen.data)
    assertEquals(seen.data.name, "Sikran")
    assertEquals(seen.data.text, "swap|now")
end

tests["dispatch of an unregistered type is ignored (no crash, no call)"] = function()
    local called = false
    Comms:RegisterHandler("registeredType", function()
        called = true
    end)

    local encoded = Comms:Encode({ type = "someOtherType", data = "x" })
    -- Must not throw and must not invoke the wrong handler.
    Comms:Dispatch(encoded, "Niv-Illidan")
    assertFalse(called, "a handler must not fire for a non-matching type")
end

tests["dispatch of a wrong-version payload does not call any handler"] = function()
    local called = false
    Comms:RegisterHandler("versionedType", function()
        called = true
    end)

    local LibSerialize = LibStub("LibSerialize")
    local LibDeflate = LibStub("LibDeflate")
    local raw = LibSerialize:Serialize({ v = 2, type = "versionedType", data = "x" })
    local wrongVersion = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(raw))

    Comms:Dispatch(wrongVersion, "Niv-Illidan")
    assertFalse(called, "a wrong-version payload must not reach any handler")
end

tests["dispatch of corrupted input does not throw or call a handler"] = function()
    local called = false
    Comms:RegisterHandler("safeType", function()
        called = true
    end)
    Comms:Dispatch("!!!not a real payload!!!", "Niv-Illidan")
    assertFalse(called)
end

--------------------------------------------------------------------------------
-- Send via injected transport
--------------------------------------------------------------------------------

-- Transport must be injectable so it is testable without AceComm. Send encodes
-- {v=1, type=msgType, data=data} and hands the encoded string to the injected
-- transport function. We assert the injected function receives the encoded
-- string, the channel, and that the string decodes back to the original.

tests["Send passes the encoded payload to the injected transport function"] = function()
    local captured = {}
    withGlobals({}, function()
        Comms.sendFunc = function(encoded, channel)
            captured.encoded = encoded
            captured.channel = channel
        end

        Comms:Send("noteBroadcast", { name = "Kyveza", text = "portal|left" }, "RAID")

        assertEquals(type(captured.encoded), "string",
            "Send must call sendFunc with the encoded string")
        assertEquals(captured.channel, "RAID",
            "Send must forward the channel to sendFunc")

        local ok, decoded = Comms:Decode(captured.encoded)
        assertTrue(ok, "the string handed to sendFunc must be decodable")
        assertEquals(decoded.v, 1)
        assertEquals(decoded.type, "noteBroadcast")
        assertEquals(decoded.data.name, "Kyveza")
        assertEquals(decoded.data.text, "portal|left")
    end)
    Comms.sendFunc = nil
end

tests["Send round-trips through inject transport into a registered handler"] = function()
    local received = {}
    Comms:RegisterHandler("endToEnd", function(data, sender)
        received.data = data
        received.sender = sender
    end)

    Comms.sendFunc = function(encoded, channel)
        -- Simulate the wire: whatever Send produced is delivered and dispatched.
        Comms:Dispatch(encoded, "Sender-Realm")
    end

    Comms:Send("endToEnd", { text = "big|note" }, "RAID")
    Comms.sendFunc = nil

    assertNotNil(received.data, "the injected transport path must reach the handler")
    assertEquals(received.data.text, "big|note")
    assertEquals(received.sender, "Sender-Realm")
end

--------------------------------------------------------------------------------
-- IsSenderPrivileged (spec 10.2.1)
--------------------------------------------------------------------------------

-- Privileged = the sender is the raid leader / raid assistant (in a raid) or the
-- party leader (in a party). The check must Ambiguate cross-realm "Name-Realm"
-- senders down to a bare name before comparing, since WoW's group-leader APIs
-- key on the ambiguated unit name. We drive the WoW APIs via test-local global
-- overrides, restored after each test.

tests["IsSenderPrivileged: true for a raid leader given a Name-Realm sender"] = function()
    withGlobals({
        IsInRaid = function() return true end,
        IsInGroup = function() return true end,
        -- The implementation resolves the sender to a unit and asks whether it
        -- is the group leader / assistant. Both APIs receive the AMBIGUATED
        -- (realm-stripped) name; assert that here.
        UnitIsGroupLeader = function(unit)
            assertEquals(unit, "Niv", "sender must be Ambiguated before the leader check")
            return true
        end,
        UnitIsGroupAssistant = function(unit)
            return false
        end,
    }, function()
        assertTrue(Comms:IsSenderPrivileged("Niv-Illidan"),
            "a cross-realm raid leader must be privileged")
    end)
end

tests["IsSenderPrivileged: true for a raid assistant"] = function()
    withGlobals({
        IsInRaid = function() return true end,
        IsInGroup = function() return true end,
        UnitIsGroupLeader = function() return false end,
        UnitIsGroupAssistant = function(unit)
            assertEquals(unit, "Helper")
            return true
        end,
    }, function()
        assertTrue(Comms:IsSenderPrivileged("Helper"),
            "a raid assistant must be privileged")
    end)
end

tests["IsSenderPrivileged: false for a plain raid member"] = function()
    withGlobals({
        IsInRaid = function() return true end,
        IsInGroup = function() return true end,
        UnitIsGroupLeader = function() return false end,
        UnitIsGroupAssistant = function() return false end,
    }, function()
        assertFalse(Comms:IsSenderPrivileged("Randouser-Area52"),
            "a non-leader, non-assistant raid member must not be privileged")
    end)
end

tests["IsSenderPrivileged: true for a party leader (not in raid)"] = function()
    withGlobals({
        IsInRaid = function() return false end,
        IsInGroup = function() return true end,
        UnitIsGroupLeader = function(unit)
            assertEquals(unit, "Partymate")
            return true
        end,
        UnitIsGroupAssistant = function() return false end,
    }, function()
        assertTrue(Comms:IsSenderPrivileged("Partymate-Ravencrest"),
            "the party leader must be privileged")
    end)
end

tests["IsSenderPrivileged: bare Name sender is handled the same as Name-Realm"] = function()
    -- A sender with no realm suffix must Ambiguate to itself and still be
    -- evaluated correctly.
    withGlobals({
        IsInRaid = function() return true end,
        IsInGroup = function() return true end,
        UnitIsGroupLeader = function(unit)
            assertEquals(unit, "Solo", "a realm-less name must pass through Ambiguate unchanged")
            return true
        end,
        UnitIsGroupAssistant = function() return false end,
    }, function()
        assertTrue(Comms:IsSenderPrivileged("Solo"))
    end)
end

return tests
