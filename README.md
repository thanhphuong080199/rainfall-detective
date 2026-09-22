# Rainfall Detective — Technical Sandbox

A Godot 4 technical sandbox for a 2D narrative detective game. Everything in
here is **placeholder content**: dummy characters ("Character A"), dummy
locations ("Test Room"), and dummy evidence ("Old Key"), used only to prove
that the systems work and that real case content can later be authored as
data rather than code.

There is no story, no protagonist, and no Case 01 yet — and deliberately so.

- `docs/architecture.md` — what the systems are and how they talk to each other.
- `docs/content-guide.md` — how to add content without touching `scripts/`.
- `docs/event-system.md` — how world/narrative events (content reacting to
  game-state changes automatically, e.g. an NPC changing location) work.
- `docs/case-system.md` — how a Case is organized into Chapters, and how a
  future case would use the same structure.
- `docs/localization.md` — how bilingual text (Vietnamese default, English
  supported) works, and how to add a translated string.
- `docs/deduction-system.md` — the Milestone 1.9 deduction foundation (proof
  sets, evaluation, timeline constraints, validation) future deduction
  prototypes build on; `docs/deduction-prototype-cases.md` audits its three
  non-canon dummy mysteries and `docs/deduction-playtest-plan.md` plans their
  A/B/C playtest. `docs/deduction-lab.md` (Milestone 1.10) is a debug-only
  shell (F1 → Deduction Lab tab) for inspecting those three cases.
  `docs/prototype-a.md` (Milestone 1.11) is the first actual mechanic on top
  of it — a debug-only, non-canon "statement contradiction" cross-examination
  (find the lie, present the one piece of evidence that disproves it),
  launched from the Deduction Lab. `docs/prototype-b.md` (Milestone 1.12) is
  the second — "clue connection" (place the evidence that jointly establishes
  a real deduction into a fixed number of slots), also launched from the
  Deduction Lab. `docs/prototype-c.md` (Milestone 1.13) is the third,
  "timeline reconstruction": place events on a timeline, then use it to
  expose an impossible claim. `docs/resolution-policy.md` (Milestone 1.14)
  covers what all three share: limited formal commits, drafts that are never
  checked until committed, acknowledged assistance and partner resolution.
  There is no game over, and each run records whether it was solved
  Independently, Guided or Assisted.
- `docs/core-loop-authoring.md` — Milestone 1.17: how to author a new
  core-loop chapter as content only (template in
  `docs/templates/core_loop_chapter/`).
- `docs/core-loop-sandbox.md` — Milestone 1.16: the first production route.
  **New Game** plays a non-canon sandbox chapter end to end — briefing,
  investigation, clue connection (B), confrontation (A), a second B,
  timeline reconstruction and a final claim (C), then a narrative result —
  with save/Continue at every step and no debug tools involved.

## Requirements

Godot **4.x** (developed against 4.7). No plugins, no C#, no other
dependencies.

## Running the game

```bash
# From the project root, with the `godot` binary on your PATH:
godot --path .

# Or open project.godot in the Godot editor and press F5.
```

The main scene is `scenes/main/TitleScreen.tscn`.

## Controls

Desktop only (mouse + keyboard). No controller or touch support yet.

| Where | Input | Does |
|---|---|---|
| Anywhere | **Mouse click** | Activates whatever is under the cursor. Every action in the game is reachable by mouse alone. |
| Title screen | **New Game** / **Continue** / **Quit** / **VI / EN** | New Game starts the core-loop sandbox chapter (confirmed first if it would replace a save). Continue is greyed out unless a readable save exists, and always resumes the saved chapter. |
| Title screen (debug builds) | **Technical sandbox** buttons | Picks which non-canon sandbox chapter New Game starts (Milestone 1.17: *The Archive Badge* or *The Cold-Room Sample*); shows which run the save holds. Not present in release builds. |
| Briefing | **Begin investigating** / **Main menu** / **VI / EN** | Leaves the briefing for the investigation. |
| Investigation (sandbox chapter) | **Case File** button (top right) | Evidence you've found (read, pin), what you've established, the current objective, and the mechanic you can work on. |
| Investigation (sandbox chapter) | **Work on it: …** (bottom-left panel) | Opens the deduction/confrontation/timeline the chapter currently offers; while it's locked the panel says to keep investigating. |
| Mechanic screen | Buttons; the primary action and **Continue** sit in the fixed bottom bar | Your draft is kept when you leave (**Back to investigation** or **Esc**); only the bottom-bar action counts as an attempt. |
| Result screen | **Restart chapter** / **Main menu** / **Export evaluation log** | Restart is confirmed first. |
| Investigation view | Click a button in the right-hand list | Examine a point, open an NPC's menu, or open the destination list. `< Back` returns one level. |
| Investigation view | **Evidence** button (top right) | Opens the evidence inventory in browse mode. |
| Investigation view | **Menu** button (top right) | Save / Load / New Game / Resume / Quit to Title. |
| Dialogue | **Left click anywhere on the box**, or **Enter** / **Space** | Advances to the next line. While text is still typing out, the first press instantly completes the line instead of advancing. |
| Dialogue with choices | **Click a choice**, or **↑ / ↓** then **Enter** / **Space** | Picks that choice. The first choice is focused automatically. Advancing is disabled until you pick one. |
| Evidence inventory | Click an item | Selects it and shows its details on the right. |
| Evidence inventory (present mode) | **Present** button | Hands the selected item to the NPC you opened it from. |
| Evidence inventory / Menu | **Esc** | Closes the overlay. |
| Anywhere (debug builds only) | **F1** | Toggles the developer Case Debugger panel. **Esc** closes it. |

