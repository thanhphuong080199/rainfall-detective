# Milestone 1.15B — Technical Core Loop Contract

**Document status:** Technical handoff for Milestone 1.16 planning

**Evidence boundary:** This contract is extracted from the reported Milestone 1.15A decisions and the 1.15B brief. The repository was not accessed or tested during this session. Every statement about current capability is reported context, not a fresh source-code audit.

## Decision statuses

- `LOCKED FOR TECHNICAL SANDBOX` — required behavior for Milestone 1.16.
- `REPOSITORY AUDIT REQUIRED` — intended behavior is clear, but existing implementation or reuse boundary must be inspected before planning code changes.
- `PROVISIONAL` — implementable baseline whose tuning may change.
- `DEFERRED TO VERTICAL SLICE` — intentionally outside Milestone 1.16.
- `REQUIRES HUMAN PLAYTEST` — cannot be established by technical QA, telemetry, or desk research.

No item in this document is described as human-validated.

## 1. Purpose and non-goals

### Purpose

Milestone 1.16 must produce a production-shaped, end-to-end technical sandbox that can be launched through normal gameplay and completed without Deduction Lab or other debug UI.

The sandbox must prove that the game can:

1. start or resume a dummy chapter;
2. acquire evidence through investigation;
3. form a clue connection through Prototype B;
4. apply that reasoning in a Prototype A confrontation;
5. acquire new information and form a second B deduction;
6. reconstruct events through Prototype C;
7. answer a final claim and complete the chapter;
8. save, quit, load, restart, and repeat the loop without leaking state;
9. expose only player-safe data in VI and EN;
10. record evaluation events without making the recorder gameplay state.

These goals are `LOCKED FOR TECHNICAL SANDBOX`.

### Non-goals

The following are `DEFERRED TO VERTICAL SLICE`:

- canon plot, real chapter content, or final character writing;
- production art, animation, audio, dialogue polish, or final visual design;
- final puzzle difficulty and chapter pacing;
- multiple endings;
- production-scale content optimization;
- a full accessibility certification pass;
- final hint tuning or final failure thresholds;
- human-playtest validation;
- a content editor, visual scripting tool, or mod system;
- generalized quest, plugin, networking, multiplayer, or analytics architecture.

Placeholder presentation and existing dummy content are acceptable. Runtime components must remain content-agnostic; no reusable system may hardcode the selected dummy case.

## 2. Locked sandbox invariants

| Invariant | Status |
|---|---|
| B is the recurring clue-connection mechanic; A is confrontation; C is chapter-end reconstruction | `LOCKED FOR TECHNICAL SANDBOX` |
| Required flow is Investigation → B1 → A → Investigation → B2 → C timeline → final claim → completion | `LOCKED FOR TECHNICAL SANDBOX` |
| A/B/C run through a production gameplay route and do not depend on Deduction Lab | `LOCKED FOR TECHNICAL SANDBOX` |
| Free exploration and draft editing never consume formal attempts | `LOCKED FOR TECHNICAL SANDBOX` |
| Only a new, complete, evaluator-graded incorrect formal submission consumes the local budget | `LOCKED FOR TECHNICAL SANDBOX` |
| Duplicate-equivalent failed candidates are blocked without cost | `LOCKED FOR TECHNICAL SANDBOX` |
| Failure budget belongs to the active resolution unit | `LOCKED FOR TECHNICAL SANDBOX` |
| Guided, Assisted, and partner resolution prevent hard lock | `LOCKED FOR TECHNICAL SANDBOX` |
| Run result records the highest help level actually used; failures are separate data | `LOCKED FOR TECHNICAL SANDBOX` |
| The orchestrator owns consequences; mechanic logic evaluates answers | `LOCKED FOR TECHNICAL SANDBOX` |
| Save snapshot is gameplay truth; recorder output is observational | `LOCKED FOR TECHNICAL SANDBOX` |
| Result screen gives a narrative summary, not a score or assistance badge | `LOCKED FOR TECHNICAL SANDBOX` |
| `3 standard failures + 2 assisted failures` is the initial local budget | `PROVISIONAL` |
| Final feel, difficulty, pacing, and agency | `REQUIRES HUMAN PLAYTEST` |

## 3. Target playable loop

```text
Main Menu
→ New Game or Continue
→ Dummy Chapter Briefing
→ Investigation
→ NPC or hotspot interaction
→ Evidence acquired and visible in Case File
→ B1 assigned and resolved
→ Confrontation unlocked
→ A required contradiction resolved
→ New evidence, interaction, or location unlocked
→ B2 assigned and resolved
→ C timeline unlocked and accepted
→ Final claim plus supporting fact accepted
→ Chapter completed
→ Narrative Result screen
→ Restart chapter or return to menu
```

The sandbox may be linear. Its architecture must express the flow through content and durable state rather than case-specific branches in reusable runtime logic.

## 4. Three-layer state model

Progression must not be inferred from which screen happens to be visible.

### 4.1 Durable chapter state

This is authoritative gameplay truth and belongs in the save snapshot:

- active run, case, chapter, and chapter phase;
- acquired evidence, visited/unlocked locations, completed interactions;
- offered, active, and resolved resolution units;
- resolved deductions and statements;
- actual accepted proof path for each resolution;
- timeline draft and accepted timeline;
- final-claim result;
- progression consequences already applied;
- hints, assistance, failures, duplicate signatures, and partner attribution;
- run help result;
- active mechanic snapshot when a unit is unresolved.

### 4.2 Active mechanic state

This is durable while a resolution unit exists, even if its screen closes:

- current unit and target;
- available player-safe evidence/facts;
- A statement/evidence selection;
- B clue draft;
- C event placements and final-claim selection;
- current local failure phase and failed-equivalence set;
- revealed hints and accepted assistance;
- last durable outcome needed to reproduce pending feedback.

Whether this state is stored inside an existing session object or a new production snapshot is `REPOSITORY AUDIT REQUIRED`. Conceptual ownership remains with the active chapter run, not the UI scene.

### 4.3 Transient UI state

