# Architecture patterns (Godot 4.x)

Read this when designing a feature that spans more than one node or scene,
adding a scene/component, touching autoloads, or deciding where state lives.

1. Scene ownership
2. Communication: call down, signal up
3. Signals in practice
4. Composition over inheritance
5. Resources as data
6. Autoloads — when to use, when not to
7. Referencing nodes without NodePath coupling
8. Instancing and freeing

---

## 1. Scene ownership

Treat a saved scene (`.tscn`) like a class. The root node's script is the
scene's **public API**; every node under it is private implementation detail.

- The root script owns its subtree. It may reach its own children (`%Name`,
  `$Child`), configure them, and connect their signals.
- Outsiders talk only to the root: call its public methods, set its `@export`
  properties, connect to its signals. They never reach into its children —
  `$Player/Sprite2D/AnimationPlayer` from a level script breaks silently (a
  `null` at runtime, not a parse error) the day someone renames a node inside
  `Player`.
- Whoever creates a node owns its lifetime. A node doesn't `queue_free()` its
  parent or siblings; it emits a signal and lets the owner decide.
- "Editable Children" on an instanced scene punches through the boundary.
  Prefer exposing what the parent needs as `@export` properties or methods on
  the sub-scene's root.
- A scene should be instantiable on its own (F6 in the editor, or
  `instantiate()` in a headless test). That holds when its dependencies arrive
  through `@export`, a `setup()` call, or autoloads — not through
  `get_parent()` assumptions.
- `owner` is not `parent`: `owner` is the root of the scene a node was saved
  in. `%UniqueName` is resolved within the owner, which is why `%` can't reach
  inside an instanced sub-scene (by design) and why nodes created at runtime
  aren't found by `%` unless you set both `owner` and `unique_name_in_owner`.
  In `@tool` scripts, nodes you create need
  `node.owner = get_tree().edited_scene_root` or they won't be saved into the
  `.tscn`.

In this repo `scripts/ui/main.gd` is the only place overlays are wired to each
other; each UI scene exposes signals (`present_requested`,
`evidence_chosen_for_present`) and methods (`open()`, `set_interactive()`).
New overlays should follow the same shape.

## 2. Communication: call down, signal up

| Direction | Mechanism |
|---|---|
| Parent → child | Call methods / set properties directly. The parent owns the child and knows its type. |
| Child → parent | Emit a signal. The child doesn't know or care who listens. |
| Sibling ↔ sibling | Neither references the other. The common parent (the orchestrator) connects one's signal to the other's method. |
| Anything → global system | Call the autoload's methods. |
| Global system → anything | The autoload emits signals; interested nodes connect in `_ready()`. |

## 3. Signals in practice

```gdscript
signal item_picked(item_id: String)          # typed parameters
signal present_requested(npc_id: String)     # "_requested" = asking someone else to act

func _ready() -> void:
	%PickButton.pressed.connect(_on_pick_button_pressed)
	GameState.evidence_added.connect(_on_evidence_added)

func _on_pick_button_pressed() -> void:
	item_picked.emit(_item_id)
```

- Name events in the past tense (`opened`, `health_changed`,
  `dialogue_ended`); name requests `*_requested`.
- Use the Godot 4 object API — `sig.emit(...)`, `sig.connect(callable)`. The
  string forms (`emit_signal("x")`, `connect("x", obj, "method")`) skip
  parse-time checking.
- Connect in `_ready()`. Editor connections (the `[connection]` block in a
  `.tscn`) also work but are invisible when reading the script; this repo
  connects in code, so keep doing that.
- Extra arguments: `.bind(point_id)` appends them after the signal's own.
- One-shot: `connect(callable, CONNECT_ONE_SHOT)`, or `await some_signal`.
- Lifetime: when a node is freed, Godot drops connections whose target is that
  node. Prefer named methods when a short-lived node listens to a long-lived
  emitter (an autoload). If you connect a lambda, make sure it can't outlive
  anything it captures. A node removed from the tree but kept alive (pooled,
  cached) keeps receiving signals — disconnect in `_exit_tree()`.
- Lambdas capture local variables **by value**, once, when the lambda is
  created. After `var done := false`, `sig.connect(func(): done = true)`
  never changes the outer `done`. To get a result out of a callback, write
  to a member variable, mutate a captured `Array` / `Dictionary`
  (`hits.append(id)`), or `await` the signal instead.
