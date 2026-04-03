# Core Infrastructure Refactor

## Status: Review

## Problem

PRT's module infrastructure was built organically—each module copied the patterns of the previous one, and nobody went back to consolidate. The result is five independent `ADDON_LOADED` frames with no shared bootstrap, three different implementations of `EnsureSettingsTable`, four separate group-roster iteration patterns, and modules that register events at startup and never unregister them. This works fine at four modules. It will not age well.

## Goals

1. **Centralized module lifecycle.** One place to register modules, one initialization path, one enable/disable mechanism.
2. **Single authoritative defaults path.** Defaults declared once per module, merged once into the profile. No more `EnsureSettingsTable`.
3. **Shared group iteration.** One utility that handles raid, party, and solo contexts. All modules use it.
4. **Event hygiene.** Modules register events when they become relevant and unregister when they are not.
5. **AutoInvite dirty-check.** Stop rebuilding the roster from scratch on every `GROUP_ROSTER_UPDATE`.

## Non-Goals

- Combat deferral patterns (no current feature needs them).
- Secret value handling via `issecretvalue()` (no current feature runs during encounters).
- Changing the config/tab registration system. `PRT:RegisterTab()` works fine.
- Changing how DontRelease hooks `StaticPopupDialogs`. Hooks are not events; they don't need lifecycle management.

---

## Design

### 1. Module Registry

**What changes:** Core owns module registration and initialization. Modules stop creating their own `ADDON_LOADED` frames.

**Registration.** Each module calls `PRT:RegisterModule(name, moduleTable)` at file scope. This stores the module in an ordered list. Registration must happen at file load time (before `ADDON_LOADED` fires), which is guaranteed because the TOC loads module files before the event fires.

```
-- In Modules/ReadyCheck.lua, at file scope:
local ReadyCheck = {}
PRT.ReadyCheck = ReadyCheck
PRT:RegisterModule("readyCheck", ReadyCheck)
```

**Initialization.** Core creates a single `ADDON_LOADED` frame. When it fires:

1. `PRT:InitializeDB()` runs (profile system, same as today).
2. `PRT:MergeDefaults()` runs (see section 2).
3. For each registered module, in TOC order: `module:Initialize()` is called.
4. For each registered module: core evaluates whether the module should be enabled (see section 3).

**Module table contract.** A registered module may define any of these methods:

