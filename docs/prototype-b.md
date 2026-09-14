# Prototype B — Clue Connection (Milestone 1.12)

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
"Out of scope" below and the milestone brief). Exactly two rounds per case,
each with a fixed number of visible connection slots; the player never picks
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
2. **Briefing and case file** — case title/description and the current
   round's investigation question are always visible above the play area;
   the evidence Case File can be opened and read before or during a round.
   All Prototype B evidence is available from the beginning (investigation
   and clue acquisition are out of scope for this prototype).
3. **Connection** — the round's number of empty connection slots is always
   visible (this intentionally prevents "select every clue" behavior — see
   "Anti-brute-force rule"). Clicking an unplaced evidence card's "Place"
   button fills the next empty slot; clicking a placed card's "Remove"
   button (the same button, relabeled) empties that slot without touching
   any other placed clue. **Connect Clues** is disabled until every slot is
   filled, and submits exactly the placed set — through
   `DeductionEvaluator.commit_attempt()` with the round's privately authored
   target and relation — with duplicate placement structurally impossible
   (a card already placed shows "Remove," never a second "Place").
   Selection order never affects correctness.
4. **Feedback** — a panel shows the mapped result (see "Feedback mapping"
   below); on success it also reveals the now-provable deduction's own
   authored text and the round's authored explanation. **Continue**
   dismisses it and, only if the current round's target is now resolved,
   advances to the next round (clearing the slots for a fresh set) or (on
   the last round) completes the prototype.
5. **Completion** — the authored `completion_text` (which says the player
   has formed **two useful deductions**, not that the whole case is solved
   — see "Out of scope"), plus elapsed time, connection attempts, failed
   attempts, clues opened, clue replacements, and hints used. Restart,
   Export Recording and Return to Lab are all offered here too.

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

## Evaluator-result feedback mapping

`PrototypeBPresenter.build_feedback(case_def, controller, result)` —
`result` is whatever `PrototypeBController.submit_connection()` returned:

| `result.category` (never shown raw) | Player sees |
|---|---|
| `valid_support` | Success headline + the now-resolved deduction's own authored text + the round's authored `success_explanation` |
| `irrelevant_evidence` | Generic: "at least part of this connection doesn't actually address the current question" — never says which item |
| `insufficient_evidence` | Generic: "this points in a useful direction, but doesn't establish the deduction on its own" — never says what's missing |
| `compatible_not_proof` | Generic: "these facts can all be true at once, but they don't logically produce this conclusion" |
| `invalid_input` (incomplete selection, etc.) | Generic: "fill every slot with a distinct piece of evidence before connecting" — the controller itself rejects an incomplete submission before it ever reaches the evaluator, so this case needs no session mutation either |

The four generic messages are static `UI_PROTOTYPE_B_FEEDBACK_*` keys, never
per-case content — only a genuine success reveals case-authored text (the
deduction's own claim text plus the round's `success_explanation`). A wrong
attempt never says which clue was missing, wrong, or extra — matching the
milestone's "failed connections informative without revealing the missing
clue" requirement — and resubmitting an already-resolved target reclassifies
(via `DeductionEvaluator.classify_attempt()`, side-effect-free) instead of
recommitting, so it never mutates the session, never increments the
attempt/failure counters, and never records a duplicate
`connection_submitted`/`deduction_unlocked` event.

## Hints

