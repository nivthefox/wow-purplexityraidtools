---
status: draft
---

# Snarky Message Toggle

## What and Why

The Ready Check system currently whispers snarky, class-specific messages to players who are missing buffs. Some raid leaders may prefer a gentler tone—either because they're in a PUG, running with newer players, or just not in the mood.

This adds a single checkbox to toggle between snarky and polite messages. When snarky mode is off, every buff reminder uses a simple, neutral template instead of the randomized snarky pool.

## Behavior

### New Setting

- **Key:** `snarkyMessages` in the `readyCheck` settings table
- **Default:** `true` (current behavior preserved)
- **UI:** A checkbox labeled "Use snarky messages" placed between the master "Enable Ready Check Features" toggle and the individual buff checkboxes

### Message Selection

When `snarkyMessages` is **enabled** (default), the system works exactly as it does today: each buff and the soulstone check pick a random message from their respective snarky message pools.

When `snarkyMessages` is **disabled**, the system skips the snarky pools entirely and sends a polite message built from a simple template:

- Buff template: `"It looks like {buffName} may be missing. Please cast it, just in case."`
- Soulstone template: `"It looks like no healer has a Soulstone. Please cast it on one, just in case."`

### Where the Branch Happens

`NotifyPlayers` currently takes a `messages` array and picks randomly. The change is upstream of that: the caller decides which messages to pass based on the setting. If snarky mode is off, it passes a single-element table containing the polite message instead of the snarky pool.

No changes to `NotifyPlayers`, `GetRandomMessage`, or `SendWhisper`.

## Edge Cases

- **Setting changed mid-raid:** Takes effect on the next ready check. No in-flight concerns since messages are composed and sent synchronously within a single event handler.
- **Profile switching:** The setting is per-profile like everything else. A profile without the key falls back to `true` via the existing default mechanism.

## Config UI

The checkbox follows existing patterns: same component (`PRT.Components.GetCheckbox`), same layout flow, same `EnsureSettingsTable` / `OnShow` refresh pattern. It should be added to the `OnShow` refresh handler alongside the other checkboxes.

## Validation

| What to Check | Expected Result |
|---|---|
| Snarky enabled, buff missing | Random snarky message whispered (unchanged behavior) |
| Snarky disabled, buff missing | Polite template message whispered |
| Snarky disabled, soulstone missing | Polite soulstone template whispered |
| Fresh profile (no `snarkyMessages` key) | Defaults to snarky (backward compatible) |
| Toggle checkbox, reopen config | Checkbox reflects saved state |
