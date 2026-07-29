# PurplexityRaidTools

A World of Warcraft addon providing raid management tools for the Purplexity guild. Open the config panel with `/prt` or `/purplexity`.

## Modules

### Don't Release
Prevents accidental spirit releases in raids. Adds a configurable delay before the release button becomes active, with an optional modifier key requirement. Can be enabled per content type (e.g., only in heroic/mythic raids).

### Ready Check
Monitors ready checks and whispers players who are missing raid buffs. Includes a rotation of snarky reminder messages per buff type (Arcane Intellect, Battle Shout, etc.). Also whispers dead players so they don't miss the check.

### Auto Invite
Handles raid invites through whisper keywords and guild rank mass-invites. Players can whisper a keyword (default: `inv`, `invite`, or `123`) to request an invite. Officers can mass-invite by guild rank via `/prt inv`. Includes auto-promote for designated players.

### Cooldown Roster
Displays available raid cooldowns based on current group composition. Categorizes abilities into defensives, externals, and movement cooldowns. Shows real-time usage tracking with status bars. Appears automatically in configured content types.

### Cooldown Tracker
Tracks the actual cooldown state of raid abilities in real time using combat log events. Detects spell casts, aura applications, and talent-based charge modifications. Feeds data to the Cooldown Roster for live availability display.

### Notes
Timed boss encounter reminders based on the format used by [wowutils](https://wowutils.com/viserio-cooldowns/planning). Write notes with phase-based timers that trigger on-screen popups, countdown alerts, text-to-speech callouts, and sound effects during boss fights. Notes are matched to encounters by encounter ID and difficulty. Supports tagging so reminders only show for relevant players (by name, class, role, group, or spell assignment).

## Communication

Modules can broadcast data to the raid using AceComm, with messages serialized via LibSerialize and compressed with LibDeflate.

## Slash Commands

| Command | Action |
|---|---|
| `/prt` | Toggle the config panel |
| `/purplexity` | Toggle the config panel |
| `/prt inv` | Mass-invite guild members by rank |

## Dependencies

Bundled libraries (no external dependencies):
- LibStub
- CallbackHandler-1.0
- AceComm-3.0 / ChatThrottleLib
- LibSerialize
- LibDeflate
- LibSharedMedia-3.0
