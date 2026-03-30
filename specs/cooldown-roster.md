---
status: review
---

# Cooldown Roster

## What and Why

The previous cooldown tracker attempted to show real-time cooldown state (available, active, on cooldown) but was killed by Blizzard's combat log restrictions, which secret-ify all UNIT_AURA fields during boss encounters. This feature takes a much simpler approach: it shows what cooldowns *exist* in the raid based on group composition and spec data. No aura tracking, no combat log, no secret values.

The goal is situational awareness. A raid leader (or anyone) can glance at the display and see "we have two Tranquilities, a Spirit Link, a Rally, and three externals" without memorizing the roster. It answers "what tools do we have?" not "what's on cooldown right now?"

This feature replaces the CooldownPrototype diagnostic module, which should be removed.

## Behavior

### Composition Scanning

The system scans the raid roster to build a list of available cooldowns. For each raid member:

1. Get their class from `GetRaidRosterInfo`.
2. Get their specialization via the inspection API (`NotifyInspect` / `INSPECT_READY` / `GetInspectSpecialization`).
3. Look up which cooldowns that class+spec combination provides from the spell data table.
4. Add one entry per cooldown to the roster display.

Scanning triggers on:
- `GROUP_ROSTER_UPDATE` (someone joins, leaves, or moves groups)
- `INSPECT_READY` (spec data becomes available for a previously-unknown player)
- Initial load when entering a group

### Inspection Queue

Spec data requires inspecting each player, which is throttled by the WoW API. The system should reuse the pattern from the old CooldownTracker:

- Maintain a queue of players who need inspection.
- Process one inspection at a time, at a rate that avoids API throttling (the old system used 0.5-second intervals).
- Pause the queue during combat (`PLAYER_REGEN_DISABLED`) and resume after (`PLAYER_REGEN_ENABLED`), since `NotifyInspect` fails in combat.
- Cache inspection results by GUID so players only need to be inspected once per session (or until they leave and rejoin).

### Spell Data

The cooldown list is based on the old CooldownTrackerData, organized into three categories. Each entry needs: spell name, spell ID (for the icon), the class that provides it, and which spec(s) within that class have it.

**Defensive** (raid-wide healing or damage reduction):
- Tranquility (Restoration Druid)
- Dream Flight (Preservation Evoker)
- Rewind (Preservation Evoker)
- Healing Tide Totem (Restoration Shaman)
- Spirit Link Totem (Restoration Shaman)
- Revival / Restoral (Mistweaver Monk — these are the same cooldown, different talent choices)
- Aura Mastery (Holy Paladin)
- Power Word: Barrier (Discipline Priest)
- Luminous Barrier (Discipline Priest — talent alternative to PW:B, same cooldown slot)
- Divine Hymn (Holy Priest)
- Rallying Cry (any Warrior)
- Anti-Magic Zone (any Death Knight)
- Darkness (any Demon Hunter)

**External** (single-target protective cooldowns):
- Time Dilation (Preservation Evoker)
- Pain Suppression (Discipline Priest)
- Ironbark (Restoration Druid)
- Blessing of Sacrifice (any Paladin)
- Guardian Spirit (Holy Priest)

**Movement** (raid movement aids):
- Stampeding Roar (any Druid)
- Wind Rush Totem (any Shaman)
- Time Spiral (any Evoker)

The spell list is assumed correct based on the old CooldownTrackerData. Verify in-game during testing.

### Display

The display consists of three independently movable category groups: **Defensives**, **Externals**, and **Movement**.

Each group consists of:
- A **category header** (text label: "Defensives", "Externals", "Movement").
- A vertical stack of **bars** anchored below the header, one per cooldown entry in the roster.

Each bar shows:
- The spell icon (from the spell ID)
- The spell name
- The player name who provides it

Bars within a group are anchored relative to their category header and stack vertically. The entire group moves as one unit when dragged.

