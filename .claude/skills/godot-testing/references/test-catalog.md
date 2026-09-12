# Test catalog — what's already covered, and what to add

`scenes/test/smoke_test.gd` is one file with one `_initialize()` that calls a
sequence of `_test_*` functions, each covering one system (some deliberately
continue from the state the previous one left, some deliberately reset first
— the comments above each function say which and why; preserve that when you
add to it). This table maps system → the function(s) that already exercise
it → the specific behaviors it pins down → what a change to that system
should add. Read the actual function before adding to it — this table is a
map, not a substitute for reading `smoke_test.gd:N` itself.

Every function referenced below lives in `scenes/test/smoke_test.gd`, run via
`.claude/skills/godot-development/scripts/verify.sh --script res://scenes/test/validate_content.gd --script res://scenes/test/smoke_test.gd`.

## `ContentValidator` / `ContentDB` — `_test_content_loaded`

Asserts every content category loaded at least the expected count, and —
this is the important one — that `content_db.get_last_validation_result()`
reports **zero errors and zero warnings** against the real sandbox content.
Any new content shape or new placeholder content must keep that true.

Add a check here when: you add a new content *category* (new top-level
`data/` folder) or a new bulk getter on `ContentDB` that other tooling will
rely on (`get_all_*_ids`).

## `ConditionEvaluator` — `_test_conditions`

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
section), or change `evaluate()`'s precedence/failure behavior at all.

## `EffectRunner` — exercised inline, no dedicated `_test_*`

Effects (`set_flag`, `add_evidence`, `remove_evidence`,
`mark_interaction_complete`) are asserted as *consequences* throughout
`_test_progression_flow` and `_test_event_system` (e.g. presenting the key
sets `hallway_unlocked`; `remove_evidence` is exercised via the dedicated
`test_effects_remove_evidence` dialogue tree, which exists purely for this
test and is never reachable through normal play — following that same
pattern for a new effect type, a small unreachable-by-players dialogue tree
or event dedicated to exercising it in isolation, is the established way to
test one action's wiring without depending on a longer content chain).

Add a check here when: you add a new effect `type` (also update
`ContentValidator._validate_effects()` and `docs/content-guide.md`'s actions
list — schema change) or change idempotency (does running it twice still
no-op correctly, like `add_evidence` on an already-held item).

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

## `DebugPanel` / scene wiring — `_test_scene_instantiation`

Not a simulated click (headless has no way to see a rendered click's
result) — instantiates `Main.tscn`/`TitleScreen.tscn` and asserts the
`mouse_filter` values the click-routing design requires, that a runtime
list rebuild (`UiUtil.clear_children`) leaves no stale nodes, and that
re-rendering the action list while `set_interactive(false)` never leaves a
button enabled. `DebugPanel` itself is instantiated and `open()`/`close()`
toggled with `visible` asserted — never visually confirmed to render
correctly (see `docs/architecture.md`'s "Known limitations" — a human should
press F1 in a running build after any DebugPanel change).

Add a check here when: you change an overlay's `mouse_filter` chain, add a
new overlay `Main.gd` wires up, or change what fields/buttons `DebugPanel`
exposes for a system this catalog covers.
