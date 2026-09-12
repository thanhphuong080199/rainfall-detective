# Lifecycle, processing, input, and resource loading (Godot 4.x)

Read this when adding `_ready`/`_process`/`_physics_process`/input handlers,
anything that moves or animates, anything that loads files, or when editing
`.tscn`/`.tres` files by hand.

1. Callback order
2. `_process` vs `_physics_process`
3. Input handling
4. Deferred calls, `await`, and freeing
5. Resource loading
6. Paths, UIDs, and exported builds
7. Editing `.tscn` / `.tres` as text

---

## 1. Callback order

| Callback | When | Order across the tree | Use for |
|---|---|---|---|
| `_init()` | Object constructed. Not in the tree yet, and **before** a scene's saved property values (including `@export`s set in the Inspector) are applied — you still see script defaults here. | — | Defaults, constructor args for code-created objects |
| `_enter_tree()` | Every time the node enters the tree | Parent first, then children | Rare: registering with something that must know immediately |
| `_ready()` | Once, the first time it enters the tree, after all its children are ready. `@onready` vars are resolved right before it. | Children first, then parent | Grabbing child refs, connecting signals, first render |
| `_process(delta)` | Every frame, variable `delta` | Tree order (adjust with `process_priority`) | Visuals, UI, animation, non-physics timers |
| `_physics_process(delta)` | Fixed tick (`physics/common/physics_ticks_per_second`, default 60) | Tree order | Physics bodies, raycasts, deterministic gameplay |
| `_exit_tree()` | Leaving the tree (also right before being freed) | Children first, then parent | Disconnecting from things that outlive you |

Consequences:
- In `_ready()` a parent can rely on its children being ready; a child can
  **not** rely on its parent's `_ready()` having run.
- Overriding a virtual replaces the base class's version — call `super()` if
  the base behaviour must still run (Godot 3 called it automatically, Godot 4
  doesn't).
- `_ready()` runs once. A node removed and re-added gets `_enter_tree()`
  again but not `_ready()` (unless `request_ready()`).

## 2. `_process` vs `_physics_process`

- Defining `_process` or `_physics_process` turns per-frame processing on.
  Don't define them "just in case". Toggle with `set_process(false)` /
  `set_physics_process(false)` while idle and back on when needed (a
  typewriter effect only needs `_process` while text is still revealing).
- Prefer signals to polling. `if GameState.current_location != _last` every
  frame should be a connection to `GameState.location_changed`.
- Physics bodies move in `_physics_process`: set `velocity`, call
  `move_and_slide()`. `move_and_slide()` already applies `delta` — don't
  multiply `velocity` by it. For manual motion in `_process`
  (`position += direction * speed * delta`) you do multiply.
- Don't set a physics body's `position` every frame — that teleports it past
  collisions.
- Don't `load()`, build big strings, or allocate scenes inside per-frame
  callbacks; hoist them to `const` preloads or cached members.

## 3. Input handling

Pipeline for each event: `_input` → GUI (`Control._gui_input`) →
`_shortcut_input` → `_unhandled_key_input` → `_unhandled_input`. Within each
stage nodes are visited in reverse tree order (the last child first). Call
`get_viewport().set_input_as_handled()` to stop propagation.

- Gameplay input (clicks on the world, movement keys) goes in
  `_unhandled_input`, so UI on top gets first refusal.
- Use `_input` only when you must beat the GUI — this repo's overlays use it
  for Esc so the topmost overlay closes first (see `docs/architecture.md`).
- Discrete presses: `event.is_action_pressed(&"interact")` inside an input
  callback. Held state: `Input.is_action_pressed()` / `Input.get_vector()`
  polled in `_physics_process`. Don't mix the two for one action.
- Define actions in the Input Map (`project.godot` `[input]`) rather than
  hard-coding keycodes.
- For Controls, `mouse_filter` decides who sees a click (`STOP` absorbs,
  `PASS` handles and passes to the parent, `IGNORE` is transparent). Get it
  wrong and clicks silently vanish — this repo documents its chain in
  `docs/architecture.md` and asserts it in `smoke_test.gd`.

## 4. Deferred calls, `await`, and freeing

- Physics state can't change while physics is flushing (inside
  `body_entered`, etc.). Use `collision_shape.set_deferred(&"disabled", true)`
  or `some_method.call_deferred()`, not a direct assignment.
- `await` inside `_ready()` returns control at the first `await`: the parent's
  `_ready()` runs before the rest of yours. After any `await`, the node (or
  what it points at) may have been freed — check `is_instance_valid()`.
- One-off delays: `await get_tree().create_timer(seconds).timeout`. Repeating:
  a `Timer` node. Don't accumulate `delta` by hand unless you need it.
