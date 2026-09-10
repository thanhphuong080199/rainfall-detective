extends Node
## Autoload: GameState
##
## Central, story-agnostic runtime state: where the player is, what they've
## found, and what has happened so far. Nothing in this file may reference a
## specific character, location, or piece of evidence by name — flags and
## variables are plain strings supplied entirely by content data, so this
## system stays reusable across every future case.

signal flag_changed(flag_name: String, value: bool)
signal evidence_added(evidence_id: String)
signal evidence_removed(evidence_id: String)
signal location_changed(location_id: String)
signal interaction_seen(key: String)

var current_location: String = ""
var visited_locations: Array[String] = []
var evidence_inventory: Array[String] = []
var flags: Dictionary = {}
var variables: Dictionary = {}

## Generic "has this happened before" set, used for state that isn't a
## simple on/off flag: e.g. "has this topic been talked about", "has this
## examine point been examined", "has this custom milestone occurred".
## Keys are namespaced strings chosen by whoever calls mark_seen() — see
## Investigation (topic:/examine: prefixes) and the "interaction_complete"
## effect (custom: prefix) in dialogue_manager.gd. Never read/written
## directly by content JSON; content only sees it through condition shapes
## like {"examined": "..."} — see condition_evaluator.gd.
var seen_interactions: Array[String] = []


func has_evidence(evidence_id: String) -> bool:
	return evidence_inventory.has(evidence_id)


func add_evidence(evidence_id: String) -> void:
	if has_evidence(evidence_id):
		return
	evidence_inventory.append(evidence_id)
	evidence_added.emit(evidence_id)


func remove_evidence(evidence_id: String) -> void:
	if not has_evidence(evidence_id):
		return
	evidence_inventory.erase(evidence_id)
	evidence_removed.emit(evidence_id)


## Marks `key` as having happened. Returns true the first time (i.e. it was
## newly marked), false if it was already seen — callers that only care
## about the first-time transition (like Investigation) can use the return
## value directly instead of calling has_seen() first.
func mark_seen(key: String) -> bool:
	if seen_interactions.has(key):
		return false
	seen_interactions.append(key)
	interaction_seen.emit(key)
	return true


func has_seen(key: String) -> bool:
	return seen_interactions.has(key)


func get_flag(flag_name: String, default_value: bool = false) -> bool:
	return flags.get(flag_name, default_value)


func set_flag(flag_name: String, value: bool) -> void:
	if flags.get(flag_name, false) == value:
		return
	flags[flag_name] = value
	flag_changed.emit(flag_name, value)


func get_var(var_name: String, default_value = null):
	return variables.get(var_name, default_value)


func set_var(var_name: String, value) -> void:
	variables[var_name] = value


func get_visited_locations() -> Array[String]:
	return visited_locations


func go_to_location(location_id: String) -> void:
	current_location = location_id
	if not visited_locations.has(location_id):
		visited_locations.append(location_id)
	location_changed.emit(location_id)


## Resets all state and applies a case's starting conditions. This is the
## only place "New Game" logic lives — SaveManager.new_game() just calls this.
func start_new_game(case_id: String) -> void:
	var case_data: Dictionary = ContentDB.get_case(case_id)
	if case_data.is_empty():
		push_error("GameState.start_new_game: unknown case '%s'" % case_id)
		return

	evidence_inventory.clear()
	flags.clear()
	variables.clear()
	visited_locations.clear()
	seen_interactions.clear()
	set_var("case_id", case_id)

	var initial_flags: Dictionary = case_data.get("initial_flags", {})
	for flag_name in initial_flags:
		flags[flag_name] = initial_flags[flag_name]

	go_to_location(case_data.get("start_location", ""))


## Plain-data snapshot for SaveManager to serialize. Deliberately has no
## opinion on file format or versioning — that belongs to SaveManager.
func get_save_dict() -> Dictionary:
	return {
		"current_location": current_location,
		"visited_locations": visited_locations,
		"evidence": evidence_inventory,
		"flags": flags,
		"variables": variables,
		"seen_interactions": seen_interactions,
	}


func load_from_dict(data: Dictionary) -> void:
	current_location = data.get("current_location", "")
	visited_locations = []
	visited_locations.assign(data.get("visited_locations", []))
	evidence_inventory = []
	evidence_inventory.assign(data.get("evidence", []))
	flags = (data.get("flags", {}) as Dictionary).duplicate()
	variables = (data.get("variables", {}) as Dictionary).duplicate()
	seen_interactions = []
	seen_interactions.assign(data.get("seen_interactions", []))
	location_changed.emit(current_location)
