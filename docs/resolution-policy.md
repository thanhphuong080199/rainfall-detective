# Resolution Policy & Anti-Bruteforce Pass (Milestone 1.14; hardened in 1.14.1)

How the three debug-only deduction prototypes — A (`docs/prototype-a.md`), B
(`docs/prototype-b.md`) and C (`docs/prototype-c.md`) — make blind
trial-and-error an inferior strategy **without** hard game-over states or
blocked progress. Read `docs/deduction-system.md` (the evaluator contract) and
`docs/deduction-lab.md` (the recorder) first.

After playing all three, the tentative structure is:

```
B — frequent core deduction
A — high-stakes NPC confrontation
C — end-of-chapter timeline reconstruction
```

Before this milestone every prototype accepted unlimited submissions, so the
evaluator itself could be used as an oracle: submit, read the category, try
the next combination. This milestone applies one shared model to all three.

```
Explore or Draft            (free — no correctness oracle)
→ Formal Commit             (the only action the evaluator grades)
→ success, or coarse logical feedback
→ after repeated failures: Assisted Mode (acknowledged, targeted help)
→ after more failures: partner/system resolution through the real evaluator
→ the run records HOW it was solved: Independent / Guided / Assisted
```

**Brute force is not made technically impossible.** This is an offline game,
so a player can always restart. The goal is that guessing is slow,
non-oracular, recorded, and eventually replaced by guided resolution that
still explains the logic. See "Why this is a design incentive, not security"
below.

## Architecture

| Piece | File | Kind |
|---|---|---|
| `ResolutionPolicy` | `scripts/deduction/resolution_policy.gd` | `class_name` `RefCounted`, pure, autoload-free, deterministic, serializable |
| `ResolutionPresenter` | `scripts/deduction/resolution_presenter.gd` | `class_name` static helper: localized status, notices and completion lines |
| Controllers | `prototype_a_controller.gd` / `prototype_b_controller.gd` / `prototype_c_controller.gd` | each owns ONE policy per run, decides what counts, records telemetry |
| Presenters | `prototype_a_presenter.gd` / `prototype_b_presenter.gd` / `prototype_c_presenter.gd` | add `resolution_status`, gated `assistance`, `completion_lines` |
| Scenes | `scenes/debug/Prototype{A,B,C}.tscn` | header `%ResolutionStatusLabel`, body `%AssistancePanel`, footer `%ResolutionActionsRow` |

**No new autoload, no production `GameState`/save change, no evaluator
change.** The policy is intentionally small and is not a gameplay framework.
It has no knowledge of statements, evidence, deductions, timeline events,
`GameState` or the recorder.

```
DECISION: The policy returns a transition dictionary from every register_*()
call. ResolutionPolicy.transition_events(transition) turns it into
[{type, payload}], and the CONTROLLER records those events with its own unit
context. The policy never touches a recorder.

WHY: The brief requires "recorder events emitted by controllers, not by
hidden global state". Each controller already owns its recorder and its
event vocabulary. A shared static describer stops the three controllers
from copying the "tier changed / assistance offered / partner offered" logic.

IMPACT: All three prototypes emit identical resolution events in the same
order, and the policy stays trivially unit-testable.
```

```
DECISION: The RUN RESOLUTION RESULT is run-wide and one-way
(get_run_resolution_result()). The failure budget and CURRENT UNIT PHASE
(get_current_unit_phase(), get_current_unit_failures(),
get_standard_attempts_remaining(), get_assisted_attempts_remaining()) are per
resolution unit. Units: Prototype A = each testimony part (round);
Prototype B = the single batch theory; Prototype C = the timeline, then the
claim justification. begin_next_unit() is refused unless the current unit is
resolved, and resets ONLY the local phase/counters/assistance flag — never
the run result.

WHY: The brief sets limits "per puzzle or formal resolution unit" but the
result "one-way within a run". Keeping a per-run budget would force partner
resolution onto every later part after one hard part. A per-unit result
would let a later clean part hide an earlier assisted one. Milestone 1.14.1
went further and gave the two concepts explicit, un-confusable names
(`run_resolution_result` vs. `current_unit_phase`) after a review found the
ORIGINAL Milestone 1.14 code already kept them logically separate, but named
both ambiguously enough ("tier", "phase") that a future call site could
plausibly conflate them — see "Local unit state vs. run result" below.

IMPACT: Credibility in A resets to 3/3 for part 2 while the run result stays
at whatever it reached. "Three failed formal commits → Assisted" counts
failures across the whole run: two failures in part 1 plus one in part 2
make the run result Assisted, even though that unit's own budget is not
exhausted. Round 2 must never be LABELED "Assisted" in its own status text
merely because round 1 used help — see "Local unit state vs. run result".
```

