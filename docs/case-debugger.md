# Case Debugger (Milestone 1.8)

The **Case Debugger** is the F1 developer overlay (`scenes/debug/DebugPanel.tscn`
+ `scripts/debug/debug_panel.gd`). It exists so a developer can inspect and
manipulate narrative state without replaying an entire Case from the
beginning — answer "why hasn't this triggered/unlocked/completed yet," build
a specific test state (a chapter, plus some evidence, plus a flag) directly,
and see the consequences immediately.

Read `docs/architecture.md`, `docs/event-system.md`, and `docs/case-system.md`
first — this doc assumes you already know Conditions, Effects, Events, and
Case/Chapter progression, and adds nothing to any of them.

**This is a development tool, not a content editor or final gameplay.** It
does not add a condition/effect/evaluation mechanism of its own, does not
implement real Case content, and is not meant to survive into a shipped
build's normal play (it is dead weight there — see "Isolation" below).

## Opening it

Press **F1** in a running debug build. **Esc** closes it (the panel is the
topmost overlay, so it gets first refusal on Esc over `InvestigationView`).
It is gone entirely in an exported release build: `_ready()` checks
`OS.is_debug_build()` first and returns immediately (no signal connections,
no input handling) if it's false, which an export sets automatically — there
is nothing to remember to strip out by hand. The node stays in `Main.tscn`'s
tree either way; in a release build it's just a hidden `Control` that never
does anything. No production content or script depends on this overlay
existing.

## Architecture — reuse, not a parallel system

```
              Case Debugger
                    │
        ┌───────────┼────────────────┐
        ↓           ↓                ↓
   Inspectors    Actions       Dependency Info
        ↓           ↓                ↓
   GameState / ContentDB / Investigation / EventManager / CaseManager /
   ConditionEvaluator.explain_tree() / ContentValidator.find_*_producers()
                    ↓
               Game Runtime (one source of truth)
```

Every inspector reads through the exact same public APIs normal gameplay UI
uses — no back-door access to private fields, and no duplicate condition
evaluation, effect execution, or progression logic anywhere in
`debug_panel.gd`. Two small helpers were added specifically for this
milestone, both additive (neither changes any existing behavior other code
depends on):

- `ConditionEvaluator.explain_tree()` — a nested ALL/ANY/NOT breakdown for
  the Condition Inspector tab (see "Condition Inspector" below). This is
  **not** a replacement for `ConditionEvaluator.explain()`, which every
  other tab's "why locked" breakdown keeps using unchanged (it flattens a
  top-level `all` and groups an `any` into one line — the right shape for "list
  what's missing," but not for genuinely visualizing an `any`/`not`'s nested
  shape, which is what the Inspector tab exists for).
- `ContentValidator.find_flag_producers()` / `find_evidence_producers()` /
  `find_interaction_producers()` — "known producers" lookup for the
  Inspector tab (see "Known producers" below). Reuses the same three
  effect-carrying places (dialogue actions, event effects, chapter
  `entry_effects`) `ContentValidator`'s existing dependency-reachability
  WARNING already walks — this only adds *which* effect and *where*, on top
  of the existing *whether one exists at all* check.

## Layout

A header line (Case / Chapter / Location, always visible, live-refreshing)
above a `TabContainer`:

| Tab | Shows | Actions |
|---|---|---|
| **State** | Every flag ever set, as a checkbox (checked = true), filterable; visited locations; the raw `seen_interactions` list (topic/examine/interaction-complete/event/chapter/case markers), filterable | Toggle any flag's checkbox; or set/unset an arbitrary flag name (including one never set before) by typing it |
| **Evidence** | Every evidence id `ContentDB` knows about, as a checkbox (checked = held), with its translated name, filterable | Toggle any checkbox; or add/remove by typing an id |
| **Location** | Current location; this location's destinations (AVAILABLE/LOCKED with the missing condition breakdown); visited locations | Jump to any location id by typing it |
| **NPCs** | Every npc entry at the current location (PRESENT/ABSENT with the missing condition breakdown), and — for a present NPC — its topics (AVAILABLE/LOCKED, `(read)` tag), filterable by npc or topic id/label | None (see "Known limitations" — no generic "move NPC" action) |
| **Events** | Every event's status (TRIGGERED / CONDITIONS MET / NOT TRIGGERED) with a per-condition breakdown, filterable | Manually trigger (confirmation required); reset trigger marker |
| **Case & Chapter** | Current case/chapter status, the current chapter's completion breakdown, its `next_chapter`, completed chapters | Start any case by id; jump to any chapter; force-complete the current chapter (confirmation required); reset the case (confirmation required) |
| **Inspector** | The Condition Inspector (a nested tree for any condition in loaded content) and Known Producers lookup | — |
| **Log** | The last 50 debug actions this session took, most recent first | — |

