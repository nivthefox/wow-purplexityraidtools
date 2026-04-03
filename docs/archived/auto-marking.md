# Auto-Marking

> **Status: Blocked.** `SetRaidTarget()` is a protected function that requires a hardware event in the call stack as of Midnight. Calling it from a `C_Timer` callback—even out of combat—triggers `ADDON_ACTION_FORBIDDEN`. The timer-based polling approach described below does not work. This spec needs a redesign around a user-initiated trigger (keybind, button click, or similar) before implementation can proceed.

## Purpose

Automatically maintain raid target icons on designated players. The player configures which player should wear each icon, and PRT keeps those marks applied while the group is out of combat. This works in both raids and parties.

This replaces MRT's `Marks.lua` feature, which used continuous 0.5-second polling (now disabled in Midnight). PRT takes a similar approach—periodic re-application—but restricts it to out-of-combat periods, which avoids Secret Values restrictions entirely.

## Behavior

### Mark Assignment

Each of the eight raid target icons (Star, Circle, Diamond, Triangle, Moon, Square, Cross, Skull) has a text field that holds a comma-separated list of player names. These names represent a priority fallback list: PRT tries the first name, and if that player isn't in the group, it tries the next, and so on.

Names are matched against the group roster by character name (case-insensitive). Server names are not required for same-server players but should be supported for cross-realm players (e.g., `"Niv-Stormrage"`).

### Application Loop

PRT runs a periodic timer (approximately every 2 seconds) that walks each mark field and applies icons. On each tick, the loop:

1. Checks whether the player is in a group (party or raid). If not, skips the tick.
2. Checks whether the player is in combat. If so, skips the tick.
3. If in a raid, checks whether the player has permission to set marks (raid leader or assistant). If not, skips the tick silently—no error message, no chat output. In a party, this check is skipped because any party member can set marks.
4. For each mark field that has at least one name:
   a. Walks the name list in order.
   b. For each name, checks whether that player is in the group.
   c. If a match is found and that player does not already have this mark, applies the mark.
   d. If a match is found and that player already has this mark, skips it (no redundant API call).
   e. If no names in the list match anyone in the group, that mark is left alone—PRT does not clear it.
5. If a mark field is empty (no names configured), PRT ignores that icon entirely. It does not clear marks that it is not managing.

### What PRT Does Not Do

- **PRT does not clear marks it isn't managing.** If you manually mark a player with an icon that has no configured names, PRT leaves it alone.
- **PRT does not actively unmark.** If you remove a name from a field, PRT stops maintaining that mark. It does not remove the icon from whoever currently has it. Use the "Clear All Marks" button for that.
- **PRT does not apply marks during combat.** The timer tick is skipped entirely while in combat.
- **PRT does not warn about missing permissions.** In a raid, if you're not leader or assistant, marks simply aren't applied. No error, no nag. In a party, permissions are not an issue—anyone can mark.

## Edge Cases

### Same Player in Multiple Fields

If the same player appears in more than one mark field, the last mark processed wins (Skull is processed last). The earlier mark will be unset by the game when the later mark is applied to the same unit, and PRT will re-apply the earlier mark on the next tick, creating a flip-flop. This is a misconfiguration, and PRT does not attempt to detect or prevent it. The user will see the icons flickering and can fix the fields.

### Mark Conflicts with Manual Marks

If someone manually assigns a different player to an icon that PRT is managing, PRT will overwrite it on the next tick. This is intentional—PRT is the authoritative source for configured marks.

### Player Leaves or Goes Offline

When a configured player leaves the group or goes offline, PRT falls through to the next name in the fallback list on the next tick. If no fallback matches, that mark is left alone (it will naturally disappear from the departed player).

### Not in a Group

If the player is not in any group (party or raid), all ticks are skipped. No marks are applied while solo.

### All Fields Empty

If no mark fields have any names configured, ticks still run but do nothing meaningful. The implementer may optimize this (stop the timer when all fields are empty) but this is not required behavior.

## Configuration

### Config Tab: "Auto-Marking"

A new tab in the PRT config frame with the following layout:

**General Section**
- Enable/disable checkbox for the module

**Mark Assignments Section**
- Eight rows, one per raid icon, in standard icon order: Star (1), Circle (2), Diamond (3), Triangle (4), Moon (5), Square (6), Cross (7), Skull (8)
- Each row displays the raid icon texture on the left, the icon name as a label, and a text input field for entering comma-separated player names
- Text fields should be wide enough for several names with commas

**Actions Section**
- "Clear All Marks" button: clears the mark from every group member (party or raid) who currently has one, regardless of whether PRT assigned it. This is a one-shot action, not a toggle. In a raid, it requires leader/assistant permissions—if the player doesn't have permission, the button does nothing (silently). In a party, no permission check is needed.

### Settings Storage

Settings are stored per-profile under `PRT:GetSetting("autoMarking")`:

```
PRT.defaults.autoMarking = {
    enabled = true,
    marks = {
        [1] = "",   -- Star
        [2] = "",   -- Circle
        [3] = "",   -- Diamond
        [4] = "",   -- Triangle
        [5] = "",   -- Moon
        [6] = "",   -- Square
        [7] = "",   -- Cross
        [8] = "",   -- Skull
    },
}
```

Each `marks[n]` value is a string of comma-separated player names (e.g., `"Niv,Elsie,Backup"`). Whitespace around names should be trimmed during lookup, not on storage.

## Module Structure

The module should follow the existing pattern established by `DontRelease.lua` and `ReadyCheck.lua`:

- Local table on the `PRT` namespace (`PRT.AutoMarking = {}`)
- Defaults registered on `PRT.defaults`
- An `Initialize` function called from an `ADDON_LOADED` handler that starts the application timer
- Config tab registered via `PRT:RegisterTab`
- Listed in `PurplexityRaidTools.toc` as `Modules/AutoMarking.lua`

### Key APIs

- `SetRaidTargetIcon(unit, markIndex)` — applies a raid target icon (1–8) or clears it (0)
- `GetRaidTargetIndex(unit)` — returns the current mark on a unit, used to avoid redundant calls
- `GetNumGroupMembers()` — checks raid membership
- `GetRaidRosterInfo(i)` — iterates raid roster for name matching
- `UnitIsGroupLeader("player")` / `IsRaidLeader()` — checks leader status
- `UnitIsGroupAssistant("player")` / `IsRaidOfficer()` — checks assistant status
- `InCombatLockdown()` — checks combat state (alternative to tracking PLAYER_REGEN events)
- `IsInRaid()` — checks if in a raid group
- `IsInGroup()` — checks if in any group (party or raid)
