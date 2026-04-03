# MRT Replacement Research Notes

Research by Sage for Zoe. Last updated 2026-02-28.

## Context

Niv wants PRT to replace MRT as the guild-required addon. The scope is limited to specific MRT features that Purplexity actually uses. This is not a full MRT competitor—it's a targeted replacement for a known feature set.

## CRITICAL: Midnight API Restrictions (Secret Values)

Midnight (patch 12.0) introduced "Secret Values," the largest addon API change in WoW's history. This fundamentally changes what's feasible for raid tool addons. Zoe, you **must** design around these constraints.

### What Changed

- **Combat log events** (`COMBAT_LOG_EVENT_UNFILTERED`): Addons can no longer parse these. The data is opaque.
- **Addon messaging** (`SendAddonMessage`): Blocked during active raid encounters and M+ runs. **Available between pulls.** Initially Blizzard blocked all instance comms; they walked it back after community feedback to only restrict during active encounters.
- **Combat state APIs** (e.g., `UnitAffectingCombat`): Return "secret values" during restricted periods—addons can display them but can't read them programmatically.
- **Aura/cooldown queries**: Secret during encounters. Addons can't inspect other players' buffs/debuffs/cooldowns.
- **WeakAuras**: Effectively dead for combat functionality. The team declined to update for Midnight.
- **BigWigs/DBM**: Still working, but adapted to use Blizzard's native encounter data system (boss timeline) rather than parsing CLEU independently. They still emit phase change callbacks (`BigWigs_SetStage`, `DBM_SetStage`).
- **Encounter events**: `ENCOUNTER_START` and `ENCOUNTER_END` still fire. BigWigs/DBM depend on them.

### What Still Works

- All UI customization (frames, fonts, textures, positioning)
- Addon comms between encounters
- Spell texture lookups (`C_Spell.GetSpellTexture`)
- Raid roster queries (names, classes, roles, groups)
- Party/raid management APIs (`SetRaidTargetIcon`, `C_PartyInfo.InviteUnit`, etc.)
- Chat events outside instances (`CHAT_MSG_WHISPER`, etc.)

### How BigWigs Adapted (Retail Midnight Architecture)

Blizzard replaced CLEU-based boss tracking with three new encounter APIs:

1. **`C_EncounterTimeline`** — Countdown bars for upcoming abilities. Fires `ENCOUNTER_TIMELINE_EVENT_ADDED` when a boss ability is queued. Event info contains NeverSecret fields (id, duration, source, maxQueueDuration) and secret fields (spellID, spellName, iconFileID). Addons can display them via Blizzard's secret-value rendering but can't read spell details programmatically.

2. **`C_EncounterWarnings`** — Alert messages when abilities fire. `ENCOUNTER_WARNING` carries severity, duration (not secret), and secret fields (text, casterName, targetName, iconFileID, etc.).

3. **`C_EncounterEvents`** — Event metadata for customizing colors and sounds per encounter event ID.

BigWigs hooks into all three:
- **Timeline plugin** → registers for `ENCOUNTER_TIMELINE_EVENT_ADDED/STATE_CHANGED/REMOVED`, creates/manages bar display.
- **Messages plugin** → registers for `ENCOUNTER_WARNING`, shows alert text on screen.
- **Sound plugin** → registers for `ENCOUNTER_WARNING`, plays audio alerts.

On Retail, `boss:Log()` (CLEU registration) returns immediately without doing anything. Boss modules use `OnEncounterStart()` instead of the Classic `OnEngage()`, and handler functions receive `duration` parameters from the timeline system. `BigWigs_SetStage` is still emitted from `boss:SetStage(stage)`, which boss modules call for phase transitions.

Key finding: `C_EncounterTimeline.AddScriptEvent()` lets addons add their own custom bars to the timeline. BigWigs uses this (or will use this) for "enhanced" timer mode where bars have customized text (ability counts, friendly labels) instead of Blizzard's raw spell names.

### Sources