- `queue_free()` deletes at the end of the frame; the node remains in the tree
  (visible, clickable, connected) until then. See `architecture.md` §8 and
  `UiUtil.clear_children()`.

## 5. Resource loading

| | `preload("res://…")` | `load(path)` | `ResourceLoader.load_threaded_request(path)` |
|---|---|---|---|
| When | When the script itself loads | When the line runs; blocks | Background threads |
| Path | String literal only | Any string | Any string |
| Good for | Small, always-needed scenes/resources this script instances (`const SlotScene := preload(...)`) | Paths from data, rarely used assets | Large scenes, anything behind a loading screen |
| Missing file | Parse error — the script fails to load | Returns `null` and prints an error | Status reports `THREAD_LOAD_FAILED` |

- Loads go through the resource cache: the same path returns the same
  instance while anything references it. See `architecture.md` §5 before
  mutating a loaded Resource.
- Validate dynamic loads:
  ```gdscript
  var texture := load(path) as Texture2D
  if texture == null:
  	push_error("missing texture: %s" % path)
  	return
  ```
  `ResourceLoader.exists(path)` checks without loading.
- Preload cycles (A preloads B, B preloads A) break loading; switch one side
  to `load()` at the point of use or an exported `PackedScene`.
- Threaded loading:
  ```gdscript
  var _pending_path: String = ""

  func begin_load(path: String) -> void:
  	_pending_path = path
  	ResourceLoader.load_threaded_request(path)
  	set_process(true)

  func _process(_delta: float) -> void:
  	var progress: Array = []
  	match ResourceLoader.load_threaded_get_status(_pending_path, progress):
  		ResourceLoader.THREAD_LOAD_LOADED:
  			set_process(false)
  			var scene := ResourceLoader.load_threaded_get(_pending_path) as PackedScene
  			get_tree().change_scene_to_packed(scene)
  		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
  			set_process(false)
  			push_error("failed to load %s" % _pending_path)
  		_:
  			_progress_bar.value = progress[0] * 100.0
  ```

## 6. Paths, UIDs, and exported builds

- `res://` is the project folder and is **read-only** in exported builds.
  Write saves, settings and logs to `user://` (on macOS:
  `~/Library/Application Support/Godot/app_userdata/<project name>/`).
- Player settings (volume, text speed) and save games are different things;
  keep them in separate `user://` files (`ConfigFile` suits settings).
- In an export, imported assets are remapped: `load("res://a.png")` works,
  but `FileAccess.open("res://a.png")` doesn't (the source file isn't
  shipped), and `DirAccess` listings show `.import` / `.remap` names. Use
  `ResourceLoader.list_directory()` (4.4+) to enumerate loadable resources.
- Non-resource files (JSON, CSV, txt) are only exported if the preset's
  "Filters to export non-resource files/folders" includes them. This repo's
  `data/*.json` needs that before its first export (known limitation in
  `docs/architecture.md`).
- UIDs (4.4+): each script/shader has a sibling `.uid` file; each imported
  asset has a `.import` file carrying its `uid://`. Commit both. Rename or
  move files in the editor's FileSystem dock so references follow. If you
  move files from the shell, move the `.uid`/`.import` with them, then run
  `godot --headless --import --path .`. A stale `uid://` in a scene falls
  back to the text path with a warning — fix it rather than ignore it.
- JSON: `JSON.new().parse(text)` gives you `get_error_line()` /
  `get_error_message()`; `JSON.parse_string()` just returns `null`.

## 7. Editing `.tscn` / `.tres` as text

Text scenes are editable by hand, and an agent often has to. Keep them valid:

- Header: `[gd_scene load_steps=N format=3 uid="uid://…"]`. If you add or
  remove `ext_resource`/`sub_resource` entries, keep `load_steps` in step
  (resources + 1) when the header has it.
- `[ext_resource type="Script" path="res://…" id="3"]`: ids are unique within
  the file and referenced as `ExtResource("3")`. Don't invent `uid=` values —
  omit the attribute and Godot resolves the path (it adds the uid next time
  the editor saves the scene).
- Node `parent=` paths are relative to the scene root: `parent="."`,
  `parent="Box/Margin"`. A node instanced from another scene is
  `[node name="X" parent="." instance=ExtResource("2")]`.
- `unique_name_in_owner = true` makes the node reachable as `%X`.
- Editor-made signal connections live at the bottom:
  `[connection signal="pressed" from="Button" to="." method="_on_button_pressed"]`.
- A broken scene often *loads* with only a printed `ERROR:`. After editing
  one, instantiate it in a headless run (see `cli-verification.md`) and read
  the output — don't assume it's fine because nothing crashed.
