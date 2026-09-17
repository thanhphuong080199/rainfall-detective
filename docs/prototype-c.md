# Prototype C — Timeline Reconstruction (Milestone 1.13)

The third playable deduction interaction, built on the same Milestone
1.9/1.9.1 foundation (`docs/deduction-system.md`) and Milestone 1.10
Deduction Lab (`docs/deduction-lab.md`) Prototype A (`docs/prototype-a.md`)
and Prototype B (`docs/prototype-b.md`) used, and launched the same way.
**Debug-only, non-canon, not the final game loop.** It exists to test one
narrow question, stated in the milestone brief:

```
Read objective timeline facts
→ place events at possible times
→ submit the reconstruction
→ inspect violated facts and revise
→ produce any timeline satisfying all required constraints
→ use that timeline to expose an impossible claim
```

**Since Milestone 1.14** the final step also requires the established fact
that justifies the verdict. Both steps are formal commits under the shared
resolution policy — see "Resolution policy and final claim justification"
below and `docs/resolution-policy.md`.

Read `docs/deduction-system.md` first (the proof-set and, in particular, the
"Timeline reconstruction" contract this all sits on — `TimelineEvaluator`
already existed, complete and tested, before this milestone), then
`docs/deduction-prototype-cases.md` (what X/Y/Z actually contain, including
their timeline sections), `docs/deduction-lab.md` (the recorder this reuses),
and `docs/prototype-a.md`/`docs/prototype-b.md` (the first two mechanics
built on the same foundation, and why each is deliberately isolated from the
others). `docs/deduction-playtest-plan.md` has the A/B/C comparison protocol
and, since this milestone, Prototype C's own facilitator section.

## What this is not