- Signals announce things. For a synchronous question ("what is the current
  value?") call a method instead.
- A global "EventBus" autoload full of signals is tempting and makes flow hard
  to trace. Put a signal on the system that owns the state
  (`GameState.flag_changed`), and reserve a bus for events that genuinely have
  no owner.

## 4. Composition over inheritance

- Build behaviour from small nodes or scenes with one job each, configured via
  `@export`, reporting via signals: a `HealthComponent` emitting `died`, an
  `Area2D` hurtbox, an interactable hotspot, this repo's `PlaceholderVisual`.
- Keep inheritance shallow — one level of your own base class is usually
  enough. Deep chains make `_ready()`/`super()` ordering hard to follow.
- Detect capabilities with types or groups (`body is Damageable`,
  `body.is_in_group(&"damageable")`) rather than duck typing;
  `has_method()` + `call()` is a last resort.
- Reuse a subtree by saving it as a scene and instancing it, not by
  copy-pasting nodes.
- Stateless helpers go in a `class_name` script with `static func`s (this
  repo's `UiUtil`, `ConditionEvaluator`) — not an autoload, not a base class.

## 5. Resources as data

A custom `Resource` is Godot's native typed data container:

```gdscript
class_name EnemyStats
extends Resource

@export var max_health: int = 10
@export var speed: float = 120.0
@export var drops: Array[ItemData] = []
```

- Use Resources for designer-tunable data and definitions: stats, item
  definitions, tuning, configuration. You get Inspector editing, type
  checking, and `.tres` files that can reference each other.
- Inject them: `@export var stats: EnemyStats`.
- **Resources are shared.** Loading the same path returns the same cached
  instance, and every node exporting it holds the same object. Mutating it at
  runtime changes it for everyone (and in the editor, for the file on disk).
  Keep definitions read-only and put runtime state (current health) on the
  node. If you truly need a private copy: `duplicate()` (shallow —
  sub-resources stay shared), `duplicate_deep()` (4.5+), or
  `resource_local_to_scene = true`.
- Never load save games as `.tres`/`.res` from `user://`: resource files can
  embed scripts that run on load. Save with JSON, `ConfigFile`, or
  `FileAccess.store_var()` (without `allow_objects`).
- **Documented project decisions win over this default.** This repo
  deliberately authors narrative content (characters, evidence, locations,
  dialogue, cases) as JSON under `data/`, read only through `ContentDB` — see
  `docs/architecture.md` → "Key Architecture Decisions". Don't convert that to
  `.tres`. Resources are the default for new engine-side data where no such
  decision exists yet; if the choice is unclear, ask.

## 6. Autoloads — when to use, when not to

An autoload is a node created under `/root` before the main scene, alive for
the whole run, reachable by its name from every script.

**Use one only when all three hold:**
1. The state or service must outlive scene changes (game state, save/load,
   player settings, music that keeps playing across scene changes, scene
   transitions).
2. Many unrelated scenes need it.
3. There must be exactly one.

**Don't use one when:**
- It's stateless → `class_name` + `static func`.
- It's data or definitions → a Resource (or, in this repo, JSON via
  `ContentDB`).
- Only one scene and its children use it → make it a node in that scene and
  pass references down / signal up.
- The motivation is "so I don't have to pass a reference". That's a hidden
  global dependency, and it makes scenes impossible to run or test alone.

**If you add one:**
- Register it in `project.godot` under `[autoload]` as
  `Name="*res://path/to/script.gd"` (the `*` makes it a singleton node) — the
  same thing Project Settings → Autoload writes.
- Don't give the script a `class_name` equal to the autoload name (the
  "hides an autoload singleton" error). This repo's autoload scripts have no
  `class_name` at all.
- Autoloads enter the tree in the order listed, before the main scene. In
  `_ready()`, depend only on autoloads listed above it. Never reach into the
  current scene (`get_tree().current_scene.get_node(...)`): scenes depend on
  autoloads, not the other way round — push changes out with signals.
- If it needs child nodes (an `AudioStreamPlayer`, a `Timer`), register a
  `.tscn` as the autoload, or create the children in `_ready()`.
- Keep the set small and each one cohesive. This repo lists its five
  autoloads with an ownership table in `docs/architecture.md`; add any new
  one there too.
- In `-s` headless scripts autoloads can't be referenced by bare name — see
  `cli-verification.md`.

## 7. Referencing nodes without NodePath coupling

In order of preference:

1. **Nodes in your own scene:** `%UniqueName` ("Access as Unique Name", stored
   as `unique_name_in_owner = true`) in a typed `@onready` var. Survives
   re-parenting within the scene. `$DirectChild` is fine for stable direct
   children.
2. **Something outside your scene:** an exported node reference
   (`@export var target: Node2D` — the Inspector assigns it and the editor
   keeps the stored path updated on rename), a `setup(dependency)` call from
   whoever instantiates you, or a signal connection made by the common
   parent.
3. **Global services:** the autoload by name.
4. **"Every node of kind X":** groups — `get_tree().get_nodes_in_group(&"x")`,
   `get_tree().call_group(&"x", &"method")`.

Avoid:
- `get_node("../../Something")`, `$"../Sibling"`, `get_parent().get_parent()`.
- Absolute paths into the running scene: `/root/Main/UI/...`.
- Any path into another scene's internals, including a sub-scene's `%Name`.
- Node paths stored as strings in data files.

Optional reference → `get_node_or_null()` and handle `null`. Required
reference → check it once in `_ready()` with a clear `push_error()` or
`assert()`, instead of crashing on first use somewhere else.

## 8. Instancing and freeing

```gdscript
const EnemyScene := preload("res://scenes/enemies/Enemy.tscn")

func spawn(stats: EnemyStats, at: Vector2) -> void:
	var enemy := EnemyScene.instantiate() as Enemy
	enemy.stats = stats            # configure BEFORE add_child — _ready() runs inside add_child
	enemy.position = at
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_enemy_container.add_child(enemy)
```

- `_ready()` runs during `add_child()`, so set whatever `_ready()` reads
  first — or make the setter handle both cases
  (`if is_node_ready(): _refresh()`).
- `queue_free()` defers deletion to the end of the frame; until then the node
  is still in the tree, visible, laid out, and connected. When rebuilding a
  list in the same frame, `remove_child()` first and then `queue_free()`. In
  this repo, use `UiUtil.clear_children(parent)`, which does exactly that.
- After an `await` or in a deferred callback, check `is_instance_valid(node)`
  before touching a node that may have been freed meanwhile.
- `remove_child()` without freeing leaks the node (an orphan) unless you keep
  it for reuse.
- `get_tree().change_scene_to_file()` / `change_scene_to_packed()` free the
  current scene; autoloads survive.
