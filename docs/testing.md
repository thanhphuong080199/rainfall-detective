# Testing (Milestone 1.7)

How this project's automated safety net is organized, how to extend it, and
what it deliberately does not attempt. Read `docs/architecture.md`,
`docs/event-system.md`, and `docs/case-system.md` first for how the systems
under test actually work — this doc is about test *mechanics*, not the
`.claude/skills/godot-testing` skill's guidance on *what to test and why* for
a given change (read that skill for that; this doc explains the repository
structure the skill's advice now maps onto).

## Test organization

```
scenes/test/
├── validate_content.gd            content validation only, fast, scriptable exit code
├── test_helpers.gd                shared boilerplate (see below) — not a runnable test
├── conditions_test.gd             focused ConditionEvaluator tests
├── effects_test.gd                focused EffectRunner tests
├── events_test.gd                 focused EventManager tests (trigger/no-trigger, once, chain, scope, debug_reset_trigger)
├── duplicate_execution_test.gd    regression coverage for accidental double-firing
├── save_load_regression_test.gd   persistence regression coverage, isolated save file
├── negative_progression_test.gd   locked/insufficient-state paths that must NOT progress
├── dependency_analysis_test.gd    ContentValidator's dependency-reachability warnings + known-producer lookup
└── smoke_test.gd                  the critical-path / integration fixture (see below)
```

Before this milestone, everything except `validate_content.gd` lived in one
776-line `smoke_test.gd`. The concrete problem that created: adding a test
for one new Condition leaf or Effect type meant editing that one file, which
also carries the entire narrative walkthrough's setup/teardown ordering.
Every focused file above is now independently runnable
(`godot --headless --path . -s res://scenes/test/<name>.gd`), needs no
knowledge of what any other test file did first, and only needs a new
`_check(...)` call in the relevant existing function — or a new small
`_test_*` function in the same file — to extend.

**`smoke_test.gd` stays as the one critical-path / integration fixture.** It
is deliberately *not* where a new Condition/Effect check belongs. It proves
the full chain end to end with real dialogue and content — Talk → Examine →
obtain Evidence → Event triggers → world state changes → new content becomes
available → Chapter 01 completes → Chapter 02 activates → Chapter 02
progression → Chapter 02 completes → Case completes — continuing several of
its own `_test_*` functions from one another's state on purpose (see the
comment above each), because that continuity is exactly what proves the
*chain* works, not just each link in isolation. See
`.claude/skills/godot-testing/references/test-catalog.md` for what each of
its functions specifically pins down.

## Adding a new Condition or Effect test

