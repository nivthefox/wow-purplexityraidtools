---
status: draft
---

# Cooldown Roster: Top-Down Growth Direction

## Problem

When the roster content changes (players join/leave, inspections complete), the category frames resize via `SetSize()`. The direction they grow depends on their anchor point, which is whatever `GetPoint()` returned when the frame was last dragged. If the anchor is `CENTER`, the frame grows in both directions. This makes the top edge jump around unpredictably.

## Behavior

Category frames should always grow downward from their top-left corner. When content changes and the frame resizes, the top edge stays pinned and the bottom edge moves.

`SaveFramePosition` currently saves whatever anchor point `GetPoint()` returns. Instead, it should always normalize the position to `TOPLEFT` before saving. On restore, the frame should always anchor at `TOPLEFT`. This ensures that `SetSize()` only expands downward and to the right.

When the user drags a frame to a new position and releases it, `SaveFramePosition` should compute the `TOPLEFT` point of the frame's current screen position (regardless of what WoW's internal anchor says) and save that. The default positions in `RestoreFramePosition` should also use `TOPLEFT` anchoring.

## Edge Cases

If a user has existing saved positions using other anchor points (from before this fix), the first load after this change will reposition their frames incorrectly. This is acceptable—they'll need to reposition once. Don't add migration logic for saved positions; it's not worth the complexity.
