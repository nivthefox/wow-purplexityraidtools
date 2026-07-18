# Changelog

All notable changes to PurplexityRaidTools will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Notes** module for timed boss note reminders:
  - Paste an NSRT-style note (one encounter per note) and PRT parses it into a live assignment sheet.
  - Static note frame with per-reminder countdowns, class-colored names, raid-target icons, and configurable fonts, colors, and hide behavior.
  - Timed popups in four styles (Icon, Bar, Text, Circle) with individually movable anchors, stacking, and scale.
  - Audio alerts, TTS callouts, and spoken countdowns per reminder.
  - Reminders filter to your role, spec, class, group, or name via note tags.
  - Phase-aware timing that tracks BigWigs and DBM stage callbacks.
  - Raid leaders and assistants can broadcast the active note to the raid or clear it with one click; sending is blocked during combat.

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
