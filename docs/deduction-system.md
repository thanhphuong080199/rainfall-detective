# Deduction System (Milestone 1.9, hardened in 1.9.1)

The shared, data-driven foundation that the future deduction prototypes will
be built on and compared with:

- **Prototype A — Statement Contradiction**: prove a statement false
  (`refutes`).
- **Prototype B — Claim / Clue Connection**: connect clues to a claim
  (`supports` / `explains` / `rules_out`).
- **Prototype C — Timeline Reconstruction**: place events so every authored
  constraint holds.

Read `docs/architecture.md` first. This doc covers the data contract, how
proofs are evaluated, how cases are validated, and how to add a case. The
three dummy mysteries built on it are audited in
`docs/deduction-prototype-cases.md`. How they will be playtested is in
`docs/deduction-playtest-plan.md`. `docs/deduction-lab.md` (Milestone 1.10)
is a debug-only, mechanic-neutral viewer for those three cases;
`docs/prototype-a.md` (Milestone 1.11) and `docs/prototype-b.md` (Milestone
1.12) are the first two actual mechanics built on top of everything below,
both launched from that Lab.

**This is infrastructure, not story, and mostly not UI.** Prototype C
still has no screen. Every deduction case in `data/deductions/prototypes/`
is a **non-canon** dummy (`metadata.canon: false`). Nothing in them belongs
to the game's world.

## Design principles the contract enforces

| Principle | Where it lives |
|---|---|
| Fair play: evidence must support the required conclusion | Proof sets are explicit and authored. `DeductionValidator` proves every required claim is reachable from the case's evidence. |
| An observation is not its interpretation | A claim's `compatible` list. "The badge opened the door" is *compatible with* "the owner did it", never proof of it (`compatible_not_proof`). |
| A contradiction proves a claim false, not guilt | `refutes` resolves a statement as `refuted` and unlocks nothing. Only a proven `deduction` can be used as input to a later proof. |
| Sources can be truthful, mistaken, deceptive, incomplete, unreliable | A statement's `veracity`. The validator rejects proofs that contradict it. |
| Difficulty comes from reasoning, not syntax or memory | Matching ignores selection order and uses ids, never player-facing text. Results report a category, never the missing item. |
| Specialist knowledge is taught in the case | Modelled as ordinary evidence: the `travel_fact` role ("the trip takes 25 minutes") and the `physical_rule_or_reference` role (an illustrated guide stating the physical rule a staging clue depends on). |
| Intermediate deductions are at most two layers deep | `MAX_INFERENCE_DEPTH` in the validator. A conclusion is a synthesis layer on top and is exempt (see "Inference depth"). |
| A private deduction never makes evidence appear | Prototype evidence is independently available. The validator warns when evidence gated behind a deduction is then required by a deduction or conclusion (see "Evidence availability"). |
| Access, opportunity, motive, lying or staging never name an actor on their own | Authored proof sets: a conclusion needs exclusive control plus staging, and refuted statements can't be inputs. Checked per case in `deduction_cases_test.gd`; argued in `docs/deduction-prototype-cases.md`, "Proof obligations". |
| Private hypotheses are freely revisable | Hypotheses are authored claims. Trying one costs nothing, and a failed attempt changes no state (only the attempt log). |

## Architecture — what was reused, what was added

```
data/deductions/**/*.json ──► ContentDB (new "deductions" category, same loader)
                                   │ plain Dictionary (immutable definition)
                                   ▼
            ┌──────────── DeductionEvaluator (static, pure) ────────────┐
            │  classify_attempt / commit_attempt / request_hint /       │
            │  get_question_status / is_case_solved / evaluate_timeline │
            └───────┬──────────────────────────────────────┬────────────┘
                    │ reads + records                      │ delegates
                    ▼                                      ▼
            DeductionSession (RefCounted)           TimelineEvaluator (static, pure)
            player progress + signals

ContentValidator.validate() ──► DeductionValidator.validate_case() / validate_structural_equivalence()
                            └─► _validate_translatable() over DeductionValidator.collect_text_keys()
```

