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
##
## Also validates data/events/*.json (see docs/event-system.md) — an event's
## "conditions" and "effects" reuse the exact same checks (_validate_condition,
## _validate_effects) dialogue/topic/destination conditions and dialogue
## actions already go through, plus a couple of event-specific checks
## (unknown trigger_policy, a repeatable event that can't self-reset).

static func validate() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	_validate_duplicate_ids(errors)
	_validate_characters(errors, warnings)
	_validate_evidence(errors, warnings)
	_validate_locations(errors, warnings)
	_validate_dialogues(errors, warnings)
	_validate_chapters(errors, warnings)
	_validate_cases(errors, warnings)
	_validate_events(errors, warnings)

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
	print("[ContentValidator] %d error(s), %d warning(s) across %d characters, %d evidence, %d locations, %d dialogue trees, %d chapters, %d cases, %d events" % [
		errors.size(), warnings.size(),
		ContentDB.get_all_character_ids().size(), ContentDB.get_all_evidence_ids().size(),
		ContentDB.get_all_location_ids().size(), ContentDB.get_all_dialogue_ids().size(),
		ContentDB.get_all_chapter_ids().size(), ContentDB.get_all_case_ids().size(), ContentDB.get_all_event_ids().size(),
	])


# ---------------------------------------------------------------------------
# Duplicate ids

## Two content files that declare the same id inside one category: the later
## one silently replaces the earlier, so every reference to that id now
## resolves to content the author never intended. ContentDB is the only place
## that can see this happen (see its get_duplicate_id_issues()).
static func _validate_duplicate_ids(errors: Array[String]) -> void:
	for message in ContentDB.get_duplicate_id_issues():
		errors.append(message)


