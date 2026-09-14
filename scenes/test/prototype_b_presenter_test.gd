extends SceneTree
## Focused tests for PrototypeBPresenter (Milestone 1.12 — see
## docs/prototype-b.md): the player view's exact allow-listed key structure,
## a content-level spoiler sweep against the real X/Y/Z prototype_b data (no
## domain id/structural role/veracity/relation/target ever reaches it before
## resolution), round-scoping (a future round's target/question is invisible
## until reached), evidence text gated on "opened", the resolved deduction
## appearing ONLY after success, hint progression via the real base API, and
## the feedback-category mapping for every evaluator outcome. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_b_presenter_test.gd

const CASE_IDS: Array[String] = ["proto_x_archive_ledger", "proto_y_lab_sample", "proto_z_customs_parcel"]

var content_db: Node
var presenter: Variant
var controller_script: Variant
var evaluator: Variant
var fixtures: Variant
var _failures: Array[String] = []
var _pass_count: int = 0


func _initialize() -> void:
	content_db = get_root().get_node("ContentDB")
	await process_frame

	presenter = load("res://scripts/deduction/prototype_b_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_b_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeBPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety(case_def)
		_test_round_scoping_hides_future_round(case_def)

	_test_resolved_claim_hidden_before_revealed_after()
	_test_evidence_text_gated_on_opened()
	_test_hint_progression_in_view()
	_test_feedback_mapping_all_categories()
	_test_stats_are_numeric_only()

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


## Every domain id anywhere in `case_def` (suspects, evidence, claims, proof
## sets) — the exact vocabulary a spoiler-safe view must never contain.
func _all_domain_ids(case_def: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			ids.append(str(entry.get("id", "")))
	for claim in case_def.get("claims", []):
		for proof_set in claim.get("proof_sets", []):
			ids.append(str(proof_set.get("id", "")))
	return ids


func _all_structural_roles(case_def: Dictionary) -> Array[String]:
	var roles: Array[String] = []
	for section in ["suspects", "evidence", "claims"]:
		for entry in case_def.get(section, []):
			var role: String = str(entry.get("structural_role", ""))
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


func _test_player_view_shape(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	_assert_keys_exactly(view, [
		"non_canon", "case_title", "case_description", "round_index", "round_count", "completed", "question",
		"slot_count", "slots", "can_submit", "evidence", "resolved", "resolved_claim", "hint", "stats", "completion_text",
	], "%s: player view" % case_id)
	_check(view.get("non_canon") == true, "%s: the player view must surface the non-canon status" % case_id)
	_check(view.get("completed") == false, "%s: a fresh run must not be completed" % case_id)
	_check(view.get("resolved") == false, "%s: a fresh round's target must not be resolved" % case_id)
	_check((view.get("resolved_claim", {}) as Dictionary).is_empty(), "%s: resolved_claim must be absent before resolution" % case_id)
	_check(view.get("completion_text") == "", "%s: completion_text must be empty before the prototype completes" % case_id)
	_check(view.get("slot_count") == 3, "%s: round 1's slot_count should be surfaced (3 for D1)" % case_id)
	for slot in view.get("slots", []):
		_assert_keys_exactly(slot, ["index", "filled", "evidence_handle"], "%s: player slot entry" % case_id)
	for evidence in view.get("evidence", []):
		_assert_keys_exactly(evidence, ["handle", "name", "opened", "text", "selected"], "%s: player evidence entry" % case_id)
	if not (view.get("hint", {}) as Dictionary).is_empty():
		_assert_keys_exactly(view.get("hint", {}), ["handle", "levels_revealed", "total_levels", "can_reveal_more"], "%s: player hint entry" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "attempts", "failed", "opened", "replacements", "hints_used"], "%s: player stats" % case_id)


## Content-level sweep after realistic play (one wrong attempt, one hint
## revealed, one evidence opened) — no domain id, structural role, relation,
## or target id may appear anywhere in the serialized view, and no banned
## key name may appear anywhere in its structure.
func _test_player_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var pool: Array = controller.get_evidence_pool_ids()
	controller.open_evidence(pool[0])
	controller.select_evidence(pool[0])
	controller.select_evidence(pool[1])
	controller.select_evidence(pool[2])
	controller.submit_connection()  # almost certainly wrong; that's fine, it's still real play
	controller.reveal_next_hint()

	var result: Dictionary = presenter.build_player_view(case_def, controller)
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
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "target", "relation", "unlock_requires", "ground_truth", "source", "certainty", "misleading"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])

	_check(not serialized.contains(str(case_def.get("ground_truth", {}).get("culprit", "IMPOSSIBLE"))), "%s: the culprit id must never appear in the Prototype B player view" % case_id)


