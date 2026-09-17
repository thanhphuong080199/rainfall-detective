# Prototype Evaluation Instrumentation & Audit (Milestone 1.14.2A/1.14.2B)

Makes the existing Prototype A (`docs/prototype-a.md`), B (`docs/prototype-b.md`)
and C (`docs/prototype-c.md`) prototypes easier to evaluate in a playtest and
safer to carry into **Milestone 1.15 — Prototype Evaluation & Core Loop
Specification**, without redesigning any of the three puzzles. Read
`docs/deduction-lab.md` ("Local playtest recorder") and
`docs/resolution-policy.md` first — this milestone adds no new autoload, no
new condition/effect/evaluator vocabulary, no production `GameState`/save
change, and does not decide which prototype (or combination) Milestone 1.15
should keep.

## Why this milestone exists

By Milestone 1.14 each prototype already recorded a rich, per-attempt event
log through `DeductionLabRecorder` (session/case metadata, sequence,
elapsed_ms, and prototype-specific payloads — `docs/deduction-lab.md`,
"Recorder schema") and already computed its own numeric `get_stats()` dict
(elapsed time, submission/failure counts, hints used, assistance/partner
counts). What was still missing for genuine playtest evaluation was:

1. **A compact, cross-run summary.** The raw log is complete but is a flat
   list of events a human has to read end-to-end; nothing turned it into the
   handful of numbers a facilitator actually wants after a session ("did
   they solve it, how long did it take, how many genuinely different things
   did they try, did they just keep guessing").
2. **Visibility into blocked/duplicate attempts.** This was the real gap —
   see below.

### What was previously unobservable

Every prototype already refuses (at no cost) a submission identical to one
that already failed — `docs/resolution-policy.md`'s anti-bruteforce pass
(Milestone 1.14). But that refusal path (`REASON_DUPLICATE_ATTEMPT` in A,
`REASON_DUPLICATE_THEORY` in B, the `blocked_duplicate`/
`REASON_DUPLICATE_CLAIM` paths in C) returned its "nothing counted" result
**without ever calling the recorder**. The refusal itself was correct and
untouched by this milestone; the problem was that a facilitator reading the
exported log afterward had **no way to tell the difference** between a
player who tried a candidate once and moved on, and one who mashed the same
already-failed submission five times in a row — exactly the "blind
trial-and-error" signal `docs/resolution-policy.md`'s own "Anti-bruteforce
note" (this milestone's brief) asks instrumentation to make observable.
Milestone 1.14.2A closes that one specific gap; it does not touch what gets
refused or why.

## Architecture — a summarizer on top of what already exists

```
                    Prototype A/B/C controller (unchanged formal-commit/duplicate-block logic)
                              │  already calls _record(event, payload) via its OWN recorder
                              ▼
                    DeductionLabRecorder (Milestone 1.10, UNMODIFIED — see docs/deduction-lab.md)
                              │  to_export_dict() — the same raw event log as before, plus 4 new event TYPES
                              ▼
                    PrototypeEvaluationSummary (scripts/deduction/prototype_evaluation_summary.gd)
                    summarize(export_dict) → per-run submission/incorrect/unique-candidate/
                    duplicate-blocked/hint/resolution counts, split at "prototype_started" boundaries
                              │
                              ▼
                    Prototype A/B/C debug scene (%RecorderStatusLabel: live get_stats() digest;
                    Export button: raw log + a sibling *_summary.json, both human-readable)
```

| Piece | File | Kind |
|---|---|---|
| `PrototypeEvaluationSummary` | `scripts/deduction/prototype_evaluation_summary.gd` | `class_name` static helper, pure/autoload-free, same shape as `DeductionLabPresenter`/`ResolutionPresenter` |
| Controllers | `prototype_{a,b,c}_controller.gd` | four new one-line `_record(...)` calls total (see below) — no other change |
| Scenes | `scripts/debug/prototype_{a,b,c}.gd` | `_render_recorder()` appends a live stats digest; `_on_recorder_export_pressed()` also writes a sibling summary JSON |

**No new autoload.** Same reasoning every other deduction-foundation doc
already gives: this is developer/analysis tooling for a handful of debug
scenes, not a system real gameplay depends on.

**`DeductionLabRecorder` itself is unmodified again**, exactly as every
prior prototype milestone kept it — its `record()`/`to_export_dict()`/
`export_to_file()` needed zero changes. The four new event *types*
(`attempt_blocked_duplicate`, `theory_blocked_duplicate`,
`timeline_blocked_duplicate`, `claim_blocked_duplicate`) are purely additive
vocabulary, the same way Prototype A/B/C each already added their own event
types on top of the Lab's original six session-signal events without
touching the recorder class. This is **not** a vocabulary *break* the way
Milestone 1.14.1's renames were (`docs/deduction-lab.md`, "Recorder
schema") — a consumer that doesn't know these four new types simply never
sees them; nothing about an existing type's meaning changed — so
`event_schema_version` stays `2`.

```
DECISION: The summarizer reads an already-exported event log after the
fact (summarize(export_dict)) rather than being wired into the controllers
as a second, parallel telemetry sink.

WHY: The brief requires instrumentation to be purely OBSERVATIONAL — it must
never be able to influence what a controller does. A summarizer that only
ever consumes a finished (or in-progress, already-recorded) export cannot,
by construction, feed back into grading, ResolutionPolicy, or a
DeductionSession: it has no reference to any of them. The only thing that
needed to change on the controllers was making the previously-silent
duplicate-block paths call the recorder they already had a reference to —
four one-line additions, not a new instrumentation channel.

IMPACT: PrototypeEvaluationSummary can be unit-tested entirely with
hand-built event-dict fixtures (no DeductionSession, no ContentDB, no
ResolutionPolicy) — see "Testing" below — and calling it, at any point,
provably cannot change a controller's next result (asserted directly by
`prototype_evaluation_summary_test.gd` and the new duplicate-telemetry tests
in each controller's own test file).
```

## What is recorded

Nothing new is recorded on the *happy path* — every existing event type
(`prototype_started`, `attempt_submitted`/`theory_batch_submitted`/
`timeline_submitted`/`claim_answered`, `formal_commit_*`, `hint_revealed`,
`prototype_completed`/`prototype_abandoned`, …) is exactly as
`docs/prototype-a.md`/`docs/prototype-b.md`/`docs/prototype-c.md`/
`docs/resolution-policy.md` already documented. The four new events are
emitted at the four existing "this exact candidate already failed, refuse
it" checkpoints (see "Recorder events" in each prototype's own doc for the
exact payload):

