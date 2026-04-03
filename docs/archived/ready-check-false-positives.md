# Ready Check: Fix False Positive Buff Detection

## Problem

The ready check buff detection whispers raid buff providers (mages, priests, etc.) when it thinks a buff is missing, but it's producing false positives even when everyone is alive and buffed. The suspected cause is range: `AuraUtil.ForEachAura` returns no aura data for units the client can't see, so those units look unbuffed.

The current check uses `EveryoneHasBuff`, which iterates every online raid member. If even one member returns empty aura data, the check fails and all providers for that class get whispered. In a 20-person raid, that's 20 chances for one unreadable unit to trigger a false alarm.

## Changes

All changes are in `Modules/ReadyCheck.lua`.

### 1. Filter unreadable members out of `GetAllRaidMembers`

Add a `UnitIsVisible(unit)` check to the existing filter in `GetAllRaidMembers` (line 159). This function already filters for `online`; add visibility as an additional condition. If the client can't see a unit's model, it can't read their aura data either, and casting a raid buff wouldn't reach them anyway.

### 2. Remove the existing debug code in `HasBuff`

Lines 189-191 print every aura on `raid1` when checking for Arcane Intellect (spell 1458). This is leftover from earlier debugging and should be removed. The replacement debugging (below) is more useful.

### 3. Add diagnostic logging to `OnReadyCheck`

When a buff is detected as missing, print a single debug line that includes:

- The buff name
- How many members were checked vs total raid size (from `GetNumGroupMembers()`)
- The names of members who are missing the buff
- The names of any members who were skipped due to `UnitIsVisible` being false

This should be enough for Niv to confirm whether the false positives are range-related or something else. Format it as a single `print()` call per missing buff so it doesn't flood chat.

To get the skip count, `GetAllRaidMembers` will need to also track how many members it filtered out, or the caller will need to compare the member count against `GetNumGroupMembers()`. Either approach works; comparing counts is simpler.

To get the names of members who failed the check, the buff-check loop in `OnReadyCheck` (line 263) will need to identify which specific members are missing the buff rather than just getting a boolean from `EveryoneHasBuff`. Consider inlining or reworking that check so you can collect the names.

## What NOT to Change

- The notification logic (`NotifyPlayers`) is correct. It already whispers all members of the responsible class, each with a random message.
- The `HasBuff` implementation using `AuraUtil.ForEachAura` with `usePackedAura = true` is correct per Blizzard's source. Don't change the API approach.
- The `AnyoneHasBuff` function used for soulstone checks is unrelated and should be left alone.
- Don't add a fallback (like sending a raid message if whispers fail). That pattern was intentionally removed.
