# Deduction Lab (Milestone 1.10)

A **developer-only, mechanic-neutral** shell for inspecting and reading the
three non-canon prototype deduction cases (X/Y/Z — see
`docs/deduction-prototype-cases.md`). It exists so the deduction foundation
(`docs/deduction-system.md`) and its content can be read, exercised and
debugged **before any of Prototype A/B/C's actual player interaction
exists**, without biasing that later choice. Read `docs/deduction-system.md`
first — this doc adds no new condition/effect/proof vocabulary of its own,
only a viewer and a debug harness on top of what already exists.

**Non-canon, like the cases it shows.** Every case loaded here is
`metadata.canon: false` prototype material (`docs/deduction-prototype-cases.md`).
The Lab itself is development tooling, not a content editor and not shipped
gameplay — see "Isolation" below.

## Opening it

Press **F1** in a running debug build to open the Case Debugger, then its
**Deduction Lab** tab, then **Open Deduction Lab**. The Lab opens as its own
overlay on top of the Case Debugger (a child scene of `DebugPanel`, not a
separate top-level scene — see "Architecture" below). **Esc** closes the Lab
first if it's open, and only closes the Case Debugger itself once the Lab is
closed (the same "topmost overlay gets first refusal" stacking rule
`docs/architecture.md` already documents for `DebugPanel` itself).

It does not exist in an exported release build: `deduction_lab.gd`'s
`_ready()` checks `OS.is_debug_build()` first and returns immediately (no
signal connections, no input handling) if it's false — the identical
isolation `DebugPanel` already uses (`docs/case-debugger.md`). There is no
other path to it: it is never wired through `Main.gd`, and no production
scene references it.

Since Milestone 1.11, a dedicated **`%PrototypeLaunchRow`** (its own row
below the case controls, inside a horizontal `%PrototypeLaunchScroll`) has a
**"Launch Prototype A — Statement Contradiction"** button, opening
`scenes/debug/PrototypeA.tscn` (a further child scene of the Lab, with the
same `OS.is_debug_build()`/Esc-stacking isolation) defaulted to whichever
case the Lab currently has active. Since Milestone 1.12, an identical
**"Launch Prototype B — Clue Connection"** button sits next to it, opening
`scenes/debug/PrototypeB.tscn` the same way, and since Milestone 1.13 a
third **"Launch Prototype C — Timeline Reconstruction"** button opens
`scenes/debug/PrototypeC.tscn` the same way again. This row was split out of
the case row and wrapped in its own horizontal scroll container in Milestone
1.13 specifically because three full-length, Vietnamese-translated launch
buttons alongside the case picker and mode buttons no longer fit any
reasonably-sized window — a real regression only visible with a display
server, not caught by any headless scene test's `visible`/structural
assertions (see `docs/architecture.md`'s "Known limitations": headless tests
verify wiring, never pixels). A fourth prototype, or longer future
translations, scrolls instead of clipping off-screen. Launching any one of
the three hides the other two if they happened to be open (avoiding
overlapping prototype overlays on screen at once) without resetting their
progress — see `docs/prototype-b.md`/`docs/prototype-c.md`, "Entry and
lifecycle". None of this makes the Lab
itself mechanic-specific — Player Preview/Author Inspector are unchanged,
and all three prototypes always start a **fresh** run of their own, never
reusing or mutating the Lab's or each other's.
See `docs/prototype-a.md`/`docs/prototype-b.md`/`docs/prototype-c.md` for
the mechanics themselves. Since Milestone 1.14 all three share one
resolution policy (`docs/resolution-policy.md`): limited formal commits,
acknowledged assistance, partner resolution through the real evaluators, and
no game over. The Lab's own Player Preview / Author Inspector are unchanged
by it.

## Architecture — reuse, not a parallel system