This can safely reset after load unless existing UX requirements say otherwise:

- scroll offsets;
- hover state;
- animation progress;
- transient focus within a reopened panel;
- open tooltip;
- temporary modal layering;
- presentation-only caches.

The current mechanic and its draft must survive; the exact temporary widget state need not.

## 5. Core loop state machine

State names below are contract labels, not required class names or enum values.

| Chapter phase | Entry condition | Player actions | Allowed transition | Completion condition | Checkpoint | Invalid transition | Resume behavior |
|---|---|---|---|---|---|---|---|
| Menu / no active chapter | Application start, return to menu, or no resumable save | New Game, Continue, locale, quit | New Game → Briefing; Continue → saved phase | A run is selected | Before replacing an existing run | Continue without valid save stays on menu with a safe message | Recompute menu from save availability |
| Briefing | New run initialized with valid dummy chapter | Read, change locale, continue, menu | Continue → Investigation B1 | Briefing acknowledged | After run creation and acknowledgement | Deduction commands are rejected without evaluator access | Reopen briefing if unacknowledged; otherwise saved phase |
| Investigation B1 | Briefing complete | Navigate, inspect, talk, acquire/open evidence, Case File, open B when offered | B1 resolution → Confrontation A | Required B1 consequence applied | Evidence acquisition, B1 resolution, quit | Opening unavailable unit or locked destination is a no-op plus player-safe reason | Restore location, evidence, B draft, and phase |
| Confrontation A | B1 consequence has unlocked required confrontation | Review testimony/evidence, select, submit, hint, assistance, partner, leave/reopen | Required A resolution → Investigation B2 | Required contradiction consequence applied | Every durable A outcome and phase transition | Hidden statement/target or inactive unit is rejected before evaluation | Reopen A at exact unit state or canonical confrontation entry |
| Investigation B2 | A consequence has opened new interaction/evidence/location | Investigate, acquire/open evidence, Case File, open B2 | B2 resolution → Timeline C | Required B2 consequence applied | Acquisition, B2 outcome, quit | B2 cannot be offered until dependencies are satisfied | Restore current location and exact B2 draft |
| Timeline C | B2 consequence has unlocked reconstruction | Read facts, place/remove events, submit, hint, assistance, partner | Accepted timeline → Final Claim | Required constraints accepted | Durable C outcomes and transition | Incomplete or inactive submissions never reach evaluator | Restore exact placements; reopen timeline screen |
| Final Claim | Timeline accepted | Review accepted timeline, select verdict and support, submit, hint, assistance, partner | Accepted claim → Completed | Claim consequence applied atomically | Every durable claim outcome and completion | Claim cannot submit before accepted timeline | Restore accepted timeline and current claim state |
| Completed | Final claim consequence completed chapter | Read summary, restart, menu | Restart → new Briefing; Menu → Menu | Already complete | Completion before showing result | Gameplay commands cannot mutate completed run | Reopen narrative Result screen |

### 5.1 Phase, screen, and resolution are independent

- **Chapter phase** states what progression is currently allowed.
- **Open screen** is navigation state. Case File can be opened during investigation without changing phase.
- **Resolved gameplay state** records facts such as `B1 resolved` or `timeline accepted` and is what permits a phase transition.

Opening Prototype B does not mean B is resolved. Closing a mechanic does not undo its draft. Showing success feedback does not itself apply progression; progression must already have been committed.

### 5.2 Transition invariant

Every durable transition follows this conceptual order:

1. validate command against active phase and unit;
2. evaluate through the correct mechanic/evaluator;
3. produce a mechanic outcome without applying chapter consequences;
4. let the chapter orchestrator apply the mapped consequence idempotently;
5. update phase when its completion condition is true;
6. atomically checkpoint durable state;
7. expose player-facing feedback;
8. emit or queue observational recorder events.

Exact transaction and event APIs are `REPOSITORY AUDIT REQUIRED`; the ordering is `LOCKED FOR TECHNICAL SANDBOX`.

## 6. Runtime ownership

Names in this section describe conceptual roles, not required implementation classes.

| Owner | Owns | Must not own |
|---|---|---|
| Chapter runtime/orchestrator | Active run, phase, active unit, consequence mapping, phase transitions, chapter completion | Puzzle correctness algorithms, UI widgets, recorder files |
| Investigation state | Current/visited/unlocked locations, completed interactions, acquired evidence | Deduction answer truth, chapter transition policy |
| Deduction session/snapshot | Opened evidence, resolved claims/deductions, accepted paths, hint and attempt state required by evaluators | Location unlock execution, screen navigation |
| A controller | Testimony-part state, selection, formal contradiction evaluation, A-local outcomes | Direct chapter unlocks, global phase transition |
| B controller | Question-scoped draft, formal clue-set evaluation, B-local outcomes | Direct location/evidence unlocks, multi-question chapter sequencing |
| C controller | Timeline placements, formal timeline evaluation, final-claim unit state and outcomes | Chapter completion mutation |
| Save service | Versioned serialization, atomic persistence, corruption handling, restore delivery | Deciding game rules or recomputing an answer |
| Recorder | Ordered local observation of commands/outcomes/transitions | Authoritative attempts, progression, save restore, evaluator decisions |
| Presenter/view model | Player-safe localized projection and available commands | Domain truth, hidden answer data, mutation outside commands |
| Content database | Loaded content and stable lookup | Mutable run state |
| Validator | Static reference, reachability, proof, localization, and sandbox-route checks | Runtime progression or automatic content repair |
| Deduction Lab | Debug inspection, author testing, isolated prototype launch | Production runtime ownership or required gameplay navigation |

### Ownership answers

