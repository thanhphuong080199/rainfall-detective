# Test catalog — what's already covered, and what to add

As of Milestone 1.7, `scenes/test/` is several small, independent `-s`
scripts rather than one file — see `docs/testing.md` for the full
organization and rationale. `scenes/test/smoke_test.gd` remains one file
with one `_initialize()` that calls a sequence of `_test_*` functions, each
covering one system (some deliberately continue from the state the previous
one left, some deliberately reset first — the comments above each function
say which and why; preserve that when you add to it) — it is the
critical-path/integration fixture, not where a new Condition/Effect check
goes (see "Focused test files" below for those). This table maps system →
the function(s)/file(s) that already exercise it → the specific behaviors
pinned down → what a change to that system should add. Read the actual
function before adding to it — this table is a map, not a substitute for
reading the file itself.

Run the full suite via
`.claude/skills/godot-development/scripts/verify.sh --script res://scenes/test/validate_content.gd --script res://scenes/test/conditions_test.gd --script res://scenes/test/effects_test.gd --script res://scenes/test/events_test.gd --script res://scenes/test/duplicate_execution_test.gd --script res://scenes/test/save_load_regression_test.gd --script res://scenes/test/negative_progression_test.gd --script res://scenes/test/dependency_analysis_test.gd --script res://scenes/test/smoke_test.gd`
(docs/testing.md's FULL command) — see that doc for the FAST subset.

## Focused test files (add a new Condition/Effect/Event check here, not to smoke_test.gd)

| File | Covers |
|---|---|
| `conditions_test.gd` | Every `ConditionEvaluator` leaf/composite shape, both directions where meaningful, plus the fail-closed edge cases and the validator's stacked-check precedence rejection. Add a new leaf shape's test here. |
| `effects_test.gd` | Every `EffectRunner` effect type: resulting `GameState`, signal-emission-only-on-real-change, idempotency on repeat run, and a safe no-op for an unknown type. Add a new effect type's test here. |
| `events_test.gd` | Negative trigger (missing condition piece), positive trigger, a "once" event's fire count under repeated reevaluation, an isolated event-chain regression, a chapter-scoped topic not leaking into an unrelated case, and `debug_reset_trigger()`'s state transitions (Milestone 1.8). |
| `duplicate_execution_test.gd` | Regression coverage specifically for accidental double-firing: an event under redundant reevaluation, a real chapter completion (and the next chapter's activation) under redundant reevaluation, case completion likewise. |
| `save_load_regression_test.gd` | An exact round trip of every persisted field, a triggered "once" event surviving save/reset/load without refiring, and a mid-chapter-2 save/load that doesn't re-run entry/completion effects. Isolated `user://` save file. |
| `negative_progression_test.gd` | The paths where a bug could let a player skip required progression: event without required evidence, chapter with partial completion conditions, locked destination, wrong evidence presented. |
| `dependency_analysis_test.gd` | `ContentValidator`'s dependency-reachability WARNING checks — both the pure collector functions in isolation and an end-to-end check that real sandbox content produces zero *unexpected* dependency warnings — plus (Milestone 1.8) `find_flag_producers`/`find_evidence_producers`/`find_interaction_producers` against real content, and the pure `_effect_produces_*` predicates in isolation. |
| `test_helpers.gd` | Not a test — shared `isolate_save`/`isolate_locale`/`finish` boilerplate every file above uses. |

## `ContentValidator` / `ContentDB` — `_test_content_loaded`

Asserts every content category loaded at least the expected count, and —
this is the important one — that `content_db.get_last_validation_result()`
reports **zero errors and zero unexpected warnings** against the real
sandbox content (`KNOWN_ACCEPTED_WARNINGS` names the one documented
exception — `test_repeatable_pulse`'s deliberately test-only `pulse_flag`
dependency, see `docs/testing.md`). Any new content shape or new placeholder
content must keep that true, and a *second* unexpected warning still fails
this check.

Add a check here when: you add a new content *category* (new top-level
`data/` folder) or a new bulk getter on `ContentDB` that other tooling will
rely on (`get_all_*_ids`).

## `ConditionEvaluator` — `conditions_test.gd`

Pins down the properties that matter more than the happy path:

- `evaluate(null)` → true; an unknown key, an empty object, a non-Dictionary,
  and a non-array `all` all fail **closed** (never silently unlock).
- `"equals"` is a recognized modifier alongside `"flag"`, not an unknown key.
- `explain()` flattens a top-level `all` into one entry per part, but keeps
  an `any` as a single grouped entry (spelling out the alternatives with
  " OR ") — this is a debug-UI correctness property, not just a data check
  (`docs/architecture.md`, "The condition mini-language").
- A condition object stacking two checks (`{"flag": ..., "has_evidence": ...}`)
  is rejected by the validator, and the error names the check that would
  actually have won (`ConditionEvaluator.KEYS` order:
  `["all", "any", "not", "flag", "has_evidence", "visited_location",
  "examined", "interaction_complete"]` — see `COMPOSITE_KEYS`/`LEAF_KEYS` in
  `condition_evaluator.gd`), not just "this is invalid."
- Non-boolean flags never leak past `get_flag()`'s typed return; setting a
  flag to `false` still records it (so the debug panel and a save both show
  it).

Add a check here when: you add a new leaf shape (also update `LEAF_KEYS` +
`ContentValidator` + `docs/content-guide.md`'s conditions table in the same
change — this is a schema change, see the SKILL.md "Regression surface"
section), or change `evaluate()`'s precedence/failure behavior at all. This
file is independent of `smoke_test.gd` — it's the one place a new leaf
shape's test goes (see `docs/testing.md`).

`_test_explain_tree()` (Milestone 1.8) covers `explain_tree()` — the nested
ALL/ANY/NOT breakdown built for the Case Debugger's Condition Inspector
(`docs/case-debugger.md`). It's additive to `explain()`'s own flattening/
grouping behavior above, not a replacement — a new leaf shape's `evaluate()`
test still only needs `_test_leaf_shapes()`; only touch `_test_explain_tree()`
if you change what a tree *node* looks like (its `passed`/`children` shape).

## `EffectRunner` — `effects_test.gd`

Direct `EffectRunner.run(...)` calls against a fresh `GameState`, asserting
the resulting state (never a private method call): each effect type's happy
path, that a signal (`flag_changed`/`evidence_added`/`evidence_removed`/
`interaction_seen`) only fires for a REAL change (not a no-op re-run), that
`add_evidence`/`remove_evidence` are idempotent, that an unrecognized effect
`type` is a safe no-op (no state mutated), and that a whole effects list is
safe to run more than once with the same net result (chapters re-run
`entry_effects` on `jump_to_chapter`). `_test_progression_flow` and
`_test_event_system` in `smoke_test.gd` still exercise effects as
*consequences* of real content (e.g. presenting the key sets
`hallway_unlocked`) — that integration-level coverage is complementary, not
redundant with this file's isolated unit-level checks.

Add a check here when: you add a new effect `type` (also update
`ContentValidator._validate_effects()` and `docs/content-guide.md`'s actions
list — schema change) or change idempotency (does running it twice still
no-op correctly, like `add_evidence` on an already-held item). This file is
independent of `smoke_test.gd` — it's the one place a new effect type's test
goes (see `docs/testing.md`).

## `DialogueManager` / `Investigation` — `_test_progression_flow`, `_test_interaction_guards`

`_test_progression_flow` is the fullest single test in the file — it's the
"critical path" for `case_00_sandbox`: talk (before/after a flag flips a
choice's availability) → examine (grants evidence, sets a flag) → repeat
examine (variant resolves to "after," no duplicate evidence) → a second
examine point → present (specific match unlocks a topic + a destination) →
present (generic fallback) → move both directions → another examine (an
`examined`-gated flavor variant with **no** evidence, proving that condition
doesn't need a flag) → present to a second NPC → an `all`-gated topic
(needs two evidence items) → an `interaction_complete`-gated topic. When
`case_00_sandbox`'s content changes shape, or a new representative sandbox
case replaces it, this is the function whose flow needs re-deriving — walk
the location/dialogue JSON the same way this function does, verb by verb,
rather than guessing a new path.

`_test_interaction_guards` is the correctness guarantee behind the UI
convenience in `InvestigationView`: a verb (examine/talk/move) rejected
because `DialogueManager.is_active` must mutate **no** state at all — not
mark anything seen, not grant evidence, not change location. Also covers
`DialogueManager.stop()` as the escape hatch and an unknown dialogue id
failing `start()` cleanly.

Add a check here when: you add a new verb, change variant/present_response
resolution order, or change what counts as "busy" (`Investigation._is_busy()`).

## `EventManager` — `_test_event_system`

Continues directly from `_test_progression_flow`'s end state (test_room,
character_a present, holding `test_key`/`test_badge`, `hallway_unlocked`
true) specifically to prove events fire off state real gameplay actions
built up, not just hand-set flags. Covers, in order:

- an event with two conditions (`interaction_complete` + `has_evidence`)
  firing exactly when the second one becomes true from a real Talk action;
- an **event chain**: a second event whose only condition is a flag the
  first event's effect just set, firing in the same evaluation pass with no
  further player action;
- character presence changing as a pure consequence of the flag flip (no
  new code — the NPC's own presence `condition` in a second location's JSON
  now passes);
- new content becoming available off the same flag (an examine variant);
- a `"once"` event **not** refiring on an unrelated later state change;
- `EventManager.force_trigger()` succeeding for a known id (bypassing
  conditions) and failing cleanly for an unknown one;
- `"repeatable"`: fires on a false→true transition, does **not** refire
  while the condition stays true through an unrelated change, and fires
  again on the next false→true transition.

Add a check here when: you add an event, change `trigger_policy` semantics,
or touch the fixed-point evaluation loop (`_evaluate_all()` /
`MAX_EVALUATION_CYCLES`) — at minimum re-verify one existing chain still
resolves in one pass and the cycle cap still logs instead of hanging.

`events_test.gd` (independent, resets per `_test_*`) adds: negative trigger
(has_evidence still missing → no fire), positive trigger, an isolated event
chain proven to fire both events in one pass, a chapter-scoped topic
confirmed absent from an unrelated flat case, and a "once" event's fire
count checked against ten unrelated reevaluation passes.
`duplicate_execution_test.gd` extends that last check to chapter/case
completion specifically (a real completion, then redundant reevaluation,
asserting `chapter_completed`/`case_completed`/`chapter_activated` signal
counts stay put) — add a check there instead of here for a new "does this
fire more than once" regression.

## `CaseManager` — `_test_case_system`, `_test_case_debug_tools`

Deliberately calls `case_manager.start_case("test_case")` to reset state
first — it must not depend on whatever `_test_save_load` left behind. Covers
the full two-chapter Test Case: starting chapter activation, a completion
explanation reporting unsatisfied conditions with a breakdown, a **save/load
round trip mid-chapter** (chapter not falsely marked complete after
loading), completing chapter 1 via its real `completion_event` → automatic
activation of chapter 2 (`entry_effects` running, a chapter-scoped topic
becoming reachable only now), a **second** save/load round trip mid-chapter-2
(chapter 1 not un-completed, `chapter_completed` not re-firing), completing
chapter 2 → case completion (`case_completed` firing, `get_completed_chapters`
listing both) — then confirms a flat case (`case_00_sandbox`) is entirely
unaffected (`get_current_chapter_id()` stays `""`,
`force_complete_current_chapter()` fails gracefully).

`_test_case_debug_tools` covers `jump_to_chapter` (teleport — runs
`entry_effects`, does **not** mark the skipped chapter complete),
`force_complete_current_chapter` (forces the real `completion_event` through
`EventManager.force_trigger()`, so it still actually completes the chapter
and cascades to case completion), and `reset_case`.

Add a check here when: you add a chapter/case, change how completion is
detected, or change what `entry_effects`/`next_chapter` do on transition —
the two things to specifically re-verify are "entry effects run exactly
once per real transition" and "a completed chapter doesn't re-fire
`chapter_completed` after a load."

## `SaveManager` / `GameState` persistence — `_test_save_load` (+ the round trips inside `_test_case_system`)

Captures location/evidence/flags/`seen_interactions` before saving, resets
via `start_new_game`, loads, and asserts every captured value came back —
including that a triggered `"once"` event's state survived and did **not**
refire just because reload re-evaluates every event against the restored
(still-satisfying) state. This is the test that actually proves
`is_event_triggered()` wins over "conditions still true" after a load.

Add a check here when: you add anything that needs new persisted state —
first check whether it actually needs a new field (see SKILL.md's "Save/load"
section) before assuming it does.

`save_load_regression_test.gd` (independent, own throwaway save file) is the
dedicated persistence suite: an exact round trip of every persisted field,
the "once" event / no-refire guarantee above repeated in isolation, and a
mid-chapter-2 save/load specifically checked to NOT re-emit
`chapter_activated`/`chapter_completed` for anything the save already
reflects (see `docs/case-system.md`'s "no `entry_effects` re-run" on load).
Prefer adding a new persistence regression check there — it doesn't require
replaying the rest of the narrative walkthrough first.

## `LocaleManager` — `_test_localization`

Confirms the CSV actually loaded into real `Translation` objects (not just
"a dictionary somewhere"), that a static UI key and a content-driven key
both resolve correctly in both locales, that an unsupported locale is
rejected (fails closed, mirroring `ConditionEvaluator`'s stance), that the
preference persists to a `ConfigFile`, that an **already-instantiated**
`InvestigationView` re-renders correctly on a live locale switch (not just a
freshly-opened one), and that `ContentValidator._validate_translatable`
reports a key missing from either locale.

Add a check here when: you add a new translatable field type, a new locale,
or a new screen that should react live to `locale_changed`.

## `DebugPanel` (Case Debugger) / scene wiring — `_test_scene_instantiation`

Not a simulated click (headless has no way to see a rendered click's
result) — instantiates `Main.tscn`/`TitleScreen.tscn` and asserts the
`mouse_filter` values the click-routing design requires, that a runtime
list rebuild (`UiUtil.clear_children`) leaves no stale nodes, and that
re-rendering the action list while `set_interactive(false)` never leaves a
button enabled. `DebugPanel` itself is instantiated and `open()`/`close()`
toggled with `visible` asserted — never visually confirmed to render
correctly (see `docs/architecture.md`'s "Known limitations" — a human should
press F1 in a running build after any DebugPanel change). The Case
Debugger's own underlying logic (Milestone 1.8) — `explain_tree()`, the
`find_*_producers()` lookups, `debug_reset_trigger()` — is unit tested where
it lives (`conditions_test.gd`, `dependency_analysis_test.gd`,
`events_test.gd` respectively, per the rows above), not here; this test stays
scoped to scene instantiation and click-routing plumbing, per
`docs/case-debugger.md`'s own "no pixel-perfect UI tests" stance.

Add a check here when: you change an overlay's `mouse_filter` chain, add a
new overlay `Main.gd` wires up, or change `DebugPanel`'s node structure in a
way that could break instantiation (a renamed unique name, a removed
`ConfirmationDialog`, etc.). A new tab's *data* (what it displays, what
action it performs) belongs in the underlying system's own focused test file
instead — see `docs/case-debugger.md`, "Automated test coverage".
