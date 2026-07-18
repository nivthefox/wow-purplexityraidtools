# Changelog

All notable changes to PurplexityRaidTools will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