Every list supports a plain case-insensitive substring filter where the tab
has enough entries for one to matter (State, Evidence, NPCs, Events) — no
query syntax, just a `LineEdit` filtering by substring
(`String.to_lower().contains(...)`).

**Live refresh.** Every list re-renders off the same `GameState`/
`EventManager`/`CaseManager`/`LocaleManager` signals `InvestigationView`
already listens to — no per-frame polling, and no need to close/reopen the
panel after an action (including one taken from *outside* the panel, like a
real dialogue action). The Inspector tab additionally remembers its last
lookup and re-runs it on every refresh, so an open Condition Inspector view
stays live too.

## Condition Inspector

Pick a source (an event's conditions, an NPC's topic condition, a
destination's condition, an NPC's presence condition, or a chapter's
completion conditions — via its `completion_event`), enter the relevant id(s),
and press **Inspect**. The tree is built entirely from
`ConditionEvaluator.explain_tree(condition)`, which mirrors the condition's
own shape one level at a time (unlike `explain()`, an `any`/`not` is **not**
flattened or summarized here — you see every branch):

```
ALL → FALSE
├─ has evidence "old_key" → TRUE
└─ ANY → FALSE
   ├─ flag "path_a" == true → FALSE
   └─ flag "path_b" == true → FALSE
```

Every `passed` value in the tree comes from `ConditionEvaluator.evaluate()`
itself — the Inspector never re-derives truth values, so it cannot drift from
what gameplay actually does.

## Known producers

Below the Condition Inspector, a second lookup: given a flag name, an
evidence id, or an `interaction_complete` id, list every Effect anywhere in
loaded content capable of producing it, and where it lives:

```
Known producers of flag "character_a_trusts_player" becoming true — 2 known producer(s)
  dialogue "character_a_family_topic" node "n4" → set character_a_trusts_player = true
  event "test_case_chapter_02_trust_event" → set character_a_trusts_player = true
```

**This is explicitly not a reachability guarantee** — the same stance
`ContentValidator`'s dependency-reachability WARNING already takes (see
`docs/testing.md`, "Progression dependency validation"). "Known producers: 2"
means two Effects in loaded content *could* set this; it does not mean
either of them is itself reachable from the current state, or that the
player will ever actually trigger one. Zero known producers is a strong
signal (the same content this milestone's `ContentValidator` check already
flags as a WARNING) that the required state may be permanently unreachable;
a non-zero count is a lead to follow by hand, not proof.

## Location jump vs. normal player progression

The Location tab's Jump bypasses the destination's own `condition` — it's a
teleport for reaching content deep in a case without unlocking every
destination along the way. It still calls `GameState.go_to_location()`, the
one production API real Move already uses, so `visited_locations`,
`location_changed`, and Event reevaluation (anything conditioned on
`visited_location` or that reacts to a location change) all still happen
exactly as they would from a real Move — jumping doesn't create a second,
inconsistent notion of "where the player has been." What it does **not** do
is pretend any *other* prerequisite for reaching that location was satisfied
(no evidence is granted, no flag is set, no dialogue plays) — only what
`go_to_location()` itself naturally does.

## Manual Event Trigger vs. Event Reset