```
                    Deduction Lab (scenes/debug/DeductionLab.tscn + scripts/debug/deduction_lab.gd)
                              │  owns
              ┌───────────────┼────────────────────┐
              ▼                                     ▼
   DeductionLabController                 DeductionLabRecorder
   (session ownership,                    (off by default, connects to
    switch/reset confirmation)             DeductionSession's own signals)
              │  reads case_def via ContentDB, holds ONE DeductionSession
              ▼
   DeductionEvaluator / TimelineEvaluator / DeductionValidator / DeductionSession
   (unchanged production code — every button here calls into this, nothing
    is reimplemented)
              │
              ▼
   DeductionLabPresenter (scripts/deduction/deduction_lab_presenter.gd)
   build_player_view()  → spoiler-safe, allow-listed view model
   build_author_view()  → complete, unfiltered debug view model
```

| Piece | File | Kind |
|---|---|---|
| `DeductionLabController` | `scripts/deduction/deduction_lab_controller.gd` | `class_name` `RefCounted`, pure/autoload-free |
| `DeductionLabPresenter` | `scripts/deduction/deduction_lab_presenter.gd` | `class_name` static helper, pure/autoload-free |
| `DeductionLabRecorder` | `scripts/deduction/deduction_lab_recorder.gd` | `class_name` `RefCounted`, pure/autoload-free (injectable clock/id/export dir) |
| The Lab scene | `scenes/debug/DeductionLab.tscn` + `scripts/debug/deduction_lab.gd` | a normal `Control` scene, instanced as a permanent child of `DebugPanel.tscn` |
| `DebugPanel` wiring | `scenes/debug/DebugPanel.tscn` + `scripts/debug/debug_panel.gd` | one new "Deduction Lab" tab with an "Open Deduction Lab" button |

**No new autoload.** `DeductionLabController`/`Presenter`/`Recorder` are
plain, autoload-free helpers exactly like `DeductionEvaluator`/
`DeductionValidator` — the same "no autoload" reasoning
`docs/deduction-system.md` already gives applies unchanged: there is one Lab
scene, not many unrelated scenes needing a shared service.

**No parallel game state.** The Lab reads deduction content only through
`ContentDB.get_deduction_case(id)` / `get_all_deduction_case_ids()` (the
production loader) and mutates progress only through `DeductionSession`'s own
methods, `DeductionEvaluator.commit_attempt()`/`request_hint()`, and
`TimelineEvaluator.evaluate()` — the exact APIs a future Prototype A/B/C
screen would call. No JSON is loaded directly by the UI, and no deduction
grading/validation/timeline logic is reimplemented anywhere in
`scripts/debug/deduction_lab.gd` or the three helper classes above it.
Production `GameState` and the save schema are untouched — deduction progress
here is exactly as persisted as it always was (not at all; see
`docs/deduction-system.md`, "Save/load (deferred)").

```
DECISION: DeductionLabController's start_case()/request_case_switch() take
the already-loaded case_def Dictionary, not a bare case id string, unlike the
milestone brief's sketch API.

WHY: Resolving an id to content would need either an autoload reference
inside a class this project's own convention keeps autoload-free (and which
would then trip the documented -s entry-script compile-order trap for
headless tests — .claude/skills/godot-development/references/cli-verification.md),
or a second, UI-owned content-loading path — both forbidden by this
milestone ("no direct JSON loading from the UI"). Taking case_def mirrors
exactly how DeductionEvaluator.commit_attempt() itself is already called.

IMPACT: The one place that resolves a case id is scripts/debug/deduction_lab.gd
itself (via ContentDB, a normal scene script, not a -s test entry point), the
same way debug_panel.gd already resolves ids for its own tabs.
```

### Isolation

- `OS.is_debug_build()` gates `_ready()` on both `DebugPanel` (already existed)
  and `DeductionLab` itself (added defensively, in case this scene is ever
  reparented elsewhere).
- No production scene, autoload, or save file references the Lab.
- No external analytics, SDK, or network call exists anywhere in this
  milestone's code — the recorder (below) writes one local JSON file, nothing
  else.

## Session lifecycle

`DeductionLabController` owns exactly **one** active `DeductionSession` at a
time, plus a pending-switch case (or none). Every case selection made through
the UI goes through its `request_case_switch()`:

