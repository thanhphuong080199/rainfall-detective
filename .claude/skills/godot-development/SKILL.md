---
name: godot-development
description: Rules and workflow for Godot 4.x + GDScript work in this repo (Rainfall Detective) — typed GDScript, composition/signals/Resources, _ready/_process/_physics_process lifecycle, scene ownership, when (not) to use autoloads, avoiding NodePath coupling, resource loading, naming conventions, and verifying changes with the headless Godot CLI. Use it for ANY task that creates or edits .gd, .tscn, .tres or project.godot files, adds a gameplay or UI feature, fixes a Godot bug, reviews or refactors GDScript, ports Godot 3 code, or runs/tests the project from the command line — even when the request doesn't say "Godot" (e.g. "add a settings option", "make the NPC walk", "why doesn't this button react to clicks").
---

# Godot development — Godot 4.x, GDScript

Engine: Godot **4.7** (`project.godot` → `config/features`), GDScript only, GL
Compatibility renderer, no plugins, `godot` binary on PATH (or `GODOT=`).

## Workflow

1. **Orient first.** Read `docs/architecture.md` — the systems, the autoload
   ownership table, "Key Architecture Decisions", "Known limitations" — and
   `docs/content-guide.md` for anything touching `data/`. Open a sibling
   script before writing a new one and match it.
2. **Documented decisions beat generic rules.** Where this skill's defaults
   and the docs disagree (narrative content is JSON read through `ContentDB`,
   not `.tres`; `scripts/ui/main.gd` is the only place overlays are wired
   together), follow the docs and mention the tension instead of "fixing" it.
3. **Write Godot 4 code** by the rules below.
4. **Verify with the Godot CLI** before calling it done (see *Verify*).
   Report the commands you ran and what they printed, and name anything you
   could not verify headlessly.
5. **Keep docs and tests true.** New autoload → the table in
   `docs/architecture.md`. New content field → `ContentValidator` +
   `docs/content-guide.md`. New behaviour → checks in
   `scenes/test/smoke_test.gd`.

## Rules

Short versions; the reference files have the details and examples.

### Godot 4, not Godot 3
Most GDScript on the web and in training data is Godot 3 and won't compile
here. Use `@export` / `@onready` / `@tool`, `await sig`,
`sig.connect(callable)` / `sig.emit()`, `CharacterBody2D` (`velocity` +
`move_and_slide()` with no args), `instantiate()`, `FileAccess` /
`DirAccess`, `JSON.stringify()` / `JSON.parse_string()`,
`Time.get_ticks_msec()`. Full table: `references/gdscript-style.md` §6. Not
sure an API exists in 4.7? Check (docs, or a two-line headless probe) rather
than guess.

### Typed GDScript
- Type every variable, parameter, return value (`-> void` included), signal
  parameter and collection (`Array[String]`, `Dictionary[String, int]`).
- `:=` only when the right side has a static type. From a Variant
  (`dict.get()`, JSON, untyped arrays) declare it:
  `var id: String = entry.get("id", "")` — `:=` there is a parse error.
- A value that really can be anything (raw JSON before validation) is typed
  `: Variant` explicitly and narrowed with `typeof()` / `is` — never left
  bare, even where older code nearby does that.
- Typed node refs: `@onready var title_label: Label = %TitleLabel`.
- `as` is not validation: objects give `null` on mismatch, built-ins silently
  convert (`"abc" as int` → `0`). Check external data with `typeof()` / `is`.
- Why: types move mistakes to script-load time, which the headless checks
  exercise; untyped mistakes only surface when that exact line runs.

### Composition, signals, Resources
- Build features from small nodes/scenes with one job — `@export`s in,
  signals out — and reuse them by instancing (`PlaceholderVisual.tscn` is the
  model). Keep inheritance shallow. Stateless helpers are `class_name` +
  `static func` (`UiUtil`, `ConditionEvaluator`).
- **Call down, signal up.** Parents call methods on children they own;
  children emit signals; siblings never reference each other — their common
  parent wires them (`scripts/ui/main.gd`).
- Signals: typed params, past tense for events (`evidence_added`),
  `*_requested` for asks (`present_requested`), `sig.emit()` /
  `sig.connect()`, connected in `_ready()`. Prefer named methods when a scene
  node listens to an autoload.