| Prototype | New event | Fires when |
|---|---|---|
| A | `attempt_blocked_duplicate` | Presenting a statement+evidence pair that already failed |
| B | `theory_blocked_duplicate` | Committing a theory identical to one that already failed |
| C (timeline) | `timeline_blocked_duplicate` | Checking a placement identical to any earlier failed one |
| C (claim) | `claim_blocked_duplicate` | Answering with a verdict+fact pair identical to one that already failed |

Each carries exactly the same candidate-identity payload as the
corresponding real submission event (`statement_id`/`evidence_id` for A,
normalized `drafts` for B, normalized `placements`/`answer`+
`justification_constraint_id` for C) — the SAME normalized identity each
controller already computed internally to decide whether to refuse the
resubmission (`_pair_key()`/`_theory_key()`/`_placement_key()`/
`_claim_key()`), reused rather than re-derived.

### `PrototypeEvaluationSummary.summarize(export_dict)`

Splits the event log at `prototype_started` boundaries (a recording can span
more than one run if the player restarts) and returns, per run:

```json
{
  "case_id": "proto_x_archive_ledger",
  "run": 1,
  "completed": true,
  "abandoned": false,
  "duration_ms": 142321,
  "submission_count": 3,
  "incorrect_submission_count": 2,
  "unique_candidate_count": 3,
  "duplicate_blocked_count": 0,
  "max_repeated_candidate_count": 0,
  "selection_change_count": 7,
  "hint_reveal_count": 1,
  "max_hint_level": 1,
  "partner_resolution_count": 0,
  "run_resolution_result": "guided"
}
```

- `submission_count`/`incorrect_submission_count` count the SHARED
  `formal_commit_started`/`formal_commit_failed` events — identical across
  A/B/C, so the summarizer needs no per-prototype branch for these two.
- `unique_candidate_count` is the size of the set of distinct candidate
  signatures seen among real submission events for this run (a `_pair_key`/
  `_theory_key`/`_placement_key`/`_claim_key` equivalent, computed from the
  payload rather than re-implemented). A blocked duplicate is, by
  definition, the SAME signature as the attempt that first failed, so it
  never inflates this count.
- `duplicate_blocked_count`/`max_repeated_candidate_count` answer this
  milestone's explicit asks directly: "whether the same failed answer was
  submitted repeatedly" (A: "evidence-spamming against a statement
  detectable"; B: "brute-force combination testing detectable"). A single
  candidate blocked 5 times in a row shows as `max_repeated_candidate_count:
  5` even if 2 OTHER distinct candidates were only tried once each.
