# Authoring a core-loop chapter (Milestone 1.17)

How to add a new playable chapter to the production core loop — briefing →
investigation → B → A → investigation → B → C timeline → final claim →
result — **as content only**. Read `docs/core-loop-sandbox.md` for how the
runtime works and `docs/Milestone 1.15B - Technical Core Loop Contract.md`
for the contract it implements; this guide is the recipe.

Milestone 1.17 proved the recipe on three chapters that share no code path:

| Chapter | Deduction case | Shape |
|---|---|---|
| `sbx_chapter_01` (sandbox 1) | `proto_x_archive_ledger` | B1 credential misuse → A (one round) → B2 staging → C |
| `sby_chapter_01` (sandbox 2) | `proto_y_lab_sample` | B1 **staging** → A (**two rounds**, optional innocent lie) → B2 credential misuse (cheapest route = the case's **alternate** proof set) → C |
| the template (below) | `proto_z_customs_parcel` | B1 credential misuse → A (one round) → B2 staging → C |

None of them needed a script change beyond the generic items listed in
"What needs code" at the end.

## 0. Start from the template

`docs/templates/core_loop_chapter/` is a **complete, valid third chapter**
(case, chapter, two locations, three characters, nine evidence items,
dialogue, the completion event and `strings.csv`) over the one dummy case
neither sandbox uses. It lives outside `data/` — and under a `.gdignore`, so
Godot never imports its `strings.csv` — so ContentDB never loads it as real
content. `core_loop_template_test.gd` injects it into the running ContentDB
and proves it validates clean and plays to completion through the unchanged
runtime, so the template cannot silently rot. Its `README.md` says exactly
what to copy and rename.

## 1. Create the chapter

A core-loop chapter is an ordinary chapter (`data/chapters/<case_id>/…json`)
with a `core_loop` section, listed by exactly one case:

- **The case** (`data/cases/…json`): `start_location`, `starting_chapter`,
  `chapters`, `initial_flags` (every flag your consequences set, `false`),
  `display_name` + `description`, and for sandbox content
  `"metadata": {"canon": false, …}`.
- **Sandbox selection** (debug builds): add `"sandbox_selection": {"order":
  N}` (a unique whole number ≥ 1). The case must be non-canon, have a
  `description` (the selector shows it) and start a `canon: false` core-loop
  chapter. `"new_game_entry": true` stays on exactly one case — the release
  default. Release builds never show the selector.
- **The chapter**: `display_name`, `completion_event`, `entry_effects` (may
  be `[]`) and the `core_loop` section:

```json
"core_loop": {
  "format": 1,
  "canon": false,
  "deduction_case": "<data/deductions case id>",
  "briefing": {"title": "CL_<CH>_BRIEFING_TITLE", "text": "CL_<CH>_BRIEFING_TEXT"},
  "result":   {"title": "CL_<CH>_RESULT_TITLE",   "text": "CL_<CH>_RESULT_TEXT"},
  "evidence_links": {"<inventory evidence id>": "<deduction evidence id>"},
  "units": [ … ],
  "phases": [ … ]
}
```

## 2. Connect investigation evidence to deduction evidence

Two evidence worlds meet here. **Inventory evidence** (`data/evidence/`) is
what dialogue/examine effects grant and the Case File lists; **deduction
evidence** is what the mechanics grade (`data/deductions/…` `evidence`).
`evidence_links` maps one to the other, one-to-one. A mechanic's pool is its
prototype layer's `evidence_pool` ∩ linked ∩ acquired — the player only ever
sees evidence they found.

- Link everything the chapter's answers need, plus any distractors you want
  offered (sandbox 2 links a red herring and the optional lie's evidence).
- Reuse the deduction case's text for the name/detail
  (`DED_PROTO_Y_E_OPEN_HATCH_NAME` / `_TEXT`) and author a short
  `EVID_<CH>_…_SHORT` of your own.
- Every linked item needs an acquisition producer (an `add_evidence` in a
  dialogue node/choice, an event, or an EARLIER phase's consequence) —
  otherwise the validator warns "a dead link".

## 3. Choose the B / A / C rounds

| `mechanic` | Takes | Resolved when |
|---|---|---|
| `clue_connection` (B) | `"round": "<prototype_b round>"` — exactly ONE | the round's target deduction is accepted |
| `statement_contradiction` (A) | `"rounds": ["<prototype_a round>", …]` — one or more, played in authored order | every configured round's `required_refutations` are refuted |
| `timeline_reconstruction` (C) | nothing | `timeline_accepted`, then `resolved` (the final claim) |

- **B is a single-deduction commit in production.** Two B units of one
  chapter may not ask the same deduction (validator error). Any order is
  fine — sandbox 2 asks staging before credential misuse.
- **A may span rounds.** Optional refutations (`optional_refutations`) are
  offered but never required and never produce progression; once the last
  required refutation lands the unit resolves and the phase moves on, so an
  optional lie can only be exposed before that.
- **C** reuses the case's `prototype_c` layer. Any placement satisfying
  every required constraint is accepted — the simulator exercises the
  authored solution and an alternate.
- **`documented_paths`** (B only, optional but recommended): the clue sets
  (inventory ids) you intend to work, first = the route the simulator plays
  by default. Each must be an authored accepted proof set of the round and
  acquirable before the unit — or validation fails ("documents an answer the
  evaluator rejects" / "is not reachable").

## 4. Offer conditions

`offer_condition` is an ordinary condition (the same mini-language as
topics). A unit is **offered** only while its phase is current *and* its
condition holds; the HUD and Case File then show it.

- It must **guarantee a solvable pool**: every evidence alternative the
  condition allows (expanded over `all`/`any`) must cover an accepted path.
  Sandbox 2's B2 uses `any` of the two alibi items for its two proof sets.
- Every required leaf (top level or in `all`) needs a producer **before the
  unit's phase**: normal play, or an earlier consequence.
- Gate the *interaction* rather than the unit when you can: sandbox 2's
  confrontation needs Priya pressed (a topic that the B1 consequence
  unlocks) plus the laundry sheet (a topic the same consequence unlocks).

## 5. Consequences

Per outcome, `{"id", "summary", "effects"}` — an ordinary `EffectRunner`
effect list (`set_flag`, `add_evidence`, `remove_evidence`,
`mark_interaction_complete`). No new vocabulary.

- Ids are unique across **every** core-loop chapter (they key saves,
  recordings and the Case Debugger).
- A consequence that ends a unit should unlock something the next phase
  reads — a topic, a destination, an NPC's presence, an examine variant, an
  offer condition (warning otherwise). C's `timeline_accepted` may have
  `"effects": []` (the template does): its only job is the phase change.
- Effects must be idempotent; one that is already satisfied (sandbox 2's A
  consequence files a timetable the player may already hold) is a no-op,
  recorded as `already_satisfied_effects` — never a duplicate reward.
- `summary` is the narrative line the Case File and Result screen show.

## 6. Avoid circular unlocks

The validator rejects, as errors: a unit offered only by its own or a later
phase's consequence (a cycle); a requirement nothing produces ("only a debug
override could"); a requirement only another chapter produces (chapters
never share run state — New Game starts a fresh GameState); and evidence a
unit needs that only arrives from its own or a later consequence. Keep the
dependency arrow pointing backwards: each phase's consequence feeds the NEXT
phase, and normal-play interactions feed their own phase.

## 7. Chapter completion

Completion stays `CaseManager`'s: the chapter's `completion_event` (an
ordinary `"once"` event) must require what the **final** consequence
produces, and nothing earlier may produce it. The event's own effects should
be a marker (`mark_interaction_complete`), not progression. It may not be
shared with, or satisfiable by, another chapter.

## 8. Validate

```bash
.claude/skills/godot-development/scripts/verify.sh --skip-import --skip-load-all --skip-boot \
  --script res://scenes/test/validate_content.gd
```

Every `core_loop` rule is a `ContentValidator` error (non-zero exit) or
warning; missing VI/EN keys are errors. Add your strings to
`localization/strings.csv` (CRLF, quoted, `en` + `vi`).

## 9. Legal-path simulation

```bash
godot --headless --path . -s res://scenes/test/core_loop_report.gd -- <chapter_id>
```

`CoreLoopRouteSimulator` (`scenes/test/core_loop_route_simulator.gd`) plays
fresh runs with the real runtime: evidence only through represented
interactions (navigation, examine, talk, dialogue choices) or applied
consequences, answers only from authored proof sets / documented paths /
accepted timelines, commands only through `ChapterRuntime`. The report runs
the primary route, every documented alternate B path, an alternate timeline
and (when present) the optional lies. It is **not** an AI player, a solver,
or a playtest — it proves one legal route exists per variant and nothing
about feel or difficulty. `core_loop_simulation_test.gd` runs it for every
selectable sandbox in FAST/FULL.

## 10. Inspect it in the Case Debugger

F1 → **Core Loop** tab (debug builds): the active chapter (or any picked
one), tagged `[ERROR]`/`[WARN]` (validation), `[info]` (route, units, offer
conditions, accepted proof sets and whether each is documented and
acquirable, A refutations required/optional, linked evidence and its
producers, consequences and effects, the completion producer) and `[NOW]`
(current phase, offered/locked with what is missing, applied consequences).
The simulation is headless-only — it would replace the run you are
inspecting.

## 11. What needs code, and what stays content

| Want | Content or code? |
|---|---|
| A new chapter, locations, NPCs, evidence, dialogue, route order, offer conditions, consequences, alternate paths, optional interactions, selector entry | **Content** |
| A different deduction case | Content (a new `data/deductions` case — its own validator rules apply) |
| A new condition leaf or effect type | Code (shared vocabulary — `docs/content-guide.md`) |
| A new mechanic, a new outcome kind, optional units, branching phases | Code (runtime semantics) |
| Multiple endings, campaign/chapter select for players | Code + design (deferred) |

## Deliberate limits

- The required route is **linear**: phases complete in order; there are no
  optional or branching units.
- The Technical Sandbox selector is a **debug-build** tool, not a campaign or
  chapter-select screen for the final game.
- There is **no generic quest scripting**: conditions and effects stay the
  fixed vocabulary.
- Nothing here needs, or implies, **canon** story content.
- Automated routes and headless checks are **not human playtests**: they
  prove technical continuity, not fun, fairness or pacing.

## Save / resume expectations

Nothing to author. A chapter's run is saved by the runtime at every durable
checkpoint (`docs/core-loop-sandbox.md`, "Save / load"); Continue resumes the
saved chapter (never asks which sandbox); a save belongs to one case,
chapter and deduction case and is rejected whole if they disagree. Changing
a chapter's units, rounds or consequence ids between a save and a load makes
that save's chapter run invalid (it is rejected, never half-loaded) — bump
nothing, but expect sandbox saves to reset while you author.
