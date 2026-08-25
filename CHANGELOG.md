# Changelog

All notable changes to PurplexityRaidTools will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.3.1] - 2026-08-24

### Added

- Notes boss ability timelines now include additional mechanics for Vashnik the Malignant and The Coiled Altar, plus Apex Predator for Sszorak.

### Changed

- The Notes boss picker now groups encounters by raid and orders them to match the Encounter Journal.

## [1.3.0] - 2026-08-24

### Added

- The Notes editor now shows boss ability timelines alongside assignments.
- Roster Nicknames can now replace character names in Grid2.

### Changed

- Notes now use encounter-specific phases for supported fights.
- Notes assignments now offer current group members while grouped and main-spec roster characters while solo, including their relevant abilities, class colors, and spell icons.
- Raid-leader note editing now stays focused on assignment content, while personal annotations use searchable sounds, explicit TTS modes, and validated lead-time, cooldown, and countdown fields.

### Fixed

- Editing or deleting a personal annotation now updates the saved annotation instead of duplicating or losing it.

## [1.2.2] - 2026-08-18

### Added

- Roster Nicknames can now replace character names in EllesmereUI and Danders Frames.

## [1.2.1] - 2026-08-18

### Fixed

- Roster Nicknames now replace names on Blizzard's standard party frames.

## [1.2.0] - 2026-08-18

### Added

- Roster Nicknames can replace character names on supported Blizzard frames and through NivUI. ElvUI roster-nickname tags are available for custom unit-frame text.

### Changed

- Roster nicknames are limited to 12 characters, and roster changes or profile switches are blocked during combat.

## [1.1.4] - 2026-08-09

### Fixed

- Attendance expiration checks no longer cause an error when the addon loads.
- Auto-Invite now safely ignores whispers that WoW marks as restricted.

## [1.1.3] - 2026-08-08

### Fixed

- Group inspection now skips offline, out-of-range, and otherwise unavailable members.

## [1.1.2] - 2026-08-08

### Added

- Ready Check can now whisper guild members or the full raid when PurplexityRaidTools is missing or outdated.
- Attendance settings now let officers choose which content types create attendance records, defaulting to raid instances only.

### Fixed

- Pull countdowns in Mythic+ dungeons no longer create attendance records by default.
- Ready Screen now receives weapon enhancement and durability reports when opened by a non-leader.

## [1.1.1] - 2026-08-07

### Added

- Ready Screen consumable and equipment checks for food, weapon enhancements, flasks, runes, and durability.

## [1.1.0] - 2026-08-07

### Added

- Combat Timer widget that shows elapsed fight duration as a small, movable overlay. Supports encounter-only mode (boss fights) and all-combat mode (any engagement).
- Attendance Tracking module that automatically records raid attendance based on pull countdowns, with per-character status tracking, configurable rollover hour, and record syncing between raiders.
- Roster tab where officers group a raider's alts under one nickname with observed class, main spec, and off-spec tags. Characters can be dragged between roster members to reassign them. Rosters sync via addon comms and can optionally auto-request from the raid leader on ready check.

### Changed

- Cooldown Roster, Battle Res Counter, and Combat Timer settings are now grouped under a single "Combat Tools" sidebar entry with Cooldowns, Battle Res, and Timer sub-tabs.

## [1.0.1] - 2026-08-06

### Fixed

- Group member specialization detection no longer errors on clients where the namespaced inspect API is unavailable.

## [1.0.0] - 2026-08-05

### Added

- Battle Res Counter with a standalone draggable icon widget (cooldown sweep, charge count, accrual timer) and a summary row at the bottom of the Cooldown Roster's Externals category. Active in any group.
- Addon Detection that identifies which group members are also running PRT and what version they have, surfaced on GroupInspect's member data.
- Ready Screen that displays a table of group members with their spec, role, PRT version, ready check responses, raid buff coverage, and soulstone status. Works in any group size, polls live during active ready checks, and detects disconnects in real time.

### Changed

- Cooldown Tracker has been removed. Patch 12.1's aura secrecy makes tracking other players' cooldown usage impossible; the Cooldown Roster still shows available cooldowns but no longer displays live usage status bars.
- Now compatible with both Patch 12.0 and Patch 12.1.

### Fixed

- Note broadcast and clear messages received during combat are now silently dropped.
- Group roster now refreshes immediately on /reload instead of showing empty data until the next scan cycle.
- Group members who reconnect now have their spec and version detected immediately instead of waiting up to 60 seconds.

## [1.0.0-beta-2] - 2026-07-30

### Added

- **Visual Note Editor** with a vertical timeline that displays reminders as blocks positioned by phase and time, replacing the raw text modal for day-to-day editing.
  - Edit mode for raid leaders to add, modify, and delete reminders through a structured form (who, ability, time, phase) instead of hand-editing syntax.
  - Annotate mode for any raider to customize how existing reminders alert them (display type, sound, TTS, countdown) and to add personal reminders that only they see.
  - Ability picker that suggests spells based on the target's spec and talents, with free-text fallback.
  - Raw text import remains available for pasting notes from external tools.
  - Freeform comment lines from the note text appear as labeled separator bars on the timeline.
- **Note self-activation** for raiders: an Activate button lets non-leaders activate a note for themselves when the raid leader hasn't set one. The raid leader's broadcast always takes priority.

### Changed

