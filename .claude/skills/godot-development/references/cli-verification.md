# Verifying a Godot project from the command line

Read this when running, testing or linting the project headlessly, when
`verify.sh` reports something you don't understand, or when writing a new
headless test.

1. Ground rules
2. `verify.sh`
3. Raw commands
4. Writing a headless test script
5. Reading Godot's output
6. This repo
7. What the CLI can't verify

---

## 1. Ground rules

All observed on Godot 4.7.2 (macOS), in this repo or a scratch project.

- **Exit codes don't report script errors.** A `-s` script that fails to
  parse exits 0. Runtime `SCRIPT ERROR`s and `push_error()` leave it at 0.
  `--check-only` exits 0 even when it prints parse errors. Only an explicit
  `quit(1)` from a test script gives you a reliable non-zero. Always read the
  output.
- **A runtime error aborts only the function it happens in.** The caller
  carries on with a default return value. So a test whose helper crashes can
  still reach `_finish()` and print `ALL TESTS PASSED` with exit 0 — treat any
  `SCRIPT ERROR` line as a failure regardless of the verdict line.
- **Godot can hang.** If the error happens directly in `_initialize()` before
  `quit()`, the process sits in an empty main loop forever. Separately, a
  plain `godot --headless --path . --quit-after 60` of this repo ran for 25
  minutes (killed; its per-frame sleeps were being throttled) while the same
  command with `--fixed-fps 60` finished in under a second. So: every call
  gets a timeout, and every run gets `--fixed-fps 60`, which drops the
  per-frame sleep and makes `--quit-after N` a deterministic N frames.
- Always pass `--headless` (no window, dummy audio) and `--path <project>`.
- macOS has no `timeout(1)`. Use `verify.sh`, `gtimeout` (coreutils) if
  installed, or `perl -e 'alarm shift; exec @ARGV' 120 godot …` (exit 142
  means it was killed).

## 2. `verify.sh`

```bash
.claude/skills/godot-development/scripts/verify.sh [--script res://…]… [--scene res://…]… \
    [--frames N] [--timeout SEC] [--skip-import] [--skip-load-all] [--skip-boot] [-v]
```

| Step | Command it runs | Catches | Fails on |
|---|---|---|---|
| import | `--import` | broken resource references, missing imports; builds `.godot/` and the `class_name` cache on a fresh clone | any `SCRIPT ERROR` / `ERROR:` |
| load-all | `-s scripts/load_all.gd` | parse errors and broken `ext_resource`s in **every** `.gd` / `.tscn` / `.tres`, including ones the main scene never loads (skips hidden folders and `addons/`) | any `SCRIPT ERROR` / `ERROR:`, exit ≠ 0 |
| boot | `--quit-after 120` (or `--scene X`) | errors in `_ready()` / first frames of the main scene and autoloads | any `SCRIPT ERROR` / `ERROR:`, exit ≠ 0 |
| test | `-s <script>` per `--script` | whatever the test asserts | `SCRIPT ERROR`, exit ≠ 0 (its `ERROR:` lines are listed, not failed) |

Every step runs with `--headless --fixed-fps 60` under a timeout (default
120 s, exit 124 = killed). Steps here take 0–2 s, so a timeout means a hang,
not slowness. The summary line is `verify: N/M steps passed`; the script
exits 0 only if all passed. Failing steps print each error with its
`at: file:line`; `-v` prints everything.

Give the shell call that runs `verify.sh` a longer timeout than the worst
case (steps × `--timeout`, about 10 minutes). Then a hang is reported by the
wrapper instead of cutting off your own tool call.

## 3. Raw commands

