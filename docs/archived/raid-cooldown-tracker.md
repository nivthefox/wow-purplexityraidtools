# Raid Cooldown Tracker

## Overview

A module that tracks raid-wide and personal external cooldowns by detecting buff application via `UNIT_AURA`, displaying availability and cooldown timers as grouped status bars.

## Problem

During raid encounters, the raid leader (and individual players) need to know which defensive and movement cooldowns are available, which are active, and when used cooldowns will be ready again. Midnight's secret value restrictions make CLEU-based tracking infeasible during boss encounters and M+ runs, but aura data remains readable.

## Approach

Rather than parsing combat log events, this module detects cooldowns by watching for known buff auras landing on the player. When a tracked buff appears, the module records the timestamp and begins a countdown timer based on the spell's known cooldown duration. This is explicitly a "best guess" system—talent-modified cooldowns and out-of-range casts will not be perfectly accurate.

### Validated Assumptions

The CooldownPrototype diagnostic module confirmed during a boss encounter (restricted context):
- `UNIT_AURA` fires with readable `addedAuras` data
- `spellId`, `name`, `sourceUnit`, `duration`, and `expirationTime` are all non-secret
- `C_Spell.IsExternalDefensive()` rejects secret values as arguments, so Blizzard's classification API cannot be used during restricted contexts
- `C_CombatLog.IsCombatLogRestricted()` correctly reports `true` during boss encounters

### Known Limitations

- **Range dependency.** If the player is out of range when a raid-wide cooldown is cast, no buff is applied and the module will not detect the usage. The bar remains "Available" even though the cooldown was consumed.
- **Cooldown duration is estimated.** Talent and gear modifications to cooldown durations are not detectable. The module uses base cooldown values, which may be slightly wrong.
- **Single-target externals only track when cast on you.** If Pain Suppression is cast on the main tank, you won't see it. This is acceptable—the module tracks what affects you.
- **Ground-effect cooldowns may not register.** Cooldowns like Spirit Link Totem or Anti-Magic Zone that create a zone only apply a buff if you stand in them. If you never enter the zone, you won't see the cast.

## Spell Data

The module maintains a hardcoded spell table since `C_Spell.IsExternalDefensive()` cannot be called during restricted contexts. Each entry contains:

| Field | Type | Purpose |
|---|---|---|
| `spellId` | number | The buff's spell ID (not the cast spell ID if they differ) |
| `name` | string | Display name |
| `category` | string | `"defensive"`, `"movement"`, or `"external"` |
| `cooldown` | number | Base cooldown duration in seconds |
| `class` | string | Class token (e.g., `"WARRIOR"`) |
| `specId` | number or nil | Required specialization ID. Nil means all specs of that class. |

The data table should be defined in a single location (`CooldownTrackerData.lua`) so it is easy to update when patches change values.

### Categories

1. **Defensive** — Raid-wide defensive and healing cooldowns (Rallying Cry, Revival, Aura Mastery, Tranquility, etc.)
2. **Movement** — Raid-wide movement cooldowns (Stampeding Roar, Wind Rush Totem, Time Spiral)
3. **External** — Single-target defensive cooldowns cast on the player (Pain Suppression, Ironbark, Blessing of Sacrifice, etc.)

### Tracked Spells

Spell IDs listed below are sourced from Wowhead and represent the **cast** spell ID. Some abilities have a different buff spell ID (the ID that appears in `UNIT_AURA` when the buff lands). Where known, the buff ID is noted. Where the buff ID is unknown, the cast ID is used as a starting point and must be corrected if it doesn't match in-game.

#### Defensive

| Spell | Cast ID | Buff ID | Class | Spec | Base CD |
|---|---|---|---|---|---|
| Tranquility | 740 | ? | Druid | Restoration | 180s |
| Dream Flight | 359816 | ? | Evoker | Preservation | 120s |
| Rewind | 363534 | ? | Evoker | Preservation | 240s |
| Healing Tide Totem | 108280 | ? | Shaman | Restoration | 180s |
| Spirit Link Totem | 98008 | ? | Shaman | Restoration | 180s |
| Revival | 115310 | ? | Monk | Mistweaver | 180s |
| Restoral | 388615 | ? | Monk | Mistweaver | 180s |
| Aura Mastery | 31821 | ? | Paladin | Holy | 180s |
| Power Word: Barrier | 62618 | ? | Priest | Discipline | 180s |
| Luminous Barrier | 271466 | ? | Priest | Discipline | 180s |
| Divine Hymn | 64843 | ? | Priest | Holy | 180s |
| Rallying Cry | 97462 | 97463 | Warrior | All | 180s |
| Anti-Magic Zone | 51052 | ? | Death Knight | All | 120s |
| Darkness | 196718 | ? | Demon Hunter | All | 300s |

