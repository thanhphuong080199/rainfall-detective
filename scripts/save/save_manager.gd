extends Node
## Autoload: SaveManager
##
## Reads/writes a single, human-readable JSON save file under user://.
## Owns the save-format version — GameState itself has no opinion on file
## format, it only hands over/accepts a plain state dictionary.

const DEFAULT_SAVE_PATH := "user://save_game.json"
const SAVE_VERSION := 1

## The slot every method below reads and writes. A variable rather than a
## constant purely so automated tests can point at a throwaway file instead
## of stomping the player's real save; gameplay never changes it.
var save_path: String = DEFAULT_SAVE_PATH


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"state": GameState.get_save_dict(),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager.save_game: could not open %s for writing (error %s)" % [save_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_game() -> bool:
	if not has_save():
		push_warning("SaveManager.load_game: no save file at %s" % save_path)
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager.load_game: could not open %s for reading (error %s)" % [save_path, FileAccess.get_open_error()])
		return false
	var text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_error("SaveManager.load_game: corrupt save file at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return false

	var payload = parser.data
	if typeof(payload) != TYPE_DICTIONARY or not payload.has("state"):
		push_error("SaveManager.load_game: save file is not in the expected format")
		return false

	GameState.load_from_dict(payload.get("state", {}))
	return true


## Starts a fresh game for the given case, discarding current in-memory
## state. Does not touch the save file on disk — the player must explicitly
## Save afterwards if they want to overwrite it. Routed through
## CaseManager.start_case() rather than GameState.start_new_game() directly
## so any case — chapter-based or flat — gets its chapter state (if any)
## initialized the same way; see docs/case-system.md, "Case initialization".
func new_game(case_id: String = "case_00_sandbox") -> void:
	CaseManager.start_case(case_id)


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
