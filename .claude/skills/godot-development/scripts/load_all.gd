extends SceneTree
## Loads every script, scene and resource in the project once — without
## instantiating anything — so parse errors and broken ext_resource references
## surface even in files the main scene never loads. Used by verify.sh; to run
## it by hand:
##   godot --headless --path <project> --fixed-fps 60 -s <path to this file>
## Exits 1 if anything failed to load. Godot prints the underlying
## SCRIPT ERROR / ERROR lines above this script's own summary.
##
## Skips hidden folders (.godot, .git, .claude) and res://addons/ — plugin
## code is often editor-only, and `extends EditorPlugin` can't load in a game
## run.

const EXTENSIONS: Array[String] = ["gd", "tscn", "scn", "tres", "res"]
const SKIPPED_TOP_LEVEL_DIRS: Array[String] = ["addons"]


func _initialize() -> void:
	# Autoload names only resolve once the main loop is running; loading a
	# script that uses them before this point fails with "Identifier not found".
	await process_frame

	var paths: Array[String] = []
	_collect("res://", paths)
	var failed: Array[String] = []
	for path in paths:
		if ResourceLoader.load(path) == null:
			failed.append(path)

	for path in failed:
		print("[load_all] FAILED to load: ", path)
	print("[load_all] %d of %d files loaded" % [paths.size() - failed.size(), paths.size()])
	quit(1 if not failed.is_empty() else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[load_all] cannot open %s" % dir_path)
		return
	for sub_dir in dir.get_directories():
		if sub_dir.begins_with(".") or (dir_path == "res://" and sub_dir in SKIPPED_TOP_LEVEL_DIRS):
			continue
		_collect(dir_path.path_join(sub_dir), out)
	for file_name in dir.get_files():
		if file_name.get_extension() in EXTENSIONS:
			out.append(dir_path.path_join(file_name))
