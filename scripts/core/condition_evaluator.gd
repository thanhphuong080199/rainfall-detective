class_name ConditionEvaluator
extends RefCounted
## Stateless helper for evaluating the small condition mini-language used
## throughout content JSON (dialogue choices, examine/present variants,
## talk topics, move destinations). Not an autoload — just a static toolbox.
##
## Supported shapes:
##   null                                    -> always true
##   {"flag": "name"}                        -> GameState.get_flag("name") == true
##   {"flag": "name", "equals": false}       -> GameState.get_flag("name") == false
##   {"has_evidence": "evidence_id"}         -> GameState.has_evidence("evidence_id")
##   {"visited_location": "location_id"}     -> that location has been entered at least once
##   {"examined": "point_id"}                -> the CURRENT location's examine point with
##                                               this id has already been examined once
##                                               (see Investigation.examine())
##   {"interaction_complete": "id"}          -> a "mark_interaction_complete" effect with
##                                               this id has fired (see dialogue_manager.gd)
##   {"all": [condition, condition, ...]}    -> every sub-condition is true
##   {"any": [condition, condition, ...]}    -> at least one sub-condition is true
##   {"not": condition}                      -> the sub-condition is false
##
## Deliberately NOT a general-purpose expression language: every shape above
## is a fixed, named check against GameState, not an arbitrary boolean
## expression string. Add a new leaf shape here (not a new operator) if a
## future case needs a new kind of check — and add it to KEYS below plus
## ContentValidator's whitelist at the same time, or authors will get a
## validation error for using it.
##
## Anything not on that list evaluates to FALSE ("fail closed"). A typo like
## {"has_evidnce": "..."} is the single most likely authoring mistake in this
## format, and content that stays locked is a bug you notice immediately,
## whereas content that silently unlocks itself from the start of the case is
## a bug you notice weeks later. ContentValidator rejects unknown keys
## outright so this runtime behaviour should never actually be reached.

## Every key evaluate() understands, split by kind. ContentValidator reads
## these so the two can't drift apart: KEYS is the whitelist for "is this key
## even a thing", LEAF_KEYS is what it uses to reject a condition that stacks
## two leaf checks in one object (evaluate() honours only the first, so those
## have to be written as an explicit {"all": [...]}).
const COMPOSITE_KEYS := ["all", "any", "not"]
const LEAF_KEYS := ["flag", "has_evidence", "visited_location", "examined", "interaction_complete"]
const KEYS := COMPOSITE_KEYS + LEAF_KEYS


static func evaluate(condition) -> bool:
	if condition == null:
		return true
	if typeof(condition) != TYPE_DICTIONARY:
		push_warning("ConditionEvaluator: condition must be a Dictionary or null, got: %s" % [condition])
		return false

	if condition.has("all"):
		var all_list = condition.get("all")
		if typeof(all_list) != TYPE_ARRAY:
			push_warning("ConditionEvaluator: \"all\" must be an array, got: %s" % [all_list])
			return false
		for sub_condition in all_list:
			if not evaluate(sub_condition):
				return false
		return true

	if condition.has("any"):
		var any_list = condition.get("any")
		if typeof(any_list) != TYPE_ARRAY:
			push_warning("ConditionEvaluator: \"any\" must be an array, got: %s" % [any_list])
			return false
		for sub_condition in any_list:
			if evaluate(sub_condition):
				return true
		return false

	if condition.has("not"):
		return not evaluate(condition.get("not"))

	if condition.has("flag"):
		var flag_name: String = condition.get("flag", "")
		var expected: bool = condition.get("equals", true)
		return GameState.get_flag(flag_name) == expected

	if condition.has("has_evidence"):
		return GameState.has_evidence(condition.get("has_evidence", ""))

	if condition.has("visited_location"):
		return GameState.visited_locations.has(condition.get("visited_location", ""))

	if condition.has("examined"):
		return GameState.has_seen("examine:%s:%s" % [GameState.current_location, condition.get("examined", "")])

	if condition.has("interaction_complete"):
		return GameState.has_seen("custom:%s" % condition.get("interaction_complete", ""))

	push_warning("ConditionEvaluator: unrecognized condition shape, treating it as false: %s" % [condition])
	return false


## Human-readable breakdown of a condition for debug tooling (Part E: "explain
## locked content") — never used for actual gameplay evaluation, only for
## showing developers *why* something is locked. Returns an array of
## {"description": String, "passed": bool}.
##
## A top-level "all" is flattened into one entry per sub-condition, because
## every one of them genuinely has to pass and listing them separately is the
## most useful thing to show. Everything else — including "any" — stays a
## single entry whose description spells the whole group out ("ANY of: X OR
## Y"), so the panel can never claim both halves of an either/or are
## "missing" when only one of them is needed.
static func explain(condition) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	_explain_into(condition, lines)
	return lines


static func _explain_into(condition, lines: Array[Dictionary]) -> void:
	if condition == null:
		return
	if typeof(condition) != TYPE_DICTIONARY:
		lines.append({"description": describe(condition), "passed": false})
		return

	if condition.has("all") and typeof(condition.get("all")) == TYPE_ARRAY:
		for sub_condition in condition.get("all"):
			_explain_into(sub_condition, lines)
		return

	lines.append({"description": describe(condition), "passed": evaluate(condition)})


## Single-line description of any condition, composites included, e.g.
## `ANY of: (has evidence "test_key" OR has evidence "test_note")`. Backs
## explain(), and is public so debug tooling can label a condition without
## going through explain(). Keep in sync with evaluate()'s shapes above.
static func describe(condition) -> String:
	if condition == null:
		return "(always true)"
	if typeof(condition) != TYPE_DICTIONARY:
		return "(malformed condition: %s)" % [condition]

	if condition.has("all"):
		return "ALL of: (%s)" % _describe_list(condition.get("all"), " AND ")
	if condition.has("any"):
		return "ANY of: (%s)" % _describe_list(condition.get("any"), " OR ")
	if condition.has("not"):
		return "NOT (%s)" % describe(condition.get("not"))
	if condition.has("flag"):
		return "flag \"%s\" == %s" % [condition.get("flag", ""), condition.get("equals", true)]
	if condition.has("has_evidence"):
		return "has evidence \"%s\"" % condition.get("has_evidence", "")
	if condition.has("visited_location"):
		return "visited location \"%s\"" % condition.get("visited_location", "")
	if condition.has("examined"):
		return "examined \"%s\"" % condition.get("examined", "")
	if condition.has("interaction_complete"):
		return "interaction complete \"%s\"" % condition.get("interaction_complete", "")
	return "(unknown condition: %s)" % [condition]


static func _describe_list(sub_conditions, separator: String) -> String:
	if typeof(sub_conditions) != TYPE_ARRAY:
		return "(malformed list: %s)" % [sub_conditions]
	var parts: Array[String] = []
	for sub_condition in sub_conditions:
		parts.append(describe(sub_condition))
	return separator.join(parts)


## Returns the first entry in `variants` whose "condition" field evaluates
## true (entries with no "condition" key always match), or an empty
## Dictionary if nothing matches. Used for both examine-point variants and
## NPC present-responses — same "ordered list, first match wins" shape.
static func resolve_variants(variants) -> Dictionary:
	if typeof(variants) != TYPE_ARRAY:
		return {}
	for variant in variants:
		if typeof(variant) != TYPE_DICTIONARY:
			continue
		if evaluate(variant.get("condition")):
			return variant
	return {}
