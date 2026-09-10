class_name ContentValidator
extends RefCounted
## Stateless helper (like ConditionEvaluator) that cross-checks everything
## ContentDB has already loaded, looking for the kind of mistakes a human or
## an AI coding agent hand-editing JSON is likely to make: a typo'd id, a
## dialogue that references a character that doesn't exist, a variant with
## no fallback, and so on. This is NOT a schema/type validator (ContentDB's
## JSON parser already catches malformed JSON) and it does not try to prove
## a case is completable — see docs/architecture.md for what it deliberately
## does not attempt.
##
## Run automatically by ContentDB._ready() after every load (see
## ContentDB.report() call), and also runnable standalone for a scriptable
## exit code via:
##   godot --headless --path . -s res://scenes/test/validate_content.gd
##
## Findings are split into two severities:
##   errors   — a broken reference; something will push_error/push_warning
##              or silently no-op at runtime when a player reaches it.
##   warnings — a content smell that isn't broken yet but likely should be
##              fixed (e.g. a present_responses list with no generic
##              fallback — see docs/content-guide.md section 7).

static func validate() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	_validate_characters(errors, warnings)
	_validate_evidence(errors, warnings)
	_validate_locations(errors, warnings)
	_validate_dialogues(errors, warnings)
	_validate_cases(errors, warnings)

	return {"errors": errors, "warnings": warnings}


## Prints a validate() result with the "[ContentValidator]" prefix required
## by docs/content-guide.md. Every line is self-contained (prefix included)
## so output stays greppable even when interleaved with other engine output.
static func report(result: Dictionary) -> void:
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])
	for message in errors:
		print("[ContentValidator] ERROR: %s" % message)
	for message in warnings:
		print("[ContentValidator] WARNING: %s" % message)
	print("[ContentValidator] %d error(s), %d warning(s) across %d characters, %d evidence, %d locations, %d dialogue trees, %d cases" % [
		errors.size(), warnings.size(),
		ContentDB.get_all_character_ids().size(), ContentDB.get_all_evidence_ids().size(),
		ContentDB.get_all_location_ids().size(), ContentDB.get_all_dialogue_ids().size(),
		ContentDB.get_all_case_ids().size(),
	])


# ---------------------------------------------------------------------------
# Characters

static func _validate_characters(errors: Array[String], warnings: Array[String]) -> void:
	var characters: Dictionary = ContentDB.get_all_characters()
	for character_id in characters:
		var data: Dictionary = characters[character_id]
		var expressions: Dictionary = data.get("expressions", {})
		if expressions.is_empty():
			warnings.append('Character "%s" has no expressions defined' % character_id)
		elif not expressions.has("normal"):
			warnings.append('Character "%s" has no "normal" expression (used as the fallback when a dialogue node requests an expression it lacks)' % character_id)
		for expression_name in expressions:
			if not _is_hex_color(expressions[expression_name]):
				warnings.append('Character "%s" expression "%s" has an invalid placeholder color "%s"' % [character_id, expression_name, expressions[expression_name]])


# ---------------------------------------------------------------------------
# Evidence

static func _validate_evidence(errors: Array[String], warnings: Array[String]) -> void:
	var all_evidence: Dictionary = ContentDB.get_all_evidence()
	for evidence_id in all_evidence:
		var data: Dictionary = all_evidence[evidence_id]
		var icon_color = data.get("icon_color", "")
		if not _is_hex_color(icon_color):
			warnings.append('Evidence "%s" references missing icon "%s"' % [evidence_id, icon_color])
		if String(data.get("detailed_description", "")).is_empty():
			warnings.append('Evidence "%s" has no detailed_description (shown in the inventory detail panel)' % evidence_id)


# ---------------------------------------------------------------------------
# Locations (npcs / topics / present_responses / examine_points / destinations)

static func _validate_locations(errors: Array[String], warnings: Array[String]) -> void:
	var locations: Dictionary = ContentDB.get_all_locations()
	for location_id in locations:
		var data: Dictionary = locations[location_id]
		_validate_npcs(location_id, data.get("npcs", []), errors, warnings)
		_validate_examine_points(location_id, data.get("examine_points", []), errors, warnings)
		_validate_destinations(location_id, data.get("destinations", []), errors, warnings)


