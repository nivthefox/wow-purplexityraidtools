# PurplexityRaidTools

A World of Warcraft addon providing raid management tools for the Purplexity guild. Open the config panel with `/prt` or `/purplexity`.

## Modules

### Don't Release

Prevents accidental spirit releases in raids. Adds a configurable delay before the release button becomes active, with an optional modifier key requirement. Can be enabled per content type (e.g., only in heroic/mythic raids).

### Ready Screen

Shows the current group's readiness in one table, including spec, role, ready-check response, raid-buff coverage, soulstone status, PRT version, food, weapon enhancement, flask, augment rune, Vantus rune, and durability. It opens automatically during ready checks and can be opened manually with `/prt ready`.

### Ready Check

During raid ready checks, whispers missing raid-buff providers, warlocks when no healer has a Soulstone, and dead players. Raid leaders can also notify guild members or the full raid when PRT is missing or older than the leader's copy. Reminder messages can be polite or snarky.

### Auto Invite

Handles raid invites through whisper keywords and guild rank mass-invites. Players can whisper a keyword (default: `inv`, `invite`, or `123`) to request an invite. Officers can mass-invite by guild rank via `/prt inv`. Includes auto-promote for designated players.

### Cooldown Roster

Shows the defensive, external, and movement cooldowns available from the current group composition. It uses inspected specializations and talents to filter abilities. It does not track other players' live cooldown usage because Midnight's aura secrecy prevents that data from being read reliably.

### Battle Res Counter

Shows the group's current battle resurrection charges and charge timer in a movable widget. It can also add a battle resurrection summary to the Cooldown Roster.

### Combat Timer

Shows elapsed fight time in a movable widget. It can run only during boss encounters or during all combat.

### Notes

Creates timed encounter notes in a visual editor or from imported [NSRT-style text](https://wowutils.com/viserio-cooldowns/planning). Notes can use phase timers, on-screen popups, countdown alerts, text-to-speech callouts, and sound effects. Tags target reminders by player, class, role, raid subgroup, or spell assignment. Raid leaders and assistants can send notes to the raid, while each player can keep personal annotations.

### Attendance

Records attendance automatically from pull countdowns in configured content types. Reports combine a raider's characters under the roster and distinguish present, late, absent, and missing attendance. Records can be corrected manually, retained for a configurable period, and synced within the raid.

### Roster

Groups a raider's characters under one nickname and records observed class, main specialization, and off-specialization tags. Officers can add players manually, import characters from attendance records, drag characters between players, and sync the roster within the raid. The optional Roster Nicknames setting shows those nicknames on supported Blizzard frames, NivUI, EllesmereUI, Danders Frames, and Grid2. EllesmereUI Unit Frames also requires its Show Nicknames display option. ElvUI users can place `[prt-roster-nickname]` or a shortened `[prt-roster-nickname:1]` through `[prt-roster-nickname:12]` tag in their unit-frame text formats.

### Profiles

Creates, clones, renames, deletes, and switches between addon configuration profiles.

## Communication

Modules can broadcast data to the raid using AceComm, with messages serialized via LibSerialize and compressed with LibDeflate.

## Slash Commands

| Command | Action |
|---|---|
| `/prt` | Toggle the config panel |
| `/purplexity` | Toggle the config panel |
| `/prt inv` or `/prt invite` | Mass-invite guild members by rank |
| `/prt ready` | Open the Raid Audit for the current group |

## Dependencies

PRT bundles its required libraries:

- LibStub
- CallbackHandler-1.0
- AceComm-3.0 / ChatThrottleLib
- LibSerialize
- LibDeflate
- LibSharedMedia-3.0

BigWigs or Deadly Boss Mods is required for Notes reminders after phase 1. NivUI, ElvUI, EllesmereUI, Danders Frames, and Grid2 integrations are optional; Blizzard roster nicknames work without them. The rest of PRT does not require an external addon.