Reuses the **real base hint contract** unmodified — see the architecture
decision above. `PrototypeBController.reveal_next_hint()` calls
`DeductionEvaluator.request_hint()` against the current round's target and
reports `DeductionSession.get_hint_level()`; there is no Prototype-B-owned
hint state at all. The Hint button is always visible next to Connect Clues
(never auto-revealed), disables once the ladder is exhausted, and — because
every Prototype B target is a `deduction` with a mandatory base ladder
(`DeductionValidator` requires one for every required deduction) — is never
absent for a round the way it can be for a non-required Prototype A
statement. Level 4 (like the base contract's own level 4) only ever narrows
the search toward the case's own reasoning; it never states the conclusion
or auto-submits anything.

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

## Recorder events

Reuses `DeductionLabRecorder` (`scripts/deduction/deduction_lab_recorder.gd`)
completely unmodified — same schema (`schema_version: 1`), same
Start/Stop/Clear/Export controls, same safe-filename export, same
off-by-default/local/no-network/no-PII stance
(`docs/deduction-lab.md`, "Local playtest recorder"). `"prototype":
"clue_connection"` distinguishes an export from the Lab's own
`"deduction_lab"` and Prototype A's own `"statement_contradiction"`
recordings. Every event uses `SOURCE_PLAYER_PREVIEW` (no Author/Debug mode
exists in this milestone either).

Recording can be started **before** pressing Start on the case (reading the
case id from the picker, not from an active session) — the same deliberate
ordering Prototype A's own recorder controls already use, so
`prototype_started`/`round_started` are actually capturable.

Event vocabulary (`PrototypeBController` decides what/when to record; the
recorder itself carries none of this):

| Event | When |
|---|---|
| `prototype_started` | `start()` — once per run |
| `round_started` | Entering round 0, and again on advancing to the next round |
| `evidence_opened` | The first time a given evidence item is opened (via `DeductionSession.mark_evidence_opened()`) |
| `clue_selected` | Placing a clue into a slot (via `select_evidence()`, or the "select" half of `replace_evidence()`) |
| `clue_removed` | Removing a clue from a slot (via `remove_evidence()`, or the "remove" half of `replace_evidence()`) |
| `connection_submitted` | Every genuinely new submission (never for a resubmission on an already-resolved target) — payload: sequence, round, target, normalized (sorted) evidence ids, count, evaluator category |
| `connection_result` | Immediately alongside `connection_submitted` — payload: target, category (kept as a separate event so an exported log can filter "was this an attempt" from "what did it resolve to" independently, matching the milestone's own event list) |
| `deduction_unlocked` | Only on a **newly** successful connection (a genuinely new `commit_attempt()` resolving the target) |
| `hint_revealed` | Each new hint level (never a repeat of an already-exhausted ladder) |
| `round_completed` | On `acknowledge_result()`, once a round's target is resolved |
| `prototype_completed` | Both rounds' targets resolved — payload is the full stats dict |
| `prototype_abandoned` | Return to Lab (or Esc) with real progress and no completion |

`connection_submitted`'s `evidence_ids` are **sorted** before recording —
"normalize attempt item IDs for deterministic exported payloads" — while
`clue_selected`/`clue_removed` fire separately, in the player's actual
placement/removal order, so selection-order/churn analysis stays possible
from the raw event stream even though the submitted set itself is
normalized. Payloads carry internal ids/categories for analysis; the UI
never renders a raw category or id from a recorded payload back to the
player, and no full localized evidence or explanation text is ever recorded
(`prototype_b_scene_test.gd`'s recorder test spot-checks this against real
translated names, the same way `prototype_a_scene_test.gd`'s own does).

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
| `scenes/test/prototype_b_controller_test.gd` | Fresh session per run, isolation from a `DeductionLabController`'s and a `PrototypeAController`'s own sessions, clue selection/removal/replacement, exact slot-capacity enforcement (including that different rounds may declare different slot counts, read from content), duplicate prevention, order-independence, required/wrong-attempt classification through the real evaluator, idempotent resubmission, round/prototype completion, hints via the real base API (not a private copy), stats/abandonment, and a structural check that no `DeductionSession` mutator is ever called directly. Pure/autoload-free — a dedicated fixture, `deduction_fixtures.gd`'s `prototype_b_case()` (independent of `base_case()`/`prototype_a_case()`, deliberately using two DIFFERENT slot counts across its two rounds to prove the controller never hardcodes one). |
| `scenes/test/prototype_b_presenter_test.gd` | The player view's exact allow-listed keys; a spoiler sweep against real X/Y/Z content (no domain id/structural role/target/relation ever reaches it); round-scoping (no future-round question/target text); evidence text gated on opened; `resolved_claim` absent before success and populated after; hint progression; and `build_feedback()`'s mapping for every evaluator category. |
| `scenes/test/prototype_b_content_test.gd` | X/Y/Z walked once in structural-role terms: exactly two rounds targeting D1 and D3; D1's primary AND alternate 3-item paths both solve through the real evaluator; D3 requires all three authored clues (no 2-of-3 subset resolves it — the audited reason round 2 uses 3 slots, not 2); no proper subset of either accepted proof resolves its target; every accepted proof item is available from the start and listed in the pool; translations resolve; the Prototype B structural-signature shape matches across all three cases; and Prototype A's own single accepted clue does not, alone, solve Prototype B's D3 target (the separation audit, machine-checked). |
| `scenes/test/prototype_b_scene_test.gd` | **FULL-only** (needs a real scene tree, like `smoke_test.gd`/`prototype_a_scene_test.gd`): launching from the Lab with/without an active Lab case (and that launching hides, never resets, Prototype A if it was open); reading/placing/removing/replacing evidence via real buttons; Connect disabled until every slot is filled; wrong-connection feedback with the board preserved; the D1 primary AND alternate paths; D3 needing all three clues (disabled Connect with only 2 of 3 filled); hint reveal; round transition and completion; restart/return confirmation (cancelling preserves the run exactly); recorder controls and the exported schema/event vocabulary (including normalized `evidence_ids`); F1 hide/show session preservation; all three cases solving round 1; bilingual coverage; and the Milestone 1.12 long-feedback layout regression applied to this scene (Continue stays structurally outside the scrolling body and reachable however long the revealed deduction/explanation text is). |

All four are in FAST and FULL (`docs/testing.md`) — the three pure ones cost
about a second together; the scene test needs the same real-scene-tree setup
`prototype_a_scene_test.gd`/`deduction_lab_scene_test.gd`/`smoke_test.gd`
already pay for, so it's FULL-only.

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
