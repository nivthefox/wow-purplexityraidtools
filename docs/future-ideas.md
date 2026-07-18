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

Noted use case (2026-07-17): annotations are the intended lever for *silencing*
line-level audio too—e.g. suppress a `countdown:` on a specific line. Notes v1
deliberately has no global countdown-mute; this is the plan for that gap.

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

## Per-Type Popup Scale (deferred from Notes v1, 2026-07-18)

Each popup display type (Icon, Bar, Text, Circle) gets its own scale instead of
the single shared `popups.scale`. Surfaced during in-game testing: the four
types have very different footprints, so one global multiplier can't make a
big Bar and a small Icon both sit right.

Open design questions to resolve before speccing:

- **Settings shape.** `popups.scale` becomes `popups.scalesByType = {Icon=1,
  ...}`? Migration for existing profiles that carry the single value.
- **UI.** Four sliders in the popup section, or a per-mover drag handle /
  scroll-to-scale while unlocked (less config clutter, more discoverable).
- **Global multiplier.** Keep the global scale as a master on top of the
  per-type values, or replace it outright.

## Auto-Load Note on Encounter Start (deferred from Notes v1, 2026-07-17)

When an encounter starts and a saved (but not active) note matches its
EncounterID and difficulty, automatically activate that note. Today the raid
leader selects the note manually or broadcasts it; auto-load closes the "we
pulled and I forgot to switch notes" gap.

Notes v1's spec §1 explicitly declares "PRT never picks a note by detecting the
boss." If this ships, that statement (and §3.2 Activate) gets revised.

Open design questions to resolve before speccing:

- **Conflict resolution.** Multiple saved notes match the same encounter ID and
  difficulty (e.g. "Sszorak week 1" and "Sszorak week 2")—which wins? Most
  recently saved? Most recently active? Refuse and stay on the current note?
- **Broadcast priority.** A broadcast-received note should presumably beat
  auto-load; the RL's explicit push is authoritative over local guessing.
- **Timing.** ENCOUNTER_START is late—the note frame would pop mid-pull-in.
  Is that acceptable, or should matching happen earlier (target-of-boss,
  zone/journal detection)? Earlier is fuzzier; later is jarring.
- **Opt-in.** A setting, or always-on? Auto-switching the active note is
  surprising behavior for a raider who curated their selection.
- **Deactivation.** Does the auto-loaded note stay active after the encounter,
  or revert to the previously active note?

## Addon Detection (deferred, 2026-07-18)

A way for the raid leader (or any user) to see which raid members do **not**
have PRT installed. Useful for enforcing addon requirements or diagnosing why
someone isn't seeing notes/popups.

Open design questions to resolve before speccing:

- **Mechanism.** Silent version handshake on group join (comms-layer ping/pong)?
  Or piggyback on an existing broadcast and track who responds?
- **Display.** Inline in the roster? A separate "addon status" tooltip or panel?
- **Staleness.** How long before a missing response counts as "not installed" vs.
  "still loading"? Timeout threshold and re-check cadence.
- **Privacy.** Is broadcasting your addon version (and implicitly your presence)
  acceptable, or should it be opt-in?

## Cooldown Roster ↔ Notes Integration (deferred, 2026-07-18)

Tie the Cooldown Roster and Notes together so that when a note line says a
player's ability is active, CDR reflects it—and when that ability *should* be
on cooldown afterward, CDR shows the cooldown state too.

This turns Notes from a display-only timeline into something that feeds live
roster state, closing the gap between "the plan says use Spirit Link now" and
"is Spirit Link actually available?"

Open design questions to resolve before speccing:

- **Data flow.** Notes → CDR (note activation sets "ability in use" on CDR), or
  bidirectional (CDR cooldown expiry updates note line styling)?
- **Ability identity.** How does a note line's text ("SLT" / "Spirit Link") map
  to CDR's spell-ID–based tracking? Relies on shared nicknames / spell aliases?
- **Timing accuracy.** Note countdown timers are best-effort; real cooldowns are
  server-authoritative. How much drift is acceptable before the CDR state
  disagrees with the note's implication?
- **Multiple assignments.** A note line might assign the same ability to different
  players at different times. CDR needs to track per-player, per-cast, not just
  per-spell.

## Ready Check Snark (deferred, 2026-07-18)

Enhance the Ready Check module with whisper-based nudges:

1. **Dead players** get a VERY snarky whisper reminding them to release their
   spirit. They are, after all, lying on the floor while 19 other people wait.
2. **Players not at full health** get a mildly snarky whisper reminding them
   that there is, in fact, a Recuperate button in the game.

Open design questions to resolve before speccing:

- **Trigger.** On ready check initiation, on ready check completion, or both?
- **Throttle.** Whisper once per ready check, or suppress repeats within some
  window so the same dead player doesn't get spammed across back-to-back checks?
- **Message pool.** Static messages or a rotating pool of snarky lines? If
  rotating, who writes them? (The answer is obviously Niv.)
- **Opt-out.** Can the recipient suppress these, or is suffering the point?
- **Permissions.** Only the ready check initiator sends whispers, or does every
  PRT user independently whisper? (The latter would be chaotic and hilarious,
  but probably wrong.)

## Per-Character Profiles (deferred, 2026-07-18)

Profiles should be swappable per-character rather than a single global "active
profile." A healer alt and a DPS main likely want completely different note
display settings, popup positions, and CDR configurations—forcing a manual
profile swap on every character switch is friction that adds up.

Open design questions to resolve before speccing:

- **Binding model.** Character name? Character GUID? Class? Spec? "Last profile
  used on this character" (implicit) vs. explicit assignment in a UI?
- **Default behavior.** What happens on a character with no binding—fall back to
  the current global active profile, or prompt?
- **Migration.** Existing users have one active profile. First login per alt
  after this ships needs a smooth path, not a "no profile selected" blank state.
- **Spec-swap.** Some players swap specs on the same character (heal vs. DPS on
  the same druid). Should the binding be per-spec, or is per-character enough?