- Notes without an EncounterID now apply to any encounter when activated, instead of silently doing nothing.
- Active note is automatically cleared when a boss is killed; wipes leave it active for the next pull.
- Note serialization now emits reminders in chronological order (grouped by phase, sorted by time) so the note frame display matches the visual editor's layout.
- Notes config button bar reorganized: New, Edit, Annotate, and Delete are left-aligned; Send/Activate, Clear, Show/Hide, and Test are right-aligned. Show/Hide label updates to reflect frame visibility.
- Test Popups button moved to the Popups settings tab.

## [1.0.0-beta-1] - 2026-07-28

### Added

- **Cooldown Tracker** module that monitors raid cooldown usage in real time via combat log events, feeding live availability data to the Cooldown Roster.
  - Tracks spell casts, aura applications, and talent-based charge modifications.
  - Cooldown Roster now shows status bars for active cooldowns and remaining time.
- Ready Check now whispers dead players so they don't miss the check.
- Releases are now automatically published to CurseForge, Wago, and WoWInterface when a GitHub release is created.

### Changed

- Config UI reworked from a top tab row to a left sidebar layout.
  - Sidebar tabs are kept in alphabetical order; Profiles is pinned to the bottom with a separator.
  - Auto-Invite and Notes tabs now use sub-tabs to organize their settings (e.g., Whispers / Guild / Auto Promote).
- Config sliders and inputs are capped at a responsive max width so the UI doesn't stretch awkwardly on wide frames.
- Config labels use a fixed-width column for consistent alignment.

### Fixed

- Gear tooltips no longer break when the Cooldown Roster inspects group members in the background.
- Auto-Invite now correctly upgrades a party to a raid when mass-inviting guild members.
- Mouse wheel scrolling removed from config sliders to prevent accidental value changes.

## [1.0.0-alpha-4] - 2026-07-18

### Added

- **Test Note** button in the Notes config tab that runs the active note's full timer without requiring a boss encounter, for validating notes on combat dummies or anywhere else.
  - Toggle button (Test Note / Stop Test) centered alongside the existing Test Popups button.
  - Auto-stops after the last reminder in the note fires.
  - A real encounter starting will supersede a running test.

### Changed

- Countdown audio now uses BigWigs Amy voice pack sound files instead of WoW's TTS engine.
- Notes frame countdown display uses ceiling instead of floor, so the displayed time stays in sync with popup timers and countdown audio.
- Sound resolution now matches NSRT behavior with case-insensitive LibSharedMedia lookups and color-code stripping.

### Fixed

- Countdown audio timing synced with visual display: sound N now fires when remaining time reaches N seconds, not one second late.
- TTS callouts (`tts:` field) now actually speak instead of producing silent clicks, caused by the `C_VoiceChat.SpeakText` API signature change in Patch 12.0.0 that removed the destination parameter.

## [1.0.0-alpha-3] - 2026-07-18

### Added

- **Notes** module for timed boss note reminders:
  - Paste an NSRT-style note (one encounter per note) into the note editor and PRT parses it into a live assignment sheet.
  - Notes are managed as a named list with New/Edit/Delete; invalid notes are rejected at save with a clear error.
  - Static note frame with per-reminder countdowns, class-colored names, raid-target icons, and configurable fonts, colors, and hide behavior.
  - Timed popups in four styles (Icon, Bar, Text, Circle) with individually movable anchors, stacking, and scale.
  - Audio alerts, TTS callouts, and spoken countdowns per reminder.
  - Reminders filter to your role, spec, class, group, or name via note tags.
  - Phase-aware timing that tracks BigWigs and DBM stage callbacks.
  - Send broadcasts the selected note to the raid and activates it for everyone (raid leader or assistant only); Clear deactivates it raid-wide. Solo, Send activates the note for yourself for validation. Sending is blocked during combat.

### Changed

- Config window widened from 500px to 750px to fit the growing tab row.
- **Profiles** extracted into their own config tab with dedicated create, copy, delete, and rename UI.

### Fixed

- Popup movers no longer appear on reload when no popups are active.

## [1.0.0-alpha-2] - 2026-04-03

### Added

- **Cooldown Roster** module that displays raid defensive and utility cooldowns organized by group composition, with talent-aware filtering, spell tooltips, and resizable frames.
- **Auto-Invite** module for automating raid formation via `/prt inv`.
- Snarky buff reminder messages for Ready Check whispers, with a toggle to turn them off if your raiders can't handle the sass.
- Ready Check now randomizes its message per player instead of per class.

### Fixed

- Buff detection now works reliably after multiple rounds of WoW API deprecation whack-a-mole.
- Ready Check whispers all missing-buff providers instead of stopping after the first.
- Ready Check falls back to defaults correctly when settings are missing.
- Out-of-range players no longer cause errors during ready check buff detection.
- Config UI now refreshes properly when switching tabs.

## [1.0.0-alpha-1] - 2026-01-21

Initial alpha release with Don't Release and Ready Check modules.

[Unreleased]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.1.4...v1.2.0
[1.1.4]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0-beta-2...v1.0.0
[1.0.0-beta-2]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0-beta-1...v1.0.0-beta-2
[1.0.0-beta-1]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0-alpha-4...v1.0.0-beta-1
[1.0.0-alpha-4]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-4
[1.0.0-alpha-3]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-3
[1.0.0-alpha-2]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-2
[1.0.0-alpha-1]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-1
