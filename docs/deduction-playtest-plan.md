# Deduction Prototype Playtest Plan (A / B / C)

How the future comparison of the three deduction mechanics should be run so
that the result reflects the **mechanic**, not the mystery or the order it
was played in. Milestones 1.9 and 1.9.1 built the foundation; Milestone 1.10
added the debug-only, mechanic-neutral Deduction Lab
(`docs/deduction-lab.md`); Milestone 1.11 built the first actual mechanic,
Prototype A (`docs/prototype-a.md`) — see section 7 below for its own
facilitator script; Milestone 1.12 built the second, Prototype B
(`docs/prototype-b.md`) — see section 8 for its own facilitator script. Both
are smaller, narrower pilots than the full A/B/C rotation this document
otherwise describes. Prototype C, and the full six-tester A/B/C rotation
below, remain future work. See `docs/deduction-system.md` for the system and
`docs/deduction-prototype-cases.md` for the three cases.

| Prototype | Mechanic | Main evaluator calls |
|---|---|---|
| **A — Statement Contradiction** | pick a statement, present what contradicts it | `commit_attempt(..., "refutes", ...)` |
| **B — Claim / Clue Connection** | connect clues to a claim or hypothesis | `commit_attempt(..., "supports" / "explains" / "rules_out", ...)` |
| **C — Timeline Reconstruction** | place events on a timeline | `evaluate_timeline(...)`, then deductions |

All three must be able to finish any of the three cases, because every case
contains statement, connection and timeline content over the same proof
graph.

## 1. Avoiding content bias and order bias

- **Never let one tester play the same mystery through two or three
  mechanics.** The second run would measure memory of the solution, not
  the mechanic.
- **Never compare three unrelated mysteries.** Different logical
  difficulty would swamp any mechanic effect. That is why X, Y and Z share
  one validated proof graph (`structural_template: credential_misuse_v2`)
  and differ only in surface story.
- **Rotate both prototype order and case assignment.** Each tester plays
  three sessions: three different prototypes, on three different cases.
- **Don't tell testers the cases are structurally identical.** Ask in the
  final debrief whether they noticed.

### Assignment for the first six testers

All six prototype orders are used once. The case pairing follows three
Latin mappings, each used by two testers:
- M1: A→X, B→Y, C→Z
- M2: A→Y, B→Z, C→X
- M3: A→Z, B→X, C→Y

| Tester | Order | Session 1 | Session 2 | Session 3 | Genre familiarity |
|---|---|---|---|---|---|
| T1 | ABC | A · X | B · Y | C · Z | familiar with deduction games |
| T2 | CBA | C · Z | B · Y | A · X | unfamiliar |
| T3 | ACB | A · Y | C · X | B · Z | familiar |
| T4 | BCA | B · Z | C · X | A · Y | unfamiliar |
| T5 | BAC | B · X | A · Z | C · Y | familiar |
| T6 | CAB | C · Y | A · Z | B · X | unfamiliar |

The table was checked for balance:
- every prototype meets every case exactly twice;
- every prototype appears in every session position exactly twice;
- every case appears in every session position exactly twice;
- each mapping pair has one genre-familiar and one unfamiliar tester.

**Include both** players experienced with deduction games (Ace Attorney,
Return of the Obra Dinn, The Case of the Golden Idol, …) and players
unfamiliar with the genre. The mechanic that works for experts can fail
newcomers, and the reverse.

Scaling past six testers: repeat the table with fresh testers, keeping the
familiar/unfamiliar split per row.

### Residual bias to analyse, not ignore

- **Structure learning.** By session 3 a tester has solved the same
  abstract graph twice. Rotation balances this across mechanics but does
  not remove it. Report every metric by session position as well as by
  mechanic, and treat a strong position effect as a finding.
