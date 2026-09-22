# Prototype B — Clue Connection (Milestone 1.12)

> **Milestone 1.16:** in production (`docs/core-loop-sandbox.md`) each
> core-loop unit runs `PrototypeBController` scoped to exactly ONE round, so
> "Commit Theory" commits a single deduction into the chapter run's shared
> session — the 1.15B contract's B, never a batch. This debug prototype keeps
> the batch theory described below; with no context the controller behaves
> exactly as documented here.

The second playable deduction interaction, built on the same Milestone
1.9/1.9.1 foundation (`docs/deduction-system.md`) and Milestone 1.10 Deduction
Lab (`docs/deduction-lab.md`) Prototype A (`docs/prototype-a.md`) used, and
launched the same way. **Debug-only, non-canon, not the final game loop.**
It exists to test one narrow question, stated in the milestone brief:

```
Read an investigation question
→ review available clues
→ place clues into connection slots
→ submit the connection
→ receive logical feedback
→ unlock the deduction
```

**Since Milestone 1.14** this loop is drafted and committed as a batch: both
questions are unverified drafts, and one "Commit Theory" checks them
together. See "Drafts and batch commit" below and `docs/resolution-policy.md`.

Read `docs/deduction-system.md` first (the proof-set contract this all sits
on), then `docs/deduction-prototype-cases.md` (what X/Y/Z actually contain),
`docs/deduction-lab.md` (the recorder this reuses, and why the Lab itself
stays mechanic-neutral), and `docs/prototype-a.md` (the first mechanic built
on the same foundation, and the milestone this one is deliberately kept
separate from). `docs/deduction-playtest-plan.md` has the A/B/C comparison
protocol and, since this milestone, Prototype B's own facilitator section.

## What this is not

