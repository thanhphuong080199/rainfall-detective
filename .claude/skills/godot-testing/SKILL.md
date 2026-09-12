---
name: godot-testing
description: Testing, validation, and regression-prevention practices for Rainfall Detective's content-driven systems — GameState, ConditionEvaluator/EffectRunner, DialogueManager, Investigation, EventManager, CaseManager/Chapters, SaveManager, ContentValidator. Use this whenever you add a feature, fix a bug, refactor a system, edit anything under data/, or touch narrative progression (conditions, effects, dialogue, talk/examine/present/move, events, event chains, case/chapter completion, save/load) — before calling the change done, not just after. Also use when asked to write or extend tests, validate content, check for regressions, reason about soft-locks or dead-end progression, or decide what a change actually needs verified. Complements godot-development (which owns GDScript style and the verify.sh CLI mechanics) — this skill owns *what* to test, *why*, and how much is enough for a given change.
---

# Testing & validation — Rainfall Detective

This repo's core risk isn't "does the script parse," it's "did this change quietly
break a state transition somewhere else." Every piece of gameplay here —
Talk/Examine/Present/Move, Events, Chapters — is the same small machine reused
everywhere: a `condition` (`ConditionEvaluator`) gates something, an
interaction or an automatic Event runs `effects`/`actions`
(`EffectRunner`), that mutates `GameState`, and the mutation is what makes the
*next* condition true. A change that "parses and the happy path works" can
still leave a topic permanently locked, a chapter that completes twice, or an
event that fires a beat too early — none of which `verify.sh`'s import/boot
steps will ever catch, because that only proves the code *loads*.

Read `docs/architecture.md`, `docs/event-system.md`, and `docs/case-system.md`
before non-trivial work in the system they cover — this skill tells you what
to verify, not how each system works internally. `.claude/skills/godot-development`
owns GDScript conventions and the raw CLI mechanics (`verify.sh`, why exit
codes lie, how to write a `-s` test script) — read that skill for the *how*;
this one is the *what/why/how much*.

## The one mental model to keep in your head

```
condition  →  interaction / event  →  effect(s)  →  GameState  →  new condition(s) now true
```

Every "did the feature work" question in this project reduces to: did the
right side of that arrow chain happen, **and** does the same chain refuse to
fire before its left side is actually true? Testing only the first half is
the single most common way a regression here goes unnoticed — a mistyped
condition key (`ConditionEvaluator` fails closed) reads as "still locked,
fine" in a quick playtest, while a condition that's accidentally too loose
reads as "wait, this looks fine" right up until someone reaches it from a
state where it shouldn't have been available yet. So for anything gated by a
`condition` — a topic, a destination, an examine variant, an NPC's presence,
an event, a chapter's `completion_event` — check **both**:

- it becomes available/fires once its condition is genuinely satisfied, and
- it stays locked/silent right up until the last piece of that condition is
  true (not "probably," actually flip the last flag and check).