- `completed`/`abandoned` come from the presence of `prototype_completed`/
  `prototype_abandoned` in the slice; a run ended by a restart before either
  fired is additionally flagged `superseded_by_restart: true` (never set on
  the last/still-active run).
- `run_resolution_result` prefers the authoritative value in
  `prototype_completed`/`prototype_abandoned`'s own `resolution` block
  (`ResolutionPolicy.get_summary()`) and falls back to the last
  `run_resolution_result`/`run_resolution_result_after` seen in the slice
  for a still-in-progress run.

`format_summary_lines(summary)` renders this as plain, deterministic text
(never localized — a developer tool, like every other Deduction Lab debug
surface) and `format_stats_line(stats)` does the same for a controller's own
live `get_stats()` dict, independent of whether recording is even on.

## Inspection / export

Reuses the existing per-prototype Recorder controls
(`%RecorderStartButton`/`%RecorderStopButton`/`%RecorderClearButton`/
`%RecorderExportButton`/`%RecorderStatusLabel`) — no new UI nodes, no `.tscn`
changes:

- **`%RecorderStatusLabel`** now also shows a live one-line digest of the
  CURRENT run (`PrototypeEvaluationSummary.format_stats_line(controller.
  get_stats())`) whenever a run is active — independent of whether recording
  is on, since it reads the controller directly, never the recorder's event
  log.