| Purpose | Command | Notes |
|---|---|---|
| Engine version | `godot --version` | Compare with `config/features` in `project.godot` |
| Import / rebuild `.godot/` | `godot --headless --path . --import` | Editor-only flag. Needed on a fresh clone or worktree before `-s` scripts can see `class_name` types |
| Boot main scene | `godot --headless --path . --quit-after 120 --fixed-fps 60` | Only loads what the main scene loads |
| Boot another scene | `godot --headless --path . --scene res://scenes/x/X.tscn --quit-after 120 --fixed-fps 60` | Accepts `uid://…` too |
| Run a headless test | `godot --headless --path . --fixed-fps 60 -s res://scenes/test/smoke_test.gd` | Script must `extends SceneTree` and call `quit(code)` |
| Parse-check one file | `godot --headless --path . --check-only -s res://path.gd` | Works on any script, exit code always 0 — grep for `SCRIPT ERROR`. False `Identifier not found` for scripts that use autoloads (godotengine/godot#80319) |
| Arguments to a script | `godot … -s res://t.gd -- --case case_01` | Read with `OS.get_cmdline_user_args()` |
| Log to a file | add `--log-file /abs/path/godot.log` | |
| Export | `godot --headless --path . --export-release "<preset>" build/game` | Needs `export_presets.cfg` and installed templates; this repo has no preset yet |

## 4. Writing a headless test script

```gdscript
extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 -s res://scenes/test/my_test.gd
## Exits 0 and prints ALL TESTS PASSED when every check passes.

var _failures: Array[String] = []
var _game_state: Node


func _initialize() -> void:
	# Autoload nodes exist already, but their _ready() runs on the next frame.
	await process_frame
	# Not the bare name `GameState`: the -s entry script is compiled before
	# autoload names are registered.
	_game_state = get_root().get_node("GameState")

	_test_new_game()
	_finish()


func _test_new_game() -> void:
	_game_state.start_new_game("case_00_sandbox")
	_check(_game_state.current_location == "test_room", "new game should start in test_room")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		print("FAIL: ", failure)
	print("ALL TESTS PASSED" if _failures.is_empty() else "%d CHECK(S) FAILED" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
```

- Reach autoloads with `get_root().get_node("Name")` after
  `await process_frame`; hold them in untyped or `Node`-typed vars.
- Don't statically reference a `class_name` script that itself uses
  autoloads (`ContentValidator.validate()`) from the entry script. It gets
  compiled too early, fails with `Identifier not found`, and the failed
  compile is cached for the rest of the process — breaking even normal
  callers. `load("res://…gd")` it at runtime, or go through an autoload
  method (this repo's `ContentDB.get_last_validation_result()`).
- Put checks in helper functions called from `_initialize()`, as above. A
  crash then only aborts that helper and `quit()` still runs; the wrapper
  flags the `SCRIPT ERROR`.
- Never touch real player data. From the first draft, point save/settings
  paths at throwaway `user://` files and delete them afterwards
  (`smoke_test.gd` sets `SaveManager.save_path`). Every copy of this
  project, git worktrees included, shares the real game's `user://` folder
  (it is keyed by `config/name`).
- Collect results from signal callbacks in member variables or a captured
  `Array` / `Dictionary`: lambdas capture locals by value, so
  `func(): fired = true` doesn't change the outer `fired`.
- UI: instantiate the scene, `get_root().add_child(instance)`, call its
  methods, assert on properties (`visible`, `mouse_filter`, child counts,
  `disabled`). Free it at the end.
- Free what you create; leaks print `ObjectDB instances were leaked` /
  `resources still in use at exit` at shutdown (noise, but it hides real
  messages).

## 5. Reading Godot's output

| Line | Meaning | Treat as |
|---|---|---|
| `SCRIPT ERROR: Parse Error: …` then `ERROR: Failed to load script "res://x.gd"` | The script doesn't compile; everything that uses it is broken | Failure |
| `SCRIPT ERROR: <message>` then `at: func (res://x.gd:12)` | Runtime error; that function aborted | Failure |
| `ERROR: <message>` | `push_error()` or an engine error (missing resource, bad node path, invalid UID) | Failure in boot/import; in a test, check whether it's an intentional negative-path check |
| `WARNING: <message>` | `push_warning()` or an engine warning | Read it; not a failure by itself |
| `… ObjectDB instances were leaked at exit` / `… resources still in use at exit` | Something wasn't freed before quitting | Noise in tests; worth a look in a normal boot |

## 6. This repo

`scenes/test/` holds several small, independent `-s` scripts plus
`smoke_test.gd` (the critical-path/integration fixture) — see
`docs/testing.md` for the full list, what each covers, and the exact
FAST/FULL commands (the FULL one is also what CI runs):

```bash
V=.claude/skills/godot-development/scripts/verify.sh
$V --script res://scenes/test/validate_content.gd --script res://scenes/test/conditions_test.gd \
   --script res://scenes/test/effects_test.gd --script res://scenes/test/events_test.gd \
   --script res://scenes/test/duplicate_execution_test.gd --script res://scenes/test/save_load_regression_test.gd \
   --script res://scenes/test/negative_progression_test.gd --script res://scenes/test/dependency_analysis_test.gd \
   --script res://scenes/test/smoke_test.gd   # FULL check (~10 s)
$V --skip-import --skip-load-all --skip-boot --script res://scenes/test/validate_content.gd   # after editing only data/*.json
```

- Every one of these ends with `--- N passed, 0 failed ---` and
  `ALL TESTS PASSED`, exit 0. Several intentionally print `ERROR:` /
  `WARNING:` lines (mistyped conditions, a non-boolean flag, unknown dialogue
  ids, verbs rejected mid-dialogue, a locked destination refusing `move_to`).
  Those are expected — see each file's own header comment.
- The main scene is `TitleScreen.tscn`; a plain boot never loads `Main.tscn`
  or its overlays. `smoke_test.gd` instantiates them, so run it after any UI
  change.
- A new Condition/Effect check goes in `conditions_test.gd`/`effects_test.gd`
  (see `docs/testing.md`), never into `smoke_test.gd`.
- Engine quirks this repo already works around are listed in
  `docs/architecture.md` → "Known limitations".

## 7. What the CLI can't verify

Layout, visuals, animation feel, real mouse routing, audio. Headless checks
prove that code loads, runs, and produces the state you assert — nothing
about what the player sees. Say what's unverified and ask the human to run
the game (`godot --path .`, or F5 / F6 in the editor).
