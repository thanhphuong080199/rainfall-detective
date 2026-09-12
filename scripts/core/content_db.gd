extends Node
## Autoload: ContentDB
##
## Loads and caches every piece of data-driven content (characters, evidence,
## locations, dialogue trees, cases, events) from plain JSON files under
## res://data/ at startup. This is the ONLY system that reads data/ directly —
## everything else (DialogueManager, Investigation, EventManager, UI) goes
## through the getters below.
## Centralizing access here means a typo in a content key breaks loudly in
## one place instead of being repeated across every consumer.
##
## Dropping a new *.json file into one of the data/ subfolders is enough to
## add content — nothing needs to be registered or imported by hand. Nested
## folders are scanned too (e.g. data/dialogue/case_01/*.json), so a case can
## keep its content together; the id namespace stays flat per category
## regardless of folder, and duplicates are reported by ContentValidator.

const DATA_ROOT := "res://data"

var _characters: Dictionary = {}
var _evidence: Dictionary = {}
var _locations: Dictionary = {}
var _dialogues: Dictionary = {}
var _chapters: Dictionary = {}
var _cases: Dictionary = {}
var _events: Dictionary = {}
var _last_validation_result: Dictionary = {}

## Duplicate-id collisions noticed while loading, as ready-to-print messages.
## They can only be detected here (by the time a category dictionary is built
## the collision has already collapsed), so ContentValidator reads them back
## out via get_duplicate_id_issues() and reports them as errors.
var _duplicate_id_issues: Array[String] = []


func _ready() -> void:
	_duplicate_id_issues.clear()
	_characters = _load_json_dir(DATA_ROOT + "/characters")
	_evidence = _load_json_dir(DATA_ROOT + "/evidence")
	_locations = _load_json_dir(DATA_ROOT + "/locations")
	_dialogues = _load_json_dir(DATA_ROOT + "/dialogue", true)
	_chapters = _load_json_dir(DATA_ROOT + "/chapters")
	_cases = _load_json_dir(DATA_ROOT + "/cases")
	_events = _load_json_dir(DATA_ROOT + "/events", true)
	print("[ContentDB] loaded %d characters, %d evidence, %d locations, %d dialogue trees, %d chapters, %d cases, %d events" % [
		_characters.size(), _evidence.size(), _locations.size(), _dialogues.size(), _chapters.size(), _cases.size(), _events.size(),
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


func get_duplicate_id_issues() -> Array[String]:
	return _duplicate_id_issues


func get_character(character_id: String) -> Dictionary:
	return _characters.get(character_id, {})


func get_evidence(evidence_id: String) -> Dictionary:
	return _evidence.get(evidence_id, {})


func get_location(location_id: String) -> Dictionary:
	return _locations.get(location_id, {})


func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})


func get_chapter(chapter_id: String) -> Dictionary:
	return _chapters.get(chapter_id, {})


func get_case(case_id: String) -> Dictionary:
	return _cases.get(case_id, {})


func get_event(event_id: String) -> Dictionary:
	return _events.get(event_id, {})


func get_all_evidence_ids() -> Array:
	return _evidence.keys()


func get_all_character_ids() -> Array:
	return _characters.keys()


func get_all_location_ids() -> Array:
	return _locations.keys()


func get_all_dialogue_ids() -> Array:
	return _dialogues.keys()


func get_all_chapter_ids() -> Array:
	return _chapters.keys()


func get_all_case_ids() -> Array:
	return _cases.keys()


func get_all_event_ids() -> Array:
	return _events.keys()


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


func get_all_chapters() -> Dictionary:
	return _chapters


func get_all_cases() -> Dictionary:
	return _cases


func get_all_events() -> Dictionary:
	return _events


## Loads every *.json file inside `dir_path`, recursing into subfolders so a
## case can group its files (data/dialogue/case_01/...) without changing how
## anything is looked up. Each file holds either one JSON object with an "id"
## field, or — when `allow_multiple` is true — an array of such objects, which
## lets a single dialogue file group several related trees together. Returns a
## dictionary of all entries keyed by their "id".
func _load_json_dir(dir_path: String, allow_multiple: bool = false) -> Dictionary:
	var result: Dictionary = {}
	# id -> the file it came from, so a duplicate can name both sides.
	var sources: Dictionary = {}
	if DirAccess.open(dir_path) == null:
		push_warning("[ContentDB] content folder not found: %s" % dir_path)
		return result
	_load_json_dir_into(dir_path, allow_multiple, result, sources)
	return result


func _load_json_dir_into(dir_path: String, allow_multiple: bool, result: Dictionary, sources: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[ContentDB] could not open content folder: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := dir_path + "/" + file_name
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_load_json_dir_into(full_path, allow_multiple, result, sources)
		elif file_name.ends_with(".json"):
			_load_json_file(full_path, allow_multiple, result, sources)
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_json_file(file_path: String, allow_multiple: bool, result: Dictionary, sources: Dictionary) -> void:
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
			_store_entry(file_path, entry, result, sources)
	else:
		_store_entry(file_path, data, result, sources)


func _store_entry(file_path: String, entry, result: Dictionary, sources: Dictionary) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("[ContentDB] expected a JSON object in %s" % file_path)
		return
	var entry_id: String = entry.get("id", "")
	if entry_id == "":
		push_error("[ContentDB] entry in %s is missing an \"id\" field" % file_path)
		return
	if result.has(entry_id):
		var message := 'duplicate content id "%s" — defined in both %s and %s (the later one wins)' % [
			entry_id, sources.get(entry_id, "(unknown file)"), file_path,
		]
		_duplicate_id_issues.append(message)
		push_warning("[ContentDB] " + message)
	result[entry_id] = entry
	sources[entry_id] = file_path
