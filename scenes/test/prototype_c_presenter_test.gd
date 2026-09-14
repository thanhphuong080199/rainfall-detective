extends SceneTree
## Focused tests for PrototypeCPresenter (Milestone 1.13 — see
## docs/prototype-c.md): the player view's exact allow-listed key structure,
## a content-level spoiler sweep against the real X/Y/Z prototype_c data (no
## domain id/structural role/raw constraint field ever reaches it), fact text
## gated on "opened", the disputed claim absent before acceptance and present
## (without veracity) after, the final explanation absent until the claim is
## actually resolved, hint progression, and the violation/claim feedback
## mappings. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_c_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

var content_db: Node
var presenter: Variant
var controller_script: Variant
var evaluator: Variant
var timeline: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	presenter = load("res://scripts/deduction/prototype_c_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_c_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	timeline = load("res://scripts/deduction/timeline_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeCPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety_before_acceptance(case_def)
		_test_accepted_view_spoiler_safety(case_def)

	_test_claim_absent_before_accepted_present_after()
	_test_resolution_absent_until_claim_resolved()
	_test_fact_text_gated_on_opened()
	_test_hint_progression_in_view()
	_test_violation_feedback_mapping()
	_test_claim_feedback_mapping()
	_test_stats_are_numeric_only()
	_test_presenter_never_reads_constraint_type_or_required()

	quit(TestHelpers.finish(_failures, _pass_count))


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append(message)


func _new_controller(case_def: Dictionary):
	var controller = controller_script.new()
	controller.start(case_def)
	return controller


## Every domain id anywhere in `case_def` — suspects, evidence, claims,
## timeline events and timeline constraints — the exact vocabulary a
## spoiler-safe view must never contain as a raw id.
func _all_domain_ids(case_def: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			ids.append(str(entry.get("id", "")))
	for event in case_def.get("timeline", {}).get("events", []):
		ids.append(str(event.get("id", "")))
	for constraint in case_def.get("timeline", {}).get("constraints", []):
		ids.append(str(constraint.get("id", "")))
	return ids


func _all_structural_roles(case_def: Dictionary) -> Array[String]:
	var roles: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			var role: String = str(entry.get("structural_role", ""))
			if role != "" and not roles.has(role):
				roles.append(role)
	for event in case_def.get("timeline", {}).get("events", []):
		var role: String = str(event.get("structural_role", ""))
		if role != "" and not roles.has(role):
			roles.append(role)
	return roles


func _collect_all_keys(value: Variant, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary):
			out[str(key)] = true
			_collect_all_keys((value as Dictionary)[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for entry in (value as Array):
			_collect_all_keys(entry, out)


func _assert_keys_exactly(dict: Dictionary, allowed: Array, context: String) -> void:
	var actual: Array = dict.keys()
	actual.sort()
	var expected: Array = allowed.duplicate()
	expected.sort()
	_check(actual == expected, "%s should have exactly the keys %s, got %s" % [context, expected, actual])


const BASE_VIEW_KEYS := [
	"non_canon", "case_title", "case_description", "objective", "completed", "accepted",
	"events", "time_slots", "unplaced_count", "can_submit", "can_resubmit", "facts", "hint", "stats", "completion_text",
]


func _test_player_view_shape(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_assert_keys_exactly(view, BASE_VIEW_KEYS, "%s: player view before acceptance" % case_id)
	_check(view.get("non_canon") == true, "%s: the player view must surface the non-canon status" % case_id)
	_check(view.get("completed") == false, "%s: a fresh run must not be completed" % case_id)
	_check(view.get("accepted") == false, "%s: a fresh run must not be accepted" % case_id)
	_check(view.get("completion_text") == "", "%s: completion_text must be empty before completion" % case_id)
	_check((view.get("events", []) as Array).size() == 7, "%s: all seven timeline events should be surfaced" % case_id)
	for event in view.get("events", []):
		_assert_keys_exactly(event, ["handle", "label", "duration_minutes", "fixed", "placement", "selected"], "%s: player event entry" % case_id)
	for fact in view.get("facts", []):
		_assert_keys_exactly(fact, ["handle", "opened", "text"], "%s: player fact entry" % case_id)
	if not (view.get("hint", {}) as Dictionary).is_empty():
		_assert_keys_exactly(view.get("hint", {}), ["levels_revealed", "total_levels", "can_reveal_more"], "%s: player hint entry" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "submissions", "failed", "moves", "facts_opened", "hints_used", "claim_attempts"], "%s: player stats" % case_id)


## Content-level sweep after realistic (but wrong) play — one fact opened,
## one hint revealed, a full-but-incorrect submission — no domain id,
## structural role, or banned field may appear anywhere in the serialized
## view before the timeline is even accepted.
func _test_player_view_spoiler_safety_before_acceptance(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var facts: Array = controller.get_fact_ids()
	controller.open_fact(facts[0])
	for event_id in controller.get_all_event_ids():
		if not controller.is_fixed(event_id):
			controller.place_event(event_id, controller.get_time_slots()[0])
	controller.submit_timeline()
	controller.reveal_next_hint()

	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	_check(view.get("accepted", true) == false, "%s: sanity — placing every movable event at the same early slot should not accept" % case_id)
	_sweep_spoiler_safety(case_def, result, case_id)


## Same sweep, but with the AUTHORED solution submitted (a genuinely accepted
## timeline) — proves the disputed claim's text, once revealed, is the only
## new thing exposed; every domain id/structural role remains absent.
func _test_accepted_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var solution: Dictionary = case_def.get("ground_truth", {}).get("solution_timeline", {})
	for event_id in controller.get_all_event_ids():
		if not controller.is_fixed(event_id):
			controller.place_event(event_id, str(solution.get(event_id, "")))
	var submit_result: Dictionary = controller.submit_timeline()
	_check(submit_result.get("accepted", false) == true, "%s: the authored solution should be accepted" % case_id)

	var result: Dictionary = presenter.build_player_view(case_def, controller)
	_check((result.get("view", {}) as Dictionary).has("claim"), "%s: the accepted view should now include the claim key" % case_id)
	_sweep_spoiler_safety(case_def, result, case_id)


func _sweep_spoiler_safety(case_def: Dictionary, result: Dictionary, case_id: String) -> void:
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)

	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	for domain_id in result.get("handle_map", {}).values():
		_check(not serialized.contains(str(domain_id)), "%s: player view must never contain a handle_map target id (\"%s\")" % [case_id, domain_id])

	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "type", "required", "unlock_requires", "ground_truth", "source", "certainty", "misleading", "solution_timeline", "constraint_ref"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])


## Only the fixture is needed for the phase-transition tests below — they
## check CONTROLLER-STATE-DEPENDENT presenter behavior, not per-case content.
func _accept_fixture_timeline(controller) -> void:
	controller.place_event("t_a", "09:00")
	controller.place_event("t_b", "10:10")
	controller.submit_timeline()


func _test_claim_absent_before_accepted_present_after() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not before.has("claim"), "the claim key must be ENTIRELY ABSENT before the timeline is accepted, not merely blank")
	_check(not JSON.stringify(before).contains("st_lie"), "the disputed claim's id must never leak before acceptance")

	_accept_fixture_timeline(controller)
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(after.has("claim"), "the claim key must appear once the timeline is accepted")
	_check(String(after.get("claim", {}).get("statement_text", "")) != "", "the claim's own statement text should be revealed")
	_check(after.get("claim_phase") == true, "claim_phase should be true immediately after acceptance")
	_check(after.get("claim_resolved") == false, "claim_resolved should be false before an answer is given")


func _test_resolution_absent_until_claim_resolved() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	_accept_fixture_timeline(controller)

	var wrong_answer: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not wrong_answer.has("resolution"), "the resolution key must be absent before the claim is answered correctly")

	controller.answer_claim(false)  # "Fits" — wrong
	var still_wrong: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not still_wrong.has("resolution"), "a wrong claim answer must not reveal the resolution")

	controller.answer_claim(true)  # "Impossible" — correct
	var resolved: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(resolved.has("resolution"), "the resolution key must appear once the claim is correctly resolved")
	_check(String(resolved.get("resolution", {}).get("explanation", "")) != "", "the resolution should include the interpolated explanation text")
	_check(resolved.get("resolution", {}).get("explanation", "").contains("10:10"), "the explanation should interpolate the player's OWN accepted time for the disputed event, not the authored one")