Revival and Restoral are a choice node—a Mistweaver will have one or the other, never both.

#### Movement

| Spell | Cast ID | Buff ID | Class | Spec | Base CD |
|---|---|---|---|---|---|
| Stampeding Roar | 106898 | ? | Druid | All | 120s |
| Wind Rush Totem | 192077 | ? | Shaman | All | 120s |
| Time Spiral | 374968 | ? | Evoker | All | 120s |

#### External

| Spell | Cast ID | Buff ID | Class | Spec | Base CD |
|---|---|---|---|---|---|
| Time Dilation | 357170 | ? | Evoker | Preservation | 120s |
| Pain Suppression | 33206 | ? | Priest | Discipline | 120s |
| Ironbark | 102342 | ? | Druid | Restoration | 60s |
| Blessing of Sacrifice | 6940 | ? | Paladin | Holy | 120s |
| Guardian Spirit | 255312 | ? | Priest | Holy | 60s |

### Spell ID Notes

The spell data table must use the **buff** spell ID (what appears in `UNIT_AURA` `addedAuras`), not the cast spell ID. Rallying Cry demonstrates the discrepancy: cast ID is 97462, but the buff that lands on the player is 97463. Buff IDs marked with `?` need to be confirmed in-game. If the cast ID and buff ID are the same for a given spell, the cast ID is correct as-is.

## Composition Scanning

### When It Runs

- On `GROUP_ROSTER_UPDATE` — whenever the group composition changes
- On module enable — initial scan of current group
- On `INSPECT_READY` — as spec inspection results arrive

### What It Does

1. Iterate group members using `GetNumGroupMembers()` with `UnitClass("raidN")` and `UnitGroupRolesAssigned("raidN")`
2. For each member, look up their class against the spell data table
3. Queue spec inspection for each member (see Spec Detection below)
4. Build a list of expected cooldowns: one entry per player per matching spell
5. Create or update bars to match the expected cooldown list

### Spec Detection via Inspection

The module uses the inspection API to determine each player's specialization, which controls which spec-restricted cooldowns are shown.

**Inspection flow:**
1. On `GROUP_ROSTER_UPDATE`, queue all group members for inspection
2. Process the queue at approximately 2 inspections per second (to stay within server throttle limits)
3. For each member: call `NotifyInspect(unit)`, wait for `INSPECT_READY`, then call `GetInspectSpecialization(unit)` to get the spec ID
4. Use `GetSpecializationInfoForSpecID(specID)` to resolve the spec identity
5. Update the cooldown list for that player—remove bars for spells that require a different spec

**Before inspection completes**, the module falls back to showing all possible cooldowns for that class. Once the spec is confirmed, bars for abilities belonging to other specs are removed.

**Inspection only runs outside of restricted contexts.** During boss encounters and M+ runs, the module does not attempt inspections. It relies on whatever spec data was gathered before combat.

**Re-inspection triggers:**
- `GROUP_ROSTER_UPDATE` (new members, role changes)
- Player login / reload while in a group

### Dynamic Discovery

If a tracked buff lands on the player from a source that wasn't in the pre-scan (e.g., a talent-granted cooldown the composition scan didn't predict), the module adds a bar for that player+spell dynamically. Once discovered, it persists until the player leaves the group.

## Bar States and Lifecycle

Each bar represents one player's one cooldown ability.

### States

| State | Color | Bar Fill | Text |
|---|---|---|---|
| Available | Green | Full | "Available" |
| Active | Gold/Yellow | Draining (buff duration countdown) | Remaining buff duration (e.g., "8.1s") |
| On Cooldown | Red/Dim | Filling (cooldown progress) | Remaining cooldown (e.g., "2:45") |

### State Transitions

```
[Group Scan Detects Cooldown] → Available
[Buff Applied to Player]      → Active (duration = auraData.duration)
[Buff Removed / Expires]      → On Cooldown (remaining = baseCooldown - buffDuration)
[Cooldown Timer Expires]      → Available
[Player Leaves Group]         → Bar Removed
[Combat Starts]               → Reset all to Available
```

### Combat Start Reset

When `PLAYER_REGEN_DISABLED` fires (entering combat), all bars reset to Available. This is a deliberate simplification—a cooldown used 30 seconds before the pull will incorrectly show as Available. The alternative (tracking cooldowns across combat boundaries) adds significant complexity for marginal accuracy gains.

### Re-Use During Combat

If a tracked buff lands on the player while that cooldown's bar is already in the "On Cooldown" state (meaning the same ability was used again—perhaps the cooldown estimation was wrong, or a different player with the same class used it), the bar transitions back to Active and the cooldown timer restarts when the buff expires.

## Display

### Layout

A movable, lockable anchor frame containing grouped status bars:

