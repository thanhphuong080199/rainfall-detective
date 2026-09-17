# Prototype A — Statement Contradiction (Milestone 1.11)

The first genuinely playable deduction interaction, built on the Milestone
1.9/1.9.1 deduction foundation (`docs/deduction-system.md`) and reusing the
Milestone 1.10 Deduction Lab's recorder unchanged (`docs/deduction-lab.md`).
**Debug-only, non-canon, not the final game loop.** It exists to test one
narrow question, stated in the milestone brief:

```
Read testimony
→ identify a questionable statement
→ choose one evidence item
→ present it
→ receive a clear logical explanation
→ expose the contradiction
```

Read `docs/deduction-system.md` first (the proof-set contract this all sits
on), then `docs/deduction-prototype-cases.md` (what X/Y/Z actually contain)
and `docs/deduction-lab.md` (the recorder this reuses, and why the Lab itself
stays mechanic-neutral). `docs/deduction-playtest-plan.md` has the A/B/C
comparison protocol and, since this milestone, Prototype A's own facilitator
script.

## What this is not

No multi-clue connection, no relation picker, no clue graph, no timeline
placement, no final-theory construction — those are Prototypes B and C
(`docs/deduction-playtest-plan.md`). Exactly one current statement, exactly
one presented evidence item, relation `refutes`, statement-by-statement
cross-examination. Not a courtroom system, not investigation/evidence
acquisition (all evidence is available from the start). Since Milestone 1.14
it has a bounded **credibility** budget per testimony part
(`docs/resolution-policy.md`), but never a health bar that ends the run. A
spent budget leads to acknowledged assistance and, at worst, partner
resolution — never a game over.

## Architecture — reuse, not a parallel system

```
                 PrototypeA (scenes/debug/PrototypeA.tscn + scripts/debug/prototype_a.gd)
                           │  owns
              ┌────────────┴────────────────────┐
              ▼                                  ▼
   PrototypeAController                 DeductionLabRecorder
   (interaction state: round,           (Milestone 1.10, REUSED
    statement, selection, hints,         UNCHANGED — see "Recorder
    stats, completion — a FRESH,         events" below)
    isolated DeductionSession per run)
              │  reads case_def via ContentDB, holds ONE DeductionSession
              ▼
   DeductionEvaluator / DeductionSession
   (unchanged production code — every submission calls into this,
    nothing is reimplemented)
              │
              ▼
   PrototypeAPresenter (scripts/deduction/prototype_a_presenter.gd)
   build_player_view()  → spoiler-safe, allow-listed view model
   build_feedback()     → evaluator category → player-facing text
```

| Piece | File | Kind |
|---|---|---|
| `PrototypeAController` | `scripts/deduction/prototype_a_controller.gd` | `class_name` `RefCounted`, pure/autoload-free |
| `PrototypeAPresenter` | `scripts/deduction/prototype_a_presenter.gd` | `class_name` static helper, pure/autoload-free |
| The scene | `scenes/debug/PrototypeA.tscn` + `scripts/debug/prototype_a.gd` | a normal `Control` scene, instanced as a **permanent child of `DeductionLab.tscn`** (not `DebugPanel` directly) |
| Lab wiring | `scenes/debug/DeductionLab.tscn` + `scripts/debug/deduction_lab.gd` | one new "Launch Prototype A — Statement Contradiction" button in the case row |
| Recorder | `scripts/deduction/deduction_lab_recorder.gd` | **unmodified** Milestone 1.10 class — see "Recorder events" |
| Content | `data/deductions/prototypes/*.json`'s new optional `prototype_a` object | loaded by the existing `ContentDB` deduction-case loader, no new content category |

**No new autoload.** Same reasoning `docs/deduction-system.md`/
`docs/deduction-lab.md` already give: one scene needs this, not several
unrelated ones. **No production `GameState`/save-schema changes** — a
Prototype A run is exactly as persisted as the rest of the deduction
foundation (not at all).