func _test_fact_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	for fact in view.get("facts", []):
		_check(fact.get("opened") == false and fact.get("text") == "", "an unopened fact must show no text yet")

	var first_fact_id: String = controller.get_fact_ids()[0]
	controller.open_fact(first_fact_id)
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var opened_count := 0
	for fact in after.get("facts", []):
		if fact.get("opened", false):
			opened_count += 1
			_check(fact.get("text", "") != "", "an opened fact must show its text")
	_check(opened_count == 1, "exactly one fact should be opened")


func _test_hint_progression_in_view() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not (before.get("hint", {}) as Dictionary).is_empty(), "a case with an authored hint_ladder should have a non-empty hint entry")
	_check((before.get("hint", {}).get("levels_revealed", []) as Array).is_empty(), "no hint level should be revealed yet")
	_check(before.get("hint", {}).get("can_reveal_more") == true, "more levels should be available")

	controller.reveal_next_hint()
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((after.get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "revealing one hint should show exactly one level")


func _test_violation_feedback_mapping() -> void:
	var case_def: Dictionary = fixtures.prototype_c_case()
	var controller = _new_controller(case_def)
	controller.place_event("t_a", "10:10")  # violates c_a_window
	controller.place_event("t_b", "10:10")
	var result: Dictionary = controller.submit_timeline()
	var feedback: Dictionary = presenter.build_violation_feedback(case_def, controller, result)
	_check(feedback.get("accepted") == false, "a rejected submission should map accepted=false")
	_check(feedback.get("invalid") == false, "a complete-but-wrong submission is not \"invalid\"")
	_check((feedback.get("violations", []) as Array).size() >= 1, "at least one violated fact should be listed")
	for violation in feedback.get("violations", []):
		_assert_keys_exactly(violation, ["text", "event_handles"], "violation entry")
		_check(violation.get("text", "") != "", "a violation must carry its natural-language fact text")

	var invalid_result: Dictionary = {"category": timeline.INVALID_INPUT, "reason": "incomplete_selection", "violated_required": [], "violated_optional": [], "accepted": false, "blocked_duplicate": false}
	var invalid_feedback: Dictionary = presenter.build_violation_feedback(case_def, controller, invalid_result)
	_check(invalid_feedback.get("invalid") == true, "an invalid_input result should be reported as invalid")
	_check(invalid_feedback.get("message", "") != "", "an invalid submission should carry a non-spoiling message")

	var accepted = _new_controller(case_def)
	accepted.place_event("t_a", "09:00")
	accepted.place_event("t_b", "10:10")
	var accepted_result: Dictionary = accepted.submit_timeline()
	var accepted_feedback: Dictionary = presenter.build_violation_feedback(case_def, accepted, accepted_result)
	_check(accepted_feedback.get("accepted") == true, "a consistent submission should map accepted=true")
	_check((accepted_feedback.get("violations", []) as Array).is_empty(), "an accepted timeline should list no violations")


func _test_claim_feedback_mapping() -> void:
	var wrong: Dictionary = presenter.build_claim_feedback({"correct": false, "resolved": false})
	_check(wrong.get("correct") == false and wrong.get("guidance", "") != "", "a wrong claim answer should carry non-spoiling guidance")

	var right: Dictionary = presenter.build_claim_feedback({"correct": true, "resolved": true})
	_check(right.get("correct") == true and right.get("guidance", "") == "", "a correct claim answer should carry no guidance text (the resolution explanation is shown separately)")


func _test_stats_are_numeric_only() -> void:
	var stats: Dictionary = {"elapsed_ms": 1234, "submissions": 2, "failed": 1, "moves": 4, "facts_opened": 2, "hints_used": 1, "claim_attempts": 1}
	for key in stats:
		_check(typeof(stats[key]) == TYPE_INT or typeof(stats[key]) == TYPE_FLOAT, "stats.%s must be numeric, never text that could leak content" % key)


## Structural guarantee, cheaper and more precise than a text sweep (the
## narrative content itself uses ordinary words like "window"): the presenter
## must never read a constraint's own "type" or "required" field at all —
## every fact it shows comes from the AUTHORED visible_constraint_facts
## translation key, never from inspecting the constraint's shape.
func _test_presenter_never_reads_constraint_type_or_required() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/deduction/prototype_c_presenter.gd")
	for forbidden in ['.get("type"', '.get("required"', '.get("earliest"', '.get("latest"', '.get("min_gap_minutes"']:
		_check(not source.contains(forbidden), "prototype_c_presenter.gd must never read a constraint's %s field — facts come only from authored translation keys" % forbidden)