- **No meaningful progress yet** (a fresh session, or none at all) → switches
  immediately: a brand-new, isolated `DeductionSession` for the requested
  case. Nothing carries over — not even re-selecting the *same* case id,
  which also gets a fresh session.
- **Meaningful progress exists** → the switch is deferred
  (`has_pending_switch() == true`) and a confirmation dialog appears.
  **Confirm** applies it (`confirm_case_switch()`, the same immediate-switch
  path). **Cancel** (`cancel_case_switch()`) leaves the current session
  **exactly** as it was — same object, same content, nothing reset.

"Meaningful progress" is defined once, in `DeductionLabController.
session_has_progress()`, purely by reading `DeductionSession`'s own public
getters (never a private field): any evidence opened, any hint level
revealed, any attempt logged (valid or not), any claim resolved/deduction
unlocked, or the case marked solved. Timeline **submissions** are not part of
this definition — `TimelineEvaluator` is pure and stateless, and
`DeductionSession` has no timeline-progress state to read (the "timeline
submitted" event is deferred to a future prototype screen per
`docs/deduction-playtest-plan.md`, "Instrumentation"). See "Known
limitations" below.

**Reset** (`reset_session()`) clears the current session's progress **in
place** (same case, same session object identity) through
`DeductionSession.reset()` itself — never a private mutation — and is also
gated behind the same has-progress confirmation.

**Mode toggle never mutates the session.** Switching between Player Preview
and Author Inspector only changes `DeductionLabController.get_mode()`; it
never reads or writes anything on the session.

**F1 hide/show.** `DeductionLab` is a permanent child of `DebugPanel`,
instantiated once and never freed or re-instantiated by
`DebugPanel.open()`/`close()`. Hiding the Case Debugger (F1, or Esc) only sets
`DebugPanel.visible = false`; since `DeductionLab` is its descendant, it stops
rendering too, but its own script instance — and the `DeductionLabController`
it owns — is never touched. Reopening restores it exactly as it was left,
including whether the Lab itself was open. This needs no explicit
snapshot/restore machinery; it falls out of normal Godot node-visibility
inheritance. (`DeductionLabController.snapshot()`/`restore()` still exist,
reusing `DeductionSession.to_dict()`/`load_dict()` — they're for tests and any
future need, not for this hide/show path.)

## Player Preview

A **spoiler-safe, content-comprehension** view — not a gameplay prototype.
Built exclusively from `DeductionLabPresenter.build_player_view(case_def,
session)`, which returns `{"view": ..., "handle_map": ...}`:

- `view` is an **explicit allow-list**, handed to every player-facing widget.
  It is never the raw case dictionary with fields hidden after the fact.
- `handle_map` maps an **opaque handle** (`"E3"`, `"C1"`, `"H0"`, …) to the
  real domain id, and is kept privately by `deduction_lab.gd` — never passed
  to a rendering widget. A click handler (e.g. "open this evidence") resolves
  its handle back to a real id only at the moment it calls a production API
  (`session.mark_evidence_opened(real_id)`).

Shown: the case's translated title/description and non-canon status;
suspects (name only); questions (text, resolved/unresolved); currently
available evidence (name always; full text, tags and any stated time only
once **opened**, via the real `mark_evidence_opened()`); statements and
hypotheses (always, since nothing in the contract gates their existence —
only their resolution status, tracked by the session); deductions/
explanations/the conclusion (**only once the session has resolved them** —
absent entirely before that); hint ladders, organized by the question they
restate at level 1, showing only as many levels as
`session.get_hint_level(target)` has actually revealed, with a "reveal next"
action that calls the real `DeductionEvaluator.request_hint()`; and timeline
events, each showing only an "explicitly known" time when a **required**
`fixed_time` constraint pins it (e.g. the credential-use anchor) — never a
`window`/`before`/`no_overlap`/`travel_time` constraint's details, and never
`ground_truth.solution_timeline`.