static func _validate_npcs(location_id: String, npcs: Array, errors: Array[String], warnings: Array[String]) -> void:
	for npc in npcs:
		if typeof(npc) != TYPE_DICTIONARY:
			errors.append('Location "%s" has a malformed npc entry' % location_id)
			continue
		var npc_id: String = npc.get("id", "")
		if npc_id == "":
			errors.append('Location "%s" has an npc entry with no "id"' % location_id)
			continue
		if ContentDB.get_character(npc_id).is_empty():
			errors.append('Location "%s" npc "%s" is not a known character' % [location_id, npc_id])

		for topic in npc.get("topics", []):
			if typeof(topic) != TYPE_DICTIONARY:
				errors.append('Location "%s" npc "%s" has a malformed topic entry' % [location_id, npc_id])
				continue
			var topic_id: String = topic.get("id", "")
			var dialogue_id: String = topic.get("dialogue_id", "")
			if dialogue_id == "" or ContentDB.get_dialogue(dialogue_id).is_empty():
				errors.append('Location "%s" npc "%s" topic "%s" references unknown dialogue "%s"' % [location_id, npc_id, topic_id, dialogue_id])
			_validate_condition(topic.get("condition"), 'Location "%s" npc "%s" topic "%s" condition' % [location_id, npc_id, topic_id], errors, location_id)

		var present_responses: Array = npc.get("present_responses", [])
		var has_generic_fallback := false
		for response in present_responses:
			if typeof(response) != TYPE_DICTIONARY:
				errors.append('Location "%s" npc "%s" has a malformed present_response entry' % [location_id, npc_id])
				continue
			var response_evidence_id: String = response.get("evidence_id", "")
			if response_evidence_id == "":
				has_generic_fallback = true
			elif ContentDB.get_evidence(response_evidence_id).is_empty():
				errors.append('Location "%s" npc "%s" present_response references unknown evidence "%s"' % [location_id, npc_id, response_evidence_id])
			var response_dialogue_id: String = response.get("dialogue_id", "")
			if response_dialogue_id == "" or ContentDB.get_dialogue(response_dialogue_id).is_empty():
				errors.append('Location "%s" npc "%s" present_response ("%s") references unknown dialogue "%s"' % [
					location_id, npc_id, response_evidence_id if response_evidence_id != "" else "generic", response_dialogue_id,
				])
		if not present_responses.is_empty() and not has_generic_fallback:
			warnings.append('Location "%s" npc "%s" has present_responses but no generic fallback (add one entry with no "evidence_id") — presenting unrelated evidence will silently do nothing' % [location_id, npc_id])


static func _validate_examine_points(location_id: String, examine_points: Array, errors: Array[String], warnings: Array[String]) -> void:
	for point in examine_points:
		if typeof(point) != TYPE_DICTIONARY:
			errors.append('Location "%s" has a malformed examine_points entry' % location_id)
			continue
		var point_id: String = point.get("id", "")
		var variants: Array = point.get("variants", [])
		if variants.is_empty():
			errors.append('Location "%s" examine point "%s" has no variants' % [location_id, point_id])
			continue
		var has_fallback := false
		for variant in variants:
			if typeof(variant) != TYPE_DICTIONARY:
				errors.append('Location "%s" examine point "%s" has a malformed variant' % [location_id, point_id])
				continue
			if not variant.has("condition"):
				has_fallback = true
			var dialogue_id: String = variant.get("dialogue_id", "")
			if dialogue_id == "" or ContentDB.get_dialogue(dialogue_id).is_empty():
				errors.append('Location "%s" examine point "%s" variant references unknown dialogue "%s"' % [location_id, point_id, dialogue_id])
			_validate_condition(variant.get("condition"), 'Location "%s" examine point "%s" variant condition' % [location_id, point_id], errors, location_id)
		if not has_fallback:
			warnings.append('Location "%s" examine point "%s" has no unconditional fallback variant (add one entry with no "condition")' % [location_id, point_id])