When the roster changes (player joins/leaves, spec data arrives), the bars within each group rebuild. Groups with no entries should hide entirely.

If multiple players provide the same cooldown (e.g., two Restoration Druids both have Tranquility), each gets its own bar.

### Frame Positioning

Each category group's position is saved per-profile and restored on login. The groups are draggable with standard click-and-drag when unlocked. A "Lock Frames" checkbox in the Cooldown Roster config tab controls whether the groups can be dragged. When locked (default), the frames ignore mouse interaction for dragging. When unlocked, they become draggable.

### Settings

Default settings:

```
cooldownRoster = {
    enabled = true,
    lockFrames = true,
    contentTypes = { ... }  -- same structure as dontRelease
    categories = {
        defensive = true,
        external = true,
        movement = true,
    },
}
```

- **enabled**: Master toggle.
- **lockFrames**: When true (default), category groups cannot be dragged. When false, they become draggable for repositioning.
- **contentTypes**: Same structure and UI pattern as DontRelease. Controls which content types the display is visible in (e.g., only Heroic/Mythic raids).
- **categories**: Per-category toggles. Hiding a category hides its entire group frame.

### Config UI

A new tab: "Cooldown Roster". Layout:

1. Master toggle: "Enable Cooldown Roster"
2. Lock Frames: "Lock frame positions" (checked by default)
3. Category toggles: checkboxes for Defensive, External, Movement
4. Content type checkboxes: same pattern as DontRelease's "Block Release In" section

### Visibility Logic

The display is visible when all of the following are true:
- `enabled` is true
- The player is in a group (raid or party)
- The current content type matches an enabled content type in settings
- At least one category is enabled and has entries

The display hides immediately when any condition becomes false (leaving the group, entering non-matching content, toggling off).

## Edge Cases

- **Player not yet inspected**: Show the player's class-wide cooldowns (ones available to any spec of that class, like Rallying Cry for Warriors). Once the spec is known, refine to show only their actual cooldowns. This means the display is useful immediately even before inspections complete.
- **Inspection fails**: Some players may be out of range or otherwise uninspectable. Keep them in the queue and retry periodically. Show class-wide cooldowns in the meantime.
- **Player changes spec mid-raid**: `GROUP_ROSTER_UPDATE` fires. Clear cached spec for that player and re-queue inspection.
- **Combat starts with pending inspections**: Pause the queue. Display whatever is known so far. Resume after combat ends.
- **Player leaves the group**: Remove all their entries from the display on the next `GROUP_ROSTER_UPDATE`.
- **Empty categories**: If no one in the raid provides Movement cooldowns, the Movement group hides entirely (no empty header floating around).
- **Solo player / not in group**: Display is hidden.
- **Party (5-man) vs. Raid**: Works in both. In a 5-man dungeon, you might only see Stampeding Roar and one external — that's fine, it's still useful information.

## What This Is NOT

This feature does **not** track:
- Whether a cooldown has been used
- How long until a cooldown is available again
- When a cooldown buff is active on someone

Those require aura data that Blizzard has made inaccessible during encounters. If Blizzard lifts those restrictions in a future patch, this feature could be extended — but that's not part of this spec.

## Validation

| What to Check | Expected Result |
|---|---|
| Join a raid with mixed classes | Bars appear showing correct cooldowns per player |
| Player leaves raid | Their cooldown entries disappear |
| New player joins | Their class-wide CDs appear immediately; spec-specific CDs appear after inspection |
| Enter non-matching content type | Display hides |
| Enter matching content type | Display shows |
| Disable a category in settings | That category's group hides |
| Drag a category group while unlocked | It moves; position is remembered after reload |
| Drag a category group while locked | Nothing happens; frame does not move |
| Uncheck "Lock frame positions", drag, recheck | Frame stays at new position; dragging is disabled again |
| Toggle master enable off | All groups hide |
| All categories empty | No frames visible (no orphaned headers) |
| Two players of same spec | Both get separate bars for shared cooldowns |
