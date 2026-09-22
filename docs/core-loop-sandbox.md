# Core Loop Sandbox (Milestones 1.16–1.17)

The first **production-shaped** route through the game: Main Menu → New Game /
Continue → briefing → investigation → Prototype B → A → investigation → B →
C timeline → final claim → chapter completion → narrative Result → restart or
menu — played entirely through normal screens, without F1, the DebugPanel or
the Deduction Lab. It implements the handoff contract
`docs/Milestone 1.15B - Technical Core Loop Contract.md` (referred to below as
"1.15B"); where this document and that one disagree, 1.15B wins.

Everything the player meets is **non-canon placeholder content**. Milestone
1.16 shipped one sandbox chapter (`case_sbx_archive` / `sbx_chapter_01`,
around the dummy mystery `proto_x_archive_ledger`); Milestone 1.17 added a
second, structurally different one (`case_sby_lab` / `sby_chapter_01`, around
`proto_y_lab_sample`) to prove the runtime is reusable — see "Multiple
chapters (Milestone 1.17)". Nothing here is story. The point is the
machinery: the same runtime drives any chapter that declares a `core_loop`
section, and a new chapter is authored as content — `docs/core-loop-authoring.md`
is the recipe, `docs/templates/core_loop_chapter/` the template.

## Ownership at a glance

```
TitleScreen ──New Game / Continue──► Main.tscn (gameplay scene)
                                      │  Main.gd: chooses the visible screen only
                                      │
                                      ├─ ChapterRuntime  (RefCounted, owned by Main.gd — not an autoload)
                                      │    ├─ reads/writes GameState.chapter_run  (durable snapshot)
                                      │    ├─ one DeductionSession (shared by every A/B unit of the run)
                                      │    ├─ CoreLoopUnit per opened unit ──► PrototypeB/A/CController
                                      │    │        (real DeductionEvaluator / TimelineEvaluator grade)
                                      │    ├─ consequences ──► EffectRunner ──► GameState ──► EventManager ──► CaseManager
                                      │    ├─ checkpoints ──► SaveManager.save_game() (atomic)
                                      │    └─ ChapterRunRecorder (observes; never read back)
                                      │
                                      └─ screens (render from CoreLoopPresenter, call runtime commands)
                                           CoreLoopHud · CaseFile · MechanicScreen · BriefingScreen · ResultScreen
```

| Role (1.15B §6) | Implemented by |
|---|---|
| Chapter runtime / orchestrator | `ChapterRuntime` (`scripts/core_loop/chapter_runtime.gd`) |
| Investigation state | unchanged: `GameState` (evidence, flags, locations, seen interactions) + `Investigation` |
| Deduction session / snapshot | one `DeductionSession` per run, owned by `ChapterRuntime`, injected into each A/B controller |
| A / B / C controllers | the existing `PrototypeA/B/CController`, started with a production *context* (below) |
| Save service | `SaveManager` (v2 format, validate-then-apply, atomic writes) |
| Recorder | `ChapterRunRecorder` (a `DeductionLabRecorder` subclass) |
| Presenter / view model | `CoreLoopPresenter` over the existing `PrototypeA/B/CPresenter` allow-lists |
| Content database / validator | `ContentDB` / `ContentValidator` + `CoreLoopValidator` |
| Deduction Lab | untouched debug tool; never on the production route |

### Why no new autoload

