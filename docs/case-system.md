# Case & Chapter System

How `data/cases/*.json` + `data/chapters/*.json` organize content into a
Case made of Chapters (Milestone 1.6), why it's built the way it is, and how
to author a new placeholder case. Read `docs/architecture.md` and
`docs/event-system.md` first — this doc assumes you already know the
condition mini-language, the effect vocabulary, and the Event system, and
builds on top of all three without changing any of them.

**This is infrastructure, not story.** `data/cases/test_case.json` and its
two chapters are placeholder content, built to prove the architecture works
— see `docs/architecture.md`'s opening note for why that distinction matters
throughout this project. There is still no real case, no protagonist, and no
deduction/courtroom gameplay; this system only answers *"how would a future
case's content be organized and sequenced,"* not *"what does a case actually
contain."*

## What problem this solves

Before this milestone, a "case" was just `data/cases/*.json`'s
`start_location` + `initial_flags` — what "New Game" resets to. That's
enough for one undifferentiated pile of content (the Milestone 0-1.5
sandbox), but it has no notion of *progression*: no way to say "this content
belongs to an early part of the case, that content belongs to a later part,
and the case should visibly move from one to the other." The Case/Chapter
layer adds exactly that — a **Case** is an ordered sequence of **Chapters**;
a **Chapter** is "the currently active phase," activated with some optional
one-shot effects and completed once a condition becomes true.

It is deliberately **not** a new gameplay engine, condition language, effect
language, or event system — see "Architecture principle" below.

## Architecture principle

```
CASE
 │
CHAPTER
 │
 ├── content (locations/dialogue/topics), scoped by a flag the chapter's own
 │   entry_effects sets — same "flag + condition" idiom as everything else
 │
 └── completion_event → an ordinary Event (ConditionEvaluator + EffectRunner)
                              │
                          GAME STATE
```

Case and Chapter **coordinate** the systems Milestones 0-1.5 already built;
they don't duplicate any of them:

- No new condition language. A chapter's completion is an existing Event's
  `conditions` (see "Chapter completion" below) — the exact same
  `ConditionEvaluator.evaluate()` every topic/destination/variant/event
  already uses.
- No new effect language. A chapter's `entry_effects` (and a completion
  event's `effects`) run through the exact same `EffectRunner.run()`
  dialogue actions and event effects already use.
- No new reactive-evaluation loop. Chapter completion is detected by
  listening to `EventManager.event_triggered`, not by re-implementing
  `EventManager`'s reentrant, bounded fixed-point evaluation — see "Why
  chapter completion is an Event, not a second evaluator" below.
- No new persisted state shape. "Current case/chapter" lives in
  `GameState.variables`; "which chapters/cases have completed" reuses the
  exact same `GameState.seen_interactions` "has this happened" set a
  `"once"` event's triggered state already uses — see "Case/Chapter runtime
  state" below.

## Case definition

`data/cases/*.json` — unchanged shape from Milestone 0, plus three new
**optional** fields:

```json
{
  "id": "test_case",
  "display_name": "Test Case",
  "description": "...",
  "version": 1,
  "start_location": "test_room",
  "starting_chapter": "test_case_chapter_01",
  "chapters": ["test_case_chapter_01", "test_case_chapter_02"],
  "initial_flags": { "...": false }
}
```

| Field | Meaning |
|---|---|
| `start_location` / `initial_flags` | Unchanged — see `docs/content-guide.md`. |
| `display_name` | Human-readable name for debug tooling. `case_00_sandbox` still uses the older `title` key (nothing programmatic ever read it); `display_name` is what new content should use. Debug tooling falls back to `title` for compatibility. |
| `description`, `version` | Purely documentary — shown nowhere yet, kept because they're obviously useful for a future case list and cost nothing to validate. |
| `chapters` | Ordered array of this case's chapter ids. **Optional.** A case that omits it (or leaves it empty) is a **flat case** — see "Flat cases" below. |
| `starting_chapter` | Which chapter id `CaseManager.start_case()` activates first. Required if `chapters` is non-empty. |