**Manual Trigger** (Events tab) runs `EventManager.force_trigger()` — the
exact same firing pipeline (`GameState.mark_seen` + `EffectRunner.run` +
`event_triggered`) automatic triggering uses, bypassing both `conditions` and
`trigger_policy`. Requires confirmation (it runs real effects immediately,
which for a `"once"` event also means it can't fire again automatically).

**Reset Trigger** (`EventManager.debug_reset_trigger()`) clears the event's
"has triggered" marker and, for a `"repeatable"` event, its in-memory
false→true edge state — then requests a normal reevaluation pass (the same
thing any real state change would trigger). It does **not** undo any Effect
the event already ran: resetting `character_a_moves_to_hallway`'s trigger
marker does not move Character A back. This is deliberately *not* offered as
"undo" — only as "let this event evaluate again," useful for repeated
testing of the *triggering* behavior itself. No confirmation dialog: unlike
Manual Trigger, it never re-runs effects by itself.

## Chapter jump vs. real chapter completion

**Jump** (Case & Chapter tab) calls `CaseManager.jump_to_chapter()`: sets
`current_chapter` and runs the target chapter's `entry_effects`, exactly like
a real transition would — but bypasses whatever the *previous* chapter's
completion normally requires, and does **not** mark any skipped chapter
complete. `get_completed_chapters()` will not list a chapter you jumped past.

**Force Complete Current** forces the current chapter's `completion_event`
through `EventManager.force_trigger()` — the exact same pipeline a real
completion uses, so `CaseManager`'s own idempotency guard
(`_complete_chapter`'s `is_chapter_complete` check) still applies and the
Milestone 1.7 duplicate-execution protections stay valid: forcing it twice in
a row is a safe no-op the second time, not a double completion. Requires
confirmation.

## Reset Case

**Reset Case** calls `CaseManager.reset_case()` — restarts whatever case is
currently active from scratch (same call "New Game" for that case would use).
Because `GameState.start_new_game()` already clears `flags`,
`evidence_inventory`, `variables`, and `seen_interactions` in full, this is a
genuinely complete reset: case progress, chapter progress, event trigger
state, and all case-specific flags/evidence in one step. The debugger
re-renders immediately afterward (it's driven by the same signals a real
reset already emits). Requires confirmation.

## Debug action logging

Every action that mutates state prints a `[CaseDebugger] ...` line to the
console and appends to the Log tab (most recent first, capped at the last 50
this session) — e.g. `Set flag "character_a_trusts_player" = true`,
`Manually triggered event "test_case.chapter_02.trust_event"`, `Jumped to
location "test_hallway"`. Passive inspection (opening a tab, filtering,
inspecting a condition) never logs — only Section "Actions" below.

## Inspection vs. Normal-Pipeline Mutation vs. Debug Override

- **Inspection** — never changes state: every list, the Condition Inspector,
  and the Known Producers lookup.
- **Normal-pipeline mutation** — changes state through the exact same
  production API real gameplay would use, so it naturally triggers whatever
  that would (Events may fire, a Chapter may complete, the UI updates):
  toggling/setting a flag (`GameState.set_flag`), adding/removing evidence
  (`GameState.add_evidence`/`remove_evidence`), starting a case
  (`CaseManager.start_case`).
- **Debug override** — intentionally bypasses a normal prerequisite, and is
  labeled as such in its own button text and status message: location jump
  (skips the destination's `condition`), manual event trigger (skips
  `conditions` and `trigger_policy`), event trigger-reset (clears "has
  triggered" without undoing effects), chapter jump (skips the previous
  chapter's completion), force-complete chapter, and case reset.

## Known limitations

- **No "move NPC" action, and no Chapter reset.** Both were considered and
  deliberately not built — see the doc comments above `_render_npc_tab()`
  and `_on_reset_pressed()` in `debug_panel.gd`. There is no generic
  "where is this NPC" mechanism to set (presence is 100% derived, fresh,
  from each npc entry's own `condition` — moving a character is already just
  editing the flag that condition reads, which the State tab covers), and
  there is no structurally-enforced "this state belongs to chapter X"
  boundary to reset against (`docs/case-system.md`, "Event/content scope" —
  it's a flag-naming convention, not something `ContentDB`/`GameState`
  tracks). A misleading partial reset would be worse than none — Reset Case
  is the one reset boundary this architecture actually guarantees.
- **Known producers is existence-only**, never a reachability proof — see
  "Known producers" above.
- **No visual-regression tooling.** The panel is instantiated and its
  `open()`/`close()`/`visible` state asserted headlessly
  (`smoke_test.gd`), and its underlying data (Condition Inspector tree
  shape, producer lookup, `debug_reset_trigger`'s state transitions) is unit
  tested — but layout, tab-switching, and click routing are not verified
  headlessly (the same stance `docs/architecture.md`'s "Known limitations"
  already takes for every other overlay in this project). A human should
  press F1 in a running build after any change to this panel.

## Automated test coverage

- `scenes/test/conditions_test.gd` — `explain_tree()`'s nested shape (ALL/
  ANY/NOT, leaves, nesting) — see `_test_explain_tree()`.
- `scenes/test/dependency_analysis_test.gd` — `find_flag_producers()` /
  `find_evidence_producers()` / `find_interaction_producers()` against real
  sandbox content, plus the pure `_effect_produces_*` predicates in
  isolation — see `_test_find_producers()`.
- `scenes/test/events_test.gd` — `debug_reset_trigger()`'s state transitions
  (clears the marker without undoing effects; doesn't spuriously refire; a
  genuine subsequent transition still fires it again) — see
  `_test_debug_reset_trigger()`.
- `scenes/test/smoke_test.gd`'s `_test_scene_instantiation()` still
  instantiates `DebugPanel` and asserts `open()`/`close()`/`visible` — see
  `docs/testing.md`'s "Known testing limitations" for what that does and does
  not prove.
