-- tests/test_autoinvite.lua
-- Behavioural tests for the Auto-Invite mass-invite -> raid-conversion flow
-- (Modules/AutoInvite.lua). These pin the fix for the reported bug: `/prt inv`
-- would build a full party and then stop instead of upgrading to a raid.
--
-- The bug: a mass invite fires every invite within a couple of seconds, before
-- anyone accepts. The old convert decision was driven by GetNumGroupMembers()
-- (accepted members), which stayed low during the burst, so every invite went
-- out as a party invite. The first four filled the party; the rest bounced.
--
-- The fix (mirroring MRT's InviteTool): when a mass invite would exceed a party,
-- invite only enough to fill the party, flag for conversion, and flush the rest
-- once GROUP_ROSTER_UPDATE reports the group is a raid.

local tests = {}

--------------------------------------------------------------------------------
-- Load the module under test
--------------------------------------------------------------------------------

if not PurplexityRaidTools.AutoInvite then
    dofile("Modules/AutoInvite.lua")
end

local PRT = PurplexityRaidTools
local AutoInvite = PRT.AutoInvite

--------------------------------------------------------------------------------
-- Simulation state
--------------------------------------------------------------------------------
-- A tiny model of the WoW group/raid lifecycle. Invites are recorded rather
-- than delivered; acceptance and party->raid conversion are driven explicitly
-- by each test so timing is deterministic.

local sim

local function newSim()
    return {
        inRaid = false,
        members = {},        -- names in the group, excluding the player
        invited = {},        -- name -> true, every InviteUnit call
        inviteOrder = {},    -- names in the order they were invited
        convertCalls = 0,    -- number of ConvertToRaid() requests
        scheduled = {},      -- pending C_Timer.After callbacks
    }
end

local function groupCount()
    -- WoW's GetNumGroupMembers() returns 0 when solo, otherwise the total
    -- including the player.
    if #sim.members == 0 then
        return 0
    end
    return #sim.members + 1
end

-- Run every scheduled timer callback, including any queued while flushing.
local function flushTimers()
    local i = 1
    while i <= #sim.scheduled do
        sim.scheduled[i]()
        i = i + 1
    end
    sim.scheduled = {}
end

--------------------------------------------------------------------------------
-- WoW API stubs for this suite
--------------------------------------------------------------------------------

local function buildGuildRoster(count)
    local roster = {}
    for i = 1, count do
        roster[i] = { name = "Guildie" .. i, rankIndex = 1, online = true }
    end
    return roster
end

local function makeStubs(guildRoster)
    return {
        IsInRaid = function() return sim.inRaid end,
        IsInGroup = function() return #sim.members > 0 end,
        GetNumGroupMembers = function() return groupCount() end,

        C_Timer = {
            After = function(_, fn)
                table.insert(sim.scheduled, fn)
            end,
        },

        C_PartyInfo = {
            InviteUnit = function(name)
                sim.invited[name] = true
                table.insert(sim.inviteOrder, name)
            end,
            ConvertToRaid = function()
                sim.convertCalls = sim.convertCalls + 1
                -- Conversion is asynchronous in WoW: the group becomes a raid,
                -- and a subsequent GROUP_ROSTER_UPDATE reports IsInRaid() == true.
                sim.inRaid = true
            end,
        },

        C_GuildInfo = {
            GuildRoster = function() end,
        },

        GetNumGuildMembers = function() return #guildRoster end,
        GetGuildRosterInfo = function(i)
            local entry = guildRoster[i]
            if not entry then return nil end
            -- name, rankName, rankIndex, level, class, zone, note, officernote, online
            return entry.name, "", entry.rankIndex, 70, "Warrior", "", "", "", entry.online
        end,

        -- Auto-promote path (only reached when new raid members appear).
        UnitIsGroupLeader = function() return true end,
        PromoteToAssistant = function() end,
    }
end

-- IsPlayerInGroup() in the module iterates PRT:IterateGroup(); provide an
-- iterator over the simulated members. UnitName() from wow_stubs returns the
-- unit argument verbatim, so yielding names directly is sufficient.
function PRT:IterateGroup()
    local i = 0
    return function()
        i = i + 1
        return sim.members[i]
    end
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

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

-- Reset internal module state (convertPending / pendingInvites are module
-- locals) by driving a clean raid roster update, then start fresh. Must run
-- with the stubs installed.
local function resetModuleState()
    sim.inRaid = true
    AutoInvite:OnGroupRosterUpdate() -- clears convertPending, drains any queue
    flushTimers()
    sim = newSim()
end

-- Configure which guild ranks the mass invite targets.
local function setInviteRanks()
    PRT.defaults.autoInvite.inviteRanks = { [1] = true }
    PRT.defaults.autoInvite.promoteEnabled = false
end

-- Simulate a single invitee accepting and the resulting roster update.
local function accept(name)
    table.insert(sim.members, name)
    AutoInvite:OnGroupRosterUpdate()
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

-- The headline case: solo leader mass-invites more people than a party holds.
-- The party must fill, convert to a raid, and then invite everyone else.
tests["mass invite of 8 from solo fills party, converts, invites the rest"] = function()
    local guild = buildGuildRoster(8)
    withGlobals(makeStubs(guild), function()
        sim = newSim()
        resetModuleState()
        setInviteRanks()

        AutoInvite:InviteByRank()
        AutoInvite:OnGuildRosterUpdate()

        -- First burst: only the four party slots go out. Nothing has been
        -- accepted, so a naive count-based approach would blast all eight here.
        flushTimers()
        assertEquals(#sim.inviteOrder, 4,
            "solo party should only invite 4 before converting")
        assertEquals(sim.convertCalls, 0,
            "no conversion until a party exists")

        -- A player accepts. Still a party, conversion pending -> request convert.
        accept("Guildie1")
        assertTrue(sim.convertCalls >= 1, "acceptance should trigger conversion")
        assertTrue(sim.inRaid, "group should now be a raid")

        -- The conversion produces another roster update; the queued invites flush.
        AutoInvite:OnGroupRosterUpdate()
        flushTimers()

        -- Everyone the mass invite selected has now been invited.
        for i = 2, 8 do
            assertTrue(sim.invited["Guildie" .. i],
                "Guildie" .. i .. " should have been invited")
        end
        assertEquals(#sim.inviteOrder, 8, "all 8 guildies should be invited")
    end)
end

-- When the whole group fits in a party, no conversion should happen.
tests["mass invite that fits in a party does not convert"] = function()
    local guild = buildGuildRoster(3)
    withGlobals(makeStubs(guild), function()
        sim = newSim()
        resetModuleState()
        setInviteRanks()

        AutoInvite:InviteByRank()
        AutoInvite:OnGuildRosterUpdate()
        flushTimers()

        assertEquals(#sim.inviteOrder, 3, "all 3 fit and should be invited")
        assertEquals(sim.convertCalls, 0, "a party of 4 needs no raid conversion")
        assertFalse(sim.inRaid, "should remain a party")
    end)
end

-- Already a raid: invite everyone straight away, no conversion.
tests["mass invite while already a raid invites everyone directly"] = function()
    local guild = buildGuildRoster(8)
    withGlobals(makeStubs(guild), function()
        sim = newSim()
        resetModuleState()
        setInviteRanks()

        -- Pretend we are a raid of 6 (existing members are not guildies).
        sim.inRaid = true
        sim.members = { "Tank", "Healer", "Dps1", "Dps2", "Dps3" }

        AutoInvite:InviteByRank()
        AutoInvite:OnGuildRosterUpdate()
        flushTimers()

        assertEquals(#sim.inviteOrder, 8, "all 8 guildies invited in one pass")
        assertEquals(sim.convertCalls, 0, "already a raid, no conversion")
    end)
end

return tests