- Engine-side data and tuning → a custom `Resource`
  (`class_name X extends Resource` + `@export`s), injected via `@export`.
  Loaded Resources are shared instances: never mutate one as per-instance
  state. (Narrative content stays JSON — a documented decision.)

### Lifecycle
- `_init` (not in the tree; Inspector/scene values not applied yet) →
  `_enter_tree` (parent first) → `_ready` (once; children are ready before
  their parent) → `_process` / `_physics_process` → `_exit_tree`.
- `_ready`: grab references, connect signals, first render. Configure a new
  instance **before** `add_child()` — `_ready()` runs inside it.
- `_process(delta)`: visuals, UI, animation. `_physics_process(delta)` (fixed
  60 Hz): physics bodies (`velocity` + `move_and_slide()`, no extra
  `* delta`), raycasts, deterministic logic.
- Don't define per-frame callbacks you don't need; `set_process(false)` while
  idle; react to signals instead of polling state every frame.
- Overriding `_ready()` & co. replaces the base script's version — call
  `super()` if it must still run.
- Input: gameplay in `_unhandled_input` so UI gets first refusal; `_input`
  only to beat the GUI (this repo's Esc handling); held keys via
  `Input.get_vector()` in `_physics_process`. For Controls, mind
  `mouse_filter`: a full-rect overlay left at `STOP` silently eats every click
  beneath it.
- Changing physics state inside a physics callback → `set_deferred()` /
  `call_deferred()`.

Details: `references/lifecycle-and-resources.md`.

### Scene ownership
- A `.tscn` is a class. Its root script is the public API; its children are
  private. Outsiders call root methods, set its exports, connect its signals —
  they never reach into another scene's children
  (`$Player/Sprite2D/AnimationPlayer`).
- The creator (or parent) owns a node's lifetime. A node doesn't free its
  parent or siblings; it emits a signal.
- Scenes must instantiate on their own (the smoke test does exactly that):
  dependencies arrive via `@export`, a `setup()` call, or autoloads — never
  `get_parent()` assumptions.
- Rebuilding a runtime list: `UiUtil.clear_children(parent)`. Plain
  `queue_free()` leaves the old nodes in the tree, visible and clickable,
  until the end of the frame.

Details: `references/architecture.md` §1, §8.

### Autoloads
Add one only if the state or service (a) must survive scene changes, (b) is
needed by many unrelated scenes, and (c) must be unique — game state,
save/load, player settings, music across scenes. Otherwise: stateless →
`class_name` static helper; data → a Resource (or `ContentDB` JSON here);
owned by one scene → a node in that scene; "so I don't have to pass a
reference" → pass the reference.

When adding one: register it in `project.godot` `[autoload]`
(`Name="*res://…"`); no `class_name` equal to its name; in `_ready()` depend
only on autoloads listed above it; never reach into the current scene (emit
signals instead); add it to the table in `docs/architecture.md`.

Details: `references/architecture.md` §6.

### No NodePath coupling
In order of preference: `%UniqueName` for your own scene's nodes (typed
`@onready`) → `@export var target: SomeNodeType`, a `setup()` argument, or a
signal wired by the common parent for anything outside your scene → the
autoload by name for global services → groups for "every X".

Avoid `get_node("../..")`, `$"../X"`, `get_parent().get_parent()`,
`/root/Main/...`, a sub-scene's `%Name`, and `body.name == "Player"` (use a
group or `is`). Validate required references once in `_ready()` with
`push_error()` / `assert()`.

### Resource loading
- `preload()` (literal path, loads with the script) for small, always-used
  scenes; `load()` for dynamic paths — check for `null`;
  `ResourceLoader.load_threaded_request()` for large scenes behind a loading
  screen. Never load inside `_process`.
- `res://` is read-only once exported; write only to `user://`. Settings and
  save games are separate files (`ConfigFile` suits settings). Never load
  `.tres`/`.res` from `user://` — they can run embedded scripts.
- Commit `.uid` and `.import` files; move/rename in the editor, or move them
  along and re-run `--import`.
- Hand-editing `.tscn`: unique `ext_resource` ids, don't invent `uid=`
  values, then load the scene headlessly to prove it works.

Details: `references/lifecycle-and-resources.md` §5–7.

