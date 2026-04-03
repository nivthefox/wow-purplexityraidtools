---
status: draft
---

# Cooldown Roster: Talent-Based Cooldown Filtering

## Problem

Some cooldowns in `SPELL_DATA` are talent-gated—a player of the right class and spec might not actually have them if they haven't talented into them. The roster currently assumes that class + spec = all cooldowns for that spec. This produces inaccurate displays.

## Behavior

After inspecting a player's spec, also query their talent loadout. For each spell in `SPELL_DATA`, add an optional `talentId` field. When `talentId` is present, the spell only appears in the roster if the player has that talent active. When `talentId` is absent, the spell is treated as baseline (current behavior).

### Integration with Background Validation

The continuous inspection loop (from the spec cache staleness fix) already re-inspects every player on rotation. Talent data should be read in the same `INSPECT_READY` callback that reads spec data. Cache the talent state alongside the spec, and compare both when validating—if either changed, update the cache and rebuild.

### Fallback

If talent inspection data isn't available for a player (API failure, timeout, etc.), fall back to the current behavior: show based on class + spec only. Don't hide cooldowns because talent data is unavailable.

## Research Findings

Research conducted by examining MRT's `Inspect.lua` (the inspect module of Method Raid Tools), which has a battle-tested implementation of talent inspection for raid cooldown tracking.

### Which APIs return talent data for an inspected player?

The retail (Dragonflight+) talent system uses the `C_Traits` API family, not the old `C_Talents` or `GetTalentInfo` functions. MRT reads talents inside the `INSPECT_READY` handler using this sequence:

1. **Get the inspect config ID:** `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID` (which is the constant `-1`). This is a magic config ID that tells the `C_Traits` API to read from the currently-inspected player's talent data rather than your own.

2. **Get the config info and tree:** `C_Traits.GetConfigInfo(activeConfig)` returns a config object with a `treeIDs` array. The first entry (`config.treeIDs[1]`) is the talent tree ID.

3. **Get all nodes in the tree:** `C_Traits.GetTreeNodes(treeID)` returns an array of node IDs.

4. **For each node, read its state:** `C_Traits.GetNodeInfo(activeConfig, nodeID)` returns a node info table. The key fields are:
   - `node.ID` -- the node ID (0 means invalid)
   - `node.activeEntry` -- a table with `entryID` if the node is selected
   - `node.currentRank` -- how many points are allocated (0 = not talented)
   - `node.maxRanks` -- maximum ranks for multi-rank talents
   - `node.subTreeID` -- non-nil for hero talent nodes
   - `node.subTreeActive` -- whether this hero talent subtree is the active one
   - `node.type` -- check against `Enum.TraitNodeType.SubTreeSelection` to skip subtree choice nodes

5. **Resolve each entry to a spell ID:** `C_Traits.GetEntryInfo(activeConfig, entryID)` returns a table with `definitionID`. Then `C_Traits.GetDefinitionInfo(definitionID)` returns a table with `spellID`.

The check for "is this talent active" is: `node.currentRank > 0` and (if it's a hero talent) `node.subTreeActive` is true.

### Is talent data available in the same INSPECT_READY callback?

Yes. MRT reads talents directly inside its `INSPECT_READY` handler (line 889 of `Inspect.lua`). The same callback that provides spec data via `GetInspectSpecialization(unit)` also makes the `C_Traits` inspect data available. There is no separate event or additional query needed.

### What does the data flow look like?

Inside the `INSPECT_READY` handler, after reading the spec (which PRT already does):

1. Get the talent tree config using the inspect magic constant (-1) as the config ID.
2. Get all node IDs from the talent tree.
3. For each node, check whether it's active (current rank > 0, and if it's a hero talent, its subtree is the active one).
4. For active nodes, resolve the entry to a definition, then to a spell ID.
5. Skip subtree selection nodes (these are the hero talent choice nodes, not actual talents).

The result is a set of spell IDs representing every talent the inspected player has active.

### How PRT should use this

PRT's approach can be much simpler than MRT's since we only care about a small set of known talent-gated cooldowns. Rather than walking every node:

1. In the `INSPECT_READY` handler (after reading spec), run the `C_Traits` loop above.
2. Collect the set of active spell IDs into a table keyed by player name.
3. For each spell in `SPELL_DATA` that has a `talentId` field, check whether that spell ID appears in the player's active talents.

The `talentId` field on `SPELL_DATA` entries should be the `spellID` from `C_Traits.GetDefinitionInfo`, not a node ID or entry ID. The spell ID is what MRT matches against, and it's the most stable identifier across patches.

### Relevant source files

- `/home/kevin/projects/methodraidtools/Inspect.lua` lines 889-1144 -- the full `INSPECT_READY` handler including talent reading
- `/home/kevin/projects/methodraidtools/Inspect.lua` lines 983-1136 -- the retail `C_Traits` talent inspection path specifically
- `/home/kevin/projects/methodraidtools/ExCD2.lua` -- the cooldown tracker module that consumes the talent data

## Scope

Only cooldowns that are talent-dependent need `talentId` entries. Which specific cooldowns those are should be determined during implementation by checking the current talent trees. This is game-knowledge work—the spec doesn't enumerate them.

## What NOT to Change

- The display logic doesn't change; it just receives a more accurately filtered list from `RebuildRoster`.
- Baseline cooldowns (no `talentId` field) work exactly as they do now.
- The inspection queue and throttling are unchanged.