### Flat cases

`case_00_sandbox` deliberately has neither field, and is untouched by this
milestone. `CaseManager.start_case("case_00_sandbox")` still works — it's
the same code path a chapter-based case uses — it just does nothing chapter
-related, because there's no `starting_chapter` to activate.
`CaseManager.get_current_chapter_id()` then returns `""`, and every other
`CaseManager` method is a safe no-op or returns an empty/false result. This
is how backward compatibility is proven, not asserted: the existing sandbox
content required zero changes to keep passing `smoke_test.gd`.

## Chapter definition

`data/chapters/<case_id>/<chapter_id>.json` — one chapter per file, the same
"one object per file" shape `data/locations/*.json` and `data/cases/*.json`
already use (chapters are a bigger conceptual unit than a dialogue tree or
an event, which is why those stay array-per-file and chapters don't).
Chapters are their own flat `ContentDB` category (`get_chapter`,
`get_all_chapter_ids`, `get_all_chapters`), loaded from `data/chapters/`
exactly like every other category — the `<case_id>/` subfolder is purely for
human organization, like every other content folder in this project.

```json
{
  "id": "test_case_chapter_01",
  "display_name": "Chapter 01",
  "entry_effects": [],
  "completion_event": "test_case_chapter_01_complete",
  "next_chapter": "test_case_chapter_02"
}
```

| Field | Meaning |
|---|---|
| `entry_effects` | Optional list of effect dictionaries (the same `EffectRunner` vocabulary — `set_flag`, `add_evidence`, `remove_evidence`, `mark_interaction_complete`), run once when this chapter becomes current. Empty/omitted is valid — `test_case_chapter_01` needs none. |
| `completion_event` | Optional id of an event in `data/events/*.json` (see "Chapter completion" below). A chapter with none can only be completed via the debug panel's "Complete Current" button. |
| `next_chapter` | Optional id of the chapter to activate once this one completes. Omitted (not present in the JSON at all — never write `"next_chapter": null`, see "A note on omitting vs. nulling fields" below) on a case's last chapter: that chapter completing instead completes the **case**. |

### Chapter completion is an ordinary Event, not a new mechanism

A chapter's `completion_event` names a normal entry in `data/events/*.json`
— its `conditions` are that chapter's completion conditions, and its
`effects` are that chapter's completion effects, using the exact vocabulary
documented in `docs/event-system.md`. `test_case_chapter_01`'s completion
event:

```json
{
  "id": "test_case_chapter_01_complete",
  "conditions": {
    "all": [
      { "flag": "character_a_moved" },
      { "visited_location": "test_hallway" },
      { "interaction_complete": "talked_to_character_a_in_hallway" }
    ]
  },
  "trigger_policy": "once",
  "effects": [
    { "type": "set_flag", "flag": "test_case_chapter_01_complete", "value": true }
  ]
}
```

`CaseManager` connects to `EventManager.event_triggered` once, in
`_ready()`, and does nothing except check: *"is the event that just fired
the current chapter's `completion_event`?"* If yes, it marks the chapter
complete, runs `next_chapter`'s `entry_effects` (or completes the case if
there is no `next_chapter`) — see `case_manager.gd`'s `_on_event_triggered`/
`_complete_chapter`/`_activate_chapter`. `CaseManager` never calls
`ConditionEvaluator.evaluate()` itself.

A completion event's own effects (like `test_case_chapter_01_complete`
above) are optional but recommended: `ContentValidator` warns about an event
with no effects (see `docs/event-system.md`), and a plain informational flag
is a cheap way to satisfy that and give future content something to
condition on ("has chapter 1 finished") without depending on `CaseManager`'s
internal bookkeeping.

### Why chapter completion is an Event, not a second evaluator