```
┌─────────────────────────────────────┐
│ Defensive Cooldowns                 │
│ [Icon] Rallying Cry (Tankname)  2:45│
│ [Icon] Aura Mastery (Healname) Avail│
│                                     │
│ Movement Cooldowns                  │
│ [Icon] Stampeding Roar (Druid) Avail│
│                                     │
│ External Cooldowns                  │
│ [Icon] Pain Supp (Priest)     Avail │
└─────────────────────────────────────┘
```

### Bar Contents

Each bar displays:
- **Spell icon** on the left
- **Spell name** and **player name** (class-colored) as the bar label
- **Status text** on the right: "Available", countdown seconds, or MM:SS for longer cooldowns
- **Bar color** reflecting state (green/gold/red)
- **Bar fill** animating for active buff duration (draining) and cooldown progress (filling)

### Category Headers

Each category ("Defensive Cooldowns", "Movement Cooldowns", "External Cooldowns") gets a header label. Categories with no detected cooldowns (or disabled in settings) are hidden entirely.

### Sorting Within Categories

Bars within a category are sorted by state priority, then alphabetically:
1. Active (currently providing a buff)
2. Available (ready to use)
3. On Cooldown (sorted by remaining time, shortest first)

### Frame Behavior

- Visible whenever the player is in a group (party or raid) and the module is enabled
- Movable by dragging when unlocked
- Position saved in settings (per-profile)
- Grows/shrinks vertically as bars are added/removed
- Does not appear during solo play

## Configuration

A new tab in the PurplexityRaidTools config frame, following the existing pattern.

### Settings

| Setting | Type | Default | Description |
|---|---|---|---|
| Enabled | checkbox | true | Master enable/disable for the module |
| Track Defensive | checkbox | true | Show defensive cooldown category |
| Track Movement | checkbox | true | Show movement cooldown category |
| Track External | checkbox | true | Show external cooldown category |
| Lock Frame | checkbox | false | Prevent the display frame from being dragged |
| Bar Height | slider | 20 | Height of each cooldown bar in pixels |
| Bar Width | slider | 250 | Width of each cooldown bar in pixels |
| Show Only in Combat | checkbox | false | Hide the frame outside of combat (overrides default always-visible behavior) |

### Defaults in PRT.defaults

```
cooldownTracker = {
    enabled = true,
    categories = {
        defensive = true,
        movement = true,
        external = true,
    },
    lockFrame = false,
    barHeight = 20,
    barWidth = 250,
    showOnlyInCombat = false,
    framePosition = nil,
}
```

## Events

| Event | Response |
|---|---|
| `ADDON_LOADED` | Initialize module, run initial composition scan if in group |
| `GROUP_ROSTER_UPDATE` | Re-scan composition, queue inspections, add/remove bars |
| `INSPECT_READY` | Process inspection result, refine cooldown list for inspected player |
| `UNIT_AURA` (player) | Check `addedAuras` against spell table; transition matching bars to Active |
| `PLAYER_REGEN_DISABLED` | Reset all bars to Available (combat start) |
| `PLAYER_REGEN_ENABLED` | Resume inspection queue if members are un-inspected |

### Aura Removal Detection

When a tracked buff expires, the bar transitions from Active to On Cooldown. Detection approach:

- `UNIT_AURA` with `removedAuraInstanceIDs` — the module must track the `auraInstanceID` from `addedAuras` and match it on removal
- Alternatively, use the `expirationTime` from the aura data and calculate the cooldown start time from there

The `auraInstanceID` approach is more reliable since buffs can be dispelled or cancelled early.

## File Structure

```
Modules/
    CooldownTracker.lua         — Module logic, event handling, composition scanning, inspection queue
    CooldownTrackerDisplay.lua  — Bar frames, layout, animation
    CooldownTrackerData.lua     — Spell ID table (separated for easy maintenance)
```

The CooldownPrototype module (`Modules/CooldownPrototype.lua`) should be deleted during implementation.

## Resolved Questions

1. **Heroism/Bloodlust/Time Warp.** Not tracked. Every raid frame already tracks Exhaustion/Sated, and hero is a fundamentally different kind of cooldown (one use per encounter).
2. **Multiple charges.** Ignored for v1. One bar per player per spell. If a talent grants multiple charges, the bar re-triggers when the next charge is used.
3. **Barkskin vs. Ironbark.** The external is Ironbark (cast on another player), not Barkskin (self-cast only).
4. **Spec detection.** Use the inspection API between pulls (~2/second) to determine specs. Fall back to showing all class-possible cooldowns for un-inspected players.

## Open Questions

1. **Buff spell IDs.** Most spell IDs in the data table are sourced from Wowhead and represent the cast ID. Rallying Cry confirmed a discrepancy (cast 97462, buff 97463). The remaining buff IDs need in-game validation and correction during implementation.
