# GDScript style and static typing (Godot 4.x)

Read this when writing or reviewing any `.gd` file, or when translating
Godot 3 code/snippets.

1. Static typing
2. Variant boundaries — where typing quietly breaks
3. Naming conventions
4. Script layout order
5. Formatting and comments
6. Godot 3 → 4 cheat sheet

---

## 1. Static typing

Type everything the parser can check: variables, parameters, return values,
signal parameters, array and dictionary element types.

Why: typed GDScript turns typos and wrong-type calls into **parse errors when
the script loads** — which the headless boot and test scripts catch — instead
of runtime errors on the one code path nobody tested. It also compiles to
faster typed opcodes and gives the editor real autocompletion.

```gdscript
signal health_changed(current: int, maximum: int)

const MAX_SPEED := 320.0                         # := is fine: the literal's type is obvious
@export var max_health: int = 100
@export var hit_sound: AudioStream
var _targets: Array[Node2D] = []
var _cooldowns: Dictionary[StringName, float] = {}   # typed dictionaries: 4.4+
@onready var _sprite: Sprite2D = %Sprite

func take_damage(amount: int) -> void:
	pass

## Returns null when nothing is in range.
func find_nearest(from: Vector2) -> Node2D:
	return null
```

Rules:
- Every `func` declares a return type, `-> void` included, and every parameter
  has a type.
- `@onready` node references are typed with the node's class:
  `@onready var title_label: Label = %TitleLabel`.
- Typed arrays: `Array[String]`, `Array[Node]`, `Array[EnemyData]`. Assigning
  a plain `Array` into a typed one fails at runtime — use
  `typed_array.assign(plain_array)` (as `GameState.load_from_dict()` does).
- `class_name` gives a script a global type usable in annotations and `is`
  checks. Add one to scripts others need to type against (components,
  Resources, static helper classes). Not needed for a scene root nobody types
  against, and **never** on an autoload script with the same name as the
  autoload.
- Use enums for closed sets instead of magic strings or ints:
  `enum Mode { BROWSE, SELECT }`. Strings are fine when the value comes from
  data (JSON ids).
- `StringName` literals (`&"move_left"`) are a good habit for input actions,
  animation names and groups on hot paths — nice to have, not required.
- Overriding a virtual (`_ready`, `_process`, …) **replaces** the base
  script's version; Godot 4 doesn't call it for you. Call `super()` when the
  base class's behaviour must still run.

Stricter checking lives in Project Settings → Debug → GDScript (Advanced
Settings), e.g. `untyped_declaration`, `unsafe_property_access`,
`unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`. Those are
project-wide decisions — propose them, don't flip them as a side effect of
another task.

## 2. Variant boundaries — where typing quietly breaks

Anything that returns `Variant` drops you out of the type system:
`Dictionary.get()`, `dict[key]`, `JSON.parse_string()`, elements of an untyped
`Array`, `get_meta()`, `Object.get()`, results of untyped functions, `for x in`
an untyped array.