```
DECISION: PrototypeAController owns its interaction state (round, current
statement, selected evidence, hint levels, stats) but does NOT own or touch
the DeductionLabRecorder's session-signal wiring the way deduction_lab.gd
does for the Lab. Instead the controller calls recorder.record(event, ...)
directly for a FIXED Prototype A event vocabulary (see "Recorder events").

WHY: The Lab's recorder.connect_session() auto-records DeductionSession's
own six signals (evidence_opened, proof_committed, claim_resolved,
deduction_unlocked, hint_revealed, case_solved) — the right shape for an
author inspecting a session from outside. Prototype A's telemetry needs are
different and more precise: per-attempt payloads that include the ROUND and
the required/optional/unsuccessful OUTCOME (data the raw signals don't
carry), hints that are Prototype-A-owned data rather than DeductionSession's
own hint machinery (see the next decision), and strict idempotency on
resubmission (no duplicate telemetry for an already-resolved claim) — all of
which needs to be decided in ONE place next to where the classification
already happens, not reconstructed from six generic signals after the fact.

IMPACT: DeductionLabRecorder itself needed zero changes (its `start()`
already took a free-form `prototype` string, and its public `record()` is
already generic) — this is the "minimal generalization" the milestone asked
for: reusing the exact same class with a new prototype id and a new,
UI-owned event vocabulary, not a second telemetry implementation. All
existing Deduction Lab recorder tests and behavior are completely unaffected.
```

```
DECISION: Hints are Prototype-A-owned data (case_def.prototype_a.rounds[].
hint_ladders: {claim_id: [4 translation keys]}) and Prototype-A-owned
progress (PrototypeAController._hint_levels), NOT DeductionEvaluator.
request_hint()/case_def.hints/DeductionSession.advance_hint().

WHY: The base hint contract (docs/deduction-system.md, "Hint ladders") can
only target a "deduction"/"conclusion" claim — level 4 is validated to
"reveal_deduction", literally a claim of kind deduction. A Prototype A
required refutation is always a "statement", which the base contract has no
hint shape for at all. Reusing DeductionSession.advance_hint() to track
progress anyway would also be a direct DeductionSession mutation the
milestone brief explicitly forbids (that method's own doc comment marks it
"Called by DeductionEvaluator only").

IMPACT: A second, smaller hint ladder shape lives in prototype_a's own data
(4 plain translation keys, no kind/question/categories/evidence typing — see
"Data contract" below), validated by DeductionValidator._validate_prototype_a
rather than the base _validate_hints/_validate_hint_level. Progress is
tracked entirely in PrototypeAController, discarded with the rest of a run's
state on Restart — never persisted, matching the base contract's own
save/load stance.
```

```
DECISION: st_oren_break_in (candidate_staging_claim) gained a second,
alternate, single-evidence refutes proof set — {"relation": "refutes",
"requires": ["e_forced_window"]} — added identically (by structural role) to
all three cases. Its "compatible": ["e_forced_window"] entry was removed
since that evidence is now a full proof-set requirement, not merely
compatible-but-insufficient.

WHY: The milestone requires "each required contradiction must have at least
one single-evidence refutes proof set" (Prototype A only ever submits one
item), but the ORIGINAL proof set for this claim requires TWO evidence items
(e_latch_guide + e_window_latch, the taught-rule + bent-direction pair) — a
genuine two-clue combination appropriate for a future Prototype B, not A.
The evidence text this milestone's "R4 last seen" rule already establishes
(docs/deduction-prototype-cases.md, section 1.1) is independently
sufficient: "Debris from the forced opening lies on top of fresh prints
leading to the target" means the prints existed BEFORE the opening was
forced — proving forced-from-inside without needing the latch-bend-direction
rule at all. This is a real, self-contained piece of reasoning, not an
arbitrary shortcut.

IMPACT: The ORIGINAL two-evidence proof set is untouched and still the
authoritative "prove the staging via the taught physical rule" path for
Author Inspector/any future Prototype B content — Prototype A's UI simply
can't reach it (it never submits two items), so it's a dormant, harmless
alternate. DeductionValidator.structural_signature() (and therefore
validate_structural_equivalence()) picks up both the new proof set and the
compatible-list change automatically, so X/Y/Z staying in lockstep is
machine-checked, not just asserted by convention.
```

## Data contract

An optional `prototype_a` object alongside the base deduction case
(`docs/deduction-system.md`, "Data contract"), validated only when present
(`DeductionValidator._validate_prototype_a` — every other deduction case,
including the hand-built fixtures, is untouched by this section):

