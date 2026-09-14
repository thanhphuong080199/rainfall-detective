extends SceneTree
## Content tests for Prototype C's optional data layer (Milestone 1.13 — see
## docs/prototype-c.md) on the real X/Y/Z prototype deduction cases, loaded
## through ContentDB and driven with the real TimelineEvaluator/
## DeductionValidator — the same pattern prototype_a_content_test.gd/
## prototype_b_content_test.gd already established. Written once, in
## structural terms, and run against all three cases so the same script
## proves X, Y and Z share one Prototype C shape. Does NOT re-derive checks
## DeductionValidator/ContentValidator already own (references, translation
## completeness of most fields, structural equivalence of the raw signature)
## — see validate_content.gd for those; this file asserts the PLAYER-FACING
## guarantees the milestone actually cares about, PLUS the one heavy, bounded
## proof deliberately kept OUT of the always-on validator for performance
## (see DeductionValidator.enumerate_accepted_prototype_c_timelines()'s own
## doc comment): every UI-offered timeline TimelineEvaluator accepts also
## makes the disputed claim impossible. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_content_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

var content_db: Node
var timeline: Variant
var validator: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
	validator = load("res://scripts/deduction/deduction_validator.gd")

	print("=== Prototype C content — X/Y/Z structural-role tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		if case_def.is_empty():
			_failures.append("%s should load through ContentDB" % case_id)
			continue
		_check(typeof(case_def.get("prototype_c")) == TYPE_DICTIONARY, "%s should declare a prototype_c data layer" % case_id)
		_test_seven_events_two_fixed_five_movable(case_def)
		_test_authored_solution_times_are_offered_and_pass(case_def)
		_test_every_required_constraint_has_a_visible_fact(case_def)
		# Enumerated ONCE per case (bounded but not free — see
		# DeductionValidator.enumerate_accepted_prototype_c_timelines()'s own
		# doc comment) and reused by every check below that needs it.
		var accepted: Array = validator.enumerate_accepted_prototype_c_timelines(case_def)
		_test_at_least_one_ui_offered_timeline_is_accepted(case_def, accepted)
		_test_alternate_valid_timeline_also_accepted(case_def, accepted)
		_test_optional_constraint_never_blocks_acceptance(case_def)
		_test_invalid_placement_is_rejected(case_def)
		_test_every_accepted_timeline_contradicts_the_claim(case_def, accepted)
		_test_translations_resolve(case_def)
	_test_prototype_c_structurally_equivalent_across_cases()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _test_seven_events_two_fixed_five_movable(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_c", {})
	var events: Array = case_def.get("timeline", {}).get("events", [])
	_check(events.size() == 7, "%s: the timeline should have exactly 7 events, got %d" % [case_id, events.size()])
	_check((proto.get("fixed_events", []) as Array).size() == 2, "%s: prototype_c should declare exactly 2 fixed events, got %d" % [case_id, (proto.get("fixed_events", []) as Array).size()])
	_check((proto.get("movable_events", []) as Array).size() == 5, "%s: prototype_c should declare exactly 5 movable events, got %d" % [case_id, (proto.get("movable_events", []) as Array).size()])


func _test_authored_solution_times_are_offered_and_pass(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_c", {})
	var slots: Array = proto.get("time_slots", [])
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	for event_id in proto.get("movable_events", []):
		_check(slots.has(str(solution.get(event_id, ""))), "%s: the authored solution time for movable event \"%s\" must be one of the offered time_slots" % [case_id, event_id])
	var result: Dictionary = timeline.evaluate(case_def, solution)
	_check(str(result.get("category", "")) == timeline.CONSISTENT, "%s: the authored solution must satisfy every required constraint, got %s" % [case_id, result])


func _test_every_required_constraint_has_a_visible_fact(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var facts: Dictionary = case_def.get("prototype_c", {}).get("visible_constraint_facts", {})
	var en: Translation = TranslationServer.get_translation_object("en")
	var vi: Translation = TranslationServer.get_translation_object("vi")
	for constraint in timeline.constraints(case_def):
		var required: bool = constraint.get("required", true) != false
		var constraint_id: String = str(constraint.get("id", ""))
		if required:
			_check(facts.has(constraint_id), "%s: required constraint \"%s\" must have a player-visible fact (a required constraint may never be a hidden author-only rule)" % [case_id, constraint_id])
			var key: String = str(facts.get(constraint_id, ""))
			_check(String(en.get_message(key)) != "" and String(vi.get_message(key)) != "", "%s: fact for \"%s\" (key \"%s\") must resolve in both en and vi" % [case_id, constraint_id, key])
		else:
			_check(not facts.has(constraint_id), "%s: optional constraint \"%s\" (the disputed claim) must stay hidden — it must never appear as a visible fact" % [case_id, constraint_id])


func _test_at_least_one_ui_offered_timeline_is_accepted(case_def: Dictionary, accepted: Array) -> void:
	var case_id: String = case_def.get("id", "")
	_check(not accepted.is_empty(), "%s: at least one UI-offered placement (movable events assigned from time_slots) must satisfy every required constraint" % case_id)


func _test_alternate_valid_timeline_also_accepted(case_def: Dictionary, accepted: Array) -> void:
	var case_id: String = case_def.get("id", "")
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	var has_alternate := false
	for placement in accepted:
		var differs := false
		for event_id in case_def.get("prototype_c", {}).get("movable_events", []):
			if str(placement.get(event_id, "")) != str(solution.get(event_id, "")):
				differs = true
				break
		if differs:
			has_alternate = true
			break
	_check(has_alternate, "%s: at least one accepted UI-offered timeline should differ from the authored solution — success must not be exact-equality with one sequence" % case_id)


func _test_optional_constraint_never_blocks_acceptance(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	var result: Dictionary = timeline.evaluate(case_def, solution)
	_check(not (result.get("violated_optional", []) as Array).is_empty(), "%s: sanity — the authored solution should violate the optional disputed-claim constraint, exactly like every other accepted timeline" % case_id)
	_check(str(result.get("category", "")) == timeline.CONSISTENT, "%s: a violated OPTIONAL constraint must never block acceptance" % case_id)


func _test_invalid_placement_is_rejected(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_c", {})
	var slots: Array = proto.get("time_slots", [])
	var placement: Dictionary = {}
	for event_id in proto.get("fixed_events", []):
		for constraint in timeline.constraints(case_def):
			if str(constraint.get("type", "")) == "fixed_time" and str(constraint.get("event", "")) == event_id:
				placement[event_id] = constraint.get("time", "")
	# Deliberately wrong: every movable event dumped on the single EARLIEST
	# candidate slot — this can satisfy at most one event's own window.
	for event_id in proto.get("movable_events", []):
		placement[event_id] = slots[0]
	var result: Dictionary = timeline.evaluate(case_def, placement)
	_check(str(result.get("category", "")) != timeline.CONSISTENT, "%s: dumping every movable event on the same early slot must violate at least one required constraint" % case_id)
	_check(not (result.get("violated_required", []) as Array).is_empty(), "%s: the rejected placement should name at least one violated required fact" % case_id)


## The universal-contradiction proof: EVERY placement the UI could ever
## submit that TimelineEvaluator accepts must also make the disputed claim's
## own hypothetical constraint fail — never just the authored solution.
func _test_every_accepted_timeline_contradicts_the_claim(case_def: Dictionary, accepted: Array) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_c", {})
	var contradiction: Dictionary = proto.get("contradiction", {})
	var constraint_ref: String = str(contradiction.get("constraint_ref", ""))
	var contradiction_constraint: Dictionary = {}
	for constraint in timeline.constraints(case_def):
		if str(constraint.get("id", "")) == constraint_ref:
			contradiction_constraint = constraint
	_check(not contradiction_constraint.is_empty(), "%s: sanity — the contradiction's constraint_ref should resolve to a real timeline constraint" % case_id)

	var events_index: Dictionary = timeline.event_index(case_def)
	_check(not accepted.is_empty(), "%s: sanity — there should be accepted timelines to check" % case_id)
	for placement in accepted:
		var starts: Dictionary = {}
		for event_id in placement:
			starts[event_id] = timeline.parse_time(placement[event_id])
		var claim_fits: bool = timeline.is_constraint_satisfied(contradiction_constraint, starts, events_index)
		_check(not claim_fits, "%s: accepted timeline %s must make the disputed claim impossible, but the claim's constraint was still satisfied" % [case_id, placement])


func _test_translations_resolve(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var proto: Dictionary = case_def.get("prototype_c", {})
	var en: Translation = TranslationServer.get_translation_object("en")
	var vi: Translation = TranslationServer.get_translation_object("vi")
	for field in ["objective", "completion_text"]:
		var key: String = str(proto.get(field, ""))
		_check(String(en.get_message(key)) != "" and String(vi.get_message(key)) != "", "%s: %s key \"%s\" must resolve in both en and vi" % [case_id, field, key])
	var explanation_key: String = str(proto.get("contradiction", {}).get("explanation", ""))
	_check(String(en.get_message(explanation_key)) != "" and String(vi.get_message(explanation_key)) != "", "%s: contradiction.explanation key \"%s\" must resolve in both en and vi" % [case_id, explanation_key])
	for level_index in (proto.get("hint_ladder", []) as Array).size():
		var key: String = str(proto.get("hint_ladder", [])[level_index])
		_check(String(en.get_message(key)) != "" and String(vi.get_message(key)) != "", "%s: hint_ladder level %d key \"%s\" must resolve in both en and vi" % [case_id, level_index + 1, key])


## The structural SHAPE of prototype_c — fixed/movable role counts, fact
## constraint-type multiset, and the contradiction's claim role/constraint
## type — must be identical across X, Y and Z.
func _test_prototype_c_structurally_equivalent_across_cases() -> void:
	var reference: Array = []
	for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[0])):
		if String(line).begins_with("prototype_c:"):
			reference.append(line)
	_check(reference.size() >= 5, "the prototype_c structural signature should describe fixed/movable roles, slot count, fact types and the contradiction, not be trivially empty")
	for i in range(1, CASE_IDS.size()):
		var other: Array = []
		for line in validator.structural_signature(content_db.get_deduction_case(CASE_IDS[i])):
			if String(line).begins_with("prototype_c:"):
				other.append(line)
		_check(other == reference, "%s's prototype_c shape should exactly match %s's, got %s vs %s" % [CASE_IDS[i], CASE_IDS[0], other, reference])