The run must survive the TitleScreen → Main scene change and be saved — but
its *durable* truth already has a home that does both: `GameState` (an
autoload SaveManager persists). So `GameState` gained one opaque field,
`chapter_run`, and the logic lives in a `RefCounted` the gameplay scene owns.
When GameState is replaced wholesale (Continue, the game menu's Load/New
Game, the Case Debugger's reset) it emits `state_replaced`, and the runtime
rebuilds itself from the snapshot (it also re-checks a
`"<run_id>#<revision>"` key before every command, so it can never act on
stale state). This is the same stance `CaseManager` takes — logic in one
place, state in `GameState`.

### The production context on the prototype controllers

`PrototypeA/B/CController.start(case_def, recorder, context)` gained an
optional third argument. With `{}` (every debug caller) nothing changes. The
runtime passes:

| key | effect |
|---|---|
| `session` | use this shared `DeductionSession` instead of a fresh one (A, B) |
| `round_ids` | only these authored rounds — B always gets exactly **one**, which makes "Commit Theory" a **single-deduction** commit (1.15B: B is never a batch) |
| `evidence_pool` | only evidence the player has actually acquired (refreshed before every command via `set_evidence_pool()`) |
| `failures_escalate_run_result: false` | `ResolutionPolicy`'s help-only mode (below) |

Each controller also gained `to_snapshot()` / `restore_snapshot()` —
JSON-safe, record nothing, reject malformed data as a whole. The shared
session is persisted once by the runtime, never by a controller. Small shared
helpers live in `PrototypeContext`.

### Run help result vs. local budget

1.15B locks the run result to "the highest help level actually used";
failures are budget/telemetry, never an escalation. `ResolutionPolicy` in
debug prototypes escalates on failures (Milestone 1.14 semantics, unchanged).
`ResolutionPolicy.new(false)` turns that off: hints (levels 1–2 Guided, 3–4
Assisted), accepted assistance and partner resolution still raise it; failed
commits never do — not even the third one that makes assistance required. The
local 3 + 2 budget is untouched (`PROVISIONAL` in 1.15B). The runtime keeps
the chapter's `run_help_result` = the maximum over its units, persists it, and
records `run_help_result_changed`. **It is never shown to the player** — not
as a badge, score or label, not in mechanic status lines, not on the Result
screen (`CoreLoopPresenter` strips every run-result field and notice).

## Content: authoring a core-loop chapter

A chapter opts in with a `core_loop` section. Nothing in `scripts/` names the
sandbox — a new chapter is JSON only. Full example:
`data/chapters/case_sbx_archive/sbx_chapter_01.json`.

```json
"core_loop": {
  "format": 1,
  "canon": false,
  "deduction_case": "proto_x_archive_ledger",
  "briefing": {"title": "KEY", "text": "KEY"},
  "result":   {"title": "KEY", "text": "KEY"},
  "evidence_links": {"<data/evidence id>": "<deduction-case evidence id>", "...": "..."},
  "units": [
    {"id": "b1_badge", "mechanic": "clue_connection", "round": "round_1", "title": "KEY",
     "offer_condition": {"all": [{"has_evidence": "sbx_door_log"}, "..."]},
     "consequences": {"resolved": {"id": "sbx_b1_resolved", "summary": "KEY",
                                   "effects": [{"type": "set_flag", "flag": "sbx_confrontation_unlocked", "value": true}]}}},
    {"id": "a1_denial", "mechanic": "statement_contradiction", "rounds": ["round_1"], "...": "..."},
    {"id": "c1_timeline", "mechanic": "timeline_reconstruction", "...": "...",
     "consequences": {"timeline_accepted": {"...": "..."}, "resolved": {"...": "..."}}}
  ],
  "phases": [
    {"id": "briefing", "kind": "briefing", "objective": "KEY"},
    {"id": "investigation_1", "unit": "b1_badge", "completes_on": "resolved", "objective": "KEY"},
    "..."
  ]
}
```

- **`mechanic`** — a closed vocabulary: `clue_connection` (B, one
  `prototype_b` round), `statement_contradiction` (A, one or more
  `prototype_a` rounds), `timeline_reconstruction` (C, `prototype_c`). The
  deduction case's own prototype layer supplies everything else.
- **`evidence_links`** — investigation evidence (what dialogue/examine
  effects grant, what the Case File lists) mapped to the deduction case's
  evidence (what A/B grade). A mechanic's pool = its authored pool ∩ linked,
  acquired evidence.
- **`offer_condition`** — an ordinary condition (the same mini-language as
  topics/destinations). A unit is **offered** only while its phase is current
  *and* this holds. The validator requires it to guarantee a solvable pool.
- **`consequences`** — per outcome, an id, a narrative `summary` key, and an
  ordinary effect list run through `EffectRunner`. No new effect or condition
  vocabulary exists.
- **`phases`** — a linear route. A `briefing` phase may open it; every other
  phase names a unit and the outcome that completes it. The implicit final
  phase `completed` is entered when the last phase completes **and**
  `CaseManager` reports the chapter complete — i.e. the final consequence must
  set whatever the chapter's `completion_event` waits for. Chapter completion
  stays `CaseManager`'s.

Also new on a **case**: `"new_game_entry": true` (the title screen's New Game
starts it — at most one case may say so; otherwise `case_00_sandbox`) and
`metadata.canon` (sandbox content says `false`).

### Outcome → progression mapping

| Mechanic outcome (read from committed controller state) | Consequence | Phase effect |
|---|---|---|
| B: theory accepted (player or partner) | unit's `resolved` consequence | completes its phase |
| A: every configured round's required refutations refuted | `resolved` | completes its phase |
| A: optional innocent lie refuted | none — never a producer | none |
| C: timeline accepted | `timeline_accepted` | activates the final-claim phase |
| C: verdict + supporting fact accepted | `resolved` | final phase → chapter completion |

Each command runs in the 1.15B order: validate the unit is current and
offered → controller evaluates → newly reached outcomes' consequences are
applied **once** (the applied set is persisted and keyed by consequence id;
effects are idempotent anyway) → phases advance → **one** checkpoint → the UI
shows feedback → recorder events are committed. Showing or dismissing feedback
never applies progression.

## Save / load

`SaveManager.SAVE_VERSION` is **2**; version 1 (every earlier save) is the
oldest supported and migrates to "no active chapter run". Every load goes
through `inspect_save()` first — read, parse, migrate, then validate the whole
file, the chapter run included, with `ChapterRuntime.validate_snapshot()`
(the same parser a resume uses). Only a file that passes everything reaches
`GameState.load_from_dict()`; anything else never partially loads. Writes go
to `<save>.tmp` and are renamed over the real file. An unreadable save is
copied to `<save>.unreadable.json` before New Game replaces it.

`GameState.chapter_run` holds:

| Persisted | Where |
|---|---|
| run id, revision, chapter, deduction case, phase index, completed | top level |
| resolved claims, opened evidence, B hint levels, every commit attempt | `session` (`DeductionSession.to_dict()`) |
| per unit: drafts / selections / placements / claim draft, failure counts, failed-candidate signatures, A/C hint levels, assistance target, partner attribution, accepted timeline, pending feedback | `units.<id>` (controller snapshot + policy + feedback) |
| applied consequences with producer and attribution | `applied_consequences` |
| run help result | `run_help_result` |
| the mechanic that was open | `open_unit` |
| Case File read/pinned items | `case_file` |

Everything else in the run — evidence, flags, visited/current location, seen
topics/examines, chapter completion — was already in `GameState` and is
unchanged. Not persisted: scroll, focus, hover, the recorder log, elapsed play
time. The restore parser rejects every half-state 1.15B §13.3 forbids: a
resolved unit whose consequence was never applied (and the reverse), a phase
that disagrees with what was applied, a unit existing before its phase, a
completed run whose chapter isn't marked complete, a run help result lower than
the help its units used, a malformed controller snapshot.

**Checkpoints:** run creation; briefing acknowledgement; every formal commit,
hint, assistance and partner action; unit creation; mechanic close;
feedback dismissal; the end of any dialogue that granted evidence or marked an
interaction (never mid-dialogue — that would persist half its actions);
location change; quit to menu, window close and scene exit (`flush()`). Draft
edits update the in-memory snapshot immediately and reach disk at the next
of those.

## UI

`Main.tscn` gained, in draw/input order: `CoreLoopHud` (objective, the offered
mechanic, notices; mouse-transparent except its panel), `CaseFile`,
`MechanicScreen`, `BriefingScreen`, `ResultScreen`. `Main.gd` shows exactly the
screen the run's durable state calls for (briefing phase → briefing; completed
→ Result; a saved open mechanic → that mechanic; else investigation). The
investigation's top-bar Evidence button becomes "Case File" in a core-loop
chapter. `MechanicScreen` is **one** shell for all three mechanics — fixed
header, scrolling body (feedback first, then assistance, hints, the mechanic),
fixed footer with the formal commit, hint, assistance, partner and Continue —
the same layout that fixed Prototype A's Continue regression. Overlays are
opaque, so nothing underneath shows through or takes input.