```
DECISION: A Chapter's completion is an existing Event (via a
"completion_event" id), not a Chapter carrying its own
"completion_conditions"/"completion_effects" fields evaluated directly by
CaseManager.

WHY IT IS NEEDED NOW: Milestone 1.6 needs *some* way to know the moment a
chapter's completion conditions become true, reactively, without per-frame
polling — the same requirement Milestone 1.5's Event system already solved.

ALTERNATIVES: Give Chapter its own completion_conditions/completion_effects
fields (closer to this milestone's brief's example schema) and have
CaseManager evaluate them by listening to the same five GameState signals
EventManager already listens to (flag_changed, evidence_added/removed,
location_changed, interaction_seen), re-checking the current chapter's
condition on each one.

WHY THIS OPTION WAS CHOSEN: The alternative works, but it requires
CaseManager to re-implement EventManager's reentrant, bounded fixed-point
evaluation loop (_is_evaluating / _needs_reevaluation / a cycle cap) to
handle the same hazard EventManager already handles: a chapter's own
entry_effects (running when it becomes current) can mutate GameState, which
re-triggers evaluation, which — without that guard — can recurse or drop a
follow-up completion. That is precisely "duplicate Event logic," which this
milestone's self-review checklist calls out by name. Routing chapter
completion through a real Event means CaseManager reacts to
EventManager.event_triggered — a single signal — and gets EventManager's
already-correct reentrancy handling for free: when a chapter's
entry_effects fire mid-evaluation, EventManager's own _needs_reevaluation
flag (already exercised by "event chains," see docs/event-system.md) picks
up any newly-satisfied chapter-completion event in the same pass.
CaseManager itself ends up with no condition-evaluation code at all.

IMPACT: A chapter's completion "conditions" and "effects" live in
data/events/, one file away from data/chapters/, instead of inline on the
chapter — one extra id (`completion_event`) to follow. In exchange,
CaseManager is ~120 lines with zero GameState-signal listening of its own,
and chapter completion inherits every already-tested Event guarantee
(idempotent "once" firing, correct save/load behavior, event chains) instead
of re-deriving them.

WHAT REMAINS OPEN: If a future case needs many chapters each with several
scoped events (not just one completion event), revisit whether a first-class
"case/chapter scope" condition leaf (e.g. {"chapter": "some_id"}) is worth
adding to ConditionEvaluator, instead of the current convention of a
chapter-entry-effects flag (see "Event/content scope" below). Not needed for
the two-chapter Test Case.
```

## Case/Chapter runtime state

`CaseManager` (`scripts/cases/case_manager.gd`, a new autoload) holds **no
persisted or cached state of its own** — every query re-reads `GameState`
live:

| What | Where it lives | Query |
|---|---|---|
| Current case id | `GameState.variables["case_id"]` (already set by `GameState.start_new_game()`, unchanged from Milestone 0) | `CaseManager.get_current_case_id()` |
| Current chapter id | `GameState.variables["current_chapter"]` (new; `""` for a flat case) | `CaseManager.get_current_chapter_id()` |
| Chapter completed? | `GameState.seen_interactions` key `"chapter_complete:<chapter_id>"` — the same "has this happened" set/`mark_seen`/`has_seen` API a `"once"` event's triggered state already uses (`"event:<id>"`) | `CaseManager.is_chapter_complete(id)` |
| Case completed? | `GameState.seen_interactions` key `"case_complete:<case_id>"`, same idiom | `CaseManager.is_case_complete(id)` |