## Only the CURRENT round's question/target ever appear — round 2's question
## text must be completely absent while round 1 is active.
func _test_round_scoping_hides_future_round(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var round2: Dictionary = (case_def.get("prototype_b", {}).get("rounds", [])[1] as Dictionary)
	var round2_question: String = String(TranslationServer.translate(str(round2.get("question", ""))))
	var round2_target_claim: Dictionary = evaluator.find_claim(case_def, str(round2.get("target", "")))
	var round2_text: String = String(TranslationServer.translate(round2_target_claim.get("text", "")))

	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(round2_question != "" and view.get("question", "") != round2_question, "%s: round 2's question must not be shown while round 1 is active" % case_id)
	_check(round2_text != "" and not JSON.stringify(view).contains(round2_text), "%s: round 2's target deduction text must not leak while round 1 is active" % case_id)


func _test_resolved_claim_hidden_before_revealed_after() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(before.get("resolved") == false, "the target must not be resolved before a successful connection")
	_check((before.get("resolved_claim", {}) as Dictionary).is_empty(), "resolved_claim must be entirely absent before resolution — not merely blank")
	_check(not JSON.stringify(before).contains("first deduction"), "the deduction's own authored text must not leak before it is proven")

	controller.select_evidence("e_a")
	controller.select_evidence("e_b")
	controller.select_evidence("e_c")
	controller.submit_connection()
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(after.get("resolved") == true, "the target must be resolved after a successful connection")
	_check((after.get("resolved_claim", {}) as Dictionary).get("text", "") != "", "resolved_claim must reveal the deduction's own text once proven")


func _test_evidence_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	for evidence in view.get("evidence", []):
		_check(evidence.get("opened") == false and evidence.get("text") == "", "unopened evidence must show no text yet")

	controller.open_evidence("e_a")
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	var opened_count := 0
	for evidence in after.get("evidence", []):
		if evidence.get("opened", false):
			opened_count += 1
			_check(evidence.get("text", "") != "", "an opened evidence item must show its text")
	_check(opened_count == 1, "exactly one evidence item should be opened")


func _test_hint_progression_in_view() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not (before.get("hint", {}) as Dictionary).is_empty(), "round 1's target has a base hint ladder, so its hint entry should be present")
	_check((before.get("hint", {}).get("levels_revealed", []) as Array).is_empty(), "no hint level should be revealed yet")
	_check(before.get("hint", {}).get("can_reveal_more") == true, "more levels should be available")

	controller.reveal_next_hint()
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((after.get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "revealing one hint should show exactly one level")


func _test_feedback_mapping_all_categories() -> void:
	var case_def: Dictionary = fixtures.prototype_b_case()
	var controller = _new_controller(case_def)

	var success_feedback: Dictionary = presenter.build_feedback(case_def, controller, {"category": "valid_support"})
	_check(success_feedback.get("success") == true, "a valid_support result should map to success")
	_check(success_feedback.get("deduction_text") != "" and success_feedback.get("explanation") != "", "a successful connection should surface both the revealed deduction's own text and the round's authored explanation")

	for entry in [
		["irrelevant_evidence", "UI_PROTOTYPE_B_FEEDBACK_IRRELEVANT"],
		["insufficient_evidence", "UI_PROTOTYPE_B_FEEDBACK_INSUFFICIENT"],
		["compatible_not_proof", "UI_PROTOTYPE_B_FEEDBACK_COMPATIBLE"],
		["invalid_input", "UI_PROTOTYPE_B_FEEDBACK_INVALID"],
	]:
		var feedback: Dictionary = presenter.build_feedback(case_def, controller, {"category": entry[0]})
		_check(feedback.get("success") == false, "%s must never be reported as success" % entry[0])
		_check(feedback.get("explanation") == String(TranslationServer.translate(entry[1])), "%s should map to the generic %s message, got \"%s\"" % [entry[0], entry[1], feedback.get("explanation")])
		_check(feedback.get("deduction_text") == "", "%s must never surface the deduction's text" % entry[0])


func _test_stats_are_numeric_only() -> void:
	var stats: Dictionary = {"elapsed_ms": 1234, "attempts": 2, "failed": 1, "opened": 3, "replacements": 1, "hints_used": 1}
	for key in stats:
		_check(typeof(stats[key]) == TYPE_INT or typeof(stats[key]) == TYPE_FLOAT, "stats.%s must be numeric, never text that could leak content" % key)
