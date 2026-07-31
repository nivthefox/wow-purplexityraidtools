# Changelog

All notable changes to PurplexityRaidTools will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Battle Res Counter** with a standalone draggable icon widget (cooldown sweep, charge count, accrual timer) and a summary row at the bottom of the Cooldown Roster's Externals category. Active in any group.

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

[Unreleased]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0-beta-2...HEAD
[1.0.0-beta-2]: https://github.com/nivthefox/wow-purplexityraidtools/compare/v1.0.0-beta-1...v1.0.0-beta-2
[1.0.0-beta-1]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-beta-1
[1.0.0-alpha-4]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-4
[1.0.0-alpha-3]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-3
[1.0.0-alpha-2]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-2
[1.0.0-alpha-1]: https://github.com/nivthefox/wow-purplexityraidtools/releases/tag/v1.0.0-alpha-1