Player-facing text is VI/EN through `tr()`. Views are allow-listed; ids travel
only as opaque handles resolved by the screen right before a command. Closing
a mechanic never loses anything, so it needs no confirmation; New Game over a
resumable save, the game menu's New Game, and Restart are confirmed.

The Result screen is **narrative only**: the chapter's result text and the
applied consequences' summaries in route order, with "(worked through with
your partner)" where that happened. No score, rank, time, attempt count or
Independent/Guided/Assisted label (1.15B locks this; see "Deviations").

## Recorder

`ChapterRunRecorder` keeps the recorder envelope and versions unchanged
(`schema_version` 1, `event_schema_version` 2) — the additions are new event
types and added payload keys, which the documented policy says never bump the
vocabulary version. Every event's payload gains `run_id`, `chapter_id` and,
inside a mechanic, `unit_id` / `mechanic`; events of one command carry the
checkpoint's revision as `transition` and are logged only **after** the
checkpoint. New types: `chapter_started/resumed/restarted/completed/abandoned`,
`phase_entered`, `briefing_acknowledged`, `location_visited`,
`interaction_completed`, `evidence_acquired`, `case_file_evidence_opened`,
`case_file_evidence_pinned`, `mechanic_opened/closed`, `unit_command_refused`,
`prototype_resumed`, `consequence_applied` (with `already_satisfied_effects`
as the "already unlocked" diagnostic), `run_help_result_changed`,
`checkpoint_saved/failed/restored`. The controllers' own events (formal
commits, duplicates, hints, assistance, partner) are recorded exactly as in
the debug prototypes.