No free-form timeline editor, no unrestricted drag-only interaction, no
multiple-day timelines or midnight crossing, no generic constraint solver, no
clue graph, no statement-evidence presentation (that is Prototype A's job),
no relation picker, no final accusation, no investigation gameplay, no
production save integration, no canon case content — those are out of scope
by design (see "Out of scope" below and the milestone brief). The player
never edits or authors constraints, never sees a raw constraint dictionary,
and is never asked to solve for anything beyond "does this specific placement
satisfy every fact I've been given" — exactly what `TimelineEvaluator.
evaluate()` already answers.

## Architecture — reuse, not a parallel system

```
                 PrototypeC (scenes/debug/PrototypeC.tscn + scripts/debug/prototype_c.gd)
                           │  owns
              ┌────────────┴────────────────────┐
              ▼                                  ▼
   PrototypeCController                 DeductionLabRecorder
   (interaction state: placements,      (Milestone 1.10, REUSED
    selection, moves, submissions,      UNCHANGED — see "Recorder
    opened facts, hint level, claim      events" below)
    attempts — NO DeductionSession,
    see the decision box below)
              │  reads case_def via ContentDB
              ▼
   TimelineEvaluator
   (unchanged production code — every submission AND the final claim
    check call into this, nothing is reimplemented)
              │
              ▼
   PrototypeCPresenter (scripts/deduction/prototype_c_presenter.gd)
   build_player_view()          → spoiler-safe, allow-listed view model
   build_violation_feedback()   → evaluator result → player-facing facts
   build_claim_feedback()       → claim answer → correct/guidance
```

| Piece | File | Kind |
|---|---|---|
| `PrototypeCController` | `scripts/deduction/prototype_c_controller.gd` | `class_name` `RefCounted`, pure/autoload-free |
| `PrototypeCPresenter` | `scripts/deduction/prototype_c_presenter.gd` | `class_name` static helper, pure/autoload-free |
| The scene | `scenes/debug/PrototypeC.tscn` + `scripts/debug/prototype_c.gd` | a normal `Control` scene, instanced as a **permanent child of `DeductionLab.tscn`**, a sibling of `PrototypeA`/`PrototypeB` (not `DebugPanel` directly) |
| Lab wiring | `scenes/debug/DeductionLab.tscn` + `scripts/debug/deduction_lab.gd` | one new "Launch Prototype C — Timeline Reconstruction" button in the case row, next to Prototype A's and B's own |
| Recorder | `scripts/deduction/deduction_lab_recorder.gd` | **unmodified** Milestone 1.10 class — see "Recorder events" |
| Content | `data/deductions/prototypes/*.json`'s new optional `prototype_c` object | loaded by the existing `ContentDB` deduction-case loader, no new content category |

**No new autoload.** Same reasoning `docs/deduction-system.md`/
`docs/deduction-lab.md`/`docs/prototype-a.md`/`docs/prototype-b.md` already
give: one scene needs this, not several unrelated ones. **No production
`GameState`/save-schema changes** — a Prototype C run is exactly as
persisted as the rest of the deduction foundation (not at all). **No new
timeline constraint vocabulary and no evaluator changes** — every constraint
type (`fixed_time`/`window`/`before`/`no_overlap`/`travel_time`) already
existed and was already fully tested by `timeline_evaluator_test.gd`; this
milestone only builds a UI and a bounded content contract on top.

```
DECISION: PrototypeCController owns NO DeductionSession at all — the one
prototype controller that doesn't, unlike DeductionLabController/
PrototypeAController/PrototypeBController.

WHY: Every other controller needs a DeductionSession because
DeductionEvaluator.commit_attempt() requires one to resolve a CLAIM into.
Prototype C never commits a claim through that path — its two evaluations,
TimelineEvaluator.evaluate() (the reconstruction) and
TimelineEvaluator.is_constraint_satisfied() (the final claim check), are both
pure, stateless functions of a case_def and a placement dict. Reusing
DeductionSession purely for its evidence-opened bookkeeping would not even
fit the shape here: a timeline constraint's "source" can be a STATEMENT id
(a suspect's claimed time), not only an evidence id, so
mark_evidence_opened() has no shape for "the player opened this fact" in
general. The milestone brief explicitly allows this ("may also own a fresh
DeductionSession if useful... but timeline correctness must remain owned by
TimelineEvaluator") — it is optional, and this milestone found it not useful.

IMPACT: Interaction-only state (placements, selection, opened facts, hint
level, submission/move counts, claim attempts) is tracked directly on
PrototypeCController, the same way PrototypeAController tracks its own
Prototype-A-owned hint state instead of forcing it through the base
contract. `prototype_c_controller_test.gd`'s
`_test_no_deduction_session_dependency()` proves the source file never
instantiates or types against DeductionSession.
```

```
DECISION: Hints are Prototype-C-owned data — ONE flat 4-level ladder per
case (`prototype_c.hint_ladder`), not per-target ladders keyed by claim id
the way the base contract's `hints` array is.

WHY: The base hint contract's ladders target a CLAIM (a deduction or
conclusion) — docs/deduction-system.md, "Hint ladders". Prototype C's puzzle
has no claim to target at all until the very end (the final claim check),
and by then the timeline is already solved. There is exactly one puzzle per
case (unlike Prototype B's multiple rounds), so one flat ladder is the
natural shape — closer to Prototype A's own Prototype-A-owned hint state
than to Prototype B's reuse of the base API.

IMPACT: PrototypeCController.reveal_next_hint()/get_hint_level() mirror
PrototypeAController's contract exactly (same four-field return shape), but
read/write a single `_hint_level: int` rather than a per-claim dictionary.
```

```
DECISION: The candidate time_slots domain is a single SHARED list of "HH:MM"
strings, not a separate list per movable event.

WHY: The milestone requires "if multiple events may legally share a start
time, the UI must allow that" and "do not let the UI impose constraints
stricter than TimelineEvaluator." A shared list is the simplest structure
that satisfies both: any movable event may be placed at any slot in the
list, and only TimelineEvaluator's own window/before/no_overlap/travel_time
checks — never the UI — ever reject a specific combination. Per-event lists
would either (a) need to already encode which events "belong" together,
silently teaching the answer, or (b) still need a union step to build one
visual timeline axis (see docs/prototype-c.md, "Timeline board").

IMPACT: `PrototypeCController.place_event()`/`place_selected()` validate
only "is this string one of the case's time_slots", never "does this event
already make sense here." Correctness is judged ENTIRELY at submission, by
the real TimelineEvaluator.
```

## Data contract

An optional `prototype_c` object alongside the base deduction case and its
`timeline` section (`docs/deduction-system.md`, "Data contract" and "Timeline
reconstruction"), validated only when present
(`DeductionValidator._validate_prototype_c` — every other deduction case,
including the hand-built fixtures, is untouched by this section):

```json
"prototype_c": {
  "fixed_events": ["tl_mara_tram_tap", "tl_badge_used"],
  "movable_events": ["tl_mara_leaves", "tl_cardigan_taken", "tl_window_forced", "tl_shredding_pickup", "tl_cardigan_returned"],
  "time_slots": ["19:25", "19:35", "19:48", "20:08", "20:10", "20:14"],
  "objective": "DED_PROTO_X_PROTOC_OBJECTIVE",
  "visible_constraint_facts": {
    "c_badge_time": "DED_PROTO_X_PROTOC_FACT_BADGE_TIME",
    "c_tram_time": "DED_PROTO_X_PROTOC_FACT_TRAM_TIME",
    "c_mara_leaves_claimed": "DED_PROTO_X_PROTOC_FACT_MARA_LEAVES",
    "c_mara_travel": "DED_PROTO_X_PROTOC_FACT_MARA_TRAVEL",
    "c_cardigan_taken_window": "DED_PROTO_X_PROTOC_FACT_CARDIGAN_TAKEN",
    "c_cardigan_returned_window": "DED_PROTO_X_PROTOC_FACT_CARDIGAN_RETURNED",
    "c_window_after_entry": "DED_PROTO_X_PROTOC_FACT_WINDOW_AFTER_ENTRY",
    "c_window_heard": "DED_PROTO_X_PROTOC_FACT_WINDOW_HEARD",
    "c_window_not_during_errand": "DED_PROTO_X_PROTOC_FACT_WINDOW_NOT_DURING_ERRAND",
    "c_shredding_window": "DED_PROTO_X_PROTOC_FACT_SHREDDING_WINDOW"
  },
  "contradiction": {
    "claim": "st_ilse_left_early",
    "constraint_ref": "c_ilse_claimed_departure",
    "supporting_constraint_refs": ["c_shredding_window"],
    "explanation": "DED_PROTO_X_PROTOC_CONTRADICTION_EXP"
  },
  "hint_ladder": ["DED_PROTO_X_PROTOC_HINT_1", "DED_PROTO_X_PROTOC_HINT_2", "DED_PROTO_X_PROTOC_HINT_3", "DED_PROTO_X_PROTOC_HINT_4"],
  "completion_text": "DED_PROTO_X_PROTOC_COMPLETION"
}
```

| Field | Meaning |
|---|---|
| `fixed_events` | Timeline event ids that are pre-placed and locked. Each must have EXACTLY one authored `fixed_time` constraint — that constraint's own `time` is the single source of truth for the locked value; it is never duplicated here. |
| `movable_events` | Timeline event ids the player places. Every `fixed_events` + `movable_events` id together must exactly partition the case's `timeline.events` (no event left out, none listed twice, none in both). |
| `time_slots` | The finite, authored candidate "HH:MM" list offered by the UI for MOVABLE events — see "Candidate time-slot domain" below. Fixed events are never placed from this list; they're always at their own locked time. |
| `objective` | Translation key for the case's timeline briefing text. |
| `visible_constraint_facts` | Maps a **required** timeline constraint id → a translation key stating that fact in natural language. Every required constraint in `timeline.constraints` must appear here (enforced) — "a required constraint must never be a hidden author-only rule." An **optional** constraint must never appear here (also enforced) — it stays hidden until the final claim phase. |
| `contradiction.claim` | A **statement** claim id (enforced — never a hypothesis/deduction/explanation/conclusion) — the disputed NPC statement revealed only after the reconstruction is accepted. |
| `contradiction.constraint_ref` | The id of an **optional** (`required: false`) timeline constraint whose `source` is that same claim (both enforced) — "what would need to be true for the claim to hold." Must never also appear in `visible_constraint_facts` (enforced). |
| `contradiction.explanation` | Translation key for the final explanation, with `%s` placeholders filled at runtime with the PLAYER'S OWN accepted time(s) for the event(s) that constraint references — see "Final claim check" below. |
| `contradiction.supporting_constraint_refs` | Milestone 1.14. The visible fact ids that justify the verdict — exactly the facts that, on their own, rule the disputed claim out (see "Final claim justification"). Several may be listed; every listed one is accepted. |
| `hint_ladder` | Exactly 4 translation keys — Prototype-C-owned (see the architecture decision above), not the base `hints` array. |
| `completion_text` | Translation key shown once the claim is correctly resolved and acknowledged. |

Authoring rules, enforced by the validator:
- `fixed_events` and `movable_events` together must be a clean partition of every timeline event, with no duplicates and no omissions;
- a fixed event must have exactly one `fixed_time` constraint on it; a movable event must have none (a "movable" event pinned to one exact time is a contradiction in terms);
- `time_slots` entries must be valid, distinct `"HH:MM"` strings, and none may let a movable event's own duration run past 23:59 (this single-day model has no midnight wraparound — `docs/deduction-system.md`, "Known limitations");
- every **required** constraint needs a `visible_constraint_facts` entry with a translation that resolves in both `en` and `vi`; every **optional** constraint must be absent from that map;
- `contradiction.claim` must be a real `statement` claim; `contradiction.constraint_ref` must be a real, **optional** constraint whose `source` is that claim, and must not double as a visible fact;
- `contradiction.supporting_constraint_refs` must be a non-empty, duplicate-free list of visible facts sharing an event with the claim, and exactly the set of visible facts that rule the claim out on their own (Milestone 1.14);
- `hint_ladder` must have exactly 4 entries, each translated in both locales.

Two heavier, genuinely important checks are **deliberately NOT run** by
`DeductionValidator` (which runs on every `ContentDB` load, including every
other focused test's boot): "at least one UI-offered timeline is accepted"
and "every accepted timeline makes the claim impossible." Enumerating the
full candidate domain through the real `TimelineEvaluator` costs real time
(see "Candidate time-slot domain" below); baking it into the always-on
validator would slow down the entire FAST/FULL suite, not just this
milestone's own tests. They live instead in
`DeductionValidator.enumerate_accepted_prototype_c_timelines()` — a public,
reusable, bounded helper — called directly, once per case, by
`prototype_c_content_test.gd`. See that function's own doc comment for the
exact reasoning, and "Universal contradiction proof" below for what it
proves.

`DeductionValidator.structural_signature()` (used by
`validate_structural_equivalence()`, already run by `ContentValidator`) was
extended with `prototype_c:` lines describing the fixed/movable role shape,
the slot count, the sorted multiset of fact constraint TYPES, and the
contradiction's claim role + constraint type (plus, since Milestone 1.14,
the sorted types of its supporting facts) — X, Y and Z's Prototype C
layers are machine-checked to share one shape, exactly like Prototype A's
and B's own layers.

## Content audit: the timeline was already there

Milestone 1.9's `timeline` section on all three prototype cases already had
exactly the shape this milestone's brief describes: 7 timeline events, 2 with
`fixed_time` constraints (the credential-use anchor and the owner's alibi
anchor), 5 without; 11 constraints covering all 5 types
(`fixed_time` ×2, `window` ×6, `before` ×1, `no_overlap` ×1, `travel_time`
×1); one `required: false` constraint per case sourced from the bystander's
innocent lie about when their errand happened (`docs/deduction-system.md`
already called this out: "the prototype cases use one for each bystander's
false claimed time"). **No new timeline content was authored** — Milestone
1.13 only adds the `prototype_c` presentation layer on top of what already
existed, and reuses that exact pre-existing optional constraint as the final
claim's hypothetical constraint (see "Final impossible claim" below).

Every one of the 10 REQUIRED constraints per case got a
`visible_constraint_facts` entry — a natural-language sentence restating
exactly what that constraint already says, sourced from evidence or a true
statement already in the case (never inventing a new fact):

| Constraint type | Example fact (X) |
|---|---|
| `fixed_time` (×2) | "The door log confirms the badge was used to open Stack Room 3 at exactly 20:06." |
| `window` (×6) | "The lost-property sheet places the cardigan being taken from the rack between 19:45 and 19:50." |
| `before` (×1) | "The window was forced open at least a minute after the badge was used to enter." |
| `no_overlap` (×1) | "The window could not have been forced at the exact same moment the shredding pickup was underway." |
| `travel_time` (×1) | "The transit map note shows the fastest trip from the archive to Harbor Station takes at least 25 minutes." |

No raw field (`type`, `min_gap_minutes`, `earliest`/`latest`, `required`) is
ever shown to the player — `prototype_c_presenter_test.gd`'s
`_test_presenter_never_reads_constraint_type_or_required()` proves
`PrototypeCPresenter` never even reads those fields, so it is structurally
impossible for a raw constraint shape to leak through it.

## Candidate time-slot domain and why it is fair

Each case offers **6** candidate `"HH:MM"` slots for its 5 movable events —
a single shared list, not per-event. The domain was chosen, and verified by
direct enumeration, to guarantee:

- **every authored solution time is offered** (`ground_truth.solution_timeline`'s
  5 movable values are a subset of `time_slots` — enforced and tested);
- **at least one alternate valid timeline exists** — for X, placing
  `tl_mara_leaves` at `19:25` instead of the authored `19:35` (its claimed
  window is `19:25–19:45`, and the travel-time constraint to the fixed
  Harbor-tram anchor only narrows that down to `19:25–19:39`) still satisfies
  every required constraint, proving success is judged by
  `TimelineEvaluator`, never by exact-equality with one sequence;
- **the domain stays small enough to enumerate exhaustively and cheaply** —
  6 slots for 5 movable events is 6⁵ = 7,776 combinations per case, checked
  directly against the real evaluator in well under half a second per case
  (measured; the original 8-slot design measured ~1.5s/case and was
  deliberately trimmed down — see the architecture decision above and the
  milestone's own "reduce redundant candidate slots" guidance);
- **every accepted timeline (out of all 7,776 combinations) makes the
  disputed claim impossible** — see "Universal contradiction proof" below.

Enumeration for all three cases (verified by
`prototype_c_content_test.gd` and, independently, by a standalone Python
model of `TimelineEvaluator`'s exact semantics used only during design/
authoring, not shipped as code) finds exactly **8** UI-offered timelines
TimelineEvaluator accepts per case: the three "independent" movable events
(the owner's departure, the credential-custody borrow, and the custody
return) each admit 2 valid slots on their own, and the one interacting pair
(the staging act and the bystander's errand, linked by a `before` + a
`no_overlap` constraint) admits exactly 1 valid combination — 2×2×1×2 = 8,
identically for X, Y and Z.

## Player-visible sources for every required constraint

For each of the 10 required constraints per case, the fact is grounded in
something the player can actually read:

| Required fact | Grounded in |
|---|---|
| Both `fixed_time` anchors | Already-authored `certainty: "fixed"` evidence (a security/access log, a transit/camera record) |
| The owner's claimed departure window | The owner's own **true** statement (`veracity: "true"`) — never a lie |
| The travel-time fact | A `travel_fact`-role evidence item (a transit map/timetable note) |
| Custody borrow/return windows | The `credential_custody`-role evidence (a hand-written lost-property/laundry/locker log) |
| The staging act's `before` fact | The `staging_sign`-role evidence (the forced entry itself) |
| The staging act's `window` fact | The `red_herring`-role evidence (a bystander sighting/footage — used here only for its timestamp, independent of whatever it misleadingly implies elsewhere in the base proof graph) |
| The `no_overlap` fact | The same red-herring evidence's own account of watching continuously |
| The errand's `window` fact | The `red_herring_explanation`-role evidence (a contractor/manifest log) |

The one constraint that is **not** a visible fact — the bystander's
optional, `required: false` claimed-time window — is sourced from a
`deceptive` statement (`veracity: "deceptive"`) precisely because it is the
false claim the final phase exposes; `_validate_constraint`'s own base rule
already forbids a *required* constraint from ever being sourced from a
mistaken/deceptive statement, so a required constraint can never accidentally
be a hidden lie.

## Final impossible claim and universal contradiction proof

The disputed claim is the SAME bystander innocent-lie statement
Milestone 1.9's content already authored (`st_ilse_left_early` /
`st_bruno_left_early` / `st_gus_not_in_yard`) and the SAME optional
constraint that already existed to represent it
(`c_ilse_claimed_departure` / `c_bruno_claimed_departure` /
`c_gus_claimed_absence`) — reused by reference (`constraint_ref`), not
duplicated. This is exactly the interaction the milestone brief describes:

```
Claim: Ilse says she "locked up and went home at quarter to eight" (19:45).
Claim constraint: tl_shredding_pickup must fall within 19:30–19:45.

The objective timeline establishes (via the REQUIRED c_shredding_window
fact): tl_shredding_pickup must fall within 20:08–20:12.

20:08–20:12 and 19:30–19:45 never overlap — so no timeline the player can
ever legally build satisfies both. The claim is impossible, unconditionally,
not just for the authored solution.
```

This is checked directly, not by inspection: `prototype_c_content_test.gd`'s
`_test_every_accepted_timeline_contradicts_the_claim()` takes **every one**
of the ~8 UI-offered timelines `enumerate_accepted_prototype_c_timelines()`
finds acceptable and evaluates the disputed constraint's own
`TimelineEvaluator.is_constraint_satisfied()` against each — asserting it
fails every single time, for all three cases. `PrototypeCController.
answer_claim()` performs the identical check at runtime, against whichever
timeline THIS player actually built, not a hardcoded expectation — so the
guarantee holds for every player, not just one authored path.

## Player-facing flow

1. **Launch** — the Deduction Lab's "Launch Prototype C — Timeline
   Reconstruction" button opens the scene, defaulting the case picker to
   whichever case the Lab currently has active, and hides Prototype A and
   Prototype B if either happened to be open (never resetting them — see
   "Entry and lifecycle"). Nothing starts until **Start** is pressed — that
   creates a fresh `PrototypeCController`, never the Lab's own, never
   Prototype A's or B's.
2. **Briefing** — the case title/description, the localized `objective`, and
   the non-canon badge are always visible above the play area.
3. **The board** — a merged vertical timeline (every candidate slot plus
   wherever the two fixed events are locked, sorted chronologically) on the
   left; all seven event cards (fixed ones marked locked, movable ones with
   Select/Remove) and the fact list on the right. Selecting a movable event
   and then clicking "Place Here" on a timeline row places it there (or
   moves it, if it was already placed elsewhere); "Remove" returns it to
   the tray. A row's "Place Here" button never rejects a slot another event
   already occupies — see the architecture decision above.
4. **Check Timeline** — disabled until every movable event is placed;
   submits the complete placement to the real `TimelineEvaluator.evaluate()`.
   On rejection, every placement is retained and feedback is progressive: a
   broad category first, then one verbatim fact (see "Resolution policy and
   final claim justification"). A placement identical to ANY earlier failed
   one stays disabled.
   On acceptance, the board is replaced by the final claim phase.
5. **Final claim** — the disputed statement's own (translated) text is
   revealed. The player selects a verdict ("Fits the timeline" /
   "Impossible") **and** one established fact from the list, then presses
   **Submit Verdict**, which stays disabled until both are chosen. A wrong
   answer keeps the accepted timeline exactly as built and gives a
   non-spoiling nudge. A correct one reveals the contradiction explanation,
   with the player's own accepted time interpolated in, plus the chosen
   supporting fact, and offers Continue.
6. **Completion** — the authored `completion_text`, plus the shared
   resolution summary (time, formal commits, failed formal commits, hints,
   assistance, tier, partner resolution) and timeline checks, failed checks,
   claim-check attempts, placements/moves and facts opened. Restart, Export Recording and Return to
   Lab are all offered here too.

## Placement and invalid-submission behavior

- `select_event()`/`place_selected()`/`place_event()`/`remove_event()` are
  the four production entry points; a fixed event rejects all four except
  its own already-locked placement.
- Placing an already-placed movable event at a **different** slot moves it
  (`event_moved`); at the **same** slot is a no-op (nothing recorded, no
  move counted).
- `can_submit()` requires every movable event placed; an incomplete board's
  Check button stays disabled, and `submit_timeline()` itself rejects an
  incomplete call as `invalid_input` too (defense in depth, matching
  Prototype B's own "the controller itself rejects... before it ever
  reaches the evaluator" pattern).
- A rejected submission changes **nothing** about the board — placements
  are read back from the same `_placements` dictionary the player built.
- `can_resubmit()` is false while the current placement is identical to ANY
  earlier failed submission, and once the timeline is accepted. Since
  Milestone 1.14, moving an event away and back no longer re-enables it. `submit_timeline()` itself
  also guards this (returns the previous result with `blocked_duplicate:
  true`, recording nothing new), the same defense-in-depth stance Prototype
  B's submission gate takes.

## Violation-feedback mapping

`PrototypeCPresenter.build_violation_feedback(case_def, controller, result)`,
where `result` is whatever `PrototypeCController.submit_timeline()` or
`resolve_with_partner()` returned. Since Milestone 1.14 the feedback is
progressive and chosen by the controller, not the presenter:

| `result` shape | Player sees |
|---|---|
| `category == invalid_input` | A fixed message: "place every event before checking", or the lock / internal-error message |
| rejected, `feedback.level == "category"` (the unit's first failure) | "This timeline conflicts with one or more established facts. Look again at *a confirmed time window / the order two events must happen in / two events that cannot overlap / the travel time between two places / a fixed, confirmed time*." **No fact is listed.** |
| rejected, `feedback.level == "fact"` (later failures) | Exactly ONE violated fact: the first visible violated fact in authored order, verbatim from `visible_constraint_facts`, with its event handles. The board marks those events "[conflict]" in text. |
| accepted | The success headline, no violations |
| accepted, `partner: true` | "Resolved with your partner", then the facts the player's last attempt broke and that the partner timeline now satisfies |

Every rejection also carries the budget/tier notice. `violated_optional` is
never read, so the disputed claim stays invisible until acceptance. The
presenter never reads a constraint's `type`: the controller maps the type to
the broad category, and a source-level test enforces this. Feedback never
states a correct time or the distance to the authored solution.

## Hints

Prototype-C-owned data (see the architecture decision above) — one flat
4-level ladder per case, always available (no "no ladder for this
non-required item" case the way Prototype A's optional lies have, since
Prototype C has exactly one puzzle, not several rounds with different
requiredness). The four levels match the milestone brief's own progression:

1. remind the player to begin with the fixed anchors;
2. direct attention to an important window/order relationship (e.g. how
   travel time narrows a claimed departure window further than the window
   alone does);
3. emphasize the travel-time/overlap relationship between the staging act
   and the bystander's errand;
4. narrow the critical event pair (the staging act vs. the errand) without
   ever stating the exact solution or the final contradiction.

`PrototypeCController.reveal_next_hint()` mirrors
`PrototypeAController.reveal_next_hint()`'s exact four-field return shape.
Hints never move an event, never reveal `ground_truth.solution_timeline`,
and never state the final claim's answer. Since Milestone 1.14 a newly
revealed level also raises the resolution tier (levels 1–2 → Guided, 3–4 →
Assisted), and the status line says so.

## Presenter and spoiler boundary

`PrototypeCPresenter.build_player_view(case_def, controller)` returns
`{"view": ..., "handle_map": ...}` — the exact same allow-list/opaque-handle
pattern `DeductionLabPresenter`/`PrototypeAPresenter`/`PrototypeBPresenter`
established. Before acceptance, `view` has exactly 18 keys since Milestone
1.14 — `can_check`, `resolution_status` and `completion_lines` joined the
original 15 (`non_canon`,
`case_title`, `case_description`, `objective`, `completed`, `accepted`,
`events`, `time_slots`, `unplaced_count`, `can_submit`, `can_resubmit`,
`facts`, `hint`, `stats`, `completion_text`) and contains **no** domain id
(event/constraint/claim id), no structural role, no raw constraint field
(`type`, `required`, `earliest`/`latest`, `min_gap_minutes`), no
`ground_truth`/`solution_timeline`, and — critically — **no `claim` key at
all** until `controller.is_accepted()` is true (an entirely absent key, not
merely blank, exactly matching `DeductionLabPresenter`'s own unresolved-claim
gating). Once accepted, `claim` appears with only the disputed statement's
own (translated) text — never its veracity, never the raw
`contradiction.constraint_ref` dictionary. The `resolution` key (the final
explanation) is likewise entirely absent until the claim is actually
answered correctly. `handle_map` is kept privately by
`scripts/debug/prototype_c.gd` and resolved back to a real id only at the
moment a click handler calls a production API.
`prototype_c_presenter_test.gd`'s own structural + content sweep methodology
mirrors `prototype_a_presenter_test.gd`'s/`prototype_b_presenter_test.gd`'s
against the real X/Y/Z content, including a sweep of the ACCEPTED view (once
the claim key legitimately appears) to prove nothing else leaks alongside it.

## Resolution policy and final claim justification (Milestone 1.14)

See `docs/resolution-policy.md` for the shared model. Prototype C has **two
resolution units**: the timeline, then the claim justification.

### Timeline

- Placing, moving, removing and reading facts are free. "Check Timeline" is
  the formal commit. An incomplete board, or a placement identical to ANY
  earlier failed one, is refused without cost.
- **Any** timeline satisfying every required constraint succeeds, so
  alternate valid timelines stay valid and optional constraints never block.
- Feedback by failure (see "Violation-feedback mapping"):
  - 1st: a broad category only.
  - 2nd: one deterministic violated fact, with its events marked.
  - 3rd: checking locks until the footer's Accept Assistance is pressed.
    Assistance names the **critical relationship** — the latest failure's
    first violated PAIR fact (before / no_overlap / travel_time), else its
    first violated fact — shows the event pair, and adds the case's own
    level-4 hint text. It never moves events and never states a time.
  - After two more failures: "Resolve with Partner".
- The **partner timeline** is the authored `ground_truth.solution_timeline`
  when every movable time is an offered slot and `TimelineEvaluator.evaluate()`
  accepts it. Otherwise it is the first accepted UI-offered candidate from
  `DeductionValidator.enumerate_accepted_prototype_c_timelines()`. It is
  applied only if the evaluator accepts it; if nothing is accepted, nothing
  is applied and the unit stays open. The feedback lists the facts the
  player's last attempt broke, which the partner timeline now satisfies.

### Final claim justification

A binary "Fits / Impossible" answer can be guessed 50% of the time. The claim
therefore needs a **verdict plus one supporting fact** selected from the
visible facts. The player identifies which temporal rule makes the claim
fail; this is not Prototype A's evidence presentation.

- **Correct** only when the verdict matches the accepted timeline, computed
  by `TimelineEvaluator.is_constraint_satisfied()` and never hardcoded, AND
  the fact is in `contradiction.supporting_constraint_refs`. Every listed
  fact is accepted; "Impossible" with an unrelated fact fails; "Fits" fails
  whenever every accepted timeline contradicts the claim.
- **Submission rules.** A verdict with no fact is refused without cost, and
  so is a verdict+fact pair that already failed. A counted failure never
  touches the accepted timeline.
- **Feedback.** The 1st failure gets a generic nudge. Later failures say
  whether the VERDICT or the FACT is off — never which fact is right. The 3rd
  failure requires assistance, which names the event the claim is about
  ("Find the confirmed fact that pins that event down"). After two more,
  partner resolution selects the correct verdict with the first authored
  supporting fact and explains it.
- **The claim unit starts completely fresh (Milestone 1.14.1).** Even when
  the timeline unit finished Assisted, `begin_next_unit()` resets only the
  local phase/failures — the claim's own `%ResolutionStatusLabel` reads a
  full budget, never "Assisted", while the separate `%RunResultLabel` still
  explains the run-wide result was reached during the (now-finished)
  timeline unit. See `docs/resolution-policy.md`, "Local unit state vs. run
  result".

**Primary actions in the fixed footer (Milestone 1.14.1).** Hint and Check
Timeline live in `%Footer`'s `%ActionRow`; Submit Verdict lives directly in
`%Footer` — none of them inside the scrolling `%BodyScroll`/`%ClaimPanel` —
so opening assistance or long feedback can never push either primary action
offscreen at 1280×720.

**What "supports" means, machine-checked.**
`DeductionValidator.prototype_c_facts_ruling_out_claim()` returns every
visible fact that, **on its own**, rules the claim out. Such a fact is
satisfiable on the board, yet no placement of the events it and the claim
reference satisfies both. Fixed events sit at their locked times; the other
referenced events range over the case's own `time_slots`.

The always-on validator requires `supporting_constraint_refs` to equal that
set exactly, so no genuinely valid justification can be rejected and no
unrelated one accepted. The check is cheap: only facts sharing an event with
the claim are enumerated, over at most `|time_slots|^3` placements. For X/Y/Z
the set is exactly the bystander errand's own confirmed window
(`c_shredding_window` / `c_bin_window` / `c_pallet_window`). The overlap fact
shares the event but does not rule the claim out by itself.
`prototype_c_content_test.gd` re-proves the equality, checks the facts hold
in every accepted timeline, and drives the real controller over every fact.

## Recorder integration

Reuses `DeductionLabRecorder` (`scripts/deduction/deduction_lab_recorder.gd`)
completely unmodified — same outer envelope (`schema_version: 1`), same
Start/Stop/Clear/Export controls, same safe-filename export, same
off-by-default/local/no-network/no-PII stance
(`docs/deduction-lab.md`, "Local playtest recorder"). The shared
resolution-policy vocabulary below is `event_schema_version: 2` (Milestone
1.14.1 — see `docs/deduction-lab.md`, "Recorder schema"). `"prototype":
"timeline_reconstruction"` distinguishes an export from the Lab's own
`"deduction_lab"`, Prototype A's `"statement_contradiction"` and Prototype
B's `"clue_connection"` recordings. Every event uses `SOURCE_PLAYER_PREVIEW`
(no Author/Debug mode exists in this milestone either). Recording can be
started **before** pressing Start on the case (reading the case id from the
picker), the same deliberate ordering A/B's own recorder controls use, so
`prototype_started` is actually capturable.

Event vocabulary (`PrototypeCController` decides what/when to record; the
recorder itself carries none of this):

| Event | When |
|---|---|
| `prototype_started` | `start()` — once per run |
| `timeline_fact_opened` | The first time a given fact is opened (`open_fact()`) |
| `event_selected` | Selecting a movable event (`select_event()`, or the implicit select inside `place_event()`) |
| `event_placed` | Placing a previously-unplaced event into a slot |
| `event_moved` | Placing an already-placed event into a DIFFERENT slot |
| `event_removed` | Removing a placed event back to the tray |
| `timeline_submitted` | Every genuinely new submission (never a blocked-duplicate resubmit) — payload: sequence, normalized (event-id-sorted) placement map, moves since the previous submission, facts-opened count, evaluator category, violation count |
| `timeline_rejected` | Immediately alongside `timeline_submitted` when the category isn't `timeline_consistent` |
| `timeline_accepted` | Immediately alongside `timeline_submitted` when the category is `timeline_consistent` |
| `violation_shown` | Alongside a rejection — payload: the violated required constraint ids (internal ids for analysis only; the UI never renders a raw id back to the player) |
| `hint_revealed` | Each new hint level (never a repeat of an already-exhausted ladder) |
| `claim_answered` | Every counted final-claim answer — payload: attempt number, "fits"/"impossible", `justification_constraint_id`, whether it was correct |
| `claim_justification_result` | Alongside it (Milestone 1.14) — payload: attempt, `justification_constraint_id`, `verdict_correct`, `justification_valid`, `correct` |
| `contradiction_resolved` | When the claim is resolved — payload `attempt`, `resolved_by` (`player`/`partner`) |
| `prototype_completed` | Acknowledging a resolved claim — payload is the full stats dict |
| `prototype_abandoned` | Return to Lab (or Esc) with real progress and no completion |

Since Milestone 1.14 the controller also records the shared resolution
events (`formal_commit_*`, `run_resolution_result_changed` (Milestone 1.14.1;
renamed from `resolution_tier_changed`), `assistance_*`,
`partner_resolution_*` — with `unit` 0 for the timeline and 1 for the claim,
and the partner timeline's `source`) and `prototype_restarted`. The timeline
unit and the claim unit are separate resolution units — `begin_next_unit()`
between them resets only the local phase/failures, never the run-wide
result, so the claim unit's OWN status always starts fresh even when the
timeline finished Assisted (`docs/resolution-policy.md`, "Local unit state
vs. run result"). `prototype_started` carries `run`, `timeline_accepted`
carries `resolved_by`, and `prototype_completed` / `prototype_abandoned`
carry a `resolution` summary.

`timeline_submitted`'s placement map is normalized (sorted by event id)
before recording, matching Prototype B's own "normalize attempt item IDs for
deterministic exported payloads" stance. No full localized text (event
labels, fact sentences, the claim's own statement, explanations) is ever
recorded — only ids, times, categories and counts.

## Validation

`DeductionValidator._validate_prototype_c()` (called from `validate_case()`
whenever a case declares `prototype_c`) and `collect_prototype_c_text_keys()`
(wired into `ContentValidator._validate_deduction_cases`, alongside the base
`collect_text_keys()` and Prototype A's/B's own) check: `fixed_events`/
`movable_events` partition every timeline event exactly once each; every
fixed event has exactly one `fixed_time` constraint and no movable event has
one; `time_slots` entries are valid, distinct `"HH:MM"` strings that never
let a movable event's duration cross midnight; every REQUIRED constraint has
a `visible_constraint_facts` entry (translated in both locales) and every
OPTIONAL constraint does not; `contradiction.claim` is a real `statement`
claim; `contradiction.constraint_ref` is a real OPTIONAL constraint sourced
from that same claim and absent from `visible_constraint_facts`;
`hint_ladder` has exactly 4 translated entries; and, since Milestone 1.14,
`contradiction.supporting_constraint_refs` is a non-empty, duplicate-free
list of visible facts sharing an event with the claim that equals EXACTLY
the facts ruling the claim out on their own
(`prototype_c_facts_ruling_out_claim()`, cheap enough to run every time). The two heavier, bounded
"at least one accepted timeline exists" / "every accepted timeline
contradicts the claim" checks are deliberately run only by
`prototype_c_content_test.gd`, not by this always-on validator — see
"Candidate time-slot domain" above for the measured reasoning.

## Testing

| File | Covers |
|---|---|
| `scenes/test/prototype_c_controller_test.gd` | Fresh interaction state per run, isolation from a `DeductionLabController`'s/`PrototypeAController`'s/`PrototypeBController`'s own state, fixed events locked against every mutator, select/place/move/remove (including two events legally sharing a slot), incomplete-board submission gating, invalid-timeline rejection with retained placements, identical-resubmission blocking until a move, acceptance via the REAL evaluator (not exact-solution equality, proven with two DIFFERENT accepted placements), an optional constraint never blocking acceptance, hints, the final claim check (wrong "Fits" preserves state and allows retry; correct "Impossible" resolves it), idempotent `acknowledge_claim()`, stats/abandonment, and a structural check that `DeductionSession` is never referenced at all. Pure/autoload-free — a dedicated fixture, `deduction_fixtures.gd`'s `prototype_c_case()`. Milestone 1.14 adds moves never consuming commits, any previously failed placement blocked, category-then-fact feedback, assistance naming the critical pair without moving events, a partner timeline applied only when the evaluator accepts it, and the verdict + supporting-fact claim: every supporting fact accepted (fixture `c_b_after_fixed`), unrelated facts and "Fits" rejected, the timeline untouched. Also claim feedback levels and duplicates, claim assistance/partner resolution, telemetry and restart. |
| `scenes/test/prototype_c_presenter_test.gd` | The player view's exact allow-listed keys (18 before acceptance since Milestone 1.14); a spoiler sweep against real X/Y/Z content both BEFORE and AFTER acceptance (no domain id/structural role/raw constraint field ever reaches it, even once the claim legitimately appears); the claim key's entire absence before acceptance and presence after; the resolution key's entire absence until the claim is correctly resolved, with the interpolated player-specific time; fact text gated on opened; hint progression; and the violation/claim feedback mappings for every outcome. Milestone 1.14 adds the claim form's neutral keys, progressive feedback on real X/Y/Z (no fact first, one verbatim fact next), assistance gating, the labeled partner timeline, claim feedback levels, localized status and the 12-line summary. |
| `scenes/test/prototype_c_content_test.gd` | X/Y/Z walked once in structural terms: 7 events/2 fixed/5 movable; the authored solution is offered and passes; every required constraint has a translated fact and every optional one doesn't; the universal-contradiction proof (every one of `enumerate_accepted_prototype_c_timelines()`'s ~8 accepted placements per case fails the disputed claim's constraint) — the one heavy, bounded check deliberately kept out of the always-on validator; an alternate valid timeline exists and differs from the authored one; an optional violation never blocks acceptance; a deliberately wrong placement is rejected; translations resolve; and the Prototype C structural-signature shape matches across all three cases. Milestone 1.14 adds that the supporting facts equal `prototype_c_facts_ruling_out_claim()` and hold in every accepted timeline, and that the real controller accepts exactly those facts. |
| `scenes/test/prototype_c_scene_test.gd` | **FULL-only** (needs a real scene tree, like `smoke_test.gd`/`prototype_a_scene_test.gd`/`prototype_b_scene_test.gd`): launching from the Lab with/without an active Lab case (and that launching hides, never resets, Prototype A AND Prototype B if either was open); fixed events rendered locked with no buttons; select/place/move/remove through real buttons; Check disabled until complete, then invalid-then-corrected with retained placements and visible violation feedback; an alternate valid timeline also accepted; fact inspection; hint reveal; the final claim phase (wrong then correct, with the interpolated time visible in the rendered label); completion with the 12-line resolution summary (Milestone 1.14); restart/return confirmation (cancelling preserves the run exactly); recorder controls and the exported schema/event vocabulary (including the normalized placement map); F1 hide/show session preservation; all three cases accepting their own authored solution; bilingual coverage; and the Milestone 1.12 long-feedback layout regression applied to this scene too. Milestone 1.14 adds category-only first feedback, the verdict + justification form, timeline and claim assistance/partner resolution through the footer, the Assisted summary, restart recording, and attempts preserved across F1 and locale switches. |

All four are wired into FAST/FULL per the existing policy: the three pure
ones (controller/presenter/content) are in **both**; the scene test is
**FULL-only**. `prototype_c_content_test.gd` costs about 1.5 seconds by
itself (the one file in this milestone that does real, bounded enumeration
work) — everything else costs a fraction of a second, matching the rest of
the deduction test suite.

## Out of scope

Deliberately not built in this milestone (see the milestone brief's own "Out
of scope" list): a free-form timeline editor, unrestricted drag-only
interaction, multiple-day timelines or midnight crossing, a generic
constraint solver, a clue graph, statement-evidence presentation (Prototype
A's job), a relation picker, a final accusation, investigation gameplay,
production save integration, canon case content, custom art/audio/polish, an
analytics backend, network telemetry, and choosing a core mechanic (that
decision is deferred to the full A/B/C rotation —
`docs/deduction-playtest-plan.md`, now that all three mechanics exist).

## Known limitations

- **No display-server visual QA in this environment** — see the milestone's
  final report for exactly what was/wasn't checked. Headless scene tests
  prove wiring and structure, not pixels (`docs/architecture.md`'s "Known
  limitations"; `docs/prototype-a.md`'s own "Layout" note on the same
  headless-geometry limitation this milestone's regression test works around
  structurally).
- **The candidate time-slot domain is deliberately small (6 per case)**, an
  audited, content-forced departure from a first 8-slot design that measured
  ~1.5s/case to enumerate exhaustively — documented above and in the
  architecture decision box. A future case with a genuinely different
  constraint-graph shape (more interacting event pairs, say) would need its
  own domain re-tuned the same way, verified the same way (direct
  enumeration through the real evaluator, not by inspection).
- **No production integration.** Debug-only, non-canon, not linked from
  `Main.gd`, no save/load — identical stance to the Deduction Lab, Prototype
  A and Prototype B.
- **Recorder has no rotation/size cap**, same accepted limitation
  `docs/deduction-lab.md`/`docs/prototype-a.md`/`docs/prototype-b.md` already
  document for their own recorder use.