| Piece | File | Kind |
|---|---|---|
| `DeductionEvaluator` | `scripts/deduction/deduction_evaluator.gd` | `class_name` static helper, no autoloads |
| `TimelineEvaluator` | `scripts/deduction/timeline_evaluator.gd` | `class_name` static helper, no autoloads |
| `DeductionValidator` | `scripts/deduction/deduction_validator.gd` | `class_name` static helper, no autoloads, called by `ContentValidator` |
| `DeductionSession` | `scripts/deduction/deduction_session.gd` | `class_name` `RefCounted` holding one player's progress |
| Content | `data/deductions/prototypes/*.json` | one case per file, loaded by `ContentDB` |
| Text | `localization/strings.csv` (`DED_PROTO_*` keys) | same CSV and validation as all other content |

**Reused unchanged:**
- `ContentDB`'s recursive JSON loader, including duplicate-id detection.
- `ContentValidator`'s report, severities and exit code.
- `_validate_translatable`.
- `LocaleManager`'s CSV.
- `TestHelpers` and `verify.sh`.

**Not touched:** `GameState`, `ConditionEvaluator`, `EffectRunner`,
`EventManager`, `CaseManager`, `SaveManager`, and every existing scene.

```
DECISION: Deduction proofs are an authored proof graph evaluated by a new
pure helper (DeductionEvaluator), not new ConditionEvaluator leaves or
EffectRunner effects.

WHY: A condition answers "is this true about GameState right now?" A proof
answers "does the player's SELECTION of clues establish this claim, and how
wrong is it if not?" — five graded outcomes, order-independent set matching,
duplicate rejection, locked inputs. Forcing that into the condition language
would need selection state in GameState and a graded (non-boolean) evaluate(),
changing a primitive every topic/destination/event depends on.

ALTERNATIVES: {"has_evidence": ...} + {"all": [...]} conditions on a
"deduction" content type, with a set_flag effect to unlock the deduction.
That checks whether the player HOLDS items, not whether they SELECTED them for
this claim. It can't tell insufficient from irrelevant evidence, and it would
unlock the moment the items are held — exactly the "unlock without explicit
commitment" the milestone forbids.

IMPACT: Two small vocabularies side by side. Narrative gating stays
condition/effect. Deduction stays proof sets. They are joined later, when a
prototype screen exists (see "Save/load (deferred)"), not by merging them now.
```

```
DECISION: No new autoload. DeductionEvaluator/TimelineEvaluator/
DeductionValidator are static helpers. Player progress is a DeductionSession
object owned by whoever runs a deduction.

WHY: The autoload bar in .claude/skills/godot-development (survives scene
changes + needed by many unrelated scenes + must be unique) isn't met by
anything that exists yet. There are zero prototype screens, and the three
prototypes will each run one session at a time.

IMPACT: Tests drive the evaluator with hand-built fixtures and no scene tree.
Whether a session should live in an autoload is decided with the first
prototype screen, together with persistence.
```

```
DECISION: A deduction case's evidence, claims and suspects are ids LOCAL to
the case file, not entries in the global data/evidence or data/characters
categories.

WHY: Deduction evidence needs fields investigation evidence doesn't
(provenance, certainty, tags, structural role, unlock requirements), and
prototype cases are standalone, non-canon test material. Putting them in the
global categories would put dummy clues in the real inventory's namespace.

IMPACT: One id namespace per deduction case (DeductionValidator enforces
uniqueness across every section). Linking an investigation evidence id to a
deduction evidence id is a later, real-content decision.
```

## Data contract

A deduction case is one JSON object in `data/deductions/**/*.json`. Every
`name` / `text` / `label` / `display_name` / `description` / `summary` field
is a **translation key** (see `docs/localization.md`). The shortened example
below is `proto_x_archive_ledger.json`.

### Case

| Field | Meaning |
|---|---|
| `id` | Unique within the `deductions` category. |
| `display_name`, `description` | Translation keys. |
| `version` | Documentary. |
| `metadata.canon` | **Required** bool. Prototype content is `false`. |
| `metadata.prototype`, `metadata.milestone`, `metadata.note` | Documentary. The note says "do not reuse". |
| `metadata.structural_template` | Optional. When set, every entity needs a `structural_role`, and every case sharing the template must have an identical proof-graph shape (see "Structural roles"). |
| `suspects`, `questions`, `evidence`, `claims` | Non-empty arrays (below). |
| `timeline` | Optional `{events, constraints}` (see "Timeline reconstruction"). |
| `hints` | Hint ladders (see "Hint ladders"). |
| `ground_truth` | **Required** objective answer (see "Ground truth"). |

