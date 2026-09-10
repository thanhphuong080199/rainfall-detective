extends Node
## Autoload: ContentDB
##
## Loads and caches every piece of data-driven content (characters, evidence,
## locations, dialogue trees, cases) from plain JSON files under res://data/
## at startup. This is the ONLY system that reads data/ directly — everything
## else (DialogueManager, Investigation, UI) goes through the getters below.
## Centralizing access here means a typo in a content key breaks loudly in
## one place instead of being repeated across every consumer.
##
## Dropping a new *.json file into one of the data/ subfolders is enough to
## add content — nothing needs to be registered or imported by hand.

const DATA_ROOT := "res://data"

var _characters: Dictionary = {}
var _evidence: Dictionary = {}
var _locations: Dictionary = {}
var _dialogues: Dictionary = {}
var _cases: Dictionary = {}
var _last_validation_result: Dictionary = {}


func _ready() -> void:
	_characters = _load_json_dir(DATA_ROOT + "/characters")
	_evidence = _load_json_dir(DATA_ROOT + "/evidence")
	_locations = _load_json_dir(DATA_ROOT + "/locations")
	_dialogues = _load_json_dir(DATA_ROOT + "/dialogue", true)
	_cases = _load_json_dir(DATA_ROOT + "/cases")
	print("[ContentDB] loaded %d characters, %d evidence, %d locations, %d dialogue trees, %d cases" % [
		_characters.size(), _evidence.size(), _locations.size(), _dialogues.size(), _cases.size(),
	])
	_last_validation_result = ContentValidator.validate()
	ContentValidator.report(_last_validation_result)


## Result of the automatic validation pass run above, for anything that
## needs a scriptable pass/fail without statically referencing
## ContentValidator itself — see scenes/test/validate_content.gd for why
## that matters (a real Godot compile-order quirk with `-s` entry scripts,
## documented in docs/architecture.md's Known Limitations).
func get_last_validation_result() -> Dictionary:
	return _last_validation_result


func get_character(character_id: String) -> Dictionary:
	return _characters.get(character_id, {})


func get_evidence(evidence_id: String) -> Dictionary:
	return _evidence.get(evidence_id, {})


func get_location(location_id: String) -> Dictionary:
	return _locations.get(location_id, {})


func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})


func get_case(case_id: String) -> Dictionary:
	return _cases.get(case_id, {})


func get_all_evidence_ids() -> Array:
	return _evidence.keys()


func get_all_character_ids() -> Array:
	return _characters.keys()


func get_all_location_ids() -> Array:
	return _locations.keys()


func get_all_dialogue_ids() -> Array:
	return _dialogues.keys()


func get_all_case_ids() -> Array:
	return _cases.keys()


## Raw id -> content dictionaries, for systems that need to iterate every
## entry in a category (ContentValidator, debug tooling) rather than look up
## one id at a time. Gameplay code should keep using the get_*(id) getters
## above instead — these exist for tooling, not for story logic.
func get_all_characters() -> Dictionary:
	return _characters


func get_all_locations() -> Dictionary:
	return _locations


func get_all_dialogues() -> Dictionary:
	return _dialogues


func get_all_evidence() -> Dictionary:
	return _evidence


func get_all_cases() -> Dictionary:
	return _cases


## Loads every *.json file directly inside `dir_path` (no recursion into
## subfolders). Each file holds either one JSON object with an "id" field,
## or — when `allow_multiple` is true — an array of such objects, which lets
## a single dialogue file group several related trees together. Returns a
## dictionary of all entries keyed by their "id".
func _load_json_dir(dir_path: String, allow_multiple: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[ContentDB] content folder not found: %s" % dir_path)
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_json_file(dir_path + "/" + file_name, allow_multiple, result)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_json_file(file_path: String, allow_multiple: bool, result: Dictionary) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[ContentDB] could not open %s (error %s)" % [file_path, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		push_error("[ContentDB] JSON error in %s line %d: %s" % [file_path, parser.get_error_line(), parser.get_error_message()])
		return

	var data = parser.data
	if allow_multiple and typeof(data) == TYPE_ARRAY:
		for entry in data:
			_store_entry(file_path, entry, result)
	else:
		_store_entry(file_path, data, result)


func _store_entry(file_path: String, entry, result: Dictionary) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("[ContentDB] expected a JSON object in %s" % file_path)
		return
	var entry_id: String = entry.get("id", "")
	if entry_id == "":
		push_error("[ContentDB] entry in %s is missing an \"id\" field" % file_path)
		return
	if result.has(entry_id):
		push_warning("[ContentDB] duplicate content id \"%s\" — %s overwrites a previous entry" % [entry_id, file_path])
	result[entry_id] = entry