The Case Debugger is inert in release exports — see
`scripts/debug/debug_panel.gd` and `docs/case-debugger.md`. Its **Deduction
Lab** tab (Milestone 1.10, also debug-only) opens a mechanic-neutral viewer
for the three non-canon prototype deduction cases — see
`docs/deduction-lab.md`.

The game is in Vietnamese by default. Open **Menu** and use the **VI / EN**
buttons to switch languages — the choice is remembered between sessions.
See `docs/localization.md`.

## The sandbox progression flow

The placeholder content demonstrates one full loop:

1. Start in **Test Room** with **Character A**.
2. **Talk** to Character A (a choice disappears later, once the desk is examined).
3. **Examine** the desk → obtain **Old Key**, set `desk_examined`.
4. Examine the desk again → a different, "already searched" response.
5. **Present** the Old Key to Character A → special response, sets `hallway_unlocked`.
6. That unlocks a new **talk topic** and the **Test Hallway** destination.
7. **Move** to Test Hallway, examine the shelf → obtain **Brass Badge**.
8. Examine the mirror twice → different response the second time (no evidence involved).
9. Present unrelated evidence to Character B → generic fallback response.
10. Talk to Character B → unlocks a topic back on Character A.
11. Back in Test Room, ask Character A if there's somewhere else to look →
    an **event** triggers automatically: Character A leaves Test Room for
    Test Hallway, and (chained from that same event) the hallway mirror's
    examine response changes.
12. Move to Test Hallway → Character A is there instead of Test Room now,
    with a new topic only reachable because they moved.
13. **Save**, **New Game**, **Load** → all of the above is restored,
    including that the event doesn't fire a second time.

See `docs/event-system.md` for how step 11 works (and for the sandbox's
other two events — a chained content-change event and a `repeatable`-policy
one exercised only by the automated test / the F1 Case Debugger's manual
trigger, not by this playthrough).

## The Test Case (Case/Chapter architecture)

This same content is also reachable as a two-chapter **Test Case**
(`test_case`), proving the Case/Chapter organization layer (Milestone 1.6)
without any real story content — see `docs/case-system.md`. Since Milestone
1.16, "New Game" from the title screen boots the core-loop sandbox chapter
(the case marked `new_game_entry`), not `case_00_sandbox`; to play the demo
flow above or `test_case`,
press **F1** in a running debug build, open the **Case & Chapter** tab, type
`case_00_sandbox` or `test_case` into the case-id field, and press **Start Case**. Chapter 1 is steps 1-3 and
5-6 above plus step 11-12's event-driven move, followed by talking to
Character A in the hallway; Chapter 2 then activates a new talk topic on
Character B ("Ask if there's anything else") — completing it completes the
Test Case.

## Verification

See `docs/testing.md` for the full test organization, and
`.claude/skills/godot-development/scripts/verify.sh` for the recommended way
to run any of this (raw Godot exit codes don't reliably reflect script
errors — see that skill for why). Quick reference:

```bash
# Content validation only (fast; exits 1 on any validation error).
godot --headless --path . -s res://scenes/test/validate_content.gd

# Focused, independent tests — one system each (Conditions, Effects, Events,
# duplicate-execution regressions, save/load regressions, negative paths,
# dependency-reachability warnings): scenes/test/*_test.gd.

# The critical-path / integration fixture: the full demo flow plus the
# two-chapter Test Case, end to end.
godot --headless --path . -s res://scenes/test/smoke_test.gd

# The Milestone 1.16 core loop through its real screens, title to result.
godot --headless --path . -s res://scenes/test/core_loop_scene_test.gd

# Milestone 1.17: the author report of every core-loop chapter, including a
# legal-path simulation of each route variant (exits 1 on a problem).
godot --headless --path . -s res://scenes/test/core_loop_report.gd
```

The canonical FAST and FULL commands (and which scripts each includes) are in
`CLAUDE.md` and `docs/testing.md`.

Every test script is safe to run at any time; each that touches save/load
uses its own throwaway `user://` file and never touches the real
`user://save_game.json`. `.github/workflows/verify.yml` runs the full suite
on every push/PR.
