# Soft-lock risk and regression traps

`ContentValidator` proves references resolve; it does not — by explicit
design (`docs/architecture.md`, "Known limitations") — prove content is
*reachable* or a case is *solvable*. That gap is where a soft lock (required
progression state that becomes permanently unreachable) lives. This file is
the practical, cheap checklist for that gap — not a call to build a solver.

## The checklist

For anything newly gated by a `condition` (a topic, destination, examine
variant, NPC presence, event, or chapter `completion_event`), trace it by
hand, the same way you'd trace a broken reference:

1. **Find the effect that's supposed to satisfy this.** Grep for the
   `set_flag`/`add_evidence`/`mark_interaction_complete` that sets whatever
   the condition checks. If nothing in `data/` sets it, that's not a future
   problem — it's dead content today.
2. **Confirm that effect's own trigger is reachable from wherever the player
   actually starts.** An action buried in a dialogue tree needs that tree to
   actually be played by some topic/examine-point/present-response the
   player can reach; an event's condition needs *its* inputs to be reachable
   the same way, recursively.
3. **Evidence that gets `remove_evidence`d**: check whether anything that
   still needs to `has_evidence` it (a present_response, a condition) runs
   strictly before the removal in every path that reaches it. This project
   has no dedicated tooling for this — it's a manual trace, same as #1.
4. **A chapter's completion conditions must not reuse a condition that's
   already true before the chapter starts.** This is the exact trap
   `docs/case-system.md` calls out and deliberately avoids: chapter 2's
   completion event does *not* reuse `talked_to_character_a_in_hallway`
   (chapter 1's own required interaction, naturally already true by chapter
   2) — it requires the chapter's own scope flag (set by its
   `entry_effects`) plus a chapter-2-only interaction instead. When you
   write a new chapter's `completion_event`, ask: "could this already be
   true the moment the chapter activates?" If yes, it will complete
   instantly and skip the chapter's actual content.
5. **Two NPC presence entries for one "moved" character are not checked for
   mutual exclusivity anywhere** (`docs/event-system.md`, "Known
   limitations"). If you add a second location entry for an existing
   character, manually verify the two conditions can't both be true (they'd
   appear in two places) or both be false (they'd vanish from the game)
   at the same time — e.g. `{"flag": "x", "equals": false}` paired with
   `{"flag": "x"}` (no `equals`), not two independently-set flags.
6. **A `ContentValidator` warning is a soft-lock signal, not noise.** "No
   generic `present_responses` fallback" means presenting *any* unrelated
   evidence to that NPC produces total silence — no dialogue, no feedback.
   "No unconditional `examine_points` variant fallback" is the same shape
   for Examine. Both are exactly the kind of dead end #1–3 above are
   checking for by hand; the validator already gives you these two for
   free, so treat a new one appearing as something to fix, not dismiss (see
   SKILL.md, "Content validation is the cheapest net you have").

## Regression traps specific to save/load

- **Only five things persist**: `current_location`, `visited_locations`,
  `evidence_inventory`, `flags`, `variables`, `seen_interactions` (see
  `GameState.get_save_dict()`). Everything this project has built since —
  event-triggered state, chapter/case completion, current chapter — is
  encoded as one of those five specifically so save/load never needed a
  format change. Before adding a new `GameState` field, check whether what
  you actually need is a new flag, a new `seen_interactions` key (via
  `mark_seen("your_namespace:your_id")`), or a `variables` entry instead —
  all three round-trip for free.
- **`variables` round-trips through JSON as-is**: a number you store there
  comes back as a float (`docs/architecture.md`, "Known limitations"). Don't
  compare it with `is` or assume integer type; compare numerically.
- **A `"repeatable"` event's false→true edge tracking is in-memory only**,
  never persisted (`docs/event-system.md`). It survives save→load within one
  running process (which is what a real player's save/reload during a
  session actually is) but not a process restart — the first evaluation
  after a fresh process boot on a save whose condition already holds is
  deliberately "arm, don't fire," not a bug. Never write a test that expects
  a repeatable event to be mid-cycle across a simulated process restart;
  only assert its in-process behavior, the way `_test_event_system` does.
- **Loading must re-evaluate events without re-firing `"once"` ones.**
  `_test_save_load` is the proof this holds: it asserts
  `is_event_triggered()` stays true and the fired-events count does **not**
  increment after a load, even though the condition is still satisfied.
  Any change to `EventManager`'s evaluation entry point should re-run this
  exact assertion, since it's the one thing standing between "loading a save
  is safe" and "loading a save silently replays every already-satisfied
  event's effects."

## Regression traps specific to events

- **No event priority beyond insertion order**
  (`ContentDB.get_all_event_ids()`, itself dependent on `res://` directory
  iteration order, which is *not* guaranteed — `docs/event-system.md`,
  "Known limitations"). Don't author two events whose effects could conflict
  if fired in either order; if you must, don't rely on which one "wins."
- **`{"examined": "..."}` inside an event's conditions is relative to
  `GameState.current_location` at evaluation time, not to any location the
  event conceptually belongs to** (events have no location of their own).
  This is an easy authoring mistake specifically for events (a dialogue
  choice condition has the same property but is usually written with the
  right location already in mind). Prefer `flag`/`has_evidence`/
  `interaction_complete` for anything event-side that should be
  location-independent.
- **The bounded fixed-point loop caps at `MAX_EVALUATION_CYCLES` (20) and
  logs a warning rather than hanging** if two events keep re-satisfying each
  other. If you add an event chain longer than a couple of hops, sanity
  check it terminates well under the cap rather than assuming it does.

## Regression traps specific to content-shape changes

Adding a new condition leaf, effect type, or content field is a schema
change with the widest blast radius in this project (see SKILL.md's
"Regression surface"). The full list of places `docs/architecture.md` and
`docs/content-guide.md` already name for this:

- `ConditionEvaluator.LEAF_KEYS` / the effect `match` in
  `EffectRunner.run()` — the actual new behavior.
- `ContentValidator`'s corresponding `_validate_condition()` /
  `_validate_effects()` branch — otherwise the new shape validates as
  silently wrong (an effect with an unrecognized `type` is currently only a
  *warning*, not an error — don't let a genuinely broken new effect type shp
  by as a warning; add the real validation).
- `docs/content-guide.md`'s reference tables (conditions reference, actions
  list) and `docs/architecture.md`'s condition-language section.
- `scenes/test/smoke_test.gd`'s `_test_conditions` (for a condition leaf) or
  the relevant `_test_*` (for an effect) — a new shape with zero coverage is
  exactly the gap this whole skill exists to close.
- `DebugPanel` — does "explain locked content" need to describe the new
  leaf type for it to stay useful as a debugging tool.
