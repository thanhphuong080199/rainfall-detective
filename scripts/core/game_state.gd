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
## examine point been examined", "has this custom milestone occurred", "has
## this event already triggered". Keys are namespaced strings chosen by
## whoever calls mark_seen() — see Investigation (topic:/examine: prefixes),
## the "mark_interaction_complete" effect (custom: prefix) in
## effect_runner.gd, and EventManager (event: prefix, for a "once" event's
## triggered state). Never read/written directly by content JSON; content
## only sees it through condition shapes like {"examined": "..."} — see
## condition_evaluator.gd.
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


## Developer-only (Milestone 1.8 Case Debugger): removes `key` from
## seen_interactions if present. No normal gameplay path ever calls this —
## mark_seen() is a one-way "this happened" record everywhere else in this
## project. See EventManager.debug_reset_trigger(), the only caller, for why
## it exists and exactly what it does and does not undo: clearing a "seen"
## marker never undoes an Effect that already ran because of it. Returns
## false (a no-op) if the key wasn't present.
func unmark_seen(key: String) -> bool:
	if not seen_interactions.has(key):
		return false
	seen_interactions.erase(key)
	return true


## Flags are always booleans. A non-boolean can only get in through content
## data (a case's initial_flags) or a hand-edited save, so it is reported
## loudly and treated as `default_value` rather than crashing the getter's
## declared return type — ContentValidator rejects the content-side case up
## front, this is the runtime backstop.
func get_flag(flag_name: String, default_value: bool = false) -> bool:
	if not flags.has(flag_name):
		return default_value
	var value = flags[flag_name]
	if typeof(value) != TYPE_BOOL:
		push_error("GameState.get_flag: flag '%s' holds a non-boolean value (%s) — treating it as %s" % [flag_name, value, default_value])
		return default_value
	return value


## Always records the flag, even when the value is unchanged, so that a flag
## explicitly set to false still shows up in GameState.flags (the debug
## panel lists it, and a save round-trips it). The signal, on the other
## hand, still only fires when the effective value actually changed — UI
## refreshes hang off it.
func set_flag(flag_name: String, value: bool) -> void:
	var previous: bool = get_flag(flag_name)
	flags[flag_name] = value
	if previous != value:
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

	_assign_flags(case_data.get("initial_flags", {}), "case '%s' initial_flags" % case_id)

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
	flags = {}
	_assign_flags(data.get("flags", {}), "save file")
	variables = (data.get("variables", {}) as Dictionary).duplicate()
	seen_interactions = []
	seen_interactions.assign(data.get("seen_interactions", []))
	location_changed.emit(current_location)


## Copies boolean flags out of a plain dictionary (a case's initial_flags, or
## a save file's flag block) into `flags`, skipping and reporting anything
## that isn't a bool. `source_description` only appears in the error message.
func _assign_flags(source, source_description: String) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		push_error("GameState: %s is not an object — no flags applied" % source_description)
		return
	for flag_name in source:
		var value = source[flag_name]
		if typeof(value) != TYPE_BOOL:
			push_error("GameState: %s flag '%s' is not a boolean (%s) — ignoring it" % [source_description, flag_name, value])
			continue
		flags[flag_name] = value