### Spoiler boundary — what never reaches Player Preview

Structurally banned from the `view` contract (checked recursively by
`deduction_lab_presenter_test.gd`, not just string-searched for): internal
domain ids; `structural_role`; `veracity`; `proof_sets`/`compatible`;
`resolved_by`; `unlock_requires`; `ground_truth`; deduction depth; `source`/
`certainty`/`misleading` (evidence provenance metadata, Author-only);
`speaker`'s raw suspect id (only a translated name is embedded); the authored
timeline solution and any hidden constraint; an unrevealed hint level; and
any locked/unavailable evidence or unresolved deduction/conclusion content.
Evidence supports search and an opened/unopened filter, entirely client-side
over the already-filtered `view.evidence` array.

Player Preview does **not** include evidence multi-selection, "present
evidence," a relation picker, proof submission, a clue graph/caseboard,
timeline drag-and-drop, or a final accusation/theory input — those belong to
Prototypes A, B and C respectively and must stay out of this shell so it
doesn't bias whichever gets built first (see `docs/deduction-playtest-plan.md`).

## Author Inspector

A **complete, explicitly unfiltered debug view** — `DeductionLabPresenter.
build_author_view(case_def, session, errors, warnings)` — clearly reachable
only via the Author Inspector mode toggle, which also reveals a dedicated
Author tab (validation status, metadata, ground truth, and the session's raw
`to_dict()`). Every tab (Suspects/Evidence/Claims/Timeline/Hints) renders the
same underlying data as Player Preview but through the unfiltered author
view instead: real ids, `structural_role`, full `veracity`, complete
`proof_sets`/`compatible` lists, `unlock_requires`, deduction depth
(`DeductionValidator.claim_depth()`), all four hint levels (including the
raw `deduction`/`question`/`evidence` references level 4 etc. carry), the
authored timeline's events/constraints and `ground_truth.solution_timeline`,
and the case's validation result (`DeductionValidator.validate_case()`,
called fresh, scoped to just this case — never filtered out of a global
`ContentValidator.validate()` result).

### Author-only debug actions

Every action calls the real production API — nothing here grades a proof,
checks a timeline, or picks a hint by itself:

| Button | Calls | Behavior |
|---|---|---|
| **AUTO-SOLVE PRIMARY PROOF** | `DeductionEvaluator.commit_attempt()` | Repeatedly commits each still-unresolved deduction/conclusion's **first authored proof set**, in a bounded fixed-point pass, until nothing more becomes provable. Generic across any case sharing (or not sharing) `credential_misuse_v2` — it never hard-codes a claim id, so it stays neutral between whatever content exists. |
| **AUTO-SOLVE ALTERNATE PROOF** | same | Same walk, but uses each claim's **last** proof set when it has more than one (its alternate), else its only one. |
| **REVEAL NEXT HINT** | `DeductionEvaluator.request_hint()` | Reveals the next level for the first required target whose ladder isn't exhausted yet. |
| **VALIDATE AUTHORED TIMELINE** | `TimelineEvaluator.evaluate()` | Runs `ground_truth.solution_timeline` through the real evaluator and reports `timeline_consistent`/`timeline_inconsistent` plus any violated constraints — read-only, no session mutation. |
| **RESET SESSION** | `DeductionLabController.reset_session()` | Same reset path as the main Reset button (confirmed the same way). |

Every action's status line shows the returned classification/category
directly (never a paraphrase), and `refresh()` re-renders every tab
afterward, so unlock/resolution state is always current. **No free-form
proof builder exists** — auto-solve always uses an authored proof set, never
an arbitrary player-chosen selection.

## Local playtest recorder

`DeductionLabRecorder` (`scripts/deduction/deduction_lab_recorder.gd`) —
**off by default**, owned by the Lab scene, not an autoload and not a
general analytics system. It connects to `DeductionSession`'s own signals
(`evidence_opened`, `proof_committed`, `claim_resolved`,
`deduction_unlocked`, `hint_revealed`, `case_solved` — see
`docs/deduction-system.md`, "Instrumentation") rather than reimplementing what
any of them mean, plus two events the UI records directly since they aren't
session signals: `mode_switched` and `session_reset`.