Because all of this is already-serialized `GameState` state (`variables` and
`seen_interactions` both already round-trip through `SaveManager` — see
`docs/architecture.md`'s content/data table), **Case/Chapter progression
persists through save/load with zero changes to the save format.** Loading a
save that landed mid-Chapter-2 restores `current_chapter` directly (no
`entry_effects` re-run — those only run from a real transition, see
`_activate_chapter()`) and restores chapter 1's already-triggered completion
event from `seen_interactions`, so it correctly does not refire (the exact
same guarantee `docs/event-system.md` already documents and tests for a
`"once"` event surviving save/load).

## Event/content scope

Nothing stops `EventManager` from evaluating *every* loaded event regardless
of which case or chapter is active — events are still global/shared content
(see "Shared vs. case-specific content" below). Milestone 1.6 needed a way
to stop `test_case_chapter_02`'s content/completion from becoming reachable
while chapter 1 is still active, without inventing a new scoping mechanism.

The chosen approach is the smallest one available in the existing
vocabulary: a chapter's own `entry_effects` sets a flag
(`test_case_chapter_02_active`) the moment it becomes current, and anything
that should only be reachable during that chapter — the
`chapter_02_debrief` topic on Character B in `data/locations/test_hallway.json`,
and `test_case_chapter_02_complete`'s own conditions — requires that flag.
This is exactly the "no `unlock_topic`/`unlock_location`, just `set_flag` +
`condition`" decision `docs/architecture.md` already documents, applied one
level up. Concretely, this is what stops the trap the milestone brief warns
about: `talked_to_character_a_in_hallway` (chapter 1's own required
interaction) is naturally already true by the time a player reaches chapter
2, so chapter 2's completion event does **not** reuse it — it requires the
scope flag plus a chapter-2-only interaction (`chapter_02_debrief_done`)
instead.

No change to `ConditionEvaluator`, `EffectRunner`, or `EventManager` was
needed for this. See "What remains open" above for when a dedicated scope
condition would become worth adding.

## ID / namespacing convention

Every content category is still one flat namespace regardless of file/folder
(`docs/content-guide.md`, "General rules") — chapters and cases follow that
too. To keep future cases from colliding on short, tempting ids like `intro`
or `chapter_01`, this project's convention (not structurally enforced,
mirroring how filename subfolders are "for humans only" everywhere else) is:

- **Case id**: short and case-specific (`test_case`), since cases are rare
  enough that collisions are unlikely and a case id is often user-facing
  later (case-select screens, if this project ever builds one).
- **Chapter id**: `<case_id>_chapter_<NN>` (`test_case_chapter_01`) —
  guarantees no two cases' chapters can collide even if both happen to reach
  for "chapter_01".
- **Chapter-scoped event id**: `<case_id>_chapter_<NN>_complete` or similar,
  same prefix rule, since events remain one global namespace.
- **Topic / examine-point / `interaction_complete` ids** (`chapter_02_debrief`,
  `chapter_02_debrief_done`): do **not** need a case prefix — a topic id is
  only unique within its own NPC's `topics` list, and an
  `interaction_complete` id, while global, is already conventionally
  authored to read unambiguously (`talked_to_character_a_in_hallway`, not
  `talked_to_them`) — the existing Milestone 0-1.5 content already relies on
  this and adding a case-id prefix there would just be noise.

## Shared vs. case-specific content

Nothing new was built to formally separate "shared" from "case-specific"
content — `ContentDB` still loads every `data/` category unconditionally,
regardless of which case is active. Milestone 1.6 demonstrates the
distinction with folder convention only, the same "subfolders are for
humans" rule every other category already follows:

- **Shared/global**: `data/characters/`, `data/locations/`,
  `data/evidence/`, and the pre-existing `data/dialogue/*.json` /
  `data/events/test_events.json` — the Test Case reuses Character A/B, Test
  Room, Test Hallway, and `test_key` directly, exactly as `case_00_sandbox`
  does. Reusing them across two different cases (`case_00_sandbox` and
  `test_case` can each be started independently and get a fully independent
  playthrough — `GameState.start_new_game()` resets everything) is itself
  the proof that this content is genuinely case-agnostic sandbox content,
  not accidentally coupled to one case.
- **Case-specific**: `data/cases/test_case.json`,
  `data/chapters/test_case/*.json`, `data/events/test_case/*.json`, and
  `data/dialogue/test_case/*.json` — content that only makes sense in the
  context of this one case's chapter structure.

This is intentionally the smallest useful line to draw — see section 14 of
the milestone brief ("don't solve every future content-sharing problem
now"). A future case that needs genuinely private evidence/characters (not
just gated by a flag) would still load them from the same global
categories; nothing here prevents that, and nothing here builds real
per-case content isolation (see "Known limitations").

## Case initialization

`CaseManager.start_case(case_id)` is the one canonical way to start (or
restart) any case:

