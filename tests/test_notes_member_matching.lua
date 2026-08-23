-- tests/test_notes_member_matching.lua
-- NotesEditor.FindMemberByTag: the single decision "which group member does this
-- bare note tag refer to?", extracted from the two file-local call sites in
-- Modules/Notes/NotesEditor.lua (ClassColorForTag and FindMemberByName) so it can
-- be exercised without a frame.
--
-- Phase 0 made GroupInspect.members[].name a full "Name-Realm"
-- (docs/spec/2026-08-05-attendance-tracking.html), while note tags stay bare
-- ("tag:Niv"). Matching therefore Ambiguates the stored name down to the bare
-- character before comparing. Ambiguate(name, "short") returns the bare character
-- in every realm/guild case per warcraft.wiki.gg/wiki/API_Ambiguate, so the match
-- does not depend on the viewer's own realm.
--
-- members is a GUID-keyed hash, so a bare name shared by two members must not
-- resolve by iteration luck. The pinned rule is the lexicographically smallest
-- full name, with GUID breaking a tie. What these tests can and cannot show: the
-- duplicate fixtures order name against GUID so an implementation sorting on the
-- wrong key fails deterministically, but no fixture here proves independence from
-- iteration order, because the order a run receives is not controllable from
-- inside the test.
--
-- NotesEditor.lua builds no frames at load time, so it loads headless. It is
-- loaded defensively below so this file also runs standalone, mirroring
-- test_wiring.lua's convention.

local tests = {}

if not PurplexityRaidTools.NotesPlanner then
    dofile("Modules/Notes/NotesPlanner.lua")
end

if not PurplexityRaidTools.NotesEditor then
    dofile("Modules/Notes/NotesEditor.lua")
end

local PRT = PurplexityRaidTools
local NotesEditor = PRT.NotesEditor

local function membersFrom(records)
    local members = {}
    for _, record in ipairs(records) do
        members[record.guid] = {
            name = record.name,
            class = record.class,
            specId = record.specId,
        }
    end
    return members
end

-- The two Nivs order name and GUID AGAINST each other on purpose: Niv-Area52 wins
-- on name and loses on GUID. Respelling these so the two orderings agree would let
-- an implementation that never reads names pass every test in this file.
local NIV_ILLIDAN = { guid = "GUID-NIV-A", name = "Niv-Illidan", class = "ROGUE", specId = 260 }
local NIV_AREA52 = { guid = "GUID-NIV-Z", name = "Niv-Area52", class = "MAGE", specId = 62 }
local BOB_ILLIDAN = { guid = "GUID-BOB", name = "Bob-Illidan", class = "WARRIOR", specId = 71 }

tests["a bare tag matches the member stored as Name-Realm"] = function()
    local members = membersFrom({ NIV_ILLIDAN, BOB_ILLIDAN })

    local guid, member = NotesEditor.FindMemberByTag(members, "Niv")

    assertEquals(guid, "GUID-NIV-A", "the matching member's GUID must come back as the first return")
    assertNotNil(member, "the member record must come back as the second return")
    assertEquals(member.name, "Niv-Illidan")
    assertEquals(member.class, "ROGUE",
        "the caller colors the block from this record, so it must be the real record")
    assertEquals(member.specId, 260,
        "the caller looks up abilities from this record, so it must be the real record")
end

tests["tag matching ignores case on both sides"] = function()
    local members = membersFrom({ NIV_ILLIDAN })

    for _, tag in ipairs({ "niv", "NIV", "nIv", "Niv" }) do
        local guid = NotesEditor.FindMemberByTag(members, tag)
        assertEquals(guid, "GUID-NIV-A", "tag " .. tag .. " must match Niv-Illidan")
    end

    local lowercased = membersFrom({ { guid = "GUID-LOW", name = "niv-illidan" } })
    assertEquals((NotesEditor.FindMemberByTag(lowercased, "NIV")), "GUID-LOW",
        "a stored name of any case must match an uppercase tag")
end

tests["a tag naming nobody in the group returns nil"] = function()
    local members = membersFrom({ NIV_ILLIDAN, BOB_ILLIDAN })

    local guid, member = NotesEditor.FindMemberByTag(members, "Zed")

    assertNil(guid, "no match must return nil, not false")
    assertNil(member)
end

-- Characterization, not a preference: tags are bare today, and a realm-qualified
-- tag has never matched. Pinned so adding realm-qualified tags stays a decision.
tests["a realm-qualified tag does not match"] = function()
    local members = membersFrom({ NIV_ILLIDAN })

    assertNil((NotesEditor.FindMemberByTag(members, "Niv-Illidan")),
        "the tag is compared against the bare character name only")