## Local unit state vs. run result

A Milestone 1.14 review flagged this as the one real ambiguity worth
hardening: `ResolutionPolicy` always kept the run-wide result and the
current unit's own phase as two separate internal fields — begin_next_unit()
already reset only the local ones — but the ORIGINAL accessors
(`get_tier()`, `get_phase()`) and several recorder payload keys (`tier`,
`tier_before`/`tier_after`, `phase_after`, `failure_count`,
`attempts_remaining`) were generic enough that a future call site could
plausibly show the wrong one, or a reader skimming a payload could not tell
which of the two concepts a bare `"tier"` key described. Milestone 1.14.1
renames every one of those to say explicitly which concept it is:

| Concept | Old name | New name |
|---|---|---|
| Run-wide result (independent/guided/assisted; monotonic for the WHOLE run) | `get_tier()` | `get_run_resolution_result()` |
| Current unit's phase (standard/assistance_required/assisted/partner_available/resolved; reset by `begin_next_unit()`) | `get_phase()` | `get_current_unit_phase()` |
| Current unit's failures so far (standard + assisted) | `get_failure_count()` | `get_current_unit_failures()` |
| Current unit's remaining standard-phase attempts | `get_remaining_standard_attempts()` | `get_standard_attempts_remaining()` |
| Current unit's remaining assisted-phase attempts | `get_remaining_assisted_attempts()` | `get_assisted_attempts_remaining()` (unchanged — already unambiguous) |

The transition dictionaries every `register_*()`/`accept_assistance()` call
returns, `result_snapshot()`'s output, `to_dict()`/`load_dict()`'s
serialized keys, and every recorder payload that carries either concept were
renamed the same way (`tier_before`/`tier_after`/`tier_changed` →
`run_resolution_result_before`/`run_resolution_result_after`/
`run_resolution_result_changed`; `phase_after` → `current_unit_phase_after`;
`failure_count` → `current_unit_failures`; `attempts_remaining` →
`standard_attempts_remaining`) — see "Recorder events" below for the full
list, and `docs/deduction-lab.md`'s "Recorder schema" for why this bumped
`event_schema_version` from 1 to 2. `ResolutionPolicy.to_dict()`'s own
`"version"` field (prototype-snapshot serialization only, never the
production save) bumped from 1 to 2 for the identical reason.

**No behavior changed** — `begin_next_unit()` already reset only the local
phase/failures/assistance flag and left the run result untouched; this pass
is a rename plus one UI fix (below), not a new mechanic.

### UI: two separate lines, never one merged string

Before this pass, `ResolutionPresenter.build_status()` returned a single
`"status_text"` that always appended the run result to whatever the current
unit's own state said (e.g. "Credibility: 3/3 · Resolution: Assisted" for a
brand-new part 2, right after part 1 finished Assisted). That is technically
accurate but reads as if THIS part is already Assisted — exactly the
"contradictory UI" risk the milestone brief called out. `build_status()` now
returns them as two separate fields the caller displays as two separate
lines:

- `"current_status_text"` — the CURRENT unit only: remaining attempts,
  "assistance required", "assisted attempts remaining", "partner resolution
  available", or "resolved". Never mentions the run result.