1. **Who owns the shared session?** The active chapter run owns durable deduction truth. A/B/C receive scoped state for their unit. Whether one existing session instance can satisfy this contract is `REPOSITORY AUDIT REQUIRED`.
2. **What survives opening and closing A/B/C?** Drafts, selections needed for exact resume, formal outcomes, failures, duplicate signatures, hints, assistance, resolutions, and attribution survive. Scroll/hover/animation do not.
3. **Who applies progression unlocks?** The chapter orchestrator, through existing condition/effect/event capabilities if the audit finds them sufficient.
4. **How does a mechanic return a result?** Through one internal outcome envelope containing unit identity, outcome category, resolved target/path when applicable, help attribution, and a player-safe feedback reference. The exact data shape is a contract proposal.
5. **Who changes chapter phase?** The orchestrator after durable completion conditions and consequences succeed.
6. **Who creates checkpoints?** The orchestrator requests them at durable boundaries; the save service writes them.
7. **Who restores?** The save service reads and validates; the orchestrator rebuilds the run and scoped mechanic state; presenters rebuild views.
8. **Where does the recorder observe?** At command/outcome and committed domain-transition boundaries. It may record free exploration events but never drives them.
9. **Can Deduction Lab own production runtime?** No. `LOCKED FOR TECHNICAL SANDBOX`.

## 7. Common mechanic outcome contract

The following is a capability proposal, not a claim about an existing schema:

```text
MechanicOutcome
  active run and resolution-unit identity
  outcome category
  normalized candidate signature when relevant
  resolved target and accepted path when successful
  local resolution-policy state after the command
  run help result after the command
  player-safe feedback reference and parameters
  chapter consequence key only when resolution succeeded
```

Required outcome categories:

- selection/draft changed;
- invalid input;
- duplicate blocked;
- meaningful formal failure;
- player resolved;
- hint revealed;
- assistance entered;
- partner resolved;
- mechanic completed;
- aborted/closed without completion;
- internal/content error.

Internal identifiers may cross runtime boundaries but must be removed or mapped to opaque view handles before reaching player UI.

## 8. Prototype A contract — Statement Contradiction

### Inputs

- active run, chapter, A resolution unit, and testimony part;
- player-safe statements and question framing;
- currently available evidence;
- prior required/optional statement resolutions;
- selection, hint, local failure, duplicate, assistance, and run-result state;
- content-defined accepted single-evidence refutations and near-valid handling.

### Player commands

- inspect statement;
- inspect evidence;
- select/change statement;
- select/change/remove evidence;
- formal Present Evidence;
- request Guided hint;
- accept Assisted help;
- resolve with partner when offered;
- close and later reopen.

### Outputs

- selection changed;
- invalid submission;
- duplicate statement/evidence pair blocked;
- relevant but insufficient;
- correct evidence on adjacent wrong statement;
- unsupported accusation and meaningful failure;
- optional innocent lie resolved;
- required contradiction resolved by player or partner;
- hint/assistance/partner state changed;
- part or encounter completed;
- aborted without completion.

### Side-effect policy

- A may mutate only its scoped selection, local Resolution Policy state, resolved-statement state, accepted path, and last outcome.
- A does not add evidence, unlock dialogue/location, or advance chapter phase directly.
- On required resolution it returns a consequence reference to the orchestrator.
- Recoverable witness pressure may be represented in the A snapshot, but cannot withhold mandatory content. `LOCKED FOR TECHNICAL SANDBOX`.
- Local credibility/witness-pressure tuning remains `PROVISIONAL`.

### Resume behavior

| Save point | Resume contract |
|---|---|
| Selection before submit | Restore selected statement/evidence and active part |
| Failed feedback | Restore consumed failure, duplicate signature, pressure state, and feedback descriptor; never charge again |
| Required/optional resolution | Restore resolution and accepted path; do not replay consequence |
| Assisted Mode | Restore help already revealed and remaining local budget |
| Partner resolution | Restore `resolved_by: partner`, explanation path, and applied consequence |
| Transition to next phase | Reopen the next phase; never reconstruct A as unresolved |

## 9. Prototype B contract — Clue Connection

### Inputs

- active run, B resolution unit, and chapter-assigned question;
- question-scoped evidence drawn only from already acquired evidence;
- a two- or three-slot requirement;
- private clue draft;
- resolved deductions and actual accepted paths;
- hint, local failure, duplicate, assistance, and run-result state;
- finite authored proof paths and near-valid combinations.

### Player commands

- inspect/open/pin evidence;
- add, remove, replace, or reorder draft clues;
- formal Commit Deduction;
- request Guided hint;
- accept Assisted premise;
- resolve with partner when offered;
- close and later reopen.

### Outputs

- draft changed;
- invalid/incomplete draft;
- duplicate-equivalent failed clue set blocked;
- relevant but insufficient combination;
- meaningful formal failure;
- deduction resolved by player or partner with the actual accepted path;
- hint/assistance/partner state changed;
- mechanic completed;
- aborted without completion.

### Side-effect policy

- B evaluates one deduction at a time. Batch commitment of B1 and B2 is not part of the 1.16 contract.
- B may mutate its draft, local Resolution Policy state, resolved deduction, actual proof path, and last outcome.
- B does not directly unlock a location, evidence, confrontation, or chapter phase.
- On resolution it returns a content-defined consequence reference. The orchestrator applies it and records its source.
- Used clues remain acquired and reusable.
- Only proven connections enter durable case-board truth; draft links remain private.

### Resume behavior

| Save point | Resume contract |
|---|---|
| Partial draft | Restore exact clue set and question |
| Failed feedback | Restore failure, signature, and feedback descriptor; no repeat charge |
| Assisted Mode | Restore surfaced premise and remaining attempts |
| Player resolution | Restore deduction, actual proof path, and applied consequence |
| Partner resolution | Restore partner path and explanation attribution |
| Transition | B1/B2 stays resolved; reopen confrontation, investigation, or timeline as appropriate |

Reported Prototype B batch behavior versus this single-deduction target is `REPOSITORY AUDIT REQUIRED`.

## 10. Prototype C contract — Timeline and final claim

### Inputs

- active run and C resolution-unit identity;
- player-safe events, facts, sources, candidate positions, and fixed anchors;
- current placements and accepted timeline, if any;
- final-claim options and eligible supporting facts only after timeline acceptance;
- independent local Resolution Policy state for timeline and final claim;
- all required constraints and finite accepted alternatives.

