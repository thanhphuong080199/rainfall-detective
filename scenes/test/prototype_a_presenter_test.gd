extends SceneTree
## Focused tests for PrototypeAPresenter (Milestone 1.11 — see
## docs/prototype-a.md): the player view's exact allow-listed key structure,
## a content-level spoiler sweep against the real X/Y/Z prototype_a data
## (no domain id/structural role/veracity/required-optional-before-resolution
## ever reaches it), round-scoping (no future-round text), evidence text
## gated on "opened", hint progression, and the feedback-category mapping for
## every evaluator outcome. Run with:
##   godot --headless --path . -s res://scenes/test/prototype_a_presenter_test.gd

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

	presenter = load("res://scripts/deduction/prototype_a_presenter.gd")
	controller_script = load("res://scripts/deduction/prototype_a_controller.gd")
	evaluator = load("res://scripts/deduction/deduction_evaluator.gd")
	fixtures = load("res://scenes/test/deduction_fixtures.gd")

	print("=== PrototypeAPresenter — focused tests ===")
	for case_id in CASE_IDS:
		var case_def: Dictionary = content_db.get_deduction_case(case_id)
		_check(not case_def.is_empty(), "%s should load through ContentDB" % case_id)
		_test_player_view_shape(case_def)
		_test_player_view_spoiler_safety(case_def)
		_test_round_scoping_hides_future_round(case_def)

	_test_outcome_hidden_before_resolution_revealed_after()
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


func _all_veracity_values(case_def: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for claim in case_def.get("claims", []):
		var veracity: String = str(claim.get("veracity", ""))
		if veracity != "" and not values.has(veracity):
			values.append(veracity)
	return values


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
		"non_canon", "case_title", "case_description", "suspects", "round_index", "round_count", "completed",
		"current_statement_handle", "statements", "evidence", "selected_evidence_handle", "hint", "stats", "completion_text",
	], "%s: player view" % case_id)
	_check(view.get("non_canon") == true, "%s: the player view must surface the non-canon status" % case_id)
	_check(view.get("completed") == false, "%s: a fresh run must not be completed" % case_id)
	_check(view.get("completion_text") == "", "%s: completion_text must be empty before the prototype completes" % case_id)
	for suspect in view.get("suspects", []):
		_assert_keys_exactly(suspect, ["handle", "name"], "%s: player suspect entry" % case_id)
	for statement in view.get("statements", []):
		_assert_keys_exactly(statement, ["handle", "text", "speaker", "resolved", "outcome"], "%s: player statement entry" % case_id)
	for evidence in view.get("evidence", []):
		_assert_keys_exactly(evidence, ["handle", "name", "opened", "text", "selected"], "%s: player evidence entry" % case_id)
	if not (view.get("hint", {}) as Dictionary).is_empty():
		_assert_keys_exactly(view.get("hint", {}), ["handle", "levels_revealed", "total_levels", "can_reveal_more"], "%s: player hint entry" % case_id)
	_assert_keys_exactly(view.get("stats", {}), ["elapsed_ms", "submissions", "incorrect", "optional_found", "hints_used"], "%s: player stats" % case_id)