### Suspect

`{id, name, structural_role}`.

### Question

`{id, text, required, structural_role, resolved_by: [{claim, status}]}`. A
question is resolved when **any** `resolved_by` entry holds, where `status`
is `"supported"` or `"refuted"`. The case is solved when every `required`
question is resolved.

### Evidence (an observation)

| Field | Meaning |
|---|---|
| `id`, `name`, `text` | The `text` is the observation only, never its interpretation. |
| `source` | Provenance: who or what produced it. Required. |
| `certainty` | `fixed` / `estimated` / `claimed`. |
| `time` | Optional `"HH:MM"`. |
| `tags` | Information categories (`time`, `location`, `distance`, `possession`, `scene`, …). Used by level-2 hints. Never shown as the answer. |
| `unlock_requires` | Deduction ids that must be committed as supported before this item can be selected. Empty or absent = available from the start. **Not for production use without a causally represented investigation action** (see "Evidence availability"). No prototype case uses it. |
| `misleading` | `true` for a red herring. The validator requires an `explains` proof set that uses it. |
| `structural_role` | See "Structural roles". |

### Claim

| Field | Meaning |
|---|---|
| `kind` | `statement` (an NPC said it), `hypothesis` (a possibility the player can entertain), `deduction` (an intermediate derived fact), `explanation` (a truthful account of a misleading observation), `conclusion` (the final answer). |
| `veracity` | Ground truth. Statements: `true` / `mistaken` / `deceptive` / `incomplete` / `unreliable`. Other kinds: `"true"` / `"false"`. Deductions, explanations and conclusions must be `"true"`. |
| `speaker` | Statements only; a suspect id. |
| `lie_motive` | Documentary (e.g. `unrelated_to_crime` for an innocent lie). |
| `required` | Required claims must be reachable, and deductions/conclusions with `required: true` need a hint ladder. |
| `compatible` | Items consistent with the claim that do **not** prove it. |
| `proof_sets` | `[{id, relation, requires: [evidence or deduction ids]}]`. Each set is one complete, rational, order-independent proof. Several sets = alternate proofs. |

### Relations

| Relation | Resolves the claim as | Allowed on |
|---|---|---|
| `supports` | `supported` | a statement whose veracity is `true`/`incomplete`; a hypothesis/deduction/conclusion whose veracity is `"true"` |
| `explains` | `supported` | an `explanation` |
| `refutes` | `refuted` | a statement whose veracity is `mistaken`/`deceptive` |
| `rules_out` | `refuted` | a hypothesis whose veracity is `"false"` |

Only a supported **`deduction`** can be used as input to another proof set,
and it unlocks only through `commit_attempt()`. A conclusion's proof sets
may use only deductions, never raw evidence. A claim cannot have both
establishing and negating proof sets.

### Inference depth

One definition, used by the validator, the tests and the case audits:

- **Raw evidence** has depth **0**.
- A **`deduction`** (an intermediate claim, the only kind that can be a proof
  input) has depth **1 + the maximum depth of the deductions it requires**,
  taken across *all* its proof sets. A deduction built only from evidence is
  depth 1.
- The **maximum intermediate deduction depth is 2** (`MAX_INFERENCE_DEPTH`).
- A **`conclusion`** is the synthesis/commit layer. It is **not** counted when
  enforcing the maximum, because nothing can build on it. Statements,
  hypotheses and explanations are terminal in the same way.
- Every claim, whatever its kind, is still checked for **cycles**, **undefined
  references** and **reachability**. Changing a claim's kind can't bypass those
  checks: a non-deduction used as an input is an error, a conclusion using raw
  evidence is an error, and a claim with an unknown kind still has its proof
  sets validated.

`DeductionValidator.proof_set_depth()` / `claim_depth()` report the depth of
any proof set or claim, including conclusions. The structural signature
records each proof set's depth.

| Chain | Deepest intermediate | Valid? |
|---|---|---|
| evidence → D1 | D1 = 1 | yes |
| evidence → D1 → D2 | D2 = 2 | yes |
| evidence → D1 → D2 → **conclusion** | D2 = 2 (conclusion reports 3, exempt) | yes — the prototype cases' shape |
| evidence → D1 → D2 → **D3** (another deduction) | D3 = 3 | **no** — validation error |

### Ground truth