- `"run_result_text"` — the RUN-WIDE result only, always shown
  ("Run result so far: Independent/Guided/Assisted"). When the current unit
  is still a fresh `PHASE_STANDARD` (no local failures, no active
  assistance) but the run result is already above Independent, this line
  says so explicitly — `UI_RESOLUTION_RUN_RESULT_FROM_EARLIER`, "…(reached
  during an earlier challenge — this challenge is still fresh)" — so the two
  lines can never be misread as contradicting each other.
- `"run_result_label"` — just the bare word ("Independent"/"Guided"/
  "Assisted"), for a caller that wants it without either sentence.

Every prototype scene renders both as separate `Label`s
(`%ResolutionStatusLabel` for `current_status_text`, a new
`%RunResultLabel` for `run_result_text`) in the fixed header — never
concatenated back into one string. `prototype_{a,b,c}_presenter_test.gd`
assert this directly: a freshly-started later round/unit's
`current_status_text` never contains the run-result wording, and
`run_result_text` carries the "earlier challenge" qualifier whenever that
applies.

## Tiers

| Tier | Id (internal only) | Reached when |
|---|---|---|
| **Independent** | `independent` | Zero failed formal commits, no hints, no assistance, no partner resolution. |
| **Guided** | `guided` | One or two failed formal commits in the run, **or** hint level 1–2 revealed. |
| **Assisted** | `assisted` | Three failed formal commits in the run, **or** hint level 3–4, **or** targeted assistance accepted, **or** partner/system resolution used. |

