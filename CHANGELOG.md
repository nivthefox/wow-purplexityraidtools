# Changelog

All notable changes to PurplexityRaidTools will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