`{culprit, credential_owner, conclusion, summary, solution_timeline}`.
`culprit` and `credential_owner` are suspect ids. `conclusion` is the
case's `conclusion` claim, which must be provable. `solution_timeline`
gives one valid `"HH:MM"` placement for every timeline event, and must
satisfy every required constraint.

## Evaluation

### API

```gdscript
var case_def: Dictionary = ContentDB.get_deduction_case("proto_x_archive_ledger")
var session := DeductionSession.new(case_def["id"])

var result := DeductionEvaluator.commit_attempt(case_def, session, "ded_badge_misused", "supports",
		["e_route_note", "e_door_log", "e_tram_tap"])     # order is irrelevant
result.category             # "valid_support"
result.unlocked_deduction   # "ded_badge_misused" — now usable as an input
result.newly_resolved_questions  # ["q_owner"]

DeductionEvaluator.get_available_evidence_ids(case_def, session)
DeductionEvaluator.get_question_status(case_def, session)   # resolved / unresolved / required_unresolved
DeductionEvaluator.request_hint(case_def, session, "ded_only_oren_had_badge")
DeductionEvaluator.evaluate_timeline(case_def, {"tl_badge_used": "20:06", ...})
session.reset()
```

`classify_attempt()` has the same signature, returns the same category, and
**changes nothing**. It exists for tooling and tests. A player-facing screen
must call `commit_attempt()`, so nothing unlocks just because related items
happen to be selected.

### Result categories (checked in this order)

| Category | When |
|---|---|
| `invalid_input` (+ `reason`) | `unknown_claim`, `session_case_mismatch`, `unknown_relation`, `empty_selection`, `malformed_item`, **`duplicate_item`**, `unknown_item`, `unselectable_item` (a non-deduction claim), `locked_item` (evidence not yet unlocked, or a deduction not yet committed). |
| `irrelevant_evidence` | At least one selected item appears nowhere in this claim's proof sets or `compatible` list. |
| `valid_support` / `valid_refutation` | The selection contains every item of a proof set with the asserted relation. The first authored match wins, and its id is returned as `proof_set_id`. |
| `insufficient_evidence` | Every item belongs to one such proof set, but something is missing. |
| `compatible_not_proof` | Everything bears on the claim, but the selection doesn't establish the asserted relation: an authored compatible observation, items split across alternate proofs, or the wrong relation. |

Results carry only the category, the claim id, the relation, `proof_set_id`
(on success) and an input `reason`. They never say which item is missing or
extra. Answer-bearing text comes only from `request_hint()`.

**Duplicate-item policy:** the same id twice is `invalid_input`/
`duplicate_item`, even if the distinct items would form a proof. An item
never counts twice.

**Extra-evidence policy:** a valid proof plus **irrelevant** items is
`irrelevant_evidence` and is rejected, so "select everything" never works. A
valid proof plus other **relevant** items is accepted, because corroboration
is not a mistake. Relevance is always judged per claim.

### Commitment, unlocks, questions

`commit_attempt()` records every attempt (valid or not) in the session's
attempt log. Only a valid category resolves the claim, and a claim resolves
at most once: re-proving it with an alternate set is valid but changes
nothing. Resolving a `deduction` as supported unlocks two things:
- evidence whose `unlock_requires` it satisfies;
- its own use as input to later proofs.

After a commit, the result lists newly resolved questions and whether the
case is now solved.

### Evidence availability: deductions, discovery, investigation actions

Four different things, which content must not blur:

| What happens | Meaning | Supported now? |
|---|---|---|
| **Unlocking a derived deduction** | Committing D1 makes D1 usable as an input to later proofs. Nothing in the world changes. | Yes — `commit_attempt()` |
| **Revealing the relevance of available evidence** | D1 explains why a record the player already has matters (for example, why the custody sheet is now worth reading). The record existed all along. | Yes — just author the record as available and let the proof sets connect it |
| **Discovering evidence through a world action** | D1 makes a lead meaningful. The player explicitly requests or searches for the record, and *that action* reveals it. | **No** — needs a future investigation lead/action system |
| **Directly unlocking evidence from a private deduction** | A realization makes a pre-existing record or clue appear. | Technically possible (`unlock_requires`), but **causally wrong**; not for production content |