end

tests["two members sharing a bare name resolve to the smallest full name"] = function()
    assertTrue(NIV_AREA52.name < NIV_ILLIDAN.name,
        "the fixture must actually order Niv-Area52 first by name")
    assertTrue(NIV_AREA52.guid > NIV_ILLIDAN.guid,
        "the fixture must actually order Niv-Area52 last by GUID, or this test "
        .. "cannot tell the two candidate sort keys apart")

    local members = membersFrom({ NIV_ILLIDAN, NIV_AREA52 })

    local guid, member = NotesEditor.FindMemberByTag(members, "niv")

    assertEquals(guid, "GUID-NIV-Z",
        "Niv-Area52 sorts FIRST by name and LAST by GUID: the winner must follow the name")
    assertEquals(member.name, "Niv-Area52")
end

-- Two members with the same Name-Realm cannot occur in a live raid. This pins the
-- comparator as a total order so even a degenerate roster resolves the same way
-- every time. It reads whatever iteration order the run happens to receive, which
-- makes it a real but probabilistic discriminator against an implementation with
-- no tie-break, not a proof that one is impossible.
tests["members with identical full names break the tie on GUID"] = function()
    local members = membersFrom({
        { guid = "GUID-B", name = "Niv-Illidan" },
        { guid = "GUID-A", name = "Niv-Illidan" },
    })

    local guid = NotesEditor.FindMemberByTag(members, "niv")

    assertEquals(guid, "GUID-A", "an equal name must fall through to the smaller GUID")
end

-- Guards against an implementation that sorts the caller's table in place or lets
-- a stale memo answer; either would let a later call answer differently from the
-- first, and a block re-renders every frame. It says nothing about iteration
-- order, which is fixed for an unmodified table within a run.
tests["repeated calls on the same roster return the same member"] = function()
    local members = membersFrom({ NIV_ILLIDAN, NIV_AREA52 })

    local firstGuid = NotesEditor.FindMemberByTag(members, "niv")
    for _ = 1, 20 do
        assertEquals((NotesEditor.FindMemberByTag(members, "niv")), firstGuid,
            "re-matching an untouched roster must not change the answer")
    end
end

-- GroupInspect never stores a nil or empty name; it stores a placeholder until the
-- name and the local realm both resolve (Modules/GroupInspect.lua PlaceholderName).
-- The placeholder is either the client's UNKNOWNOBJECT string or a real name whose
-- realm has not loaded, and neither identifies a character, so the rule is on
-- shape: no realm, no match. The retry timer upgrades the record to Name-Realm
-- shortly after, and matching resumes.
tests["a name with no realm never matches"] = function()
    local coldNameCache = membersFrom({ { guid = "GUID-UNK", name = "Unknown" } })
    assertNil((NotesEditor.FindMemberByTag(coldNameCache, "unknown")),
        "the placeholder written for a cold name cache is not an identity")

    local coldRealm = membersFrom({ { guid = "GUID-BOB", name = "Bob" } })
    assertNil((NotesEditor.FindMemberByTag(coldRealm, "bob")),
        "a real name still missing its realm is not an identity either, and this "
        .. "is the case an implementation comparing against a literal placeholder misses")
end

tests["a placeholder does not hide a resolved member behind it"] = function()
    local members = membersFrom({
        { guid = "GUID-UNK", name = "Unknown" },
        NIV_ILLIDAN,
    })

    assertEquals((NotesEditor.FindMemberByTag(members, "niv")), "GUID-NIV-A",
        "skipping a placeholder must not abandon the scan")
end

tests["a member record carrying no name is skipped"] = function()
    local members = { ["GUID-EMPTY"] = { class = "PRIEST" } }
    members["GUID-NIV-A"] = { name = "Niv-Illidan", class = "ROGUE" }

    assertEquals((NotesEditor.FindMemberByTag(members, "niv")), "GUID-NIV-A",
        "a record with no name must be stepped over, not error")
    assertNil((NotesEditor.FindMemberByTag(members, "priest")))
end

tests["an absent or empty roster returns nil"] = function()
    assertNil((NotesEditor.FindMemberByTag(nil, "niv")),
        "the roster is nil before GroupInspect initializes")
    assertNil((NotesEditor.FindMemberByTag({}, "niv")),
        "the roster is empty when solo")
end

tests["an absent or empty tag returns nil"] = function()
    local members = membersFrom({ NIV_ILLIDAN })

    assertNil((NotesEditor.FindMemberByTag(members, nil)),
        "an unset tag matches nobody")
    assertNil((NotesEditor.FindMemberByTag(members, "")),
        "an empty tag matches nobody")
end

return tests