```
start_case(case_id)
    │
    ▼
GameState.start_new_game(case_id)   (unchanged — flags/evidence/location reset,
    │                                 case_id var set, exactly as Milestone 0)
    ▼
case has "starting_chapter"?  ──no──▶ done (flat case)
    │ yes
    ▼
_activate_chapter(starting_chapter)
    │
    ├── GameState.set_var("current_chapter", starting_chapter)
    └── EffectRunner.run(chapter.entry_effects)
```

`SaveManager.new_game(case_id)` calls this instead of
`GameState.start_new_game()` directly, so "New Game" for *any* future case
goes through the same chapter-aware path the Test Case uses — nothing
hardcodes `"test_case"` anywhere in `scripts/`. The title screen's default
case is still `case_00_sandbox`; reaching `test_case` for manual testing is
the debug panel's new "Start Case" field (see "Developer tools" below), not
a change to the primary New Game path.

## Case reset

`CaseManager.reset_case()` is `start_case(get_current_case_id())` — it
restarts whatever case is currently active from scratch. Because
`GameState.start_new_game()` already clears `flags`, `evidence_inventory`,
`variables`, and `seen_interactions` in full, this clears case progression,
chapter progression, case-specific flags/evidence, and event state (a
`"once"` event's triggered marker lives in `seen_interactions`) all in one
step — there's no separate "case state" to reset independently, because
none was ever created (see "Case/Chapter runtime state" above). This is a
developer-only affordance (the debug panel's "Reset Case" button, which
replaced Milestone 0-1.5's "Reset Sandbox State" button — same underlying
call, now case-aware).

## Developer tools

The Case Debugger's (F1) **Case & Chapter** tab shows the current case (with
`ACTIVE`/`COMPLETED` status), the current chapter, a per-condition `[x]`/`[ ]`
breakdown of why the current chapter hasn't completed yet (via
`CaseManager.explain_chapter_completion()`, which delegates entirely to
`EventManager.explain_event()` — the same `ConditionEvaluator.explain()`
grouping rules from `docs/architecture.md`, "Developer tools," apply
unchanged), its `next_chapter`, and the completed-chapters list. A chapter's
completion conditions can also be inspected as a nested tree (via its
`completion_event`) from the Inspector tab — see `docs/case-debugger.md`,
"Condition Inspector". Actions, all reusing real progression APIs rather than
duplicating them (per the milestone brief's explicit rule for developer
shortcuts):

- **Start Case** (case id field) — `CaseManager.start_case(id)`, stopping
  any active dialogue first (same "yanking state out from under a running
  dialogue" guard `docs/architecture.md` documents for Jump/Reset).
- **Jump** (chapter id field) — `CaseManager.jump_to_chapter(id)`: a
  teleport, exactly like the existing location Jump — sets the chapter and
  runs its `entry_effects`, bypassing whatever the previous chapter's
  completion would normally require. Does not mark anything complete.
- **Force Complete Current** (requires confirmation) —
  `CaseManager.force_complete_current_chapter()`: forces the current
  chapter's `completion_event` through `EventManager.force_trigger()`, the
  exact pipeline a real completion uses and the exact bypass-conditions
  behavior `docs/event-system.md` already documents for manually triggering
  any other event. `CaseManager`'s own `_on_event_triggered` handler does
  the rest — there is no separate "force-complete" transition code path.
- **Reset Case** (requires confirmation) — see "Case reset" above.

Chapter reset (resetting only the current chapter's own state, leaving
earlier chapters intact) is deliberately **not** offered — see
`docs/case-debugger.md`, "Known limitations", for why: there is no
structurally-enforced "this state belongs to chapter X" boundary to reset
against, only the flag-naming convention "Event/content scope" above
already describes.

## Content validation

`ContentValidator._validate_chapters()` (new) checks every loaded chapter:
`entry_effects` through the existing `_validate_effects()` (same checks a
dialogue action or event effect already gets), `completion_event`
references a known event (and warns if that event is `"repeatable"` — a
chapter should only complete once), and `next_chapter` references a known
chapter.

`ContentValidator._validate_cases()` (extended) additionally checks, only
when a case declares a non-empty `chapters` array (a flat case like
`case_00_sandbox` gets none of this — see "Flat cases" above): every id in
`chapters` is a known chapter; `starting_chapter` is set and is one of
`chapters`; and walking `next_chapter` from `starting_chapter` — bounded by
the case's own chapter count — never leaves the case's declared `chapters`
set and never cycles. This is the same "cheap structural smell, not a
completability proof" stance `docs/architecture.md`'s "Known limitations"
already takes for dialogue reachability and event self-reference — it does
not attempt to prove every chapter is reachable, only that the declared
chain doesn't obviously loop or point outside the case.

Duplicate chapter ids are caught for free — `ContentDB`'s duplicate-id
detection (`get_duplicate_id_issues()`) already runs per category regardless
of what the category is, and chapters are loaded through the exact same
`_load_json_dir()` every other category uses.

## A note on omitting vs. nulling fields

Chapter's `next_chapter` and `completion_event` are read with
`data.get(key, "")` (String default), so the correct way to leave either
absent is to **omit the key entirely** — not write `"next_chapter": null`.
Unlike a dialogue node's `"next"` (which `DialogueManager._show_node()`
explicitly treats `null` and `""` as equivalent for), Chapter/Case fields
here follow the plainer `dict.get(key, default)` convention
`docs/content-guide.md`/`gdscript-style.md` already use for every other
optional field in this project (locations, cases, events) — this doc calls
it out once because a chapter is the one place in this pass where "the last
one" needing an explicit absence is common enough to get it wrong.