### Player commands

- inspect events/facts/sources;
- place, move, or remove an event;
- formal Submit Timeline;
- request/accept help or partner resolution for timeline;
- select/change verdict and supporting fact;
- formal Submit Final Claim;
- request/accept help or partner resolution for final claim;
- close and later reopen.

### Outputs

- placement or claim draft changed;
- incomplete/invalid input;
- duplicate-equivalent placement or verdict/support pair blocked;
- broad constraint-class failure;
- accepted timeline with actual placement;
- final-claim meaningful failure;
- final claim resolved by player or partner;
- hint/assistance/partner state changed;
- mechanic completed;
- aborted without completion.

### Side-effect policy

- Timeline and final claim are separate formal units with separate local budgets.
- C mutates placements, accepted timeline, claim draft, unit Resolution Policy state, attribution, and last outcome.
- C does not mark the chapter complete directly.
- Accepted timeline returns the consequence that makes final claim active.
- Accepted final claim returns the consequence that completes the chapter.
- Partner resolution solves only the stuck unit. A partner-solved timeline still leaves final claim for the player with a fresh local budget.

### Resume behavior

| Save point | Resume contract |
|---|---|
| Partial timeline | Restore exact placements and opened facts |
| Failed timeline feedback | Restore failure, signature, and feedback descriptor |
| Assisted timeline | Restore the revealed premise; do not move events automatically |
| Accepted timeline | Restore and lock accepted placement; enter/reopen final claim |
| Partial final claim | Restore selected verdict/support |
| Failed final-claim feedback | Restore its separate failure/signature state |
| Partner timeline | Preserve partner attribution; final claim remains unresolved |
| Completed claim | Restore completed chapter and Result screen; do not resubmit |

## 11. Progression contract

### 11.1 Outcome-to-consequence mapping

| Outcome | Minimum supported consequence |
|---|---|
| Evidence acquired | Add evidence to durable inventory and make it available to eligible views |
| B deduction resolved | Add proven deduction/path; unlock evidence, interaction, location, confrontation, objective, or phase defined by content |
| A required statement refuted | Add statement resolution/path; unlock response, evidence, interaction, B2, or phase |
| Optional A lie resolved | Record optional resolution and optional response only; never satisfy required progression unless explicitly authored as required |
| C timeline accepted | Store accepted placement and activate final claim |
| Final claim accepted | Apply chapter completion consequence and enter completed phase |

### 11.2 Consequence requirements

Every durable consequence must be:

- **idempotent:** applying it twice produces the same gameplay state as once;
- **attributable:** debug output can state which outcome/consequence produced an unlock;
- **reference-valid:** all source, target, and content references can be validated;
- **phase-safe:** it does not depend on a UI node being open;
- **restore-safe:** loading a post-consequence save does not execute it again;
- **explainable:** an author/debug view can trace required progression backward to its producer.

### 11.3 Edge behavior

- **Already unlocked:** idempotent no-op for gameplay; optionally record a diagnostic, never duplicate rewards or events.
- **Out of order:** a hidden or inactive resolution unit cannot be opened or formally submitted. Reject before evaluator mutation.
- **Optional resolution:** may add optional context or dialogue but cannot silently become a producer for required completion.
- **Red herring:** can be useful elsewhere or insufficient for the active question; resolving an optional red-herring thread cannot satisfy a required target unless content explicitly changes its classification.
- **Invalid/unreachable transition:** preserve current state, show a safe error when player-visible, and emit a diagnostic in debug builds.
- **Circular dependency:** boot/CI validation failure, not a runtime puzzle.

The existing condition/effect/event system should be reused if it can express these bounded consequences. Reuse versus minimal extension is `REPOSITORY AUDIT REQUIRED`. A generic quest language or arbitrary scripting layer is forbidden for 1.16.

## 12. Experimentation and formal commitment

### 12.1 Free experimentation

The following never consumes a formal attempt:

- opening or rereading evidence;
- pinning, filtering, or navigating Case File;
- changing A selection;
- adding/removing/reordering B draft clues;
- placing/moving/removing C events;
- changing final-claim draft before submission;
- opening notebook/case board;
- navigating locations or dialogue;
- incomplete or structurally invalid submit attempts;
- resubmitting a previously failed semantic-equivalence class.

Free experimentation may be recorded for evaluation, but must not produce a correctness oracle.

### 12.2 Formal commitment

| Mechanic | Formal command | Evaluated candidate |
|---|---|---|
| A | Present Evidence | Statement + one evidence item |
| B | Commit Deduction | Complete order-independent clue set for one assigned question |
| C timeline | Submit Timeline | Complete placement |
| C claim | Submit Final Claim | Verdict + supporting fact |

### 12.3 Candidate classification

- **Invalid input:** missing, structurally malformed, inactive, or not eligible. No attempt consumed.
- **Duplicate candidate:** normalized equivalent to an earlier failed candidate in the same unit. Blocked, no attempt consumed.
- **Meaningful failure:** complete, active, new, evaluator-graded, and incorrect. Consumes one local failure.
- **Valid optional outcome:** accepted and recorded, never a failure.
- **Resolution:** accepted required solution path, resolved by player or partner.

Semantic normalization is mechanic-specific and order-independent where order has no meaning. Its exact current implementation is `REPOSITORY AUDIT REQUIRED`.

### 12.4 Resolution Policy

```text
Standard
→ after 3 meaningful failures: Assisted help must be acknowledged
→ after 2 more meaningful failures: partner resolution available
```

The thresholds are `PROVISIONAL`; the separation of local budget from run result is locked.

- **Independent:** no Guided hint, Assisted premise, or partner resolution used.
- **Guided:** at least one Guided hint used, but no Assisted premise or partner resolution.
- **Assisted:** an Assisted premise or partner resolution used.

Run result is the maximum help level actually used across the run. Failed attempts alone do not change it. Result screen does not show it as a grade; save, detailed case history, and recorder may store it.

## 13. Save/load contract

### 13.1 State classification