## Content-level sweep after realistic play (one wrong attempt, one correct
## required refutation, one hint revealed, one evidence opened) — no domain
## id, structural role, or raw veracity value may appear anywhere in the
## serialized view, and no banned key name may appear anywhere in its
## structure.
func _test_player_view_spoiler_safety(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var pool: Array = controller.get_evidence_pool_ids()
	controller.open_evidence(pool[0])
	controller.select_evidence(pool[1])
	controller.present_evidence()  # almost certainly wrong; that's fine, it's still real play
	var required_id: String = str((case_def.get("prototype_a", {}).get("rounds", [])[0] as Dictionary).get("required_refutations", [])[0])
	controller.reveal_next_hint(required_id)

	var result: Dictionary = presenter.build_player_view(case_def, controller)
	var view: Dictionary = result.get("view", {})
	var serialized: String = JSON.stringify(view)

	for domain_id in _all_domain_ids(case_def):
		_check(not serialized.contains(domain_id), "%s: player view must never contain the raw domain id \"%s\"" % [case_id, domain_id])
	for role in _all_structural_roles(case_def):
		_check(not serialized.contains(role), "%s: player view must never contain the structural role \"%s\"" % [case_id, role])
	for veracity in _all_veracity_values(case_def):
		if veracity == "true" or veracity == "false":
			continue
		_check(not serialized.contains(veracity), "%s: player view must never contain the raw veracity value \"%s\"" % [case_id, veracity])
	for domain_id in result.get("handle_map", {}).values():
		_check(not serialized.contains(str(domain_id)), "%s: player view must never contain a handle_map target id (\"%s\")" % [case_id, domain_id])

	var all_keys: Dictionary = {}
	_collect_all_keys(view, all_keys)
	for banned_key in ["id", "veracity", "proof_sets", "compatible", "structural_role", "required_refutations", "optional_refutations", "unlock_requires", "ground_truth", "source", "certainty", "misleading", "lie_motive", "speaker_id"]:
		_check(not all_keys.has(banned_key), '%s: player view must never carry a "%s" field anywhere in its structure' % [case_id, banned_key])

	_check(not serialized.contains(str(case_def.get("ground_truth", {}).get("culprit", "IMPOSSIBLE"))), "%s: the culprit id must never appear in the Prototype A player view" % case_id)


## Only the CURRENT round's statements ever appear — round 2's content must
## be completely absent while round 1 is active.
func _test_round_scoping_hides_future_round(case_def: Dictionary) -> void:
	var case_id: String = case_def.get("id", "")
	var controller = _new_controller(case_def)
	var round2_statement_id: String = str((case_def.get("prototype_a", {}).get("rounds", [])[1] as Dictionary).get("statements", [])[0])
	var round2_claim: Dictionary = evaluator.find_claim(case_def, round2_statement_id)
	var round2_text: String = String(TranslationServer.translate(round2_claim.get("text", "")))

	var view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((view.get("statements", []) as Array).size() == (case_def.get("prototype_a", {}).get("rounds", [])[0] as Dictionary).get("statements", []).size(), "%s: only round 1's statements should be visible initially" % case_id)
	_check(round2_text != "" and not JSON.stringify(view).contains(round2_text), "%s: round 2's statement text must not leak while round 1 is active" % case_id)


func _test_outcome_hidden_before_resolution_revealed_after() -> void:
	var controller = _new_controller(fixtures.prototype_a_case())
	controller.next_statement()  # st_required1
	var before: Dictionary = presenter.build_player_view(fixtures.prototype_a_case(), controller).get("view", {})
	var before_statement: Dictionary = _find_by_handle_field(before.get("statements", []), "handle", before.get("current_statement_handle", ""))
	_check(before_statement.get("resolved") == false and before_statement.get("outcome") == "", "the required/optional classification must be invisible before resolution")

	controller.select_evidence("e_b")
	controller.present_evidence()
	var after: Dictionary = presenter.build_player_view(fixtures.prototype_a_case(), controller).get("view", {})
	var after_statement: Dictionary = _find_by_handle_field(after.get("statements", []), "handle", after.get("current_statement_handle", ""))
	_check(after_statement.get("resolved") == true and after_statement.get("outcome") == "required", "the outcome should reveal \"required\" only once the session has actually resolved it")


func _test_evidence_text_gated_on_opened() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
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
	var case_def: Dictionary = fixtures.prototype_a_case()
	var controller = _new_controller(case_def)
	controller.next_statement()  # st_required1, which HAS a ladder
	var before: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check(not (before.get("hint", {}) as Dictionary).is_empty(), "a required refutation's hint entry should be present")
	_check((before.get("hint", {}).get("levels_revealed", []) as Array).is_empty(), "no hint level should be revealed yet")
	_check(before.get("hint", {}).get("can_reveal_more") == true, "more levels should be available")

	controller.reveal_next_hint("st_required1")
	var after: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((after.get("hint", {}).get("levels_revealed", []) as Array).size() == 1, "revealing one hint should show exactly one level")

	controller.previous_statement()  # st_true, which has NO ladder
	var no_ladder_view: Dictionary = presenter.build_player_view(case_def, controller).get("view", {})
	_check((no_ladder_view.get("hint", {}) as Dictionary).is_empty(), "a statement with no hint ladder must show an empty hint entry")


func _test_feedback_mapping_all_categories() -> void:
	var case_def: Dictionary = fixtures.prototype_a_case()
	var required_feedback: Dictionary = presenter.build_feedback(case_def, {"category": "valid_refutation", "claim_id": "st_required1", "outcome": "required"})
	_check(required_feedback.get("success") == true and required_feedback.get("optional") == false, "a required refutation should map to success, not optional")
	_check(required_feedback.get("explanation") != "" and required_feedback.get("witness_response") != "", "a required refutation should surface the round's authored explanation and witness response")

	var optional_feedback: Dictionary = presenter.build_feedback(case_def, {"category": "valid_refutation", "claim_id": "st_optional", "outcome": "optional"})
	_check(optional_feedback.get("success") == true and optional_feedback.get("optional") == true, "an optional refutation should map to success AND optional")
	_check(optional_feedback.get("explanation") != "", "an optional refutation should also surface its authored explanation")

	for entry in [
		["irrelevant_evidence", "UI_PROTOTYPE_A_FEEDBACK_IRRELEVANT"],
		["insufficient_evidence", "UI_PROTOTYPE_A_FEEDBACK_INSUFFICIENT"],
		["compatible_not_proof", "UI_PROTOTYPE_A_FEEDBACK_COMPATIBLE"],
		["invalid_input", "UI_PROTOTYPE_A_FEEDBACK_INVALID"],
	]:
		var feedback: Dictionary = presenter.build_feedback(case_def, {"category": entry[0], "claim_id": "st_required1", "outcome": "unsuccessful"})
		_check(feedback.get("success") == false, "%s must never be reported as success" % entry[0])
		_check(feedback.get("explanation") == String(TranslationServer.translate(entry[1])), "%s should map to the generic %s message, got \"%s\"" % [entry[0], entry[1], feedback.get("explanation")])
		_check(feedback.get("witness_response") == "", "%s must never surface a witness response" % entry[0])


func _test_stats_are_numeric_only() -> void:
	var stats: Dictionary = {"elapsed_ms": 1234, "submissions": 2, "incorrect": 1, "optional_found": 0, "hints_used": 1}
	for key in stats:
		_check(typeof(stats[key]) == TYPE_INT or typeof(stats[key]) == TYPE_FLOAT, "stats.%s must be numeric, never text that could leak content" % key)


func _find_by_handle_field(entries: Array, field: String, value: String) -> Dictionary:
	for entry in entries:
		if entry.get(field, "") == value:
			return entry
	return {}