- [Blizzard: Combat Philosophy and Addon Disarmament](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [Blizzard: How Midnight's Changes Impact Combat Addons](https://news.blizzard.com/en-us/article/24244638/how-midnights-upcoming-game-changes-will-impact-combat-addons)
- [Blizzard Forum: Beta UI and Addons Update](https://us.forums.blizzard.com/en/wow/t/beta-ui-and-addons-update/2177122) — confirms addon comms relaxed between encounters
- [Warcraft Wiki: 12.0.0 API Changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [WowCoach: Best Raid Tools for Midnight 2026](https://wowcoach.gg/blog/best-raid-tools-wow-midnight-2026) — confirms MRT notes "all working"
- BigWigs source code: `Core/BossPrototype.lua`, `Plugins/Timeline.lua`, `TheVoidspire/*.lua`
- WoW UI source: `Blizzard_APIDocumentationGenerated/EncounterTimeline*.lua`, `EncounterWarnings*.lua`, `EncounterEvents*.lua`

---

## Feature 1: Auto-Marking by Name — ✅ Feasible

**MRT Source:** `Marks.lua` (120 lines total, ~20 lines of core logic)

**MRT Status:** Disabled for Midnight (`if ExRT.isMN then return end`). However, the API (`SetRaidTargetIcon`) still exists in the Midnight UI source and is used by Blizzard's own keybindings and unit popup menus. MRT likely disabled it because the 0.5s polling approach doesn't play well with encounter restrictions, not because the API is gone.

**PRT Approach:** Apply marks on demand (button press or event-driven), not via continuous polling. Apply marks between pulls. Don't attempt to maintain marks during active encounters.

**How it works:** Eight text fields, one per raid icon. Each holds a player name or comma-separated fallback names. When triggered, iterate names and call `SetRaidTargetIcon(unit, markNum)` for the first matching player found in the raid.

**Key APIs:**
- `SetRaidTargetIcon(unit, markIndex)` — wrapper around `SetRaidTarget`; applies a raid target icon (1-8)
- `GetRaidTargetIndex(unit)` — checks current mark to avoid redundant calls
- `UnitName(name)` — validates the player is in the raid

**Config surface:**
- 8 text input fields (one per mark icon)
- "Apply Marks" button (or auto-apply on ENCOUNTER_END / GROUP_ROSTER_UPDATE)
- Clear All button

**Complexity:** Trivial. Clean module boundary, no external dependencies, no addon comms.

**Effort:** An afternoon.

---

## Feature 2: Auto-Invite — ✅ Feasible

**MRT Source:** `InviteTool.lua` (956 lines, but most is UI and features Niv doesn't need)

**MRT Status:** Still active in Midnight (no `isMN` gate). This feature operates entirely outside instances, so Secret Values restrictions don't apply.

**Core feature Niv uses:** Listen for whispered keywords (e.g., "inv", "123") and auto-invite the sender.

**How whisper-based invite works:**
1. Register for `CHAT_MSG_WHISPER` and `CHAT_MSG_BN_WHISPER`
2. Lowercase and trim the incoming message
3. Check against a configurable keyword set (stored as a table for O(1) lookup)
4. Optionally restrict to guild members only
5. If fewer than 5 members, invite directly; auto-convert to raid at 5+

**BNet invite path:** More complex than character whispers. When a BNet friend whispers a keyword:
1. Find the sender's `bnetAccountID` in the friends list via `C_BattleNet.GetFriendAccountInfo`
2. Enumerate their game accounts via `C_BattleNet.GetFriendNumGameAccounts` / `C_BattleNet.GetFriendGameAccountInfo`
3. Find the WoW Retail account that's online and in the right region
4. Call `BNInviteFriend(gameAccountID)`

**Auto-convert to raid:** When inviting would exceed 5 members, calls `C_PartyInfo.ConvertToRaid()`. Uses a `GROUP_ROSTER_UPDATE` handler to retry pending invites after the conversion completes.

**Key APIs:**
- `C_PartyInfo.InviteUnit(name)` — invite a character
- `BNInviteFriend(gameAccountID)` — invite a BNet friend's game account
- `C_PartyInfo.ConvertToRaid()` — convert party to raid
- `C_BattleNet.GetFriendAccountInfo(friendIndex)` — BNet friend lookup
- `C_BattleNet.GetFriendNumGameAccounts` / `C_BattleNet.GetFriendGameAccountInfo` — enumerate game accounts
- `GetNumGuildMembers()` / `GetGuildRosterInfo(i)` — guild roster for guild-only filtering
- PRT will need its own `UnitInGuild(name)` helper (MRT has one at `ExRT.F.UnitInGuild`)

**Config surface (minimal viable):**
- Enable/disable whisper invite
- Keyword list (text input, space-delimited)
- Guild-only toggle

**Features Niv probably doesn't need:** Guild rank-based mass invite, 4 preset invite lists, auto-promote by rank/name, demote tracking, reinvite (disband + re-invite), auto raid difficulty, auto-accept invites, loot method management (Classic-only).

**Complexity:** Moderate. The character whisper path is simple. The BNet path is fiddly because of the `C_BattleNet` API surface. The auto-convert-to-raid dance with `GROUP_ROSTER_UPDATE` requires a small state machine.

**Effort:** 1-2 days.

---

## Feature 3: Fight Notes (Visero Format) — ⚠️ Feasible with Caveats

**MRT Source:** `Note.lua` (4,592 lines). This is the big one.

**MRT Status:** Still active in Midnight (no `isMN` gate). Confirmed working by multiple sources. The CLEU-based timer features silently don't fire (no events to trigger them), but everything else works.

**Niv's workflow:** Copy note text from Visero's website → paste into a simple text editor in PRT → broadcast to raid between pulls → everyone's PRT receives and renders it. No draft library, no encounter-based auto-loading, no note history. Auto-clear on boss kill and/or leaving raid. Store current note text so it survives reloads.

### The Note Format

The MRT note format is a mini-language built on gsub pattern substitutions. PRT must support the full format for Visero compatibility.

**Role filtering (evaluated first, before other patterns):**
- `{H}...{/H}` — show only to healers
- `{T}...{/T}` — show only to tanks
- `{D}...{/D}` — show only to DPS

**Player/group filtering:**
- `{P:name1,name2}...{/P}` — show only to listed players
- `{!P:name1}...{/P}` — hide from listed players
- `{C:class}...{/C}` — show only to class (supports localized names, English names, abbreviations like "dk" or "sham", and numeric IDs)
- `{!C:class}...{/C}` — hide from class
- `{ClassUnique:class1,class2}...{/ClassUnique}` — show to the first matching class found in the raid
- `{G1}...{/G}` — show only to raid group N
- `{!G1}...{/G}` — hide from raid group N
- `{Race:race}...{/Race}` — show only to race
- `{!Race:race}...{/Race}` — hide from race

**Context filtering:**
- `{E:encounterID}...{/E}` — show only during specific encounter
- `{Z:zoneName}...{/Z}` — show only in specific zone (by name or instance ID)
- `{P1}...{/P}` (no colon, numeric) — show only during boss phase N (requires encounter to be active)
- `{!P1}...{/P}` — hide during boss phase N
- `{0}...{/0}` — always hidden (comment sections)

**Inline elements:**
- `{spell:ID}` or `{spell:ID:size}` — inline spell icon (via `C_Spell.GetSpellTexture`)
- `{icon:path}` — arbitrary icon texture
- `{rt1}` through `{rt8}` — raid target icons (also supports localized names like `{star}`, `{circle}`, etc.)
- Class icons (`{Warrior}`, `{Paladin}`, etc.)
- Role icons (`{tank}`, `{healer}`, `{dps}`)
- `{self}` — replaced with personal note text

**Timer system — PARTIALLY BROKEN BY SECRET VALUES:**

What still works:
- `{time:X}` — countdown from encounter start. `ENCOUNTER_START` still fires; the countdown is just `GetTime()` math.
- `{time:X,p:N}` — countdown from phase N start. BigWigs/DBM still emit `BigWigs_SetStage` / `DBM_SetStage` callbacks.
- `{time:X,pg:N}` — countdown from global phase N start. Same mechanism.
- `{time:X,e:name}` — countdown from custom named timer.
- `{time:X,...,glow}` — glow the note frame when ≤5s and line contains player's name.
- `{time:X,...,glowall}` — glow regardless of name.
- `{time:X,...,all}` — show to all players even when "only show my timers" is enabled.

What is DEAD (CLEU is gone):
- `{time:X,SCS:spellID:count}` — countdown from Nth `SPELL_CAST_START`. **Non-functional.**
- `{time:X,SCC:spellID:count}` — countdown from Nth `SPELL_CAST_SUCCESS`. **Non-functional.**
- `{time:X,SAA:spellID:count}` — countdown from Nth `SPELL_AURA_APPLIED`. **Non-functional.**
- `{time:X,SAR:spellID:count}` — countdown from Nth `SPELL_AURA_REMOVED`. **Non-functional.**
- All name-scoped and phase-scoped CLEU variants — **non-functional.**
- `{time:X,...,wa:eventID}` — WeakAura event integration. **WeakAuras combat functionality is dead.**

**No replacement path for CLEU counters:** The `C_EncounterTimeline` API provides countdown bars for upcoming abilities, but the spell data in those events is secret—addons can't read `spellID` or `spellName` programmatically to match against note patterns. There is no addon-accessible equivalent of "the boss cast Ability X for the 3rd time." The timeline tells you *when* the next ability is coming, but not *which* ability in a way addons can use for logic.

**PRT should still parse these patterns** (for format compatibility) but they will simply never trigger their countdowns. They'll render as static timestamps, same as MRT does now.

**Auto-coloring:** All player names in the rendered text are automatically colored by class. Built by scanning the raid roster for `name → "|cCOLORname|r"` and running it as the final gsub pass. This still works—raid roster queries are not restricted.

**Timer display states:**
- `> 10s remaining` or `outside encounter` — gold text, shows `M:SS`
- `0-10s remaining` — green text, player's own name highlighted in red
- `< 0` (passed) — gray text, or hidden if "hide passed timers" is enabled

### Addon Communication Protocol

**Timing constraint:** `SendAddonMessage` is blocked during active encounters but available between pulls. Notes must be sent between encounters. This matches the natural workflow (RL sends note before first pull or between wipes).

**Channel:** PRT should use its own prefix (e.g., `"PRT"`), not MRT's `"EXRTADD"`. This cleanly separates it from MRT if anyone in the raid still has MRT installed.

**Sending a note:**
1. Chunk the note text into 220-character segments
2. Generate a unique index: `tostring(GetTime()) .. tostring(math.random(1000,9999))`
3. Send each chunk as: `SendAddonMessage(prefix, "multiline\t" .. index .. "\t" .. chunk, "RAID")`
4. Send completion marker: `SendAddonMessage(prefix, "multiline_add\t" .. index, "RAID")`

**Receiving a note:**
1. Listen for addon messages with the PRT prefix
2. On `multiline`: if index matches current, append chunk; otherwise start new note with this chunk
3. On `multiline_add`: note is complete; store and render

**Clearing a note:** PRT needs a "clear" message type (MRT doesn't have one). Something like: `SendAddonMessage(prefix, "note_clear", "RAID")`. This must also be sent between encounters.

### Encounter Integration

**Phase tracking via boss mods:**
```lua
-- BigWigs (still working in Midnight)
BigWigsLoader.RegisterMessage({}, "BigWigs_SetStage", function(event, addon, stage)
    SetPhase(stage)
end)

-- DBM (still working in Midnight)
DBM:RegisterCallback("DBM_SetStage", function(event, addon, modId, stage, encounterId, globalStage)
    SetPhase(stage, globalStage)
end)
```

On phase change, `SetPhase` records `encounter_time_p[stage] = GetTime()` and resets per-phase state.

**How BigWigs phases still work:** On Retail, boss modules call `self:SetStage(stage)` which fires `BigWigs_SetStage`. This is called from within boss module code (not from CLEU). The boss modules themselves determine phase transitions based on Blizzard's encounter data system, and `BigWigs_SetStage` is still emitted as a public message that any addon can listen to.

**CLEU counter system:** NOT IMPLEMENTABLE. Combat log events are no longer available to addons in Midnight. PRT should parse `SCS`/`SCC`/`SAA`/`SAR` patterns for format compatibility but they will not fire. Do not register for `COMBAT_LOG_EVENT_UNFILTERED`.

**Timer update loop:** During an active encounter, a 1-second timer re-renders the note to update countdowns. Registered on `ENCOUNTER_START`, unregistered on `ENCOUNTER_END`. This still works—it's just `GetTime()` math, not combat data.

### Storage

- `noteText` — the current note (persisted in SavedVariables to survive reloads)
- `autoClearOnKill` — bool setting
- `autoClearOnLeave` — bool setting
- Font size, frame position, frame strata, show/hide state

### Auto-Clear Triggers

- **Boss kill:** `ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)` where `success == 1`. Clear note text locally and broadcast a clear message (if between encounters—the encounter just ended, so comms should be available).
- **Leave raid:** `GROUP_ROSTER_UPDATE` when `GetNumGroupMembers() == 0`. Clear locally only.

### Display

A movable text frame with configurable font size. During encounters with `{time:}` patterns, refreshes every second. Outside encounters, renders once on note receipt.

**Effort:** 1-2 weeks. The renderer is mechanical but large. The CLEU counter system can be stubbed out (parse but don't implement), which saves time.

---

## Feature 4: Who Pulled — ❌ Likely Not Feasible

**MRT Source:** `WhoPulled.lua` (122 lines)

**MRT Status:** Disabled for Midnight (`if ExRT.isMN then return end`).

**Why it's broken:** The feature relies on `UnitAffectingCombat(unit)` to detect which raid member entered combat first. Under Secret Values, combat state data is opaque during restricted periods in instances. The detection has to happen at the exact moment someone enters combat—which is precisely when the restrictions are active.

**Could it be worked around?** Unclear. The `UNIT_FLAGS` event may still fire, but the data it carries may be secret. Even if the event fires, checking `UnitAffectingCombat` would return a secret value that can't be compared. This needs live testing to confirm, but MRT's decision to disable it is strong evidence that it doesn't work.

**Recommendation:** Drop this feature from the initial scope. If someone finds a workaround, it can be added later. It's the least important of the four—a novelty/shame tool rather than a raid management necessity.

---

## Effort Summary

| Module | Effort | Status |
|---|---|---|
| Auto-Marking | Afternoon | ✅ Between pulls, on demand |
| Auto-Invite | 1-2 days | ✅ Outside instances |
| Fight Notes | 1-2 weeks | ⚠️ CLEU timers dead, rest works |
| Who Pulled | N/A | ❌ Probably broken by Secret Values |

The fight notes module is the critical path. Everything else is straightforward.

---

## Design Decisions for Zoe

1. **Addon comm prefix:** PRT should use its own prefix, not `EXRTADD`. Cleanly separates it from MRT.

2. **Note clear protocol:** MRT has no "clear note" message. PRT needs one for auto-clear-on-kill (broadcast clear to all raiders when boss dies).

3. **CLEU timer patterns:** Parse them for format compatibility but stub out the implementation. They'll render as static gold timestamps (the "not in encounter" fallback), which is the same behavior MRT exhibits now since CLEU is dead.

4. **WeakAura event integration:** Dead. `{time:X,wa:eventID}` can be parsed but the `WeakAuras.ScanEvents` call should be skipped. WeakAuras combat functionality is discontinued.

5. **BigWigs vs DBM phase callbacks:** Both still work in Midnight. Both must be supported. MRT checks for BigWigs first, then DBM. The callbacks are similar but DBM provides `globalStage` while BigWigs doesn't (BigWigs sends `stage`, MRT auto-increments a global counter).

6. **Class abbreviation table:** The note format supports multiple ways to refer to classes (localized name, English name, abbreviation like "dk" or "sham", numeric ID). PRT needs the same lookup table for format compatibility.

7. **Auto-marking approach:** Use on-demand application (button or event-driven) rather than MRT's continuous 0.5s polling. Trigger on `ENCOUNTER_END`, `GROUP_ROSTER_UPDATE`, or manual button press. Don't poll during encounters.

8. **Note sending timing:** Notes can only be sent between encounters. The UI should make this clear—if the RL tries to send during an active encounter, either queue it or show a message explaining why it can't send right now.

9. **`SendAddonMessage` on ENCOUNTER_END for auto-clear:** When a boss dies, `ENCOUNTER_END` fires with `success == 1`. The encounter is now over, so addon comms should be available again. Broadcasting a clear message here should work, but the timing is worth testing—there may be a brief delay before comms reopen.

10. **No CLEU replacement exists:** The `C_EncounterTimeline` API provides countdown data for upcoming abilities, but the spell-identifying fields (spellID, spellName) are secret. Addons cannot programmatically determine *which* ability is on the timeline—only that *an* ability exists with a given duration. This means there is no way to build CLEU counter equivalents (`SCS`, `SCC`, etc.) using the new APIs. The data literally isn't available to addon code.
