---
status: draft
---

# Ready Check: Buff Detection Always Returning False

## Problem

The ready check system whispers buff providers when it detects missing raid buffs, but it warns about ALL buffs even when they are visibly active on everyone. A previous fix (`ready-check-false-positives.md`) addressed range-based false positives by filtering out-of-range members via `UnitIsVisible`. That fix is in the current code and should stay. The problem persists for visible, in-range, buffed members.

## Root Cause Investigation

The `HasBuff` function uses `AuraUtil.ForEachAura` with `usePackedAura = true` and checks `auraData.spellId` against the spell ID in `RAID_BUFFS`. If this check never matches, every buff looks missing. Two likely causes:

### A. Spell ID Mismatch (Most Likely)

The spell ID used to *cast* a buff is often different from the spell ID of the *aura* it applies. `RAID_BUFFS` may contain cast spell IDs rather than aura spell IDs. If so, the check would never find a match.

**To verify:** In-game, inspect a buffed player's auras (using `/dump` or an aura-browsing addon) and compare the aura's spell ID against what's in `RAID_BUFFS`. If they differ, update `RAID_BUFFS` to use the aura spell IDs.

### B. API Behavior Change

`AuraUtil.ForEachAura` may have changed behavior in the current client. The callback might not fire, or `auraData.spellId` might not be populated as expected.

**To verify:** Add temporary debug logging inside the `HasBuff` callback that prints every aura it encounters for a single unit (e.g., only for `raid1` to avoid spam). If the callback never fires, the API approach is broken. If it fires but no spell IDs match the expected values, it's cause A.

## Research Findings

Research conducted by examining MRT's `RaidCheck.lua`, MRT's `ExCD2.lua`, and Blizzard's own UI source (`AuraUtil.lua`, `CompactUnitFrame.lua`, `BuffFrame.lua`).

### How MRT checks for buffs on other players

MRT does not use `AuraUtil.ForEachAura` at all. Instead, it calls `C_UnitAuras.GetAuraDataByIndex` directly in a simple counting loop: iterate from index 1 to 60, get aura data at each index, break when nil, check the spell ID against known values. This pattern appears throughout `RaidCheck.lua` for rune checking, flask checking, food checking, and raid buff checking.

MRT also checks `C_Secrets.ShouldAurasBeSecret()` before any aura reads and bails out if it returns true. This is a newer API restriction where certain content (like Plunderstorm or special events) hides aura data from addons.

### How Blizzard's own UI reads auras

Blizzard's `CompactUnitFrame.lua` (the raid frames) uses `AuraUtil.ForEachAura` with `batchCount = nil` and `usePackedAura = true`, which is the same approach PRT uses. The filter string is constructed with `AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)` which evaluates to `"HELPFUL"`.

The `AuraUtil.ForEachAura` implementation (in `AuraUtil.lua` lines 109-118) calls `C_UnitAuras.GetAuraSlots` to get slot IDs, then calls `C_UnitAuras.GetAuraDataBySlot` for each slot. This is a different code path from `GetAuraDataByIndex`. The slot-based approach uses a continuation token for batching.

Blizzard's `BuffFrame.lua` (the player buff bar) also uses the same `ForEachAura` pattern with `usePackedAura = true`.

### The field name is correct: spellId (lowercase d)

Confirmed in Blizzard's `AuraUtil.UnpackAuraData` (line 47 of `AuraUtil.lua`): the field is `auraData.spellId` with a lowercase `d`. PRT's code matches this. (Note: the API documentation Lua files use `spellID` with a capital D in their type annotations, but the actual runtime object uses lowercase. This is a known inconsistency in Blizzard's docs vs. implementation.)

### There is a simpler API: C_UnitAuras.GetAuraDataBySpellName

`C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)` returns an aura data table or nil if the aura isn't found. Blizzard's own `AuraUtil.FindAuraByName` wraps this function. It's marked `RequiresNonSecretAura = true`, meaning it won't work for private/hidden auras, but raid buffs are not private.

There is no `C_UnitAuras.GetAuraDataBySpellID` function. To check by spell ID, you either iterate with `GetAuraDataByIndex` or use `GetAuraDataBySpellName`.

### What is likely broken in PRT's HasBuff

PRT's `HasBuff` implementation looks correct at the API level. `AuraUtil.ForEachAura` with `usePackedAura = true` and `"HELPFUL"` filter is exactly what Blizzard uses in their own raid frames. The field name `auraData.spellId` is correct.

Given that the API approach is sound, the most likely cause remains **spell ID mismatch** (cause A from the original spec). The spell IDs in `RAID_BUFFS` need to be verified in-game against the actual aura spell IDs. This still requires in-game testing.

### Recommended fix

Replace the `ForEachAura` loop with a single `GetAuraDataBySpellName` call using the buff name. If it returns non-nil, the buff is present. This bypasses the spell ID question entirely—no ID mismatch possible. PRT is English-only, so localization sensitivity is a non-issue. `RAID_BUFFS` already has the buff names.

### Relevant source files

- `/home/kevin/projects/methodraidtools/RaidCheck.lua` lines 577-605 -- MRT's buff checking loop (runes example)
- `/home/kevin/projects/methodraidtools/RaidCheck.lua` lines 930-1000 -- MRT's raid buff checking
- `/home/kevin/projects/wow-ui-source/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` lines 13-54 -- data provider, UnpackAuraData, FindAuraByName
- `/home/kevin/projects/wow-ui-source/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` lines 84-118 -- ForEachAura implementation
- `/home/kevin/projects/wow-ui-source/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua` lines 1755-1763 -- Blizzard raid frame aura reading
- `/home/kevin/projects/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua` lines 148-199 -- GetAuraDataByIndex and GetAuraDataBySpellName documentation

## Fix Strategy

1. **Switch to `C_UnitAuras.GetAuraDataByIndex` loop** (MRT's pattern) or **`C_UnitAuras.GetAuraDataBySpellName`** (single-call, name-based). Either approach is proven to work. The name-based approach is simpler and avoids spell ID confusion entirely.

2. **Verify spell IDs in-game regardless.** Even if switching to name-based matching, the `RAID_BUFFS` spell IDs should be verified and corrected for any future code that might use them. Compare each entry against actual in-game aura spell IDs using `/dump C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")` etc.

3. **Add a `C_Secrets.ShouldAurasBeSecret()` guard** at the top of the buff-checking flow. MRT does this before every aura read. If auras are secret, skip the buff check entirely rather than producing false positives.

## What NOT to Change

- The overall flow (ready check fires → scan visible members → check buffs → whisper providers) is correct.
- The `UnitIsVisible` filtering from the previous fix is correct and should stay.
- The snarky/polite message system is unrelated.
- The soulstone check uses `AnyoneHasBuff` with the same `HasBuff` function. If `HasBuff` is broken, soulstone detection is also broken. Fixing `HasBuff` fixes both.