`✓` indicates the primary classification. “Recompute” means derive only from persisted gameplay truth and content, never from recorder history.

| State | Persist | Recompute | Runtime-only | Recorder-only | Debug-only |
|---|:---:|:---:|:---:|:---:|:---:|
| Current run/case/chapter | ✓ |  |  |  |  |
| Chapter phase | ✓ | validate |  |  |  |
| Visited/current/unlocked locations | ✓ |  |  |  |  |
| Completed interactions | ✓ |  |  |  |  |
| Acquired evidence | ✓ |  |  |  |  |
| Opened/read/pinned evidence | ✓ |  |  |  |  |
| Available B question set |  | ✓ |  |  |  |
| A selection and resolved statements | ✓ |  |  |  |  |
| B drafts, resolved deductions, accepted paths | ✓ |  |  |  |  |
| Optional resolutions | ✓ |  |  |  |  |
| C placements and accepted timeline | ✓ |  |  |  |  |
| Final-claim draft and resolution | ✓ |  |  |  |  |
| Hint progress | ✓ |  |  |  |  |
| Local unit phase/failures | ✓ |  |  |  |  |
| Duplicate candidate signatures | ✓ |  |  |  |  |
| Run help result | ✓ |  |  |  |  |
| Partner-resolution attribution | ✓ |  |  |  |  |
| Applied consequence identities/sources | ✓ |  |  |  |  |
| Last durable feedback descriptor | ✓ | localized text |  |  |  |
| Active resolution-unit identity | ✓ |  |  |  |  |
| Current canonical screen for active phase |  | ✓ |  |  |  |
| Scroll, hover, tooltip, animation |  |  | ✓ |  |  |
| Recorder events and recorder sequence |  |  |  | ✓ |  |
| Active-play elapsed duration |  |  |  | ✓ |  |
| Debug Lab selection/inspector state |  |  |  |  | ✓ |

### 13.2 Checkpoint policy

Create a durable checkpoint:

- after evidence acquisition or any required progression interaction;
- after every valid formal resolution;
- after every meaningful failure;
- after hint reveal or assistance/partner-state change;
- before exposing a completed phase transition to UI;
- on safe quit;
- on chapter completion;
- after explicit restart creates the new run.

Frequent draft edits may be checkpointed immediately or on mechanic close/quit, provided an ordinary save/load restores the latest acknowledged player draft. The implementation choice is `REPOSITORY AUDIT REQUIRED`.

### 13.3 Atomicity

A formal outcome and its durable consequences form one logical checkpoint. The save must never represent:

- a consumed failure without its failed signature;
- a resolved deduction without its accepted path;
- an applied unlock without its producer resolution;
- an accepted timeline with final claim still marked unavailable;
- a completed claim with chapter still incomplete;
- partner attribution without the corresponding resolution.

Storage format and atomic-write mechanism are not specified here. They must match existing project conventions after audit.

### 13.4 Schema and migration

- Save data requires an explicit schema version.
- 1.16 must define the oldest schema it can load; no speculative migration framework is required.
- A supported older save is migrated once to a valid current snapshot.
- An unsupported or corrupted save never partially loads. Preserve the file for diagnosis when practical, show a safe Continue failure, and allow New Game.
- Restore is idempotent and emits no acquisition, unlock, formal-attempt, or completion event as if it just occurred.
- A resumed run may emit one explicit `chapter resumed` observation.

Exact current save capabilities are `REPOSITORY AUDIT REQUIRED`.

## 14. Player-facing UI boundary

### 14.1 General rules

- Target 1280×720 with VI and EN.
- Keyboard and mouse must complete the entire sandbox.
- Content scrolls; primary action and Return/Continue remain in a fixed reachable footer.
- Focus ownership is explicit when screens/modals open and returns to a sensible control when they close.
- Presenters expose allow-listed, localized view data and commands.
- Player views never expose domain ids, hidden proof sets, veracity, ground truth, author notes, debug metadata, future graph topology, or raw evaluator categories.
- Placeholder visuals are acceptable. Final visual style is `DEFERRED TO VERTICAL SLICE`.

### 14.2 Minimum screens

| Screen | Purpose and safe view data | Commands and navigation | Exit/resume/error behavior |
|---|---|---|---|
| Main Menu | New Game, Continue availability, locale | Start, continue, locale, quit | Invalid/corrupt Continue stays here with safe message |
| Briefing | Localized dummy chapter title/objective | Continue, menu, locale | Resume until acknowledged; no deduction data |
| Investigation | Current location, player-safe NPC/hotspot/destination state | Examine, Talk, Present if supported, Move, Case File, menu | Locked action explains unavailable state without ids |
| Dialogue/NPC | Localized lines, choices, acquired evidence notification | Advance/choose, Case File when allowed, return | Restores durable dialogue/progression state; presentation position may reset |
| Case File | Acquired evidence, short facts, expandable source, proven connections | Inspect, pin, open offered B, return | Empty inventory has explicit empty state |
| Prototype B | Assigned question, eligible acquired clues, 2–3 slots, draft, help state | Inspect, add/remove, commit, hint, assistance, partner, return | Reopens exact draft; no hidden target/relation leak |
| Prototype A | Testimony, available evidence, selection, witness-pressure/help state | Inspect/select/present, hint, assistance, partner, return | Reopens exact part and selection; no veracity leak |
| Prototype C | Events, facts, sources, placements, fixed anchors; then final claim | Place/remove/submit, hint, assistance, partner, return | Reopens exact placements or claim draft; keyboard alternative required |
| Hint/Assistance | Current mechanic's next player-safe help level | Reveal, accept, close, partner when offered | Never shows future levels before they are available |
| Chapter Result | Narrative causal summary and completion actions | Restart, menu | No score, rank, or Independent/Guided/Assisted badge; internal run result remains stored |

Mechanic screens may be separate scenes or modes of a shared shell. That implementation choice is `REPOSITORY AUDIT REQUIRED`; the boundary above is locked.

## 15. Content capability contract

This section states required capabilities, not a new JSON schema.