- **Surface difficulty.** Since 1.9.1 the three staging puzzles share one
  taught rule and one reasoning pattern, and the text lengths are measured.
  Residual differences are listed in `docs/deduction-prototype-cases.md`,
  "Known equivalence caveats". Report metrics by case too. Six testers cannot
  separate a case effect from noise, so read per-case numbers only as a
  sanity check.
- **Facilitator influence.** Use a written script and give no hints beyond
  the in-game hint ladder.

## 2. Session protocol (proposed)

1. Short neutral briefing: "You're investigating a small incident. Work it
   out at your own pace. Use hints if you want them." No mention of
   prototypes or of the other cases.
2. Play one case with one prototype. Think-aloud is optional but should be
   consistent across all testers.
3. After each session: a questionnaire (section 3), then the
   explanation-in-own-words interview **before** the next session starts.
4. A break between sessions.
5. Final debrief: ranking of the three experiences, "did any case feel
   familiar?", free comments.

## 3. Metrics to record

| Metric | Definition | Source | Available now? |
|---|---|---|---|
| **Completion without final-tier hint** | case solved AND no `hint_revealed` with level 4 for any target | `DeductionSession` signals | yes (signals exist; needs a recorder) |
| **Time to first meaningful hypothesis** | from session start to the first commit whose category is not `invalid_input`/`irrelevant_evidence` | commit timestamps | needs prototype UI clock |
| **Time spent stuck** | total time in gaps longer than a threshold (proposed: 90 s) with no new resolved claim, no new valid category and no new evidence opened | event timestamps | needs prototype UI clock |
| **Blind proof submissions** | commits that are `irrelevant_evidence`, or ≥ 3 consecutive failed commits on the same claim within 30 s | `get_attempts()` + timestamps | category log yes; timing needs UI |
| **Hints used** | count of `hint_revealed`, by level | signals | yes |
| **Can explain the final reasoning** | interview rubric: 0 = can't; 1 = names the culprit only; 2 = culprit + opportunity/access **or** staging, but can't say why nobody else could have done it; 3 = culprit + why only they could have used the credential (exclusive control, not just access) + what was staged and how that was shown, with evidence | facilitator | protocol only |
| **Opportunity trap** | the tester tries to prove the final conclusion with the opportunity-only deduction (`candidate_had_opportunity`) or with D1 instead of exclusive control, at least once before solving | attempt log + the selection's roles | category log yes; the selected items need the recorder (the session log stores claim, relation and category only) |
| **Perceived fairness** | "The solution followed from the evidence I had." (1–7) | questionnaire | protocol only |
| **Strength of the "aha" moment** | "I had a clear moment where it clicked." (1–7) + "When?" | questionnaire | protocol only |
| **Sense of agency** | "I solved this myself rather than the game walking me through it." (1–7) | questionnaire | protocol only |
| **Desire to continue** | "I'd like to play another case like this right now." (1–7) + a behavioural check: offered an optional extra case, do they take it? | questionnaire + observation | protocol only |

**The fastest mechanic is not automatically the best one.** Speed and
low hint use can mean the mechanic removed the reasoning: a timeline you
can brute-force, or a connection board that pattern-matches without
understanding. Weigh the explanation rubric, fairness, aha and agency at
least as heavily as time. A mechanic that is slower but produces rubric-3
explanations and higher fairness is the stronger candidate.

## 4. Instrumentation

### What exists (Milestone 1.9)

The project has no telemetry or analytics abstraction, so none was invented.
What exists is the local Godot signals on `DeductionSession`, emitted only
on real transitions and never from `load_dict()`:

| Event | Signal | Payload | Notes |
|---|---|---|---|
| evidence opened | `evidence_opened` | `evidence_id` | The UI must call `session.mark_evidence_opened()` when an item is inspected. First time only. |
| proof committed + result category | `proof_committed` | `claim_id`, `relation`, `category` | Every commit, valid or not. The session's attempt log keeps the same data in order. |
| claim resolved | `claim_resolved` | `claim_id`, `status` | |
| derived deduction unlocked | `deduction_unlocked` | `claim_id` | Only for `deduction` claims, only once. |
| hint requested | `hint_revealed` | `target_id`, `level` | New levels only. A repeat request for an exhausted ladder is not emitted (see deferred list). |
| case completed | `case_solved` | `case_id` | Once. |

