# Event System

How `data/events/*.json` works, why it's built the way it is, and how to
author a new event. Read `docs/architecture.md` first — this doc assumes you
already know the condition mini-language, the effect vocabulary, and the
autoload layer it's built on top of.

**This is infrastructure, not story.** Every event in the sandbox
(`data/events/test_events.json`) is placeholder content that exists to prove
the system works — see `docs/architecture.md`'s opening note for why that
distinction matters throughout this project.

## What problem this solves

Investigation content already reacts to game state through conditions: a
topic, a destination, an examine variant all stay hidden until their
`condition` passes. What content couldn't do before this system is react to
game state *by itself* — something happening automatically the moment a
combination of flags/evidence/interactions becomes true, without the player
clicking the one specific thing that happens to trigger it.

An **event** is exactly that: a `condition` (the same mini-language as
everywhere else) that, instead of gating one piece of UI, gates a burst of
**effects** (the same vocabulary dialogue actions already use), evaluated
automatically whenever relevant state changes rather than on a player click.

## Reusing Conditions and Effects — not a second system

This is the load-bearing design decision, so it's worth being explicit:

- **Conditions**: `EventManager` calls `ConditionEvaluator.evaluate()` — the
  exact function `Investigation`/`DialogueManager` already call for topics,
  destinations, examine variants, and dialogue choices. An event's
  `"conditions"` field accepts the identical shapes documented in
  `docs/content-guide.md`, "Conditions reference" (`flag`, `has_evidence`,
  `visited_location`, `examined`, `interaction_complete`, `all`/`any`/`not`).
  Nothing new was added to the condition language for events.
- **Effects**: dialogue node/choice `"actions"` and event `"effects"` are the
  same shape (`[{"type": ..., ...}, ...]`), and now run through the exact
  same executor: `EffectRunner.run()` (`scripts/core/effect_runner.gd`). This
  is a small, deliberate refactor — `EffectRunner` used to be
  `DialogueManager._run_actions()`, a private method. It was pulled out,
  unchanged in behavior, because the event system needed to run the
  identical logic from outside dialogue playback. Both `DialogueManager` and
  `EventManager` now call `EffectRunner.run(...)`; neither owns effect
  execution.

  The JSON key differs by content type (dialogue keeps `"actions"`, events
  use `"effects"`) purely because those are each type's natural vocabulary —
  see `docs/architecture.md`'s note on why the dialogue key stayed
  `"actions"` in the first place. Both keys feed the same function.

No second condition language and no second effect language exist anywhere in
this project. See `docs/architecture.md`, "Key Architecture Decisions", for
the same reasoning applied to character presence below.

## Character presence: reusing conditions again, not a new mechanism

The obvious way to let an event "move a character" would be a pair of new
effects — `add_character_to_location`/`remove_character_from_location` —
backed by a new piece of `GameState`, something like a
`character_location_overrides` map. That was deliberately **not** built.

Before this system, an NPC's presence in a location was 100% static: each
location's `npcs` array was rendered unfiltered. The smallest change that
makes presence dynamic turns out to be exactly the same trick every other
kind of "unlock" in this project already uses: give each `npcs` entry an
optional `"condition"` (the same shape as a topic's or a destination's), and
filter by it:

```json
// data/locations/test_room.json
{ "id": "character_a", "condition": { "flag": "character_a_moved", "equals": false }, "topics": [...] }

// data/locations/test_hallway.json
{ "id": "character_a", "condition": { "flag": "character_a_moved" }, "topics": [...] }
```

One flag, two complementary conditions, one `set_flag` effect on the event
that "moves" the character. `Investigation.get_npcs()` (the same accessor
`InvestigationView` and `DebugPanel` already used) now filters
`get_all_npcs()` by each entry's `condition`, exactly like `get_topics()`
already filters by a topic's `condition`. No new `GameState` field, no
second place that knows "who is where," and the UI needed **zero** changes —
`InvestigationView._render_main()` already re-renders the NPC list on every
relevant signal, so a character disappearing from one location and appearing
in another is a pure consequence of content + `GameState`, not new UI code.

