# Rainfall Detective — Milestone 0 Sandbox

A Godot 4 technical sandbox for a 2D narrative detective game. Everything in
here is **placeholder content**: dummy characters ("Character A"), dummy
locations ("Test Room"), and dummy evidence ("Old Key"), used only to prove
that the systems work and that real case content can later be authored as
data rather than code.

There is no story, no protagonist, and no Case 01 yet — and deliberately so.

- `docs/architecture.md` — what the systems are and how they talk to each other.
- `docs/content-guide.md` — how to add content without touching `scripts/`.

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
| Title screen | **New Game** / **Continue** / **Quit** | Continue is greyed out until a save file exists. |
| Investigation view | Click a button in the right-hand list | Examine a point, open an NPC's menu, or open the destination list. `< Back` returns one level. |
| Investigation view | **Evidence** button (top right) | Opens the evidence inventory in browse mode. |
| Investigation view | **Menu** button (top right) | Save / Load / New Game / Resume / Quit to Title. |
| Dialogue | **Left click anywhere on the box**, or **Enter** / **Space** | Advances to the next line. While text is still typing out, the first press instantly completes the line instead of advancing. |
| Dialogue with choices | **Click a choice**, or **↑ / ↓** then **Enter** / **Space** | Picks that choice. The first choice is focused automatically. Advancing is disabled until you pick one. |
| Evidence inventory | Click an item | Selects it and shows its details on the right. |
| Evidence inventory (present mode) | **Present** button | Hands the selected item to the NPC you opened it from. |
| Evidence inventory / Menu | **Esc** | Closes the overlay. |
| Anywhere (debug builds only) | **F1** | Toggles the developer debug panel. **Esc** closes it. |

The debug panel is inert in release exports — see `scripts/debug/debug_panel.gd`.

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
11. **Save**, **New Game**, **Load** → all of the above is restored.

## Verification

```bash
# Content validation only (fast; exits 1 on any validation error).
godot --headless --path . -s res://scenes/test/validate_content.gd

# Full end-to-end headless test of every system.
godot --headless --path . -s res://scenes/test/smoke_test.gd
```

Both are safe to run at any time; the smoke test uses its own throwaway save
file and never touches `user://save_game.json`.