## Known limitations

- **A chapter's completion event firing out of turn isn't fully prevented,
  only made unlikely by convention.** If a badly-authored future case's
  chapter-2 completion event's conditions became satisfiable while chapter 1
  is still current (skipping the scope-flag convention above),
  `EventManager` would still fire it and mark it triggered — but
  `CaseManager` would not advance chapters from it (it only reacts when the
  fired event matches the *current* chapter's `completion_event`), so the
  event would be "used up" (a `"once"` event, permanently triggered) without
  ever completing the chapter it was meant for. The scope-flag convention
  above is what prevents this in practice; nothing in `ContentValidator`
  proves a chapter's conditions can only become true once its chapter is
  current (the same "not a completability proof" stance as everywhere else
  in this project — see `docs/architecture.md`'s "Known limitations").
- **No content isolation, only folder convention.** Every case still shares
  one global id namespace per category; nothing stops a `test_case`-specific
  dialogue tree from being started by name from anywhere, including a
  different case. See "ID / namespacing convention" above.
- **Chapters have no "repeatable"/re-enterable concept.** A chapter
  completes at most once per case playthrough — matching the milestone
  brief's own framing of chapters as sequential progression, not a quest
  log. `jump_to_chapter()`'s "teleport, no completion marked" behavior is
  the only supported way to revisit one for testing.
- **Case/Chapter has no dedicated completion screen or UI beyond the debug
  panel.** Deliberately deferred — see "Phase" below and the milestone
  brief's explicit scope guard against final UI/campaign structure. Case
  completion is verifiable today via `CaseManager.is_case_complete()`, the
  debug panel, and `[CaseManager]` console log lines, matching
  `EventManager`'s own `[EventManager]` logging style.

## Phase — deferred

The milestone brief raises a "Phase" concept (multiple gameplay modes within
a chapter — investigation, interlude, deduction, etc.) but is explicit that
final gameplay structure hasn't been decided. **This pass deliberately does
not implement Phase.** A Chapter here is the smallest unit that already
demonstrates the whole architecture end-to-end (entry effects, chapter-
scoped content, a completion event, transition to the next chapter, case
completion) without inventing a gameplay-mode taxonomy nothing in this
project has designed yet. If a future case genuinely needs sub-chapter
phases, the same pattern this doc already establishes for chapters —
optional fields, an id, reuse of Conditions/Effects/Events, no new
evaluation loop — is the template to extend, not a reason to have built it
speculatively now.