**Source tagging.** `deduction_lab.gd` calls
`recorder.set_current_source("player_preview" | "author_debug")`
immediately before any call that might trigger a signal, so every recorded
event is tagged by *how* it happened — a Player Preview interaction
(opening evidence, revealing a hint) or an Author-only debug action (a proof
auto-solved, a hint pulled from the Author tab, a session reset). This makes
author-tool activity **unmistakably** distinguishable from real playtest
behavior in the exported log.

### Schema (`schema_version: 1`, `event_schema_version: 2`)

Two independent version numbers, deliberately never merged into one:

- **`schema_version`** is the outer **envelope** — the top-level fields
  (`session_id`/`case_id`/`prototype`/`locale`/`started_at_utc`/`events`) and
  each event's own `sequence`/`elapsed_ms`/`type`/`source`/`payload` shape.
  Unchanged since Milestone 1.10 and still `1` — nothing about that
  structure has ever needed to change.
- **`event_schema_version`** is the **event vocabulary** — which `type`
  strings exist and what each one's `payload` keys mean. A consumer decides
  how to parse a given event from THIS number, never from `schema_version`.
  Added in Milestone 1.14.1 and set to `2`, because two real vocabulary
  breaks had already shipped under an unchanged `1`: Milestone 1.14 replaced
  Prototype B's per-round vocabulary with theory-batch events, and Milestone
  1.14.1 itself renamed several resolution-policy payload keys and one event
  type for clarity (see "v1 → v2 diff" below). A consumer that only checked
  `schema_version` had no way to notice either change; `event_schema_version`
  exists so it never has to guess again.

```json
{
  "schema_version": 1,
  "event_schema_version": 2,
  "session_id": "dbg-1234567890-42",
  "case_id": "proto_x_archive_ledger",
  "prototype": "deduction_lab",
  "locale": "vi",
  "started_at_utc": "2026-09-13T10:00:00Z",
  "events": [
    { "sequence": 1, "elapsed_ms": 0, "type": "session_started", "source": "player_preview", "payload": {"case_id": "proto_x_archive_ledger"} },
    { "sequence": 2, "elapsed_ms": 340, "type": "evidence_opened", "source": "player_preview", "payload": {"evidence_id": "e_door_log"} }
  ]
}
```

Recorded event `type`s: `session_started`, `mode_switched`,
`evidence_opened`, `hint_revealed`, `proof_committed`, `claim_resolved`,
`deduction_unlocked`, `case_solved`, `session_reset`, and (Author-only)
`timeline_validated` — all unaffected by the event_schema_version bump.
Every debug-only prototype (A/B/C) additionally emits the shared
resolution-policy vocabulary documented in `docs/resolution-policy.md`,
"Recorder events" — THAT vocabulary is what moved from v1 to v2. `sequence`
strictly increases from 1; `elapsed_ms` is milliseconds since `start()`, from
an injectable clock (default `Time.get_ticks_msec`, so non-decreasing exactly
the way that function already is in production). No player/machine identity,
filename, or network call appears anywhere — `session_id` is a locally
generated, opaque token (`_default_session_id()`), and both the clock and the
id generator are injectable for tests.

#### v1 → v2 diff (resolution-policy vocabulary only)