One recording lives as long as the gameplay scene (restarts append to it); a
Continue starts a new segment linked by `run_id` with one `chapter_resumed`
and one `prototype_resumed` per unfinished unit — nothing is replayed.
`PrototypeEvaluationSummary` now opens a run at `prototype_resumed` too, tags
runs with `unit_id`/`mechanic`/`chapter_run_id`/`resumed`, and adds a
`chapter` block for core-loop exports. The Result screen's "Export evaluation
log" writes both to `user://core_loop_recordings/`; a failure is reported and
changes nothing. Gameplay never reads the log back.

## Validation

`CoreLoopValidator` (run by `ContentValidator`, so `validate_content.gd`
exits non-zero on any of it) reports as errors: unknown deduction case /
mechanic / round / unit / evidence link; duplicate unit, consequence or phase
ids; a consequence for an outcome the mechanic can't produce; a unit without a
`resolved` consequence; a briefing that isn't first; non-contiguous unit
phases; the final claim phase before the timeline phase; a unit never fully
resolved by a phase; an offer condition that can be true while no authored
accepted path is held (expanded over `all`/`any`); a required path whose
evidence is not linked or never granted; a unit offered only by its own or a
later consequence (a cycle); a completion event not produced by the final
consequence or produced earlier; `canon` missing or inconsistent with a
non-canon deduction case / case; a chapter no case (or two cases) lists; any
`res://`/`user://` path in the section; two `new_game_entry` cases. Offer
conditions and consequence effects also go through the existing condition/
effect/translation checks, and consequences count as producers in the
dependency analysis and the Case Debugger's "known producers".