| Capability | Reported current capability from 1.15A | Audit or possible 1.16 extension |
|---|---|---|
| Case/chapter metadata and completion | Reported present | Confirm production chapter can reference sandbox flow and completion producer |
| Chapter phase/objective sequence | Not established | May need minimal sandbox orchestration metadata |
| Locations, NPCs, interactions | Reported present | Confirm dummy content can acquire required evidence through normal gameplay |
| Evidence and localized display keys | Reported present | Confirm read/pin state and question eligibility |
| Claims, deductions, proof sets | Reported present | Confirm production-scoped target references and accepted alternate paths |
| A confrontation rounds | Reported prototype-specific content | Audit reuse outside debug route and consequence binding |
| B questions, clue pools, slot count | Reported prototype-specific content | Replace/adapter for single-deduction production commit if current content assumes batch |
| Timeline events/constraints | Reported present | Confirm accepted timeline and final-claim binding outside debug route |
| Hint ladders | Reported across base/prototype content | Confirm mechanic-specific Guided/Assisted projection |
| Outcome-to-consequence mapping | Existing condition/effect/event system reported, deduction binding unclear | Prefer bounded reuse; minimal extension only if audit proves a gap |
| Optional content classification | Partly reported through optional contradictions/constraints | Add explicit validation that optional content is not required progression |
| Localization keys | VI/EN reported present | Confirm all new player-facing sandbox strings resolve in both locales |
| Non-canon dummy marker | Dummy/prototype status reported in documentation | Confirm production route can include sandbox content without treating it as canon |

Minimum sandbox content must express:

- briefing and completion text;
- investigation evidence producers;
- B1 and B2 targets with accepted paths;
- A required contradiction and optional content if reused;
- C events, required constraints, accepted alternatives, final claim and supporting facts;
- hints and partner explanations;
- idempotent progression consequences;
- localization keys for all player-facing text.

Do not create a new general-purpose scripting language. Do not duplicate an existing content capability merely to make the sandbox self-contained.

## 16. Validation requirements

### 16.1 Boot/CI content validation

Reject content before gameplay for:

- missing or duplicate ids;
- invalid cross-category references;
- missing VI or EN localization keys;
- deduction target without a valid proof path;
- accepted proof path using unavailable or invalid evidence;
- confrontation part with no resolvable required contradiction;
- unsatisfiable required timeline;
- final claim inconsistent across accepted timelines;
- progression consequence without a valid source or target;
- required target with no producer or no consumer;
- dependency cycle;
- unreachable required evidence, unit, or chapter completion;
- optional content becoming a hidden required dependency;
- debug-only author metadata exposed to a production player view;
- sandbox route that requires Deduction Lab or DebugPanel.

The exact split between existing validator coverage and 1.16 work is `REPOSITORY AUDIT REQUIRED`.

### 16.2 Runtime defensive handling

Runtime must safely handle:

- command sent to an inactive phase/unit;
- incomplete/invalid/duplicate candidate;
- missing presentation data after a content error;
- repeated idempotent consequence;
- unavailable locale string fallback according to project policy;
- unsupported/corrupted save;
- recorder export failure;
- close/quit during active mechanic;
- load at every durable checkpoint.

Recorder failure must not block gameplay. A content error that makes required progression impossible must fail loudly in debug/CI and show a safe non-spoiler error in player UI rather than mutate around the defect.

### 16.3 Automated integration tests

At minimum, production APIs must drive:

- New Game through chapter completion;
- save/load at each phase;
- save/load after failure, hint, assistance, and partner resolution;
- duplicate-equivalence blocking for A/B/C units;
- alternate accepted path where dummy content provides one;
- restart with no previous-run leakage;
- VI and EN view creation;
- no Deduction Lab dependency;
- no player-view metadata leak;
- corrupted/unsupported save fallback;
- existing FAST/FULL regression suite.

This document does not claim those tests currently exist and does not authorize running them in 1.15B.

## 17. Recorder and evaluation contract

### 17.1 Separation from gameplay truth

- Recorder subscribes to observations after commands/outcomes and durable transitions.
- It cannot mutate chapter state, policy state, evaluation, progression, or save decisions.
- Deleting or failing to write a recording cannot change the run.
- Gameplay restore never rebuilds state from recorder events.

### 17.2 Event families

- run/chapter started, resumed, restarted, completed, abandoned;
- phase entered;
- location visited and interaction completed;
- evidence acquired/opened/pinned;
- mechanic/unit opened and closed;
- draft/selection/placement changed, where useful for evaluation;
- formal attempt started and outcome category;
- duplicate candidate blocked;
- deduction/statement/timeline/final claim resolved;
- hint requested/revealed;
- local unit phase changed;
- run help result escalated due to help actually used;
- assistance accepted;
- partner resolution offered/used;
- progression consequence applied or already applied;
- checkpoint saved/restored/failed.

### 17.3 Event envelope requirements

Every event requires:

- event schema version;
- run identity and per-run ordering sequence;
- chapter identity;
- mechanic and resolution-unit identity when applicable;
- elapsed monotonic time when available;
- minimal normalized payload;
- durable transition identity when the event mirrors a saved transition.

Reported recorder envelope/event versions must be audited. If 1.16 changes vocabulary meaning, bump the appropriate schema version; additive events alone follow existing versioning policy after audit.

### 17.4 Resume and deduplication

- Save persists gameplay run identity and enough durable transition identity to avoid replay ambiguity.
- Recorder owns its own event sequence/history.
- Load emits one explicit resume/checkpoint-restored event.
- Restore does not re-emit old evidence acquisition, resolution, unlock, or completion events.
- If recorder history is unavailable, begin a clearly linked or new recording segment without altering gameplay.

### 17.5 Privacy

Keep recordings local and manually exportable. Store stable content/state identifiers, timing, and categories only. Do not add personal identity, machine identity, free-form player text, network upload, or analytics backend.

## 18. Debug and production boundary

