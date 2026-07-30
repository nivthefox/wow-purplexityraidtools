# Update CHANGELOG.md with user-visible changes

Review all commits since the last release, rewrite them as user-facing changelog entries matching the project's existing style, and update the Unreleased section of CHANGELOG.md.

## Steps

### 1. Identify the last release

- Read `PurplexityRaidTools.toc` and extract the current `## Version:` value to get the tag name `v$version`.
- Verify the tag exists: `git tag -l v$version`.

### 2. Gather commits since the last release

- Run `git log --format="%H %s" v$version..HEAD` to get every commit since the tag.
- STOP if there are no commits since the last release—there is nothing to do.

### 3. Identify what is already in Unreleased

- Read `CHANGELOG.md` and extract any entries already under `## Unreleased`.
- Do NOT duplicate entries that are already present. If all commits are already covered, STOP.

### 4. Read the changed code

- For each commit, run `git show --stat $hash` to understand the scope of the change.
- If the commit message alone is not clear enough to write a user-facing entry, run `git show $hash` to read the full diff.

### 5. Write changelog entries

Rewrite each commit as a user-facing changelog entry. Follow these rules:

- **Voice**: describe what changed from the user's perspective, not the developer's. "Raid container sizing uses maximum group count" → "Raid frames no longer drift out of position when group size changes."
- **Tense**: use present tense or past-tense result ("now does X", "no longer does Y"), not imperative ("fix X").
- **Grouping**: use Keep a Changelog categories—Added, Changed, Fixed, Removed—in that order. Omit empty categories.
- **Granularity**: multiple commits that address the same user-visible change MUST be merged into a single entry. Do NOT produce one entry per commit when commits are related.
- **Commit types to skip**: `release:`, `docs:`, `chore:`, `ci:`, `test:` commits that have no user-visible effect. If every commit is skippable, STOP.
- **Style reference**: match the tone and detail level of existing entries in CHANGELOG.md. Read at least two prior release sections before writing.

### 6. Update CHANGELOG.md

- Insert the new entries under the existing `## Unreleased` header.
- Preserve any entries already in the Unreleased section—append new entries to the appropriate category, or create new categories as needed.
- Preserve all existing versioned sections below.
- Write the file.

### 7. Show the diff and ask for verification

- Run `git diff CHANGELOG.md` and display the result.
- Ask: "Does this look good? I'll commit when you give the word."

## Stop conditions

- STOP if there are no commits since the last release.
- STOP if all commits since the last release are already represented in the Unreleased section.
- STOP if every commit is a non-user-facing type (docs, chore, ci, test, release).
- Do NOT commit. Wait for explicit confirmation.