Milestone 1.17 hardened it for more than one chapter (negative fixtures in
`core_loop_validation_test.gd`). Errors: evidence a unit needs that only its
own or a later consequence grants ("the acquisition producer arrives after
the unit requires it" — evidence an EARLIER consequence grants counts as
acquirable); a required offer-condition leaf nothing produces ("only a debug
override could", the phase is unreachable) or only ANOTHER chapter's
consequence produces (chapters never share run state); a completion event
shared with another chapter, or a requirement of it another chapter's
consequence produces; a consequence id reused by another chapter; two B units
asking the same deduction; `documented_paths` that are not authored accepted
proof sets, name unlinked evidence, cannot be acquired before the unit, or sit
on a non-B unit. Warnings: a linked evidence item nothing can grant (a dead
link); a consequence that ends a unit but unlocks nothing any condition reads.
Sandbox-selection metadata is checked by `ContentValidator` (see "Sandbox
selection"). Existence of a whole legal route is NOT a boot-time check — the
legal-path simulator proves it in tests and in the headless author report.

## What stays debug-only

The Deduction Lab, its three prototype screens, their case pickers, recorder
controls and completion statistics, the Case Debugger (F1) and its jump/reset
tools. The production route never instantiates or requires any of them; the
debug prototypes keep their own fresh sessions, batch B and failure-escalating
policy, and never touch the production run.

## Deferred to the vertical slice

Canon content; art, audio, animation, final dialogue and visual design;
difficulty, pacing and final hint/threshold tuning; multiple endings;
optional units and additional optional B deductions; multi-evidence A
refutations; free-form timeline/hypothesis authoring; a case board; a
player-facing detailed case history; public or automatic analytics;
accessibility beyond keyboard/mouse, readable layout and VI/EN; export-build
data packaging (`docs/architecture.md`, "Known limitations").

## Manual QA and known limitations

- The headless scene test drives the real screens and buttons (pressing only
  visible, enabled ones) and the dialogue box's own click handler, and scans
  every visible string for ids, keys and run-result labels — but it cannot see
  pixels. Visual QA was done by running the game windowed at 1280×720 and
  pushing real mouse events through the viewport; a human playthrough (feel,
  readability, keyboard-only navigation) is still required and is
  `REQUIRES HUMAN PLAYTEST` in 1.15B.
- Keyboard: every control is a focusable button with explicit initial focus
  per screen; full keyboard-only completion was not verified by a human.
- Checkpoint writes are synchronous and small; a draft edit made after the
  last checkpoint is lost only if the process dies without a flush.
- A unit's evidence pool only grows, so a placed clue can never disappear.
- One save slot (unchanged).
- The HUD "offered" state reveals *when* a unit's evidence is complete (the
  offer condition requires it, so the unit is always solvable when offered).
  Accepted trade-off for the sandbox; a vertical slice may prefer looser
  offers with a different solvability guarantee.

### Milestone 1.17 visual QA

Run windowed at 1280×720 with clicks delivered as mouse press/release events
through the viewport's GUI input (hit-testing, `mouse_filter`, scrolling a
control into view first) and rendered frames captured and inspected — scripted
input, **not** a human playthrough. Covered: the debug sandbox selector,
sandbox 2 in VI (primary route) and EN (alternate B proof set, alternate
timeline, optional innocent lie), sandbox 1 in EN (alternate B proof set,
alternate timeline), restart/replace confirmations, Continue on a completed
run. Three defects were found and fixed:

- **HUD drawn under the dialogue** (pre-existing since 1.16): the
  translucent dialogue panel covers the HUD's area, so both texts overlapped.
  The HUD now hides while a dialogue plays (`CoreLoopHud`); the
  sandbox scene test checks it.
- **Production B used the debug batch's wording** ("both connections hold"):
  see "Production B is not debug Prototype B".
- **The selected sandbox was hard to tell apart** (pressed style only): the
  selector now marks it ●/○.

Still unverified by a human: feel, pacing, keyboard-only play, readability
for real players.