1. New leaf condition shape → add a `_check(...)` (or a new `_test_*`
   function) to `conditions_test.gd`. Small deterministic setup
   (`game_state.start_new_game(...)` + a couple of `GameState` pokes) →
   `ConditionEvaluator.evaluate(...)` (loaded via `load()`, never referenced
   by bare class name — see the file's own header comment for why) → assert.
2. New effect type → the same shape in `effects_test.gd`: build a minimal
   effects list, run it through `EffectRunner.run(...)`, assert the
   resulting `GameState` (never a private method call — see
   `docs/godot-testing`'s "Avoid brittle tests"). Also add a case proving it
   behaves safely if the same effect (or effect list) runs twice — most
   effects in this project are meant to be idempotent.
3. Either way, also update: `ContentValidator`'s corresponding
   `_validate_condition()`/`_validate_effects()` branch, and
   `docs/content-guide.md`'s reference tables — this is a schema change with
   the widest blast radius in the project (see the `godot-testing` skill's
   "Regression surface").

No test file in `scenes/test/` needs a companion `.tscn` — each is a plain
`SceneTree` script run via `-s` (see
`.claude/skills/godot-development/references/cli-verification.md`).

## `test_helpers.gd`

A tiny `class_name TestHelpers` static toolbox — not a parallel gameplay
API, just what would otherwise be copy-pasted into every focused test file:

- `TestHelpers.isolate_save(save_manager, test_name)` / `isolate_locale(...)`
  — point `SaveManager`/`LocaleManager` at a throwaway `user://` file unique
  to that test, and delete any leftover file from a previous run. Every copy
  of this project (including a git worktree) shares one real `user://`
  folder — this must never be skipped in a test that touches either.
- `TestHelpers.finish(failures, pass_count)` — the
  `--- N passed, M failed --- / ALL TESTS PASSED` verdict block, returning
  the exit code to pass to `quit()`.

It holds no state of its own and never references another autoload by bare
name, so — unlike `ConditionEvaluator`/`ContentValidator`/`EffectRunner` —
it's safe to call directly by class name from a custom `-s` entry script.

## FAST vs FULL verification

Both reuse `.claude/skills/godot-development/scripts/verify.sh` — no
verification logic is duplicated anywhere else, CI included.

**FAST** — routine development, after a local change (skip import/load-all/
boot if `.godot/` is already built):

```bash
.claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/conditions_test.gd \
  --script res://scenes/test/effects_test.gd \
  --script res://scenes/test/dependency_analysis_test.gd
```

**FULL** — before finishing a milestone/refactor, and what CI runs on every
push/PR: content validation, every focused test, the critical-path fixture,
save/load regression, negative paths, plus the import/load-all/boot runtime
checks `verify.sh` always does unless skipped:

```bash
.claude/skills/godot-development/scripts/verify.sh \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/conditions_test.gd \
  --script res://scenes/test/effects_test.gd \
  --script res://scenes/test/events_test.gd \
  --script res://scenes/test/duplicate_execution_test.gd \
  --script res://scenes/test/save_load_regression_test.gd \
  --script res://scenes/test/negative_progression_test.gd \
  --script res://scenes/test/dependency_analysis_test.gd \
  --script res://scenes/test/smoke_test.gd
```

A change touching only `data/*.json` with no new field/shape only needs
FAST's content-validation step
(`--skip-import --skip-load-all --skip-boot --script res://scenes/test/validate_content.gd`
alone, per the `godot-development` skill) — see the `godot-testing` skill's
"Testing priority, in order" for how to scale effort to a change's actual
blast radius.

## CI

`.github/workflows/verify.yml` runs the exact FULL command above on every
`push` and `pull_request`. It downloads the official Godot 4.7.2 Linux
editor binary (matching `project.godot`'s `config/features`) and calls
`verify.sh` with `GODOT` pointed at it — no test or validation logic is
reimplemented in the workflow YAML. A regression `verify.sh` catches locally
fails the same way in CI.

## ERROR vs WARNING

`ContentValidator` (`scripts/core/content_validator.gd`) has always
distinguished these; Milestone 1.7 adds one more WARNING-only category
(dependency reachability, below) on top of the errors/warnings
`docs/architecture.md`'s "Content validation" section already documents:

- **ERROR** — a configuration that is *definitely* invalid: a broken id
  reference, an unknown condition key, a condition object stacking more than
  one check, a non-boolean flag value, and so on. These fail
  `validate_content.gd`'s exit code and are asserted at zero in
  `smoke_test.gd`.
- **WARNING** — a *static progression smell* that may have a legitimate
  exception: a missing fallback, an unreachable dialogue node, a
  self-resetting repeatable event — and now, a flag/evidence/interaction a
  condition requires that no known Effect in loaded content is capable of
  producing. Warnings never fail `validate_content.gd`'s exit code, but
  `smoke_test.gd` still asserts the real sandbox content produces **zero
  unexpected** warnings (see the next section for the one accepted
  exception) — a *new* warning appearing against real content is a
  regression to investigate, not noise to ignore.

## Progression dependency validation (`ContentValidator._validate_dependency_reachability`)

Cheap, best-effort, **not a solver** (see "Soft-lock safety philosophy"
below). For every condition anywhere in loaded content that requires a flag
to be `true`, evidence to be held, or an interaction to be marked complete,
it confirms *some* Effect somewhere in loaded content (a dialogue action, an
event effect, or a chapter's `entry_effects`) is at least capable of
producing it:

```
[ContentValidator] WARNING: Dependency check: a condition requires flag
"totally_unreachable_flag" to be true, but no Effect anywhere in loaded
content ever sets it — this content may be permanently unreachable
```

Deliberately narrow, to stay cheap and low-noise:

- Only `equals: true` (or omitted, which defaults to true) flag requirements
  are checked — `equals: false` is already satisfied by a flag simply never
  being set, the default state, so it needs no producing Effect.
- Only a top-level condition or one nested inside a top-level `"all"` counts
  as a requirement — a leaf inside `"any"` isn't a bug on its own (the other
  alternative may well be reachable), and `"not"` inverts meaning enough
  that "required" stops being well-defined. This mirrors the precedent
  already set by `_validate_repeatable_self_reset`'s own
  `_collect_flag_requirements` scoping.
- It does **not** attempt "chapter X depends on content scoped exclusively
  to chapter Y" (section 19's fourth example) — there is no first-class
  chapter-scope condition in this project to detect that from (see
  `docs/case-system.md`, "What remains open"); inferring it from flag-naming
  convention alone would be speculative and noisy, so it isn't implemented.
- It does **not** check whether the Effect it finds is itself reachable —
  only that one exists somewhere. That deeper trace is still the manual
  checklist in `.claude/skills/godot-testing/references/soft-lock-and-regression.md`.

**One accepted exception exists in real content today**:
`test_repeatable_pulse`'s `pulse_flag` condition is deliberately
test-scaffolding-only — driven purely by direct `GameState` pokes from test
code (see `events_test.gd`) to exercise the `"repeatable"` trigger policy,
never by any in-game Effect, the same way `test_effects_remove_evidence`'s
dialogue tree is deliberately unreachable through normal play (see
`docs/architecture.md`'s "Known limitations"). `smoke_test.gd`'s
`KNOWN_ACCEPTED_WARNINGS` and `dependency_analysis_test.gd` both name this
exact warning explicitly (not a blanket "ignore all dependency warnings") —
a second, unrelated dependency warning still fails both.

## Soft-lock safety philosophy

This project does **not** formally prove a case is solvable, and never will
by design (see `docs/architecture.md`'s "Known limitations" — the original
brief explicitly rules out building a theorem prover). Soft-lock risk is
instead reduced by several complementary, individually cheap defenses:

```
Content Validation (broken references, unknown keys, malformed shapes)
        +
Dependency Warnings (a required flag/evidence/interaction with no producer)
        +
Focused Tests (Conditions/Effects behave correctly in isolation)
        +
Negative Tests (locked/insufficient state genuinely stays locked)
        +
Critical-Path Tests (the one real chain the game currently has works end to end)
        +
Runtime Debug Tools (F1 panel: explain why anything is locked, right now)
```

None of these, individually or together, guarantee every future case is
completable — a required Effect can exist yet still be behind its own
unreachable trigger; two conditions can be individually valid yet mutually
exclusive in a way nothing here checks (see `docs/event-system.md`'s "Known
limitations" on NPC presence). Treat this layer as **raising the floor**,
not as proof.

## Critical-path coverage

`smoke_test.gd`'s `_test_progression_flow()` → `_test_event_system()` →
`_test_case_system()` sequence *is* this project's critical-path fixture
(section 17): starting `case_00_sandbox`'s flat flow, then continuing into
`test_case`'s two-chapter structure, ending at case completion. When
`case_00_sandbox`/`test_case`'s content shape changes, or a new
representative sandbox case replaces either, this is the sequence whose flow
needs re-deriving by walking the actual location/dialogue/event/chapter JSON
— never by guessing a path that used to work.

## Negative-path coverage

`negative_progression_test.gd` (section 18): an event that must not fire
without its full evidence requirement, a chapter that must stay active with
only partial completion conditions satisfied, a destination that must stay
unreachable (and refuse `move_to`) before its unlock condition, and
presenting the wrong evidence that must not fire the specific response's
side effect.

## Event-chain coverage

`events_test.gd`'s `_test_event_chain_fires_in_one_pass()` (section 13): one
state change (`add_evidence("test_key")`, with
`interaction_complete:character_a_ready_to_move` already set) that satisfies
two chained events' conditions, both firing in the same evaluation pass with
no further action in between — plus that neither fires more than once from
that single change. `_test_chapter_scoped_content_does_not_leak_into_unrelated_case()`
covers the scope-leak guarantee (section 12) by replaying chapter_01's exact
completion state inside the *flat* `case_00_sandbox` and confirming the
chapter-2-scoped topic still never appears.

## Save/load regression coverage

`save_load_regression_test.gd` (section 16), using its own isolated
`user://` save file: an exact round trip of every persisted field, a
triggered `"once"` event surviving save/reset/load without refiring, and a
mid-chapter-2 save/load that restores `current_chapter` directly without
re-emitting `chapter_activated`/`chapter_completed` for anything already
processed (see `docs/case-system.md`'s "no `entry_effects` re-run" on load).

## Duplicate-execution regression coverage

`duplicate_execution_test.gd` (section 15): a triggered `"once"` event's
fire count survives ten unrelated reevaluation passes unchanged; a real
chapter completion (and the `chapter_activated` it causes for the next
chapter) survives further redundant reevaluation without firing twice; case
completion likewise. Calling `EventManager.force_trigger()` twice on the
same event is deliberately **not** tested as a bug here — it's a documented
developer bypass that skips `trigger_policy` on purpose (see
`docs/event-system.md`, "Developer tools"); double-firing when *deliberately
told to* is that tool working as designed, not a regression in automatic
progression.

## Test isolation

Every focused test script starts from `game_state.start_new_game(...)` or
`case_manager.start_case(...)` at the top of each independent `_test_*`
function (see each file), and any member-level accumulator array (fired
event ids, activated/completed chapter ids) is explicitly `.clear()`ed at
the start of a function that asserts an absolute count against it — a
function that only needs a *delta* (count-before vs. count-after) doesn't
need to, since the comparison is self-consistent regardless of what came
before. No test file writes to the real `user://save_game.json` or
`user://settings.cfg` — see `TestHelpers.isolate_save`/`isolate_locale`
above.

## Manual verification checklist

Headless runs cannot prove real click routing, layout, or visual
correctness (`docs/architecture.md`'s "Known limitations";
`.claude/skills/godot-development/references/cli-verification.md` §7). After
a UI-affecting change, run `godot --path .` and manually confirm:

- [ ] Every button in `InvestigationView`'s action list actually responds to
      a click (not just that it renders).
- [ ] `DialogueBox`, `EvidenceInventory`, and `GameMenu` don't visually
      overlap or clip at the default window size.
- [ ] Dialogue advances/choice-selection feels responsive (click-anywhere,
      keyboard focus on the first choice).
- [ ] F1's Case Debugger opens, every tab switches and renders without
      visual overlap, and its actions (jump, trigger, start case, Condition
      Inspector, producer lookup) are reachable and legible — see
      `docs/case-debugger.md`.
- [ ] A full manual playthrough of the sandbox flow (see `README.md`, "The
      sandbox progression flow") still feels correct end to end.

This list stays short on purpose (see section 28/29 of the Milestone 1.7
brief) — it exists for what automated tests structurally cannot prove, not
as a substitute for the cheap automated checks above.

## Known testing limitations

- No screenshot/visual-regression tooling — deliberately out of scope while
  the UI is still prototype-level (see the manual checklist above).
- `ContentValidator` cannot tell whether the Effect it finds for a required
  flag/evidence/interaction is *itself* reachable — only that one exists.
- A `"repeatable"` event's false→true edge state is in-memory only, never
  persisted (`docs/event-system.md`) — no test asserts it survives a
  simulated process restart, only within-process save/load.
- `res://` directory iteration order isn't guaranteed, so no test relies on
  which of two same-named content files "wins" — only that `ContentValidator`
  reports the collision.