Rules:
- Evidence a deduction or conclusion requires must be independently
  available. All three prototype cases have no `unlock_requires` at all; the
  custody and continuity records are available from the start.
- `unlock_requires` is kept in the generic contract for future use. Before
  any production case uses it, the unlock must be represented by an explicit
  investigation action, not by a thought.
- `DeductionValidator` **warns** when evidence gated behind a deduction is
  then required by a deduction or conclusion. Such a claim is always a
  descendant of the gate. That is the "resolve D1 → custody log appears →
  D1 + custody log proves D2" pattern. Gated evidence nothing derived needs
  (like the fixture's `e_followup`) does not warn.

### Hint ladders

`hints: [{target, levels: [4 levels]}]`, one ladder per required deduction
and per conclusion:

| Level | `kind` | Extra field | Purpose |
|---|---|---|---|
| 1 | `restate_question` | `question` | Restate the missing investigative question. |
| 2 | `compare_categories` | `categories` (evidence tags) | Point toward the kinds of information to compare. |
| 3 | `evidence_group` | `evidence` | Identify the relevant evidence group. |
| 4 | `reveal_deduction` | `deduction` | Reveal one **intermediate** deduction, never the conclusion. Information only; it does not commit anything. |

Each `request_hint()` call reveals the next level. Asking past level 4
repeats it with `exhausted: true`.

## Timeline reconstruction

`timeline.events`:
`{id, label, actor (suspect id or ""), location, certainty, duration_minutes?, structural_role}`.

`timeline.constraints`: `{id, type, …, required?, source}`. `source` is the
evidence or claim that justifies the constraint. `required` defaults to
`true`.

| `type` | Fields | Holds when (an event occupies `[start, start + duration]`) |
|---|---|---|
| `fixed_time` | `event`, `time` | start == time |
| `window` | `event`, `earliest`, `latest` | earliest ≤ start ≤ latest |
| `before` | `events: [a, b]`, `min_gap_minutes?` | end(a) + gap ≤ start(b). Covers before/after, minimum gap and minimum duration. |
| `no_overlap` | `events: [a, b]` | the intervals share no time; two instants at the same minute overlap |
| `travel_time` | `events: [a, b]`, `minutes` | whichever comes first, the other starts ≥ `minutes` after it ends. This encodes "one person can't be in two places" plus minimum travel time. |

A submission maps **every** event id to `"HH:MM"`. It is
`timeline_consistent` when every **required** constraint holds, so any
placement the evidence allows is accepted, not just the authored one.
Violated optional constraints are reported in `violated_optional`. The
prototype cases use one for each bystander's false claimed time: the true
timeline "contradicts what they said" without being wrong. An unknown or
missing event or a malformed time is `invalid_input`. A malformed constraint
fails closed.

This is a checker, not a solver: it never searches for a placement.

## Content validation

`ContentValidator.validate()` runs `DeductionValidator` on every loaded
deduction case. Its findings print as `[ContentValidator]` lines and fail
`validate_content.gd` like any other error.

**Errors:**
- **Shape and ids:** a missing or empty section; a malformed entry; a
  missing id; a **duplicate id** anywhere in the case (one namespace); a
  duplicate case id across files (`ContentDB`).
- **Metadata:** `metadata.canon` not a bool.
- **Missing text keys**, and any key missing from the `en` or `vi`
  translations.
- **Suspect/evidence/claim fields:**
  - an unknown claim `kind` (its proof sets are still validated, so a typo
    can't hide broken references), an invalid `veracity`, or a derived claim
    that isn't true;
  - a statement speaker who isn't a suspect;
  - evidence with no `source`, an invalid `certainty` or time, or
    `unlock_requires` pointing at a non-deduction;
  - an unexplained `misleading` item.
- **Proof sets:**
  - an **invalid relation**;
  - a relation that contradicts ground truth (kind/veracity table above);
  - an **empty proof set**;
  - **duplicate items** in a set;
  - references to **undefined evidence or deductions**, or to a
    non-deduction claim;
  - a conclusion using raw evidence;
  - a claim with both establishing and negating sets;
  - a derived claim with no proof sets.
- **Graph:**
  - any **dependency cycle**, reported as a *deduction dependency cycle* or
    a *circular clue unlock* when evidence is locked behind a deduction that
    needs it. Any cycle is an error, even one an alternate proof could route
    around, because prototype cases must be clean DAGs to stay comparable.
  - an **intermediate deduction above depth 2**, reported as
    `intermediate deduction "D3" is at depth 3, above the maximum intermediate
    deduction depth of 2 (…)`. A conclusion on top of a depth-2 deduction is
    valid (see "Inference depth").
  - a **required claim that can never be proven** (a fixed-point walk over
    unlocks and proof sets);
  - a **required question with no valid resolution path**;
  - no required question at all;
  - a ground-truth conclusion that can't be proven.
- **Timeline:**
  - an unknown constraint type;
  - **references to unknown timeline events**;
  - a malformed time;
  - **an obviously invalid window** (earliest after latest);
  - a negative gap or travel time;
  - a constraint source that isn't evidence or a claim;
  - a *required* constraint sourced from a mistaken or deceptive statement.
- **Hints:**
  - a ladder with an unknown target, or a duplicated ladder;
  - not exactly the four levels in order;
  - **missing question, category, evidence or deduction references**;
  - a level 4 that reveals the conclusion;
  - a required deduction or conclusion with no ladder.
- **Ground truth:**
  - missing;
  - a culprit, credential owner or conclusion that is unknown;
  - a solution timeline that is incomplete, or that **violates its own
    required constraints** (checked with `TimelineEvaluator`, the same code
    the game runs).
- **Structural roles:**
  - a **missing `structural_role`** or a reused role (when a template is
    declared);
  - **cases sharing a `structural_template` whose structural signatures
    differ**.

**Warnings:**
- a proof set duplicating another on the same claim;
- a non-required claim whose proof sets can never be satisfied;
- evidence that can never be unlocked;
- **evidence locked behind a deduction and then required by a deduction or
  conclusion** (see "Evidence availability"). Real content must produce zero
  warnings, so for the prototype cases this is enforced by
  `deduction_validation_test.gd` and `smoke_test.gd`.

## Structural roles and equivalence

Every suspect, question, evidence item, claim and timeline event carries a
`structural_role`: the case-independent part it plays (`credential_use_record`,
`candidate_exclusive_control`, `bystander_innocent_lie`, …). The full role
table for the `credential_misuse_v2` template is in
`docs/deduction-prototype-cases.md`.

`DeductionValidator.structural_signature(case)` turns a case into a sorted
list of role-only entries:
- roles, with each claim's kind, veracity and `required` flag;
- every proof set as `claim role : relation : [input roles] : depth`, so
  alternate paths and conclusions must also match in inference depth;
- unlock requirements, compatible lists and question resolutions;
- timeline events and constraint shapes (type, event roles, required,
  source role);
- hint ladders and ground-truth roles.

Ids, text and times are left out. Two cases with the same
`metadata.structural_template` must have **identical** signatures. The error
names the missing and unexpected entries. This compares proof-graph shape,
not raw counts.

## Save/load (deferred)

Deduction progress is **not** persisted through `SaveManager` in this
milestone.

- **Why deferred:** nothing owns a session at runtime yet. There is no
  prototype screen, and no autoload (see the decision above). Persisting
  means choosing where a session lives, and whether deduction progress
  resets with a narrative case's New Game. Those decisions belong with the
  first real prototype screen, not with the comparison sandbox.
- **What exists instead:** `DeductionSession.to_dict()`/`load_dict()` are
  JSON-safe and strict. A malformed dictionary is rejected whole, and
  loading emits no signals. `deduction_evaluator_test.gd` round-trips a
  session through `JSON.stringify`/`JSON.parse_string`, the same path
  `SaveManager` uses. It asserts that resolved claims, integer hint levels,
  the attempt log and evidence unlocks all survive.
- **When integrated:** the obvious zero-format-change route is a
  `GameState.variables["deductions"][case_id] = session.to_dict()` entry,
  written before `SaveManager.save_game()` and restored after
  `load_game()`, plus a case in `save_load_regression_test.gd`. See the
  `godot-testing` skill's "Save/load" section.

## Instrumentation

`DeductionSession` emits local Godot signals:
- `evidence_opened(evidence_id)`
- `proof_committed(claim_id, relation, category)`
- `claim_resolved(claim_id, status)`
- `deduction_unlocked(claim_id)`
- `hint_revealed(target_id, level)`
- `case_solved(case_id)`

There is no sink, recorder or network; the project has no telemetry
abstraction to hook into. The full event contract, including what is
deliberately deferred to the prototype UI (hypothesis created, timing), is
in `docs/deduction-playtest-plan.md`, "Instrumentation".

## Adding a deduction case

1. Copy a prototype file in `data/deductions/prototypes/` to
   `data/deductions/<folder>/<case_id>.json`. Give it a new `id` and set
   `metadata.canon` honestly.
2. Write the **ground truth first**: the objective sequence of events,
   culprit and method, and each suspect's real activity. Then derive
   evidence as observations of that truth, never as interpretations.
3. Author claims:
   - statements, with honest `veracity`;
   - hypotheses players will plausibly hold mid-case;
   - intermediate deductions, at most depth 2 (see "Inference depth");
   - one conclusion that combines deductions and genuinely **entails** the
     answer under rules the case states. Access, opportunity, motive, a lie
     or staging must never be enough on its own. Write down, for every
     plausible alternative actor, the fact that eliminates them (see
     `docs/deduction-prototype-cases.md`, "Proof obligations").

   Give each provable claim one or more proof sets. A second proof set is an
   alternate proof of the **same** proposition, at the same strength, not
   weaker corroboration. Put "consistent but not proof" observations in
   `compatible`.
4. Make every clue a deduction needs independently available. Don't gate
   evidence behind a deduction (`unlock_requires`) until an
   investigation-action system represents the discovery (see "Evidence
   availability"). Teach any physical or specialist rule with its own
   reference evidence item.
5. Author questions with `resolved_by`, a four-level hint ladder for every
   required deduction and the conclusion, and a timeline whose
   `ground_truth.solution_timeline` satisfies every required constraint.
6. Add every text key to `localization/strings.csv` in both `en` and `vi`,
   using the `DED_<CASE>_…` convention (see `docs/localization.md`).
7. If the case must be comparable with others, set the same
   `structural_template` and reuse the role names from
   `docs/deduction-prototype-cases.md`. The validator then enforces the
   shared shape.
8. Run the FAST command from `docs/testing.md`, then document the case the
   way `docs/deduction-prototype-cases.md` does, and work through its
   "Human audit checklist". A reviewer must be able to audit it without
   reading code.

No script needs to change.

## Testing

| File | Covers |
|---|---|
| `scenes/test/deduction_evaluator_test.gd` | The result-category contract, order independence, alternate proofs, duplicates, locked inputs, unlock-only-on-commit, conclusion locking, refutations, hint ladders, deterministic reset, JSON round trip. |
| `scenes/test/timeline_evaluator_test.gd` | Every constraint type on both sides of its boundary, multiple valid timelines, optional violations, invalid input, fail-closed constraints. |
| `scenes/test/deduction_validation_test.gd` | One negative fixture per validation rule, the inference-depth definition (D1, D2 and a conclusion on D2 pass; a third intermediate layer fails), conclusion/kind-change graph soundness, the deduction-gated-evidence warning, plus zero deduction errors/warnings in real content. |
| `scenes/test/deduction_cases_test.gd` | All three real cases, walked in structural-role terms: primary and alternate path, conclusion locking, final-proof sufficiency (access, opportunity, staging or a lie never resolves the conclusion; removing exclusive-control evidence makes it unprovable), elimination of every alternative actor, independent evidence availability, the taught staging rule, wrong attempts, statements/hypotheses/red herring, role topology and depth, timelines, and identical structural signatures. |
| `scenes/test/deduction_fixtures.gd` | Not a test: the hand-built fixture case the unit tests use. |

All four are in FAST and FULL (`docs/testing.md`).

## Known limitations

- **No UI.** Evaluation, validation and content are headless-verified only.
- **Not persisted** (see "Save/load (deferred)").
- **Single-day times.** `"HH:MM"` with no midnight wrap-around. A case
  crossing midnight would need a day offset field.
- **Reachability is about authored proofs, not real-world logic.** The
  validator proves the *authored* graph is solvable and consistent with its
  *authored* ground truth. Whether a proof set is actually rational is a
  human review question, which is why every case has an audit document.
- **Tag vocabulary is free-form.** Hint categories must match some evidence
  tag, but tags are not a closed list.
- **`compatible_not_proof` is intentionally broad.** It covers "consistent
  observation", "split across alternates" and "wrong relation", so feedback
  never tells a player which of those it was.