## Deviations from the prompt (1.15B wins)

- **Result screen**: the implementation prompt suggested showing the
  Independent/Guided/Assisted outcome, hints used, failed attempts and time;
  1.15B §2/§14.2 lock a narrative summary with no score, rank or help badge.
  The narrative wins; the numbers stay in the save and the recording.
- **Title text**: the title screen still shows the existing
  "Milestone 0" title string — unrelated to this milestone, left unchanged.

## Multiple chapters (Milestone 1.17)

The second sandbox exists to break assumptions the first could hide. It runs
through the same `ChapterRuntime`, `CoreLoopUnit`, mechanic screen, Case File,
save schema, effects, recorder and Result screen — and was added as content
only (the one generic runtime change is below).

| Dimension | Sandbox 1 (`sbx_chapter_01`, X) | Sandbox 2 (`sby_chapter_01`, Y) |
|---|---|---|
| Locations | archive lobby / stacks wing / maintenance office | cold-store corridor / facilities workshop / lab front office |
| First B | credential misuse (round_1) | **staging** (round_2) — the reverse deduction order |
| B1 evidence | two examines + one NPC topic | two examines (one **examined-gated**) + one NPC topic gated on evidence |
| Confrontation | one testimony round | **two rounds**; round 2 exposes the **optional innocent lie** |
| A's evidence | an examine | an NPC topic that B1's consequence unlocks |
| A's consequence | unlocks a destination + an examine variant | makes an NPC **appear** (presence condition), unlocks an examine variant, **grants evidence** the player may already hold (the idempotent "already satisfied" path) |
| Second B | staging, one proof set | credential misuse; the cheapest route uses the case's **alternate** proof set, the primary one needs one more interaction |
| Dialogue | lines only | includes a **choice** that gates an optional hotspot |
| C | same mechanic; both sandboxes accept an alternate timeline (owner departure at the earliest slot), exercised by the simulator |

**What was content-only:** the whole second chapter — case, chapter, three
locations, three characters, ten evidence items, dialogue, events, strings —
validated clean and played to completion through the unchanged runtime
before any code changed.

**Generic gaps found and closed** (each with a generic test):

- *Sandbox selection* — `new_game_entry` can name only one case, so two
  sandboxes had no way in. Added content metadata and a debug-only selector
  (below) — a real generic capability, not sandbox-specific.
- *Case/chapter ownership of a save* — a save whose `chapter_run` belongs to
  a chapter its own `case_id` does not list was accepted as resumable
  (resume one sandbox, Restart into the other).
  `ChapterRuntime._parse_snapshot()` — the one parser both Continue and
  `SaveManager.inspect_save()` use — now rejects it
  (`core_loop_multi_chapter_test.gd`, "mismatched snapshots"). No save
  format change: the snapshot already names its chapter and deduction case.
- *Validator limitations* — consequence-granted evidence, unreachable /
  debug-only / cross-chapter offer dependencies, cross-chapter completion and
  ids, duplicate B targets, documented paths, and a warning channel (see
  "Validation").
- *Test-helper limitation* — `CoreLoopTestSupport` hard-codes sandbox 1, so
  the content-derived `CoreLoopRouteSimulator` now drives any chapter.

Nothing sandbox-specific entered the runtime: `core_loop_multi_chapter_test.gd`
scans the CODE of every script under `scripts/` for every id either sandbox
defines (cases, chapters, units, consequences, evidence, locations,
characters, dialogue, events, flags, interactions, deduction case, its
evidence/claims/timeline) — 0 hits. (One pre-1.17 doc comment in the debug
Lab presenter quotes `e_door_log` as an example; comments are excluded.)

Isolation: starting either sandbox after the other always creates a fresh
run and session (no evidence, flags, phase, hints, failures, help result or
consequences leak); units use only the active run's session; closing and
reopening a mechanic keeps the current run's draft and nothing survives into
a new run; one chapter's completion never satisfies the other's.

### Sandbox selection

