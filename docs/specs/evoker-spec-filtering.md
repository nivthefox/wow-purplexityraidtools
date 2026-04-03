---
status: draft
---

# Cooldown Roster: Spec Cache Staleness

## Problem

The spec cache (`specCache`) is populated via the inspect API but never refreshed unless a player leaves the group. If a player respecs, the cache holds their old spec indefinitely. This has been directly observed: Preservation Evoker cooldowns (Dream Flight, Rewind, Time Dilation) showing for Augmentation Evokers.

The filtering logic in `RebuildRoster` is correct—`spell.specId == nil or spell.specId == cachedSpec` does the right thing when the cache is accurate. The problem is upstream: the cache goes stale and there's no mechanism to detect it.

## Fix: Continuous Background Validation

Replace the current "inspect once, cache forever" model with a perpetual background validation loop.

### Background Rotation

Every 0.5 seconds (the existing ticker interval), inspect the next person in the roster. Compare the result against the cached spec for that player. If it matches, do nothing. If it doesn't, update the cache entry and rebuild the display.

When the loop reaches the end of the roster, it wraps back to the beginning. It never stops—as long as the player is in a group and out of combat, the rotation runs. In combat, it pauses (inspections can't run in combat). When combat ends, it resumes where it left off.

### Priority Inspects for New Joins

When `GROUP_ROSTER_UPDATE` fires and a new GUID appears with no cache entry, that player is queued for immediate inspection ahead of the background rotation. Once their spec is cached, they join the normal rotation like everyone else.

Priority inspects jump the queue—if the background rotation is waiting on its 0.5-second interval, a new join doesn't wait for that. But if an inspect is already in-flight (waiting on `INSPECT_READY`), the new join waits for it to finish before going next.

### GUID Check on `INSPECT_READY`

The `INSPECT_READY` event's first argument is the GUID of the inspected unit. `OnInspectReady` currently ignores this and uses the `inspectPending` unit variable. This is a race condition: if another addon triggers an inspect, the event fires for their target but the handler reads data as if it were for `inspectPending`.

Fix: verify that the GUID from the event matches `UnitGUID(inspectPending)`. If it doesn't match, ignore the event.

### Stale GUID Cleanup

`ScanRoster` already removes GUIDs from the cache when players leave the group. This behavior stays the same.

## What NOT to Change

- The `SPELL_DATA` table and its spec filtering logic are correct.
- The display update flow (`RebuildRoster` → `UpdateDisplay`) is correct—it just gets called when fresh data reveals a change.
- The inspection throttle (0.5-second intervals, one at a time) stays the same. The change is what gets fed into the queue, not how fast the queue processes.

## Documentation

Add comments in the spec ID block for Augmentation Evoker (1473) and Devastation Evoker (1467) alongside the existing Preservation (1468) entry.