- **Don't use `:=` on a Variant.** `var id := entry.get("id", "")` is a
  parse error by default in 4.x ("inferred from a Variant value … Warning
  treated as error"). Declare the type:
  `var id: String = entry.get("id", "")`. This repo does this everywhere it
  reads JSON-backed dictionaries.
- **`as` is not validation.** For objects, `x as Node2D` yields `null` on
  mismatch (then check for null). For built-in types it *converts*:
  `"abc" as int` is silently `0`. To validate data from JSON, saves, or
  `get_meta()`, check first: `if typeof(v) != TYPE_BOOL: ...` or
  `if v is String: ...`.
- **Say `Variant` when you mean it.** A value that really can be anything —
  raw JSON before validation, a save-file field — is declared `: Variant`
  (`func _read_weather(raw: Variant, source: String) -> String:`) and then
  narrowed with `typeof()` / `is`. That documents that the function must
  check its input, and keeps the script clean if the project ever enables
  the `untyped_declaration` warning. A bare parameter reads as an
  oversight, even where older code nearby does it.
- JSON numbers always come back as `float`. Convert explicitly
  (`int(value)`) and compare numerically.
- Read optional keys with `dict.get(key, default)`, never `dict[key]` — a
  missing key is an error with `[]`. In this repo, route content access
  through `ContentDB` getters instead of repeating key chains.

## 3. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Script files, folders | `snake_case` | `scripts/dialogue/dialogue_box.gd` |
| Scene files | Match the repo. Here: `PascalCase.tscn` (the official guide prefers snake_case; consistency within a project matters more) | `scenes/dialogue/DialogueBox.tscn` |
| `class_name`, node names | `PascalCase` | `class_name ConditionEvaluator`, node `ActionList` |
| Functions, variables | `snake_case` | `get_topics()`, `current_location` |
| Private members | leading `_` | `_render_current()`, `_is_interactive` |
| Signals | `snake_case`, past tense for events, `_requested` for asks | `flag_changed`, `dialogue_ended`, `present_requested` |
| Signal handlers | `_on_<emitter>_<signal>` | `_on_menu_button_pressed`, `_on_location_changed` |
| Constants | `CONSTANT_CASE` | `DATA_ROOT` |
| Enums | `PascalCase` name, `CONSTANT_CASE` members | `enum State { IDLE, TALKING }` |
| Booleans | `is_` / `has_` / `can_` prefix | `is_active`, `has_evidence()` |
| Input actions, groups | `snake_case` | `move_left`, `interactable` |
| Autoloads | `PascalCase` noun | `GameState`, `SaveManager` |

## 4. Script layout order

Follow the official order so any script reads the same way:

```
@tool / @icon                      (if any)
class_name X                       (if any)
extends Base
## Doc comment: what this script is for and how it fits in.

signal ...
enum ...
const ...
static var ...
@export var ...
var public_state
var _private_state
@onready var ...

func _static_init() / static func ...
func _init()
func _enter_tree()
func _ready()
func _process(delta)
func _physics_process(delta)
func _input / _unhandled_input / other virtuals
func public_methods()
func _private_methods()
class InnerClass
```

## 5. Formatting and comments

- Tabs for indentation (Godot's default; every script here uses them).
- Two blank lines between functions; one blank line to group related lines.
- `and` / `or` / `not` rather than `&&` / `||` / `!`.
- Trailing comma on multi-line arrays, dictionaries and argument lists.
- `##` doc comments above scripts and public members show up in the editor's
  built-in help. This repo uses them to explain *why* (design reasons,
  engine quirks, bugs that were fixed) — match that density in the files you
  touch, and don't narrate what the code already says.

## 6. Godot 3 → 4 cheat sheet

Training data and web snippets are full of Godot 3. None of the left column
compiles (or behaves the same) in Godot 4.

| Godot 3 | Godot 4 |
|---|---|
| `export var x = 1` / `onready var n = $N` / `tool` | `@export var x: int = 1` / `@onready var n: Node = $N` / `@tool` |
| `yield(obj, "sig")` | `await obj.sig` |
| `yield(get_tree().create_timer(1), "timeout")` | `await get_tree().create_timer(1.0).timeout` |
| `connect("pressed", self, "_on_pressed")` | `pressed.connect(_on_pressed)` |
| `emit_signal("died", x)` | `died.emit(x)` |
| `var hp setget set_hp` | `var hp: int: set = _set_hp` or an inline `set(value):` block |
| `funcref(obj, "m")` | `obj.m` (a `Callable`) or `Callable(obj, "m")` |
| `KinematicBody2D` + `move_and_slide(velocity, Vector2.UP)` | `CharacterBody2D`: assign `velocity`, call `move_and_slide()` with no args |
| `scene.instance()` | `scene.instantiate()` |
| `get_tree().change_scene("res://x.tscn")` | `get_tree().change_scene_to_file("res://x.tscn")` |
| `File.new()` / `Directory.new()` | `FileAccess.open(path, mode)` / `DirAccess.open(path)` — return `null` on failure |
| `to_json(x)` / `parse_json(s)` | `JSON.stringify(x)` / `JSON.parse_string(s)`, or `JSON.new().parse(s)` for error line and message |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `rand_range(a, b)` | `randf_range(a, b)` / `randi_range(a, b)` |
| `.empty()` | `.is_empty()` |
| `PoolStringArray` | `PackedStringArray` |
| `Spatial` / `Position2D` / `Sprite` | `Node3D` / `Marker2D` / `Sprite2D` |
| `BUTTON_LEFT` | `MOUSE_BUTTON_LEFT` |
| `deg2rad` / `str2var` | `deg_to_rad` / `str_to_var` |
| `Tween` node | `create_tween()` (a `RefCounted`, not a node) |
| `update()` on a CanvasItem | `queue_redraw()` |
| `rect_position` / `rect_size` | `position` / `size` |
| Virtuals auto-call the base `_ready()` | They don't — call `super()` |