A case may declare `"sandbox_selection": {"order": N}`. In **debug builds**
the title screen shows a "Technical sandbox" panel listing every such case
(`SaveManager.get_sandbox_entries()`, ordered, the release default first when
it is not itself selectable) as toggle buttons with the case's localized
name and description, plus which run the save holds. Picking one only
changes which case the ordinary New Game route starts — the confirmation over
a resumable save (now naming the sandbox), `SaveManager.new_game()`, the
gameplay scene and the first checkpoint are the release path. With one entry
or fewer the panel collapses. Continue never asks: it resumes whatever the
save holds. Release builds (`OS.is_debug_build()` false) never show the panel
and always start `new_game_entry`.

`ContentValidator` checks: a whole-number `order` ≥ 1, unique across cases;
the case is `metadata.canon: false` (canon content is never picked from a
debug selector); it has a `description`; its `starting_chapter` exists and is
a `canon: false` core-loop chapter; and once anything is selectable, exactly
one case is the release `new_game_entry`.

This is deliberately not a campaign or chapter-select system for the final
game.

### Production B is not debug Prototype B

Milestone 1.16 made production B a **single-deduction commit** (one authored
round per unit, the run's shared session, the acquired pool, help-only
policy); the debug Prototype B still drafts **every** round and commits them
as one atomic batch with failure-escalating policy. That difference is
intentional and now pinned by `core_loop_b_parity_test.gd`, over X/Y/Z and
EVERY complete clue set of every round (504 candidates):

- *identical*: the evaluator category recorded for the round's clue set, the
  accept/reject outcome, the counted failure; incomplete drafts and repeated
  failed sets refused free in both; exactly the three authored proof sets
  accepted;
- *different, on purpose*: production asks one question and resolves only
  its own deduction (a later B unit sharing the session is never resolved by
  an earlier one, in either order); the debug batch drafts all rounds, one
  invalid draft commits nothing, and failures still escalate its run result;
- *worded for what it is*: 1.17's visual QA found production B still showing
  the batch's feedback ("Theory confirmed — both connections hold", "at
  least one connection in this theory…"). `PrototypeBPresenter` now picks
  single-question wording (`UI_PROTOTYPE_B_FEEDBACK_*_SINGLE`) whenever the
  controller holds exactly one question; the debug batch's text is
  unchanged. Both sides are pinned by the parity test.

Do not read `docs/prototype-b.md`'s batch interaction model as the production
one.

### Legal-path simulation and the author report

`CoreLoopRouteSimulator` (`scenes/test/`, test/authoring tooling only) plays
a fresh run of any chapter with production logic only and records the route;
`core_loop_simulation_test.gd` runs it over every selectable sandbox (primary,
each documented alternate B path, an alternate timeline, the optional lie,
the already-satisfied consequence) plus a broken-chapter fixture.
`CoreLoopAuthorReport` (`scripts/debug/`) is the author-facing report shown in
the Case Debugger's Core Loop tab and printed, with simulation results, by
`scenes/test/core_loop_report.gd`. Neither ever reaches a player view. See
`docs/core-loop-authoring.md`, §9–10.

## Tests

`core_loop_mechanics_test.gd` (pure), `core_loop_validation_test.gd`,
`core_loop_runtime_test.gd`, `core_loop_save_test.gd` — FAST and FULL;
`core_loop_scene_test.gd` — FULL only. Milestone 1.17 adds
`core_loop_b_parity_test.gd` (pure), `core_loop_simulation_test.gd`,
`core_loop_multi_chapter_test.gd`, `core_loop_author_report_test.gd`,
`core_loop_template_test.gd` — FAST and FULL; `core_loop_sandbox_scene_test.gd`
and the `core_loop_report.gd` tool — FULL only. Shared driving helpers (and,
with the simulator's content-derived routes, the only place sandbox ids appear
outside `data/`) are in `core_loop_test_support.gd`. See `docs/testing.md`,
"Core loop tests".
