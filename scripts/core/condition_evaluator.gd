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
## future case needs a new kind of check.

static func evaluate(condition) -> bool:
	if condition == null:
		return true
	if typeof(condition) != TYPE_DICTIONARY:
		push_warning("ConditionEvaluator: condition must be a Dictionary or null, got: %s" % [condition])
		return true

	if condition.has("all"):
		for sub_condition in condition.get("all", []):
			if not evaluate(sub_condition):
				return false
		return true

	if condition.has("any"):
		for sub_condition in condition.get("any", []):
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

	push_warning("ConditionEvaluator: unrecognized condition shape: %s" % [condition])
	return true


## Human-readable breakdown of a condition for debug tooling (Part E: "explain
## locked content") — never used for actual gameplay evaluation, only for
## showing developers *why* something is locked. Returns a flat array of
## {"description": String, "passed": bool} for every leaf condition found,
## recursing into all/any/not. Grouping (which leaves belong to which "any")
## is intentionally not preserved — a flat list of what's missing is enough
## to debug Milestone-0-era content without building a second render path.
static func explain(condition) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	_explain_into(condition, lines)
	return lines


static func _explain_into(condition, lines: Array[Dictionary]) -> void:
	if condition == null:
		return
	if typeof(condition) != TYPE_DICTIONARY:
		return

	if condition.has("all") or condition.has("any"):
		var key: String = "all" if condition.has("all") else "any"
		for sub_condition in condition.get(key, []):
			_explain_into(sub_condition, lines)
		return

	if condition.has("not"):
		var sub = condition.get("not")
		lines.append({"description": "NOT (%s)" % _describe(sub), "passed": not evaluate(sub)})
		return

	lines.append({"description": _describe(condition), "passed": evaluate(condition)})


## Single-line description of one leaf condition shape, e.g. `flag
## "hallway_unlocked" == true`. Used only by explain(); keep in sync with
## evaluate()'s supported shapes above.
static func _describe(condition) -> String:
	if condition == null:
		return "(always true)"
	if typeof(condition) != TYPE_DICTIONARY:
		return str(condition)
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
	return str(condition)


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