static func _validate_destinations(location_id: String, destinations: Array, errors: Array[String], warnings: Array[String]) -> void:
	for destination in destinations:
		if typeof(destination) != TYPE_DICTIONARY:
			errors.append('Location "%s" has a malformed destinations entry' % location_id)
			continue
		var destination_id: String = destination.get("location_id", "")
		if destination_id == "" or ContentDB.get_location(destination_id).is_empty():
			errors.append('Location "%s" destination references unknown location "%s"' % [location_id, destination_id])
		_validate_condition(destination.get("condition"), 'Location "%s" destination "%s" condition' % [location_id, destination_id], errors, location_id)


## Checks the id references inside a condition (has_evidence / visited_location
## / examined) against what ContentDB actually has. `context` is a full,
## already-formatted human-readable description of where this condition came
## from (the caller decides the exact wording). `examined_scope_location_id`
## is the location {"examined": "point_id"} should resolve against — pass ""
## when there isn't one (e.g. a dialogue choice condition can be triggered
## from any location that references that dialogue tree, so there's no
## single location to check "examined" against; that check is skipped, not
## treated as an error). `flag` and `interaction_complete` are free-form,
## author-chosen ids with nothing to check them against, so they're skipped
## unconditionally.
static func _validate_condition(condition, context: String, errors: Array[String], examined_scope_location_id: String = "") -> void:
	if condition == null or typeof(condition) != TYPE_DICTIONARY:
		return
	if condition.has("all"):
		for sub_condition in condition.get("all", []):
			_validate_condition(sub_condition, context, errors, examined_scope_location_id)
		return
	if condition.has("any"):
		for sub_condition in condition.get("any", []):
			_validate_condition(sub_condition, context, errors, examined_scope_location_id)
		return
	if condition.has("not"):
		_validate_condition(condition.get("not"), context, errors, examined_scope_location_id)
		return
	if condition.has("has_evidence"):
		var evidence_id: String = condition.get("has_evidence", "")
		if ContentDB.get_evidence(evidence_id).is_empty():
			errors.append('%s references unknown evidence "%s"' % [context, evidence_id])
	if condition.has("visited_location"):
		var visited_id: String = condition.get("visited_location", "")
		if ContentDB.get_location(visited_id).is_empty():
			errors.append('%s references unknown location "%s"' % [context, visited_id])
	if condition.has("examined") and examined_scope_location_id != "":
		var point_id: String = condition.get("examined", "")
		if not _location_has_examine_point(examined_scope_location_id, point_id):
			errors.append('%s references unknown examine point "%s"' % [context, point_id])


static func _location_has_examine_point(location_id: String, point_id: String) -> bool:
	for point in ContentDB.get_location(location_id).get("examine_points", []):
		if typeof(point) == TYPE_DICTIONARY and point.get("id", "") == point_id:
			return true
	return false


# ---------------------------------------------------------------------------
# Dialogue trees

static func _validate_dialogues(errors: Array[String], warnings: Array[String]) -> void:
	var dialogues: Dictionary = ContentDB.get_all_dialogues()
	for dialogue_id in dialogues:
		var tree: Dictionary = dialogues[dialogue_id]
		var nodes: Dictionary = tree.get("nodes", {})
		var start_id = tree.get("start", "")
		if start_id == "" or not nodes.has(start_id):
			errors.append('Dialogue "%s" start node "%s" does not exist' % [dialogue_id, start_id])

		for node_id in nodes:
			var node = nodes[node_id]
			if typeof(node) != TYPE_DICTIONARY:
				errors.append('Dialogue "%s" node "%s" is not an object' % [dialogue_id, node_id])
				continue
			_validate_dialogue_node(dialogue_id, node_id, node, nodes, errors, warnings)


