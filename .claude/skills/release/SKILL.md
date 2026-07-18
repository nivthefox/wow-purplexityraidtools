# Release PurplexityRaidTools

Release the addon by cutting a versioned changelog entry, bumping the TOC, tagging, pushing, and publishing a GitHub release.

## Parameters

- `$version` (optional) — The version to release (e.g., `1.0.0-alpha-4`). If omitted, auto-increment the current version's last numeric segment (e.g., `1.0.0-alpha-3` → `1.0.0-alpha-4`).

## Steps

### 1. Determine the version

- Read `PurplexityRaidTools.toc` and extract the current `## Version:` value.
- If `$version` is provided, use it as the new version.
- If `$version` is omitted, increment the last numeric segment of the current version by 1.

### 2. Update CHANGELOG.md

- Read `CHANGELOG.md`.
- Move everything under `## [Unreleased]` into a new section `## [$version] - YYYY-MM-DD` (today's date) inserted immediately after the `## [Unreleased]` header.
- Leave the `## [Unreleased]` header in place with no content beneath it (empty section).
- Preserve all existing versioned sections below.

### 3. Update PurplexityRaidTools.toc

- Replace the `## Version:` field value with the new version string.

### 4. Commit

- Stage `CHANGELOG.md` and `PurplexityRaidTools.toc`.
- Commit with the message: `chore: prepare v$version release`

### 5. Tag

- Create an annotated or lightweight git tag: `v$version`

### 6. Push

- Push `main` and tags to `origin`: `git push origin main --tags`

### 7. Create GitHub release

- Use `gh release create v$version` with:
  - `--title "v$version"`
  - `--notes` set to the changelog content for this version (the Added/Changed/Fixed sections)
  - `--prerelease` flag if the version contains a prerelease suffix (e.g., `-alpha`, `-beta`, `-rc`)
- Report the release URL when done.

## Stop conditions

- STOP and ask if `CHANGELOG.md` has an empty `[Unreleased]` section (nothing to release).
- STOP and ask if the working tree has uncommitted changes before starting.
- STOP and report the error if `git push` or `gh release create` fails.
