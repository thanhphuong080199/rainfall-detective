extends SceneTree
## Focused unit tests for TimelineEvaluator (Milestone 1.9 — see
## docs/deduction-system.md, "Timeline reconstruction"): every constraint type
## on both sides of its boundary, submissions accepted by constraint rather
## than by equality with one sequence, optional (claimed-time) violations
## reported without failing, and malformed input. Run with:
##   godot --headless --path . -s res://scenes/test/timeline_evaluator_test.gd

var timeline: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	await process_frame
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== TimelineEvaluator — focused tests ===")
	_test_parse_time()
	_test_fixed_time()
	_test_window()
	_test_before()
	_test_no_overlap()
	_test_travel_time()
	_test_multiple_valid_timelines()
	_test_optional_constraints_do_not_fail()
	_test_invalid_input()
	_test_malformed_constraint_fails_closed()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _case(events: Array, constraints: Array) -> Dictionary:
	return {"id": "tl_case", "timeline": {"events": events, "constraints": constraints}}


func _event(event_id: String, duration: int = 0) -> Dictionary:
	return {"id": event_id, "duration_minutes": duration}


func _consistent(case_def: Dictionary, placements: Dictionary) -> bool:
	return timeline.evaluate(case_def, placements).get("category") == timeline.CONSISTENT


func _test_parse_time() -> void:
	_check(timeline.parse_time("09:05") == 545, "09:05 should parse to 545 minutes")
	_check(timeline.parse_time("00:00") == 0 and timeline.parse_time("23:59") == 1439, "the day's bounds should parse")
	for bad in ["9:05", "24:00", "12:60", "ab:cd", "", "12-30"]:
		_check(timeline.parse_time(bad) == -1, "'%s' should be rejected" % bad)
	_check(timeline.parse_time(905) == -1, "a non-string time should be rejected")


func _test_fixed_time() -> void:
	var case_def := _case([_event("a")], [{"id": "c", "type": "fixed_time", "event": "a", "time": "10:00"}])
	_check(_consistent(case_def, {"a": "10:00"}), "fixed_time should accept the exact time")
	_check(not _consistent(case_def, {"a": "10:01"}), "fixed_time should reject any other time")


func _test_window() -> void:
	var case_def := _case([_event("a")], [{"id": "c", "type": "window", "event": "a", "earliest": "09:00", "latest": "09:30"}])
	_check(_consistent(case_def, {"a": "09:00"}) and _consistent(case_def, {"a": "09:30"}), "window bounds should be inclusive")
	_check(not _consistent(case_def, {"a": "08:59"}) and not _consistent(case_def, {"a": "09:31"}), "window should reject times outside it")


func _test_before() -> void:
	var case_def := _case([_event("a", 10), _event("b")], [{"id": "c", "type": "before", "events": ["a", "b"], "min_gap_minutes": 5}])
	_check(_consistent(case_def, {"a": "09:00", "b": "09:15"}), "before should accept b starting exactly end(a) + gap")
	_check(not _consistent(case_def, {"a": "09:00", "b": "09:14"}), "before should respect a's duration plus the minimum gap")
	_check(not _consistent(case_def, {"a": "09:30", "b": "09:00"}), "before is ordered — b before a must fail")


func _test_no_overlap() -> void:
	var case_def := _case([_event("a", 30), _event("b", 20)], [{"id": "c", "type": "no_overlap", "events": ["a", "b"]}])
	_check(_consistent(case_def, {"a": "09:00", "b": "09:30"}), "intervals that only touch should not overlap")
	_check(not _consistent(case_def, {"a": "09:00", "b": "09:29"}), "b starting inside a should overlap")
	_check(_consistent(case_def, {"a": "09:00", "b": "08:40"}), "no_overlap is symmetric — b entirely before a is fine")
	var instants := _case([_event("x"), _event("y")], [{"id": "c", "type": "no_overlap", "events": ["x", "y"]}])
	_check(not _consistent(instants, {"x": "09:00", "y": "09:00"}), "two instants at the same minute should count as overlapping")


func _test_travel_time() -> void:
	var case_def := _case([_event("a"), _event("b", 10)], [{"id": "c", "type": "travel_time", "events": ["a", "b"], "minutes": 20}])
	_check(_consistent(case_def, {"a": "09:00", "b": "09:20"}), "travel_time should accept exactly the travel time")
	_check(not _consistent(case_def, {"a": "09:00", "b": "09:19"}), "one person can't be in both places with less than the travel time between")
	_check(_consistent(case_def, {"a": "09:00", "b": "08:30"}), "travel_time should apply in whichever order the events happen (b ends 08:40, +20 = 09:00)")
	_check(not _consistent(case_def, {"a": "09:00", "b": "08:31"}), "the reverse order should also enforce the travel time")


func _test_multiple_valid_timelines() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var authored: Dictionary = case_def["ground_truth"]["solution_timeline"]
	var alternate: Dictionary = fixtures.alternate_valid_timeline()
	_check(authored != alternate, "sanity: the two placements differ")
	_check(_consistent(case_def, authored), "the authored solution should be consistent")
	_check(_consistent(case_def, alternate), "a different placement satisfying every required constraint must also be accepted")
	var wrong: Dictionary = timeline.evaluate(case_def, {"t_leaves": "09:30", "t_away": "09:50", "t_use": "10:00"})
	_check(wrong.get("category") == timeline.INCONSISTENT, "a placement violating a required constraint should be inconsistent")
	_check(wrong.get("violated_required") == ["c_travel"], "the result should name the violated constraint (not the correct placement)")


func _test_optional_constraints_do_not_fail() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var result: Dictionary = timeline.evaluate(case_def, case_def["ground_truth"]["solution_timeline"])
	_check(result.get("category") == timeline.CONSISTENT, "violating only an optional (claimed-time) constraint should stay consistent")
	_check(result.get("violated_optional") == ["c_claimed"], "the contradicted claimed time should still be reported")


func _test_invalid_input() -> void:
	var case_def: Dictionary = fixtures.base_case()
	var cases := {
		"not_a_dictionary": ["t_leaves", "09:20"],
		"unknown_event": {"t_leaves": "09:20", "t_away": "09:55", "t_use": "10:00", "t_ghost": "10:30"},
		"missing_event": {"t_leaves": "09:20", "t_use": "10:00"},
		"bad_time": {"t_leaves": "9:20", "t_away": "09:55", "t_use": "10:00"},
	}
	for reason in cases:
		var result: Dictionary = timeline.evaluate(case_def, cases[reason])
		_check(result.get("category") == timeline.INVALID_INPUT and result.get("reason") == reason, "expected invalid_input/%s, got %s/%s" % [reason, result.get("category"), result.get("reason")])


func _test_malformed_constraint_fails_closed() -> void:
	var case_def := _case([_event("a")], [
		{"id": "c_unknown_type", "type": "teleport", "event": "a"},
		{"id": "c_bad_ref", "type": "fixed_time", "event": "ghost", "time": "10:00"},
		{"id": "c_bad_window", "type": "window", "event": "a", "earliest": "nine", "latest": "10:00"},
	])
	var result: Dictionary = timeline.evaluate(case_def, {"a": "10:00"})
	_check(result.get("category") == timeline.INCONSISTENT, "malformed constraints must fail closed, never silently pass")
	_check((result.get("violated_required") as Array).size() == 3, "every malformed constraint should be reported as violated")
