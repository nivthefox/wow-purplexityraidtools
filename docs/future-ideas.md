# PRT Future Ideas

Ideas explicitly deferred out of shipped specs. Nothing here is committed work.

## Note Annotations (deferred from Notes v1, 2026-07-17)

Allow a user to annotate a line in the active note with their own additional
context—for example, click a reminder line and add a `countdown:` to it, or a
personal TTS callout, without editing the shared note text.

Key properties as discussed:

- Annotations are **local overlays**, layered on top of the note at parse time.
  The shared/broadcast note text is never modified.
- Conceptually this is injecting extra NSRT-format fields (`countdown:`, `TTS:`,
  `sound:`, maybe `dur:`) into the local copy of a specific line.

Open design questions to resolve before speccing:

- **Line identity.** How does an annotation stay attached to "its" line when the
  raid leader re-broadcasts an edited note? Line index breaks on insertion;
  content hashing breaks on edits to the annotated line itself. This is the hard
  problem.
- **Interaction surface.** "Click a line"—in the static note frame, the paste
  box, or a dedicated annotation UI?
- **Conflict rules.** What happens when an annotation adds a field the line
  already has (e.g. line has `countdown:5`, annotation says `countdown:3`)?
- **Scope.** Per-note or per-encounter-per-note? Do annotations survive note
  deletion/rename?

## Shared Nicknames (deferred from Notes v1, 2026-07-17)

A **leader-owned, shared** nickname list: the raid leader maintains a
nickname → character mapping and broadcasts it to the raid, so the entire raid
uses the RL's vocabulary. When the RL says "Get Viper up," everyone's addon
knows Viper is Vha. This is deliberately NOT NSRT's model (self-assigned
nicknames synced per player)—the mapping is the raid leader's, distributed
top-down.

Notes v1 explicitly declined nicknames (spec §5.1: "PRT has no nickname
system; only actual character names match"). If this ships, that spec section
gets revised.

Consequences of the shared model:

- Notes can tag by nickname, and every raider's tag matching resolves the same
  way, because everyone holds the same list.
- One player can have multiple nicknames (mains, alts, "the other Viper"), all
  resolving to the same character.

Open design questions to resolve before speccing:

- **Distribution.** Rides the comms layer from Notes v1. Pushed with the note?
  Separately on demand? Auto on roster join? Same leader/assistant sender
  gating as note broadcasts, presumably.
- **Persistence.** Receivers store the list in their profile? What happens to a
  stale list from last week's raid with a different leader?
- **Alt mapping.** Nickname → player vs. nickname → specific character. Alts
  break character-name mapping; probably wants nickname → "whichever of these
  characters is in the raid."
- **Display.** Does the static note frame render the nickname or resolve it to
  the character name (with class color, per Notes v1's always-class-colored
  names)? Rendering the nickname in the character's class color is probably
  the winner—the RL's language, the player's identity.
- **NSRT note interop.** Notes authored with NSRT nicknames should still tag
  correctly if the RL's shared list defines the same nicknames.