| Debug/author capability | Production sandbox rule |
|---|---|
| Deduction Lab | Remains optional debug/author tool; never required to start, own, resume, or complete the chapter |
| Prototype launch buttons | Production route launches mechanics from chapter state and player actions |
| Author inspector/raw definitions | Never included in player view models |
| Debug auto-solve | Not exposed in release/player UI; partner resolution is content-authored and explanatory |
| Test fixture state | Created per test/run; never registered as mutable runtime global |
| Dummy cases | May be reused and marked non-canon; runtime components remain case-agnostic |
| Debug recorder controls | Player route may expose only the minimum evaluation/export surface required by 1.16 |

Production controllers may reuse evaluator/controller logic discovered during audit. They must not require a Deduction Lab scene, its selected case, its recorder instance, or its UI lifecycle.

## 19. Consistency and idempotency matrix

| Durable fact | Producer | Owner | Saved | Player projection | Recorder observation |
|---|---|---|:---:|---|---|
| Evidence acquired | Investigation interaction/consequence | Investigation/chapter state | Yes | Case File and eligible mechanic views | `evidence acquired` once |
| B deduction resolved | B outcome accepted | Deduction/chapter state | Yes | Proven connection and explanation | formal success + deduction resolved |
| Confrontation unlocked | B consequence | Chapter state | Yes | NPC/objective becomes available | consequence applied once |
| A statement resolved | A outcome accepted | Deduction/chapter state | Yes | Testimony response and case detail | formal success + statement resolved |
| New evidence/location unlocked | A consequence | Chapter/investigation state | Yes | Investigation update | consequence applied once |
| Timeline accepted | C timeline outcome | C/chapter state | Yes | Accepted reconstruction, final claim active | timeline success once |
| Final claim accepted | C claim outcome | Chapter state | Yes | Narrative result | claim success + chapter completed |
| Hint/assistance/partner used | Active unit outcome | Unit and run state | Yes | Current help content; no result badge | help event once |
| Checkpoint restored | Save service | No new gameplay mutation | Existing snapshot | Canonical phase/mechanic screen | resume observation only |

If a fact cannot name one producer, one authoritative owner, and one restore path, implementation planning must stop and resolve the ambiguity.

## 20. End-to-end acceptance criteria for Milestone 1.16

All criteria below are `LOCKED FOR TECHNICAL SANDBOX` unless marked otherwise.

1. Player opens the normal game route and selects New Game.
2. A localized dummy chapter begins without F1, DebugPanel, or Deduction Lab.
3. Player acquires required evidence through a normal NPC or hotspot interaction.
4. Acquired evidence appears in Case File with player-safe VI and EN text.
5. Player opens B1 from normal gameplay and resolves one deduction.
6. B1 resolution idempotently unlocks the confrontation or its required progression.
7. Player opens A and resolves the required single-evidence contradiction.
8. A resolution idempotently opens the next evidence, interaction, or location.
9. Player investigates and resolves B2 as a separate single deduction.
10. B2 unlocks C without a debug action.
11. C accepts every authored valid timeline used by the sandbox test fixture.
12. Final claim requires both verdict and supporting fact and can be accepted.
13. Accepted final claim completes the chapter and opens a narrative Result screen. Run help result is retained internally and is not displayed as a score/badge.
14. Result screen can restart the chapter as a clean new run or return to menu.
15. Save/quit/load during each phase restores exact durable gameplay and active mechanic state.
16. Save/load after a formal failure does not refund the attempt or forget its duplicate signature.
17. Duplicate-equivalent A, B, timeline, and final-claim submissions are blocked without consuming another attempt.
18. Guided, Assisted, and partner paths can complete every required unit without hard lock.
19. Run result escalates only when help is actually used; failures remain separate telemetry/budget data.
20. VI and EN can complete the same logical route.
21. Player views leak no ids, answer metadata, veracity, raw constraints, or author/debug fields.
22. Replaying/restarting leaks no inventory, resolution, attempt, hint, consequence, recorder, or completion state from the previous run.
23. One automated integration test drives the full flow through production APIs, not UI-only debug shortcuts.
24. Existing FAST/FULL tests pass without regression when 1.16 implementation is complete.
25. Recorder/export failure does not stop completion or corrupt save.

No acceptance item claims that the sandbox is fun, well-paced, fair to a representative audience, or production-balanced. Those remain `REQUIRES HUMAN PLAYTEST` or `DEFERRED TO VERTICAL SLICE`.

## 21. Claude Code handoff matrix

“Reported” means reported by 1.15A context and must be verified.

| Area | Required behavior | Reported current capability | Repository audit question | Expected 1.16 change |
|---|---|---|---|---|
| Entry route | New Game/Continue starts sandbox normally | Normal menu/case systems reportedly exist; prototypes are debug-only | How are cases/chapters started from menu today? | Add production sandbox route using existing entry conventions |
| Chapter state | Durable phase independent of screen | Chapter progression reportedly event-driven | Can existing chapter/event state represent A/B/C phases idempotently? | Add smallest phase/objective binding needed |
| Investigation | Acquire evidence and unlock content | Generic locations/interactions/evidence reportedly exist | Which existing interactions and effects fit the dummy flow? | Author/reuse dummy progression without case-specific runtime code |
| Shared deduction truth | A/B/C resolutions persist across screens | A/B reportedly own fresh sessions; C reportedly owns timeline state separately | Can existing session snapshot be chapter-owned or adapted? | Establish one durable chapter deduction snapshot boundary |
| Prototype A | Production confrontation, single evidence, resume | Debug A reportedly exists | What controller content and UI dependencies point to Lab/debug scenes? | Reuse/adapt logic behind production route and snapshot |
| Prototype B | One deduction at a time, opens lead | Debug B reportedly batch-commits multiple drafts | How deeply is batching coupled to controller/content/presenter? | Provide single-unit commit contract for B1 and B2 |
| Prototype C | Timeline then separate final claim | Debug C reportedly exists with two units | Can its state serialize and launch without Lab? | Add production ownership, resume, and consequence outputs |
| Resolution Policy | Local budget; run result based on help used | Reported current policy may escalate result from failures | Where are result and failure semantics coupled? | Separate failure telemetry/budget from help attribution |
| Progression | Outcomes map to idempotent consequences | Conditions/effects/events reportedly exist | Can they bind deduction outcomes without arbitrary scripting? | Reuse or minimally extend bounded consequence vocabulary |
| Save/load | Exact mid-unit restore and atomic outcomes | General save reportedly exists; deduction persistence reportedly absent | What schema/version/atomic conventions exist? | Add versioned deduction/chapter snapshot and restore |
| UI | Player-safe normal screens at 1280×720, VI/EN, keyboard/mouse | Debug prototype screens and localization reportedly exist | Which presentation code is reusable without metadata leaks? | Build/adapt production shell and navigation |
| Result | Narrative summary, restart/menu; no grade badge | Debug completion summary reportedly exists | Does it expose run-resolution labels? | Produce narrative summary and keep help result internal |
| Recorder | Local observer across chapter/save/load | Debug recorder and evaluation summary reportedly exist | What schema/version and lifecycle assumptions are Lab-specific? | Attach observer at production boundaries; prevent replay duplicates |
| Content | Data-driven dummy route | Dummy cases and deduction data reportedly exist | Do they contain compatible dependencies and production consequences? | Add only missing sandbox orchestration data |
| Validation | Detect unreachable/invalid full route | Reference/proof/timeline validators reportedly exist | Which progression and debug-route checks are missing? | Extend validators only for proven gaps |
| Testing | Full production API flow and regression safety | Prototype and FAST/FULL tests reportedly exist | What helpers can drive real menu/chapter APIs? | Add one full-flow integration fixture plus focused persistence tests |

