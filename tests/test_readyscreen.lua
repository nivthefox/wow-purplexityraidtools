local tests = {}

if not PurplexityRaidTools.ReadyScreen then
    dofile("Modules/ReadyScreen.lua")
end

local ReadyScreen = PurplexityRaidTools.ReadyScreen

tests["GetDisplayedState: offline member shows offline regardless of dead or response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(true, false, "ready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, true, "ready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, true, "notready"), "offline")
    assertEquals(ReadyScreen.GetDisplayedState(true, false, "pending"), "offline")
end

tests["GetDisplayedState: dead non-offline member shows dead regardless of response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "ready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "notready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "pending"), "dead")
end

tests["GetDisplayedState: alive connected member shows response state"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "pending"), "pending")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "ready"), "ready")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "notready"), "notready")
end

tests["GetDisplayedState: dead clears to recorded response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, "ready"), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(false, false, "ready"), "ready")
end

tests["FinalizeResponse: pending becomes notready at check completion"] = function()
    assertEquals(ReadyScreen.FinalizeResponse("pending"), "notready")
    assertEquals(ReadyScreen.FinalizeResponse("ready"), "ready")
    assertEquals(ReadyScreen.FinalizeResponse("notready"), "notready")
end

tests["GetDisplayedState after FinalizeResponse: condition overrides finalized response"] = function()
    assertEquals(ReadyScreen.GetDisplayedState(false, true, ReadyScreen.FinalizeResponse("pending")), "dead")
    assertEquals(ReadyScreen.GetDisplayedState(true, false, ReadyScreen.FinalizeResponse("pending")), "offline")
end

tests["SortRoster: produces alphabetical order by name"] = function()
    local roster = {
        { name = "Zed" },
        { name = "Alice" },
        { name = "Moe" },
    }
    local result = ReadyScreen.SortRoster(roster)
    assertNotNil(result, "SortRoster must return the table")
    assertEquals(result, roster, "SortRoster must return the same table reference")
    assertEquals(roster[1].name, "Alice")
    assertEquals(roster[2].name, "Moe")
    assertEquals(roster[3].name, "Zed")
end

tests["ClassifyVersion: member version below RL is outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1000000, 1001003), "outdated")
end

tests["ClassifyVersion: member version equal to RL is current"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1001003, 1001003), "current")
    assertEquals(ReadyScreen.ClassifyVersion(1001004, 1001003), "current",
        "member running a newer version than RL is still current")
end

tests["ClassifyVersion: nil member version is missing not outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(nil, 1001003), "missing")
end

tests["SortRoster: nil names sort last without error"] = function()
    local roster = {
        { name = "Zed" },
        { name = nil },
        { name = "Alice" },
    }
    local result = ReadyScreen.SortRoster(roster)
    assertNotNil(result, "SortRoster must not crash on nil names")
    assertEquals(roster[1].name, "Alice")
    assertEquals(roster[2].name, "Zed")
    assertNil(roster[3].name, "nil-name members must sort last")
end

tests["ClassifyVersion: nil RL version means nobody is outdated"] = function()
    assertEquals(ReadyScreen.ClassifyVersion(1000000, nil), "current")
    assertEquals(ReadyScreen.ClassifyVersion(999, nil), "current")
    assertEquals(ReadyScreen.ClassifyVersion(nil, nil), "missing",
        "nil member with nil RL is still missing, not outdated")
end

return tests
