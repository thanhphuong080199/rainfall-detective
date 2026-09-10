extends SceneTree
## Standalone content-validation runner. Run with:
##   godot --headless --path . -s res://scenes/test/validate_content.gd
## Exits 0 if there are no validation errors (warnings are fine), 1 otherwise
## — intended for a pre-commit check or CI step when adding/editing content
## under data/, without booting the full game or running the smoke test.
##
## ContentDB._ready() already runs the validator and prints this same report
## on every boot (see content_db.gd) — this script exists only to turn that
## into a scriptable process exit code. See docs/content-guide.md,
## "Validating content".
##
## Deliberately reaches ContentValidator's result ONLY through
## ContentDB.get_last_validation_result() — via get_root().get_node(), the
## same pattern smoke_test.gd uses for every autoload — rather than calling
## `ContentValidator.validate()` directly. Calling a class_name script that
## itself references an autoload (ContentDB) by bare name, directly from a
## custom `-s` entry script, hits a real Godot compile-order bug: it forces
## that class_name script to compile during the entry script's own
## restricted early pass (before autoload identifiers are registered),
## which fails with "Identifier not found: ContentDB" — and because
## GDScript caches that failed compile, ContentValidator then stays broken
## for the rest of the process, including inside ContentDB's own normal
## _ready() call to it. Routing through the autoload's own method sidesteps
## this entirely, matching the existing documented quirk in
## docs/architecture.md ("A Godot quirk this project works around").


func _initialize() -> void:
	var content_db := get_root().get_node("ContentDB")
	# ContentDB's own data load + validation happens in _ready(), which (like
	# every autoload) runs next frame under the -s entry point.
	await process_frame

	var result: Dictionary = content_db.get_last_validation_result()
	var error_count: int = result.get("errors", []).size()
	quit(1 if error_count > 0 else 0)