If several rules apply, the least independent tier wins. Tier changes are
one-way within a run. A reset selection, a new unit, a locale switch, F1
hide/show or a closed dialog never lowers it. A **confirmed restart** creates
a new run with a fresh policy, and it is recorded (`prototype_restarted`,
with the previous run's tier and counts). Views never carry the raw ids;
`ResolutionPresenter.tier_label()` localizes them.

## Failure limits and phases

Centralized in `ResolutionPolicy` — no controller redefines them
(`resolution_policy_test.gd` checks the sources):

```
STANDARD_FAILURE_LIMIT := 3      ASSISTED_FAILURE_LIMIT := 2
GUIDED_FAILED_COMMITS  := 1      ASSISTED_FAILED_COMMITS := 3
GUIDED_HINT_LEVEL      := 1      ASSISTED_HINT_LEVEL     := 3
```

```
standard ──fail──▶ standard ──fail──▶ standard ──fail (3rd)──▶ assistance_required
   │                                                                │ accept_assistance()
   │ success                                                        ▼
   ▼                                                            assisted ──fail──▶ assisted ──fail (5th)──▶ partner_available
resolved ◀──────────────── success (any submitting phase) ─────────┘                                              │
   ▲                                                                                                             │
   └──────────────────────────────── register_partner_resolution() ──────────────────────────────────────────────┘
```

- `can_submit()` is true only in `standard` and `assisted`. In every other
  phase each register call is **rejected and counts nothing**, including a
  success. That is how "stop accepting blind commits" is enforced, as defense
  in depth behind the disabled buttons.
- `register_success(resolves_unit := true)`: pass `false` for a valid commit
  that doesn't finish the unit, such as Prototype A's optional innocent lie.
  It still counts as a formal commit and is never a penalty.
- Partner resolution never counts as the player's formal commit.
- `to_dict()` / `load_dict()` are JSON-safe for prototype snapshots and tests.
  `load_dict()` rejects malformed or internally inconsistent state as a whole,
  including a tier lower than its own counts imply.

## What counts as a formal commit

| | Formal commit | Never counts |
|---|---|---|
| **A** | "Present Evidence" that reaches `DeductionEvaluator.commit_attempt()` | No statement/evidence selected; a pair that already failed; an already-resolved statement (reclassified, not recommitted); a locked policy. A **valid** optional innocent lie or alternate refutation counts as a commit but never as a failure. |
| **B** | "Commit Theory" once every draft is complete | Editing, saving or switching drafts; an incomplete draft; a theory identical to an already-failed one; an already-accepted theory; a locked policy. |
| **C** | "Check Timeline" on a complete board; "Submit Verdict" with a verdict **and** a supporting fact | Placing, moving, removing, reading facts; an incomplete board; a placement identical to **any** earlier failed one; a verdict without a fact; a verdict+fact pair that already failed; a locked policy. |

## Hints

Hints stay opt-in (the Hint button never auto-reveals). Each prototype shows
`UI_RESOLUTION_HINT_NOTICE` ("levels 1–2 → Guided; 3–4 → Assisted") beside the
Hint button before the first hint. A newly revealed level calls
`register_hint(level)`. When that changes the tier, the status line says so
explicitly ("This run is now Guided."), so no hint ever changes the tier
silently. Assistance content reuses existing ladder text but never advances
the player's own hint level.

## Mechanic-specific behavior (summary)

Full detail lives in each prototype's own doc.

- **A — high-stakes confrontation** (`docs/prototype-a.md`, "Resolution
  policy").
  - The header shows "Credibility: 3/3 · Resolution: Independent" in text.
  - A counted failure costs one credibility and shows a generic NPC rebuttal
    plus the evaluator-category message. It never reveals the correct
    evidence and never resets the testimony.
  - The third failure disables Present Evidence until assistance is
    acknowledged. Assistance names the statement to focus on (also marked
    "[Partner focus]" in the list) and shows that statement's own level-2
    ladder text, a category hint. It never names the evidence.
  - Two assisted failures offer "Resolve with Partner". Partner resolution
    commits the first authored single-evidence `refutes` proof set through
    `classify_attempt()` then `commit_attempt()`, and explains which evidence
    was presented.
- **B — draft and batch commitment** (`docs/prototype-b.md`, "Drafts and
  batch commit").
  - Both questions are "Unverified Draft" tabs. Commit Theory classifies both
    drafts side-effect-free, then commits both through `commit_attempt()`, or
    commits **neither**.
  - Feedback by failure: 1st is the generic "at least one connection is not
    sufficiently established"; 2nd names **one** affected question; 3rd
    requires assistance (that question's base-ladder level 2). Two more
    failures offer the partner.
  - Partner resolution keeps valid drafts exactly as built and fills invalid
    drafts with authored proof sets (classified, then committed).
  - A classify/commit disagreement is an internal error. The theory is never
    reported as accepted in that case.
- **C — timeline finalization and justification** (`docs/prototype-c.md`,
  "Resolution policy").
  - Feedback by failure: 1st gives only a broad category (a fixed time, a
    window, an order, an overlap, travel time); 2nd gives one deterministic
    violated fact, verbatim, with its events marked "[conflict]"; 3rd
    requires assistance (the critical violated pair relationship plus the
    ladder's level-4 text; events are never moved). Two more failures offer
    the partner.
  - The partner timeline is the authored solution if `TimelineEvaluator`
    accepts it, otherwise the first accepted candidate from the UI domain. It
    is applied only if the evaluator accepts it.
  - The final claim needs a verdict **and** one supporting fact
    (`contradiction.supporting_constraint_refs`). It is its own unit, with
    the same limits and a partner that picks the correct verdict plus the
    first authored supporting fact.

## Feedback rules

Never exposed, in any prototype, before assistance allows it: the exact
missing evidence, per-clue correctness or "2 of 3 correct", which draft
failed on a first rejection, an exact correct event time, distance to the
authored solution, raw evaluator categories, internal ids, ground truth or
veracity, the partner's solution, and future assistance text.
Presenter tests check this structurally (allow-listed keys, no raw ids as
values) and by content sweeps over real X/Y/Z.

May be exposed: the type of logical gap (A's irrelevant/insufficient/
compatible messages), a known fact that is violated (C, from the second
failure), an event pair involved in a conflict, one affected question (B,
from the second failure), and a category hint once assistance is
acknowledged. Correct feedback still explains why the accepted solution works.

## Partner resolution

| Prototype | Path | Real API |
|---|---|---|
| A | First authored `refutes` proof set with exactly one pool item, per unresolved required statement of the part | `DeductionEvaluator.classify_attempt()` then `commit_attempt()` |
| B | Player's valid drafts kept; each invalid draft replaced by the first authored proof set matching relation, slot count and pool | `classify_attempt()` for every draft, then `commit_attempt()` for every draft |
| C (timeline) | Authored `solution_timeline` if accepted, else `DeductionValidator.enumerate_accepted_prototype_c_timelines()[0]` | `TimelineEvaluator.evaluate()`; applied only when `timeline_consistent` |
| C (claim) | Verdict computed from the accepted timeline; first authored `supporting_constraint_refs` entry | `TimelineEvaluator.is_constraint_satisfied()` |

Partner resolution is always labeled ("Resolved with your partner"), always
explains the logic, is recorded as `partner_resolution_used` with
`resolved_by: "partner"`, makes the run Assisted, and never counts as the
player's commit. If the evaluator disagrees unexpectedly, nothing is marked
resolved and the unit stays open, reported as an internal error.

## Recorder events

Reuses `DeductionLabRecorder` unchanged. Every event already carries
`sequence` and `elapsed_ms`; the export carries `prototype`, `case_id` and
`locale`. Payloads hold only ids, numbers, booleans and tier ids — never
localized text or personal data.

Every event type below belongs to one of two kinds, and a consumer can tell
which from the type alone (Milestone 1.14.1 — see "Local unit state vs. run
result" above): `run_resolution_result_changed` is the only RUN-WIDE
escalation event and fires at most once per threshold the run crosses,
however many units it takes; every other event here is a LOCAL unit-scoped
event (`formal_commit_*`, `assistance_offered`/`assistance_accepted`,
`partner_resolution_offered`/`partner_resolution_used`) and fires again,
independently, in a later unit that needs it — starting a new unit
(`begin_next_unit()`) itself emits neither kind, so opening part 2 never
looks like a run-result escalation.

| Event | Payload |
|---|---|
| `formal_commit_started` | `unit`, `sequence`, `run_resolution_result` (A adds `statement_id`/`evidence_id`) |
| `formal_commit_failed` | `unit`, `sequence`, `current_unit_failures`, remaining attempts, `run_resolution_result_before`, `run_resolution_result_after` (A: `category`, `credibility_remaining`; B/C: `standard_attempts_remaining`) |
| `formal_commit_succeeded` | `unit`, `sequence`, `resolved_by: "player"`, `run_resolution_result` |
| `run_resolution_result_changed` | `unit`, `from`, `to`, `reason` (`failed_commit`/`hint`/`assistance`/`partner_resolution`) — the one RUN-WIDE escalation event; see above |
| `assistance_offered` / `partner_resolution_offered` | `unit`, `run_resolution_result` — LOCAL to the unit; can recur in a later unit |
| `assistance_accepted` | `unit`, target (A `statement_id`, B `draft`/`target`, C `constraint_id`), `run_resolution_result_before`, `run_resolution_result_after` |
| `partner_resolution_used` | `unit`, `resolved_by: "partner"`, `run_resolution_result_before`, `run_resolution_result_after`, plus the path (A `resolutions`, B `drafts`/`partner_supplied_drafts`, C `placements`/`source` or `answer`/`justification_constraint_id`) |
| `prototype_restarted` | `case_id`, `previous_case_id`, `previous_run`, `previous_completed`, `previous_run_resolution_result`, `previous_formal_commits`, `previous_failed_commits` |

Also: B records `draft_selected`, `draft_saved`, `theory_batch_submitted`,
`theory_batch_rejected` (with per-draft categories, for analysis only) and
`theory_batch_accepted`. C adds `justification_constraint_id` to
`claim_answered` and records `claim_justification_result`. `prototype_started`
gains a `run` number. `prototype_completed`/`prototype_abandoned` gain a
`resolution` summary (from `ResolutionPolicy.get_summary()`, keyed
`run_resolution_result`/`formal_commits`/`failed_commits`/`max_hint_level`/
`assistance_used`/`partner_resolutions`). Unlocks and resolutions carry
`resolved_by`.

**`event_schema_version` is now 2** (`schema_version`, the outer envelope,
stays 1) — see `docs/deduction-lab.md`, "Recorder schema", for the full v1 →
v2 diff and why a version bump belongs to the event VOCABULARY, not the
envelope shape. In short: Milestone 1.14 had already replaced Prototype B's
per-round vocabulary (`round_started`, `connection_submitted`,
`connection_result`, `round_completed`) with the theory-batch events above
without bumping anything; Milestone 1.14.1 renamed the resolution-policy
payload keys/event type shown in the table above (`tier*` →
`run_resolution_result*`, `phase_after` → `current_unit_phase_after`,
`failure_count` → `current_unit_failures`, `attempts_remaining` →
`standard_attempts_remaining`, `resolution_tier_changed` →
`run_resolution_result_changed`) and used THAT as the occasion to add the
missing version field. No v1-shaped alias is kept: a consumer must read
`event_schema_version` and use the matching column above, not guess.

## Help-only mode and production persistence (Milestone 1.16)

`ResolutionPolicy.new(failures_escalate_run_result := true)`. The default is
everything above. The production chapter run (`docs/core-loop-sandbox.md`)
passes `false`, because 1.15B locks the run result to the highest help
actually used: failed commits then never raise it — not the first, not the
third, not reaching the assistance gate — while hints (1–2 Guided, 3–4
Assisted), accepted assistance and partner resolution still do. The local
3 + 2 budget, the phases and every event are unchanged. The mode is
serialized (`"failures_escalate_run_result"`, an additive key — a dictionary
without it restores with the original semantics) and `load_dict()`'s
"result lower than its counts imply" check honors it. In production each
unit owns its own policy; the chapter's run help result is the maximum over
them, stored in the save and the recording, never shown to the player.

Production persistence follows the rule stated below: the formal outcome,
its policy snapshot, failed-candidate keys and the session are written in ONE
atomic checkpoint before the feedback is shown, and the pending feedback
itself is part of the snapshot — quitting on the feedback screen neither
refunds the attempt nor loses the message.

## Persistence (prototype-only)

Policy state lives in the controller the scene owns, so within a debug
prototype:
- F1 hide/show keeps it (the scene node is never freed);
- cancelling Restart or Return keeps it exactly;
- a locale switch only re-renders it;
- a confirmed restart creates a new run, recorded as `prototype_restarted`.

**Nothing is written to the production save.** A future vertical slice that
owns deduction sessions in real gameplay **must persist the formal-commit
state before it shows feedback**: the policy snapshot (`to_dict()`), the
failed-attempt keys and the session, written atomically in the same save
operation as the commit itself. Otherwise quitting on the feedback screen
refunds the attempt. That integration is deferred to the milestone that
brings deduction into `SaveManager` (`docs/deduction-system.md`, "Save/load
(deferred)").

## Accessibility and pacing

- Every status is **text**: credibility, remaining attempts, tier, "Unverified
  Draft", "[Partner focus]", "[conflict]", selected markers. Nothing depends
  on color.
- No timers. Assistance is **acknowledged** (a footer button), never
  auto-applied. Resolution actions live in the fixed footer, so they are
  always reachable however long the feedback text is, and focus moves to
  them after Continue.
- Feedback states consequences plainly ("this costs no credibility",
  "nothing is lost and nothing needs replaying").

## Why no hard game-over

A detective game that can lock the player out of the story punishes exactly
the players who most need help, and it teaches nothing: a game-over screen
cannot explain the contradiction. Assisted Mode and partner resolution
guarantee every puzzle ends. They also guarantee it ends **with** the logical
explanation, and with an honest record of how it was solved. Nothing replays
long dialogue, resets testimony or discards drafts.

## Why this is a design incentive, not security

An offline game cannot stop a determined player from restarting, editing
files or reading content. The policy only changes the **cost/benefit** of
guessing:
- each guess spends a visible, limited budget;
- feedback carries too little information to steer a search;
- identical guesses are refused for free, so spamming gains nothing;
- the tier and the recorder make guessing visible to the player and to
  playtest analysis.

Known ways to retry anyway:
- Restart: always allowed, always recorded.
- Return to Lab, then Start: a new run, also recorded as a restart.
- Hint levels before failing: allowed, and they change the tier.
- Changing one clue or placement between commits is allowed. Each commit is
  a genuinely new, counted attempt.
- In C, trying different verdict+fact pairs costs attempts, but the 20-pair
  space is finite.

## Testing

| File | FAST/FULL | Covers |
|---|---|---|
| `scenes/test/resolution_policy_test.gd` | FAST + FULL | The policy alone: initial state, Guided/Assisted thresholds, assistance acknowledgement, assisted failures, partner availability, hint-driven results, one-way run results across units (a fresh unit's own phase/failures always reset, the run result never does), run-wide failure counting, refused actions counting nothing, transition-event order (local vs. run-wide), snapshots, centralized constants, strict serialization (`run_resolution_result`/`current_unit_phase` keys), determinism. |
| `prototype_{a,b,c}_controller_test.gd` | FAST + FULL | Each mechanic's commit rules, blocking, feedback levels, assistance, partner resolution through the real evaluator, telemetry, restart, using the renamed `get_run_resolution_result()`/`get_current_unit_phase()`/`get_current_unit_failures()` accessors. |
| `prototype_{a,b,c}_presenter_test.gd` | FAST + FULL | Status keys (now split into `current_status_text`/`run_result_text`/`run_result_label`), no raw ids, assistance/partner leakage gating on real X/Y/Z, VI/EN, completion lines, and (Milestone 1.14.1) a dedicated check per prototype that a round/unit resolved in Assisted Mode never leaks its status wording OR its assistance content into the next fresh round/unit, while the separate run-result line still reads Assisted with an "earlier challenge" qualifier. |
| `prototype_c_content_test.gd` / `deduction_validation_test.gd` | FAST + FULL | C's supporting facts exactly equal the facts that rule the claim out, accepted/rejected by the controller; negative fixtures for the validator rule. |
| `deduction_lab_recorder_test.gd` | FAST + FULL | Milestone 1.14.1 adds a contract test that drives a real `PrototypeAController` failure through a recorder and asserts the exported dict's `event_schema_version` (2) actually matches its event vocabulary — the renamed `run_resolution_result_changed` type and `run_resolution_result_before`/`after` payload keys are present, the retired v1 `resolution_tier_changed`/`tier_before`/`tier_after` are absent. |
| `prototype_{a,b,c}_scene_test.gd` | FULL only | Real buttons: budgets, assistance, partner resolution, completion summaries, restart recording, locale/F1 preservation, fixed footer (now also asserting each prototype's PRIMARY formal-commit button — Present/Commit Theory/Check Timeline/Submit Verdict — lives in the fixed Footer, not just the resolution actions), and a real exported recording's `event_schema_version`/renamed event vocabulary. |
| `deduction_lab_scene_test.gd` | FULL only | Milestone 1.14.1 adds overlay visibility/input-ownership checks: opening any Prototype hides the Lab's own `%CenterPanel`/`%DimBackground` (no text bleed-through, no focusable/clickable Lab controls underneath), and returning restores them with the Lab's session untouched. |

## Known limitations

- **No production save integration** (see "Persistence").
- **Per-unit budgets are fixed defaults** (3 + 2). A Story Mode with earlier
  assistance is a playtest question, not implemented.
- **C's claim space is small** (verdict × facts). Duplicate blocking makes
  exhaustive guessing slow, not impossible.
- **B's single-unit theory** means a player strong on one question and weak
  on the other shares one budget. That is deliberate (the batch is the unit),
  and worth watching in playtests.
- **Headless tests prove wiring, not pixels or feel** (`docs/architecture.md`,
  "Known limitations").