The one thing this doesn't do for you: nothing stops a badly-authored case
from giving a character mutually-*non*-exclusive presence conditions (true
in two locations at once). `ContentValidator` checks that a presence
`condition` references only known ids/keys, the same as any other condition
— but whether two conditions across two different location files are
actually exclusive is state-dependent and not something the validator
attempts to prove (see `docs/architecture.md`'s "Known limitations" for why
this project doesn't try to prove content correctness in general).

## Event definition

`data/events/*.json` — each file holds an **array** of event objects, the
same "group related things in one file" shape `data/dialogue/*.json` already
uses (grouping is for humans; ids stay in one flat namespace regardless of
file, exactly like every other content category — see `docs/content-guide.md`
"General rules").

```json
{
  "id": "character_a_moves_to_hallway",
  "conditions": {
    "all": [
      { "interaction_complete": "character_a_ready_to_move" },
      { "has_evidence": "test_key" },
      { "flag": "hallway_unlocked" }
    ]
  },
  "trigger_policy": "once",
  "effects": [
    { "type": "set_flag", "flag": "character_a_moved", "value": true }
  ]
}
```

**Why `hallway_unlocked` is in there**: the other two conditions
(`character_a_ready_to_move` and `test_key`) are both reachable from the
very start with no ordering dependency on presenting the key — a player who
talks about "about_moving" and examines the desk, in either order, without
ever presenting the key, would otherwise move Character A away before the
key could ever be presented, permanently locking `hallway_unlocked` (and
Test Hallway, where Character A now stands) — a real soft-lock a developer
found via the Case Debugger while testing Milestone 1.8. This is exactly the
class of bug `docs/testing.md`'s "Soft-lock safety philosophy" says
`ContentValidator` cannot catch (individually-reachable conditions whose
*order* matters) — see `scenes/test/negative_progression_test.gd`'s
`_test_event_does_not_fire_before_hallway_is_unlocked()` for the regression
test that pins this down, and `docs/testing.md`, "Soft-lock risk", for the
general lesson: a condition being individually reachable doesn't mean every
order of reaching it is safe.

| Field | Meaning |
|---|---|
| `id` | Unique within the `events` category (same rules as every other content id — see `docs/content-guide.md`). |
| `conditions` | Optional; the condition mini-language. Omitted/`null` means "always satisfied" (matches every other use of `condition` in this project) — an event like that fires the moment it's first evaluated. |
| `trigger_policy` | `"once"` (default if omitted) or `"repeatable"` — see below. |
| `effects` | A list of effect dictionaries, run through `EffectRunner.run()` — see "Reusing Conditions and Effects" above. An event with no effects does nothing when it fires; `ContentValidator` warns about this. |

## Trigger policies

- **`once`** — fires the first time `conditions` is satisfied, never again.
  Backed by `GameState.seen_interactions`, using a new `"event:<id>"`
  namespace alongside the existing `topic:`/`examine:`/`custom:` ones (see
  `game_state.gd`'s doc comment on `seen_interactions`) — deliberately not a
  new persisted field. `EventManager.is_event_triggered(event_id)` reads it.
- **`repeatable`** — fires again on every **false→true transition** of
  `conditions`, not on every evaluation while it happens to stay true (see
  "Event evaluation" below for why that distinction matters), and not on the
  very first evaluation an event is ever seen at (so loading a save where the
  condition already holds doesn't immediately misfire it — see "Known
  limitations"). Tracked by an in-memory-only dictionary in `EventManager`,
  never persisted.

An unrecognized `trigger_policy` is a `ContentValidator` error and falls back
to `once` at runtime (fails toward "an event that under-fires," not one that
fires unpredictably).

## Event state

Two states, matching what the brief actually needs: **not triggered** /
**triggered**. `EventManager.is_event_triggered(event_id)` is the query;
`EventManager.explain_event(event_id)` (debug-only) additionally reports
whether `conditions` currently passes and a per-condition breakdown, via the
same `ConditionEvaluator.explain()` used for "explain locked content"
elsewhere (`docs/architecture.md`, "Developer tools").

For `repeatable` events, "triggered" means "has fired at least once" — the
real repeat-gating state is the in-memory edge-tracking dictionary described
above, not something exposed as a third state. Keeping it to two states
(plus that one internal implementation detail) matches the brief's "keep
additional states minimal."

## Event evaluation

No per-frame polling. `EventManager` connects once, in `_ready()`, to the
same `GameState` signals investigation UI already listens to:
`flag_changed`, `evidence_added`, `evidence_removed`, `location_changed`,
`interaction_seen`. Any of those firing calls `_request_evaluation()`, which
re-scans **every** event (`ContentDB.get_all_event_ids()`) and runs whichever
ones are newly satisfied.

Re-scanning the whole list on every relevant change, rather than tracking
which events depend on which flags, is a deliberate simplification for this
project's scale — see `docs/architecture.md`'s general stance on optimizing
only when something actually needs it. If a future case has hundreds of
events and this becomes measurably slow, the fix is a flag/evidence →
interested-events index in front of the same `_try_trigger()` logic, not a
different architecture.

## Event chains

An event's effects can satisfy another event's conditions with no further
player action — see the sandbox's `mirror_note_ready`, whose only condition
is the flag `character_a_moves_to_hallway` sets. `EventManager._evaluate_all()`
handles this with a **bounded fixed-point loop**, not a queue:

```text
loop (up to MAX_EVALUATION_CYCLES times):
    any_fired = false
    for every event: if its conditions are newly satisfied, fire it, any_fired = true
    if not any_fired: stop
```

Effects that fire from inside this loop mutate `GameState` synchronously,
which re-emits the same signals `EventManager` listens to — a naive
implementation would recurse back into `_evaluate_all()` from inside itself.
Instead, a re-entrant call while a pass is already running just sets a
"please run once more when this pass finishes" flag (`_needs_reevaluation`)
and returns immediately; the *current* pass's own `for` loop is what
actually catches the newly-satisfied follow-up event, in the same or a
subsequent cycle. `MAX_EVALUATION_CYCLES` (20) is the loop-prevention
backstop: content where two events keep re-satisfying each other's
conditions forever hits the cap, logs a `push_warning`, and stops — it does
not hang.

This is the "simplest reliable approach" the brief asks for: no execution
queue, no dependency graph, just "re-check everything until nothing changes,
with a cap." At this project's scale (a handful of events) that's cheap and
easy to reason about; see "Event evaluation" above for the same call on not
pre-optimizing.

## Character presence, event-driven content, and the sandbox demo flow

`scenes/test/smoke_test.gd`'s `_test_event_system()` exercises the sandbox
demo end to end:

1. Character A starts in Test Room (`data/locations/test_room.json`).
2. Talking to Character A's `about_moving` topic marks
   `interaction_complete: character_a_ready_to_move`. The player already
   holds `test_key` and has already unlocked the hallway from earlier, so
   `character_a_moves_to_hallway`'s other two conditions are already
   satisfied — the event fires mid-dialogue, from this one action. (If the
   player instead reached this state before presenting the key, the event
   would correctly stay silent — see the `hallway_unlocked` condition above.)
3. Its effect sets `character_a_moved = true`. That alone satisfies
   `mirror_note_ready`'s condition, which chain-fires in the same pass (see
   "Event chains").
4. Character A is now filtered out of Test Room's NPC list and into Test
   Hallway's (see "Character presence" above) — pure content/condition, no
   UI code changed.
5. Test Hallway's mirror examine point gains a new variant once
   `mirror_note_ready` is set — an event changing available content, not
   just a flag (`docs/content-guide.md` section 5's `variants` mechanism,
   unchanged).
6. Moving to Test Hallway and talking to Character A there is a genuinely
   new interaction (`character_a_greeting_hallway`), only reachable because
   the character is now present.

The same test also exercises `trigger_policy: "repeatable"` in isolation
(`test_repeatable_pulse`, driven purely by toggling a flag back and forth —
see the test for exactly what it asserts) and the manual-trigger path (see
"Developer tools" below), independent of the narrative-ish demo above.

## Developer tools

The Case Debugger's (F1) **Events** tab lists every event with its status —
`NOT TRIGGERED`, `CONDITIONS MET` (satisfied but not yet evaluated/fired —
transient, you'll rarely catch it, since evaluation runs synchronously off
the same signal), or `TRIGGERED` — and, like locked topics/destinations, a
per-condition `[x]`/`[ ]` breakdown for anything not yet satisfied,
filterable by event id. The **NPCs** tab shows `PRESENT`/`ABSENT` per NPC
entry with the same missing-condition breakdown, so a character who has
moved away is visible as "ABSENT — missing: flag ... == ..." rather than
silently gone. See `docs/case-debugger.md` for the full tab layout.

An **event id field + Trigger button** calls
`EventManager.force_trigger(event_id)`, which runs `_fire()` directly —
bypassing both `conditions` and `trigger_policy` — through the exact same
pipeline (`GameState.mark_seen` + `EffectRunner.run` + `event_triggered`
signal) automatic triggering uses, per the brief's instruction not to
duplicate the firing logic for a developer shortcut. This is a developer-only
override: forcing a `"once"` event still marks it triggered (so automatic
evaluation won't also fire it), and forcing a `"repeatable"` event doesn't
touch its false→true edge tracking, so it doesn't interfere with the next
real transition either. Requires confirming in the debugger (it runs real
effects immediately).

A **Reset Trigger button** (Milestone 1.8) calls
`EventManager.debug_reset_trigger(event_id)`: clears the "has triggered"
marker (and, for a `"repeatable"` event, its in-memory false→true edge
state) via a new `GameState.unmark_seen()`, then requests a normal
reevaluation pass. It does **not** undo the event's own already-run effects —
see `docs/case-debugger.md`, "Manual Event Trigger vs. Event Reset", for
exactly what this does and doesn't simulate, and why it needs no
confirmation dialog (it never re-runs effects by itself).

## Logging

`EventManager` prints `[EventManager]` lines: one "Evaluating events after
state change" per evaluation pass, `Triggered: <id>` plus an indented list of
its effects (via `EffectRunner.describe()`) whenever something actually
fires, and a `push_warning` if the cycle cap is hit. `_request_evaluation()`
short-circuits entirely (no print, no work) when `data/events/` is empty, so
a case with no events yet — or the title screen, before any case is loaded —
produces zero event-system log output.

## Save / load

Nothing new to serialize. A `"once"` event's triggered state lives in
`GameState.seen_interactions` (already saved/loaded verbatim), and dynamic
world state (`character_a_moved`, `mirror_note_ready`, ...) is plain
`GameState.flags` (already saved/loaded verbatim) — see "Reusing Conditions
and Effects" above for why this was the point of building it this way.
Loading a save re-evaluates every event against the restored state
(`GameState.load_from_dict()`'s one `location_changed` emission triggers it,
the same as any other state change), which is what proves a `"once"` event
doesn't refire after load: its condition may still be true, but
`is_event_triggered()` already reads `true` from the restored
`seen_interactions`, so `_try_trigger()` refuses it.

## Content validation

`ContentValidator._validate_events()` runs the same checks every other
condition/effect already gets — no `unknown key`, evidence/location
references resolve, an `all`/`any` that isn't a non-empty array, exactly one
check per condition object — via the same `_validate_condition()` /
`_validate_effects()` helpers dialogue/topic/destination validation already
calls. On top of that:

- unknown `trigger_policy` → error.
- an event with no `effects` → warning (it would fire and do nothing).
- a `"repeatable"` event whose own effects set the exact same flag/value its
  own top-level (or `all`-nested) `conditions` require → warning. This is a
  cheap, best-effort "obvious self-reference" check, not a proof: it catches
  the common mistake of writing a repeatable event that resets its own
  trigger condition to the value that would keep it satisfied forever
  (meaning it can, in practice, only ever fire once) — it does not attempt
  to detect every possible way a repeatable event could fail to reset (see
  `docs/architecture.md`'s "Known limitations" on why this project doesn't
  try to prove content correctness in general).
- duplicate event ids are already caught for free — `ContentDB`'s
  duplicate-id detection (`get_duplicate_id_issues()`) runs per category
  regardless of what that category is.
- an npc entry's presence `condition` is validated exactly like a topic's or
  destination's condition (see "Character presence" above).

## Known limitations

- **A `"repeatable"` event's false→true edge state is in-memory only, not
  persisted.** In the vast majority of real play this doesn't matter: the
  autoloads (including `EventManager`) live for the whole process, so
  save → return to title → load → keep playing all happen inside the same
  process, and the edge state survives exactly as expected. It only matters
  after an actual process restart (quit and relaunch, or a fresh headless
  run) landing on a save whose restored state already satisfies a repeatable
  event's condition: the first evaluation after that restart is deliberately
  treated as an "arm, don't fire" baseline (see "Trigger policies" above),
  which is the safe default, but it does mean that specific event won't
  re-fire again until its condition goes false and true at least once in the
  new process, even though it may have already fired several times before
  the restart.
- **`{"examined": "..."}` in an event's `conditions` resolves against
  whatever location the player currently happens to be standing in at
  evaluation time** — `ConditionEvaluator`'s `examined` check is always
  relative to `GameState.current_location` (see `docs/architecture.md`), and
  an event has no location of its own the way an examine point does. This
  isn't specific to events (a dialogue choice condition has exactly the same
  property, and isn't checked against a fixed location by the validator
  either — see `_validate_condition`'s `examined_scope_location_id`
  parameter) — but it's an easy trap for an event, since an event's
  conditions are typically written with a specific moment in mind. Prefer
  `has_evidence`/`flag`/`interaction_complete` for anything that should be
  location-independent, which is true of every event in the sandbox.
- **No event priority / ordering control beyond insertion order.** If two
  events' conditions both become true in the same evaluation pass and their
  effects would conflict, whichever comes first in `ContentDB.get_all_event_ids()`
  runs first — itself dependent on file load order, which
  `docs/architecture.md`'s "Known limitations" already documents as not
  guaranteed across content files. Not a concern for anything in this
  sandbox (no two events currently touch the same state), but worth knowing
  before authoring events whose effects could interact.
- **`ContentValidator` does not attempt to prove an event is ever reachable**
  (that its conditions can actually become true given everything else in a
  case), the same way it doesn't attempt this for a topic or a dialogue
  choice — see `docs/architecture.md`'s "Known limitations".