### Naming and layout
`snake_case` for files, folders, functions, variables, signals, input
actions, groups · `PascalCase` for `class_name`, node names and — in this
repo — scene files (`DialogueBox.tscn`) · `CONSTANT_CASE` for constants and
enum members · `_leading_underscore` for private members · `is_`/`has_`/`can_`
for booleans · handlers `_on_<emitter>_<signal>` · tabs, two blank lines
between functions · member order: signals → enums → consts → `@export` →
vars → `@onready` → built-in virtuals → public → private · `##` doc comments
that explain *why*, matching the surrounding density.

Details: `references/gdscript-style.md`.

## Verify with the Godot CLI

Two facts shape everything here (observed on 4.7.2):
- **Exit codes lie.** Runtime `SCRIPT ERROR`s, `push_error()`, a `-s` script
  that fails to parse, `--check-only` finding errors — all exit 0. A runtime
  error inside a test helper even lets the test print `ALL TESTS PASSED`.
  Read the output; any `SCRIPT ERROR` is a failure.
- **Godot can hang.** A `-s` script that errors before `quit()` never exits.
  A plain headless `--quit-after 60` boot of this repo ran 25 minutes on macOS
  before it was killed (its per-frame sleeps throttled), while the same boot
  with `--fixed-fps 60` finished in under a second. Every call gets a
  timeout; every run gets `--fixed-fps 60`.

Use the bundled wrapper, from the repo root:

```bash
.claude/skills/godot-development/scripts/verify.sh \
  --script res://scenes/test/validate_content.gd \
  --script res://scenes/test/smoke_test.gd
```

Each step runs under a timeout: `--import` → load every script/scene/resource
once (catches parse errors in files the main scene never loads) → boot the
main scene for 120 frames → each `--script`. It fails on script errors,
engine `ERROR:`s outside tests, non-zero exits and timeouts, and prints the
offending lines. Other flags (`--skip-import`, `--skip-load-all`,
`--skip-boot`, `--scene res://…`, `-v`) are in the script's header. After
editing only `data/*.json`:
`verify.sh --skip-import --skip-load-all --skip-boot --script res://scenes/test/validate_content.gd`.

Things to know:
- A full run takes about 5 s. Each step's timeout defaults to 120 s
  (`--timeout`), so give the shell command itself a longer limit (about 10
  minutes). Then a hang is reported by the wrapper instead of cutting off
  your tool call.
- Tests and probes use throwaway `user://` paths from the first draft on.
  `user://` is keyed by `config/name`, so every copy of this project — git
  worktrees and scratch copies included — shares the real game's folder,
  and a stray write lands in the player's real save or settings.
- The smoke test's verdict is `ALL TESTS PASSED` + exit 0. It prints
  intentional `ERROR:` / `WARNING:` lines from negative-path checks —
  expected.
- A plain boot only loads `TitleScreen.tscn`. `Main.tscn` and its overlays
  run only in the smoke test, so run it after any UI change.
- In a `-s` entry script, autoloads aren't resolvable by bare name: use
  `get_root().get_node("GameState")` after `await process_frame`. Don't
  statically call `class_name` scripts that use autoloads from there either;
  `load()` them at runtime.
- `--check-only` on scripts that use autoloads reports false
  `Identifier not found` — rely on load-all/boot/smoke instead.
- Fresh clone or git worktree: the import step builds `.godot/` (incl. the
  `class_name` cache); without it `-s` scripts can't see `class_name` types.
- Writing a new headless test, raw commands, reading Godot's output:
  `references/cli-verification.md`.

Headless runs can't prove layout, visuals, real mouse routing, or feel. Say
what is unverified and ask the human to check it in the running game
(`godot --path .`).

## Reference files

- `references/gdscript-style.md` — typing details, Variant pitfalls, naming
  table, script layout, Godot 3 → 4 cheat sheet. Read when writing or
  reviewing any `.gd`.
- `references/architecture.md` — scene ownership, signals, composition,
  Resources, the autoload decision guide, node references, instancing and
  freeing. Read when a feature spans several nodes/scenes or adds a scene or
  autoload.
- `references/lifecycle-and-resources.md` — callback order, process vs
  physics, input pipeline, deferred calls and `await`, loading, UIDs,
  exported-build paths, hand-editing `.tscn`.
- `references/cli-verification.md` — `verify.sh` in detail, raw CLI commands,
  a headless test template, how to read Godot's output.