```json
"prototype_a": {
  "evidence_pool": ["e_lost_property_sheet", "e_forced_window", "e_shredding_log", "e_wing_camera", "e_window_latch", "e_tram_tap"],
  "rounds": [
    {
      "id": "round_1",
      "statements": ["st_mara_went_to_harbor", "st_mara_badge_on_cardigan", "st_oren_never_touched"],
      "required_refutations": ["st_oren_never_touched"],
      "optional_refutations": [],
      "success_explanations": { "st_oren_never_touched": "DED_PROTO_X_PROTOA_EXP_DENIAL" },
      "witness_responses": { "st_oren_never_touched": "DED_PROTO_X_PROTOA_RESP_DENIAL" },
      "hint_ladders": { "st_oren_never_touched": ["KEY_1", "KEY_2", "KEY_3", "KEY_4"] }
    },
    { "id": "round_2", "...": "same shape, the required refutation plus the optional innocent lie" }
  ],
  "completion_text": "DED_PROTO_X_PROTOA_COMPLETION"
}
```

| Field | Meaning |
|---|---|
| `evidence_pool` | Evidence ids (from the case's own `evidence` array) shown in Prototype A's Case File — a curated subset (5-7 items for X/Y/Z), not the full 11-item deduction dossier. Every item must be available from the start (no `unlock_requires`). |
| `rounds[].statements` | Claim ids (must be `kind: "statement"`), shown in order for that round only — a future round's statements are never shown. |
| `rounds[].required_refutations` | Statement ids that must be refuted to advance. Each needs at least one `refutes` proof set with exactly one evidence item. |
| `rounds[].optional_refutations` | Statement ids (the innocent lie) that are logically valid to refute but never required and never block/replace a required refutation. Same single-evidence-solvable rule applies. |
| `rounds[].success_explanations` / `witness_responses` | One translation key per required/optional target — the logical explanation and the in-fiction reaction shown on a successful refutation. |
| `rounds[].hint_ladders` | One 4-translation-key array per **required** target — see "Hints" below. Never the base contract's `{kind, question, categories, evidence, deduction}` shape. |
| `completion_text` | Translation key shown once both required contradictions (across all rounds) are exposed. |

Authoring rule, enforced by the validator: every statement listed in
`rounds[].statements` must end up in exactly one of `required_refutations`/
`optional_refutations` if it's false (`mistaken`/`deceptive`), and in
neither if it's `true`/`incomplete` — so a true statement can never be
misconfigured as a target, and no false statement can be shown with no
accepted outcome.

`DeductionValidator.structural_signature()` (used by
`validate_structural_equivalence()`, already run by `ContentValidator`) was
extended with `prototype_a:` lines describing the evidence pool and each
round's statement/required/optional/hint-target roles — X, Y and Z's
Prototype A layers are machine-checked to share one shape, exactly like the
base `credential_misuse_v2` proof graph.

## Playable flow

1. **Launch** — the Deduction Lab's "Launch Prototype A — Statement
   Contradiction" button opens the scene, defaulting the case picker to
   whichever case the Lab currently has active (or leaving it for the
   facilitator to pick if none). Nothing starts until **Start** is pressed —
   that's what creates a fresh, isolated `PrototypeAController`/
   `DeductionSession`, never the Lab's own.
2. **Case briefing** — case title/description, suspects, and the objective
   line are always visible above the play area; the evidence Case File can
   be opened and read before or during cross-examination.
3. **Cross-examination** — Previous/Next move between the current round's
   statements (each row shows its text and, once resolved, whether it was
   exposed as required or found as an optional contradiction — never
   before). Selecting an evidence item and the current statement together
   form the confirmation view; **Present Evidence** submits exactly that
   pair with relation `refutes` through `DeductionEvaluator.commit_attempt()`.
4. **Feedback** — a panel shows the mapped result (see "Feedback mapping"
   below); **Continue** dismisses it and, only if every required refutation
   in the current round is now resolved, advances to the next round or (on
   the last round) completes the prototype.
5. **Completion** — the authored `completion_text`, plus the shared
   resolution summary (elapsed time, formal commits, failed formal commits,
   hints used, assistance used, resolution tier, partner resolution used —
   `docs/resolution-policy.md`) and optional contradictions found. Everything
   is localized; raw ids never appear. Restart, Export
   Recording and Return to Lab are all offered here too.

## Feedback mapping

`PrototypeAPresenter.build_feedback(case_def, result)` — `result` is
whatever `PrototypeAController.present_evidence()` returned:

| `result.category` (never shown raw) | Player sees |
|---|---|
| `valid_refutation`, outcome `required` | Success headline + the round's `success_explanations`/`witness_responses` for that claim |
| `valid_refutation`, outcome `optional` | A distinct "found something, not the one you need" headline + its own explanation/response — never called wrong |
| `irrelevant_evidence` | Generic: "that evidence doesn't address what this statement claims" |
| `insufficient_evidence` | Generic: "raises suspicion, but doesn't directly contradict this statement alone" |
| `compatible_not_proof` | Generic: "consistent with the statement — doesn't actually contradict it" |
| `invalid_input` (nothing selected, etc.) | Generic: "select a statement and one piece of evidence" — no session mutation happens for this case |
| `invalid_input`, reason `duplicate_failed_attempt` (Milestone 1.14) | "You've already presented that evidence against this statement" — costs no credibility |
| `invalid_input`, reason `submission_locked` (Milestone 1.14) | "Submissions are paused — accept assistance or resolve with your partner first" |

The four generic messages are static `UI_PROTOTYPE_A_FEEDBACK_*` keys, never
per-case content — only a genuine success reveals case-authored text.
Resubmitting an already-resolved claim reclassifies (via
`DeductionEvaluator.classify_attempt()`, side-effect-free) instead of
recommitting, so it never mutates the session, never increments the
submission/incorrect counters, and never records a duplicate
`attempt_submitted`/`contradiction_resolved` event.

Since Milestone 1.14, every counted failure also shows a generic rebuttal
(`UI_PROTOTYPE_A_REBUTTAL`, naming only the speaker) and its credibility/tier
consequence (`ResolutionPresenter.build_commit_notice()`). A partner
resolution is headed "Resolved with your partner" and names the evidence the
partner presented (`UI_PROTOTYPE_A_PARTNER_NOTE`), alongside the authored
explanation.

## Hints

Optional, per required target, 4 plain translation keys (see "Data
contract"). The Hint button is always visible next to Present Evidence
(never auto-revealed); it disables once a ladder is exhausted, and is absent
entirely for a statement with no ladder (true/incomplete statements and the
optional lie never get one — only required refutations do). Revealing a
level never displays an internal id, and level 4 (like the base contract's
own level 4) only ever narrows the search — it never states the conclusion
or auto-submits anything.

## Spoiler boundary

`PrototypeAPresenter.build_player_view(case_def, controller)` returns
`{"view": ..., "handle_map": ...}` — the exact same allow-list/opaque-handle
pattern `DeductionLabPresenter` established (`docs/deduction-lab.md`,
"Player Preview"). `view` never contains a domain id, `structural_role`,
`veracity`, `proof_sets`/`compatible`, `ground_truth`, or a statement's
required/optional classification before the session has actually resolved
it; `handle_map` is kept privately by `scripts/debug/prototype_a.gd` and
resolved back to a real id only at the moment a click handler calls a
production API (`controller.open_evidence()`/`select_evidence()`). Only the
CURRENT round's statements ever appear — a future round's text is invisible
until the player actually reaches it. `deduction_lab_presenter_test.gd`'s
own structural + content sweep methodology is mirrored in
`prototype_a_presenter_test.gd` against the real X/Y/Z content.

## Recorder events

Reuses `DeductionLabRecorder` (`scripts/deduction/deduction_lab_recorder.gd`)
completely unmodified — same outer schema (`schema_version: 1`), same
Start/Stop/Clear/Export controls, same safe-filename export, same
off-by-default/local/no-network/no-PII stance. The resolution-policy event
vocabulary below is `event_schema_version: 2` (Milestone 1.14.1 — see
`docs/deduction-lab.md`, "Recorder schema", and `docs/resolution-policy.md`)
(`docs/deduction-lab.md`, "Local playtest recorder"). `"prototype":
"statement_contradiction"` distinguishes an export from the Lab's own
`"deduction_lab"` recordings. Every event uses `SOURCE_PLAYER_PREVIEW` (no
Author/Debug mode exists in this milestone).

Recording can be started **before** pressing Start on the case (reading the
case id from the picker, not from an active session) — this is deliberate,
so `prototype_started`/`round_started` are actually capturable, matching the
facilitator script's own order ("start recording", then "begin the run").
Starting/restarting a run never auto-stops an in-progress recording (unlike
the Lab's own case-switch handler) for the same reason.

Event vocabulary (`PrototypeAController` decides what/when to record; the
recorder itself carries none of this):

| Event | When |
|---|---|
| `prototype_started` | `start()` — once per run |
| `round_started` | Entering round 0, and again on advancing to the next round |
| `statement_viewed` | The FIRST time a given statement is reached in this run |
| `statement_selected` | Every time the current statement changes (Previous/Next/row click) |
| `evidence_opened` | The first time a given evidence item is opened (via `DeductionSession.mark_evidence_opened()`) |
| `evidence_selected` | Choosing an item as the one to present (may repeat as the player changes their mind) |
| `attempt_submitted` | Every genuinely new submission (never for a resubmission on an already-resolved claim) — payload: sequence, round, statement id, evidence id, evaluator category, outcome (`required`/`optional`/`unsuccessful`) |
| `attempt_blocked_duplicate` | Milestone 1.14.2A — presenting a statement+evidence pair that already failed (previously silently dropped; see `docs/prototype-evaluation.md`) — payload: round, statement id, evidence id. Purely observational: never counted, never reaches the evaluator, never changes `present_evidence()`'s return value |
| `contradiction_resolved` | Only on a **newly** successful required/optional resolution — payload includes the outcome |
| `hint_revealed` | Each new hint level (never a repeat of an already-revealed level) |
| `round_completed` | On `acknowledge_feedback()`, once a round's required refutation(s) are all resolved |
| `prototype_completed` | Both rounds' required refutations resolved — payload is the full stats dict |
| `prototype_abandoned` | Return to Lab (or Esc) with real progress and no completion |

Payloads carry internal ids/categories for analysis; the UI never renders a
raw category or id from a recorded payload back to the player, and no full
localized text is ever recorded (`prototype_a_scene_test.gd`'s recorder test
spot-checks this against real translated names).

## Resolution policy (Milestone 1.14)

See `docs/resolution-policy.md` for the shared model. In Prototype A,
"Present Evidence" is the formal commit of a high-stakes confrontation.

- **Credibility.** The header's `%ResolutionStatusLabel` reads, in text,
  "Credibility: 3/3" — the CURRENT part's own state only. The separate
  `%RunResultLabel` reads "Run result so far: Independent" — the run-wide
  result, never merged into the credibility line (Milestone 1.14.1; see
  `docs/resolution-policy.md`, "Local unit state vs. run result"). Each
  testimony part (round) is one resolution unit with a fresh 3-credibility
  budget; the run-wide result never moves back down, and a fresh round is
  never itself labeled Assisted just because an earlier round used help.
- **What costs credibility:** only a genuinely evaluated failure
  (irrelevant, insufficient, or compatible-but-not-proof).
- **What never costs anything:**
  - nothing selected;
  - re-presenting a statement + evidence pair that already failed
    (`is_known_failed_pair()`);
  - an already-resolved statement;
  - a locked policy;
  - the valid optional innocent lie, or an accepted alternate refutation.
- **A failure** costs one credibility and shows a generic rebuttal, the
  category message and the consequence. It never reveals the correct
  evidence and never resets testimony or selections.
- **Third failure.** Present Evidence disables and the footer's
  `%AcceptAssistanceButton` appears.
  `PrototypeAController.accept_assistance()` pins the first unresolved
  required statement of the part. The view's `assistance` block, absent
  until then, names that statement ("Focus on what X said: …", also marked
  "[Partner focus]" in the statement list). It also shows that statement's
  own authored level-2 ladder text — a category hint that never names the
  evidence. The current selection is preserved.
- **Two assisted failures.** Blind presenting closes and
  `%PartnerResolveButton` ("Resolve with Partner") calls
  `resolve_with_partner()`. That commits the first authored single-evidence
  `refutes` proof set, classified first, through
  `DeductionEvaluator.commit_attempt()`. The feedback is labeled, names the
  presented evidence and shows the authored explanation. The part is then
  ready to continue — no game over, no replay.
- **Hints** raise the run-wide result (levels 1–2 → Guided, 3–4 → Assisted)
  and say so explicitly. The notice sits next to the Hint button.
- **Restart** is a new, recorded run (`prototype_restarted`).
- **Primary action in the fixed footer.** Present Evidence (and Hint) live
  in `%Footer`'s `%ActionRow`, not inside the scrolling `%BodyScroll` — so
  opening assistance or long feedback can never push them offscreen at
  1280×720 (Milestone 1.14.1).

Recorder additions:

- new events: `formal_commit_started` / `formal_commit_failed` /
  `formal_commit_succeeded`, `run_resolution_result_changed`,
  `assistance_offered` / `assistance_accepted`,
  `partner_resolution_offered` / `partner_resolution_used`,
  `prototype_restarted`;
- `contradiction_resolved` and `round_completed` carry `resolved_by`;
- `prototype_started` carries `run`;
- `prototype_completed` / `prototype_abandoned` carry a `resolution` summary.

## Validation

`DeductionValidator._validate_prototype_a()` (called from `validate_case()`
whenever a case declares `prototype_a`) and
`collect_prototype_a_text_keys()` (wired into
`ContentValidator._validate_deduction_cases`, alongside the base
`collect_text_keys()`) check: duplicate round ids; undefined
claim/evidence/hint references; a claim used as a target in more than one
round; empty `statements`/`required_refutations`; a required or optional
target with no single-evidence `refutes` proof set, or whose accepted
evidence is missing from `evidence_pool`; evidence in the pool that's locked
(`unlock_requires`) or doesn't exist; a displayed false statement with no
accepted outcome; a true/incomplete statement misconfigured as a target;
missing `success_explanations`/`witness_responses`/`completion_text`; a
required target's hint ladder that isn't exactly 4 non-empty entries; and
(via the extended `structural_signature()`) a Prototype A shape mismatch
between X/Y/Z. A warning (not an error) fires if the total required-
refutation count across all rounds isn't exactly 2, since that's the
milestone's designed 5-10 minute target, not a structural requirement.

## Layout (Milestone 1.12 fix)

Manual play surfaced a regression: when the feedback/explanation text under
a submission was long (especially in Vietnamese, which typically runs
longer than the equivalent English), it pushed the **Continue** button
outside the visible window at 1280×720, since the original `PrototypeA.tscn`
stacked `PlayArea`, `FeedbackPanel` (with `ContinueButton` inside it) and
`CompletionPanel` directly as siblings in one `VBoxContainer` with no
scrollable region — a `VBoxContainer` gives every non-expanding child its
full requested minimum size, so however tall the feedback text's wrapped
`Label` needed to be, the container just grew to fit it, past the window's
actual bottom edge.

The fix, applied without hardcoded text lengths, truncation, smaller fonts,
or per-language offsets: the scene now has a **fixed header** (title/case
row/objective/progress/status), a single **expandable `%BodyScroll`**
(`ScrollContainer`) holding `PlayArea`/`FeedbackPanel`/`CompletionPanel`
together, and a **fixed `%Footer`** (`VBoxContainer`) placed as a LATER
sibling of `%BodyScroll` in the outer `VBoxContainer`, holding
`ContinueButton`/`CompletionButtonsRow`/`RecorderRow`. A `VBoxContainer`
always honors a non-expanding sibling's minimum size, so `%Footer` (and
therefore Continue) can never be pushed outside the window by how long the
scrolling body's content is — the body clips and scrolls instead. Opening
feedback resets `%BodyScroll.scroll_vertical` to 0 and calls
`continue_button.grab_focus()`, so the headline is visible first and
keyboard users land on Continue immediately (`prototype_a.gd`'s
`_show_feedback()`). Milestone 1.14's windowed visual QA found that
`%FeedbackPanel` sat *below* `%PlayArea` inside the body, so resetting the
scroll showed the play area instead of the feedback. `%FeedbackPanel` is now
the body's first section in all three prototype scenes, and each scene test
asserts that order. Prototype B (`docs/prototype-b.md`) uses the identical
structure in `PrototypeB.tscn` from the start, so it never reproduces this
bug; the Deduction Lab's own screen (`DeductionLab.tscn`) was audited too
and found NOT to have the same defect — its `%Tabs` (`TabContainer`) is
itself the expanding element, and every tab already wraps its content in its
own `ScrollContainer` with no button living below variable-height text.

**Headless verification limitation.** Godot's `-s` `SceneTree` entry scripts
do not reliably compute real Control pixel geometry in this environment —
confirmed by direct experimentation while building the regression test (the
root `Window`'s `.size` collapses to a dummy 64×64 after the first
processed frame regardless of `project.godot`'s configured 1280×720 or an
explicit script-side override, and reasserting it afterward does not
propagate a fresh layout pass down through the existing Control tree). This
is the same class of limitation `docs/architecture.md`'s "Known
limitations" and `.claude/skills/godot-development` already name ("Headless
runs can't prove layout, visuals, real mouse routing, or feel"). So
`prototype_a_scene_test.gd`'s `_test_continue_button_stays_reachable_with_
long_feedback()` proves the fix through what headless CAN reliably assert
— see "Testing" below — and real on-screen pixel verification is a manual
QA step (see the Milestone 1.12 final report for exactly what was/wasn't
checked).

## Testing

| File | Covers |
|---|---|
| `scenes/test/prototype_a_controller_test.gd` | Fresh session per run, isolation from a `DeductionLabController`'s own session, statement/evidence navigation, one-evidence-only enforcement, required/optional/wrong-attempt classification through the real evaluator, idempotent resubmission, round/prototype completion via `acknowledge_feedback()`, hints, stats, abandonment, and a structural check that no `DeductionSession` mutator is ever called directly. Pure/autoload-free — a dedicated fixture, `deduction_fixtures.gd`'s `prototype_a_case()`. Milestone 1.14 adds the resolution policy: credibility consumed only by genuinely evaluated failures, the optional lie/alternate refutation (fixture `e_alt`)/duplicates/locked presentations costing nothing, assistance after three failures, assisted success, partner resolution through `commit_attempt()`, hint tier changes, telemetry and restart recording. |
| `scenes/test/prototype_a_presenter_test.gd` | The player view's exact allow-listed keys, a spoiler sweep against real X/Y/Z content, round-scoping (no future-round text), evidence text gated on opened, hint progression, and `build_feedback()`'s mapping for every evaluator category. Milestone 1.14 adds the `resolution_status` contract and localization, no raw policy ids, assistance/partner content gated by the policy on real X/Y/Z (never an accepted evidence name), the rebuttal/duplicate/locked/notice mapping, and the localized completion summary. |
| `scenes/test/prototype_a_content_test.gd` | X/Y/Z walked once in structural-role terms: the true/incomplete/required×2/optional role coverage, each target solvable with one evidence item that's actually in the pool, every pool item available from the start, true/incomplete statements never refutable, translations resolve, and the Prototype A structural-signature shape matches across all three cases. |
| `scenes/test/prototype_a_scene_test.gd` | **FULL-only** (needs a real scene tree, like `smoke_test.gd`/`deduction_lab_scene_test.gd`): launching from the Lab with/without an active Lab case, reading/selecting evidence via real buttons, wrong/correct/optional feedback, hint reveal, round transition and completion via real button clicks, restart/return confirmation (including that cancelling preserves the run exactly), recorder controls and the exported schema/event vocabulary, F1 hide/show session preservation, bilingual coverage, and (Milestone 1.12) `_test_continue_button_stays_reachable_with_long_feedback()` — the Continue-button layout regression: structural proof Continue lives outside the scrolling body, and behavioral proof it stays visible/focused with real-then-synthetic-long feedback text in both locales — see "Layout" above. Milestone 1.14 adds credibility → assistance → partner resolution through real buttons, the Assisted completion summary, attempts surviving locale/F1/cancelled restart, restart recording, and the resolution actions in the fixed footer. |

All four are in FAST and FULL (`docs/testing.md`) — the three pure ones cost
about a second together; the scene test needs the same real-scene-tree setup
`deduction_lab_scene_test.gd`/`smoke_test.gd` already pay for, so it's
FULL-only.

## Known limitations

- **No display-server visual QA in this environment** — see the milestone's
  final report for exactly what was/wasn't checked. Headless scene tests
  prove wiring, not pixels (`docs/architecture.md`'s "Known limitations").
- **Single fixed pairing of round → required/optional target**, matching
  X/Y/Z's shared shape. A case with a different round count or target
  distribution is legal per the validator but untested beyond the fixture.
- **No production integration.** Debug-only, non-canon, not linked from
  `Main.gd`, no save/load — identical stance to the Deduction Lab itself.
- **Recorder has no rotation/size cap**, same accepted limitation as
  `docs/deduction-lab.md` already documents for its own recorder — a single
  playtest session's scale is what this was built for.