| Method | Required | Called when |
|---|---|---|
| `Initialize()` | No | Once, during `ADDON_LOADED`. For one-time setup that does not depend on being in a group (e.g., DontRelease's hook installation). |
| `IsActivatable()` | No | During lifecycle evaluation. Returns `true` if the module's context is relevant. Should only check context (group state, zone, etc.), not settings—the framework checks settings separately. |
| `OnEnable()` | No | Module transitions from inactive to active. Register events here. |
| `OnDisable()` | No | Module transitions from active to inactive. Unregister events, cancel timers here. |
| `GetEnabledSetting()` | No | Returns `true` if the module considers itself enabled based on its settings. If not defined, the framework checks for an `enabled` key in the module's settings table. Override this for modules with non-standard enabled logic (e.g., AutoInvite, which is enabled if either sub-feature is on). |

Modules that define neither `OnEnable` nor `OnDisable` are "always on" after `Initialize`—this is fine for DontRelease, which is hook-based.

### 2. Defaults Consolidation

**What changes:** One deep-merge replaces `ImportDefaultsToProfile` and all `EnsureSettingsTable` functions.

**How it works.** `PRT:MergeDefaults()` performs a recursive deep-merge of `PRT.defaults` into the current profile. For each key in the defaults tree:

- If the key is absent from the profile, it is copied in (deep-copied if it is a table).
- If the key exists in both and both values are tables, recurse.
- If the key exists in the profile, the profile value wins (even if the types differ).

This runs once during initialization (after `InitializeDB`) and again whenever the player switches profiles.

**What gets removed:**

- `PRT:ImportDefaultsToProfile()` — replaced by `MergeDefaults`.
- `EnsureSettingsTable()` in DontRelease, ReadyCheck, AutoInvite, and CooldownRoster — no longer needed.
- `GetReadyCheckSetting()` in ReadyCheck — no longer needed; per-field fallback is handled by the merge.

**`PRT:GetSetting(key)` behavior.** After the merge, the profile is always complete. `GetSetting` can simply return the profile value without a fallback check. However, keeping the fallback as a safety net is harmless and defensive:

```
function PRT:GetSetting(key)
    local profile = self.Profiles:GetCurrent()
    if profile[key] ~= nil then
        return profile[key]
    end
    return self.defaults[key]
end
```

The difference is that after `MergeDefaults`, the fallback should never be reached for known keys.

**Migration concern.** Existing profiles may have partial settings tables (e.g., a `dontRelease` table that's missing keys added in later versions). The deep-merge handles this correctly—it fills in missing sub-keys without overwriting existing ones. This is the whole point.

### 3. Module Lifecycle (Enable/Disable)

**What changes:** Modules declare when they should be active. Core manages transitions.

**Enabled check (framework-level).** Before evaluating any context conditions, core checks the module's `enabled` setting in the profile. If the module has an `enabled` key in its settings table and it is `false`, the module is not activated regardless of context. This check lives in the framework so individual modules do not need to duplicate it.

**Activation conditions.** Each module may additionally define an `IsActivatable()` method that returns `true` when the module's context is relevant (e.g., "player is in a raid"). If a module does not define `IsActivatable`, it is activatable whenever it is enabled. `IsActivatable` should only check context, not settings—the framework handles the settings check.

Examples:

| Module | Enabled setting | `IsActivatable()` returns true when... |
|---|---|---|
| DontRelease | `dontRelease.enabled` | *(not defined—always activatable when enabled, hook-based)* |
| ReadyCheck | `readyCheck.enabled` | Player is in a raid (`IsInRaid()`) |
| AutoInvite | `autoInvite.whisperInviteEnabled` or `autoInvite.promoteEnabled` | *(not defined—always activatable when enabled)* |
| CooldownRoster | `cooldownRoster.enabled` | Player is in a group (`IsInGroup()` or `IsInRaid()`) |

**Note on AutoInvite's enabled check.** AutoInvite has two independent sub-features (whisper invite and auto-promote) with separate toggles. The framework-level check should treat the module as enabled if *either* sub-feature is enabled. The module itself handles which sub-features are active internally.

**Evaluation triggers.** Core listens for a small set of lifecycle events and re-evaluates module activation when they fire:

- `GROUP_ROSTER_UPDATE` — group composition changed.
- `PLAYER_ENTERING_WORLD` — login, reload, or instance transition.
- `ZONE_CHANGED_NEW_AREA` — zone change.

Additionally, `PRT:ApplySettings()` triggers re-evaluation, so toggling a module's enabled setting in the config UI takes effect immediately.

**Transition mechanics.** When core evaluates a module:

1. Check the module's enabled state: call `module:GetEnabledSetting()` if defined, otherwise check for an `enabled` key in the module's settings table (`PRT:GetSetting(moduleName).enabled`). If the result is `false`, treat as not activatable.
2. If enabled, call `module:IsActivatable()`. If not defined, treat as `true`.
3. Check `module.active` (internal state flag managed by core).
4. If activatable and not currently active: set `module.active = true`, call `module:OnEnable()`.
5. If not activatable and currently active: call `module:OnDisable()`, set `module.active = false`.

**Event frame.** Core creates one event frame per module at registration time. The module receives a reference to its frame and uses it in `OnEnable`/`OnDisable` to register/unregister events. This replaces the module creating its own event frame in `Initialize()`.

```
-- In OnEnable:
function ReadyCheck:OnEnable()
    self.eventFrame:RegisterEvent("READY_CHECK")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "READY_CHECK" then
            self:OnReadyCheck(...)
        end
    end)
end

-- In OnDisable:
function ReadyCheck:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
end
```

### 4. Shared Group Iteration

**What changes:** One group iterator on the core namespace, used by all modules.

**`PRT:IterateGroup()`.** Returns an iterator that yields unit IDs for every member of the current group. Handles raid, party, and solo contexts:

- **Raid:** Yields `"raid1"` through `"raidN"` where N is `GetNumGroupMembers()`.
- **Party:** Yields `"party1"` through `"partyN"` (where N is `GetNumGroupMembers() - 1`), then `"player"`.
- **Solo:** Yields `"player"`.

This is CooldownRoster's `GetGroupUnitIterator` extracted and promoted to the core namespace, with the solo case added.

**Module migration.** Each module's roster iteration code changes to use `PRT:IterateGroup()`:

- **ReadyCheck:** `GetPlayersByClass`, `GetAllRaidMembers`, and `GetHealers` switch from `GetRaidRosterInfo(i)` loops to iterating unit IDs and using `UnitClass(unit)`, `UnitGroupRolesAssigned(unit)`, `UnitIsConnected(unit)`, etc.
- **AutoInvite:** `IsPlayerInGroup` switches from its dual raid/party check to `PRT:IterateGroup()` with `UnitName(unit)` comparisons. `OnGroupRosterUpdate`'s promotion logic switches similarly.
- **CooldownRoster:** Replaces its local `GetGroupUnitIterator` with `PRT:IterateGroup()`.

**What about `GetRaidRosterInfo`?** Some call sites use data from `GetRaidRosterInfo` that is not directly available from unit APIs (specifically, the raid roster index for `SetRaidSubgroup` or similar). If any call site genuinely needs `GetRaidRosterInfo` data, it can keep its own loop. The shared iterator is for the common case: "give me each group member's unit ID so I can query them."

### 5. AutoInvite Dirty-Check

**What changes:** `OnGroupRosterUpdate` stops rebuilding `knownMembers` from scratch every time.

**Current behavior.** Every `GROUP_ROSTER_UPDATE`:
1. Rebuild `knownMembers` by iterating the full roster.
2. Check each member for promotion eligibility.

**New behavior.** On `GROUP_ROSTER_UPDATE`:
1. Build a new roster snapshot (set of names).
2. Compare against the previous snapshot.
3. Only process members who are *new* since the last snapshot (joined the group).
4. Store the new snapshot as the previous snapshot.

Promotion checks only run for newly joined members. Members who were already in the group and triggered a roster update (role change, subgroup move, etc.) are not re-checked.

---

## Build Sequence

These changes layer on each other. The recommended implementation order:

### Phase 1: Module Registry + Centralized Init
- Add `PRT:RegisterModule()` and the module list to core.
- Replace the five `ADDON_LOADED` frames with one in core that calls each module's `Initialize()`.
- All modules switch to `PRT:RegisterModule()` and remove their init frames.
- **Behavior is identical after this phase.** Modules still register their own runtime events in `Initialize()`. This is purely structural.

### Phase 2: Defaults Consolidation
- Implement `PRT:MergeDefaults()` as a recursive deep-merge.
- Call it from `InitializeDB()` and from profile switching.
- Remove `ImportDefaultsToProfile()`.
- Remove all `EnsureSettingsTable()` functions. Config UI code that called `EnsureSettingsTable()` to get the settings table should call `PRT:GetSetting(moduleName)` instead.
- Remove `GetReadyCheckSetting()` in ReadyCheck.
- **Test carefully:** Verify that existing profiles load correctly with all sub-keys present after merge. Verify that new profiles get all defaults. Verify that switching profiles triggers a merge.

### Phase 3: Shared Group Iteration
- Add `PRT:IterateGroup()` to core.
- Migrate CooldownRoster first (simplest—it already uses the same pattern).
- Migrate ReadyCheck's three functions.
- Migrate AutoInvite's `IsPlayerInGroup` and `OnGroupRosterUpdate`.
- Remove all module-local group iteration code.
- ReadyCheck remains raid-only: its functions should use `PRT:IterateGroup()` but guard with an `IsInRaid()` check, returning empty results in non-raid contexts.
- **Test:** Verify behavior in raid, party, and solo contexts.

### Phase 4: Module Lifecycle
- Add `IsActivatable`, `OnEnable`, `OnDisable` support to the module registry.
- Core creates one event frame per module at registration time.
- Core listens for lifecycle events and evaluates module activation.
- Migrate AutoInvite: move event registration from `Initialize()` to `OnEnable()`, add `OnDisable()`.
- Migrate CooldownRoster: move event registration and ticker from `Initialize()` to `OnEnable()`, add `OnDisable()` that cancels the ticker (`ticker:Cancel()`) and unregisters events.
- Migrate ReadyCheck: move `READY_CHECK` registration to `OnEnable()`.
- DontRelease: no changes needed (hook-based, no lifecycle events).
- **Test:** Verify modules enable/disable correctly when joining/leaving groups. Verify AutoInvite stops listening for whispers when disabled. Verify CooldownRoster's ticker stops when solo.

### Phase 5: AutoInvite Dirty-Check
- Refactor `OnGroupRosterUpdate` to compare snapshots.
- **Test:** Verify promotion still fires for new members. Verify it does not re-fire for existing members on role/subgroup changes.

---

## Resolved Questions

1. **ReadyCheck in parties.** ReadyCheck remains raid-only. Migrating to `PRT:IterateGroup()` adds an explicit `IsInRaid()` guard so behavior does not change.

2. **AutoInvite activation condition.** "Enabled in settings" is sufficient. If the user turned it on, it listens—even solo, since someone might whisper an invite keyword.

3. **CooldownRoster ticker.** `OnDisable` cancels the ticker; `OnEnable` restarts it. Clean lifecycle, no wasted work when solo.

4. **Profile switching.** Only happens from the config screen, not during gameplay. `MergeDefaults` and module re-evaluation run on profile switch but do not need to handle combat lockdown or mid-encounter transitions.
