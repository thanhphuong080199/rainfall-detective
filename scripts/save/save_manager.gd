extends Node
## Autoload: SaveManager
##
## Reads/writes a single, human-readable JSON save file under user://.
## Owns the save-format version — GameState itself has no opinion on file
## format, it only hands over/accepts a plain state dictionary.

const SAVE_PATH := "user://save_game.json"
const SAVE_VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"state": GameState.get_save_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager.save_game: could not open %s for writing (error %s)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_game() -> bool:
	if not has_save():
		push_warning("SaveManager.load_game: no save file at %s" % SAVE_PATH)
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager.load_game: could not open %s for reading (error %s)" % [SAVE_PATH, FileAccess.get_open_error()])
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
## Save afterwards if they want to overwrite it.
func new_game(case_id: String = "case_00_sandbox") -> void:
	GameState.start_new_game(case_id)


func delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("save_game.json"):
		dir.remove("save_game.json")
