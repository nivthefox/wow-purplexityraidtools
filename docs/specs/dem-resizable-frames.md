---
status: draft
---

# Cooldown Roster: Resizable Category Frames

## Problem

The Defensives, Externals, and Movement frames have a hardcoded width (`BAR_WIDTH = 200`). When unlocked for positioning, there is no way to adjust the width.

## Behavior

When frames are unlocked (`lockFrames = false`), each category frame should be resizable by dragging its right edge. The minimum width should prevent the frame from collapsing below a readable size (probably around 120px). There is no maximum width.

Width changes persist per-category in the same `positions` table that already stores `point`, `x`, and `y`. Each category's saved position should include a `width` field. On load, frames restore their saved width; if no saved width exists, they use the current default (200).

When frames are locked, resize handles are hidden and the frame width is fixed.

The bars inside the frame (icon, spell name, player name) should fill the available width. The player name text should be the flexible element—it already has no fixed width constraint, so it just needs the spell text width to stay fixed while the player name region stretches.

## What NOT to Change

- Bar height, icon size, spacing, and other vertical metrics stay the same.
- The drag-to-reposition behavior is unchanged; resizing is a separate interaction (right-edge drag, not whole-frame drag).
