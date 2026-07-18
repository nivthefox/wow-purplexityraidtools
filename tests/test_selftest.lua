-- tests/test_selftest.lua
-- Exercises every assert helper (both passing and failing cases) and
-- validates fundamental wow_stubs.lua behaviors.

local tests = {}

--------------------------------------------------------------------------------
-- assertEquals
--------------------------------------------------------------------------------

tests["assertEquals: passes on equal values"] = function()
    assertEquals(1, 1)
    assertEquals("hello", "hello")
    assertEquals(true, true)
    assertEquals(nil, nil)
end

tests["assertEquals: fails on unequal values"] = function()
    assertError(function()
        assertEquals(1, 2)
    end)
end

tests["assertEquals: failure message includes actual and expected"] = function()
    local ok, err = pcall(assertEquals, "got", "want")
    assertFalse(ok)
    assertTrue(err:find("got") ~= nil)
    assertTrue(err:find("want") ~= nil)
end

--------------------------------------------------------------------------------
-- assertNear
--------------------------------------------------------------------------------

tests["assertNear: passes when within epsilon"] = function()
    assertNear(1.0001, 1.0, 0.001)
    assertNear(0.9999, 1.0, 0.001)
end

tests["assertNear: fails when outside epsilon"] = function()
    assertError(function()
        assertNear(1.1, 1.0, 0.001)
    end)
end

--------------------------------------------------------------------------------
-- assertTrue
--------------------------------------------------------------------------------

tests["assertTrue: passes on truthy values"] = function()
    assertTrue(true)
    assertTrue(1)
    assertTrue("x")
    assertTrue({})
end

tests["assertTrue: fails on false"] = function()
    assertError(function() assertTrue(false) end)
end

tests["assertTrue: fails on nil"] = function()
    assertError(function() assertTrue(nil) end)
end

--------------------------------------------------------------------------------
-- assertFalse
--------------------------------------------------------------------------------

tests["assertFalse: passes on false"] = function()
    assertFalse(false)
    assertFalse(nil)
end

tests["assertFalse: fails on true"] = function()
    assertError(function() assertFalse(true) end)
end

tests["assertFalse: fails on truthy value"] = function()
    assertError(function() assertFalse(1) end)
end

--------------------------------------------------------------------------------
-- assertNil
--------------------------------------------------------------------------------

tests["assertNil: passes on nil"] = function()
    assertNil(nil)
end

tests["assertNil: fails on non-nil"] = function()
    assertError(function() assertNil(0) end)
    assertError(function() assertNil(false) end)
    assertError(function() assertNil("") end)
end

--------------------------------------------------------------------------------
-- assertNotNil
--------------------------------------------------------------------------------

tests["assertNotNil: passes on non-nil"] = function()
    assertNotNil(0)
    assertNotNil(false)
    assertNotNil("")
    assertNotNil({})
end

tests["assertNotNil: fails on nil"] = function()
    assertError(function() assertNotNil(nil) end)
end

--------------------------------------------------------------------------------
-- assertTableEquals
--------------------------------------------------------------------------------

tests["assertTableEquals: passes on equal tables"] = function()
    assertTableEquals({ 1, 2, 3 }, { 1, 2, 3 })
    assertTableEquals({ a = 1, b = 2 }, { b = 2, a = 1 })
    assertTableEquals({ 1, a = "x", b = { 2, 3 } }, { 1, b = { 2, 3 }, a = "x" })
end

tests["assertTableEquals: fails on different tables"] = function()
    assertError(function()
        assertTableEquals({ 1, 2 }, { 1, 3 })
    end)
    assertError(function()
        assertTableEquals({ a = 1 }, { a = 2 })
    end)
    assertError(function()
        assertTableEquals({ 1, 2, 3 }, { 1, 2 })
    end)
end

tests["assertTableEquals: nested deep equality"] = function()
    assertTableEquals(
        { x = { y = { z = 99 } } },
        { x = { y = { z = 99 } } }
    )
    assertError(function()
        assertTableEquals(
            { x = { y = { z = 99 } } },
            { x = { y = { z = 100 } } }
        )
    end)
end

--------------------------------------------------------------------------------
-- assertError
--------------------------------------------------------------------------------

tests["assertError: passes when error is raised"] = function()
    assertError(function() error("boom") end)
end