- **Export** now writes the raw recording exactly as before
  (`<session>_<case>.json`, unchanged) AND a sibling
  `<session>_<case>_summary.json` (`PrototypeEvaluationSummary.
  export_to_file()`, same directory, same filename-safety rule as
  `DeductionLabRecorder.export_to_file()` — see "Why this duplicates one
  tiny helper" below) — both reported in the status line. Neither file
  replaces or alters the other; the raw export is unchanged Milestone 1.10
  behavior.

Both are plain, pretty-printed JSON under `user://deduction_lab_recordings/`
— the same documented development-artifact location as the raw recordings,
never mixed with `user://save_game.json` or any other production save file.

```
DECISION: PrototypeEvaluationSummary duplicates DeductionLabRecorder's small
private _sanitize_filename_part() helper (~6 lines) rather than depending on
it.

WHY: That method is private (an underscore-prefixed static helper on a
DIFFERENT class) and DeductionLabRecorder is documented, repeatedly, across
three milestones' docs as "reused unmodified" / "completely unmodified" —
changing its visibility (even just to `static func` non-underscore) to serve
a second caller is a larger, less obviously safe edit than copying six lines
of character-whitelisting that cannot drift in a way that matters (both
copies implement the identical, simple "only [A-Za-z0-9_-] survives" rule,
and both are exercised by their own tests).

IMPACT: One tiny, inert duplication (flagged below, "Code duplication") —
not a shared dependency between the recorder and the summarizer, so a future
change to either file's filename rule cannot silently break the other.
```

## Safeguards — why this is purely observational

- **No grading changes.** Every new `_record(...)` call sits strictly AFTER
  the existing early-`return` decision that already refused the duplicate
  submission — it observes a decision already made, never makes one.
  `prototype_evaluation_summary_test.gd`'s real-controller tests and the new
  duplicate-telemetry tests in each `prototype_{a,b,c}_controller_test.gd`
  assert this directly: `present_evidence()`/`commit_theory()`/
  `submit_timeline()`/`answer_claim()` return **byte-identical** results
  (`JSON.stringify` equality) whether a recorder is attached or not.
- **No session/GameState mutation.** `PrototypeEvaluationSummary` never
  references `GameState`, `DeductionSession`, or `ResolutionPolicy` — it is
  a pure function of an already-captured `Dictionary`. It cannot mutate
  anything because it holds no reference to anything mutable.
- **No cross-prototype leakage.** Each Prototype A/B/C debug scene already
  owned its OWN `DeductionLabRecorder` instance before this milestone
  (`scripts/debug/prototype_{a,b,c}.gd`'s own `_recorder` field, never
  shared with the Lab's or another prototype's) — this milestone adds
  nothing that could change that. `_test_ab_c_recordings_do_not_leak_into_
  each_other()` asserts it directly with two independently-recorded runs.
- **Recorder-optional gameplay is unaffected.** Every `_record(...)` call
  (old and new) goes through the controller's own `_record()` private
  helper, which already no-ops when `_recorder == null` — the overwhelming
  majority of this project's own controller tests never attach a recorder
  at all, and none of them needed to change for this milestone.
- **No production analytics.** Still exactly what `docs/deduction-lab.md`
  already established: local files under `user://`, no network call, no
  player/machine identity, no external SDK, debug-build only
  (`OS.is_debug_build()`, inherited unchanged from the Lab/Prototype
  scenes' own `_ready()` gate).

## Testing

| File | FAST/FULL | Covers |
|---|---|---|
| `scenes/test/prototype_evaluation_summary_test.gd` | FAST + FULL | `PrototypeEvaluationSummary` alone from hand-built event fixtures (no ContentDB): empty/malformed exports, single-run counting, repeated-duplicate-does-not-inflate-unique-count, abandoned vs. completed vs. still-in-progress, multi-run splitting at a restart boundary without leakage, deterministic formatting, safe/round-tripping file export, purity (never mutates its input) — plus real-controller integration smoke tests for A/B/C proving the summarizer reads genuine recorder output correctly, and that two independently-recorded prototype runs never leak into each other's summary. |
| `scenes/test/prototype_a_controller_test.gd` (extended) | FAST + FULL | `attempt_blocked_duplicate` is recorded exactly once with the repeated candidate's identity, and attaching a recorder never changes `present_evidence()`'s returned result for a blocked duplicate. |
| `scenes/test/prototype_b_controller_test.gd` (extended) | FAST + FULL | Same for `theory_blocked_duplicate` / `commit_theory()`. |
| `scenes/test/prototype_c_controller_test.gd` (extended) | FAST + FULL | Same for `timeline_blocked_duplicate` / `submit_timeline()` and `claim_blocked_duplicate` / `answer_claim()`. |

All of the above are pure/autoload-free (fixture-driven, no scene tree),
belonging to both FAST and FULL like every other deduction-foundation unit
test — see `docs/testing.md`.

## Milestone 1.14.2B — audit findings

A targeted technical audit of the resulting A/B/C implementations, scoped to
state ownership, retry/reset, save/load, invalid-content handling, edge
cases, hard-coded assumptions, code duplication, test coverage and
debuggability (the milestone's own checklist). Grouped by what happened to
each finding.

### Fixed now

- **The duplicate/blocked-attempt telemetry gap itself** (this milestone's
  whole Phase A) — arguably also an audit finding in its own right: a
  developer reading an exported recording had no way to see "the player kept
  resubmitting the same wrong answer," which is precisely the behavior
  `docs/resolution-policy.md`'s anti-bruteforce pass exists to discourage.
  Fixed by the four `_record(...)` additions described above.

### Technical debt — defer

- **Real duplication across the three controllers' own plumbing.** See
  "Potential abstraction candidates" below — real, but not touched here per
  the milestone's explicit "do not prematurely unify A/B/C" constraint.
- **The recorder has no rotation or size cap** (`docs/deduction-lab.md`,
  "Known limitations" — pre-existing, unchanged by this milestone). A very
  long playtest session's export (raw log AND now the summary computed from
  it) both grow with the session; acceptable at this project's current
  scale.
- **`PrototypeEvaluationSummary._sanitize_filename_part()` duplicates
  `DeductionLabRecorder`'s private helper** (documented above as a
  deliberate, audited choice, not an oversight) — worth collapsing into one
  shared tiny utility IF a third caller ever needs the same rule, not before.

### Milestone 1.15 design decisions

- **Which prototype (or combination) becomes the real mechanic.** Out of
  scope for this milestone by explicit instruction — this instrumentation
  exists so that decision can be made from evidence (`unique_candidate_count`
  vs. `duplicate_blocked_count`, resolution outcomes, completion times
  across real playtest sessions) rather than intuition, but it does not make
  the decision itself.
- **Whether A/B/C's real duplication (see below) should ever be unified into
  a shared base/composition object** — depends entirely on which
  mechanic(s) Milestone 1.15 actually keeps; unifying three controllers when
  one or two may be deleted next milestone would be wasted, premature work.
- **Per-unit resolution budgets (3 standard + 2 assisted) staying fixed
  defaults** — already an open question in `docs/resolution-policy.md`,
  "Known limitations"; this audit found nothing new to add to it.
- **Whether/how prototype run summaries should feed a real analysis
  pipeline** (a spreadsheet import, a small local dashboard, …) beyond the
  plain JSON this milestone produces — genuinely a Milestone 1.15 "Core Loop
  Specification" question, not a technical one this milestone can resolve on
  its own.

### Potential abstraction candidates (NOT implemented)

Real, meaningful duplication exists across `prototype_{a,b,c}_controller.gd`
— documented here for Milestone 1.15 to decide, per the hard constraint
against introducing a shared framework preemptively:

- **Run-clock/telemetry plumbing.** `_clock_fn`/`_start_ticks`/`_init(clock_fn)`,
  `_record()`, `_record_transition()`, `_stats_with_resolution()` and
  `_previous_run_payload()` are byte-for-byte identical (or differ only in
  which "unit" index is passed) across all three controllers. This is the
  single most extractable candidate — a small composition object
  (`RunTelemetry` or similar) that each controller HOLDS (not inherits from)
  could own exactly these five members. Not extracted now because the
  milestone brief explicitly calls out "no new orchestration layers" and
  because whether all three controllers still exist after Milestone 1.15
  is not yet decided.
- **`has_progress()`/`abandon()`.** Same two-method shape, same "record
  prototype_abandoned only if there was real progress and it never
  completed" contract, different specific fields checked. Smaller and more
  case-specific than the telemetry plumbing above — lower priority.
- **`get_stats()`.** Same "elapsed_ms + counts" shape, different field
  names/semantics per prototype (A: `submissions`/`incorrect`; B:
  `attempts`/`failed`; C: `submissions`/`failed`/`claim_attempts`). The
  field NAMES themselves already differ for real reasons (B has drafts, not
  submissions in the A sense; C has two separate unit types) — unifying the
  shape without unifying the meaning would just be surface-level, so this is
  a weaker candidate than the two above.
- **The `*_blocked_duplicate` recording pattern this milestone just added.**
  Four call sites, near-identical shape, but each keyed off that
  controller's own private duplicate-key dictionary/method
  (`_failed_pairs`/`is_known_failed_pair`,
  `_failed_theory_keys`/`is_known_failed_theory`,
  `_failed_placement_keys`/`can_resubmit`, `_failed_claim_keys`) — the
  DUPLICATE-DETECTION logic itself was already prototype-specific before
  this milestone touched it, so this is not new duplication so much as a
  thin, consistent convention layered on top of existing prototype-specific
  state. Not a strong abstraction candidate on its own.

## Hard-coded assumptions

- **`PrototypeEvaluationSummary.CANDIDATE_SIGNATURE_KEYS`/
  `DUPLICATE_BLOCK_EVENT_TYPES`/`SELECTION_CHANGE_EVENT_TYPES`** are small,
  explicit, hand-maintained lists of the CURRENT three prototypes' own event
  vocabulary — classification: **harmless for current prototypes**. A future
  fourth prototype-style mechanic (or a Milestone 1.15 redesign of an
  existing one) would need one more entry per list; the summarizer degrades
  gracefully (an unrecognized event type simply contributes nothing to
  `unique_candidate_count`/`duplicate_blocked_count`/
  `selection_change_count`, never crashes) rather than silently
  misclassifying it as something else.
- **Every other hard-coded assumption already surfaced and classified by
  prior milestones' own docs was re-checked and found unchanged by this
  audit** — `docs/resolution-policy.md`'s fixed 3+2 failure budget, its
  "per-unit budgets are fixed defaults" limitation, Prototype B's
  single-shared-budget-per-batch design, and Prototype C's small,
  finite-but-not-impossible claim space. None of these are new findings;
  they are restated here only so this doc's own "hard-coded assumptions"
  section is complete without duplicating their full rationale — see each
  one's own doc for that.

## Known limitations

- **A summary is only as complete as the export it was computed from.** A
  recording that was Stopped, or never Started, before a run finished is
  missing whatever happened outside the recorded window — this mirrors
  `docs/deduction-lab.md`'s own recorder limitations exactly and is not a
  new gap introduced here.
- **No automated cross-session aggregation.** Each `summarize()` call
  describes ONE recorder export (one facilitator session, possibly several
  restarts within it). Comparing many playtesters' sessions against each
  other is a manual (or future Milestone 1.15) step — this milestone
  deliberately does not build a multi-session dashboard.
- **Still debug-build-only, still never wired through `Main.gd`** — this
  instrumentation inherits the exact same isolation stance as the Lab and
  all three Prototypes (`OS.is_debug_build()`, launched only from the
  Deduction Lab's own buttons).

## Recommended next step

**Milestone 1.15 — Prototype Evaluation & Core Loop Specification.** This
milestone deliberately does not begin any part of it — no mechanic is
chosen, no abstraction is built, no puzzle rule changes.