## 22. Proposed Milestone 1.16 implementation sequence

This is planning guidance, not authorization to implement during 1.15B.

1. **Repository audit**
   - Verify every “reported” capability in the handoff matrix.
   - Trace current menu → case/chapter → interaction → save path.
   - Trace A/B/C ownership, content lookup, presenter, recorder, and test fixtures.
   - Produce a gap list before choosing names or files.

2. **Freeze durable state and transition boundaries**
   - Define the chapter snapshot and active resolution-unit snapshot using existing conventions.
   - Define idempotent consequence identity and the common mechanic outcome capability.
   - Resolve run-result versus failure-count coupling.

3. **Bind dummy content to the chapter flow**
   - Reuse existing condition/effect/event vocabulary where sufficient.
   - Add the smallest orchestration data required for B1 → A → B2 → C.
   - Extend static validation for the full required route.

4. **Integrate mechanic logic without Lab ownership**
   - Start with B1, then A, B2, C timeline, and final claim.
   - Keep controller evaluation separate from orchestrator consequences.
   - Remove batch behavior from the production B path while preserving debug compatibility only if needed.

5. **Add atomic save/resume**
   - Serialize all durable unit and chapter state.
   - Test every formal-outcome boundary and restart isolation before UI polish.

6. **Build the production player route**
   - Wire normal menu, briefing, investigation, Case File, A/B/C, help, and Result screens.
   - Reuse presenters only where they satisfy the allow-list boundary.
   - Verify fixed footer, scroll, focus, keyboard/mouse, 1280×720, VI/EN.

7. **Attach recorder observation**
   - Observe committed production boundaries.
   - Handle resume without event replay.
   - Keep export failure non-fatal.

8. **Complete automated verification**
   - Add full-flow production API test.
   - Add focused save/load, duplicate, help/partner, locale, view-leak, and restart tests.
   - Run established FAST/FULL commands only during 1.16 implementation.

## 23. Decisions Claude Code must not make independently

Claude Code must not:

1. change the B → A → B → C role assignment;
2. restore batch submission as the production B contract;
3. count ordinary selection, drafting, movement, invalid input, or duplicate attempts as failures;
4. let failed commits alone escalate Independent/Guided/Assisted;
5. turn run result into a public score, rank, badge, ending, or reward modifier;
6. make partner resolution produce an inferior ending or block completion;
7. let A witness pressure hide mandatory evidence;
8. make optional content a hidden requirement;
9. hardcode the selected dummy case into reusable runtime components;
10. make any player screen or Deduction Lab the source of progression truth;
11. rebuild gameplay state from recorder events;
12. expose ids, ground truth, veracity, proof sets, raw constraints, or author metadata;
13. silently reject a documented alternate proof path to simplify implementation;
14. choose new save storage, migration framework, or event-version rules before auditing project conventions;
15. add a generic quest language, arbitrary visual scripting, plugin framework, content editor, mod system, network layer, multiplayer abstraction, or analytics backend;
16. create canon plot, final art/audio, production dialogue, or balance content;
17. tune the provisional `3 + 2` threshold based only on internal preference;
18. claim human validation from automated tests, telemetry, the project owner's playthrough, or AI review.

Any required deviation must be reported as a separate design issue with its consequence and evidence.

## 24. Deferred ideas and human evidence boundary

### Deferred to vertical slice

- final number and cadence of puzzles outside the sandbox flow;
- production clue-pool size, red-herring density, and exact counts;
- polished case-board/hypothesis visualization;
- public-facing detailed case history presentation;
- final witness-pressure writing and animation;
- final result-screen visual treatment;
- advanced accessibility options beyond the sandbox's basic keyboard/mouse, readable layout, and localization contract;
- content-scale performance work;
- additional optional B deductions;
- multi-evidence A refutations;
- free-form timeline or hypothesis authoring.

### Requires human playtest

- whether required B feels like deduction rather than a task list;
- whether the formal-commit boundary discourages brute force without suppressing experimentation;
- whether `3 + 2` offers help at the right time;
- whether A's recoverable pressure feels dramatic rather than punitive;
- whether C feels like synthesis rather than permutation;
- whether hints solve the stuck step without removing the “aha”;
- whether partner explanations preserve understanding;
- whether VI and EN produce equivalent player reasoning;
- whether the narrative Result screen feels earned after assisted resolution.

Milestone 1.16 proves technical continuity, ownership, persistence, safety, and testability. It does not prove player experience.