No relation picker, no unrestricted clue graph, no draggable free-form
caseboard, no selecting more clues than the round's authored slot count, no
statement contradiction (that is Prototype A's job), no D2/final-case
synthesis, no final accusation — those are out of scope by design (see
"Out of scope" below and the milestone brief). Exactly two investigation
questions per case — drafted side by side and committed together since
Milestone 1.14 — each with a fixed number of visible connection slots; the player never picks
a relation, a statement to contradict, or the final wording of a deduction —
only which clues jointly establish it.

## Architecture — reuse, not a parallel system

```
                 PrototypeB (scenes/debug/PrototypeB.tscn + scripts/debug/prototype_b.gd)
                           │  owns
              ┌────────────┴────────────────────┐
              ▼                                  ▼
   PrototypeBController                 DeductionLabRecorder
   (interaction state: round,           (Milestone 1.10, REUSED
    placed clues, attempt/failure/       UNCHANGED — see "Recorder
    replacement counts, stats — a        events" below)
    FRESH, isolated DeductionSession
    per run)
              │  reads case_def via ContentDB, holds ONE DeductionSession
              ▼
   DeductionEvaluator / DeductionSession
   (unchanged production code — every submission calls into this,
    nothing is reimplemented)
              │
              ▼
   PrototypeBPresenter (scripts/deduction/prototype_b_presenter.gd)
   build_player_view()  → spoiler-safe, allow-listed view model
   build_feedback()     → evaluator category → player-facing text
```

| Piece | File | Kind |
|---|---|---|
| `PrototypeBController` | `scripts/deduction/prototype_b_controller.gd` | `class_name` `RefCounted`, pure/autoload-free |
| `PrototypeBPresenter` | `scripts/deduction/prototype_b_presenter.gd` | `class_name` static helper, pure/autoload-free |
| The scene | `scenes/debug/PrototypeB.tscn` + `scripts/debug/prototype_b.gd` | a normal `Control` scene, instanced as a **permanent child of `DeductionLab.tscn`**, a sibling of `PrototypeA` (not `DebugPanel` directly) |
| Lab wiring | `scenes/debug/DeductionLab.tscn` + `scripts/debug/deduction_lab.gd` | one new "Launch Prototype B — Clue Connection" button in the case row, next to Prototype A's own |
| Recorder | `scripts/deduction/deduction_lab_recorder.gd` | **unmodified** Milestone 1.10 class — see "Recorder events" |
| Content | `data/deductions/prototypes/*.json`'s new optional `prototype_b` object | loaded by the existing `ContentDB` deduction-case loader, no new content category |

**No new autoload.** Same reasoning `docs/deduction-system.md`/
`docs/deduction-lab.md`/`docs/prototype-a.md` already give: one scene needs
this, not several unrelated ones. **No production `GameState`/save-schema
changes** — a Prototype B run is exactly as persisted as the rest of the
deduction foundation (not at all).

```
DECISION: PrototypeBController reuses the BASE hint contract
(DeductionEvaluator.request_hint() / DeductionSession.get_hint_level())
directly, rather than inventing a second, Prototype-B-owned hint shape the
way PrototypeAController did.

WHY: Prototype A's required targets are STATEMENTS, which the base hint
contract has no shape for at all (level 4 is validated to "reveal_deduction",
literally a claim of kind deduction — docs/deduction-system.md, "Hint
ladders"). Prototype B's targets are exactly the opposite: every round
targets a real "deduction" claim (D1, D3), and every REQUIRED deduction
already has a base hints[] ladder (DeductionValidator enforces this — see
"required deduction or conclusion with no hint ladder" in
docs/deduction-system.md, "Content validation"). Reusing the real API is
literally the milestone's own instruction ("prefer using the existing
deduction hint ladders and real session/evaluator hint APIs... Do not
duplicate hint state in Prototype B if DeductionSession already supports the
target correctly").

IMPACT: PrototypeBController.reveal_next_hint()/get_hint_level() are thin
pass-throughs with zero private hint state of its own — contrast with
PrototypeAController's _hint_levels dictionary and Prototype-A-owned
hint_ladders data. Progress is tracked entirely by DeductionSession, exactly
like the Deduction Lab's own Player Preview hint usage, and is discarded with
the rest of a run's state on Restart (a fresh DeductionSession), matching the
base contract's own save/load stance.
```

```
DECISION: Round 2 (the "staged entry" round) uses slot_count 3, not the
milestone brief's illustrative "two clue slots" diagram.

WHY: The brief's own ASCII sketch shows two inputs ("Staging sign" +
"Physical contradiction") for D3. The REAL, already-validated D3 proof set
(ded_break_in_staged / ded_hatch_staged / ded_fence_staged) requires all
THREE roles — staging_sign + physical_rule_or_reference + staging_contradiction
— and deduction_cases_test.gd (predating this milestone) already asserts,
for all three cases, that BOTH 2-of-3 subsets ({sign, contradiction} and
{rule, contradiction}) are INSUFFICIENT by design: "the contradiction without
the taught rule must not prove staging" and "the rule + contradiction without
the staging sign must not prove staging." The third possible pair (sign +
rule, without the observed contradiction) would be logically UNSOUND to
accept — you cannot apply a bend-direction rule without observing the bend.
So no 2-item subset of D3's evidence can legitimately prove it; the deduction
genuinely needs all three facts together.

ALTERNATIVES CONSIDERED: (a) add a new, weaker 2-item alternate proof set to
the D3 deduction claim — rejected: it would either exactly match one of the
two pairs deduction_cases_test.gd already asserts is insufficient (breaking
that established, deliberate test) or accept the unsound sign+rule pair;
(b) treat the physical_rule_or_reference as "always-known background
knowledge" auto-included outside the player's 2 chosen slots — rejected: the
milestone's own validator requirement ("proof cardinality inconsistent with
visible slots") and "every accepted proof alternatives have the configured
slot count" both require the visible slot count to equal the accepted proof's
actual cardinality, not a slot count smaller than what's actually submitted
to the evaluator.

IMPACT: Round 2 uses 3 slots, matching D3's real, already-tested proof
requirement exactly. The milestone's higher-level goals — several clues,
none alone (or in any smaller combination) sufficient, jointly proving
staging, "D3 cannot be solved by one clue" — are all still met, just with 3
inputs instead of 2. prototype_b_content_test.gd's
_test_d3_requires_every_authored_clue() and
_test_no_proper_subset_resolves_either_target() directly assert this for all
three cases. See the final Milestone 1.12 report for the full audit.
```

## Data contract

An optional `prototype_b` object alongside the base deduction case
(`docs/deduction-system.md`, "Data contract"), validated only when present
(`DeductionValidator._validate_prototype_b` — every other deduction case,
including the hand-built fixtures, is untouched by this section):

```json
"prototype_b": {
  "evidence_pool": ["e_door_log", "e_tram_tap", "e_harbor_photo", "e_route_note", "e_forced_window", "e_latch_guide", "e_window_latch", "e_lost_property_sheet", "e_back_door_sighting"],
  "rounds": [
    {
      "id": "round_1",
      "question": "DED_PROTO_X_PROTOB_Q1",
      "target": "ded_badge_misused",
      "relation": "supports",
      "slot_count": 3,
      "success_explanation": "DED_PROTO_X_PROTOB_EXP1"
    },
    {
      "id": "round_2",
      "question": "DED_PROTO_X_PROTOB_Q2",
      "target": "ded_break_in_staged",
      "relation": "supports",
      "slot_count": 3,
      "success_explanation": "DED_PROTO_X_PROTOB_EXP2"
    }
  ],
  "completion_text": "DED_PROTO_X_PROTOB_COMPLETION"
}
```

| Field | Meaning |
|---|---|
| `evidence_pool` | Evidence ids (from the case's own `evidence` array) shown in Prototype B's Case File — a curated subset (9 items for X/Y/Z: the 7 items either round's accepted proof actually needs, plus 2 genuine distractors relevant to OTHER parts of the base proof graph), not the full 11-item deduction dossier. Every item must be available from the start (no `unlock_requires`). |
| `rounds[].question` | Translation key for the round's open investigation question (e.g. "What does the credential record imply?"). |
| `rounds[].target` | A claim id. **Must be a `deduction`** — never a statement, hypothesis, explanation or the final conclusion (the player never contradicts a statement here; that is Prototype A). |
| `rounds[].relation` | The relation the submission is checked against (always `supports` for X/Y/Z's D1/D3 targets — `docs/deduction-system.md`'s full relation vocabulary still applies generically). |
| `rounds[].slot_count` | The number of visible connection slots — must equal the size of at least one of the target's own authored proof sets with this relation (`_validate_prototype_b_target` — "proof cardinality inconsistent with visible slots"), and must be ≥ 2 (a single clue can never be enough — `PROTOTYPE_B_MIN_SLOT_COUNT`). |
| `rounds[].success_explanation` | Translation key: the authored explanation of why the selected clues, together, establish the target — shown on success alongside the now-revealed deduction claim's own (already-translated) text. |
| `completion_text` | Translation key shown once both rounds are resolved. Says the player has formed two useful deductions, never that the whole case is solved (see "Out of scope"). |

Authoring rules, enforced by the validator:
- the target must be a `deduction` claim, never any other kind;
- the target must not also be a Prototype A round's `required_refutations`/
  `optional_refutations` target — **Prototype B must target a broader
  deduction, never the same claim Prototype A cross-examines** (the
  "Separation from Prototype A" audit, below);
- a claim may be a Prototype B round target in at most one round;
- the target must have at least one proof set with exactly `(relation,
  slot_count)` matching, made only of evidence already in `evidence_pool`
  (never a derived deduction — Prototype B only ever selects **evidence**,
  matching "only evidence items, not derived deductions, are selectable");
- no proper (non-empty, non-full) subset of that accepted proof set may
  itself already resolve the target through the real evaluator — the
  anti-brute-force rule, checked directly with `DeductionEvaluator.
  classify_attempt()` against a fresh session (see "Anti-brute-force rule").

`DeductionValidator.structural_signature()` (used by
`validate_structural_equivalence()`, already run by `ContentValidator`) was
extended with `prototype_b:` lines describing the evidence pool and each
round's target role/relation/slot_count — X, Y and Z's Prototype B layers are
machine-checked to share one shape, exactly like the base
`credential_misuse_v2` proof graph and Prototype A's own layer.

## Content audit: separation from Prototype A

Milestone 1.11 added a single-evidence `refutes` proof set to
`candidate_staging_claim` (`st_oren_break_in` / `st_priya_vent_entry` /
`st_felix_fence_entry` — a **statement**), so Prototype A can present the
`staging_sign` alone to expose that specific lie. Milestone 1.12's audit
confirmed the two mechanics already target genuinely different claims:

```
Prototype A: st_oren_break_in (kind: statement, "candidate_staging_claim")
             → refuted by ONE clue: staging_sign alone
             ("I entered through this opening" — proven false)

Prototype B: ded_break_in_staged (kind: deduction, "staging_deduction")
             → supported by THREE clues: staging_sign + physical_rule_or_reference + staging_contradiction
             ("The apparent break-in was staged" — proven true)
```

These were **already separate claims** before this milestone (the statement
and the deduction have always had independent proof sets in the base
`credential_misuse_v2` content) — no case restructuring was needed. What this
milestone added is a **machine-checked guarantee** that they stay separate:
`DeductionValidator._validate_prototype_b` rejects a round whose `target`
also appears in any `prototype_a` round's `required_refutations`/
`optional_refutations`, and `prototype_b_content_test.gd`'s
`_test_prototype_a_target_does_not_solve_prototype_b_d3()` submits Prototype
A's own single accepted clue against Prototype B's D3 target through the
real evaluator and asserts it is rejected (`INSUFFICIENT_EVIDENCE`, since
that item is one third of D3's own proof set but nowhere near sufficient
alone). Neither the one-evidence Prototype A proof nor the three-evidence
Prototype B proof was weakened to achieve this — both are exactly as strong
as before, on their own separate claims.

## Playable flow

1. **Launch** — the Deduction Lab's "Launch Prototype B — Clue Connection"
   button opens the scene, defaulting the case picker to whichever case the
   Lab currently has active (or leaving it for the facilitator to pick if
   none), and hides Prototype A if it happened to be open (never resetting
   it — see "Entry and lifecycle"). Nothing starts until **Start** is
   pressed — that creates a fresh, isolated `PrototypeBController`/
   `DeductionSession`, never the Lab's own, never Prototype A's.
2. **Briefing and case file** — case title/description and the active
   draft's investigation question are always visible above the play area;
   the evidence Case File can be opened and read before or during a round.
   All Prototype B evidence is available from the beginning (investigation
   and clue acquisition are out of scope for this prototype).
3. **Drafting** — every question is a draft tab (`%DraftTabsRow`), always
   labeled "Unverified Draft — n/m slots filled". Each draft's slot count is
   always visible, which intentionally prevents "select every clue" behavior
   (see "Clue-slot and anti-dumping behavior"). "Place" fills the ACTIVE
   draft's next empty slot. "Remove" empties that slot without touching any
   other clue, in this draft or the other. Switching tabs, Save Draft and any
   edit are free: they never call the evaluator, never reveal correctness
   and never consume an attempt. Selection order never affects correctness.
4. **Commit Theory** — disabled until every slot of every draft is filled and
   the theory differs from any already-failed one. It classifies both drafts
   and either commits both through `DeductionEvaluator.commit_attempt()` or
   commits neither (see "Drafts and batch commit"). A feedback panel shows
   the result. On success it reveals both deductions' own text and both
   authored explanations; **Continue** then completes the prototype.
5. **Completion** — the authored `completion_text`, which says the player
   has formed **two useful deductions**, not that the whole case is solved
   (see "Out of scope"). Below it: the shared resolution summary (time,
   formal commits, failed formal commits, hints, assistance, tier, partner
   resolution) plus clues opened, clue replacements and drafts saved.
   Restart, Export Recording and Return to Lab are also offered here.

## Clue-slot and anti-dumping behavior

Every round declares an authored `slot_count`, and the UI shows exactly that
many empty slots from the start — the player always knows how many clues
this connection needs, which is precisely what prevents "select every clue
and see what sticks":

- `PrototypeBController.select_evidence()` rejects a selection once the
  round's slots are already full, **before** the evaluator ever sees it —
  the player physically cannot place a 4th item into a 3-slot round.
- Duplicate placement is impossible: `select_evidence()` rejects an id
  already placed, and the UI shows "Remove" (never a second "Place") for
  anything currently in a slot.
- `remove_evidence()`/`replace_evidence()` change exactly one slot, leaving
  the rest of the board untouched — so after a wrong attempt the player can
  reconsider and swap just one clue, never starting over.
- `DeductionValidator._validate_prototype_b_target` proves, for every
  accepted proof set, that **no proper subset** of it (checked against every
  non-empty, non-full combination via the real evaluator) already resolves
  the target — so a smaller, "cheaper" connection can never sneak through
  even if the UI's slot limit were somehow bypassed. `prototype_b_content_
  test.gd` re-proves this end to end against the real X/Y/Z content.
- The evaluator's own "extra relevant evidence still succeeds" leniency
  (`docs/deduction-system.md`, "Extra-evidence policy") is never reachable
  here at all — the UI physically cannot select more items than
  `slot_count`, so a padded submission never happens.

## Drafts and batch commit (Milestone 1.14)

Prototype B is the frequent core mechanic, so it has the strongest protection
against using the evaluator as an oracle (`docs/resolution-policy.md`):

```
Build Draft 1  +  Build Draft 2  →  Commit Theory
```

- **Drafts.** Every question in `prototype_b.rounds` is a draft tab.
  Placing, removing, replacing, **Save Draft** (`save_draft()`, recorded as
  `draft_saved`) and switching tabs (`select_draft()`) never call the
  evaluator, never unlock anything, never consume an attempt, and never say
  whether a draft is right.
  - A draft entry carries only `number`, `question`, `slot_count`,
    `filled_count`, `complete`, `saved` and `active`.
  - A correct and a wrong draft render identically (test-enforced).
  - The target deductions stay hidden.
- **Commit Theory** (`PrototypeBController.commit_theory()`) is enabled only
  when every draft is complete, the policy accepts a commit, and the theory
  isn't identical to one that already failed. It classifies EVERY draft with
  `DeductionEvaluator.classify_attempt()`, which has no side effects.
  - If ANY draft is invalid it commits **neither**, unlocks nothing,
    preserves both drafts, and counts one failed formal commit.
  - If all are valid it commits each through `commit_attempt()` and reveals
    both deductions.
  - A classify/commit disagreement is an internal error, never a false
    success.
- **Feedback is non-oracular.**
  - 1st failure: "At least one connection in this theory is not sufficiently
    established." It names no draft and no clue.
  - From the 2nd failure: the result adds `affected_draft_index` (the first
    invalid draft in authored order), and only that question is named. The
    incorrect clue is never named, and "2/3 correct" is never reported.
  - 3rd failure: Commit Theory locks until the footer's Accept Assistance is
    pressed. Assistance opens the affected draft and shows its base hint
    ladder's **level-2** (compare-categories) text — never the level-3
    evidence group, never an inserted clue.
- **After two assisted failures,** "Resolve with Partner":
  - keeps every draft the evaluator already accepts exactly as built;
  - replaces each invalid draft with the first authored proof set matching
    the question's relation, slot count and pool, classified first;
  - commits everything through `commit_attempt()`;
  - labels the result, lists which clues the partner connected for which
    question, and shows both authored explanations.
- **Unchanged anti-brute-force invariants:** authored slot counts, no
  duplicates within a draft, no over-capacity placement, no valid proper
  subset (validator), alternate proof paths accepted, selection order
  ignored. A clue may appear in drafts for two different questions; drafts
  are independent.
- **Primary action in the fixed footer (Milestone 1.14.1).** Hint, Save
  Draft and Commit Theory live in `%Footer`'s `%ActionRow`, not inside the
  scrolling `%BodyScroll` — so opening assistance or long feedback can never
  push Commit Theory offscreen at 1280×720.

## Feedback mapping

`PrototypeBPresenter.build_feedback(case_def, controller, result)`, where
`result` is whatever `commit_theory()` or `resolve_with_partner()` returned.
Per-draft evaluator categories are never shown, because they would be
exactly the oracle Milestone 1.14 removes. `theory_batch_rejected` records
them for analysis only.

| `result` | Player sees |
|---|---|
| `theory_accepted` | Success headline + both deductions' own text + both authored `success_explanation`s |
| `theory_accepted`, `partner: true` | "Resolved with your partner" + the same texts + which clues the partner connected for which question |
| `theory_rejected`, `feedback_level: coarse` | `UI_PROTOTYPE_B_FEEDBACK_THEORY_REJECTED` only, plus the attempts/tier notice |
| `theory_rejected`, `feedback_level: guided` | The same line + "Take another look at this question: …" for `affected_draft_index` |
| `invalid_input` — `incomplete_drafts`, `duplicate_failed_theory`, `already_accepted`, `submission_locked`, `internal_error` | A fixed explanation; nothing counted |

Committing an already-accepted theory is refused as `already_accepted`. It
never reclassifies, recommits or records telemetry again.

## Hints

Reuses the **real base hint contract** unmodified — see the architecture
decision above. `PrototypeBController.reveal_next_hint()` calls
`DeductionEvaluator.request_hint()` against the active draft's target and
reports `DeductionSession.get_hint_level()`; there is no Prototype-B-owned
hint state at all. The Hint button is always visible next to Save Draft / Commit Theory
(never auto-revealed), disables once the ladder is exhausted, and — because
every Prototype B target is a `deduction` with a mandatory base ladder
(`DeductionValidator` requires one for every required deduction) — is never
absent for a round the way it can be for a non-required Prototype A
statement. Level 4 (like the base contract's own level 4) only ever narrows
the search toward the case's own reasoning; it never states the conclusion
or auto-submits anything. Since Milestone 1.14 a newly revealed level also
raises the resolution tier (levels 1–2 → Guided, 3–4 → Assisted), and the
status line says so.

## Presenter and spoiler boundary

`PrototypeBPresenter.build_player_view(case_def, controller)` returns
`{"view": ..., "handle_map": ...}` — the exact same allow-list/opaque-handle
pattern `DeductionLabPresenter`/`PrototypeAPresenter` established. `view`
never contains a domain id, `structural_role`, `veracity`, `proof_sets`/
`compatible`, `ground_truth`, the round's private `target` id or `relation`,
or the target deduction's own text/status before the session has actually
resolved it — `resolved_claim` (the revealed deduction, once proven) is an
**entirely absent key** before resolution, not merely blank, exactly
matching `DeductionLabPresenter`'s own unresolved-claim gating. Only the
CURRENT round's question/slots/evidence/hint ever appear — a future round's
content is invisible until the player actually reaches it. `handle_map` is
kept privately by `scripts/debug/prototype_b.gd` and resolved back to a real
id only at the moment a click handler calls a production API
(`controller.open_evidence()`/`select_evidence()`/`remove_evidence()`).
`prototype_b_presenter_test.gd`'s own structural + content sweep methodology
mirrors `prototype_a_presenter_test.gd`'s against the real X/Y/Z content.

Since Milestone 1.14, both questions are visible as draft tabs (question
text only). `resolved_claims`, holding both deductions, replaces
`resolved_claim` and stays an entirely absent key until the theory is
accepted. `resolution_status` is always present. An `assistance` block exists
only once assistance was acknowledged.

## Recorder events

Reuses `DeductionLabRecorder` (`scripts/deduction/deduction_lab_recorder.gd`)
completely unmodified: same outer envelope (`schema_version: 1`), same
Start/Stop/Clear/Export controls, same safe-filename export, same
off-by-default / local / no-network / no-PII stance (`docs/deduction-lab.md`,
"Local playtest recorder"). The event VOCABULARY below is
`event_schema_version: 2` (Milestone 1.14.1 renamed the shared
resolution-policy payload keys — see `docs/deduction-lab.md`, "Recorder
schema"). `"prototype": "clue_connection"` distinguishes an
export from the Lab's `"deduction_lab"`, Prototype A's
`"statement_contradiction"` and Prototype C's `"timeline_reconstruction"`.
Every event uses `SOURCE_PLAYER_PREVIEW`. Recording can start **before**
pressing Start, because it reads the case id from the picker.

Event vocabulary since Milestone 1.14. `PrototypeBController` decides what
and when to record; the shared resolution events are described in
`docs/resolution-policy.md`, "Recorder events".

| Event | When |
|---|---|
| `prototype_started` | `start()` — payload `case_id`, `run`, `draft_count` |
| `prototype_restarted` | A second `start()` on the same controller, before its `prototype_started` |
| `evidence_opened` | The first time a given evidence item is opened |
| `draft_selected` | Switching to a different draft tab — payload `draft` |
| `clue_selected` / `clue_removed` | Placing/removing a clue — payload `evidence_id`, `draft`, in the player's actual order |
| `draft_saved` | Save Draft — payload `draft`, normalized `evidence_ids`, `filled`, `slot_count`, `complete` |
| `formal_commit_started` | Every counted Commit Theory |
| `theory_batch_submitted` | Alongside it — payload `sequence`, `drafts` (each `draft`, `target`, normalized `evidence_ids`) |
| `theory_batch_rejected` | A rejected theory — payload `sequence`, per-draft `draft_categories`, `invalid_drafts` (analysis only; never shown) |
| `theory_blocked_duplicate` | Milestone 1.14.2A — committing a theory identical to one that already failed (previously silently dropped; see `docs/prototype-evaluation.md`) — payload `drafts` (the repeated normalized identity). Purely observational: never counted, never reaches the evaluator, never changes `commit_theory()`'s return value |
| `formal_commit_failed` | Alongside a rejection — budget, `run_resolution_result_before`/`after` |
| `theory_batch_accepted` / `formal_commit_succeeded` | An accepted theory — `resolved_by: "player"` |
| `deduction_unlocked` | Each newly committed deduction — payload `target`, `draft`, `resolved_by` |
| `run_resolution_result_changed`, `assistance_offered`, `assistance_accepted`, `partner_resolution_offered`, `partner_resolution_used` | The shared resolution events (Milestone 1.14.1 renamed from `resolution_tier_changed` and `tier`-prefixed payload keys — see `docs/resolution-policy.md`) |
| `hint_revealed` | Each new hint level — payload `target`, `draft`, `level` |
| `prototype_completed` / `prototype_abandoned` | Stats plus a `resolution` summary |

The Milestone 1.12 per-round events are no longer emitted: `round_started`,
`connection_submitted`, `connection_result` and `round_completed` described
an interaction that no longer exists. Submitted evidence ids are sorted for
deterministic payloads, while `clue_selected` / `clue_removed` keep the
player's real order. No localized text is ever recorded.

## Validation

`DeductionValidator._validate_prototype_b()` (called from `validate_case()`
whenever a case declares `prototype_b`) and `collect_prototype_b_text_keys()`
(wired into `ContentValidator._validate_deduction_cases`, alongside the base
`collect_text_keys()` and Prototype A's own) check: duplicate round ids;
missing question/target/evidence references; missing translations (question,
success_explanation, completion_text); a target that isn't a `deduction`
claim; a target that is also a Prototype A cross-examination target; a claim
used as a target in more than one round; an invalid or unsupported relation;
a `slot_count` below the anti-brute-force minimum of 2; no proof set on the
target matching `(relation, slot_count)` exactly ("proof cardinality
inconsistent with visible slots"); an accepted proof item that is a derived
deduction rather than evidence, undefined, or missing from `evidence_pool`
("required evidence locked at prototype start" is covered too — every pool
item must have no `unlock_requires`); a valid proper subset of an accepted
proof that would make the larger connection redundant (checked directly with
the real evaluator against a fresh session — this single check also covers
"single-evidence shortcut to a two-clue Prototype B deduction" as its size-1
case); and, via the extended `structural_signature()`, a Prototype B shape
mismatch between X/Y/Z. Reachability of the target itself is already proven
by the base `_validate_dependency_graph` (every X/Y/Z Prototype B target is
`required: true`), so this section does not re-derive it.

## Testing

| File | Covers |
|---|---|
| `scenes/test/prototype_b_controller_test.gd` | Rewritten in Milestone 1.14. Fresh session per run and isolation from the Lab and Prototype A. Two independent drafts with per-draft slot capacity, duplicates and remove/replace. Editing, saving and switching never evaluate. Commit Theory requires every draft. One correct + one incorrect draft commits neither and carries no per-draft/per-clue detail. Coarse → guided feedback levels, identical failed theories blocked, selection order and the alternate path (fixture `e_f`). Both deductions committed through `commit_attempt()`. Assistance targets an invalid draft without inserting clues; partner batch resolution keeps valid drafts. Hints via the real base API raise the tier. Stats, abandonment, restart, and the no-direct-session-mutation source check. Uses `deduction_fixtures.gd`'s `prototype_b_case()` (two rounds with different slot counts). |
| `scenes/test/prototype_b_presenter_test.gd` | Rewritten in Milestone 1.14. Exact allow-listed keys and a spoiler sweep against real X/Y/Z. A correct and a wrong draft render identically. `resolved_claims` absent until accepted. Generated wrong drafts drive coarse → guided → assistance feedback with no clue names, and assistance uses only the ladder's category level. Partner notes, uncounted-reason mapping, evidence text gated on opened, hints following the active draft, localized status and the 10-line summary. |
| `scenes/test/prototype_b_content_test.gd` | Unchanged. X/Y/Z in structural-role terms: two rounds targeting D1 and D3, D1's primary and alternate paths, D3 requiring all three clues, no valid proper subset, pool availability, translations, structural parity, and the Prototype A/B separation audit. |
| `scenes/test/prototype_b_scene_test.gd` | **FULL-only**, rewritten in Milestone 1.14. Launching from the Lab leaves the Lab and Prototype A untouched. Draft tabs retain content and Save Draft costs nothing. Commit Theory stays disabled until both drafts are complete. A mixed batch reveals and unlocks nothing, with progressive feedback. Both D1 paths complete. Hints; assistance and partner resolution through the footer; the Assisted completion summary. Restart cancel/confirm with restart recording, return/abandon, and the recorder export vocabulary. Drafts and attempts preserved across F1 and locale switches, translations, all three cases, and the long-feedback layout regression. |

The three pure files run in FAST and FULL; the scene test is FULL-only.

## Out of scope

Deliberately not built in this milestone (see the milestone brief's own "Out
of scope" list): Prototype C, a relation picker, an unrestricted clue graph,
a draggable free-form caseboard, selecting more clues than authored slots,
statement contradiction inside Prototype B, D2 (`candidate_exclusive_control`)
or the final case conclusion (`final_conclusion`) as a round target, a final
accusation, investigation gameplay, production save integration, canon case
content, custom art/audio, an analytics backend, network telemetry, a
generic content editor, and choosing a core mechanic (that decision is
deferred to the full A/B/C rotation — `docs/deduction-playtest-plan.md`).
The completion screen is deliberately worded around "two useful deductions,"
never "the case is solved" — the purpose is testing the connection
interaction in 5–10 minutes, not making the player solve the entire proof
graph.

## Known limitations

- **No display-server visual QA in this environment** — see the milestone's
  final report for exactly what was/wasn't checked. Headless scene tests
  prove wiring and structure, not pixels (`docs/architecture.md`'s "Known
  limitations"; `docs/prototype-a.md`'s own "Layout" note on the same
  headless-geometry limitation this milestone's regression test works
  around structurally).
- **Both rounds use `slot_count: 3` for X/Y/Z**, not the brief's illustrative
  "3 then 2" — an audited, content-forced departure documented above and in
  the architecture decision box. A future case declaring a genuinely
  2-item-provable deduction round is legal per the validator (the minimum is
  2, not a fixed 3) but untested beyond the fixture's own round 2.
- **No production integration.** Debug-only, non-canon, not linked from
  `Main.gd`, no save/load — identical stance to the Deduction Lab and
  Prototype A.
- **Recorder has no rotation/size cap**, same accepted limitation
  `docs/deduction-lab.md`/`docs/prototype-a.md` already document for their
  own recorder use — a single playtest session's scale is what this was
  built for.
- **One shared budget for the whole theory** (Milestone 1.14). A player who
  is strong on one question and weak on the other spends one budget for
  both. That is deliberate, since the batch is the resolution unit, and is
  a playtest question (`docs/deduction-playtest-plan.md`, section 10).