| v1 (Milestone 1.14) | v2 (Milestone 1.14.1) | Why |
|---|---|---|
| Event type `resolution_tier_changed` | `run_resolution_result_changed` | The old name never said *which* of the two independent concepts (the current unit's phase vs. the run-wide result) it described — only the run-wide result ever emits this event; see `docs/resolution-policy.md`. |
| Payload keys `tier`, `tier_before`, `tier_after`, `tier_changed`, `previous_tier` | `run_resolution_result`, `run_resolution_result_before`, `run_resolution_result_after`, `run_resolution_result_changed`, `previous_run_resolution_result` | Same reason, applied to every event that carries the run result (`formal_commit_started`, `formal_commit_succeeded`, `formal_commit_failed`, `assistance_accepted`, `partner_resolution_used`, `prototype_restarted`, `round_completed`). |
| Payload key `phase_after` | `current_unit_phase_after` | Names the CURRENT unit's own phase explicitly, never confusable with the run result above. |
| Payload key `failure_count` (on `formal_commit_failed`, meaning the current unit's own failures) | `current_unit_failures` | Was easy to misread as a run-wide count; it was always local to the unit. |
| Payload key `attempts_remaining` (Prototype B/C's `formal_commit_failed`; Prototype A already used its own `credibility_remaining` and is unchanged) | `standard_attempts_remaining` | Matches the renamed `ResolutionPolicy.get_standard_attempts_remaining()`. |
| `assistance_offered`/`partner_resolution_offered` payload key `tier` | `run_resolution_result` | Same rename, applied consistently. |

No event type was removed by this bump — every v1 resolution-policy event
still exists, several with renamed payload keys as above. A consumer reading
`event_schema_version == 1` should expect the OLD names; one reading `== 2`
must use the NEW ones. Nothing here retains a v1-shaped alias: an analysis
script that parsed `resolution_tier_changed`/`tier_before`/`tier_after`
against a real export has to switch to the v2 names, exactly the same way
Milestone 1.14's own switch from Prototype B's per-round events to
theory-batch events required (that break shipped, in hindsight, without
bumping any version number — this field exists so the next one doesn't
repeat that mistake).

#### Production core-loop recordings (Milestone 1.16, additive — still v2)

`ChapterRunRecorder` (a `DeductionLabRecorder` subclass, `prototype:
"core_loop"`) records the production chapter run with the SAME envelope and
versions. Its additions are purely additive — new event types and new payload
keys, never a rename or a changed meaning — so neither version moves: every
payload gains `run_id`/`chapter_id` (and `unit_id`/`mechanic` inside a
mechanic, `transition` for events committed with a checkpoint), and the new
chapter-level types are listed in `docs/core-loop-sandbox.md`, "Recorder". A
consumer that only knows v2 prototype events can read a core-loop export
unchanged and ignore the rest.

**Controls:** Start (begins a fresh recording, itself logging
`session_started`), Stop (pauses; keeps captured events), Clear (empties the
log without changing whether recording is on), Export.

**Export location:** `user://deduction_lab_recordings/<session_id>_<case_id>.json`
by default (`DeductionLabRecorder.DEFAULT_EXPORT_DIR`), pretty-printed JSON.
The session/case id parts of the filename are sanitized to `[A-Za-z0-9_-]`
only (anything else, including `/`/`..`, becomes `_`), so the file always
stays inside the requested directory. Export reports success/failure and the
resulting path in the Lab's status line; a blocked destination (e.g. a file
where a directory was expected) fails cleanly with an explanation instead of
crashing or silently overwriting anything.

## Test commands

Pure/autoload-free (both FAST and FULL):
```bash
.claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
  --script res://scenes/test/deduction_lab_controller_test.gd \
  --script res://scenes/test/deduction_lab_presenter_test.gd \
  --script res://scenes/test/deduction_lab_recorder_test.gd
```

Scene/integration (FULL only — needs a real scene tree):
```bash
.claude/skills/godot-development/scripts/verify.sh \
  --script res://scenes/test/deduction_lab_scene_test.gd
```

Both are already part of the repository's canonical FAST/FULL commands — see
`CLAUDE.md` and `docs/testing.md`.

## Known limitations

- **No timeline-submission progress tracking.** `TimelineEvaluator` is pure
  and stateless; `DeductionSession` has no "the player attempted this
  placement" state to read, so `has_progress()` cannot detect "meaningful"
  timeline work specifically (only a future prototype-C screen, which would
  add that instrumentation per `docs/deduction-playtest-plan.md`, changes
  this).
- **`OS.is_debug_build()`'s false branch is not exercised by the automated
  test suite** — every test in this repository runs as a debug build, so the
  release-mode gate is verified by code inspection (it mirrors
  `DebugPanel`'s own, already-relied-upon gate) rather than a headless run
  that actually flips it.
- **No visual-regression tooling**, same stance as the rest of this project
  (`docs/architecture.md`, "Known limitations"). Layout, wrapping and click
  routing are asserted by value-inspection and signal-emission in
  `deduction_lab_scene_test.gd`, not by rendering/screenshotting — see that
  doc's "UI click-routing is verified by value-inspection, not a simulated
  click."
- **Author Inspector's evidence/claim/timeline dumps are plain formatted
  text**, not a generic tree/graph widget — deliberately: this milestone
  explicitly excludes building a generic graph/content editor.
- **The recorder has no automatic rotation or size cap.** A very long
  session accumulates events in memory for the whole Lab session; acceptable
  at this project's scale (a handful of pilot sessions), the same "not
  over-built for a need that doesn't exist yet" stance taken elsewhere in
  this codebase.

## Explicitly deferred / out of scope

The Lab itself still stays mechanic-neutral and does not grow evidence
multi-selection, a clue-connection board, a proof-submission UI, or a
timeline board of its own — those live only in Prototype A's own scene
(`docs/prototype-a.md`, launched from the button above), Prototype B's own
scene (`docs/prototype-b.md`, launched the same way), and Prototype C's own
scene (`docs/prototype-c.md`, Milestone 1.13, launched the same way — select
an event, then place it into a candidate time slot; drag-and-drop was never
required and is not built). Also still deferred here: a relation picker
(deliberately out of scope for A/B/C — see `docs/prototype-b.md`, "What this
is not"), NPC reactions/consequences, production save/load integration for
deductions, production or canon case content, art/audio/polish, external
analytics or network telemetry, a generic graph/content editor, and choosing
a core mechanic. See `docs/deduction-playtest-plan.md` for how that
comparison is meant to be run now that A/B/C all exist.

## Content-comprehension pilot (procedure)

Before any A/B/C session protocol runs (`docs/deduction-playtest-plan.md`),
this Lab supports a much smaller, targeted check: **can a reader correctly
understand the two rules the whole exclusive-control proof depends on, using
only Player Preview, before any inference-mechanic UI exists to bias them?**

1. Open the Lab in Player Preview mode on one of X/Y/Z. Do not explain the
   case or mention the other two.
2. Have the tester open (read) the `credential_use_record`, `credential_custody`
   and `custody_continuity` evidence items (the "only entrance," now
   explicitly "found empty at the check" zone-closure rule — see
   `docs/deduction-prototype-cases.md`, "0.1") and the staging trio
   (`staging_sign`, `physical_rule_or_reference`, `staging_contradiction` —
   the illustrated "bends away from the side the force came from" rule).
3. **Before** showing any inference interaction (there isn't one to show yet
   in this milestone — that's the point), ask the tester to explain, in
   their own words:
   - the zone-closure rule ("why couldn't someone else have used it/been
     inside?");
   - the staging rule ("what does the bent part tell you, and why?").
4. Record, per rule: any misunderstanding (verbatim if possible); time needed
   to locate the relevant evidence item; whether they infer the intended
   direction of reasoning without outside specialist knowledge; and exactly
   which wording or the illustrated reference's phrasing caused confusion, if
   any.
5. Fix wording only by changing all three cases in lockstep (they share one
   proof graph and one reasoning pattern by design — see
   `docs/deduction-prototype-cases.md`, "1.6").

This is **content-clarity testing**, not a ranking of Prototype A vs. B vs.
C, and a handful of testers is not statistically sufficient to declare
anything about the mechanics themselves — only about whether the two taught
rules read clearly on their own. The later six-tester A/B/C rotation
(`docs/deduction-playtest-plan.md`) is a separate, qualitative usability
discovery exercise once a prototype exists to test, not a statistically
powered experiment either.