tests["assertError: fails when no error is raised"] = function()
    local ok, _ = pcall(assertError, function() end)
    assertFalse(ok)
end

--------------------------------------------------------------------------------
-- strsplit stub
--------------------------------------------------------------------------------

tests["strsplit: splits on delimiter"] = function()
    local a, b, c = strsplit(",", "one,two,three")
    assertEquals(a, "one")
    assertEquals(b, "two")
    assertEquals(c, "three")
end

tests["strsplit: returns single value when no delimiter present"] = function()
    local a = strsplit(",", "hello")
    assertEquals(a, "hello")
end

tests["strsplit: returns empty string for empty input"] = function()
    local a = strsplit(",", "")
    assertEquals(a, "")
end

tests["strsplit: preserves empty fields"] = function()
    local a, b, c = strsplit(",", "a,,b")
    assertEquals(a, "a")
    assertEquals(b, "")
    assertEquals(c, "b")
end

tests["strsplit: preserves trailing empty field"] = function()
    local a, b = strsplit(";", "a;")
    assertEquals(a, "a")
    assertEquals(b, "")
end

tests["strsplit: pieces limit keeps remainder unsplit"] = function()
    local a, b = strsplit(":", "key:value:with:colons", 2)
    assertEquals(a, "key")
    assertEquals(b, "value:with:colons")
end

tests["strsplit: multi-character sep is a delimiter set"] = function()
    local a, b, c = strsplit(" ,", "one two,three")
    assertEquals(a, "one")
    assertEquals(b, "two")
    assertEquals(c, "three")
end

--------------------------------------------------------------------------------
-- CopyTable stub
--------------------------------------------------------------------------------

tests["CopyTable: returns a deep copy"] = function()
    local original = { a = 1, b = { c = 2 } }
    local copy = CopyTable(original)
    assertEquals(copy.a, 1)
    assertEquals(copy.b.c, 2)
    -- Modifying copy must not affect original
    copy.b.c = 99
    assertEquals(original.b.c, 2)
end

tests["CopyTable: handles non-table passthrough"] = function()
    assertEquals(CopyTable(42), 42)
    assertEquals(CopyTable("hi"), "hi")
    assertNil(CopyTable(nil))
end

--------------------------------------------------------------------------------
-- Controllable clock
--------------------------------------------------------------------------------

tests["GetTime: returns WowStubs.clock"] = function()
    local saved = WowStubs.clock
    WowStubs.clock = 0
    assertEquals(GetTime(), 0)
    WowStubs.clock = 12345.5
    assertEquals(GetTime(), 12345.5)
    WowStubs.clock = saved
end

--------------------------------------------------------------------------------
-- Ambiguate stub
--------------------------------------------------------------------------------

tests["Ambiguate: strips realm for mode none"] = function()
    assertEquals(Ambiguate("Thrall-Stormrage", "none"), "Thrall")
end

tests["Ambiguate: strips realm for mode short"] = function()
    assertEquals(Ambiguate("Jaina-Dalaran", "short"), "Jaina")
end

tests["Ambiguate: returns name unchanged for other modes"] = function()
    assertEquals(Ambiguate("Thrall-Stormrage", "full"), "Thrall-Stormrage")
end

tests["Ambiguate: handles name without realm"] = function()
    assertEquals(Ambiguate("Thrall", "none"), "Thrall")
end

--------------------------------------------------------------------------------
-- PRT namespace basics
--------------------------------------------------------------------------------

tests["PRT.Profiles: GetCurrent returns current table"] = function()
    local p = PurplexityRaidTools.Profiles
    assertNotNil(p)
    local current = p:GetCurrent()
    assertNotNil(current)
    assertEquals(type(current), "table")
end

tests["PRT.Profiles: GetCurrentName returns Test"] = function()
    assertEquals(PurplexityRaidTools.Profiles.GetCurrentName(), "Test")
end

tests["PRT: RegisterModule stores module"] = function()
    local dummy = { value = 42 }
    PurplexityRaidTools:RegisterModule("TestDummy", dummy)
    assertEquals(PurplexityRaidTools.modules["TestDummy"], dummy)
end

tests["PRT: GetSetting returns from defaults"] = function()
    PurplexityRaidTools.defaults["myKey"] = "myValue"
    assertEquals(PurplexityRaidTools:GetSetting("myKey"), "myValue")
    PurplexityRaidTools.defaults["myKey"] = nil
end

return tests