### Deferred to the prototype milestone (proposed contract)

These need a prototype screen or a clock, which this milestone deliberately
does not build:

| Event | Payload | Why deferred |
|---|---|---|
| `hypothesis_created` | `claim_id`, `source` (`"player_pin"` / `"auto"`) | There is no "pin a hypothesis" interaction yet. Its meaning depends on the A/B/C UI. |
| `hypothesis_discarded` | `claim_id` | Same. Private hypotheses must stay free to revise, so this is logged, never penalised. |
| `timeline_submitted` | `category`, `violated_required_count`, `violated_optional_count` | `TimelineEvaluator` is pure; the screen that submits should emit it. |
| `hint_requested_exhausted` | `target_id` | Only interesting once a UI lets players ask repeatedly. |
| `session_started` / `session_ended` | `tester_id`, `prototype`, `case_id`, `session_position` | Belongs to the playtest harness. |

Every recorded event gets `t_ms` (milliseconds since `session_started`) added
by the recorder, not by the session.

**Recorder, when built:** a small local node that connects to these signals
and appends one JSON object per line to `user://playtest/<tester>_<session>.jsonl`.
No network, no SDK, and no personal data beyond an opaque tester id. It
must use a throwaway `user://` path in tests (see
`TestHelpers.isolate_save`'s rationale).

## 5. Changes after the Milestone 1.9.1 case audit

The cases were hardened (see `docs/deduction-prototype-cases.md`, section 0).
What that means for the sessions:

- **More to read.** Each case now has 11 evidence items instead of 9: a zone
  camera log (custody continuity) and a separate illustrated rule for the
  staging clue. Budget a few extra minutes per session, and don't compare
  session times with any 1.9-era pilot.
- **A deliberate trap.** Each case has a true opportunity-only deduction
  that never proves the conclusion. A tester who tries it and then finds
  exclusive control is reasoning correctly. Record it ("Opportunity trap"
  above), but don't count it as a blind submission unless it matches that
  definition anyway.
- **Rubric level 3 now requires exclusive control.** "They had the badge"
  is level 2.
- **No clue appears after a deduction.** Prototype C and B screens must
  show all 11 items from the start. A screen must not hide custody or
  continuity evidence until D1 is committed, because that would reintroduce
  the defect this milestone removed.
- **Pilot first.** Before tester T1, run one facilitator-only pilot per case
  to confirm that players read the zone rule ("only entrance", "nobody else
  enters") and the illustrated staging rule as intended. These are the two
  places a surface-wording problem could still create unequal difficulty.
  Fix wording only by changing all three cases in lockstep.

## 6. Decision rule (proposed)

After the first six testers, prefer the mechanic that:
1. has no fairness or explanation-rubric floor failures, i.e. no tester
   scores fairness ≤ 2 or rubric 0 on a solved case;
2. then has the highest combined fairness + explanation + agency;
3. then the strongest aha;
4. then the lowest blind-submission rate;
5. and only then the shortest time.

If two mechanics tie, run six more testers before deciding. Combining
mechanics (for example, C feeding deductions into B) is a legitimate
outcome, not a failure to choose.

## 7. Prototype A pilot (Milestone 1.11)

Prototype A (`docs/prototype-a.md`) is the first mechanic that actually
exists to test. This is a **standalone pilot of Prototype A alone** — it
does not substitute for the six-tester A/B/C rotation above, which needs all
three mechanics built first. Its target is qualitative: is the core loop
(read testimony → find the lie → present one piece of evidence → get a clear
explanation → "caught you") enjoyable, fair, and completable in roughly
5-10 minutes — not a statistically powered comparison.

### Facilitator script

1. Assign the tester one of X/Y/Z (rotate across testers so the same case
   isn't overused; a later A/B/C rotation will re-use this same rotation
   discipline once B and C exist — see "Assignment for the first six
   testers" above and the note at the end of this section).
2. Open the Deduction Lab (F1 → Deduction Lab tab), select the assigned
   case, and press **Start Recording** *before* pressing **Launch Prototype
   A** — this is what captures `prototype_started`/`round_started`
   (`docs/prototype-a.md`, "Recorder events"). Get the tester's consent to
   record first.
3. Do **not** explain which statement is the lie, what the required
   evidence is, or that the two cases share a proof graph with any other
   session. A short neutral framing is fine: "This witness gave testimony
   about an incident. Find the part that doesn't add up, and show the
   evidence that proves it."
4. Ask the tester to think aloud.
5. Intervene only if the tester is completely blocked (not merely stuck) —
   remind them the Hint button exists, but never state the answer yourself.
6. After completion (or after a reasonable time limit if they abandon —
   record which), ask:
   - Which contradiction felt most satisfying, and why?
   - Did any rejected attempt feel logically valid to you at the time?
   - Did you reason from the specific facts, or match keywords/vibes?
   - Was the feedback on a wrong attempt useful without giving away the
     answer?
   - Rate difficulty, 1-5.
   - Rate satisfaction, 1-5.
   - In your own words, explain why the evidence you presented contradicts
     the statement.

### What to record

Export the recording (`docs/prototype-a.md`'s schema) and, alongside it,
note:

- completion time (from the export's `prototype_completed` payload);
- submissions per required contradiction (filter `attempt_submitted` by
  `statement_id`);
- rejected evidence/statement combinations (every `attempt_submitted` whose
  category wasn't a valid refutation);
- whether the optional innocent lie was discovered (`outcome: "optional"` on
  any `contradiction_resolved`), and whether the tester correctly treated it
  as unrelated to the crime rather than as "the answer";
- hint levels used per required contradiction (`hint_revealed` count/level);
- abandonment (`prototype_abandoned`, if the session ends without
  `prototype_completed`);
- qualitative confusion moments, in the tester's own words;
- the interview rubric from section 3 above, adapted: can they explain WHY
  the presented evidence and the statement can't both be true, not just
  WHAT the answer was.

Treat the 5-10 minute target and any small number of pilot testers as
qualitative design evidence, not statistical proof — the same stance section
1's "Residual bias to analyse, not ignore" already takes for the full
rotation. When Prototypes B and C exist, assign different testers to
different case/mechanic pairings than this pilot used, to avoid the
"structure learning" bias section 1 already names (a tester who solved one
of X/Y/Z's proof graph once will recognize its shape faster the second
time, regardless of mechanic).

### Recommended gate before beginning Prototype B

Do not start Prototype B until this pilot (or the team's own judgment from
running it once or twice) confirms: the two required contradictions are
findable through reasoning (not brute-forcing every evidence item against
every statement), the innocent lie is genuinely felt as "valid but not what
I needed" rather than "wrong", and wrong-attempt feedback is reported as
useful rather than either too vague or too revealing. A pilot that instead
surfaces basic UX confusion (can't find the Hint button, doesn't notice
which statement is selected) should be fixed and re-piloted before
proceeding, since that confusion would otherwise contaminate whichever
mechanic comparison follows.

## 8. Prototype B pilot (Milestone 1.12)

Prototype B (`docs/prototype-b.md`) is the second mechanic that now exists to
test. Like section 7, this is a **standalone pilot of Prototype B alone** —
it does not substitute for the six-tester A/B/C rotation above, which still
needs Prototype C built first. Its target is qualitative: does combining
clues feel like reasoning rather than inventory matching, and is the core
loop (read the question → review clues → place them into slots → submit →
get logical feedback → unlock the deduction) enjoyable, fair, and
completable in roughly 5–10 minutes — not a statistically powered
comparison.

**Reducing answer-memory transfer.** A tester who already played Prototype A
(section 7) solved one of X/Y/Z's proof graph once already and will
recognize its shape faster the second time, regardless of mechanic —
exactly the "structure learning" bias section 1 names. So: **assign a
tester who has already played Prototype A a DIFFERENT dummy case for
Prototype B than the one they used for A** (rotate X/Y/Z across the pool of
testers the same way section 1's Latin-mapping table does for the full
rotation). A tester who has not yet played anything may take any case.

### Facilitator script

1. Assign the tester one of X/Y/Z, per the rule above. If this tester
   already ran the Prototype A pilot, confirm from your own notes which
   case they used there and pick a different one here.
2. Open the Deduction Lab (F1 → Deduction Lab tab), select the assigned
   case, and press **Start Recording** *before* pressing **Launch Prototype
   B** — this is what captures `prototype_started`/`round_started`
   (`docs/prototype-b.md`, "Recorder events"). Get the tester's consent to
   record first.
3. Do **not** explain which clues are needed, how many rounds there are
   beyond what the UI already shows, or that the cases share a proof graph
   with any other session. A short neutral framing is fine: "You're looking
   into an incident. Each question needs a few pieces of evidence placed
   together to answer it — read what's here, and connect the clues that
   answer the question."
4. Ask the tester to think aloud.
5. Intervene only if the tester is completely blocked (not merely stuck) —
   remind them the Hint button exists, but never state which clue is
   missing yourself.
6. After completion (or after a reasonable time limit if they abandon —
   record which), ask:
   - Why do the selected clues prove the deduction only when combined?
   - Which clue felt indispensable?
   - Did the visible number of slots help, or did it give away too much?
   - Did you reason about the facts, or try combinations?
   - Did any rejected combination seem logically valid to you at the time?
   - Was failed-attempt feedback useful without giving away the answer?
   - Rate difficulty, 1–5.
   - Rate satisfaction, 1–5.
   - Which felt better: catching a contradiction in Prototype A, or
     constructing a deduction in Prototype B — and why? (Skip this question
     for a tester who has not played Prototype A.)

### What to record

Export the recording (`docs/prototype-b.md`'s schema, `"prototype":
"clue_connection"`) and, alongside it, note:

- completion time (from the export's `prototype_completed` payload);
- connection attempts per round (filter `connection_submitted` by `round`);
- rejected clue combinations (every `connection_submitted` whose category
  wasn't `valid_support`);
- clue-selection churn (`clue_selected`/`clue_removed` counts and, if
  selection-order analysis is useful, their relative ordering in the raw
  event stream — the submitted set itself is normalized, but these two
  event types are not);
- hint levels used per round (`hint_revealed` count/level);
- abandonment (`prototype_abandoned`, if the session ends without
  `prototype_completed`);
- qualitative confusion moments, in the tester's own words;
- whether the tester can restate the deduction in their own words after
  solving it — the interview rubric from section 3 above, adapted: can they
  explain WHY the combined clues establish the conclusion, not just WHAT the
  conclusion was.

Treat the 5–10 minute target and any small number of pilot testers as
qualitative design evidence, not statistical proof — the same stance section
1's "Residual bias to analyse, not ignore" already takes for the full
rotation, and the same stance section 7 already takes for the Prototype A
pilot.

### Recommended gate before beginning Prototype C

Do not start Prototype C until this pilot (or the team's own judgment from
running it once or twice) confirms: both rounds are solvable through
reasoning about which facts jointly establish the deduction (not
"try-every-item-until-something-lights-up," which the fixed slot count and
anti-brute-force validation are specifically meant to prevent), the visible
slot count is reported as helpful framing rather than as a spoiler, and
wrong-connection feedback is reported as useful rather than either too vague
or too revealing. A pilot that instead surfaces basic UX confusion (can't
find the Connect button, doesn't notice a slot is still empty) should be
fixed and re-piloted before proceeding, for the same contamination reason
section 7's own gate gives.