static func _validate_dialogue_node(dialogue_id: String, node_id, node: Dictionary, nodes: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var speaker: String = node.get("speaker", "")
	var character: Dictionary = {}
	if speaker != "":
		character = ContentDB.get_character(speaker)
		if character.is_empty():
			errors.append('Dialogue "%s" node "%s" references unknown character "%s"' % [dialogue_id, node_id, speaker])

	var expression: String = node.get("expression", "")
	if speaker != "" and not character.is_empty() and expression != "":
		var expressions: Dictionary = character.get("expressions", {})
		if not expressions.is_empty() and not expressions.has(expression):
			errors.append('Dialogue "%s" node "%s" references unknown expression "%s" for character "%s"' % [dialogue_id, node_id, expression, speaker])

	_validate_actions(node.get("actions", []), dialogue_id, node_id, "", errors, warnings)

	var next_id = node.get("next")
	if next_id != null and String(next_id) != "" and not nodes.has(next_id):
		errors.append('Dialogue "%s" node "%s" next references unknown node "%s"' % [dialogue_id, node_id, next_id])

	var choices: Array = node.get("choices", [])
	for i in choices.size():
		var choice = choices[i]
		if typeof(choice) != TYPE_DICTIONARY:
			errors.append('Dialogue "%s" node "%s" choice %d is not an object' % [dialogue_id, node_id, i])
			continue
		_validate_actions(choice.get("actions", []), dialogue_id, node_id, "choice %d " % i, errors, warnings)
		var choice_next = choice.get("next")
		if choice_next != null and String(choice_next) != "" and not nodes.has(choice_next):
			errors.append('Dialogue "%s" node "%s" choice %d next references unknown node "%s"' % [dialogue_id, node_id, i, choice_next])
		_validate_condition(choice.get("condition"), 'Dialogue "%s" node "%s" choice %d condition' % [dialogue_id, node_id, i], errors)


static func _validate_actions(actions, dialogue_id: String, node_id, prefix: String, errors: Array[String], warnings: Array[String]) -> void:
	if typeof(actions) != TYPE_ARRAY:
		return
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			errors.append('Dialogue "%s" node "%s" %shas a malformed action' % [dialogue_id, node_id, prefix])
			continue
		var action_type: String = action.get("type", "")
		match action_type:
			"set_flag":
				if String(action.get("flag", "")).is_empty():
					errors.append('Dialogue "%s" node "%s" %saction "set_flag" is missing "flag"' % [dialogue_id, node_id, prefix])
			"add_evidence", "remove_evidence":
				var evidence_id: String = action.get("evidence_id", "")
				if evidence_id == "" or ContentDB.get_evidence(evidence_id).is_empty():
					errors.append('Dialogue "%s" node "%s" %saction "%s" references unknown evidence "%s"' % [dialogue_id, node_id, prefix, action_type, evidence_id])
			"mark_interaction_complete":
				if String(action.get("id", "")).is_empty():
					errors.append('Dialogue "%s" node "%s" %saction "mark_interaction_complete" is missing "id"' % [dialogue_id, node_id, prefix])
			"":
				errors.append('Dialogue "%s" node "%s" %shas an action with no "type"' % [dialogue_id, node_id, prefix])
			_:
				warnings.append('Dialogue "%s" node "%s" %shas an action with unknown type "%s"' % [dialogue_id, node_id, prefix, action_type])


# ---------------------------------------------------------------------------
# Cases

static func _validate_cases(errors: Array[String], warnings: Array[String]) -> void:
	var cases: Dictionary = ContentDB.get_all_cases()
	for case_id in cases:
		var data: Dictionary = cases[case_id]
		var start_location: String = data.get("start_location", "")
		if start_location == "" or ContentDB.get_location(start_location).is_empty():
			errors.append('Case "%s" start_location "%s" is not a known location' % [case_id, start_location])
		if typeof(data.get("initial_flags", {})) != TYPE_DICTIONARY:
			errors.append('Case "%s" initial_flags must be an object' % case_id)


# ---------------------------------------------------------------------------

static func _is_hex_color(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if not text.begins_with("#") or (text.length() != 7 and text.length() != 9):
		return false
	return text.substr(1).is_valid_hex_number()