`scenes/test/smoke_test.gd` already does this pattern dozens of times (e.g.
`about_key` stays locked until `test_key` is presented; `character_a_moves_to_hallway`
doesn't fire until *both* `interaction_complete` and `has_evidence` are true).
New coverage should follow the same shape, not just assert the end state.

## Testing priority, in order

When a change touches several layers, spend effort in this order — earlier
items are cheaper to check and catch a wider class of mistakes:

1. **Broken/invalid content** — run content validation first, always. It's
   near-instant and catches the typo'd id or unknown condition key that would
   otherwise waste time debugging a "why won't this unlock" mystery two
   layers up.
2. **Progression correctness** — the transition above, both directions.
3. **Save/load correctness** — silent state corruption is the hardest class
   of bug to notice by playing normally.
4. **Conditions/Effects behavior** — shared primitives; a mistake here is
   multiplied across every topic/destination/event/chapter that uses them.
5. **Event behavior** — chains, trigger policy, character presence.
6. **Case/Chapter transitions** — entry/completion effects firing exactly
   once, scope flags.
7. **Investigation verb behavior** — Examine/Talk/Present/Move and the
   mid-dialogue guards.
8. **UI reflection** — does the screen/debug panel show the state correctly.
9. **Low-risk implementation details.**

Don't force every item for every change — a one-line label tweak in `data/`
only needs #1. A new condition leaf or effect type touches #1 through #4 at
minimum, because it's shared infrastructure. Match effort to blast radius.

## Workflow

1. **Identify what actually changed** — which system(s) in the table below,
   and whether it's a *content* change (new JSON, no new field/shape), a
   *behavior* change (existing script logic), or a *schema* change (new
   condition leaf, new effect type, new content field). Schema changes have
   the widest regression surface — see "Regression surface" below.
2. **Check existing coverage first.** `scenes/test/smoke_test.gd` already
   exercises most of this project's progression paths end to end — read
   `references/test-catalog.md` for which `_test_*` function already covers
   the system you're touching, so you extend it instead of duplicating setup.
3. **Add or update the smallest useful check.** A new `_check(...)` call
   inside the relevant `_test_*` function, in the same style already there
   (see the mental model above — assert both sides of the transition). Don't
   build a parallel test file or a fixture framework for this; the project
   has exactly two headless test scripts by design.
4. **Run verification proportional to the change:**
   - Only `data/*.json` edited, no new field/shape:
     ```bash
     .claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
       --script res://scenes/test/validate_content.gd
     ```
   - Anything else (script changes, new content shape, UI, a bug fix):
     ```bash
     .claude/skills/godot-development/scripts/verify.sh \
       --script res://scenes/test/validate_content.gd \
       --script res://scenes/test/smoke_test.gd
     ```
   `validate_content.gd` is content-only and fast; `smoke_test.gd` is
   authoritative and asserts **zero** `ContentValidator` errors *and*
   warnings on top of the full demo flow — treat a new warning it surfaces
   as a real regression, not noise (see "Content validation" below).
5. **Report what you tested and what you couldn't.** Only claim a check
   passed if you actually ran it — see "Final report" below. Headless runs
   cannot prove real click routing, layout, or visual correctness
   (`docs/architecture.md`, "Known limitations"); say so rather than
   guessing, and suggest the human run `godot --path .` for anything
   genuinely visual.

## Systems this covers, and the autoload/helper each check ultimately talks to

| System | Where it lives | Existing coverage |
|---|---|---|
| Game state | `scripts/core/game_state.gd` (`GameState`) | `_test_progression_flow`, `_test_conditions` |
| Conditions | `scripts/core/condition_evaluator.gd` (`ConditionEvaluator`) | `_test_conditions` |
| Effects | `scripts/core/effect_runner.gd` (`EffectRunner`) | exercised throughout `_test_progression_flow`/`_test_event_system` |
| Dialogue | `scripts/dialogue/dialogue_manager.gd` (`DialogueManager`) | `_test_progression_flow`, `_test_interaction_guards` |
| Investigation (Examine/Talk/Present/Move) | `scripts/investigation/investigation_manager.gd` (`Investigation`) | `_test_progression_flow`, `_test_interaction_guards` |
| Events | `scripts/events/event_manager.gd` (`EventManager`) | `_test_event_system` |
| Case/Chapter progression | `scripts/cases/case_manager.gd` (`CaseManager`) | `_test_case_system`, `_test_case_debug_tools` |
| Save/Load | `scripts/save/save_manager.gd` (`SaveManager`) | `_test_save_load`, plus the mid-chapter round trips inside `_test_case_system` |
| Content validation | `scripts/core/content_validator.gd` (`ContentValidator`) | `_test_content_loaded` (asserts zero errors/warnings in real content), `validate_content.gd` |
| Localization | `scripts/core/locale_manager.gd` (`LocaleManager`) | `_test_localization` |
| Debug tools | `scripts/debug/debug_panel.gd` | `_test_scene_instantiation`, `_test_case_debug_tools` |

Full detail per system — exactly what each `_test_*` function proves, and
what a change to that system should add — is in `references/test-catalog.md`.

## Regression surface — trace the chain, don't rerun everything

A change ripples along the dependency order these systems are already built
in (see `docs/architecture.md`'s autoload table). Two shapes come up
constantly:

```
GameState field/behavior change
    → ConditionEvaluator (reads GameState)
    → Investigation / DialogueManager (consumers of conditions/effects)
    → EventManager (listens to GameState's 5 signals)
    → CaseManager (listens to EventManager.event_triggered)
    → SaveManager (serializes whatever GameState now holds)
```

```
Content shape change (new condition leaf, new effect type, new JSON field)
    → ContentDB loader (does it even parse the new shape)
    → ContentValidator (does it validate the new shape — errors AND warnings)
    → docs/content-guide.md + docs/architecture.md (the tables there go stale otherwise)
    → smoke_test.gd (new behavior needs a new _check, per the godot-development
      skill's "keep docs and tests true" rule)
    → DebugPanel (does it need to display the new thing to stay useful)
```

Test the smallest meaningful slice of whichever chain you actually touched —
if you changed `GameState.set_flag`'s signal-emission behavior, check
`ConditionEvaluator`/`EventManager` consumers, not the entire event catalog
and every dialogue tree. If you added a brand-new autoload-level system, the
whole chain applies. See `references/soft-lock-and-regression.md` for the
save/load-specific and event-specific traps that don't fit a simple chain.

## Content validation is the cheapest net you have

`ContentValidator` (`scripts/core/content_validator.gd`) already checks nearly
every reference this project's content can get wrong — unknown ids, unknown
condition keys (fails closed, never silently unlocks), duplicate ids,
stacked conditions, unreachable dialogue nodes, missing fallback
`present_responses`/`examine_points` entries, and (for chapter-based cases)
bad chapter/completion-event references. It does **not** attempt to prove
content is *reachable* or *solvable* — see "Soft-lock risk" below for what
that gap means in practice.

`smoke_test.gd` asserts the real sandbox content produces **zero** errors and
**zero** warnings. That means: if your change makes `ContentValidator` print
a new warning against real content, that is a regression to fix, not a
message to shrug off — a "no generic present_responses fallback" warning, for
instance, means presenting unrelated evidence to that NPC does nothing at all
and gives the player no feedback, which is exactly the kind of soft dead end
this project can't afford to accumulate as placeholder content grows.

## Soft-lock risk — cheap checks, not a solver

This is a narrative game where required state can become permanently
unreachable if authored wrong (a chapter needs a flag nothing sets; evidence
gets removed before the one NPC who needed it; an NPC's "moved" conditions
aren't actually mutually exclusive). Don't try to prove completability —
that's explicitly out of scope for this project (`docs/architecture.md`,
"Known limitations"). Do trace the specific dependency by hand whenever you
add or change something gated: find the effect that's supposed to satisfy
the new condition and confirm a path reaches it. The concrete checklist and
the sandbox's own worked traps (chapter 2 deliberately *not* reusing chapter
1's completion interaction, for exactly this reason) are in
`references/soft-lock-and-regression.md`.

## Save/load: what actually round-trips

`GameState.get_save_dict()`/`load_from_dict()` persist exactly five things:
`current_location`, `visited_locations`, `evidence_inventory` (as `evidence`),
`flags`, `variables` (includes `case_id`, `current_chapter`), and
`seen_interactions` (the one array carrying `topic:`/`examine:`/`custom:`/
`event:`/`chapter_complete:`/`case_complete:` namespaced keys — this is how a
`"once"` event, a completed chapter, and a completed case all survive
save/load with **zero** save-format changes). If a change needs new persisted
state, ask first whether it actually fits one of those five buckets (a new
flag, a new `seen_interactions` key via `mark_seen`) before adding a new
`GameState` field + touching `get_save_dict`/`load_from_dict`/`SaveManager`'s
format — the existing systems were deliberately designed to avoid ever
needing that (see `docs/case-system.md`'s "no new persisted state shape").

One thing that does **not** round-trip: a `"repeatable"` event's false→true
edge-tracking is in-memory only (`docs/event-system.md`, "Known
limitations") — never write a test asserting that state survives a process
restart; only assert it survives within one process (which is what real
save→load during a single play session actually is).

For any save/load test: progress state → save → mutate/reset (`start_new_game`
or `case_manager.start_case`) → load → assert the restored values, **and**
assert loading did **not** re-run a one-time effect (chapter `entry_effects`,
a `"once"` event, chapter/case completion) — `_test_save_load` and the
mid-chapter round trips inside `_test_case_system` are the working templates.

## Test independence

Follow `smoke_test.gd`'s own pattern: point `SaveManager.save_path` and
`LocaleManager.settings_path` at throwaway `user://` filenames before
touching either, and delete them when done — every copy of this project
(including a git worktree) shares one real `user://` folder, so a stray write
lands in an actual player's save or settings. Reset to a known case
(`game_state.start_new_game(...)` or `case_manager.start_case(...)`) at the
start of any test function that needs clean state; only chain off a previous
function's leftover state deliberately and say so in a comment, the way
`smoke_test.gd` already documents which `_test_*` functions continue from
which (`_test_event_system` continues from `_test_progression_flow`;
`_test_case_system` resets via `start_case` specifically because it must not
depend on what `_test_save_load` left behind).

## Bug fix / refactor / new feature — the short version

- **Bug fix**: reproduce it as a `_check(...)` that fails first when
  practical, fix the code, confirm that check now passes, then run the
  proportional verification from "Workflow" above. Don't add a check that
  can't fail given the fix (meaningless coverage).
- **Refactor** (no intended behavior change): run the relevant existing
  `_test_*` functions *before* changing anything to confirm they currently
  pass, refactor, then confirm they still pass unchanged. If you can't run
  them before (e.g. the refactor and the test touch the same code), reason
  through what they assert and preserve it deliberately.
- **New feature**: identify the happy path, the one negative path that
  actually matters (locked-until / not-yet-triggered / not-yet-complete),
  save/load implications, and validation implications — then write the
  smallest set of checks covering those four, not maximum coverage.

## Failure handling

If a check fails: find out whether the implementation or the check's
expectation is wrong before touching either — don't weaken or delete a
failing check just to get back to green, and don't assume a pre-existing
failure unrelated to your change is safe to ignore (report it explicitly
instead). Only update a check's expectation when the behavior change was
actually intended.

## Final report

For any change that touched progression-relevant systems, close with a short
verification summary — but only list a line if you actually ran that check:

```
Content validation:     PASS/FAIL (validate_content.gd or smoke_test.gd's own assertion)
Automated tests:        PASS/FAIL (smoke_test.gd — N passed, N failed)
Progression flow:       what you specifically verified, in one line
Save/load:              verified / not applicable / not verified (why)
Manual/visual check:    not performed — ask the human to run `godot --path .` (when relevant)
```

Never state a step ran if it didn't.