## Reports ids that repeat inside a single list (npcs in a location, topics on
## an NPC, examine points, destinations). Every lookup for these is
## first-match-wins, so a duplicate makes the second entry permanently
## unreachable. Also catches entries with a missing/blank id, which collide
## with each other the same way.
static func _validate_unique_ids(entries: Array, id_key: String, context: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_id: String = str(entry.get(id_key, ""))
		if entry_id == "":
			errors.append('%s has an entry with no "%s"' % [context, id_key])
			continue
		if seen.has(entry_id):
			errors.append('%s defines "%s" more than once — only the first one is ever reachable' % [context, entry_id])
		seen[entry_id] = true


# ---------------------------------------------------------------------------
# Characters

static func _validate_characters(errors: Array[String], warnings: Array[String]) -> void:
	var characters: Dictionary = ContentDB.get_all_characters()
	for character_id in characters:
		var data: Dictionary = characters[character_id]
		_validate_translatable(data.get("name", ""), 'Character "%s" name' % character_id, errors)
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
		_validate_translatable(data.get("name", ""), 'Evidence "%s" name' % evidence_id, errors)
		_validate_translatable(data.get("short_description", ""), 'Evidence "%s" short_description' % evidence_id, errors)
		_validate_translatable(data.get("detailed_description", ""), 'Evidence "%s" detailed_description' % evidence_id, errors)


# ---------------------------------------------------------------------------
# Locations (npcs / topics / present_responses / examine_points / destinations)

static func _validate_locations(errors: Array[String], warnings: Array[String]) -> void:
	var locations: Dictionary = ContentDB.get_all_locations()
	for location_id in locations:
		var data: Dictionary = locations[location_id]
		_validate_translatable(data.get("name", ""), 'Location "%s" name' % location_id, errors)
		var npcs: Array = data.get("npcs", [])
		var examine_points: Array = data.get("examine_points", [])
		var destinations: Array = data.get("destinations", [])
		_validate_unique_ids(npcs, "id", 'Location "%s" npcs' % location_id, errors)
		_validate_unique_ids(examine_points, "id", 'Location "%s" examine_points' % location_id, errors)
		_validate_unique_ids(destinations, "location_id", 'Location "%s" destinations' % location_id, errors)
		_validate_npcs(location_id, npcs, errors, warnings)
		_validate_examine_points(location_id, examine_points, errors, warnings)
		_validate_destinations(location_id, destinations, errors, warnings)


static func _validate_npcs(location_id: String, npcs: Array, errors: Array[String], warnings: Array[String]) -> void:
	for npc in npcs:
		if typeof(npc) != TYPE_DICTIONARY:
			errors.append('Location "%s" has a malformed npc entry' % location_id)
			continue
		var npc_id: String = npc.get("id", "")
		if npc_id == "":
			# Already reported by _validate_unique_ids above; just skip it
			# here rather than printing the same problem twice.
			continue
		if ContentDB.get_character(npc_id).is_empty():
			errors.append('Location "%s" npc "%s" is not a known character' % [location_id, npc_id])
		_validate_condition(npc.get("condition"), 'Location "%s" npc "%s" presence condition' % [location_id, npc_id], errors, location_id)

		_validate_unique_ids(npc.get("topics", []), "id", 'Location "%s" npc "%s" topics' % [location_id, npc_id], errors)
		for topic in npc.get("topics", []):
			if typeof(topic) != TYPE_DICTIONARY:
				errors.append('Location "%s" npc "%s" has a malformed topic entry' % [location_id, npc_id])
				continue
			var topic_id: String = topic.get("id", "")
			var dialogue_id: String = topic.get("dialogue_id", "")
			if dialogue_id == "" or ContentDB.get_dialogue(dialogue_id).is_empty():
				errors.append('Location "%s" npc "%s" topic "%s" references unknown dialogue "%s"' % [location_id, npc_id, topic_id, dialogue_id])
			_validate_condition(topic.get("condition"), 'Location "%s" npc "%s" topic "%s" condition' % [location_id, npc_id, topic_id], errors, location_id)
			_validate_translatable(topic.get("label", ""), 'Location "%s" npc "%s" topic "%s" label' % [location_id, npc_id, topic_id], errors)

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
		if present_responses.is_empty():
			warnings.append('Location "%s" npc "%s" has no present_responses at all — presenting any evidence to them does nothing at all, with no dialogue and no feedback (add at least a generic entry with no "evidence_id")' % [location_id, npc_id])
		elif not has_generic_fallback:
			warnings.append('Location "%s" npc "%s" has present_responses but no generic fallback (add one entry with no "evidence_id") — presenting unrelated evidence will silently do nothing' % [location_id, npc_id])


static func _validate_examine_points(location_id: String, examine_points: Array, errors: Array[String], warnings: Array[String]) -> void:
	for point in examine_points:
		if typeof(point) != TYPE_DICTIONARY:
			errors.append('Location "%s" has a malformed examine_points entry' % location_id)
			continue
		var point_id: String = point.get("id", "")
		_validate_translatable(point.get("label", ""), 'Location "%s" examine point "%s" label' % [location_id, point_id], errors)
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
		_validate_translatable(destination.get("label", ""), 'Location "%s" destination "%s" label' % [location_id, destination_id], errors)


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

	# The important one, checked before anything else so it covers every
	# shape: ConditionEvaluator only understands a fixed set of keys and
	# treats anything else as false (fail closed), so a typo like
	# {"has_evidnce": "..."} would leave content permanently locked with no
	# other symptom. An empty {} is the same trap with nothing to name.
	if condition.is_empty():
		errors.append("%s is an empty object, which is never true — omit it instead" % context)
	for key in condition:
		if not ConditionEvaluator.KEYS.has(key) and key != "equals":
			errors.append('%s uses unknown key "%s" — supported keys are %s' % [context, key, ", ".join(ConditionEvaluator.KEYS)])

	# evaluate() checks its shapes in a fixed order and returns on the first
	# match, so {"flag": "a", "has_evidence": "b"} silently ignores the
	# has_evidence half — one condition object holds exactly one check.
	# ConditionEvaluator.KEYS is in that same precedence order, so walking it
	# (rather than the object's own key order) names the check that would
	# actually win.
	var present: Array[String] = []
	for key in ConditionEvaluator.KEYS:
		if condition.has(key):
			present.append(key)
	if present.size() > 1:
		errors.append('%s combines %s in one object, but evaluate() would only check "%s" — wrap them in {"all": [...]} instead' % [
			context, ", ".join(present), present[0],
		])

	if condition.has("all") or condition.has("any"):
		var key: String = "all" if condition.has("all") else "any"
		var sub_conditions = condition.get(key)
		if typeof(sub_conditions) != TYPE_ARRAY:
			errors.append('%s "%s" must be an array of conditions' % [context, key])
			return
		if sub_conditions.is_empty():
			errors.append('%s "%s" is empty' % [context, key])
		for sub_condition in sub_conditions:
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

		_validate_dialogue_reachability(dialogue_id, tree, warnings)


## Walks the tree from its start node and reports anything it can't get to.
## An orphaned node is almost always a typo in some other node's "next" — the
## dialogue still runs, it just quietly skips content the author wrote. Only a
## warning: an author mid-edit may legitimately have a node not wired up yet.
static func _validate_dialogue_reachability(dialogue_id: String, tree: Dictionary, warnings: Array[String]) -> void:
	var nodes: Dictionary = tree.get("nodes", {})
	var start_id = tree.get("start", "")
	if not nodes.has(start_id):
		return  # Already reported as an error; nothing to walk from.

	var reachable: Dictionary = {}
	var pending: Array = [start_id]
	while not pending.is_empty():
		var node_id = pending.pop_back()
		if reachable.has(node_id):
			continue
		reachable[node_id] = true
		var node = nodes.get(node_id)
		if typeof(node) != TYPE_DICTIONARY:
			continue
		for next_id in _node_exits(node):
			if nodes.has(next_id) and not reachable.has(next_id):
				pending.append(next_id)

	for node_id in nodes:
		if not reachable.has(node_id):
			warnings.append('Dialogue "%s" node "%s" is unreachable — nothing points at it (typo in a "next"?)' % [dialogue_id, node_id])


## Every node id this node can lead to: its own "next" plus each choice's.
## A choice node's own "next" counts too — DialogueManager falls back to it
## when every choice is filtered out by its condition.
static func _node_exits(node: Dictionary) -> Array:
	var exits: Array = []
	var next_id = node.get("next")
	if next_id != null and String(next_id) != "":
		exits.append(next_id)
	for choice in node.get("choices", []):
		if typeof(choice) != TYPE_DICTIONARY:
			continue
		var choice_next = choice.get("next")
		if choice_next != null and String(choice_next) != "":
			exits.append(choice_next)
	return exits


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

	_validate_effects(node.get("actions", []), 'Dialogue "%s" node "%s"' % [dialogue_id, node_id], errors, warnings)
	_validate_translatable(node.get("text", ""), 'Dialogue "%s" node "%s" text' % [dialogue_id, node_id], errors)

	var next_id = node.get("next")
	if next_id != null and String(next_id) != "" and not nodes.has(next_id):
		errors.append('Dialogue "%s" node "%s" next references unknown node "%s"' % [dialogue_id, node_id, next_id])

	var choices: Array = node.get("choices", [])
	for i in choices.size():
		var choice = choices[i]
		if typeof(choice) != TYPE_DICTIONARY:
			errors.append('Dialogue "%s" node "%s" choice %d is not an object' % [dialogue_id, node_id, i])
			continue
		_validate_effects(choice.get("actions", []), 'Dialogue "%s" node "%s" choice %d' % [dialogue_id, node_id, i], errors, warnings)
		var choice_next = choice.get("next")
		if choice_next != null and String(choice_next) != "" and not nodes.has(choice_next):
			errors.append('Dialogue "%s" node "%s" choice %d next references unknown node "%s"' % [dialogue_id, node_id, i, choice_next])
		_validate_condition(choice.get("condition"), 'Dialogue "%s" node "%s" choice %d condition' % [dialogue_id, node_id, i], errors)
		_validate_translatable(choice.get("text", ""), 'Dialogue "%s" node "%s" choice %d text' % [dialogue_id, node_id, i], errors)


## Validates a list of effect dictionaries — the one shared vocabulary both
## dialogue "actions" and event "effects" use (see EffectRunner). `context`
## is a full, pre-formatted description of where this list came from,
## exactly like _validate_condition()'s `context` parameter.
static func _validate_effects(effects, context: String, errors: Array[String], warnings: Array[String]) -> void:
	if typeof(effects) != TYPE_ARRAY:
		return
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			errors.append('%s has a malformed effect' % context)
			continue
		var effect_type: String = effect.get("type", "")
		match effect_type:
			"set_flag":
				if String(effect.get("flag", "")).is_empty():
					errors.append('%s effect "set_flag" is missing "flag"' % context)
				if effect.has("value") and typeof(effect.get("value")) != TYPE_BOOL:
					errors.append('%s effect "set_flag" value must be true or false, got %s' % [context, effect.get("value")])
			"add_evidence", "remove_evidence":
				var evidence_id: String = effect.get("evidence_id", "")
				if evidence_id == "" or ContentDB.get_evidence(evidence_id).is_empty():
					errors.append('%s effect "%s" references unknown evidence "%s"' % [context, effect_type, evidence_id])
			"mark_interaction_complete":
				if String(effect.get("id", "")).is_empty():
					errors.append('%s effect "mark_interaction_complete" is missing "id"' % context)
			"":
				errors.append('%s has an effect with no "type"' % context)
			_:
				warnings.append('%s has an effect with unknown type "%s" — supported types are %s' % [context, effect_type, ", ".join(EffectRunner.KNOWN_TYPES)])


# ---------------------------------------------------------------------------
# Cases

static func _validate_cases(errors: Array[String], warnings: Array[String]) -> void:
	var cases: Dictionary = ContentDB.get_all_cases()
	for case_id in cases:
		var data: Dictionary = cases[case_id]
		var start_location: String = data.get("start_location", "")
		if start_location == "" or ContentDB.get_location(start_location).is_empty():
			errors.append('Case "%s" start_location "%s" is not a known location' % [case_id, start_location])
		_validate_translatable(data.get("display_name", data.get("title", "")), 'Case "%s" display_name' % case_id, errors)
		if data.has("description"):
			_validate_translatable(data.get("description", ""), 'Case "%s" description' % case_id, errors)
		var initial_flags = data.get("initial_flags", {})
		if typeof(initial_flags) != TYPE_DICTIONARY:
			errors.append('Case "%s" initial_flags must be an object' % case_id)
		else:
			for flag_name in initial_flags:
				if typeof(initial_flags[flag_name]) != TYPE_BOOL:
					errors.append('Case "%s" initial flag "%s" must be true or false, got %s' % [case_id, flag_name, initial_flags[flag_name]])
		_validate_case_chapters(case_id, data, errors)


## Chapter fields are entirely opt-in — a case with no (or an empty)
## "chapters" array is a flat/legacy case (case_00_sandbox) and is skipped
## here completely, so this adds zero validation noise for existing content.
## See docs/case-system.md, "Content validation".
static func _validate_case_chapters(case_id: String, data: Dictionary, errors: Array[String]) -> void:
	var chapters = data.get("chapters", [])
	if typeof(chapters) != TYPE_ARRAY or chapters.is_empty():
		return

	# Only ids that are both known chapters AND declared by this case — used
	# below so a next_chapter pointing at a real chapter that just isn't
	# *this* case's is still flagged (catches a chapter reused/misrouted
	# across cases).
	var declared: Dictionary = {}
	for raw_chapter_id in chapters:
		var chapter_id: String = String(raw_chapter_id)
		if ContentDB.get_chapter(chapter_id).is_empty():
			errors.append('Case "%s" chapters references unknown chapter "%s"' % [case_id, chapter_id])
			continue
		declared[chapter_id] = true

	var starting_chapter: String = data.get("starting_chapter", "")
	if starting_chapter == "":
		errors.append('Case "%s" declares chapters but has no starting_chapter' % case_id)
	elif not declared.has(starting_chapter):
		errors.append('Case "%s" starting_chapter "%s" is not in its own chapters list' % [case_id, starting_chapter])
	else:
		_validate_chapter_chain(case_id, starting_chapter, declared, errors)


## Walks next_chapter from starting_chapter, bounded by the case's own
## declared chapter count — catches an obvious transition cycle and a
## next_chapter that leaks outside this case's chapters list. Not a proof
## every chapter is reachable or that the case is completable (a chapter
## listed in "chapters" but never pointed at by any next_chapter is
## legitimate mid-authoring) — same stance ContentValidator already takes on
## unreferenced dialogue, see docs/architecture.md's "Known limitations".
static func _validate_chapter_chain(case_id: String, starting_chapter: String, declared: Dictionary, errors: Array[String]) -> void:
	var visited: Dictionary = {}
	var current: String = starting_chapter
	var steps := 0
	var max_steps: int = declared.size() + 1
	while current != "" and steps <= max_steps:
		if visited.has(current):
			errors.append('Case "%s" has a chapter transition cycle starting at "%s"' % [case_id, current])
			return
		visited[current] = true
		steps += 1
		var next_chapter: String = ContentDB.get_chapter(current).get("next_chapter", "")
		if next_chapter == "":
			return
		if not declared.has(next_chapter):
			errors.append('Case "%s" chapter "%s" next_chapter "%s" is not in this case\'s chapters list' % [case_id, current, next_chapter])
			return
		current = next_chapter


# ---------------------------------------------------------------------------
# Chapters

## Validates every loaded chapter's own fields (entry_effects, and the
## chapter/event references a case can't check on its behalf, since those
## are meaningful independent of which case — if any — currently lists this
## chapter). See docs/case-system.md.
static func _validate_chapters(errors: Array[String], warnings: Array[String]) -> void:
	var chapters: Dictionary = ContentDB.get_all_chapters()
	for chapter_id in chapters:
		var data: Dictionary = chapters[chapter_id]
		_validate_effects(data.get("entry_effects", []), 'Chapter "%s" entry_effects' % chapter_id, errors, warnings)
		_validate_translatable(data.get("display_name", ""), 'Chapter "%s" display_name' % chapter_id, errors)

		var completion_event: String = data.get("completion_event", "")
		if completion_event != "":
			var event: Dictionary = ContentDB.get_event(completion_event)
			if event.is_empty():
				errors.append('Chapter "%s" completion_event references unknown event "%s"' % [chapter_id, completion_event])
			elif event.get("trigger_policy", "once") == "repeatable":
				warnings.append('Chapter "%s" completion_event "%s" is "repeatable" — a chapter should only complete once, use "once"' % [chapter_id, completion_event])

		var next_chapter: String = data.get("next_chapter", "")
		if next_chapter != "" and ContentDB.get_chapter(next_chapter).is_empty():
			errors.append('Chapter "%s" next_chapter references unknown chapter "%s"' % [chapter_id, next_chapter])


# ---------------------------------------------------------------------------
# Events

const KNOWN_TRIGGER_POLICIES := ["once", "repeatable"]

static func _validate_events(errors: Array[String], warnings: Array[String]) -> void:
	var events: Dictionary = ContentDB.get_all_events()
	for event_id in events:
		var data: Dictionary = events[event_id]

		var policy: String = data.get("trigger_policy", "once")
		if not KNOWN_TRIGGER_POLICIES.has(policy):
			errors.append('Event "%s" has unknown trigger_policy "%s" — supported values are %s' % [event_id, policy, ", ".join(KNOWN_TRIGGER_POLICIES)])

		# No examined_scope_location_id: an event isn't scoped to one fixed
		# location the way an examine-point variant is, so {"examined": ...}
		# can't be checked against a specific location's points here — same
		# reasoning _validate_dialogue_node uses for a choice condition. See
		# docs/event-system.md for why {"examined": ...} in an event
		# condition is best avoided anyway (it resolves against whatever the
		# player's *current* location happens to be at evaluation time).
		_validate_condition(data.get("conditions"), 'Event "%s" conditions' % event_id, errors)

		var effects: Array = data.get("effects", [])
		if effects.is_empty():
			warnings.append('Event "%s" has no effects — triggering it will do nothing' % event_id)
		_validate_effects(effects, 'Event "%s"' % event_id, errors, warnings)

		if policy == "repeatable":
			_validate_repeatable_self_reset(event_id, data.get("conditions"), effects, warnings)


## Cheap, best-effort "obvious self-reference" check — not a general proof
## (see docs/architecture.md's Content validation section on why this
## project doesn't attempt that). A repeatable event whose own effects set
## the exact same flag/value its own top-level condition (or a direct
## sub-condition of a top-level "all") requires can never see that condition
## go false again on its own, so in practice it will only ever fire once —
## almost certainly not what "repeatable" was meant to do. Only "flag" leaves
## are checked (the only leaf set_flag can actually affect); "any"/"not"
## branches are skipped since there's no longer one single required value to
## compare against there.
static func _validate_repeatable_self_reset(event_id: String, conditions, effects: Array, warnings: Array[String]) -> void:
	var required: Dictionary = {}
	_collect_flag_requirements(conditions, required)
	if required.is_empty():
		return
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY or effect.get("type", "") != "set_flag":
			continue
		var flag_name: String = effect.get("flag", "")
		if required.has(flag_name) and effect.get("value", true) == required[flag_name]:
			warnings.append('Event "%s" is repeatable but its effects set flag "%s" to the same value its own conditions require — that condition can never go false again on its own, so this event will likely only ever fire once in practice' % [event_id, flag_name])


## Collects {flag_name: required_bool} for every direct "flag" leaf reachable
## through a top-level condition or a nested "all".
static func _collect_flag_requirements(condition, out: Dictionary) -> void:
	if typeof(condition) != TYPE_DICTIONARY:
		return
	if condition.has("flag"):
		out[condition.get("flag", "")] = condition.get("equals", true)
		return
	if condition.has("all"):
		var sub_conditions = condition.get("all")
		if typeof(sub_conditions) == TYPE_ARRAY:
			for sub_condition in sub_conditions:
				_collect_flag_requirements(sub_condition, out)


# ---------------------------------------------------------------------------

static func _is_hex_color(value) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if not text.begins_with("#") or (text.length() != 7 and text.length() != 9):
		return false
	return text.substr(1).is_valid_hex_number()


# ---------------------------------------------------------------------------
# Localization (see docs/localization.md)

## Every player-facing content field (name/label/text/display_name/
## description) is authored as a translation key resolved through
## LocaleManager's registered Translation objects, not literal text. A key
## missing from a supported locale is checked directly against that
## locale's own Translation object — never via tr()/TranslationServer.translate(),
## which would silently succeed through the configured fallback locale
## (locale/fallback="en" in project.godot) and hide a missing "vi" message
## behind whatever "en" happens to say. `key` may be a Variant (most callers
## pass a dict.get(field, "") result straight through) since a missing field
## is already reported elsewhere as its own error — this only checks keys
## that are actually present.
static func _validate_translatable(key, context: String, errors: Array[String]) -> void:
	if typeof(key) != TYPE_STRING or key == "":
		return
	for locale in LocaleManager.SUPPORTED_LOCALES:
		var translation: Translation = TranslationServer.get_translation_object(locale)
		if translation == null or translation.get_message(key) == "":
			errors.append('%s ("%s") has no "%s" translation — add it to localization/strings.csv' % [context, key, locale])
